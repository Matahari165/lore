import Foundation

extension BookRepository: ReaderProgressStore {
    func locatorData(for bookID: UUID) throws -> Data? {
        try book(id: bookID)?.lastLocatorJSON
    }

    func saveLocatorData(_ data: Data, progression: Double?, for bookID: UUID) throws {
        try saveProgress(for: bookID, locatorJSON: data, progression: progression)
    }
}
