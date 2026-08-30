import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct StatisticsDataAdapterTests {
    @Test func usesLocalCivilBoundariesAndAMondayWeek() throws {
        let fixture = try StatisticsFixture()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 60 * 60))
        calendar.firstWeekday = 1
        let sunday = try date(2026, 8, 30, 23, 30, calendar: calendar)
        let monday = try date(2026, 8, 31, 0, 30, calendar: calendar)
        fixture.insertSession(startedAt: sunday, endedAt: monday)

        let snapshot = try fixture.adapter.snapshot(containing: monday, calendar: calendar)

        #expect(snapshot.todayDuration == 30 * 60)
        #expect(snapshot.weekDuration == 30 * 60)
        #expect(snapshot.monthDuration == 60 * 60)
        #expect(snapshot.readingDays == [
            ReadingDaySummary(date: calendar.startOfDay(for: sunday), duration: 30 * 60),
            ReadingDaySummary(date: calendar.startOfDay(for: monday), duration: 30 * 60)
        ])
    }

    @Test func buildsHistoryFromBooksAndFirstRealSessions() throws {
        let fixture = try StatisticsFixture()
        let firstStart = Date(timeIntervalSince1970: 1_000)
        let laterStart = firstStart.addingTimeInterval(500)
        let finishedAt = firstStart.addingTimeInterval(1_000)
        let inProgress = BookRecord(
            title: "En cours",
            author: "Autrice",
            relativeFilePath: "Books/current/book.epub",
            lastProgression: 0.4
        )
        let finished = BookRecord(
            title: "Terminé",
            relativeFilePath: "Books/finished/book.epub",
            lastProgression: 1,
            finishedAt: finishedAt,
            rating: 9
        )
        let unread = BookRecord(title: "À lire", relativeFilePath: "Books/unread/book.epub")
        fixture.context.insert(inProgress)
        fixture.context.insert(finished)
        fixture.context.insert(unread)
        fixture.insertSession(bookID: inProgress.id, startedAt: laterStart, endedAt: laterStart.addingTimeInterval(10))
        fixture.insertSession(bookID: inProgress.id, startedAt: firstStart, endedAt: firstStart.addingTimeInterval(10))
        fixture.insertSession(bookID: finished.id, startedAt: firstStart, endedAt: firstStart.addingTimeInterval(10))
        try fixture.context.save()

        let snapshot = try fixture.adapter.snapshot(
            containing: finishedAt,
            calendar: Calendar(identifier: .gregorian)
        )

        let current = try #require(snapshot.inProgressBooks.first)
        #expect(snapshot.inProgressBooks.count == 1)
        #expect(current.id == inProgress.id)
        #expect(current.startedAt == firstStart)
        #expect(current.progress == 0.4)
        let completed = try #require(snapshot.finishedBooks.first)
        #expect(snapshot.finishedBooks.count == 1)
        #expect(completed.id == finished.id)
        #expect(completed.finishedAt == finishedAt)
        #expect(completed.rating == 9)
    }

    @Test func capsOpenSessionAtTheInactivityDeadline() throws {
        let fixture = try StatisticsFixture()
        let start = Date(timeIntervalSince1970: 10_000)
        fixture.insertSession(startedAt: start, lastActivityAt: start.addingTimeInterval(30))

        let snapshot = try fixture.adapter.snapshot(
            containing: start.addingTimeInterval(1_000),
            calendar: Calendar(identifier: .gregorian),
            inactivityTimeout: 120
        )

        #expect(snapshot.todayDuration == 150)
    }

    @Test func rejectsARatingOutsideTheZeroToTenContract() throws {
        let fixture = try StatisticsFixture()
        let book = BookRecord(
            title: "Note invalide",
            relativeFilePath: "Books/invalid/book.epub",
            rating: 11
        )
        fixture.context.insert(book)
        try fixture.context.save()

        #expect(throws: StatisticsDataAdapterError.invalidRating(bookID: book.id)) {
            try fixture.adapter.snapshot(
                containing: Date(timeIntervalSince1970: 1_000),
                calendar: Calendar(identifier: .gregorian)
            )
        }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }
}

@MainActor
private final class StatisticsFixture {
    let container: ModelContainer
    let context: ModelContext
    let adapter: StatisticsDataAdapter

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: BookRecord.self,
            ReadingSessionRecord.self,
            configurations: configuration
        )
        context = container.mainContext
        adapter = StatisticsDataAdapter(context: context)
    }

    func insertSession(
        bookID: UUID = UUID(),
        startedAt: Date,
        lastActivityAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        context.insert(ReadingSessionRecord(
            bookID: bookID,
            startedAt: startedAt,
            lastActivityAt: lastActivityAt,
            endedAt: endedAt
        ))
    }
}
