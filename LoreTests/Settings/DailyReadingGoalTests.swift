import Foundation
import Testing
@testable import Lore

struct DailyReadingGoalTests {
    @Test func persistsAndDisablesTheGoal() throws {
        let suiteName = "DailyReadingGoalTests-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsDailyReadingGoalStore(defaults: suite)

        #expect(try store.loadMinutes() == nil)
        try store.saveMinutes(35)
        #expect(try store.loadMinutes() == 35)
        try store.saveMinutes(nil)
        #expect(try store.loadMinutes() == nil)
    }

    @Test func rejectsValuesOutsideTheContract() throws {
        let suiteName = "DailyReadingGoalBounds-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsDailyReadingGoalStore(defaults: suite)

        #expect(throws: DailyReadingGoalError.invalidMinutes(4)) { try store.saveMinutes(4) }
        #expect(throws: DailyReadingGoalError.invalidMinutes(181)) { try store.saveMinutes(181) }
    }

    @Test func reportsAnUnreadablePersistedValue() throws {
        let suiteName = "DailyReadingGoalUnreadable-\(UUID())"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("vingt", forKey: UserDefaultsDailyReadingGoalStore.key)

        #expect(throws: DailyReadingGoalError.unreadableValue) {
            try UserDefaultsDailyReadingGoalStore(defaults: suite).loadMinutes()
        }
    }

    @Test func capsOnlyTheVisualProgressAndKeepsExactReadingTime() {
        let progress = DailyGoalProgress(readSeconds: 27 * 60 + 12, targetMinutes: 20)

        #expect(progress.visualFraction == 1)
        #expect(progress.exactFraction == Double(27 * 60 + 12) / Double(20 * 60))
        #expect(progress.readSeconds == 1_632)
        #expect(progress.isReached)
        #expect(progress.remainingSeconds == 0)
    }

    @Test func roundsReadMinutesDownAndRemainingMinutesUp() {
        let progress = DailyGoalProgress(readSeconds: 4 * 60 + 31, targetMinutes: 10)

        #expect(progress.displayedReadMinutes == 4)
        #expect(progress.displayedRemainingMinutes == 6)
        #expect(!progress.isReached)
    }

    @MainActor
    @Test func exposesAStoreFailureWithoutInventingAValue() {
        let model = DailyReadingGoalModel(store: FailingDailyReadingGoalStore())

        #expect(model.minutes == nil)
        #expect(model.state == .failed(message: "Échec de lecture"))
    }

    @MainActor
    @Test func exposesAnUnavailableProgressWithoutReplacingItWithZero() {
        let model = DailyReadingGoalModel(store: FixedDailyReadingGoalStore(minutes: 20))
        model.updateTodayDuration(8 * 60)
        model.markProgressUnavailable()

        #expect(model.todayDuration == 8 * 60)
        #expect(model.state == .failed(message: "La progression du jour n’est pas disponible pour le moment."))
    }
}

private struct FailingDailyReadingGoalStore: DailyReadingGoalStore {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Échec de lecture" }
    }

    func loadMinutes() throws -> Int? { throw Failure() }
    func saveMinutes(_ minutes: Int?) throws { throw Failure() }
}

private struct FixedDailyReadingGoalStore: DailyReadingGoalStore {
    let minutes: Int?

    func loadMinutes() throws -> Int? { minutes }
    func saveMinutes(_ minutes: Int?) throws {}
}
