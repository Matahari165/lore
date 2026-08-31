import Foundation
import ReadiumShared
import SwiftData

@MainActor
final class VocabularyRepository: VocabularyStoring {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(context: ModelContext, save: ((ModelContext) throws -> Void)? = nil) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func vocabulary(for bookID: UUID) throws -> [VocabularyItem] {
        var descriptor = FetchDescriptor<VocabularyRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try context.fetch(descriptor).map(VocabularyItem.init(record:))
    }

    func allVocabulary() throws -> [VocabularyItem] {
        var descriptor = FetchDescriptor<VocabularyRecord>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try context.fetch(descriptor).map(VocabularyItem.init(record:))
    }

    func addVocabulary(bookID: UUID, locator: Locator, text: String) throws -> VocabularyItem {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw VocabularyStoreError.emptyText }
        let stored = try HighlightLocatorCodec.encode(locator)
        let record = VocabularyRecord(
            bookID: bookID,
            locatorJSON: stored.data,
            locatorSchemaVersion: stored.schemaVersion,
            text: normalizedText
        )
        context.insert(record)
        do {
            try saveContext(context)
            return try VocabularyItem(record: record)
        } catch {
            context.delete(record)
            throw error
        }
    }

    func deleteVocabulary(id: UUID, bookID: UUID) throws {
        let descriptor = FetchDescriptor<VocabularyRecord>(
            predicate: #Predicate { $0.id == id && $0.bookID == bookID }
        )
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteVocabulary(for bookID: UUID, save: Bool = true) throws {
        let descriptor = FetchDescriptor<VocabularyRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        try context.fetch(descriptor).forEach(context.delete)
        guard save else { return }
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

private extension VocabularyItem {
    init(record: VocabularyRecord) throws {
        self.init(
            id: record.id,
            bookID: record.bookID,
            locator: try HighlightLocatorCodec.decode(
                StoredHighlightLocator(
                    data: record.locatorJSON,
                    schemaVersion: record.locatorSchemaVersion
                )
            ),
            text: record.text,
            createdAt: record.createdAt
        )
    }
}

enum VocabularyStoreError: LocalizedError, Equatable {
    case emptyText
    case unavailable

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "Le mot ou le passage sélectionné est vide."
        case .unavailable:
            "Le vocabulaire local est indisponible."
        }
    }
}
