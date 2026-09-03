import Foundation
import SwiftData

@Model
final class PodcastRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var contentSHA256: String?
    var title: String
    var originalFilename: String
    var relativeFilePath: String
    var importedAt: Date
    var durationSeconds: Double?
    var lastPositionSeconds: Double
    var progressUpdatedAt: Date?
    var importStateRawValue: String = PodcastImportState.ready.rawValue
    var stagingToken: UUID?

    init(
        id: UUID = UUID(),
        contentSHA256: String? = nil,
        title: String,
        originalFilename: String,
        relativeFilePath: String,
        importedAt: Date = .now,
        durationSeconds: Double? = nil,
        lastPositionSeconds: Double = 0,
        progressUpdatedAt: Date? = nil,
        importState: PodcastImportState = .ready,
        stagingToken: UUID? = nil
    ) {
        self.id = id
        self.contentSHA256 = contentSHA256
        self.title = title
        self.originalFilename = originalFilename
        self.relativeFilePath = relativeFilePath
        self.importedAt = importedAt
        self.durationSeconds = durationSeconds
        self.lastPositionSeconds = max(0, lastPositionSeconds)
        self.progressUpdatedAt = progressUpdatedAt
        importStateRawValue = importState.rawValue
        self.stagingToken = stagingToken
    }

    var importState: PodcastImportState {
        get { PodcastImportState(rawValue: importStateRawValue) ?? .recoveryRequired }
        set { importStateRawValue = newValue.rawValue }
    }

    var progression: Double {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        return min(max(lastPositionSeconds / durationSeconds, 0), 1)
    }
}

enum PodcastImportState: String, Codable, Sendable {
    case pending
    case ready
    case recoveryRequired
}
