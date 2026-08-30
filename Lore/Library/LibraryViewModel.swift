import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    struct ReaderPresentation: Identifiable {
        let id: UUID
        let title: String
        let session: ReaderSessionController
    }

    private let repository: BookRepository
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService
    private let importService: BookImportService

    var books: [BookRecord] = []
    var isImporting = false
    var openingBookID: UUID?
    var errorMessage: String?
    var readerPresentation: ReaderPresentation?
    private(set) var lastReconciliationReport: ImportReconciliationReport?

    init(
        repository: BookRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        self.repository = repository
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

    func importSelection(_ result: Result<URL, Error>) async {
        guard !isImporting else { return }
        do {
            let url = try result.get()
            isImporting = true
            defer { isImporting = false }
            _ = try await importService.importEPUB(from: url)
            reload()
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
