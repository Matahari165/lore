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
    /// Optional so SwiftData can lightweight-migrate stores created before
    /// personal notes existed without manufacturing content for old highlights.
    var note: String?

    init(
        id: UUID = UUID(),
        bookID: UUID,
        locatorJSON: Data,
        locatorSchemaVersion: Int,
        text: String,
        createdAt: Date = .now,
        colorRawValue: String,
        note: String? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.locatorJSON = locatorJSON
        self.locatorSchemaVersion = locatorSchemaVersion
        self.text = text
        self.createdAt = createdAt
        self.colorRawValue = colorRawValue
        self.note = note
    }
}
