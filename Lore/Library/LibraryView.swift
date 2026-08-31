import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Mode { case home, library }

    let mode: Mode
    let model: LibraryViewModel
    let dailyGoalState: DailyGoalState
    let onOpenSettings: () -> Void
    let onOpenActivityChart: (() -> Void)?
    /// Optional hand-off to the reader for a selected highlight. The library
    /// still presents the complete local list when no reader route is supplied.
    let onOpenHighlight: ((BookRecord, ReaderHighlight) -> Void)?
    @State private var presentsImporter = false
    @State private var discussionBook: BookRecord?
    @State private var completionBook: BookRecord?
    @State private var highlightsBook: BookRecord?
    @State private var selectedHighlights: [ReaderHighlight] = []

    init(
        mode: Mode = .library,
        model: LibraryViewModel,
        dailyGoalState: DailyGoalState = .disabled,
        onOpenSettings: @escaping () -> Void = {},
        onOpenActivityChart: (() -> Void)? = nil,
        onOpenHighlight: ((BookRecord, ReaderHighlight) -> Void)? = nil
    ) {
        self.mode = mode
        self.model = model
        self.dailyGoalState = dailyGoalState
        self.onOpenSettings = onOpenSettings
        self.onOpenActivityChart = onOpenActivityChart
        self.onOpenHighlight = onOpenHighlight
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.books.isEmpty { emptyState }
                else if mode == .home { homeContent }
                else { libraryContent }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(mode == .home ? "Accueil" : "Bibliothèque")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }
                if mode == .home {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Réglages", systemImage: "gearshape", action: onOpenSettings)
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Configurer l’objectif quotidien")
                    }
                }
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
        .sheet(item: $discussionBook) { book in
            BookDiscussionView(
                book: book,
                conversationRepository: model.conversationRepository,
                onOpenSettings: mode == .home ? onOpenSettings : nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $completionBook) { book in
            BookCompletionView(book: book) { rating, readingYear in
                model.finish(book, rating: rating, readingYear: readingYear)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $highlightsBook) { book in
            LibraryHighlightsView(
                book: book,
                highlights: selectedHighlights,
                onOpenHighlight: onOpenHighlight.map { callback in
                    { highlight in callback(book, highlight) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(isPresented: $presentsImporter, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data], allowsMultipleSelection: true) { result in
            Task { await model.importSelection(result.mapError { $0 as Error }) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if mode == .home {
                DailyGoalProgressView(state: dailyGoalState, onTap: onOpenActivityChart)
                    .padding(.horizontal, LoreTheme.pageMargin)
            }
            ContentUnavailableView {
                Label(mode == .home ? "Votre prochaine lecture commence ici" : "Aucun livre", systemImage: "books.vertical")
            } description: {
                Text("Importez un ou plusieurs EPUB sans DRM depuis Fichiers.")
            } actions: {
                Button("Importer des EPUB") { presentsImporter = true }
                    .buttonStyle(.borderedProminent).foregroundStyle(LoreTheme.canvas).controlSize(.large)
            }
        }
    }

    private var homeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                DailyGoalProgressView(state: dailyGoalState, onTap: onOpenActivityChart)
                if !model.resumableBooks.isEmpty { resumeSection(model.resumableBooks) }
                YesterdayReadingSummaryView(summary: model.yesterdayReadingSummary)
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

    private func resumeSection(_ books: [BookRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprendre").font(.title3.weight(.semibold))
            ForEach(books) { book in
                HStack(spacing: 10) {
                    Button { Task { await model.open(book) } } label: {
                        HStack(spacing: 14) {
                            BookCoverView(book: book).frame(width: 72)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title).font(.headline).foregroundStyle(LoreTheme.ink).lineLimit(2)
                                if let author = book.author {
                                    Text(author).font(.subheadline).foregroundStyle(LoreTheme.secondaryInk).lineLimit(1)
                                }
                                if let progression = book.lastProgression {
                                    Text("Progression \(progression, format: .percent.precision(.fractionLength(0)))")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(LoreTheme.secondaryInk)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if model.openingBookID == book.id { ProgressView() }
                            else {
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
                    .accessibilityValue(resumeAccessibilityValue(for: book))
                    .contextMenu { bookContextMenu(for: book) }
                }
            }
        }
    }

    private func resumeAccessibilityValue(for book: BookRecord) -> String {
        var details: [String] = []
        if let author = book.author { details.append(author) }
        if let progression = book.lastProgression {
            details.append("progression \(progression.formatted(.percent.precision(.fractionLength(0))))")
        }
        return details.joined(separator: ", ")
    }

    private func bookGrid(title: String, books: [BookRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                alignment: .leading,
                spacing: 24
            ) {
                ForEach(books) { book in bookButton(book) }
            }
        }
    }

    private func bookButton(_ book: BookRecord) -> some View {
        Button { Task { await model.open(book) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                BookCoverView(book: book)
                    .overlay {
                        if model.openingBookID == book.id {
                            LoreTheme.canvas.opacity(0.68)
                            ProgressView()
                        }
                    }
                // Fixed label slots prevent a long title or a missing author
                // from changing the height of a grid row.
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LoreTheme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)
                Group {
                    if let author = book.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(LoreTheme.secondaryInk)
                            .lineLimit(1)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
                Text(book.readingStatus.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir \(book.title), \(book.readingStatus.title)")
        .contextMenu { bookContextMenu(for: book) }
    }

    @ViewBuilder
    private func bookContextMenu(for book: BookRecord) -> some View {
        if book.readingStatus == .finished {
            Button("Marquer comme non terminé", systemImage: "arrow.uturn.backward") {
                model.setFinished(false, for: book)
            }
        } else {
            Button("Marquer comme lu", systemImage: "checkmark.circle") {
                completionBook = book
            }
        }

        Button("Passages surlignés", systemImage: "highlighter") {
            selectedHighlights = model.highlights(for: book)
            highlightsBook = book
        }

        Button("Discuter avec le livre", systemImage: "sparkles") {
            discussionBook = book
        }
    }
}
