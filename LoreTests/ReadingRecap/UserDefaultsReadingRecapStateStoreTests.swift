import Foundation
import Testing
@testable import Lore

@MainActor
struct UserDefaultsReadingRecapStateStoreTests {
    @Test func persistsShownDayAndCheckpoint() throws {
        let suiteName = "ReadingRecapStore-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsReadingRecapStateStore(defaults: defaults)
        let bookID = UUID()
        let day = Date(timeIntervalSinceReferenceDate: 123_456)
        let locator = ReadingRecapLocator(json: Data("locator".utf8), schemaVersion: 1)
        let checkpoint = ReadingRecapCheckpoint(
            bookID: bookID,
            localDayStart: day,
            firstLocator: locator,
            lastLocator: locator,
            firstRecordedAt: day,
            lastRecordedAt: day
        )

        try store.saveLastShownDay(day, for: bookID)
        try store.saveCheckpoint(checkpoint)

        let reloaded = UserDefaultsReadingRecapStateStore(defaults: defaults)
        #expect(try reloaded.lastShownDay(for: bookID) == day)
        #expect(try reloaded.checkpoint(for: bookID, localDayStart: day) == checkpoint)
    }

    @Test func reportsCorruptPersistentState() throws {
        let suiteName = "ReadingRecapStoreCorrupt-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsReadingRecapStateStore.stateKey)

        let store = UserDefaultsReadingRecapStateStore(defaults: defaults)
        #expect(throws: ReadingRecapStoreError.unreadableState) {
            try store.lastShownDay(for: UUID())
        }
    }
}

