import Foundation
import ReadiumShared
import SwiftData

@MainActor
final class HighlightRepository: HighlightStoring {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(context: ModelContext, save: ((ModelContext) throws -> Void)? = nil) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func highlights(for bookID: UUID) throws -> [ReaderHighlight] {
        var descriptor = FetchDescriptor<HighlightRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try context.fetch(descriptor).map(ReaderHighlight.init(record:))
    }

    func allHighlights() throws -> [ReaderHighlight] {
        var descriptor = FetchDescriptor<HighlightRecord>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try context.fetch(descriptor).map(ReaderHighlight.init(record:))
    }

    func addHighlight(bookID: UUID, locator: Locator, text: String, color: HighlightColor) throws -> ReaderHighlight {
        let stored = try HighlightLocatorCodec.encode(locator)
        let record = HighlightRecord(
            bookID: bookID,
            locatorJSON: stored.data,
            locatorSchemaVersion: stored.schemaVersion,
            text: text,
            colorRawValue: color.rawValue
        )
        context.insert(record)
        do {
            try saveContext(context)
            return try ReaderHighlight(record: record)
        } catch {
            context.delete(record)
            throw error
        }
    }

    func deleteHighlight(id: UUID, bookID: UUID) throws {
        let descriptor = FetchDescriptor<HighlightRecord>(
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

    func updateHighlightNote(id: UUID, bookID: UUID, note: String?) throws -> ReaderHighlight {
        let descriptor = FetchDescriptor<HighlightRecord>(
            predicate: #Predicate { $0.id == id && $0.bookID == bookID }
        )
        guard let record = try context.fetch(descriptor).first else {
            throw HighlightStoreError.missingHighlight
        }
        let previousNote = record.note
        let normalized = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.note = normalized?.isEmpty == false ? normalized : nil
        do {
            try saveContext(context)
            return try ReaderHighlight(record: record)
        } catch {
            record.note = previousNote
            // Revert only this edit. A context-wide rollback could discard an
            // unrelated pending reader mutation owned by the shared context.
            throw error
        }
    }

    func deleteHighlights(for bookID: UUID, save: Bool = true) throws {
        let descriptor = FetchDescriptor<HighlightRecord>(
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

private extension ReaderHighlight {
    init(record: HighlightRecord) throws {
        guard let color = HighlightColor(rawValue: record.colorRawValue) else {
            throw HighlightStoreError.invalidColor
        }
        self.init(
            id: record.id,
            bookID: record.bookID,
            locator: try HighlightLocatorCodec.decode(
                StoredHighlightLocator(data: record.locatorJSON, schemaVersion: record.locatorSchemaVersion)
            ),
            text: record.text,
            createdAt: record.createdAt,
            color: color,
            note: record.note
        )
    }
}

enum HighlightStoreError: LocalizedError {
    case missingHighlight
    case invalidColor
    case unsupportedLocatorSchemaVersion
    case invalidLocator

    var errorDescription: String? {
        switch self {
        case .missingHighlight:
            "Ce surlignage n’existe plus. Fermez puis rouvrez la liste pour l’actualiser."
        case .invalidColor, .unsupportedLocatorSchemaVersion, .invalidLocator:
            "Ce surlignage est illisible, mais vos autres annotations sont conservées."
        }
    }
}
