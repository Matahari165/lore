import Foundation
import SwiftData

@Model
final class VocabularyRecord {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var locatorJSON: Data
    var locatorSchemaVersion: Int
    var text: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: Data,
        locatorSchemaVersion: Int,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.locatorSchemaVersion = locatorSchemaVersion
        self.text = text
        self.createdAt = createdAt
    }
}
