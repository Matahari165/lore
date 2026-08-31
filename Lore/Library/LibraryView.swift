import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Mode { case home, library }

    let mode: Mode
    let model: LibraryViewModel
    @State private var presentsImporter = false

    init(mode: Mode = .library, model: LibraryViewModel) {
        self.mode = mode
        self.model = model
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.books.isEmpty { emptyState }
                else if mode == .home { homeContent }
                else { libraryContent }
            }
            .navigationTitle(mode == .home ? "Accueil" : "Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer des EPUB", systemImage: "plus") { presentsImporter = true }
                        .disabled(model.isImporting)
                }
            }
            .overlay {
                if model.isImporting {
                    ZStack {
                        LoreTheme.canvas.opacity(0.88)
                        ProgressView("Importation en cours…").font(.callout.weight(.medium))
                    }
                    .ignoresSafeArea()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .loreCanvas()
        .task { model.reload() }
        .fileImporter(isPresented: $presentsImporter, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data], allowsMultipleSelection: true) { result in
            Task { await model.importSelection(result.mapError { $0 as Error }) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(mode == .home ? "Votre prochaine lecture commence ici" : "Aucun livre", systemImage: "books.vertical")
        } description: {
            Text("Importez un ou plusieurs EPUB sans DRM depuis Fichiers.")
        } actions: {
            Button("Importer des EPUB") { presentsImporter = true }
                .buttonStyle(.borderedProminent).foregroundStyle(LoreTheme.canvas).controlSize(.large)
        }
    }

    private var homeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let book = model.resumableBook { resumeSection(book) }
                bookGrid(title: "Ajouts récents", books: model.recentlyImportedBooks)
            }
            .padding(.horizontal, LoreTheme.pageMargin).padding(.bottom, 32)
        }
        .background(LoreTheme.canvas)
    }

    private var libraryContent: some View {
        @Bindable var model = model
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Catégorie", selection: $model.filter) {
                    ForEach(LibraryViewModel.Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Menu {
                        Picker("Trier par", selection: $model.sort) {
                            ForEach(LibraryViewModel.Sort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: { Label(model.sort.title, systemImage: "arrow.up.arrow.down") }
                    Spacer()
                    Button(model.sortAscending ? "Ordre ascendant" : "Ordre descendant", systemImage: model.sortAscending ? "arrow.up" : "arrow.down") { model.sortAscending.toggle() }
                        .labelStyle(.iconOnly)
                        .accessibilityValue(model.sortAscending ? "Ascendant" : "Descendant")
                }
                .font(.subheadline)

                if model.visibleBooks.isEmpty { ContentUnavailableView.search(text: model.searchText) }
                else { bookGrid(title: "\(model.visibleBooks.count) livre\(model.visibleBooks.count > 1 ? "s" : "")", books: model.visibleBooks) }
            }
            .padding(.horizontal, LoreTheme.pageMargin).padding(.bottom, 32)
        }
        .searchable(text: $model.searchText, prompt: "Titre ou auteur")
        .background(LoreTheme.canvas)
    }

    private func resumeSection(_ book: BookRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprendre").font(.title3.weight(.semibold))
            Button { Task { await model.open(book) } } label: {
                HStack(spacing: 18) {
                    BookCoverView(book: book).frame(width: 92)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title).font(.headline).foregroundStyle(LoreTheme.ink).lineLimit(2)
                        if let author = book.author { Text(author).font(.subheadline).foregroundStyle(LoreTheme.secondaryInk).lineLimit(1) }
                        if let progression = book.lastProgression { Text(progression, format: .percent.precision(.fractionLength(0))).font(.caption.weight(.medium)).foregroundStyle(LoreTheme.secondaryInk) }
                    }
                    Spacer(minLength: 8)
                    if model.openingBookID == book.id { ProgressView() }
                    else { Image(systemName: "play.fill").font(.headline).foregroundStyle(LoreTheme.ink).frame(width: 44, height: 44).background(LoreTheme.ink.opacity(0.08), in: Circle()) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Reprendre \(book.title)")
        }
    }

    private func bookGrid(title: String, books: [BookRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 18)], alignment: .leading, spacing: 24) {
                ForEach(books) { book in bookButton(book) }
            }
        }
    }

    private func bookButton(_ book: BookRecord) -> some View {
        Button { Task { await model.open(book) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    BookCoverView(book: book)
                    if model.openingBookID == book.id { LoreTheme.canvas.opacity(0.68); ProgressView() }
                }
                Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(LoreTheme.ink).lineLimit(2)
                if let author = book.author { Text(author).font(.caption).foregroundStyle(LoreTheme.secondaryInk).lineLimit(1) }
                Text(book.readingStatus.title).font(.caption2.weight(.medium)).foregroundStyle(LoreTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).accessibilityLabel("Ouvrir \(book.title), \(book.readingStatus.title)")
    }
}
