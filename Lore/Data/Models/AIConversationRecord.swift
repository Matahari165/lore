import Foundation
import SwiftData

/// Fil local unique d'une conversation par livre. Les extraits EPUB ne sont
/// jamais stockés dans ce modèle.
@Model
final class AIConversationRecord {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

@Model
final class AIMessageRecord {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID
    var roleRawValue: String
    var text: String
    var sequence: Int
    var createdAt: Date
    var frontierProgression: Double?
    var frontierDescription: String?

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: LoreAIChatRole,
        text: String,
        sequence: Int,
        createdAt: Date = .now,
        frontierProgression: Double? = nil,
        frontierDescription: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        roleRawValue = role.rawValue
        self.text = text
        self.sequence = sequence
        self.createdAt = createdAt
        self.frontierProgression = frontierProgression
        self.frontierDescription = frontierDescription
    }

    var role: LoreAIChatRole? { LoreAIChatRole(rawValue: roleRawValue) }
}
