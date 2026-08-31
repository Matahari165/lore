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
        let session: ReaderSessionController
    }

    private let repository: BookRepository
    private let sessionRepository: ReadingSessionRepository
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService
    private let importService: BookImportService

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
    private(set) var lastReconciliationReport: ImportReconciliationReport?

    init(
        repository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.fileStore = fileStore
        self.publicationService = publicationService
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

    var resumableBook: BookRecord? {
        books
            .filter { $0.lastLocatorJSON != nil }
            .sorted { ($0.progressUpdatedAt ?? .distantPast) > ($1.progressUpdatedAt ?? .distantPast) }
            .first
    }

    var recentlyImportedBooks: [BookRecord] {
        Array(books.sorted { $0.importedAt > $1.importedAt }.prefix(4))
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
                onError: { [weak self] error in self?.present(error) }
            )
            readerPresentation = ReaderPresentation(id: book.id, title: book.title, session: session)
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
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Une erreur inattendue est survenue."
    }
}
