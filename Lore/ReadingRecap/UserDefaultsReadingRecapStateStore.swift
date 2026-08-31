import Foundation

@MainActor
final class UserDefaultsReadingRecapStateStore: ReadingRecapStateStore {
    static let stateKey = "reading-recap-state-v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastShownDay(for bookID: UUID) throws -> Date? {
        try load().lastShownDays[bookID.uuidString]
    }

    func saveLastShownDay(_ dayStart: Date, for bookID: UUID) throws {
        var state = try load()
        state.lastShownDays[bookID.uuidString] = dayStart
        try save(state)
    }

    func checkpoint(for bookID: UUID, localDayStart: Date) throws -> ReadingRecapCheckpoint? {
        try load().checkpoints[Self.checkpointKey(bookID: bookID, dayStart: localDayStart)]
    }

    func saveCheckpoint(_ checkpoint: ReadingRecapCheckpoint) throws {
        var state = try load()
        state.checkpoints[Self.checkpointKey(
            bookID: checkpoint.bookID,
            dayStart: checkpoint.localDayStart
        )] = checkpoint
        try save(state)
    }

    private func load() throws -> PersistedState {
        guard let data = defaults.data(forKey: Self.stateKey) else { return PersistedState() }
        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            throw ReadingRecapStoreError.unreadableState
        }
    }

    private func save(_ state: PersistedState) throws {
        do {
            defaults.set(try encoder.encode(state), forKey: Self.stateKey)
        } catch {
            throw ReadingRecapStoreError.couldNotEncodeState
        }
    }

    private static func checkpointKey(bookID: UUID, dayStart: Date) -> String {
        "\(bookID.uuidString)|\(dayStart.timeIntervalSinceReferenceDate)"
    }
}

private struct PersistedState: Codable {
    var lastShownDays: [String: Date] = [:]
    var checkpoints: [String: ReadingRecapCheckpoint] = [:]
}

enum ReadingRecapStoreError: LocalizedError, Equatable {
    case unreadableState
    case couldNotEncodeState

    var errorDescription: String? {
        switch self {
        case .unreadableState:
            "Les données de reprise quotidienne sont illisibles."
        case .couldNotEncodeState:
            "Les données de reprise quotidienne n'ont pas pu être enregistrées."
        }
    }
}

