import SwiftUI

struct ReaderScreen: View {
    let presentation: LibraryViewModel.ReaderPresentation
    let onRequestClose: @MainActor () async -> Void

    @State private var showsControls = false
    @State private var showsQuickPreferences = false
    @State private var showsAllPreferences = false
    @State private var presentedPanel: Panel?
    @State private var preferences: ReaderPreferences
    @State private var progression: Double
    @State private var highlights: [ReaderHighlight]
    @State private var aiExplanation: ReaderAIExplanationState?
    @State private var aiRecap: ReaderAIRecapState?
    @Namespace private var glassNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        presentation: LibraryViewModel.ReaderPresentation,
        onRequestClose: @escaping @MainActor () async -> Void
    ) {
        self.presentation = presentation
        self.onRequestClose = onRequestClose
        _preferences = State(initialValue: presentation.session.preferences)
        _progression = State(initialValue: presentation.session.currentProgression)
        _highlights = State(initialValue: presentation.session.highlights)
    }

    var body: some View {
        ZStack {
            ReaderView(session: presentation.session)

            if showsControls {
                controls
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .preferredColorScheme(preferences.appearance == .dark ? .dark : .light)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .accessibilityAction(.escape) { closeReader() }
        .interactiveDismissDisabled(true)
        .onAppear {
            presentation.session.setTapHandler {
                animateChrome {
                    showsControls.toggle()
                    if !showsControls { showsQuickPreferences = false }
                }
            }
            presentation.session.setProgressionHandler { progression = $0 }
            presentation.session.setHighlightChangeHandler { highlights = $0 }
            presentation.session.setExplanationHandler { aiExplanation = $0 }
            presentation.session.setRecapHandler { aiRecap = $0 }
            presentation.session.requestDailyRecapIfEligible()
        }
        .onDisappear {
            presentation.session.setTapHandler(nil)
            presentation.session.setProgressionHandler(nil)
            presentation.session.setHighlightChangeHandler(nil)
            presentation.session.setExplanationHandler(nil)
            presentation.session.setRecapHandler(nil)
        }
        .sheet(item: $presentedPanel) { panel in
            switch panel {
            case .chapters:
                ReaderChaptersSheet(chapters: presentation.session.chapters, onSelect: openChapter)
            case .highlights:
                ReaderHighlightsSheet(
                    highlights: highlights,
                    onSelect: openHighlight,
                    onDelete: presentation.session.deleteHighlight
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
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 8) {
                controlButton("Fermer le lecteur", systemImage: "xmark") { closeReader() }
                Text(presentation.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .readerGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), reduceTransparency: reduceTransparency)
            .padding(.horizontal, 12)

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
                        progressLabel
                        Divider().frame(height: 20)
                        controlButton("Sommaire", systemImage: "list.bullet") { presentedPanel = .chapters }
                        controlButton("Surlignages", systemImage: "highlighter") { presentedPanel = .highlights }
                        controlButton("Réglages de lecture", systemImage: "textformat") {
                            animateChrome { showsQuickPreferences.toggle() }
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 52)
                    .readerGlass(in: Capsule(), reduceTransparency: reduceTransparency, interactive: true)
                }
            }
            .padding(.horizontal, 12)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 8)
    }

    private var progressLabel: some View {
        Text(progression, format: .percent.precision(.fractionLength(0)))
            .font(.caption.monospacedDigit().weight(.medium))
            .contentTransition(.numericText())
            .frame(minWidth: 52, minHeight: 44)
            .accessibilityLabel("Progression")
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

    private func closeReader() {
        Task { await onRequestClose() }
    }

    private enum Panel: String, Identifiable {
        case chapters, highlights
        var id: String { rawValue }
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
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
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
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .textSelection(.enabled)
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

private struct ReaderHighlightsSheet: View {
    let highlights: [ReaderHighlight]
    let onSelect: (ReaderHighlight) -> Void
    let onDelete: (ReaderHighlight) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: ReaderHighlight?

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "Aucun surlignage",
                        systemImage: "highlighter",
                        description: Text("Sélectionnez un passage puis touchez Surligner.")
                    )
                } else {
                    List(highlights) { highlight in
                        HStack(spacing: 8) {
                            Button { onSelect(highlight) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(highlight.text)
                                        .foregroundStyle(.primary)
                                        .lineLimit(4)
                                    Text(highlight.createdAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityHint("Revient au passage surligné")

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
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
                preferenceButton("Thème clair", systemImage: "sun.max", selected: preferences.appearance == .light) {
                    preferences.appearance = .light
                    commit()
                }
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
                    Picker("Thème de lecture", selection: $preferences.appearance) {
                        ForEach(ReaderPreferences.Appearance.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preferences.appearance) { _, _ in commit() }
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
