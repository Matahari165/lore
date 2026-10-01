import SwiftUI

/// IA globale de bibliothèque : bilan et recommandations à partir des livres
/// lus, de leurs notes, dates et temps de lecture.
///
/// Confidentialité : le contexte est assemblé localement depuis SwiftData et
/// n'est envoyé à OpenAI (`gpt-5.6-luna`, `store: false`) qu'après une question
/// explicite. Seules des métadonnées et de courts extraits déjà surlignés
/// partent ; le texte complet des EPUB ne quitte jamais l'appareil.
@MainActor
struct LibraryAIDiscussionView: View {
    private let makeContext: @MainActor ([LoreAIChatMessage], String) throws -> LoreAILibraryContext
    private let aiService: any LoreAILibraryService
    private let onOpenSettings: (() -> Void)?
    private let initialSummary: LibraryAISummary

    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    @State private var messages: [LoreAIChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var failedQuestion: String?

    struct LibraryAISummary: Equatable {
        let totalBooks: Int
        let finishedCount: Int
        let inProgressCount: Int
        let ratedCount: Int
    }

    init(
        summary: LibraryAISummary,
        makeContext: @escaping @MainActor ([LoreAIChatMessage], String) throws -> LoreAILibraryContext,
        aiService: any LoreAILibraryService = OpenAIResponsesClient(),
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.initialSummary = summary
        self.makeContext = makeContext
        self.aiService = aiService
        self.onOpenSettings = onOpenSettings
    }

    /// Construction depuis le view-model : le résumé affiché vient des mêmes
    /// entrées valeur que le contexte envoyé.
    init(
        model: LibraryViewModel,
        aiService: any LoreAILibraryService = OpenAIResponsesClient(),
        onOpenSettings: (() -> Void)? = nil
    ) {
        let inputs = (try? model.libraryAIBookInputs()) ?? []
        let summary = LibraryAISummary(
            totalBooks: inputs.count,
            finishedCount: inputs.filter { $0.status == "terminé" }.count,
            inProgressCount: inputs.filter { $0.status == "en cours" }.count,
            ratedCount: inputs.filter { $0.rating != nil }.count
        )
        self.init(
            summary: summary,
            makeContext: { history, question in
                try model.makeLibraryAIContext(question: question, history: history)
            },
            aiService: aiService,
            onOpenSettings: onOpenSettings
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contextHeader
                        if messages.isEmpty { welcome } else { conversation }
                        if let errorMessage { errorBanner(errorMessage) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LoreTheme.pageMargin)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(LoreTheme.canvas)
                .onChange(of: messages.count) { _, _ in
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("library-ai-end", anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("IA Bibliothèque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .loreCanvas()
    }

    private var contextHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "books.vertical")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contexte bibliothèque : \(scopeTitle). \(scopeDescription)")
    }

    private var scopeTitle: String {
        if initialSummary.totalBooks == 0 { return "Bibliothèque vide" }
        return "\(initialSummary.totalBooks) livres · \(initialSummary.finishedCount) terminés"
    }

    private var scopeDescription: String {
        "Basé sur vos titres, auteurs, notes sur 10, dates et temps de lecture, plus vos surlignages et notes. Le texte complet des livres n'est jamais envoyé. Aucun envoi sans votre question."
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Que voulez-vous explorer ?")
                    .font(.title2.weight(.semibold))
                Text(welcomeDescription)
                    .font(.body)
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            quickActions
        }
    }

    private var welcomeDescription: String {
        if initialSummary.totalBooks == 0 {
            return "Importez des livres pour obtenir des recommandations fondées sur vos lectures."
        }
        return "Demandez des recommandations basées sur vos lectures passées, ou un bilan de ce que vous avez aimé."
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 8) {
                    if message.role == .user { Spacer(minLength: 36) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role == .user ? "Vous" : "Lore")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LoreTheme.secondaryInk)
                            .accessibilityHidden(true)
                        if message.role == .assistant {
                            LibraryAIMarkdownText(markdown: message.text)
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
            Color.clear.frame(height: 1).id("library-ai-end")
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pour commencer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreTheme.secondaryInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickAction("Recommande des livres", systemImage: "sparkles") {
                        send("Recommande-moi 3 livres à découvrir en fonction de mes lectures terminées et de mes notes. Explique pour chacun le lien avec ce que j'ai aimé.")
                    }
                    quickAction("Bilan de mes goûts", systemImage: "chart.bar") {
                        send("À partir de mes livres terminés, notes et temps de lecture, décris mes goûts dominants et ce que j'ai moins aimé.")
                    }
                    quickAction("Que lire ensuite ?", systemImage: "book") {
                        send("Parmi mes livres en cours et à lire, lequel me conseilles-tu en priorité et pourquoi ?")
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
        .disabled(isLoading || initialSummary.totalBooks == 0)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ex : recommande-moi un livre…", text: $draft, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        LoreTheme.canvas.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LoreTheme.hairline, lineWidth: 0.5)
                    }
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .accessibilityLabel("Question bibliothèque")
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
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(message, systemImage: "exclamationmark.circle")
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
                if let onOpenSettings, message.localizedCaseInsensitiveContains("clé API") {
                    Button("Réglages", action: onOpenSettings)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(LoreTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
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
        failedQuestion = nil
        errorMessage = nil
        isLoading = true
        let previousMessages = messages
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let context = try makeContext(previousMessages, value)
                let answer = try await aiService.libraryChat(context)
                messages.append(LoreAIChatMessage(role: .user, text: value))
                messages.append(LoreAIChatMessage(role: .assistant, text: answer))
            } catch is CancellationError {
                failedQuestion = value
            } catch {
                failedQuestion = value
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "La réponse est indisponible pour le moment."
            }
        }
    }
}

private struct LibraryAIMarkdownText: View {
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
