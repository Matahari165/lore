import Foundation

struct ReadingRecapLocator: Codable, Sendable, Equatable {
    let json: Data
    let schemaVersion: Int?

    init(json: Data, schemaVersion: Int?) {
        self.json = json
        self.schemaVersion = schemaVersion
    }

    init(_ locator: StoredLocator) {
        self.init(json: locator.data, schemaVersion: locator.schemaVersion)
    }

    var storedLocator: StoredLocator {
        StoredLocator(data: json, schemaVersion: schemaVersion)
    }
}

struct ReadingRecapCheckpoint: Codable, Sendable, Equatable {
    let bookID: UUID
    let localDayStart: Date
    let firstLocator: ReadingRecapLocator
    let lastLocator: ReadingRecapLocator
    let firstRecordedAt: Date
    let lastRecordedAt: Date
}

struct ReadingRecapSession: Sendable, Equatable {
    let startedAt: Date
    let lastActivityAt: Date
    let endedAt: Date?

    init(startedAt: Date, lastActivityAt: Date, endedAt: Date?) {
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.endedAt = endedAt
    }
}

struct ReadingRecapWindow: Sendable, Equatable {
    let bookID: UUID
    let localDayInterval: DateInterval
    let firstActivityAt: Date
    let lastActivityAt: Date
    let exactReadingDuration: TimeInterval
    let firstLocator: ReadingRecapLocator
    let lastLocator: ReadingRecapLocator
}

enum ReadingRecapUnavailableReason: Sendable, Equatable {
    case noPreviousDay
    case noReadingOnPreviousDay
    case missingLocatorCheckpoints
}

enum ReadingRecapEligibility: Sendable, Equatable {
    case eligible(ReadingRecapWindow)
    case alreadyShownToday
    case unavailable(ReadingRecapUnavailableReason)
}

enum ReadingRecapCompletion: Sendable, Equatable {
    /// Le résumé a réellement été produit et présenté.
    case delivered
    /// L'utilisateur a fermé explicitement la proposition pour cette journée.
    case dismissed
    /// La génération ou la présentation a échoué. Une nouvelle tentative reste possible.
    case failed
}

@MainActor
protocol ReadingRecapStateStore: AnyObject {
    func lastShownDay(for bookID: UUID) throws -> Date?
    func saveLastShownDay(_ dayStart: Date, for bookID: UUID) throws
    func checkpoint(for bookID: UUID, localDayStart: Date) throws -> ReadingRecapCheckpoint?
    func saveCheckpoint(_ checkpoint: ReadingRecapCheckpoint) throws
}

