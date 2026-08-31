import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
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
        var issues: [ImportIssue] = []

        var message: String {
            var lines = ["\(imported) importé(s), \(duplicates) déjà présent(s)."]
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

        init(
            id: UUID,
            title: String,
            author: String? = nil,
            readingStage: LoreAIReadingStage = .inProgress,
            conversationRepository: AIConversationRepository? = nil,
            session: ReaderSessionController
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.readingStage = readingStage
            self.conversationRepository = conversationRepository
            self.session = session
        }
    }

    private let repository: BookRepository
    private let sessionRepository: ReadingSessionRepository
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService
    private let importService: BookImportService
    private let recapEngine: DailyReadingRecapEngine
    let conversationRepository: AIConversationRepository?

    var books: [BookRecord] = []
    var isImporting = false
    var openingBookID: UUID?
    var errorMessage: String?
    var readerPresentation: ReaderPresentation?
    var searchText = ""
    var filter: Filter = .all
    var sort: Sort = .recent
    var sortAscending = false
    var importSummary: ImportSummary?
    private(set) var yesterdayReadingSummary: String?
    private(set) var lastReconciliationReport: ImportReconciliationReport?
    private var latestSessionActivityByBookID: [UUID: Date] = [:]

    init(
        repository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService,
        conversationRepository: AIConversationRepository? = nil
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.fileStore = fileStore
        self.publicationService = publicationService
        self.conversationRepository = conversationRepository
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
        let candidates = books.filter { $0.readingStatus == .inProgress }
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

    /// Kept as a convenience for callers that only need the first queue entry.
    var resumableBook: BookRecord? {
        resumableBooks.first
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

    func importSelection(_ result: Result<[URL], Error>) async {
        guard !isImporting else { return }
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            isImporting = true
            defer { isImporting = false }
            var summary = ImportSummary()
            for url in urls {
                do {
                    switch try await importService.importEPUB(from: url) {
                    case .imported: summary.imported += 1
                    case .alreadyImported: summary.duplicates += 1
                    }
                } catch {
                    summary.issues.append(ImportIssue(
                        filename: url.lastPathComponent,
                        message: (error as? LocalizedError)?.errorDescription ?? "Import impossible"
                    ))
                }
            }
            reload()
            importSummary = summary
        } catch {
            present(error)
        }
    }

    func open(_ book: BookRecord) async {
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
            books = try repository.books()
            let sessions = try sessionRepository.sessions()
            latestSessionActivityByBookID = sessions.reduce(into: [:]) { latest, session in
                guard session.lastActivityAt > (latest[session.bookID] ?? .distantPast) else { return }
                latest[session.bookID] = session.lastActivityAt
            }
            yesterdayReadingSummary = makeYesterdaySummary(from: sessions)
        } catch {
            present(error)
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

    func finish(_ book: BookRecord, rating: Int?, readingYear: Int) {
        do {
            try repository.finish(bookID: book.id, rating: rating, readingYear: readingYear)
            reload()
        } catch {
            present(error)
        }
    }

    func highlights(for book: BookRecord) -> [ReaderHighlight] {
        do {
            return try repository.highlights(for: book.id)
        } catch {
            present(error)
            return []
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Une erreur inattendue est survenue."
    }

    private func makeYesterdaySummary(from sessions: [ReadingSessionRecord]) -> String? {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        let interval = DateInterval(start: yesterday, end: today)
        let matching = sessions.filter { session in
            let end = session.endedAt ?? session.lastActivityAt
            return session.startedAt < interval.end && end > interval.start
        }
        guard !matching.isEmpty else { return nil }

        let duration = matching.reduce(0.0) { total, session in
            let start = max(session.startedAt, interval.start)
            let end = min(session.endedAt ?? session.lastActivityAt, interval.end)
            return total + max(0, end.timeIntervalSince(start))
        }
        let titles = Set(matching.compactMap { session in
            books.first(where: { $0.id == session.bookID })?.title
        }).sorted()
        let minutes = max(1, Int((duration / 60).rounded()))
        guard !titles.isEmpty else { return "Vous avez lu \(minutes) min hier." }
        return "Vous avez lu \(minutes) min hier dans " + titles.joined(separator: ", ") + "."
    }
}
