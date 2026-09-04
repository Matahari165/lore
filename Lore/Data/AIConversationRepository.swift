import Foundation
import SwiftData

@MainActor
final class AIConversationRepository {
    static let sourcesSchemaVersion = 1
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(context: ModelContext, save: ((ModelContext) throws -> Void)? = nil) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func conversation(for bookID: UUID) throws -> AIConversationRecord? {
        var descriptor = FetchDescriptor<AIConversationRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\AIConversationRecord.createdAt)]
        return try context.fetch(descriptor).first
    }

    func messages(for conversationID: UUID) throws -> [AIMessageRecord] {
        let descriptor = FetchDescriptor<AIMessageRecord>(
            predicate: #Predicate { $0.conversationID == conversationID }
        )
        return try context.fetch(descriptor).sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.createdAt < $1.createdAt
        }
    }

    /// Retourne l'historique local dans l'ordre d'affichage. Les tours
    /// invalides hérités d'une ancienne version sont ignorés plutôt que
    /// d'empêcher l'ouverture de la discussion.
    func history(for bookID: UUID) throws -> [LoreAIChatMessage] {
        guard let conversation = try conversation(for: bookID) else { return [] }
        return try messages(for: conversation.id).compactMap { message in
            guard let role = message.role else { return nil }
            let sources = storedSources(for: message, bookID: bookID)
            return LoreAIChatMessage(role: role, text: message.text, sources: sources)
        }
    }

    /// Persiste un tour complet uniquement après le succès de la réponse IA.
    /// Les extraits transmis au modèle ne sont pas conservés.
    @discardableResult
    func appendTurn(
        bookID: UUID,
        question: String,
        answer: String,
        sources: [LoreAIChatSource] = [],
        readingStage: LoreAIReadingStage = .inProgress,
        frontierProgression: Double? = nil,
        frontierDescription: String? = nil,
        at date: Date = .now
    ) throws -> AIConversationRecord {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else {
            throw AIConversationRepositoryError.emptyMessage
        }
        if let frontierProgression, !(0...1).contains(frontierProgression) {
            throw AIConversationRepositoryError.invalidFrontier
        }
        guard sources.allSatisfy({ source in
            source.bookID == bookID
                && source.hasValidIdentityAndProgression
                && source.locatorSchemaVersion == LocatorPersistenceCodec.currentSchemaVersion
                && (readingStage == .finished || source.progression.map { progression in
                    frontierProgression.map { progression <= $0 + 0.000_001 } ?? false
                } == true)
                && ((try? LocatorPersistenceCodec.decode(.init(
                    data: source.locatorJSON,
                    schemaVersion: source.locatorSchemaVersion
                )).locator.locations.totalProgression).flatMap { locatorProgression in
                    source.progression.map { abs(locatorProgression - $0) <= 0.000_001 }
                } == true)
        }) else { throw AIConversationRepositoryError.invalidSource }
        guard readingStage != .notStarted || sources.isEmpty else {
            throw AIConversationRepositoryError.invalidSource
        }
        guard Set(sources.map(\.id)).count == sources.count else {
            throw AIConversationRepositoryError.invalidSource
        }

        let conversationRecord: AIConversationRecord
        let isNewConversation: Bool
        if let existing = try conversation(for: bookID) {
            conversationRecord = existing
            isNewConversation = false
        } else {
            conversationRecord = AIConversationRecord(bookID: bookID, createdAt: date)
            context.insert(conversationRecord)
            isNewConversation = true
        }

        let existingMessages = try messages(for: conversationRecord.id)
        let firstSequence = (existingMessages.map(\AIMessageRecord.sequence).max() ?? -1) + 1
        let userMessage = AIMessageRecord(
            conversationID: conversationRecord.id,
            role: .user,
            text: question,
            sequence: firstSequence,
            createdAt: date,
            frontierProgression: frontierProgression,
            frontierDescription: frontierDescription
        )
        let assistantMessage = AIMessageRecord(
            conversationID: conversationRecord.id,
            role: .assistant,
            text: answer,
            sequence: firstSequence + 1,
            createdAt: date,
            frontierProgression: frontierProgression,
            frontierDescription: frontierDescription,
            sourcesJSON: sources.isEmpty ? nil : try JSONEncoder().encode(sources),
            sourcesSchemaVersion: sources.isEmpty ? nil : Self.sourcesSchemaVersion,
            readingStage: readingStage
        )
        context.insert(userMessage)
        context.insert(assistantMessage)
        let previousUpdatedAt = conversationRecord.updatedAt
        conversationRecord.updatedAt = max(previousUpdatedAt, date)

        do {
            try saveContext(context)
        } catch {
            // Keep the caller's context usable after a failed save and avoid
            // leaving a half-persisted turn in memory.
            context.delete(userMessage)
            context.delete(assistantMessage)
            if isNewConversation { context.delete(conversationRecord) }
            conversationRecord.updatedAt = previousUpdatedAt
            throw error
        }
        return conversationRecord
    }

    private func validStoredSource(
        _ source: LoreAIChatSource,
        bookID: UUID,
        message: AIMessageRecord
    ) -> Bool {
        guard source.bookID == bookID,
              source.hasValidIdentityAndProgression,
              source.locatorSchemaVersion == LocatorPersistenceCodec.currentSchemaVersion,
              let decoded = try? LocatorPersistenceCodec.decode(.init(
                  data: source.locatorJSON,
                  schemaVersion: source.locatorSchemaVersion
              )),
              let locatorProgression = decoded.locator.locations.totalProgression,
              source.progression.map({ abs($0 - locatorProgression) <= 0.000_001 }) == true
        else { return false }
        if message.readingStageRawValue == LoreAIReadingStage.finished.rawValue { return true }
        guard let frontier = message.frontierProgression else { return false }
        return source.progression.map { $0 <= frontier + 0.000_001 } == true
    }

    private func storedSources(for message: AIMessageRecord, bookID: UUID) -> [LoreAIChatSource] {
        guard message.sourcesSchemaVersion == Self.sourcesSchemaVersion,
              let data = message.sourcesJSON,
              let decoded = try? JSONDecoder().decode([LoreAIChatSource].self, from: data),
              Set(decoded.map(\.id)).count == decoded.count
        else { return [] }
        return decoded.filter { validStoredSource($0, bookID: bookID, message: message) }
    }

    @discardableResult
    func deleteConversation(for bookID: UUID) throws -> Bool {
        guard let conversation = try conversation(for: bookID) else { return false }
        try delete(conversation)
        return true
    }

    @discardableResult
    func deleteConversations(for bookID: UUID, save: Bool = true) throws -> Int {
        let descriptor = FetchDescriptor<AIConversationRecord>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        let conversations = try context.fetch(descriptor)
        guard !conversations.isEmpty else { return 0 }
        for conversation in conversations { try deleteWithoutSaving(conversation) }
        guard save else { return conversations.count }
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
        return conversations.count
    }

    private func delete(_ conversation: AIConversationRecord) throws {
        try deleteWithoutSaving(conversation)
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func deleteWithoutSaving(_ conversation: AIConversationRecord) throws {
        let conversationID = conversation.id
        let descriptor = FetchDescriptor<AIMessageRecord>(
            predicate: #Predicate { $0.conversationID == conversationID }
        )
        for message in try context.fetch(descriptor) { context.delete(message) }
        context.delete(conversation)
    }
}

enum AIConversationRepositoryError: LocalizedError, Equatable {
    case emptyMessage
    case invalidFrontier
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .emptyMessage: "La question et la réponse ne peuvent pas être vides."
        case .invalidFrontier: "La progression de lecture doit être comprise entre 0 et 1."
        case .invalidSource: "Une source de la réponse ne correspond pas au passage lu."
        }
    }
}
