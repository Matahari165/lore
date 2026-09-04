import SwiftUI

struct AllHighlightsView: View {
    let loadError: String?
    let onOpenHighlight: ((UUID, ReaderHighlight) -> Void)?
    let onUpdateNote: (String?, ReaderHighlight) -> ReaderHighlight?
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [BookHighlightGroup]
    @State private var searchText = ""
    @State private var filter: HighlightFilter = .all
    @State private var editingHighlight: ReaderHighlight?

    init(
        groups: [BookHighlightGroup],
        loadError: String?,
        onOpenHighlight: ((UUID, ReaderHighlight) -> Void)?,
        onUpdateNote: @escaping (String?, ReaderHighlight) -> ReaderHighlight?
    ) {
        _groups = State(initialValue: groups)
        self.loadError = loadError
        self.onOpenHighlight = onOpenHighlight
        self.onUpdateNote = onUpdateNote
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Annotations indisponibles",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if groups.isEmpty {
                    ContentUnavailableView("Aucune annotation", systemImage: "highlighter", description: Text("Les passages surlignés apparaîtront ici, groupés par livre."))
                } else if filteredGroups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredGroups) { group in
                            Section(group.title) {
                                ForEach(group.highlights) { highlight in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Button {
                                            dismiss()
                                            onOpenHighlight?(group.bookID, highlight)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(highlight.text).foregroundStyle(.primary).lineLimit(4)
                                                if let note = highlight.note {
                                                    Label(note, systemImage: "note.text").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(onOpenHighlight == nil)
                                        .accessibilityHint(onOpenHighlight == nil ? "" : "Ouvre le passage dans le lecteur")

                                        Button(highlight.note == nil ? "Ajouter une note" : "Modifier la note", systemImage: "square.and.pencil") {
                                            editingHighlight = highlight
                                        }
                                        .font(.callout.weight(.medium))
                                        .frame(minHeight: 44)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Livre, passage ou note")
            .safeAreaInset(edge: .top) {
                if !groups.isEmpty {
                    Picker("Filtrer les annotations", selection: $filter) {
                        ForEach(HighlightFilter.allCases) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.bar)
                }
            }
            .navigationTitle("Annotations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: HighlightMarkdownExporter.export(groups: groups)) {
                        Label("Exporter en Markdown", systemImage: "square.and.arrow.up")
                    }
                    .disabled(groups.isEmpty)
                }
            }
        }
        .sheet(item: $editingHighlight) { highlight in
            HighlightNoteEditor(highlight: highlight) { note in
                guard let updated = onUpdateNote(note, highlight) else { return false }
                replace(updated)
                return true
            }
        }
        .loreCanvas()
    }

    private var filteredGroups: [BookHighlightGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.compactMap { group in
            let highlights = group.highlights.filter { highlight in
                let matchesFilter = filter == .all || highlight.note != nil
                let matchesSearch = HighlightSearchMatcher.matches(query, group: group, highlight: highlight)
                return matchesFilter && matchesSearch
            }
            guard !highlights.isEmpty else { return nil }
            return BookHighlightGroup(bookID: group.bookID, title: group.title, author: group.author, highlights: highlights)
        }
    }

    private func replace(_ updated: ReaderHighlight) {
        guard let groupIndex = groups.firstIndex(where: { $0.bookID == updated.bookID }),
              let highlightIndex = groups[groupIndex].highlights.firstIndex(where: { $0.id == updated.id }) else { return }
        groups[groupIndex].highlights[highlightIndex] = updated
    }
}
