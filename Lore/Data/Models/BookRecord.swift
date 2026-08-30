import Foundation
import SwiftData

@Model
final class BookRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var contentSHA256: String?
    var title: String
    var author: String?
    @Attribute(.externalStorage) var coverData: Data?
    var relativeFilePath: String
    var mediaType: String
    var importedAt: Date
    var lastLocatorJSON: Data?
    var lastProgression: Double?
    var progressUpdatedAt: Date?
    var locatorSchemaVersion: Int?
    var importStateRawValue: String = BookImportState.ready.rawValue
    var stagingToken: UUID?

    init(
        id: UUID = UUID(),
        contentSHA256: String? = nil,
        title: String,
        author: String? = nil,
        coverData: Data? = nil,
        relativeFilePath: String,
        mediaType: String = "application/epub+zip",
        importedAt: Date = .now,
        lastLocatorJSON: Data? = nil,
        lastProgression: Double? = nil,
        progressUpdatedAt: Date? = nil,
        locatorSchemaVersion: Int? = nil,
        importState: BookImportState = .ready,
        stagingToken: UUID? = nil
    ) {
        self.id = id
        self.contentSHA256 = contentSHA256
        self.title = title
        self.author = author
        self.coverData = coverData
        self.relativeFilePath = relativeFilePath
        self.mediaType = mediaType
        self.importedAt = importedAt
        self.lastLocatorJSON = lastLocatorJSON
        self.lastProgression = lastProgression
        self.progressUpdatedAt = progressUpdatedAt
        self.locatorSchemaVersion = locatorSchemaVersion
        importStateRawValue = importState.rawValue
        self.stagingToken = stagingToken
    }

    var importState: BookImportState {
        get { BookImportState(rawValue: importStateRawValue) ?? .recoveryRequired }
        set { importStateRawValue = newValue.rawValue }
    }
}

enum BookImportState: String, Codable, Sendable {
    case pending
    case ready
    case recoveryRequired
}
