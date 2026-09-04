import SwiftUI

struct LibraryHighlightsView: View {
    let book: BookRecord
    let loadError: String?
    let onOpenHighlight: ((ReaderHighlight) -> Void)?
    let onUpdateNote: (String?, ReaderHighlight) -> ReaderHighlight?
    let onDiscussHighlight: ((ReaderHighlight) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var highlights: [ReaderHighlight]
    @State private var searchText = ""
    @State private var filter: HighlightFilter = .all
    @State private var editingHighlight: ReaderHighlight?

    init(
        book: BookRecord,
        highlights: [ReaderHighlight],
        loadError: String?,
        onOpenHighlight: ((ReaderHighlight) -> Void)?,
        onUpdateNote: @escaping (String?, ReaderHighlight) -> ReaderHighlight?,
        onDiscussHighlight: ((ReaderHighlight) -> Void)?
    ) {
        self.book = book
        self.loadError = loadError
        self.onOpenHighlight = onOpenHighlight
        self.onUpdateNote = onUpdateNote
        self.onDiscussHighlight = onDiscussHighlight
        _highlights = State(initialValue: highlights)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Surlignages indisponibles",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if highlights.isEmpty {
                    ContentUnavailableView(
                        "Aucun passage surligné",
                        systemImage: "highlighter",
                        description: Text("Les passages que vous surlignez dans le lecteur apparaîtront ici.")
                    )
                } else if filteredHighlights.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredHighlights) { highlight in highlightRow(highlight) }
                }
            }
            .safeAreaInset(edge: .top) {
                if !highlights.isEmpty { filterPicker }
            }
            .navigationTitle("Passages surlignés")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Passage ou note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: HighlightMarkdownExporter.export(groups: [BookHighlightGroup(
                            bookID: book.id,
                            title: book.title,
                            author: book.author,
                            highlights: highlights
                        )]),
                        subject: Text("Annotations — \(book.title)")
                    ) {
                        Label("Exporter en Markdown", systemImage: "square.and.arrow.up")
                    }
                    .disabled(highlights.isEmpty)
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

    private var filterPicker: some View {
        Picker("Filtrer les surlignages", selection: $filter) {
            ForEach(HighlightFilter.allCases) { option in Text(option.title).tag(option) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var filteredHighlights: [ReaderHighlight] {
        highlights.filter { highlight in
            let matchesFilter = filter == .all || highlight.note != nil
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || highlight.text.localizedStandardContains(query)
                || (highlight.note?.localizedStandardContains(query) ?? false)
            return matchesFilter && matchesSearch
        }
    }

    private func highlightRow(_ highlight: ReaderHighlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                dismiss()
                onOpenHighlight?(highlight)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.text).foregroundStyle(LoreTheme.ink).lineLimit(5)
                    if let note = highlight.note {
                        Label(note, systemImage: "note.text")
                            .font(.callout)
                            .foregroundStyle(LoreTheme.secondaryInk)
                            .lineLimit(3)
                    }
                    Text(highlight.createdAt, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(LoreTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(onOpenHighlight == nil)
            .accessibilityHint(onOpenHighlight == nil ? "" : "Ouvre ce passage dans le lecteur")

            Button(highlight.note == nil ? "Ajouter une note" : "Modifier la note", systemImage: "square.and.pencil") {
                editingHighlight = highlight
            }
            .font(.callout.weight(.medium))
            .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(highlight.note == nil ? "Ajouter une note" : "Modifier la note", systemImage: "square.and.pencil") {
                editingHighlight = highlight
            }
            if let onDiscussHighlight {
                Button("Discuter de ce passage", systemImage: "sparkles") {
                    dismiss()
                    onDiscussHighlight(highlight)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func replace(_ updated: ReaderHighlight) {
        guard let index = highlights.firstIndex(where: { $0.id == updated.id }) else { return }
        highlights[index] = updated
    }
}

enum HighlightFilter: String, CaseIterable, Identifiable {
    case all, withNote
    var id: String { rawValue }
    var title: String { self == .all ? "Tous" : "Avec note" }
}

struct HighlightNoteEditor: View {
    let highlight: ReaderHighlight
    let onSave: (String?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var showsSaveError = false
    @State private var confirmsNoteDeletion = false

    init(highlight: ReaderHighlight, onSave: @escaping (String?) -> Bool) {
        self.highlight = highlight
        self.onSave = onSave
        _note = State(initialValue: highlight.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Passage") { Text(highlight.text).foregroundStyle(.secondary) }
                Section("Note personnelle") {
                    TextEditor(text: $note)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Note personnelle")
                }
            }
            .navigationTitle(highlight.note == nil ? "Ajouter une note" : "Modifier la note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if onSave(note) { dismiss() } else { showsSaveError = true }
                    }
                    .fontWeight(.semibold)
                }
                if highlight.note != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Supprimer la note", role: .destructive) {
                            confirmsNoteDeletion = true
                        }
                    }
                }
            }
            .alert("Note non enregistrée", isPresented: $showsSaveError) {
                Button("OK") {}
            } message: {
                Text("La note n’a pas pu être sauvegardée. Le surlignage existant est conservé.")
            }
            .confirmationDialog(
                "Supprimer cette note ?",
                isPresented: $confirmsNoteDeletion,
                titleVisibility: .visible
            ) {
                Button("Supprimer la note", role: .destructive) {
                    if onSave(nil) { dismiss() } else { showsSaveError = true }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le passage surligné restera disponible.")
            }
        }
        .interactiveDismissDisabled(note != (highlight.note ?? ""))
    }
}
