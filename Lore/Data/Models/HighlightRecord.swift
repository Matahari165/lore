import Foundation
import SwiftData

@Model
final class HighlightRecord {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var locatorJSON: Data
    var locatorSchemaVersion: Int
    var text: String
    var createdAt: Date
    var colorRawValue: String

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: Data,
        locatorSchemaVersion: Int,
        text: String,
        createdAt: Date = .now,
        colorRawValue: String
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.locatorSchemaVersion = locatorSchemaVersion
        self.text = text
        self.createdAt = createdAt
        self.colorRawValue = colorRawValue
    }
}
