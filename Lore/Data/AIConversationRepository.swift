import Foundation
import SwiftData

@MainActor
final class AIConversationRepository {
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
            return LoreAIChatMessage(role: role, text: message.text)
        }
    }

    /// Persiste un tour complet uniquement après le succès de la réponse IA.
    /// Les extraits transmis au modèle ne sont pas conservés.
    @discardableResult
    func appendTurn(
        bookID: UUID,
        question: String,
        answer: String,
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
            frontierDescription: frontierDescription
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

    var errorDescription: String? {
        switch self {
        case .emptyMessage: "La question et la réponse ne peuvent pas être vides."
        case .invalidFrontier: "La progression de lecture doit être comprise entre 0 et 1."
        }
    }
}
