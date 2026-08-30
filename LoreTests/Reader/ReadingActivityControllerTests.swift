import Foundation
import Testing
@testable import Lore

@MainActor
struct ReadingActivityControllerTests {
    @Test func inactivityAutomaticallyClosesAtIsolatedTwoMinuteDeadline() async throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 1_000))
        let store = ReadingSessionStoreSpy()
        let controller = ReadingActivityController(
            bookID: UUID(),
            store: store,
            clock: dates.clock,
            sleep: { _ in dates.advance(by: ReadingActivityPolicy.defaultInactivityTimeout) }
        )

        try controller.readerDidBecomeActive()
        try controller.recordReadingInteraction()
        await Task.yield()
        await Task.yield()

        #expect(store.records.count == 1)
        #expect(store.records[0].endedAt == Date(timeIntervalSince1970: 1_120))
    }

    @Test func activityExtendsDeadlineAndBackgroundStopsImmediately() async throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 2_000))
        let store = ReadingSessionStoreSpy()
        let controller = ReadingActivityController(
            bookID: UUID(), store: store,
            clock: dates.clock,
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        try controller.readerDidBecomeActive()
        try controller.recordReadingInteraction()
        dates.advance(by: 30)
        try controller.recordReadingInteraction()
        dates.advance(by: 20)
        try await controller.readerBecameInactive()

        #expect(store.records[0].lastActivityAt == Date(timeIntervalSince1970: 2_030))
        #expect(store.records[0].endedAt == Date(timeIntervalSince1970: 2_050))
    }

    @Test func lateActivityDoesNotCountIdleGap() throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 3_000))
        let store = ReadingSessionStoreSpy()
        let controller = ReadingActivityController(
            bookID: UUID(), store: store,
            clock: dates.clock,
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        try controller.readerDidBecomeActive()
        try controller.recordReadingInteraction()
        dates.advance(by: 180)
        try controller.recordReadingInteraction()

        #expect(store.records.count == 2)
        #expect(store.records[0].endedAt == Date(timeIntervalSince1970: 3_120))
        #expect(store.records[1].startedAt == Date(timeIntervalSince1970: 3_180))
    }

    @Test func closeFailureRemainsRetryable() async throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 4_000))
        let store = ReadingSessionStoreSpy(finishFailures: 1)
        let controller = ReadingActivityController(
            bookID: UUID(), store: store,
            clock: dates.clock,
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
        try controller.readerDidBecomeActive()
        try controller.recordReadingInteraction()
        dates.advance(by: 10)

        await #expect(throws: ReadingSessionStoreSpy.Failure.self) { try await controller.close() }
        try await controller.close()

        #expect(store.finishAttempts == 2)
        #expect(store.records[0].endedAt == Date(timeIntervalSince1970: 4_010))
    }

    @Test func foregroundAloneDoesNotStartAReadingSession() throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 5_000))
        let store = ReadingSessionStoreSpy()
        let controller = ReadingActivityController(bookID: UUID(), store: store, clock: dates.clock)

        try controller.readerDidBecomeActive()

        #expect(store.records.isEmpty)
    }

    @Test func lateInteractionAfterBackgroundOrCloseIsIgnored() async throws {
        let dates = LockedDate(Date(timeIntervalSince1970: 6_000))
        let store = ReadingSessionStoreSpy()
        let controller = ReadingActivityController(bookID: UUID(), store: store, clock: dates.clock)
        try controller.readerDidBecomeActive()
        try controller.recordReadingInteraction()
        dates.advance(by: 10)
        try await controller.readerBecameInactive()

        try controller.recordReadingInteraction()
        try await controller.close()
        try controller.recordReadingInteraction()

        #expect(store.records.count == 1)
        #expect(store.records[0].endedAt == Date(timeIntervalSince1970: 6_010))
    }
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var value: Date { lock.withLock { date } }
    var clock: ReadingActivityClock {
        ReadingActivityClock(
            date: { [self] in value },
            uptime: { [self] in value.timeIntervalSince1970 }
        )
    }
    func advance(by interval: TimeInterval) { lock.withLock { date.addTimeInterval(interval) } }
}

@MainActor
private final class ReadingSessionStoreSpy: ReadingSessionStore {
    enum Failure: Error { case finish }
    struct Record { let id: UUID; let bookID: UUID; let startedAt: Date; var lastActivityAt: Date; var endedAt: Date? }
    private(set) var records: [Record] = []
    private(set) var finishAttempts = 0
    private var finishFailures: Int

    init(finishFailures: Int = 0) { self.finishFailures = finishFailures }
    func begin(bookID: UUID, at date: Date) throws -> UUID {
        let id = UUID()
        records.append(Record(id: id, bookID: bookID, startedAt: date, lastActivityAt: date))
        return id
    }
    func recordActivity(sessionID: UUID, at date: Date) throws {
        let index = try index(of: sessionID)
        records[index].lastActivityAt = date
    }
    func finish(sessionID: UUID, at date: Date) throws {
        finishAttempts += 1
        if finishFailures > 0 { finishFailures -= 1; throw Failure.finish }
        let index = try index(of: sessionID)
        records[index].endedAt = date
    }
    private func index(of id: UUID) throws -> Int {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw Failure.finish }
        return index
    }
}
