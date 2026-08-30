import Foundation
import SwiftData

@Model
final class BookRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    @Attribute(.externalStorage) var coverData: Data?
    var relativeFilePath: String
    var mediaType: String
    var importedAt: Date
    var lastLocatorJSON: Data?
    var lastProgression: Double?
    var progressUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        coverData: Data? = nil,
        relativeFilePath: String,
        mediaType: String = "application/epub+zip",
        importedAt: Date = .now,
        lastLocatorJSON: Data? = nil,
        lastProgression: Double? = nil,
        progressUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverData = coverData
        self.relativeFilePath = relativeFilePath
        self.mediaType = mediaType
        self.importedAt = importedAt
        self.lastLocatorJSON = lastLocatorJSON
        self.lastProgression = lastProgression
        self.progressUpdatedAt = progressUpdatedAt
    }
}
