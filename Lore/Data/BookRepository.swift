import Foundation
import ReadiumShared
import SwiftData

@MainActor
final class BookRepository {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void
    private let highlightRepository: HighlightRepository
    private let conversationRepository: AIConversationRepository?
    private let vocabularyRepository: VocabularyRepository?

    init(
        context: ModelContext,
        save: ((ModelContext) throws -> Void)? = nil,
        conversationRepository: AIConversationRepository? = nil,
        vocabularyRepository: VocabularyRepository? = nil
    ) {
        self.context = context
        saveContext = save ?? { try $0.save() }
        highlightRepository = HighlightRepository(context: context, save: save)
        self.conversationRepository = conversationRepository
        self.vocabularyRepository = vocabularyRepository
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

    func prepareRepair(
        bookID: UUID,
        stagingToken: UUID,
        metadata: ImportedEPUBMetadata
    ) throws {
        guard let book = try book(id: bookID) else { throw BookRepositoryError.bookNotFound }
        book.title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? book.title
        book.author = metadata.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        book.coverData = metadata.coverData
        book.mediaType = metadata.mediaType
        book.relativeFilePath = ""
        book.importState = .pending
        book.stagingToken = stagingToken
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
        try highlightRepository.deleteHighlights(for: book.id, save: false)
        try vocabularyRepository?.deleteVocabulary(for: book.id, save: false)
        try conversationRepository?.deleteConversations(for: book.id, save: false)
        context.delete(book)
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func setFinished(_ isFinished: Bool, for bookID: UUID, at date: Date = .now) throws {
        guard let book = try book(id: bookID) else { throw BookRepositoryError.bookNotFound }
        let previous = book.finishedAt
        book.finishedAt = isFinished ? (previous ?? date) : nil
        do {
            try saveContext(context)
        } catch {
            book.finishedAt = previous
            throw error
        }
    }

    func setHiddenFromResume(_ isHidden: Bool, for bookID: UUID) throws {
        guard let book = try book(id: bookID) else { throw BookRepositoryError.bookNotFound }
        let previous = book.isHiddenFromResume
        book.isHiddenFromResume = isHidden
        do {
            try saveContext(context)
        } catch {
            book.isHiddenFromResume = previous
            throw error
        }
    }

    /// Completes a book and stores the user's review metadata atomically.
    /// `rating` is optional so the user can explicitly choose to skip a note,
    /// while `readingYear` remains required for a completed reading record.
    func finish(
        bookID: UUID,
        rating: Int?,
        readingYear: Int,
        at date: Date = .now
    ) throws {
        guard let book = try book(id: bookID) else { throw BookRepositoryError.bookNotFound }
        guard rating.map({ (0...10).contains($0) }) ?? true else {
            throw BookRepositoryError.invalidRating
        }
        guard (1...9_999).contains(readingYear) else {
            throw BookRepositoryError.invalidReadingYear
        }

        let previousFinishedAt = book.finishedAt
        let previousRating = book.rating
        let previousReadingYear = book.readingYear
        book.finishedAt = previousFinishedAt ?? date
        book.rating = rating
        book.readingYear = readingYear
        do {
            try saveContext(context)
        } catch {
            book.finishedAt = previousFinishedAt
            book.rating = previousRating
            book.readingYear = previousReadingYear
            throw error
        }
    }
}

extension BookRepository: HighlightStoring {
    func highlights(for bookID: UUID) throws -> [ReaderHighlight] {
        try highlightRepository.highlights(for: bookID)
    }

    func addHighlight(bookID: UUID, locator: Locator, text: String, color: HighlightColor) throws -> ReaderHighlight {
        try highlightRepository.addHighlight(bookID: bookID, locator: locator, text: text, color: color)
    }

    func deleteHighlight(id: UUID, bookID: UUID) throws {
        try highlightRepository.deleteHighlight(id: id, bookID: bookID)
    }
}

extension BookRepository: VocabularyStoring {
    func vocabulary(for bookID: UUID) throws -> [VocabularyItem] {
        guard let vocabularyRepository else { throw VocabularyStoreError.unavailable }
        return try vocabularyRepository.vocabulary(for: bookID)
    }

    func allVocabulary() throws -> [VocabularyItem] {
        guard let vocabularyRepository else { throw VocabularyStoreError.unavailable }
        return try vocabularyRepository.allVocabulary()
    }

    func addVocabulary(bookID: UUID, locator: Locator, text: String) throws -> VocabularyItem {
        guard let vocabularyRepository else { throw VocabularyStoreError.unavailable }
        return try vocabularyRepository.addVocabulary(bookID: bookID, locator: locator, text: text)
    }

    func deleteVocabulary(id: UUID, bookID: UUID) throws {
        guard let vocabularyRepository else { throw VocabularyStoreError.unavailable }
        try vocabularyRepository.deleteVocabulary(id: id, bookID: bookID)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum BookRepositoryError: LocalizedError, Equatable {
    case bookNotFound
    case invalidRating
    case invalidReadingYear

    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            "Le livre demandé n’existe plus dans la bibliothèque."
        case .invalidRating:
            "La note doit être comprise entre 0 et 10."
        case .invalidReadingYear:
            "L’année de lecture n’est pas valide."
        }
    }
}
