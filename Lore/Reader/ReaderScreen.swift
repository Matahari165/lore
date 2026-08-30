import SwiftUI

struct ReaderScreen: View {
    let presentation: LibraryViewModel.ReaderPresentation
    let onRequestClose: @MainActor () async -> Void

    @State private var showsControls = true
    @State private var presentedPanel: Panel?
    @State private var preferences: ReaderPreferences

    init(
        presentation: LibraryViewModel.ReaderPresentation,
        onRequestClose: @escaping @MainActor () async -> Void
    ) {
        self.presentation = presentation
        self.onRequestClose = onRequestClose
        _preferences = State(initialValue: presentation.session.preferences)
    }

    var body: some View {
        ZStack {
            ReaderView(session: presentation.session)

            if showsControls {
                controls.transition(.opacity)
            }
        }
        .preferredColorScheme(preferences.appearance == .dark ? .dark : .light)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .accessibilityAction(.escape) { closeReader() }
        .interactiveDismissDisabled(true)
        .onAppear {
            presentation.session.setTapHandler {
                withAnimation(.easeOut(duration: 0.18)) { showsControls.toggle() }
            }
        }
        .onDisappear { presentation.session.setTapHandler(nil) }
        .sheet(item: $presentedPanel) { panel in
            switch panel {
            case .chapters:
                ReaderChaptersSheet(chapters: presentation.session.chapters, onSelect: openChapter)
            case .preferences:
                ReaderPreferencesSheet(preferences: $preferences, onChange: applyPreferences)
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                controlButton("Fermer le lecteur", systemImage: "chevron.down") { closeReader() }
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            Spacer()
            HStack(spacing: 20) {
                controlButton("Sommaire", systemImage: "list.bullet") { presentedPanel = .chapters }
                controlButton("Réglages de lecture", systemImage: "textformat.size") {
                    presentedPanel = .preferences
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(alignment: .top) { barMaterial }
        .background(alignment: .bottom) { barMaterial }
    }

    private var barMaterial: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: 64)
            .ignoresSafeArea(edges: .horizontal)
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

    private func closeReader() {
        Task { await onRequestClose() }
    }

    private enum Panel: String, Identifiable {
        case chapters
        case preferences
        var id: String { rawValue }
    }
}

private struct ReaderPreferencesSheet: View {
    @Binding var preferences: ReaderPreferences
    let onChange: (ReaderPreferences) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Texte") {
                    HStack {
                        Button("Réduire la taille du texte", systemImage: "textformat.size.smaller") {
                            preferences.fontSize = max(0.8, preferences.fontSize - 0.1)
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
                            preferences.fontSize = min(2.0, preferences.fontSize + 0.1)
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
                        ), in: 1.0 ... 2.0, step: 0.1)
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
            }
            .navigationTitle("Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commit() { onChange(preferences) }
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
