import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var model: LibraryViewModel
    @State private var presentsImporter = false

    init(
        repository: BookRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        _model = State(initialValue: LibraryViewModel(
            repository: repository,
            fileStore: fileStore,
            publicationService: publicationService
        ))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                if model.books.isEmpty {
                    emptyLibrary
                } else {
                    libraryContent
                }
            }
            .navigationTitle("Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer un EPUB", systemImage: "plus") {
                        presentsImporter = true
                    }
                    .disabled(model.isImporting)
                }
            }
            .overlay {
                if model.isImporting {
                    ZStack {
                        LoreTheme.canvas.opacity(0.82)
                        ProgressView("Importation…")
                            .font(.callout.weight(.medium))
                    }
                    .ignoresSafeArea()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .loreCanvas()
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            let selection = result.flatMap { urls -> Result<URL, Error> in
                guard let url = urls.first else {
                    return .failure(CocoaError(.fileNoSuchFile))
                }
                return .success(url)
            }
            Task { await model.importSelection(selection) }
        }
        .alert("Impossible de continuer", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .fullScreenCover(item: $model.readerPresentation) { presentation in
            ReaderScreen(presentation: presentation) {
                await model.closeReader()
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Aucun livre", systemImage: "books.vertical")
        } description: {
            Text("Importez un EPUB sans DRM depuis Fichiers.")
        } actions: {
            Button("Importer un EPUB") { presentsImporter = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let book = model.resumableBook {
                    resumeSection(book)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Tous les livres")
                        .font(.title3.weight(.semibold))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 18)],
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(model.books) { book in
                            bookButton(book)
                        }
                    }
                }
            }
            .padding(.horizontal, LoreTheme.pageMargin)
            .padding(.bottom, 32)
        }
        .background(LoreTheme.canvas)
    }

    private func resumeSection(_ book: BookRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprendre")
                .font(.title3.weight(.semibold))

            Button {
                Task { await model.open(book) }
            } label: {
                HStack(spacing: 18) {
                    BookCoverView(book: book)
                        .frame(width: 92)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.headline)
                            .foregroundStyle(LoreTheme.ink)
                            .lineLimit(2)
                        if let author = book.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(LoreTheme.secondaryInk)
                                .lineLimit(1)
                        }
                        if let progression = book.lastProgression {
                            Text(progression, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LoreTheme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 8)
                    if model.openingBookID == book.id {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill")
                            .font(.headline)
                            .foregroundStyle(LoreTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(LoreTheme.ink.opacity(0.08), in: Circle())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reprendre \(book.title)")
        }
    }

    private func bookButton(_ book: BookRecord) -> some View {
        Button {
            Task { await model.open(book) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    BookCoverView(book: book)
                    if model.openingBookID == book.id {
                        LoreTheme.canvas.opacity(0.68)
                        ProgressView()
                    }
                }
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LoreTheme.ink)
                    .lineLimit(2)
                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(LoreTheme.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir \(book.title)")
    }
}
