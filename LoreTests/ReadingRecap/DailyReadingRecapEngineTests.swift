import Foundation
import Testing
@testable import Lore

@MainActor
struct DailyReadingRecapEngineTests {
    @Test func offersYesterdayOnceThenWaitsForTheNextLocalDay() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let yesterday = try fixture.date(year: 2026, month: 8, day: 30, hour: 20)
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 8)
        fixture.sessions[bookID] = [ReadingRecapSession(
            startedAt: yesterday,
            lastActivityAt: yesterday.addingTimeInterval(600),
            endedAt: yesterday.addingTimeInterval(600)
        )]
        try fixture.recordTwoCheckpoints(bookID: bookID, start: yesterday)

        guard case let .eligible(window) = try fixture.engine.eligibility(for: bookID, at: now) else {
            Issue.record("Le résumé de la veille devrait être proposé")
            return
        }
        #expect(window.exactReadingDuration == 600)
        #expect(window.firstLocator.json == Data("first".utf8))
        #expect(window.lastLocator.json == Data("last".utf8))

        try fixture.engine.markShown(for: bookID, at: now, completion: .delivered)
        #expect(try fixture.engine.eligibility(for: bookID, at: now.addingTimeInterval(43_200)) == .alreadyShownToday)
    }

    @Test func explicitDismissalMarksTheDayButFailureAllowsRetry() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let yesterday = try fixture.date(year: 2026, month: 8, day: 30, hour: 18)
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 9)
        fixture.sessions[bookID] = [.init(
            startedAt: yesterday,
            lastActivityAt: yesterday.addingTimeInterval(60),
            endedAt: yesterday.addingTimeInterval(60)
        )]
        try fixture.recordTwoCheckpoints(bookID: bookID, start: yesterday)

        try fixture.engine.markShown(for: bookID, at: now, completion: .failed)
        guard case .eligible = try fixture.engine.eligibility(for: bookID, at: now) else {
            Issue.record("Un échec doit permettre une nouvelle tentative")
            return
        }

        try fixture.engine.markShown(for: bookID, at: now, completion: .dismissed)
        #expect(try fixture.engine.eligibility(for: bookID, at: now) == .alreadyShownToday)
    }

    @Test func shownStateIsIndependentForEveryBook() throws {
        let fixture = try RecapFixture()
        let firstBook = UUID()
        let secondBook = UUID()
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 9)

        try fixture.engine.markShown(for: firstBook, at: now, completion: .delivered)

        #expect(try fixture.engine.eligibility(for: firstBook, at: now) == .alreadyShownToday)
        #expect(try fixture.engine.eligibility(for: secondBook, at: now) == .unavailable(.noReadingOnPreviousDay))
    }

    @Test func oldSessionsWithoutLocatorCheckpointsAreUnavailable() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let yesterday = try fixture.date(year: 2026, month: 8, day: 30, hour: 19)
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 8)
        fixture.sessions[bookID] = [.init(
            startedAt: yesterday,
            lastActivityAt: yesterday.addingTimeInterval(300),
            endedAt: yesterday.addingTimeInterval(300)
        )]

        #expect(try fixture.engine.eligibility(for: bookID, at: now) == .unavailable(.missingLocatorCheckpoints))
    }

    @Test func checkpointKeepsFirstLocatorAndUpdatesOnlyTheLast() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let date = try fixture.date(year: 2026, month: 8, day: 30, hour: 10)

        try fixture.engine.recordCheckpoint(
            bookID: bookID,
            locator: StoredLocator(data: Data("one".utf8), schemaVersion: 1),
            at: date
        )
        try fixture.engine.recordCheckpoint(
            bookID: bookID,
            locator: StoredLocator(data: Data("two".utf8), schemaVersion: 1),
            at: date.addingTimeInterval(900)
        )

        let day = fixture.calendar.startOfDay(for: date)
        let storedCheckpoint = try fixture.store.checkpoint(for: bookID, localDayStart: day)
        let checkpoint = try #require(storedCheckpoint)
        #expect(checkpoint.firstLocator.json == Data("one".utf8))
        #expect(checkpoint.lastLocator.json == Data("two".utf8))
        #expect(checkpoint.firstRecordedAt == date)
        #expect(checkpoint.lastRecordedAt == date.addingTimeInterval(900))
    }

    @Test func clipsCrossMidnightSessionsToYesterday() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let start = try fixture.date(year: 2026, month: 8, day: 30, hour: 23, minute: 55)
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 8)
        fixture.sessions[bookID] = [.init(
            startedAt: start,
            lastActivityAt: start.addingTimeInterval(600),
            endedAt: start.addingTimeInterval(600)
        )]
        try fixture.recordTwoCheckpoints(bookID: bookID, start: start)

        guard case let .eligible(window) = try fixture.engine.eligibility(for: bookID, at: now) else {
            Issue.record("La portion avant minuit devrait être résumable")
            return
        }
        #expect(window.exactReadingDuration == 300)
    }

    @Test func openSessionUsesTheCanonicalInactivityDeadline() throws {
        let fixture = try RecapFixture()
        let bookID = UUID()
        let start = try fixture.date(year: 2026, month: 8, day: 30, hour: 19)
        let now = try fixture.date(year: 2026, month: 8, day: 31, hour: 8)
        fixture.sessions[bookID] = [.init(
            startedAt: start,
            lastActivityAt: start.addingTimeInterval(60),
            endedAt: nil
        )]
        try fixture.recordTwoCheckpoints(bookID: bookID, start: start)

        guard case let .eligible(window) = try fixture.engine.eligibility(for: bookID, at: now) else {
            Issue.record("La session ouverte récupérée doit respecter le délai d'inactivité")
            return
        }
        #expect(window.exactReadingDuration == 180)
    }

    @Test func previousDayUsesCalendarAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let fixture = try RecapFixture(calendar: calendar)
        let bookID = UUID()
        let sessionStart = try fixture.date(year: 2026, month: 3, day: 8, hour: 10)
        let now = try fixture.date(year: 2026, month: 3, day: 9, hour: 8)
        fixture.sessions[bookID] = [.init(
            startedAt: sessionStart,
            lastActivityAt: sessionStart.addingTimeInterval(600),
            endedAt: sessionStart.addingTimeInterval(600)
        )]
        try fixture.recordTwoCheckpoints(bookID: bookID, start: sessionStart)

        guard case let .eligible(window) = try fixture.engine.eligibility(for: bookID, at: now) else {
            Issue.record("Le changement d'heure ne doit pas masquer la veille")
            return
        }
        #expect(window.localDayInterval.duration == 23 * 60 * 60)
        #expect(window.exactReadingDuration == 600)
    }
}

