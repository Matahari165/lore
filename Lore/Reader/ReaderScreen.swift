import Foundation
import SwiftUI

struct ReaderScreen: View {
    let presentation: LibraryViewModel.ReaderPresentation
    let onRequestClose: @MainActor () async -> Void
    let onReadingProgress: @MainActor () -> Void

    @State private var showsControls = false
    @State private var showsQuickPreferences = false
    @State private var showsAllPreferences = false
    @State private var presentedPanel: Panel?
    @State private var preferences: ReaderPreferences
    @State private var progression: Double
    @State private var scrubProgression: Double
    @State private var pageNumber: Int?
    @State private var navigationPreview: ReaderNavigationPreview?
    @State private var isScrubbing = false
    @State private var canGoBackAfterJump = false
    @State private var previewTask: Task<Void, Never>?
    @State private var highlights: [ReaderHighlight]
    @State private var vocabulary: [VocabularyItem]
    @State private var aiExplanation: ReaderAIExplanationState?
    @State private var aiRecap: ReaderAIRecapState?
    @State private var showsDiscussion = false
    @State private var citationNavigationError: String?
    @State private var readerPresentationState: ReaderPresentationState = .appearing
    @State private var coverTransitionOpacity: Double = 1.0
    @State private var goalRefreshTask: Task<Void, Never>?
    @Namespace private var glassNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        presentation: LibraryViewModel.ReaderPresentation,
        onRequestClose: @escaping @MainActor () async -> Void,
        onReadingProgress: @escaping @MainActor () -> Void = {}
    ) {
        self.presentation = presentation
        self.onRequestClose = onRequestClose
        self.onReadingProgress = onReadingProgress
        _preferences = State(initialValue: presentation.session.preferences)
        _progression = State(initialValue: presentation.session.currentProgression)
        _scrubProgression = State(initialValue: presentation.session.currentProgression)
        _highlights = State(initialValue: presentation.session.highlights)
        _vocabulary = State(initialValue: presentation.session.vocabulary)
    }

    var body: some View {
        GeometryReader { geometry in
            let cardRect = currentCardRect(in: geometry)
            let cornerRadius = currentCornerRadius()
            let isVisible = readerPresentationState == .visible

            ZStack {
                readerBackground
                    .ignoresSafeArea()
                    .opacity(isVisible ? 1 : 0)

                ReaderView(session: presentation.session)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(isVisible ? 1 : 0)
                    .allowsHitTesting(isVisible)

                if readerPresentationState != .visible || coverTransitionOpacity > 0 {
                    ZStack {
                        LoreTheme.canvas

                        BookCoverView(
                            coverData: presentation.coverData,
                            title: presentation.title,
                            cornerRadius: cornerRadius
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: cardRect.width, height: cardRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(LoreTheme.hairline, lineWidth: 0.5)
                            .opacity(isVisible ? 0 : 1)
                    }
                    .shadow(
                        color: Color.black.opacity(isVisible ? 0 : 0.20),
                        radius: isVisible ? 0 : 12,
                        y: isVisible ? 0 : 6
                    )
                    .position(x: cardRect.midX, y: cardRect.midY)
                    .opacity(coverTransitionOpacity)
                    .allowsHitTesting(false)
                }

                if showsControls && isVisible {
                    controls
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(preferences.appearance == .light ? .light : .dark)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .accessibilityAction(.escape) { closeReader() }
        .interactiveDismissDisabled(true)
        .onAppear {
            ReadingFocusMode.shared.setReaderActive(true)
            presentation.session.setTapHandler {
                animateChrome {
                    showsControls.toggle()
                    if !showsControls { showsQuickPreferences = false }
                }
            }
            presentation.session.setProgressionHandler {
                progression = $0
                if !isScrubbing { scrubProgression = $0 }
                scheduleGoalRefresh()
            }
            presentation.session.setLocationHandler { locator in
                pageNumber = locator?.locations.position
            }
            presentation.session.setNavigationHistoryHandler { canGoBackAfterJump = $0 }
            presentation.session.setHighlightChangeHandler { highlights = $0 }
            presentation.session.setVocabularyChangeHandler { vocabulary = $0 }
            presentation.session.setExplanationHandler { aiExplanation = $0 }
            presentation.session.setRecapHandler { aiRecap = $0 }
            presentation.session.requestDailyRecapIfEligible()
            if let initialHighlight = presentation.initialHighlight {
                Task { _ = await presentation.session.go(to: initialHighlight) }
            }
        }
        .onDisappear {
            ReadingFocusMode.shared.setReaderActive(false)
            presentation.session.setTapHandler(nil)
            presentation.session.setProgressionHandler(nil)
            presentation.session.setLocationHandler(nil)
            presentation.session.setNavigationHistoryHandler(nil)
            presentation.session.setHighlightChangeHandler(nil)
            presentation.session.setVocabularyChangeHandler(nil)
            presentation.session.setExplanationHandler(nil)
            presentation.session.setRecapHandler(nil)
            previewTask?.cancel()
            goalRefreshTask?.cancel()
        }
        .onAppear(perform: animateReaderEntrance)
        .sheet(item: $presentedPanel) { panel in
            switch panel {
            case .chapters:
                ReaderChaptersSheet(chapters: presentation.session.chapters, onSelect: openChapter)
            case .highlights:
                ReaderHighlightsSheet(
                    bookID: presentation.id,
                    bookTitle: presentation.title,
                    author: presentation.author,
                    highlights: highlights,
                    onSelect: openHighlight,
                    onUpdateNote: presentation.session.updateNote,
                    onDelete: presentation.session.deleteHighlight
                )
            case .vocabulary:
                ReaderVocabularySheet(
                    items: vocabulary,
                    currentBookID: presentation.id,
                    onSelect: openVocabularyItem,
                    onDelete: presentation.session.deleteVocabularyItem
                )
            }
        }
        .fullScreenCover(isPresented: $showsAllPreferences) {
            ReaderPreferencesPage(preferences: $preferences, onChange: applyPreferences)
        }
        .sheet(item: $aiExplanation) { state in
            ReaderAIExplanationSheet(state: state) {
                presentation.session.cancelExplanation()
                aiExplanation = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $aiRecap) { state in
            ReaderAIRecapSheet(state: state) {
                presentation.session.cancelDailyRecap()
                aiRecap = nil
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsDiscussion) {
            BookDiscussionView(
                bookID: presentation.id,
                title: presentation.title,
                author: presentation.author,
                stage: presentation.readingStage,
                initialProgression: progression,
                conversationRepository: presentation.conversationRepository,
                session: presentation.session,
                onOpenSource: { source in
                    Task {
                        if await presentation.session.go(to: source) {
                            showsDiscussion = false
                            showsControls = false
                        } else {
                            citationNavigationError = "Le passage cité n’est plus disponible dans ce livre."
                        }
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Passage indisponible", isPresented: Binding(
            get: { citationNavigationError != nil },
            set: { if !$0 { citationNavigationError = nil } }
        )) {
            Button("OK", role: .cancel) { citationNavigationError = nil }
        } message: {
            Text(citationNavigationError ?? "")
        }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)

                    navigationScrubber
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)
                controlButton("Discuter avec le livre", systemImage: "sparkles") {
                    showsDiscussion = true
                }
                controlButton("Fermer le lecteur", systemImage: "xmark") { closeReader() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            .readerGlass(in: RoundedRectangle(cornerRadius: 20), reduceTransparency: reduceTransparency)
            .padding(.horizontal, 16)

            Spacer()

            VStack(spacing: 10) {
                if showsQuickPreferences {
                    ReaderQuickPreferences(
                        preferences: $preferences,
                        reduceTransparency: reduceTransparency,
                        onChange: applyPreferences,
                        onShowAll: {
                            animateChrome { showsQuickPreferences = false }
                            showsAllPreferences = true
                        }
                    )
                    .glassEffectID("reader-quick-preferences", in: glassNamespace)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 4) {
                        if canGoBackAfterJump {
                            controlButton("Retour à la position précédente", systemImage: "arrow.uturn.backward") {
                                goBackAfterJump()
                            }
                            Divider().frame(height: 20)
                        } else {
                            pageLabel
                            Divider().frame(height: 20)
                        }
                        controlButton("Sommaire", systemImage: "list.bullet") { presentedPanel = .chapters }
                        controlButton("Surlignages", systemImage: "highlighter") { presentedPanel = .highlights }
                        controlButton("Vocabulaire", systemImage: "character.book.closed") { presentedPanel = .vocabulary }
                        controlButton("Réglages de lecture", systemImage: "textformat") {
                            animateChrome { showsQuickPreferences.toggle() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 68)
                    .readerGlass(in: Capsule(), reduceTransparency: reduceTransparency, interactive: true)
                }
            }
            .padding(.horizontal, 16)
        }
        .foregroundStyle(.primary)
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 12)
    }

    private var pageLabel: some View {
        Text(pageNumber.map { "Page \($0)" } ?? "Page indisponible")
            .font(.caption.monospacedDigit().weight(.medium))
            .contentTransition(.numericText())
            .lineLimit(1)
            .frame(minWidth: 84, minHeight: 44)
            .accessibilityLabel("Page")
            .accessibilityValue(pageNumber.map(String.init) ?? "indisponible")
    }

    private var navigationScrubber: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                LoreProgressBar(
                    value: scrubProgression,
                    fill: .white,
                    track: .white.opacity(0.22),
                    height: 8
                )
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

                Slider(
                    value: $scrubProgression,
                    in: 0...1,
                    onEditingChanged: scrubberEditingChanged
                )
                .frame(minHeight: 44)
                .tint(.clear)
                .accessibilityLabel("Position dans le livre")
                .accessibilityValue(Text(scrubProgression, format: .percent.precision(.fractionLength(0))))
                .accessibilityHint("Ajustez puis relâchez pour aller à cette position")
            }
            .frame(minHeight: 44)

            if isScrubbing {
                Text(navigationPreviewText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Aperçu du chapitre")
                    .accessibilityValue(navigationPreview?.chapterTitle ?? "Indisponible")
            }
        }
        .onChange(of: scrubProgression) { _, newValue in
            guard isScrubbing else { return }
            requestNavigationPreview(at: newValue)
        }
    }

    private var navigationPreviewText: String {
        guard let navigationPreview else { return "Recherche du chapitre…" }
        guard navigationPreview.isAvailable else { return "Navigation indisponible" }
        return navigationPreview.chapterTitle ?? "Chapitre sans titre"
    }

    private func scrubberEditingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            requestNavigationPreview(at: scrubProgression)
        } else {
            previewTask?.cancel()
            navigationPreview = nil
            let destination = scrubProgression
            Task {
                if !(await presentation.session.go(toProgression: destination)) {
                    scrubProgression = progression
                }
            }
        }
    }

    private func requestNavigationPreview(at value: Double) {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let preview = await presentation.session.previewNavigation(at: value)
            guard !Task.isCancelled else { return }
            navigationPreview = preview
        }
    }

    private func goBackAfterJump() {
        Task {
            if await presentation.session.goBackAfterJump() {
                showsControls = false
            }
        }
    }

    private func controlButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
    }

    private func animateChrome(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.easeOut(duration: 0.2), changes)
        }
    }

    private func animateReaderEntrance() {
        guard readerPresentationState == .appearing else { return }
        guard !reduceMotion else {
            readerPresentationState = .visible
            coverTransitionOpacity = 0
            return
        }

        // Expands smoothly from the cover frame using an authentic iOS spring curve.
        // The Readium WebView sits stationary underneath, letting it complete its
        // initial layout without stuttering, while the cover card cross-fades out.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                readerPresentationState = .visible
            }
            withAnimation(.easeOut(duration: 0.20).delay(0.18)) {
                coverTransitionOpacity = 0
            }
        }
    }

    private func scheduleGoalRefresh() {
        goalRefreshTask?.cancel()
        goalRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            onReadingProgress()
        }
    }

    private func applyPreferences(_ newValue: ReaderPreferences) {
        do {
            try presentation.session.updatePreferences(newValue)
        } catch {
            preferences = presentation.session.preferences
        }
    }

    private func openChapter(_ chapter: ReaderChapter) {
        Task {
            if await presentation.session.go(to: chapter) {
                presentedPanel = nil
                showsControls = false
            }
        }
    }

    private func openHighlight(_ highlight: ReaderHighlight) {
        Task {
            if await presentation.session.go(to: highlight) {
                presentedPanel = nil
                showsControls = false
            }
        }
    }

    private func openVocabularyItem(_ item: VocabularyItem) {
        Task {
            if await presentation.session.go(to: item) {
                presentedPanel = nil
                showsControls = false
            }
        }
    }

    private func closeReader() {
        guard readerPresentationState != .closing else { return }
        guard !reduceMotion else {
            Task { await onRequestClose() }
            return
        }

        showsControls = false
        showsQuickPreferences = false

        withAnimation(.easeIn(duration: 0.12)) {
            coverTransitionOpacity = 1.0
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            readerPresentationState = .closing
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            await onRequestClose()

            // If closing failed (for example, a pending Locator could not be
            // saved), keep the reader usable instead of leaving it invisible.
            if readerPresentationState == .closing {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    readerPresentationState = .visible
                    coverTransitionOpacity = 0
                }
            }
        }
    }

    private enum Panel: String, Identifiable {
        case chapters, highlights, vocabulary
        var id: String { rawValue }
    }

    private enum ReaderPresentationState: Equatable {
        case appearing
        case visible
        case closing
    }

    private func sourceRect(in geometry: GeometryProxy) -> CGRect {
        let screenBounds = geometry.frame(in: .global)
        let screenSize = geometry.size

        if let source = presentation.sourceFrame,
           source.width > 0, source.height > 0 {
            let localX = source.minX - screenBounds.minX
            let localY = source.minY - screenBounds.minY
            let localRect = CGRect(x: localX, y: localY, width: source.width, height: source.height)

            let screenRect = CGRect(origin: .zero, size: screenSize)
            if localRect.intersects(screenRect) {
                return localRect
            }
        }

        let fallbackWidth = min(screenSize.width * 0.40, 140)
        let fallbackHeight = fallbackWidth / LoreTheme.coverAspectRatio
        let fallbackX = (screenSize.width - fallbackWidth) / 2
        let fallbackY = (screenSize.height - fallbackHeight) / 2
        return CGRect(x: fallbackX, y: fallbackY, width: fallbackWidth, height: fallbackHeight)
    }

    private func targetRect(in geometry: GeometryProxy) -> CGRect {
        CGRect(origin: .zero, size: geometry.size)
    }

    private func currentCardRect(in geometry: GeometryProxy) -> CGRect {
        switch readerPresentationState {
        case .visible:
            return targetRect(in: geometry)
        case .appearing, .closing:
            return sourceRect(in: geometry)
        }
    }

    private func currentCornerRadius() -> CGFloat {
        switch readerPresentationState {
        case .visible:
            return 0
        case .appearing, .closing:
            return LoreTheme.coverRadius
        }
    }

    private var readerBackground: Color {
        preferences.appearance == .light ? Color(UIColor.systemBackground) : .black
    }
}

