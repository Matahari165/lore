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
    let onOpenDiscussionSource: ((BookRecord, LoreAIChatSource) -> Void)?
    @State private var presentsImporter = false
    @State private var discussionBook: BookRecord?
    @State private var completionBook: BookRecord?
    @State private var highlightsBook: BookRecord?
    @State private var selectedHighlights: [ReaderHighlight] = []
    @State private var highlightsLoadError: String?
    @State private var discussionDraft: String?
    @State private var discussionHighlight: ReaderHighlight?
    @State private var pendingHighlightDiscussion: PendingHighlightDiscussion?
    @State private var showsAllHighlights = false
    @State private var allHighlightGroups: [BookHighlightGroup] = []
    @State private var allHighlightsLoadError: String?
    @State private var presentsCollections = false
    @State private var detailBook: BookRecord?
    @State private var pendingDetailDestination: PendingDetailDestination?

    init(
        mode: Mode = .library,
        model: LibraryViewModel,
        dailyGoalState: DailyGoalState = .disabled,
        onOpenSettings: @escaping () -> Void = {},
        onOpenActivityChart: (() -> Void)? = nil,
        onOpenHighlight: ((BookRecord, ReaderHighlight) -> Void)? = nil,
        onOpenDiscussionSource: ((BookRecord, LoreAIChatSource) -> Void)? = nil
    ) {
        self.mode = mode
        self.model = model
        self.dailyGoalState = dailyGoalState
        self.onOpenSettings = onOpenSettings
        self.onOpenActivityChart = onOpenActivityChart
        self.onOpenHighlight = onOpenHighlight
        self.onOpenDiscussionSource = onOpenDiscussionSource
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                pageHeader
                Group {
                    if model.books.isEmpty { emptyState }
                    else if mode == .home { homeContent }
                    else { libraryContent }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if model.isImporting {
                    ZStack {
                        LoreTheme.canvas.opacity(0.88)
                        ProgressView(model.currentImportProgress ?? "Importation en cours…")
                            .font(.callout.weight(.medium))
                    }
                    .ignoresSafeArea()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .loreCanvas()
        .task { model.reload() }
        .sheet(item: $discussionBook, onDismiss: {
            discussionHighlight = nil
            discussionDraft = nil
        }) { book in
            BookDiscussionView(
                book: book,
                conversationRepository: model.conversationRepository,
                onOpenSettings: mode == .home ? onOpenSettings : nil,
                initialDraft: discussionDraft,
                initialHighlight: discussionHighlight,
                onOpenSource: onOpenDiscussionSource.map { route in
                    { source in
                        discussionBook = nil
                        route(book, source)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailBook, onDismiss: presentPendingDetailDestination) { book in
            BookDetailView(
                book: book,
                loadDetail: { try model.detailData(for: book.id) },
                onOpenBook: {
                    pendingDetailDestination = .reader(book)
                    detailBook = nil
                },
                onOpenHighlights: {
                    pendingDetailDestination = .highlights(book)
                    detailBook = nil
                },
                onOpenDiscussion: {
                    pendingDetailDestination = .discussion(book)
                    detailBook = nil
                },
                collections: model.manualCollections,
                isMember: { model.isMember(book, of: $0) },
                onToggleCollection: { model.toggleMembership(of: book, in: $0) }
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
        .sheet(item: $highlightsBook, onDismiss: presentPendingHighlightDiscussion) { book in
            LibraryHighlightsView(
                book: book,
                highlights: selectedHighlights,
                loadError: highlightsLoadError,
                onOpenHighlight: onOpenHighlight.map { callback in
                    { highlight in
                        highlightsBook = nil
                        callback(book, highlight)
                    }
                },
                onUpdateNote: model.updateNote,
                onDiscussHighlight: { highlight in
                    pendingHighlightDiscussion = PendingHighlightDiscussion(
                        book: book,
                        highlight: highlight
                    )
                    highlightsBook = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAllHighlights) {
            AllHighlightsView(
                groups: allHighlightGroups,
                loadError: allHighlightsLoadError,
                onOpenHighlight: onOpenHighlight.map { callback in
                    { bookID, highlight in
                        guard let book = model.books.first(where: { $0.id == bookID }) else { return }
                        showsAllHighlights = false
                        callback(book, highlight)
                    }
                },
                onUpdateNote: model.updateNote
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentsCollections) {
            CollectionsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(isPresented: $presentsImporter, allowedContentTypes: [.epub, .folder], allowsMultipleSelection: true) { result in
            Task { await model.importSelection(result.mapError { $0 as Error }) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            Task { await model.importURLs(urls) }
            return true
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 10) {
            Text(mode == .home ? "Accueil" : "Bibliothèque")
                .font(.title.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if mode == .home {
                Button("Réglages", systemImage: "gearshape", action: onOpenSettings)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityHint("Configurer l’objectif quotidien")
            }

            if mode == .library {
                Button("Toutes les annotations", systemImage: "highlighter") {
                    do {
                        allHighlightGroups = try model.highlightGroups()
                        allHighlightsLoadError = nil
                    } catch {
                        allHighlightGroups = []
                        allHighlightsLoadError = (error as? LocalizedError)?.errorDescription
                            ?? "Les annotations n’ont pas pu être chargées."
                    }
                    showsAllHighlights = true
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                Button("Collections", systemImage: "books.vertical") { presentsCollections = true }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityHint("Afficher les collections manuelles et intelligentes")
            }

            Button("Importer des EPUB", systemImage: "plus") { presentsImporter = true }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(model.isImporting)
        }
        .foregroundStyle(LoreTheme.ink)
        .padding(.leading, LoreTheme.pageMargin)
        .padding(.trailing, max(8, LoreTheme.pageMargin - 6))
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(LoreTheme.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if mode == .home {
                DailyGoalProgressView(state: dailyGoalState, compact: true, onTap: onOpenActivityChart)
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
                DailyGoalProgressView(state: dailyGoalState, compact: true, onTap: onOpenActivityChart)
                if !model.resumableBooks.isEmpty { resumeSection(model.resumableBooks) }
                YesterdayReadingSummaryView(
                    state: model.isShowingHistoryPastDay ? model.historyRecapState : model.yesterdayReadingSummaryState,
                    dayTitle: model.historyDayTitle,
                    isHistoryDay: model.isShowingHistoryPastDay,
                    canGoPrevious: model.canGoToOlderHistoryDay,
                    canGoNext: model.canGoToNewerHistoryDay,
                    onPrevious: { model.showPreviousHistoryDay() },
                    onNext: { model.showNextHistoryDay() },
                    onRetry: {
                        Task { await model.loadYesterdayAIRecapIfNeeded(force: true) }
                    },
                    onOpenSettings: onOpenSettings
                )
                if !model.recentlyViewedBooks.isEmpty {
                    recentlyViewedSection(model.recentlyViewedBooks)
                }
                bookGrid(title: "Ajouts récents", books: model.recentlyImportedBooks)
            }
            .padding(.horizontal, LoreTheme.pageMargin).padding(.bottom, 32)
        }
        .background(LoreTheme.canvas)
        .task(id: model.yesterdayRecapRequestID) {
            await model.loadYesterdayAIRecapIfNeeded()
        }
    }

    private var libraryContent: some View {
        @Bindable var model = model
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                librarySearchField

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
        .background(LoreTheme.canvas)
    }

    private var librarySearchField: some View {
        @Bindable var model = model
        return HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LoreTheme.secondaryInk)
                .accessibilityHidden(true)
            TextField("Titre ou auteur", text: $model.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Rechercher par titre ou auteur")
            if !model.searchText.isEmpty {
                Button("Effacer la recherche", systemImage: "xmark.circle.fill") {
                    model.searchText = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(LoreTheme.secondaryInk)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, model.searchText.isEmpty ? 13 : 2)
        .frame(minHeight: 44)
        .background(LoreTheme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func resumeSection(_ books: [BookRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprendre").font(.title3.weight(.semibold))
            ForEach(books) { book in
                HStack(spacing: 10) {
                    Button { Task { await model.open(book) } } label: {
                        HStack(spacing: 14) {
                            trackedCover(book, width: 72)
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
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reprendre \(book.title)")
                    .accessibilityValue(resumeAccessibilityValue(for: book))

                    if model.openingBookID == book.id {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }

                    resumeActionButton(
                        title: "Discuter avec \(book.title)",
                        systemImage: "sparkles"
                    ) {
                        discussionDraft = nil
                        discussionHighlight = nil
                        discussionBook = book
                    }
                }
                .contentShape(Rectangle())
                .accessibilityHint("Appui long pour les détails et les autres actions du livre")
                .contextMenu { bookContextMenu(for: book) }
            }
        }
    }

    private func resumeActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(LoreTheme.ink)
            .frame(width: 44, height: 44)
            .background(LoreTheme.ink.opacity(0.08), in: Circle())
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

    private func recentlyViewedSection(_ books: [BookRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Derniers livres lus")
                .font(.title3.weight(.semibold))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(books) { book in
                    coverActions(book)
                    .contextMenu { bookContextMenu(for: book) }
                }
            }
        }
    }

    private func bookButton(_ book: BookRecord) -> some View {
        Button { Task { await model.open(book) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                trackedCover(book)
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
        .accessibilityHint("Appui long pour les détails et les autres actions du livre")
        .accessibilityElement(children: .contain)
        .contextMenu { bookContextMenu(for: book) }
    }

    private func coverActions(_ book: BookRecord) -> some View {
        Button { Task { await model.open(book) } } label: {
            trackedCover(book)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir \(book.title)")
        .accessibilityHint("Appui long pour les détails et les autres actions du livre")
    }

    @ViewBuilder
    private func bookContextMenu(for book: BookRecord) -> some View {
        Button("Détails du livre", systemImage: "info.circle") {
            presentDetails(for: book)
        }

        if !model.manualCollections.isEmpty {
            Menu("Collections", systemImage: "books.vertical") {
                ForEach(model.manualCollections) { collection in
                    Button {
                        model.toggleMembership(of: book, in: collection)
                    } label: {
                        Label(collection.name, systemImage: model.isMember(book, of: collection) ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }

        if book.readingStatus == .inProgress {
            Button("Retirer de Reprendre", systemImage: "rectangle.badge.minus") {
                model.setHiddenFromResume(true, for: book)
            }
        }

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
            do {
                selectedHighlights = try model.highlights(for: book)
                highlightsLoadError = nil
            } catch {
                selectedHighlights = []
                highlightsLoadError = (error as? LocalizedError)?.errorDescription
                    ?? "Les passages surlignés n’ont pas pu être chargés."
            }
            highlightsBook = book
        }

        Button("Discuter avec le livre", systemImage: "sparkles") {
            discussionDraft = nil
            discussionHighlight = nil
            discussionBook = book
        }
    }

    private func presentPendingHighlightDiscussion() {
        guard let pending = pendingHighlightDiscussion else { return }
        pendingHighlightDiscussion = nil
        discussionDraft = "Aide-moi à comprendre ce passage sans dépasser ma progression de lecture."
        discussionHighlight = pending.highlight
        discussionBook = pending.book
    }

    private func presentDetails(for book: BookRecord) {
        detailBook = book
    }

    private func presentHighlights(for book: BookRecord) {
        do {
            selectedHighlights = try model.highlights(for: book)
            highlightsLoadError = nil
        } catch {
            selectedHighlights = []
            highlightsLoadError = (error as? LocalizedError)?.errorDescription
                ?? "Les passages surlignés n’ont pas pu être chargés."
        }
        highlightsBook = book
    }

    private func presentPendingDetailDestination() {
        guard let destination = pendingDetailDestination else { return }
        pendingDetailDestination = nil
        switch destination {
        case let .reader(book):
            Task { await model.open(book) }
        case let .highlights(book):
            presentHighlights(for: book)
        case let .discussion(book):
            discussionDraft = nil
            discussionHighlight = nil
            discussionBook = book
        }
    }

    private func trackedCover(_ book: BookRecord, width: CGFloat? = nil) -> some View {
        BookCoverView(book: book)
            .frame(width: width)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                model.recordCoverFrame(frame, for: book.id)
            }
    }
}

private extension UTType {
    static let epub = UTType(importedAs: "org.idpf.epub-container", conformingTo: .zip)
}

private struct PendingHighlightDiscussion {
    let book: BookRecord
    let highlight: ReaderHighlight
}

private enum PendingDetailDestination {
    case reader(BookRecord)
    case highlights(BookRecord)
    case discussion(BookRecord)
}
