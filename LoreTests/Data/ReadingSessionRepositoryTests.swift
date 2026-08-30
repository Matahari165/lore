import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct ReadingSessionRepositoryTests {
    @Test func recoversOpenSessionAtInactivityDeadline() throws {
        let repository = try makeRepository()
        let start = Date(timeIntervalSince1970: 1_000)
        let id = try repository.begin(bookID: UUID(), at: start)
        try repository.recordActivity(sessionID: id, at: start.addingTimeInterval(30))

        #expect(try repository.recoverOpenSessions(now: start.addingTimeInterval(1_000)) == 1)

        let session = try #require(repository.sessions().first)
        #expect(session.endedAt == start.addingTimeInterval(30))
    }

    @Test func summarySplitsAnIntervalAcrossMidnightWeekAndMonth() throws {
        let repository = try makeRepository()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31, hour: 23, minute: 59
        )))
        let id = try repository.begin(bookID: UUID(), at: start)
        try repository.finish(sessionID: id, at: start.addingTimeInterval(120))
        let now = start.addingTimeInterval(90)

        let summary = try repository.summary(containing: now, calendar: calendar)

        #expect(summary.today == 60)
        #expect(summary.thisWeek == 60)
        #expect(summary.thisMonth == 60)
    }

    @Test func summariesAreZeroWithoutSessions() throws {
        let repository = try makeRepository()
        let summary = try repository.summary(containing: Date(timeIntervalSince1970: 1_000))
        #expect(summary == ReadingTimeSummary(today: 0, thisWeek: 0, thisMonth: 0))
    }

    @Test func firstSessionDateComesFromFirstRealReadingInterval() throws {
        let repository = try makeRepository()
        let bookID = UUID()
        let first = Date(timeIntervalSince1970: 10)
        _ = try repository.begin(bookID: bookID, at: first)
        _ = try repository.begin(bookID: bookID, at: first.addingTimeInterval(50))
        #expect(try repository.firstSessionDate(for: bookID) == first)
    }

    private func makeRepository() throws -> ReadingSessionRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ReadingSessionRecord.self, configurations: configuration)
        return ReadingSessionRepository(context: container.mainContext)
    }
}
