import Foundation

extension BookRepository: ReaderProgressStore {
    func storedLocator(for bookID: UUID) throws -> StoredLocator? {
        guard let book = try book(id: bookID), let data = book.lastLocatorJSON else { return nil }
        return StoredLocator(data: data, schemaVersion: book.locatorSchemaVersion)
    }

    func saveLocator(_ stored: StoredLocator, progression: Double?, for bookID: UUID) throws {
        try saveProgress(
            for: bookID,
            locatorJSON: stored.data,
            locatorSchemaVersion: stored.schemaVersion,
            progression: progression
        )
    }
}
