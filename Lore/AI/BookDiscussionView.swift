import SwiftUI

/// Conversation principale de Lore. La vue est volontairement la même avant,
/// pendant et après la lecture : seule la portée affichée et envoyée change.
@MainActor
struct BookDiscussionView: View {
    private let bookID: UUID
    private let title: String
    private let author: String?
    private let stage: LoreAIReadingStage
    private let initialProgression: Double?
    private let conversationRepository: AIConversationRepository?
    private let session: ReaderSessionController?
    private let aiService: any LoreAIChatService
    private let localContextLoader: LocalBookAIContextLoader?
    private let initialExcerpt: LoreAIChatExcerpt?
    private let onOpenSettings: (() -> Void)?
    private let onOpenSource: ((LoreAIChatSource) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var inputFocused: Bool

    @State private var messages: [LoreAIChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var pendingQuestion: String?
    @State private var failedQuestion: String?
    @State private var errorMessage: String?
    @State private var scopeWarning: String?
    @State private var contextCharacters = 0
    @State private var isPreparingContext = false
    @State private var contextLoadError: String?
    @State private var didLoadHistory = false
    @State private var confirmsDeletion = false
    @State private var activeConversationID: UUID?
    @State private var conversations: [DiscussionSummary] = []

    init(
        book: BookRecord,
        conversationRepository: AIConversationRepository?,
        session: ReaderSessionController? = nil,
        onOpenSettings: (() -> Void)? = nil,
        aiService: any LoreAIChatService = OpenAIResponsesClient(),
        initialDraft: String? = nil,
        initialHighlight: ReaderHighlight? = nil,
        onOpenSource: ((LoreAIChatSource) -> Void)? = nil
    ) {
        let localContextLoader = LocalBookAIContextLoader.makeDefault(book: book)
        self.init(
            bookID: book.id,
            title: book.title,
            author: book.author,
            stage: book.readingStatus.loreAIStage,
            initialProgression: book.lastProgression,
            conversationRepository: conversationRepository,
            session: session,
            onOpenSettings: onOpenSettings,
            aiService: aiService,
            initialDraft: initialDraft,
            initialExcerpt: Self.chatExcerpt(bookID: book.id, highlight: initialHighlight),
            localContextLoader: localContextLoader,
            onOpenSource: onOpenSource
        )
    }

    init(
        bookID: UUID,
        title: String,
        author: String? = nil,
        stage: LoreAIReadingStage,
        initialProgression: Double? = nil,
        conversationRepository: AIConversationRepository?,
        session: ReaderSessionController? = nil,
        onOpenSettings: (() -> Void)? = nil,
        aiService: any LoreAIChatService = OpenAIResponsesClient(),
        initialDraft: String? = nil,
        initialExcerpt: LoreAIChatExcerpt? = nil,
        localContextLoader: LocalBookAIContextLoader? = nil,
        onOpenSource: ((LoreAIChatSource) -> Void)? = nil
    ) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.stage = stage
        self.initialProgression = initialProgression
        self.conversationRepository = conversationRepository
        self.session = session
        self.onOpenSettings = onOpenSettings
        self.aiService = aiService
        self.localContextLoader = localContextLoader
        self.initialExcerpt = initialExcerpt
        self.onOpenSource = onOpenSource
        _draft = State(initialValue: initialDraft ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contextHeader

                        if let scopeWarning {
                            Label(scopeWarning, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(LoreTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                        }

                        if isPreparingContext {
                            Label("Lecture locale en cours…", systemImage: "book.pages")
                                .font(.caption)
                                .foregroundStyle(LoreTheme.secondaryInk)
                                .accessibilityElement(children: .combine)
                        }

                        if messages.isEmpty {
                            welcome
                        } else {
                            conversation
                        }

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LoreTheme.pageMargin)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
                .background(LoreTheme.canvas)
                .onChange(of: messages.count) { _, _ in
                    scrollToLatest(using: proxy)
                }
                .onChange(of: pendingQuestion) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nouvelle discussion", systemImage: "plus") {
                        startNewConversation()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(isLoading)
                    .accessibilityLabel("Nouvelle discussion")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !conversations.isEmpty {
                            Section("Discussions") {
                                ForEach(conversations) { conversation in
                                    Button {
                                        selectConversation(conversation.id)
                                    } label: {
                                        Label(
                                            conversation.label,
                                            systemImage: conversation.id == activeConversationID
                                                ? "checkmark.bubble"
                                                : "bubble.left"
                                        )
                                    }
                                    .disabled(conversation.id == activeConversationID || isLoading)
                                }
                            }
                        }
                        if let onOpenSettings {
                            Button("Ouvrir les réglages", systemImage: "gearshape", action: onOpenSettings)
                        }
                        if !messages.isEmpty {
                            Button("Effacer la discussion", systemImage: "trash", role: .destructive) {
                                confirmsDeletion = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Options de la discussion")
                }
            }
        }
        .loreCanvas()
        .task(id: bookID) {
            loadHistory()
            await prepareLocalContext()
        }
        .confirmationDialog(
            "Effacer cette discussion ?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Effacer", role: .destructive) { deleteHistory() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette discussion locale sera supprimée.")
        }
    }

    private var contextHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stage == .finished ? "book.closed" : "lock.shield")
                .font(.headline)
                .foregroundStyle(LoreTheme.ink)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(scopeTitle)
                    .font(.subheadline.weight(.semibold))
                Text(scopeDescription)
                    .font(.caption)
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LoreTheme.hairline.opacity(0.7))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contexte de lecture : \(scopeTitle). \(scopeDescription)")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discuter de \(title)")
                    .font(.title2.weight(.semibold))
                Text(welcomeDescription)
                    .font(.body)
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            quickActions
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                messageBubble(message)
            }

            if let pendingQuestion {
                messageBubble(LoreAIChatMessage(role: .user, text: pendingQuestion))
                    .opacity(0.62)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lore prépare une réponse…")
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.secondaryInk)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Réponse en cours")
            }

            Color.clear.frame(height: 1).id("discussion-end")
        }
    }

    private func messageBubble(_ message: LoreAIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "Vous" : "Lore")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .accessibilityHidden(true)

                if message.role == .assistant {
                    DiscussionMarkdownText(markdown: message.text)
                    if !message.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Passages cités")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LoreTheme.secondaryInk)
                            ForEach(message.sources) { source in
                                Button {
                                    onOpenSource?(source)
                                } label: {
                                    Label(source.label, systemImage: "book.pages")
                                        .font(.subheadline)
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(onOpenSource == nil)
                                .accessibilityLabel("Passage cité : \(source.label)")
                                .accessibilityHint("Revient au passage cité dans le livre")
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    if !message.sources.isEmpty, onOpenSource == nil {
                        Text("Retour au passage indisponible depuis cet écran.")
                            .font(.caption)
                            .foregroundStyle(LoreTheme.secondaryInk)
                    }
                } else {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, message.role == .user ? 12 : 0)
            .padding(.vertical, message.role == .user ? 9 : 2)
            .background(
                message.role == .user
                    ? LoreTheme.ink.opacity(0.10)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            if message.role == .assistant { Spacer(minLength: 12) }
        }
        .accessibilityElement(children: message.sources.isEmpty ? .combine : .contain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pour commencer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreTheme.secondaryInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickAction("Résumer le chapitre", systemImage: "text.alignleft") {
                        send("Résume le chapitre disponible en quelques idées, sans dépasser ma progression de lecture.")
                    }
                    quickAction("Question libre", systemImage: "questionmark") {
                        inputFocused = true
                    }
                    if stage == .finished {
                        quickAction("Discuter de la fin", systemImage: "flag.checkered") {
                            send("Je viens de terminer ce livre. Aide-moi à discuter de sa fin à partir du contexte disponible.")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func quickAction(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LoreTheme.ink)
        .background(LoreTheme.ink.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
        .accessibilityHint(label == "Question libre" ? "Ouvre le champ de question" : "Envoie cette demande à Lore")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Posez votre question…", text: $draft, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        reduceTransparency
                            ? Color(uiColor: .secondarySystemBackground)
                            : LoreTheme.canvas.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LoreTheme.hairline, lineWidth: 0.5)
                    }
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .accessibilityLabel("Question")

                Button("Envoyer", systemImage: "arrow.up.circle.fill") { send() }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .foregroundStyle(LoreTheme.ink)
                    .disabled(isLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Envoyer la question")
            }
        }
        .padding(.horizontal, LoreTheme.pageMargin)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(LoreTheme.hairline.opacity(0.55)).frame(height: 0.5)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(message, systemImage: errorIcon)
                .font(.subheadline)
                .foregroundStyle(LoreTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let failedQuestion {
                    Button("Réessayer") { send(failedQuestion) }
                        .buttonStyle(.borderedProminent)
                        .tint(LoreTheme.ink)
                        .foregroundStyle(LoreTheme.canvas)
                }
                if let onOpenSettings, isMissingKey {
                    Button("Réglages", action: onOpenSettings)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(LoreTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var errorIcon: String {
        isMissingKey ? "key.fill" : (isOffline ? "wifi.exclamationmark" : "exclamationmark.circle")
    }

    private var isMissingKey: Bool {
        errorMessage?.localizedCaseInsensitiveContains("clé API") == true
    }

    private var isOffline: Bool {
        errorMessage?.localizedCaseInsensitiveContains("connexion") == true
            || errorMessage?.localizedCaseInsensitiveContains("réseau") == true
    }

    private var scopeTitle: String {
        switch stage {
        case .notStarted: "Avant lecture"
        case .inProgress: "Jusqu’à votre progression"
        case .finished: "Livre terminé"
        }
    }

    private var scopeDescription: String {
        switch stage {
        case .notStarted:
            "Aucun texte n’est envoyé avant votre première lecture."
        case .inProgress:
            if let contextLoadError { contextLoadError }
            else if let initialProgression {
                "Contexte limité à votre progression (\(initialProgression.formatted(.percent.precision(.fractionLength(0))))) ; aucun passage futur."
            } else {
                "Contexte limité à votre progression de lecture ; aucun passage futur."
            }
        case .finished:
            if let contextLoadError { contextLoadError }
            else { "Le texte local du livre est disponible pour discuter de votre lecture." }
        }
    }

    private var welcomeDescription: String {
        switch stage {
        case .notStarted:
            "Préparez votre lecture, clarifiez vos attentes ou dites-moi ce que vous aimeriez observer."
        case .inProgress:
            "Posez une question sur ce que vous avez lu. Lore respecte votre progression pour éviter les spoilers."
        case .finished:
            "Revenez sur votre lecture, ses idées et sa fin. La conversation reste attachée à ce livre."
        }
    }

    private func loadHistory() {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        guard let conversationRepository else { return }
        do {
            let records = try conversationRepository.conversations(for: bookID)
            conversations = records.map(DiscussionSummary.init)
            guard let record = records.first else { return }
            activeConversationID = record.id
            messages = try conversationRepository.history(
                for: bookID,
                conversationID: record.id,
                maximumFrontierProgression: currentHistoryFrontier,
                readingStage: stage
            )
        } catch {
            errorMessage = "L’historique local est indisponible pour le moment."
        }
    }

    private var currentHistoryFrontier: Double? {
        guard stage != .finished else { return nil }
        if let session { return session.chatFrontierProgression }
        return initialProgression
    }

    private func selectConversation(_ id: UUID) {
        guard !isLoading, id != activeConversationID, let conversationRepository else { return }
        do {
            messages = try conversationRepository.history(
                for: bookID,
                conversationID: id,
                maximumFrontierProgression: currentHistoryFrontier,
                readingStage: stage
            )
            activeConversationID = id
            errorMessage = nil
            failedQuestion = nil
            scopeWarning = nil
        } catch {
            errorMessage = "Cette discussion n’a pas pu être ouverte."
        }
    }

    private func startNewConversation() {
        guard !isLoading else { return }
        activeConversationID = nil
        messages = []
        draft = ""
        pendingQuestion = nil
        failedQuestion = nil
        errorMessage = nil
        scopeWarning = nil
        inputFocused = true
    }

    private func prepareLocalContext() async {
        guard session == nil, let localContextLoader else { return }
        isPreparingContext = true
        defer { isPreparingContext = false }
        do {
            let snapshot = try await localContextLoader.snapshot(for: nil)
            contextCharacters = snapshot.excerpts.reduce(0) { $0 + $1.text.count }
            contextLoadError = snapshot.isAvailable ? nil : snapshot.unavailableMessage
        } catch {
            contextLoadError = (error as? LocalizedError)?.errorDescription
                ?? "Le contexte local n’a pas pu être chargé."
        }
    }

    private func send(_ requestedQuestion: String? = nil) {
        guard !isLoading else { return }
        let value = (requestedQuestion ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            inputFocused = true
            return
        }

        draft = ""
        inputFocused = false
        pendingQuestion = value
        failedQuestion = nil
        errorMessage = nil
        scopeWarning = nil
        isLoading = true

        let previousMessages = messages
        Task { @MainActor in
            defer {
                isLoading = false
                pendingQuestion = nil
            }

            do {
                let context = await makeContext(question: value, history: previousMessages)
                contextCharacters = context.excerpts.reduce(0) { $0 + $1.text.count }
                if stage != .notStarted, context.excerpts.isEmpty {
                    let answer = insufficientContextMessage(
                        for: context.summaryScope,
                        loaderMessage: contextLoadError
                    )
                    if let conversationRepository {
                        let record = try conversationRepository.appendTurn(
                            bookID: bookID,
                            conversationID: activeConversationID,
                            question: value,
                            answer: answer,
                            readingStage: stage,
                            frontierProgression: context.readFrontierProgression,
                            frontierDescription: context.readFrontierDescription,
                            fullBookAccessGranted: context.fullBookAccessGranted
                        )
                        activeConversationID = record.id
                        refreshConversations()
                    }
                    messages.append(LoreAIChatMessage(role: .user, text: value))
                    messages.append(LoreAIChatMessage(role: .assistant, text: answer))
                    scopeWarning = "Aucun texte du livre n’a été envoyé pour cette réponse."
                    return
                }
                let response = try await aiService.chat(context)
                if let conversationRepository {
                    let record = try conversationRepository.appendTurn(
                        bookID: bookID,
                        conversationID: activeConversationID,
                        question: value,
                        answer: response.text,
                        sources: response.sources,
                        readingStage: stage,
                        frontierProgression: context.readFrontierProgression,
                        frontierDescription: context.readFrontierDescription,
                        fullBookAccessGranted: context.fullBookAccessGranted
                    )
                    activeConversationID = record.id
                    refreshConversations()
                }
                messages.append(LoreAIChatMessage(role: .user, text: value))
                messages.append(LoreAIChatMessage(role: .assistant, text: response.text, sources: response.sources))
            } catch is CancellationError {
                failedQuestion = value
            } catch {
                failedQuestion = value
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "La réponse est indisponible pour le moment."
            }
        }
    }

    private func makeContext(
        question: String,
        history: [LoreAIChatMessage]
    ) async -> LoreAIChatContext {
        if let session, let context = await session.chatContext(
            stage: stage,
            question: question,
            history: history
        ) {
            return addingInitialExcerpt(to: context)
        }

        let summaryScope = LoreAISummaryIntentRouter().route(question)
        if let localContextLoader {
            do {
                let snapshot = try await localContextLoader.snapshot(for: summaryScope)
                contextCharacters = snapshot.excerpts.reduce(0) { $0 + $1.text.count }
                contextLoadError = snapshot.isAvailable ? nil : snapshot.unavailableMessage
                return addingInitialExcerpt(to: snapshot.chatContext(
                    summaryScope: summaryScope,
                    question: question,
                    history: history
                ))
            } catch {
                contextLoadError = (error as? LocalizedError)?.errorDescription
                    ?? "Le contexte local n’a pas pu être chargé."
            }
        }

        return addingInitialExcerpt(to: LoreAIChatContext(
            bookID: bookID,
            title: title,
            author: author,
            stage: stage,
            readFrontierProgression: initialProgression,
            readFrontierDescription: initialProgression.map {
                "Progression connue : \($0.formatted(.percent.precision(.fractionLength(0))))"
            },
            summaryScope: summaryScope,
            history: history,
            question: question
        ))
    }

    private func addingInitialExcerpt(to context: LoreAIChatContext) -> LoreAIChatContext {
        guard let initialExcerpt,
              let progression = initialExcerpt.progression,
              context.fullBookAccessGranted
                || context.readFrontierProgression.map({ progression <= $0 + 0.000_001 }) == true,
              !context.excerpts.contains(where: { $0.source?.id == initialExcerpt.source?.id })
        else { return context }

        return LoreAIChatContext(
            bookID: context.bookID,
            title: context.title,
            author: context.author,
            stage: context.stage,
            chapterTitle: context.chapterTitle,
            readFrontierProgression: context.readFrontierProgression,
            readFrontierDescription: context.readFrontierDescription,
            excerpts: [initialExcerpt] + context.excerpts,
            fullBookAccessGranted: context.fullBookAccessGranted,
            summaryScope: context.summaryScope,
            history: context.history,
            question: context.question
        )
    }

    private func refreshConversations() {
        guard let conversationRepository,
              let records = try? conversationRepository.conversations(for: bookID)
        else { return }
        conversations = records.map(DiscussionSummary.init)
    }

    private func insufficientContextMessage(
        for scope: LoreAISummaryScope?,
        loaderMessage: String?
    ) -> String {
        let message: String
        if let loaderMessage {
            message = loaderMessage
        } else {
            message = switch scope {
            case .currentChapter:
                "Le chapitre correspondant à la position sauvegardée n’est pas disponible depuis cet écran."
            case .yesterday:
                "Les bornes locales de la lecture d’hier ne sont pas disponibles depuis cet écran."
            case .sinceLastSession:
                "Les positions de début et de fin de cette session ne sont pas disponibles."
            case nil:
                "Le texte lu n’a pas pu être chargé jusqu’à la position sauvegardée."
            }
        }
        return LoreAIResponseFormatter.bulleted(
            "\(message)\nIdée essentielle : aucun texte futur n’a été envoyé."
        )
    }

    private func deleteHistory() {
        do {
            if let activeConversationID {
                try conversationRepository?.deleteConversation(id: activeConversationID, for: bookID)
                conversations.removeAll { $0.id == activeConversationID }
            }
            messages = []
            activeConversationID = nil
            errorMessage = nil
            failedQuestion = nil
        } catch {
            errorMessage = "La discussion n’a pas pu être supprimée."
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo("discussion-end", anchor: .bottom)
            }
        }
    }

    private static func chatExcerpt(
        bookID: UUID,
        highlight: ReaderHighlight?
    ) -> LoreAIChatExcerpt? {
        guard let highlight,
              highlight.bookID == bookID,
              let progression = highlight.locator.locations.totalProgression,
              let text = highlight.text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              let locatorJSON = try? highlight.locator.jsonData()
        else { return nil }

        let source = LoreAIChatSource(
            id: "highlight-\(highlight.id.uuidString)",
            bookID: bookID,
            label: "Passage surligné",
            locatorJSON: locatorJSON,
            locatorSchemaVersion: LocatorPersistenceCodec.currentSchemaVersion,
            progression: progression
        )
        return LoreAIChatExcerpt(
            text: text,
            sourceDescription: "Passage surligné",
            progression: progression,
            source: source
        )
    }
}

private struct DiscussionSummary: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date

    init(_ record: AIConversationRecord) {
        id = record.id
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var label: String {
        "Discussion du \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct DiscussionMarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = ReaderMarkdownRenderer.attributedString(from: markdown) {
            Text(attributed)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

extension BookReadingStatus {
    var loreAIStage: LoreAIReadingStage {
        switch self {
        case .toRead: .notStarted
        case .inProgress: .inProgress
        case .finished: .finished
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
