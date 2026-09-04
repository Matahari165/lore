import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    enum SmartCollection: Hashable, Identifiable {
        case inProgress, finished, notStarted, recent, year(Int), author(String)
        var id: String {
            switch self {
            case .inProgress: "status-in-progress"
            case .finished: "status-finished"
            case .notStarted: "status-not-started"
            case .recent: "recent"
            case let .year(year): "year-\(year)"
            case let .author(author): "author-\(author)"
            }
        }
        var title: String {
            switch self {
            case .inProgress: "En cours"
            case .finished: "Terminés"
            case .notStarted: "Non commencés"
            case .recent: "Récents"
            case let .year(year): String(year)
            case let .author(author): author
            }
        }
    }

    struct BookDetailData: Equatable {
        let totalReadingTime: TimeInterval
        let firstReadAt: Date?
        let lastReadAt: Date?
        let highlightCount: Int
        let noteCount: Int
        let collectionNames: [String]
    }
    enum Filter: String, CaseIterable, Identifiable {
        case all, toRead, inProgress, finished
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "Tous"
            case .toRead: "À lire"
            case .inProgress: "En cours"
            case .finished: "Terminés"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent, title, author, progress
        var id: Self { self }
        var title: String {
            switch self {
            case .recent: "Ajout récent"
            case .title: "Titre"
            case .author: "Auteur"
            case .progress: "Progression"
            }
        }
    }

    struct ImportIssue: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let message: String
    }

    struct ImportSummary: Equatable {
        var imported = 0
        var duplicates = 0
        var completedFiles: [String] = []
        var issues: [ImportIssue] = []

        var message: String {
            var lines = ["\(imported) importé(s), \(duplicates) déjà présent(s)."]
            lines.append(contentsOf: completedFiles)
            if !issues.isEmpty {
                lines.append(contentsOf: issues.map { "\($0.filename) : \($0.message)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    struct ReaderPresentation: Identifiable {
        let id: UUID
        let title: String
        let author: String?
        let readingStage: LoreAIReadingStage
        let conversationRepository: AIConversationRepository?
        let session: ReaderSessionController
        let sourceFrame: CGRect?
        let initialHighlight: ReaderHighlight?

        init(
            id: UUID,
            title: String,
            author: String? = nil,
            readingStage: LoreAIReadingStage = .inProgress,
            conversationRepository: AIConversationRepository? = nil,
            sourceFrame: CGRect? = nil,
            initialHighlight: ReaderHighlight? = nil,
            session: ReaderSessionController
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.readingStage = readingStage
            self.conversationRepository = conversationRepository
            self.sourceFrame = sourceFrame
            self.initialHighlight = initialHighlight
            self.session = session
        }
    }

    private let repository: BookRepository
    private let sessionRepository: ReadingSessionRepository
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService
    private let importService: BookImportService
    private let recapEngine: DailyReadingRecapEngine
    private let aiService: any LoreAIService
    private let yesterdayRecapCache: YesterdayReadingRecapCache
    let conversationRepository: AIConversationRepository?

    var books: [BookRecord] = []
    var manualCollections: [ManualCollectionRecord] = []
    var isImporting = false
    var openingBookID: UUID?
    var errorMessage: String?
    var readerPresentation: ReaderPresentation?
    var searchText = ""
    var filter: Filter = .all
    var sort: Sort = .recent
    var sortAscending = false
    var importSummary: ImportSummary?
    var currentImportProgress: String?
    private var pendingImportURLs: [URL] = []
    private(set) var yesterdayReadingSummaryState: YesterdayReadingSummaryState = .noReading
    private(set) var lastReconciliationReport: ImportReconciliationReport?
    private var latestSessionActivityByBookID: [UUID: Date] = [:]
    private var coverFramesByBookID: [UUID: CGRect] = [:]
    private var yesterdayActivity: YesterdayActivity?
    // Historique multi-jours adossé à `YesterdayReadingRecapCache.recapHistory()`
    // (dictionnaire par jour + fingerprint, 30 jours, migration v1 incluse).
    // nil signifie « veille » ; toute autre valeur est un début de jour local.
    var selectedHistoryDay: Date?
    private var collectionIDsByBookID: [UUID: Set<UUID>] = [:]

    init(
        repository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService,
        conversationRepository: AIConversationRepository? = nil,
        aiService: any LoreAIService = OpenAIResponsesClient(),
        yesterdayRecapCache: YesterdayReadingRecapCache = .init()
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.fileStore = fileStore
        self.publicationService = publicationService
        self.conversationRepository = conversationRepository
        self.aiService = aiService
        self.yesterdayRecapCache = yesterdayRecapCache
        recapEngine = DailyReadingRecapEngine(
            store: UserDefaultsReadingRecapStateStore(),
            sessionRepository: sessionRepository
        )
        importService = BookImportService(
            repository: repository,
            fileStore: fileStore,
            publicationService: publicationService
        )
        do {
            let report = try importService.reconcileImports()
            lastReconciliationReport = report
            if !report.recoveryRequiredBookIDs.isEmpty || !report.files.missingBookIDs.isEmpty {
                errorMessage = "Certains livres nécessitent une nouvelle importation. Leurs données ont été conservées."
            } else if !report.files.quarantinedBookIDs.isEmpty || !report.files.orphanBookIDs.isEmpty {
                errorMessage = "Lore a isolé ou signalé des fichiers sans entrée de bibliothèque, sans les supprimer."
            }
        } catch {
            present(error)
        }
        reload()
    }

    /// The small resume queue shown on Accueil. A completion flag always wins over
    /// a saved position, so finished books never reappear here.
    var resumableBooks: [BookRecord] {
        let candidates = books.filter {
            $0.readingStatus == .inProgress && !$0.isHiddenFromResume
        }
        return Array(candidates.sorted { lhs, rhs in
            let lhsActivity = recentActivityDate(for: lhs) ?? lhs.importedAt
            let rhsActivity = recentActivityDate(for: rhs) ?? rhs.importedAt
            if lhsActivity != rhsActivity { return lhsActivity > rhsActivity }

            // Keep ordering deterministic when two books were touched at the same
            // instant (for example after a restored database import).
            let lhsProgress = lhs.progressUpdatedAt ?? .distantPast
            let rhsProgress = rhs.progressUpdatedAt ?? .distantPast
            if lhsProgress != rhsProgress { return lhsProgress > rhsProgress }
            return lhs.id.uuidString < rhs.id.uuidString
        }.prefix(4))
    }

    func recentActivityDate(for book: BookRecord) -> Date? {
        [book.progressUpdatedAt, latestSessionActivityByBookID[book.id]]
            .compactMap { $0 }
            .max()
    }

    var recentlyImportedBooks: [BookRecord] {
        // Two complete rows keep the home screen useful on iPhone while still
        // respecting the actual number of imported books.
        Array(books.sorted { $0.importedAt > $1.importedAt }.prefix(6))
    }

    var recentlyViewedBooks: [BookRecord] {
        Array(books.filter { $0.readingStatus == .finished }
        .sorted { lhs, rhs in
            let left = lhs.finishedAt ?? .distantPast
            let right = rhs.finishedAt ?? .distantPast
            if left != right { return left > right }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .prefix(3)
        )
    }

    func recordCoverFrame(_ frame: CGRect, for bookID: UUID) {
        guard frame.width > 0, frame.height > 0 else { return }
        coverFramesByBookID[bookID] = frame
    }

    var yesterdayRecapRequestID: String {
        yesterdayActivity?.fingerprint ?? "no-reading-yesterday"
    }

    // MARK: - Navigation historique du bloc Hier

    private var yesterdayStart: Date {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    var historyDayStart: Date {
        selectedHistoryDay ?? yesterdayStart
    }

    var isShowingHistoryPastDay: Bool {
        selectedHistoryDay != nil
    }

    var historyDayTitle: String {
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM"
        var formatted = formatter.string(from: historyDayStart)
        // « 1 sept. » devient « 1er sept. » comme dans l'exemple produit.
        if calendar.component(.day, from: historyDayStart) == 1 {
            formatted = formatted.replacingOccurrences(of: " 1 ", with: " 1er ")
        }
        if !isShowingHistoryPastDay {
            return "Hier · \(formatted)"
        }
        return formatted
    }

    var canGoToNewerHistoryDay: Bool {
        isShowingHistoryPastDay
    }

    var canGoToOlderHistoryDay: Bool {
        // Fenêtre alignée sur le cache (30 jours max).
        let calendar = Calendar.autoupdatingCurrent
        let depth = calendar.dateComponents([.day], from: historyDayStart, to: yesterdayStart).day ?? 0
        return depth < (YesterdayReadingRecapCache.maxKeptDays - 1)
    }

    /// État à afficher pour le jour sélectionné : veille = état live existant,
    /// jour passé = résumé en cache (`recapHistory`) ou repli gracieux.
    var historyRecapState: YesterdayReadingSummaryState {
        guard isShowingHistoryPastDay else { return yesterdayReadingSummaryState }
        let calendar = Calendar.autoupdatingCurrent
        if let entry = yesterdayRecapCache.recapHistory().first(where: {
            calendar.isDate($0.dayStart, inSameDayAs: historyDayStart)
        }) {
            return .available(activityLine: historyDayTitle, markdown: entry.markdown)
        }
        return .noReading
    }

    func showPreviousHistoryDay() {
        let calendar = Calendar.autoupdatingCurrent
        guard let previous = calendar.date(byAdding: .day, value: -1, to: historyDayStart) else { return }
        selectedHistoryDay = previous
    }

    func showNextHistoryDay() {
        let calendar = Calendar.autoupdatingCurrent
        guard isShowingHistoryPastDay else { return }
        guard let next = calendar.date(byAdding: .day, value: 1, to: historyDayStart) else { return }
        if calendar.isDate(next, inSameDayAs: yesterdayStart) || next > yesterdayStart {
            selectedHistoryDay = nil
        } else {
            selectedHistoryDay = next
        }
    }

    var visibleBooks: [BookRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = books.filter { book in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .toRead: book.readingStatus == .toRead
            case .inProgress: book.readingStatus == .inProgress
            case .finished: book.readingStatus == .finished
            }
            let matchesSearch = query.isEmpty
                || book.title.localizedCaseInsensitiveContains(query)
                || (book.author?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesFilter && matchesSearch
        }
        return filtered.sorted { lhs, rhs in
            let comparison: ComparisonResult = switch sort {
            case .recent: lhs.importedAt.compare(rhs.importedAt)
            case .title: lhs.title.localizedStandardCompare(rhs.title)
            case .author: (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "")
            case .progress:
                if (lhs.lastProgression ?? 0) < (rhs.lastProgression ?? 0) { .orderedAscending }
                else if (lhs.lastProgression ?? 0) > (rhs.lastProgression ?? 0) { .orderedDescending }
                else { .orderedSame }
            }
            if comparison == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var smartCollections: [SmartCollection] {
        var values: [SmartCollection] = [.inProgress, .finished, .notStarted, .recent]
        values += Set(books.compactMap(\.readingYear)).sorted(by: >).map(SmartCollection.year)
        let authors = Dictionary(grouping: books.compactMap { Self.trimmedAuthor($0.author) }) {
            Self.normalizedAuthor($0)
        }.values.compactMap(\.first)
        values += authors.sorted().map(SmartCollection.author)
        return values
    }

    func books(in smartCollection: SmartCollection) -> [BookRecord] {
        if smartCollection == .recent {
            return Array(books.sorted { $0.importedAt > $1.importedAt }.prefix(12))
        }
        let selected: [BookRecord] = switch smartCollection {
        case .inProgress: books.filter { $0.readingStatus == .inProgress }
        case .finished: books.filter { $0.readingStatus == .finished }
        case .notStarted: books.filter { $0.readingStatus == .toRead }
        case .recent: []
        case let .year(year): books.filter { $0.readingYear == year }
        case let .author(author):
            books.filter { Self.normalizedAuthor(Self.trimmedAuthor($0.author) ?? "") == Self.normalizedAuthor(author) }
        }
        return selected.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func trimmedAuthor(_ author: String?) -> String? {
        guard let value = author?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func normalizedAuthor(_ author: String) -> String {
        author.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    func books(in collection: ManualCollectionRecord) -> [BookRecord] {
        books.filter { collectionIDsByBookID[$0.id, default: []].contains(collection.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func isMember(_ book: BookRecord, of collection: ManualCollectionRecord) -> Bool {
        collectionIDsByBookID[book.id, default: []].contains(collection.id)
    }

    func createCollection(named name: String) {
        do { _ = try repository.createCollection(named: name); reload() }
        catch { present(error) }
    }

    func toggleMembership(of book: BookRecord, in collection: ManualCollectionRecord) {
        do {
            try repository.setMembership(!isMember(book, of: collection), bookID: book.id, collectionID: collection.id)
            reload()
        } catch { present(error) }
    }

    func deleteCollection(_ collection: ManualCollectionRecord) {
        do { try repository.deleteCollection(collection); reload() }
        catch { present(error) }
    }

    func importSelection(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            await importURLs(urls)
        } catch {
            if (error as? CocoaError)?.code == .userCancelled { return }
            present(error)
        }
    }

    func importURLs(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        if isImporting {
            pendingImportURLs.append(contentsOf: urls)
            return
        }

        isImporting = true
        defer { isImporting = false }
        var summary = ImportSummary()
        var batch = urls
        while !batch.isEmpty {
            for sourceURL in batch {
                await importSource(sourceURL, into: &summary)
            }
            batch = pendingImportURLs
            pendingImportURLs.removeAll()
        }
        reload()
        importSummary = summary
    }

    private func importSource(_ sourceURL: URL, into summary: inout ImportSummary) async {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
            currentImportProgress = nil
        }

        do {
            let candidates = try EPUBImportSourceResolver.epubURLs(from: sourceURL)
            guard !candidates.isEmpty else {
                summary.issues.append(ImportIssue(
                    filename: sourceURL.lastPathComponent,
                    message: "Ce dossier ne contient aucun fichier EPUB."
                ))
                return
            }
            for url in candidates {
                currentImportProgress = "Import de \(url.lastPathComponent)…"
                do {
                    switch try await importService.importEPUB(from: url) {
                    case .imported:
                        summary.imported += 1
                        summary.completedFiles.append("\(url.lastPathComponent) : importé.")
                    case .alreadyImported:
                        summary.duplicates += 1
                        summary.completedFiles.append("\(url.lastPathComponent) : déjà présent.")
                    }
                } catch is CancellationError {
                    summary.issues.append(ImportIssue(
                        filename: url.lastPathComponent,
                        message: "Import interrompu. Vous pouvez réessayer sans créer de doublon."
                    ))
                    return
                } catch {
                    summary.issues.append(ImportIssue(
                        filename: url.lastPathComponent,
                        message: (error as? LocalizedError)?.errorDescription ?? "Import impossible."
                    ))
                }
            }
        } catch {
            summary.issues.append(ImportIssue(
                filename: sourceURL.lastPathComponent,
                message: (error as? LocalizedError)?.errorDescription ?? "Cette source ne peut pas être parcourue."
            ))
        }
    }

    func open(_ book: BookRecord, at highlight: ReaderHighlight? = nil) async {
        guard openingBookID == nil else { return }
        openingBookID = book.id
        defer { openingBookID = nil }

        do {
            let fileURL = try fileStore.fileURL(for: book.relativeFilePath)
            let session = try await ReaderSessionController.make(
                bookID: book.id,
                fileURL: fileURL,
                publicationService: publicationService,
                progressStore: repository,
                readingActivity: ReadingActivityController(
                    bookID: book.id,
                    store: sessionRepository,
                    onError: { [weak self] error in self?.present(error) }
                ),
                recapEngine: recapEngine,
                onError: { [weak self] error in self?.present(error) }
            )
            readerPresentation = ReaderPresentation(
                id: book.id,
                title: book.title,
                author: book.author,
                readingStage: book.readingStatus.loreAIStage,
                conversationRepository: conversationRepository,
                sourceFrame: coverFramesByBookID[book.id],
                initialHighlight: highlight,
                session: session
            )
        } catch {
            present(error)
        }
    }

    func closeReader() async {
        guard let presentation = readerPresentation else { return }
        do {
            try await presentation.session.close()
            readerPresentation = nil
            reload()
        } catch {
            present(error)
        }
    }

    func reload() {
        do {
            books = try repository.books().filter { $0.importState == .ready }
            manualCollections = try repository.collections()
            collectionIDsByBookID = try repository.collectionMemberships().reduce(into: [:]) { result, item in
                result[item.bookID, default: []].insert(item.collectionID)
            }
            let sessions = try sessionRepository.sessions()
            latestSessionActivityByBookID = sessions.reduce(into: [:]) { latest, session in
                guard session.lastActivityAt > (latest[session.bookID] ?? .distantPast) else { return }
                latest[session.bookID] = session.lastActivityAt
            }
            updateYesterdayActivity(from: sessions)
        } catch {
            present(error)
        }
    }

    func loadYesterdayAIRecapIfNeeded(force: Bool = false) async {
        guard let activity = yesterdayActivity else {
            yesterdayReadingSummaryState = .noReading
            return
        }

        if let cached = yesterdayRecapCache.recap(
            dayStart: activity.dayStart,
            fingerprint: activity.fingerprint
        ) {
            yesterdayReadingSummaryState = .available(
                activityLine: activity.activityLine,
                markdown: cached
            )
            return
        }

        if case .loading = yesterdayReadingSummaryState { return }
        if !force {
            switch yesterdayReadingSummaryState {
            case .loading, .available, .missingAPIKey, .failed:
                return
            case .noReading, .awaiting:
                break
            }
        }

        do {
            let storedKey = try KeychainOpenAIAPIKeyStore().loadAPIKey()
            guard let storedKey,
                  !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                yesterdayReadingSummaryState = .missingAPIKey(activityLine: activity.activityLine)
                return
            }
        } catch {
            yesterdayReadingSummaryState = .failed(
                activityLine: activity.activityLine,
                message: "La clé OpenAI ne peut pas être lue pour le moment."
            )
            return
        }

        yesterdayReadingSummaryState = .loading(activityLine: activity.activityLine)

        do {
            let store = UserDefaultsReadingRecapStateStore()
            // L'extraction conserve tout l'intervalle first…last. Les grands
            // intervalles sont ensuite résumés par morceaux afin qu'aucune page
            // intermédiaire ne soit silencieusement supprimée.
            let extractor = ReadiumReadingRecapContextExtractor(maximumCharacters: .max)
            var contexts: [ReaderAIReadingRecapContext] = []

            for book in activity.books {
                try Task.checkCancellation()
                guard let checkpoint = try store.checkpoint(
                    for: book.id,
                    localDayStart: activity.dayStart
                ) else { continue }

                do {
                    let first = try LocatorPersistenceCodec.decode(
                        checkpoint.firstLocator.storedLocator
                    ).locator
                    let last = try LocatorPersistenceCodec.decode(
                        checkpoint.lastLocator.storedLocator
                    ).locator
                    let fileURL = try fileStore.fileURL(for: book.relativeFilePath)
                    let publication = try await publicationService.openEPUB(at: fileURL).publication
                    contexts.append(try await extractor.extract(
                        from: publication,
                        firstLocator: first,
                        lastLocator: last
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A missing or malformed book must not hide a valid recap
                    // from another book read on the same day.
                    continue
                }
            }

            guard !contexts.isEmpty else {
                yesterdayReadingSummaryState = .failed(
                    activityLine: activity.activityLine,
                    message: "Le texte lu hier n’est pas disponible pour créer le résumé."
                )
                return
            }

            var partialRecaps: [String] = []
            for context in contexts {
                for chunk in Self.recapChunks(context.excerpt) {
                    try Task.checkCancellation()
                    partialRecaps.append(try await aiService.recap(PreviousReadingContext(
                        title: context.title,
                        author: context.author,
                        chapterTitles: context.chapterTitles,
                        excerpt: chunk,
                        lastReadPositionDescription: context.lastReadPositionDescription
                    )))
                }
            }
            let answer = try await synthesizeRecaps(
                partialRecaps,
                title: contexts.map(\.title).joined(separator: " · "),
                chapterTitles: contexts.flatMap(\.chapterTitles),
                lastReadPositionDescription: contexts.last?.lastReadPositionDescription
            )
            let conciseAnswer = Self.conciseRecap(answer)

            try? yesterdayRecapCache.save(
                conciseAnswer,
                dayStart: activity.dayStart,
                fingerprint: activity.fingerprint
            )
            for book in activity.books {
                try? recapEngine.markShown(for: book.id, at: .now, completion: .delivered)
            }
            yesterdayReadingSummaryState = .available(
                activityLine: activity.activityLine,
                markdown: conciseAnswer
            )
        } catch is CancellationError {
            yesterdayReadingSummaryState = .awaiting(activityLine: activity.activityLine)
        } catch {
            yesterdayReadingSummaryState = .failed(
                activityLine: activity.activityLine,
                message: (error as? LocalizedError)?.errorDescription
                    ?? "Le résumé est indisponible pour le moment."
            )
        }
    }

    func setFinished(_ isFinished: Bool, for book: BookRecord) {
        do {
            try repository.setFinished(isFinished, for: book.id)
            reload()
        } catch {
            present(error)
        }
    }

    func setHiddenFromResume(_ isHidden: Bool, for book: BookRecord) {
        do {
            try repository.setHiddenFromResume(isHidden, for: book.id)
            reload()
        } catch {
            present(error)
        }
    }

    func finish(_ book: BookRecord, rating: Int?, readingYear: Int) {
        do {
            try repository.finish(bookID: book.id, rating: rating, readingYear: readingYear)
            reload()
        } catch {
            present(error)
        }
    }

    func highlights(for book: BookRecord) throws -> [ReaderHighlight] {
        try repository.highlights(for: book.id)
    }

    func highlightGroups() throws -> [BookHighlightGroup] {
        let allHighlights = try repository.allHighlights()
        let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        return Dictionary(grouping: allHighlights, by: \.bookID).compactMap { bookID, highlights in
            guard let book = booksByID[bookID] else { return nil }
            return BookHighlightGroup(
                bookID: bookID,
                title: book.title,
                author: book.author,
                highlights: highlights
            )
        }
    }

    func updateNote(_ note: String?, for highlight: ReaderHighlight) -> ReaderHighlight? {
        do {
            return try repository.updateHighlightNote(
                id: highlight.id,
                bookID: highlight.bookID,
                note: note
            )
        } catch {
            present(error)
            return nil
        }
    }

    func detailData(for bookID: UUID, now: Date = .now) throws -> BookDetailData {
        guard try repository.book(id: bookID) != nil else {
            throw BookRepositoryError.bookNotFound
        }
        let sessions = try sessionRepository.sessions(for: bookID)
        let highlights = try repository.highlights(for: bookID)
        let firstReadAt = sessions.first?.startedAt
        let totalReadingTime: TimeInterval
        if let firstReadAt {
            totalReadingTime = ReadingSessionDuration.total(
                sessions,
                in: DateInterval(start: firstReadAt, end: max(now, firstReadAt)),
                now: now,
                inactivityTimeout: ReadingActivityPolicy.defaultInactivityTimeout
            )
        } else {
            totalReadingTime = 0
        }
        let lastReadAt = sessions.map { session in
            min(now, session.endedAt ?? session.lastActivityAt)
        }.max()
        let collectionNames = manualCollections
            .filter { collectionIDsByBookID[bookID, default: []].contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return BookDetailData(
            totalReadingTime: totalReadingTime,
            firstReadAt: firstReadAt,
            lastReadAt: lastReadAt,
            highlightCount: highlights.count,
            noteCount: highlights.filter { !($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count,
            collectionNames: collectionNames
        )
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Une erreur inattendue est survenue."
    }

    private func updateYesterdayActivity(from sessions: [ReadingSessionRecord]) {
        let previousFingerprint = yesterdayActivity?.fingerprint
        guard let activity = makeYesterdayActivity(from: sessions) else {
            yesterdayActivity = nil
            yesterdayReadingSummaryState = .noReading
            return
        }
        yesterdayActivity = activity

        if let cached = yesterdayRecapCache.recap(
            dayStart: activity.dayStart,
            fingerprint: activity.fingerprint
        ) {
            yesterdayReadingSummaryState = .available(
                activityLine: activity.activityLine,
                markdown: cached
            )
        } else if previousFingerprint != activity.fingerprint {
            yesterdayReadingSummaryState = .awaiting(activityLine: activity.activityLine)
        }
    }

    private func makeYesterdayActivity(from sessions: [ReadingSessionRecord]) -> YesterdayActivity? {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        let interval = DateInterval(start: yesterday, end: today)
        let matching = sessions.filter { session in
            let end = session.endedAt ?? session.lastActivityAt
            return session.startedAt < interval.end && end > interval.start
        }
        guard !matching.isEmpty else { return nil }

        let duration = ReadingSessionDuration.total(
            matching,
            in: interval,
            now: today,
            inactivityTimeout: ReadingActivityPolicy.defaultInactivityTimeout
        )
        let titles = Set(matching.compactMap { session in
            books.first(where: { $0.id == session.bookID })?.title
        }).sorted()
        let minutes = max(1, Int((duration / 60).rounded()))
        let durationText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let activityLine: String
        if titles.isEmpty {
            activityLine = "Vous avez lu \(durationText) hier."
        } else {
            activityLine = "Vous avez lu \(durationText) hier dans "
                + ListFormatter.localizedString(byJoining: titles) + "."
        }

        let matchingBookIDs = Set(matching.map(\.bookID))
        let matchingBooks = books.compactMap { book -> YesterdayBook? in
            guard matchingBookIDs.contains(book.id) else { return nil }
            let latest = matching
                .filter { $0.bookID == book.id }
                .map(\.lastActivityAt)
                .max() ?? .distantPast
            return YesterdayBook(
                id: book.id,
                title: book.title,
                relativeFilePath: book.relativeFilePath,
                lastActivityAt: latest
            )
        }.sorted { $0.lastActivityAt > $1.lastActivityAt }

        let fingerprint = matching.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id.uuidString):\($0.lastActivityAt.timeIntervalSinceReferenceDate):\($0.endedAt?.timeIntervalSinceReferenceDate ?? -1)"
        }.joined(separator: "|")

        return YesterdayActivity(
            dayStart: yesterday,
            exactDuration: duration,
            activityLine: activityLine,
            books: matchingBooks,
            fingerprint: fingerprint
        )
    }

    private static func conciseRecap(_ source: String) -> String {
        let lines = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var bullets = lines.filter {
            $0.hasPrefix("-") || $0.hasPrefix("•") || $0.range(
                of: #"^\d+[\.)]\s"#,
                options: .regularExpression
            ) != nil
        }
        let resumeLine = lines.first {
            $0.localizedCaseInsensitiveContains("où reprendre")
        }

        if bullets.isEmpty {
            var sentences: [String] = []
            source.enumerateSubstrings(
                in: source.startIndex..<source.endIndex,
                options: [.bySentences, .substringNotRequired]
            ) { _, range, _, stop in
                let sentence = source[range]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                if sentences.count == 5 { stop = true }
            }
            bullets = sentences.map { "- \($0)" }
        }

        let shortBullets = bullets.prefix(6).map { line -> String in
            let normalized = line
                .replacingOccurrences(of: "•", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(normalized.prefix(240))
        }
        var output = shortBullets.joined(separator: "\n")
        if let resumeLine, !shortBullets.contains(resumeLine) {
            let normalizedResume = resumeLine.hasPrefix("-") ? resumeLine : "- \(resumeLine)"
            output += "\n\n" + String(normalizedResume.prefix(260))
        }
        return LoreAIResponseFormatter.bulleted(output.isEmpty ? String(source.prefix(900)) : output)
    }

    private static func recapChunks(_ source: String, maximumCharacters: Int = 15_000) -> [String] {
        guard maximumCharacters > 0 else { return [] }
        var chunks: [String] = []
        var start = source.startIndex
        while start < source.endIndex {
            let end = source.index(start, offsetBy: maximumCharacters, limitedBy: source.endIndex)
                ?? source.endIndex
            chunks.append(String(source[start..<end]))
            start = end
        }
        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func synthesizeRecaps(
        _ initial: [String],
        title: String,
        chapterTitles: [String],
        lastReadPositionDescription: String?
    ) async throws -> String {
        guard !initial.isEmpty else { throw LoreAIError.emptyContext }
        var level = initial
        while level.count > 1 {
            var groups: [[String]] = []
            var current: [String] = []
            var currentLength = 0
            for recap in level {
                if !current.isEmpty, currentLength + recap.count > 12_000 {
                    groups.append(current)
                    current = []
                    currentLength = 0
                }
                current.append(recap)
                currentLength += recap.count
            }
            if !current.isEmpty { groups.append(current) }

            var next: [String] = []
            for group in groups {
                try Task.checkCancellation()
                if group.count == 1 {
                    next.append(group[0])
                } else {
                    next.append(try await aiService.recap(PreviousReadingContext(
                        title: title,
                        author: nil,
                        chapterTitles: chapterTitles,
                        excerpt: group.joined(separator: "\n\n"),
                        lastReadPositionDescription: lastReadPositionDescription
                    )))
                }
            }
            guard next.count < level.count else { return next.joined(separator: "\n\n") }
            level = next
        }
        return level[0]
    }
}

private struct YesterdayActivity {
    let dayStart: Date
    let exactDuration: TimeInterval
    let activityLine: String
    let books: [YesterdayBook]
    let fingerprint: String
}

private struct YesterdayBook {
    let id: UUID
    let title: String
    let relativeFilePath: String
    let lastActivityAt: Date
}
