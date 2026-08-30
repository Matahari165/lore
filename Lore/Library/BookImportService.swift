import Foundation

@MainActor
final class BookImportService {
    private let repository: BookRepository
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService

    init(
        repository: BookRepository,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.publicationService = publicationService
    }

    func importEPUB(from sourceURL: URL) async throws -> BookRecord {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let opened = try await publicationService.openEPUB(at: sourceURL)
        let bookID = UUID()
        let relativePath = try fileStore.importEPUB(from: sourceURL, bookID: bookID)

        do {
            let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
            let book = BookRecord(
                id: bookID,
                title: opened.title?.nonEmpty ?? fallbackTitle,
                author: opened.author?.nonEmpty,
                coverData: opened.coverData,
                relativeFilePath: relativePath,
                mediaType: opened.mediaType?.string ?? "application/epub+zip"
            )
            try repository.add(book)
            return book
        } catch {
            try? fileStore.removeBookFile(at: relativePath)
            throw error
        }
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