@MainActor
private final class RecapFixture {
    let calendar: Calendar
    let store = InMemoryReadingRecapStore()
    var sessions: [UUID: [ReadingRecapSession]] = [:]
    lazy var engine = DailyReadingRecapEngine(store: store, calendar: calendar) { [unowned self] bookID in
        sessions[bookID] ?? []
    }

    init(calendar: Calendar? = nil) throws {
        if let calendar {
            self.calendar = calendar
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
            self.calendar = calendar
        }
    }

    func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    func recordTwoCheckpoints(bookID: UUID, start: Date) throws {
        try engine.recordCheckpoint(
            bookID: bookID,
            locator: StoredLocator(data: Data("first".utf8), schemaVersion: 1),
            at: start
        )
        try engine.recordCheckpoint(
            bookID: bookID,
            locator: StoredLocator(data: Data("last".utf8), schemaVersion: 1),
            at: start.addingTimeInterval(60)
        )
    }
}

@MainActor
private final class InMemoryReadingRecapStore: ReadingRecapStateStore {
    var shown: [UUID: Date] = [:]
    var checkpoints: [String: ReadingRecapCheckpoint] = [:]

    func lastShownDay(for bookID: UUID) throws -> Date? { shown[bookID] }

    func saveLastShownDay(_ dayStart: Date, for bookID: UUID) throws {
        shown[bookID] = dayStart
    }

    func checkpoint(for bookID: UUID, localDayStart: Date) throws -> ReadingRecapCheckpoint? {
        checkpoints[key(bookID, localDayStart)]
    }

    func saveCheckpoint(_ checkpoint: ReadingRecapCheckpoint) throws {
        checkpoints[key(checkpoint.bookID, checkpoint.localDayStart)] = checkpoint
    }

    private func key(_ bookID: UUID, _ day: Date) -> String {
        "\(bookID.uuidString)|\(day.timeIntervalSinceReferenceDate)"
    }
}