private struct ReaderAIExplanationSheet: View {
    let state: ReaderAIExplanationState
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(state.selectedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .accessibilityLabel("Passage sélectionné : \(state.selectedText)")

                    switch state {
                    case .loading:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Explication en cours…")
                        }
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    case let .answer(_, text):
                        ReaderMarkdownText(markdown: text)
                    case let .failure(_, message):
                        ContentUnavailableView(
                            "Explication indisponible",
                            systemImage: "sparkles",
                            description: Text(message)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Expliquer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", action: onClose)
                }
            }
        }
    }
}

private struct ReaderAIRecapSheet: View {
    let state: ReaderAIRecapState
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Résumé de votre lecture d’hier…")
                    }
                    .padding(20)
                case let .answer(text):
                    ScrollView {
                        ReaderMarkdownText(markdown: text)
                            .padding(20)
                    }
                case let .failure(message):
                    ContentUnavailableView(
                        "Résumé indisponible",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Hier, vous en étiez là")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", action: onClose)
                }
            }
        }
    }
}

/// Displays the AI answer as rich Markdown instead of exposing the syntax
/// (`**gras**`, `# titre`, etc.) to the reader. Foundation handles the
/// standard inline and block Markdown syntax and the plain text fallback keeps
/// an answer readable if a future response contains unsupported markup.
private struct ReaderMarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = ReaderMarkdownRenderer.attributedString(from: markdown) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        } else {
            Text(markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        }
    }
}

