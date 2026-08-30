import Foundation
import SwiftData

@Model
final class ReadingSessionRecord {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var startedAt: Date
    var lastActivityAt: Date
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        bookID: UUID,
        startedAt: Date,
        lastActivityAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt ?? startedAt
        self.endedAt = endedAt
    }
}
