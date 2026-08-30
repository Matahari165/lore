import Foundation
import SwiftData

@MainActor
final class BookRepository {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(context: ModelContext, save: ((ModelContext) throws -> Void)? = nil) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func add(_ book: BookRecord) throws {
        context.insert(book)
        do {
            try saveContext(context)
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

    func book(contentSHA256: String) throws -> BookRecord? {
        var descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.contentSHA256 == contentSHA256 }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func pendingImports() throws -> [BookRecord] {
        let pending = BookImportState.pending.rawValue
        let descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.importStateRawValue == pending }
        )
        return try context.fetch(descriptor)
    }

    func confirmImport(bookID: UUID, relativeFilePath: String) throws {
        guard let book = try book(id: bookID) else {
            throw BookRepositoryError.bookNotFound
        }
        book.relativeFilePath = relativeFilePath
        book.importState = .ready
        book.stagingToken = nil
        try saveContext(context)
    }

    func markRecoveryRequired(bookID: UUID) throws {
        guard let book = try book(id: bookID) else {
            throw BookRepositoryError.bookNotFound
        }
        book.importState = .recoveryRequired
        try saveContext(context)
    }

    func saveProgress(
        for bookID: UUID,
        locatorJSON: Data,
        locatorSchemaVersion: Int?,
        progression: Double?,
        updatedAt: Date = .now
    ) throws {
        guard let book = try book(id: bookID) else {
            throw BookRepositoryError.bookNotFound
        }
        book.lastLocatorJSON = locatorJSON
        book.lastProgression = progression.map { min(max($0, 0), 1) }
        book.progressUpdatedAt = updatedAt
        book.locatorSchemaVersion = locatorSchemaVersion
        try saveContext(context)
    }

    func delete(_ book: BookRecord) throws {
        context.delete(book)
        try saveContext(context)
    }
}

enum BookRepositoryError: LocalizedError, Equatable {
    case bookNotFound

    var errorDescription: String? {
        "Le livre demandé n’existe plus dans la bibliothèque."
    }
}
