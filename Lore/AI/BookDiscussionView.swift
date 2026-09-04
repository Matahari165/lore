import SwiftUI

/// Conversation principale de Lore. La vue est volontairement la même avant,
/// pendant et après la lecture : seule la portée affichée et envoyée change.
struct BookDiscussionView: View {
    private let bookID: UUID
    private let title: String
    private let author: String?
    private let stage: LoreAIReadingStage
    private let initialProgression: Double?
    private let conversationRepository: AIConversationRepository?
    private let session: ReaderSessionController?
    private let aiService: any LoreAIChatService
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
    @State private var didLoadHistory = false
    @State private var confirmsDeletion = false

    init(
        book: BookRecord,
        conversationRepository: AIConversationRepository?,
        session: ReaderSessionController? = nil,
        onOpenSettings: (() -> Void)? = nil,
        aiService: any LoreAIChatService = OpenAIResponsesClient(),
        initialDraft: String? = nil,
        onOpenSource: ((LoreAIChatSource) -> Void)? = nil
    ) {
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
        self.onOpenSource = onOpenSource
        _draft = State(initialValue: initialDraft ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        scopeBanner

                        if let scopeWarning {
                            Label(scopeWarning, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(LoreTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
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
            .navigationTitle("Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
        .task(id: bookID) { loadHistory() }
        .confirmationDialog(
            "Effacer cette discussion ?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Effacer", role: .destructive) { deleteHistory() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les questions et réponses locales de ce livre seront supprimées.")
        }
    }

    private var scopeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stage == .finished ? "checkmark.circle" : "lock.shield")
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            reduceTransparency
                ? Color(uiColor: .secondarySystemBackground)
                : LoreTheme.ink.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LoreTheme.hairline.opacity(0.7), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Portée de la discussion : \(scopeTitle). \(scopeDescription)")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(LoreTheme.ink)
                    .accessibilityHidden(true)
                Text("Parlez à \(title)")
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                message.role == .user
                    ? LoreTheme.ink.opacity(0.10)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if message.role == .assistant {
                    Capsule()
                        .fill(Color(red: 0.0, green: 0.72, blue: 0.82))
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }

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
                .frame(minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(LoreTheme.ink)
        .accessibilityHint("Envoie cette demande à Lore")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if messages.isEmpty == false && stage != .notStarted {
                quickActions
            }

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
            if contextCharacters > 0 {
                "\(contextCharacters.formatted()) caractères de texte local sont disponibles pour ce tour."
            } else {
                "Le texte envoyé reste limité aux passages déjà lus, jamais à la suite."
            }
        case .finished:
            "L’analyse complète n’est pas encore raccordée : seuls les extraits disponibles sont utilisés pour l’instant."
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
            messages = try conversationRepository.history(for: bookID)
        } catch {
            errorMessage = "L’historique local est indisponible pour le moment."
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
                if let summaryScope = context.summaryScope, context.excerpts.isEmpty {
                    let answer = insufficientContextMessage(for: summaryScope)
                    if let conversationRepository {
                        _ = try conversationRepository.appendTurn(
                            bookID: bookID,
                            question: value,
                            answer: answer,
                            frontierProgression: context.readFrontierProgression,
                            frontierDescription: context.readFrontierDescription
                        )
                    }
                    messages.append(LoreAIChatMessage(role: .user, text: value))
                    messages.append(LoreAIChatMessage(role: .assistant, text: answer))
                    scopeWarning = "Aucun texte du livre n’a été envoyé pour cette réponse."
                    return
                }
                if stage != .notStarted, context.excerpts.isEmpty {
                    scopeWarning = "Aucun extrait n’est disponible pour ce tour. Lore indiquera quand le texte ne suffit pas."
                }
                let response = try await aiService.chat(context)
                if let conversationRepository {
                    _ = try conversationRepository.appendTurn(
                        bookID: bookID,
                        question: value,
                        answer: response.text,
                        sources: response.sources,
                        readingStage: stage,
                        frontierProgression: context.readFrontierProgression,
                        frontierDescription: context.readFrontierDescription
                    )
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
            return context
        }

        return LoreAIChatContext(
            bookID: bookID,
            title: title,
            author: author,
            stage: stage,
            readFrontierProgression: initialProgression,
            readFrontierDescription: initialProgression.map {
                "Progression connue : \($0.formatted(.percent.precision(.fractionLength(0))))"
            },
            summaryScope: LoreAISummaryIntentRouter().route(question),
            history: history,
            question: question
        )
    }

    private func insufficientContextMessage(for scope: LoreAISummaryScope) -> String {
        switch scope {
        case .currentChapter:
            "Je n’ai pas accès au chapitre ouvert depuis cet écran. Ouvrez la discussion depuis le lecteur pour le résumer sans dépasser votre progression."
        case .yesterday:
            "Je n’ai pas de bornes de lecture locales suffisantes pour résumer hier sans risquer d’inclure un autre passage."
        case .sinceLastSession:
            "Lore ne conserve pas encore les positions de début et de fin de chaque session. Je ne peux donc pas résumer cette session précisément sans approximation."
        }
    }

    private func deleteHistory() {
        do {
            try conversationRepository?.deleteConversation(for: bookID)
            messages = []
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