enum ReaderMarkdownRenderer {
    static func attributedString(from markdown: String) -> AttributedString? {
        try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        )
    }
}

private struct ReaderHighlightsSheet: View {
    let bookID: UUID
    let bookTitle: String
    let author: String?
    let highlights: [ReaderHighlight]
    let onSelect: (ReaderHighlight) -> Void
    let onUpdateNote: (String?, ReaderHighlight) -> ReaderHighlight?
    let onDelete: (ReaderHighlight) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: ReaderHighlight?
    @State private var editingHighlight: ReaderHighlight?
    @State private var searchText = ""
    @State private var filter: HighlightFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "Aucun surlignage",
                        systemImage: "highlighter",
                        description: Text("Sélectionnez un passage puis touchez Surligner.")
                    )
                } else if filteredHighlights.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredHighlights) { highlight in
                        HStack(spacing: 8) {
                            Button { onSelect(highlight) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(highlight.text)
                                        .foregroundStyle(.primary)
                                        .lineLimit(4)
                                    Text(highlight.createdAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let note = highlight.note {
                                        Label(note, systemImage: "note.text")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityHint("Revient au passage surligné")

                            Button(highlight.note == nil ? "Ajouter une note" : "Modifier la note", systemImage: "square.and.pencil") {
                                editingHighlight = highlight
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)

                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                pendingDeletion = highlight
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }
            .navigationTitle("Surlignages")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Passage ou note")
            .safeAreaInset(edge: .top) {
                if !highlights.isEmpty {
                    Picker("Filtrer les surlignages", selection: $filter) {
                        ForEach(HighlightFilter.allCases) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: HighlightMarkdownExporter.export(groups: [BookHighlightGroup(
                        bookID: bookID,
                        title: bookTitle,
                        author: author,
                        highlights: highlights
                    )])) {
                        Label("Exporter en Markdown", systemImage: "square.and.arrow.up")
                    }
                    .disabled(highlights.isEmpty)
                }
            }
            .confirmationDialog(
                "Supprimer ce surlignage ?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    guard let highlight = pendingDeletion else { return }
                    onDelete(highlight)
                    pendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { pendingDeletion = nil }
            }
        }
        .sheet(item: $editingHighlight) { highlight in
            HighlightNoteEditor(highlight: highlight) { note in
                onUpdateNote(note, highlight) != nil
            }
        }
    }

    private var filteredHighlights: [ReaderHighlight] {
        highlights.filter { highlight in
            let matchesFilter = filter == .all || highlight.note != nil
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesFilter && (query.isEmpty
                || highlight.text.localizedStandardContains(query)
                || (highlight.note?.localizedStandardContains(query) ?? false))
        }
    }
}

private struct ReaderQuickPreferences: View {
    @Binding var preferences: ReaderPreferences
    let reduceTransparency: Bool
    let onChange: (ReaderPreferences) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                preferenceButton("Réduire la taille du texte", title: "A−") {
                    preferences.adjustFontSize(by: -1)
                    commit()
                }
                Text(preferences.fontSize, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 48)
                    .accessibilityLabel("Taille du texte")
                preferenceButton("Augmenter la taille du texte", title: "A+") {
                    preferences.adjustFontSize(by: 1)
                    commit()
                }
                Divider().frame(height: 20)
                preferenceButton("Thème sombre", systemImage: "moon", selected: preferences.appearance == .dark) {
                    preferences.appearance = .dark
                    commit()
                }
            }
            Button("Tous les réglages", systemImage: "slider.horizontal.3", action: onShowAll)
                .font(.footnote.weight(.medium))
                .frame(minHeight: 44)
        }
        .padding(8)
        .readerGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), reduceTransparency: reduceTransparency)
    }

    private func preferenceButton(
        _ label: String,
        title: String? = nil,
        systemImage: String? = nil,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let title { Text(title) }
                else if let systemImage { Image(systemName: systemImage) }
            }
            .font(.body.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .background(selected ? Color.primary.opacity(0.12) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func commit() { onChange(preferences) }
}

private struct ReaderPreferencesPage: View {
    @Binding var preferences: ReaderPreferences
    let onChange: (ReaderPreferences) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Texte") {
                    HStack {
                        Button("Réduire la taille du texte", systemImage: "textformat.size.smaller") {
                            preferences.adjustFontSize(by: -1)
                            commit()
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        Spacer()
                        Text("\(Int((preferences.fontSize * 100).rounded())) %")
                            .font(.body.monospacedDigit())
                            .accessibilityLabel("Taille du texte, \(Int((preferences.fontSize * 100).rounded())) pour cent")
                        Spacer()
                        Button("Augmenter la taille du texte", systemImage: "textformat.size.larger") {
                            preferences.adjustFontSize(by: 1)
                            commit()
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    }

                    Picker("Typographie", selection: $preferences.typeface) {
                        ForEach(ReaderPreferences.Typeface.allCases, id: \.self) { typeface in
                            Text(typeface.label).tag(typeface)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preferences.typeface) { _, _ in commit() }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Interligne")
                            Spacer()
                            Text(preferences.lineHeight?.formatted(.number.precision(.fractionLength(1))) ?? "Livre")
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { preferences.lineHeight ?? 1.4 },
                            set: { preferences.lineHeight = $0 }
                        ), in: ReaderPreferences.lineHeightRange, step: 0.1)
                        .onChange(of: preferences.lineHeight) { _, _ in commit() }
                        if preferences.lineHeight != nil {
                            Button("Utiliser l’interligne du livre") {
                                preferences.lineHeight = nil
                                commit()
                            }
                        }
                    }
                }

                Section("Thème") {
                    Label("Mode sombre permanent", systemImage: "moon.fill")
                        .foregroundStyle(.secondary)
                }

                Section {
                    marginSlider(
                        title: "Gauche et droite",
                        value: $preferences.horizontalMargins,
                        range: ReaderPreferences.horizontalMarginsRange
                    )

                    marginSlider(
                        title: "Haut et bas",
                        value: $preferences.verticalMargins,
                        range: ReaderPreferences.verticalMarginsRange
                    )
                } header: {
                    Text("Marges")
                } footer: {
                    Text("Les marges sont globales et s’appliquent à tous les livres.")
                }

                Section {
                    Button("Réinitialiser les réglages", role: .destructive) {
                        preferences.reset()
                        commit()
                    }
                }
            }
            .navigationTitle("Réglages de lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func commit() { onChange(preferences) }

    private func marginSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: value,
                in: range,
                step: 0.25,
                onEditingChanged: { isEditing in
                    if !isEditing { commit() }
                }
            )
            .accessibilityLabel("Marges \(title.lowercased())")
            .accessibilityValue(
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
            )
        }
    }
}

private extension View {
    @ViewBuilder
    func readerGlass<S: Shape>(
        in shape: S,
        reduceTransparency: Bool,
        interactive: Bool = false
    ) -> some View {
        if reduceTransparency {
            background(Color(uiColor: .systemBackground).opacity(0.96), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.16), lineWidth: 0.5))
        } else {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

private struct ReaderChaptersSheet: View {
    let chapters: [ReaderChapter]
    let onSelect: (ReaderChapter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "Sommaire indisponible",
                        systemImage: "list.bullet",
                        description: Text("Cet EPUB ne fournit aucun chapitre navigable.")
                    )
                } else {
                    List(chapters) { chapter in
                        Button { onSelect(chapter) } label: {
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                                .padding(.leading, CGFloat(min(chapter.depth, 3)) * 16)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("Sommaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
