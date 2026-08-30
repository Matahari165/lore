import Foundation
import SwiftData

@MainActor
final class BookRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func add(_ book: BookRecord) throws {
        context.insert(book)
        do {
            try context.save()
        } catch {
            context.delete(book)
            throw error
        }
    }

    func books() throws -> [BookRecord] {
        var descriptor = FetchDescriptor<BookRecord>()
        descriptor.sortBy = [SortDescriptor(\.importedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    func book(id: UUID) throws -> BookRecord? {
        var descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func saveProgress(
        for bookID: UUID,
        locatorJSON: Data,
        progression: Double?,
        updatedAt: Date = .now
    ) throws {
        guard let book = try book(id: bookID) else {
            throw BookRepositoryError.bookNotFound
        }
        book.lastLocatorJSON = locatorJSON
        book.lastProgression = progression.map { min(max($0, 0), 1) }
        book.progressUpdatedAt = updatedAt
        try context.save()
    }

    func delete(_ book: BookRecord) throws {
        context.delete(book)
        try context.save()
    }
}

enum BookRepositoryError: LocalizedError, Equatable {
    case bookNotFound

    var errorDescription: String? {
        "Le livre demandé n’existe plus dans la bibliothèque."
    }
}
