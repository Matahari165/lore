import Foundation

enum ReadingActivityPolicy {
    static let defaultInactivityTimeout: TimeInterval = 2 * 60
}

struct ReadingActivityClock: Sendable {
    var date: @Sendable () -> Date
    var uptime: @Sendable () -> TimeInterval

    static let system = ReadingActivityClock(
        date: Date.init,
        uptime: { ProcessInfo.processInfo.systemUptime }
    )
}

@MainActor
protocol ReadingActivityManaging: AnyObject {
    func readerDidBecomeActive() throws
    func retryPendingStop() throws
    func recordReadingInteraction() throws
    func readerBecameInactive() async throws
    func close() async throws
}

@MainActor
final class NoopReadingActivityManager: ReadingActivityManaging {
    func readerDidBecomeActive() throws {}
    func retryPendingStop() throws {}
    func recordReadingInteraction() throws {}
    func readerBecameInactive() async throws {}
    func close() async throws {}
}

@MainActor
final class ReadingActivityController: ReadingActivityManaging {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    private enum ReaderState { case inactive, active, closed }

    private let bookID: UUID
    private let store: any ReadingSessionStore
    private let timeout: TimeInterval
    private let clock: ReadingActivityClock
    private let sleep: Sleep
    private let onError: @MainActor (Error) -> Void

    private var sessionID: UUID?
    private var deadline: Date?
    private var lastObservedDate: Date?
    private var timerRevision: UInt64 = 0
    private var inactivityTask: Task<Void, Never>?
    private var pendingStopAt: Date?
    private var readerState: ReaderState = .inactive
    private var sessionStartDate: Date?
    private var sessionStartUptime: TimeInterval?
    private var lastActivityDate: Date?
    private var deadlineUptime: TimeInterval?

    init(
        bookID: UUID,
        store: any ReadingSessionStore,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout,
        clock: ReadingActivityClock = .system,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.bookID = bookID
        self.store = store
        timeout = inactivityTimeout
        self.clock = clock
        self.sleep = sleep
        self.onError = onError
    }

    func readerDidBecomeActive() throws {
        guard readerState != .closed else { return }
        readerState = .active
        try retryPendingStop()
    }

    func retryPendingStop() throws {
        guard let pendingStopAt else { return }
        try finish(at: pendingStopAt)
    }

    func recordReadingInteraction() throws {
        guard readerState == .active else { return }
        try retryPendingStop()
        if sessionID == nil { try startSession() }
        guard let sessionID else { return }
        let uptime = clock.uptime()
        if let deadlineUptime, uptime >= deadlineUptime {
            try finish(at: deadline ?? observedNow())
            try startSession()
            return
        }
        let activityDate = monotonicDate(at: uptime)
        try store.recordActivity(sessionID: sessionID, at: activityDate)
        lastActivityDate = activityDate
        deadline = activityDate.addingTimeInterval(timeout)
        deadlineUptime = uptime + timeout
        scheduleInactivityTimer()
    }

    private func startSession() throws {
        guard sessionID == nil else { return }
        let now = observedNow()
        sessionID = try store.begin(bookID: bookID, at: now)
        sessionStartDate = now
        sessionStartUptime = clock.uptime()
        lastActivityDate = now
        deadline = now.addingTimeInterval(timeout)
        deadlineUptime = (sessionStartUptime ?? 0) + timeout
        scheduleInactivityTimer()
    }

    func readerBecameInactive() async throws {
        readerState = .inactive
        try finish(at: observedNow())
    }

    func close() async throws {
        readerState = .closed
        try finish(at: observedNow())
    }

    private func finish(at date: Date) throws {
        inactivityTask?.cancel()
        inactivityTask = nil
        guard let sessionID else { return }
        let effectiveEnd = min(date, deadline ?? date)
        pendingStopAt = effectiveEnd
        try store.finish(sessionID: sessionID, at: effectiveEnd)
        self.sessionID = nil
        deadline = nil
        deadlineUptime = nil
        sessionStartDate = nil
        sessionStartUptime = nil
        lastActivityDate = nil
        pendingStopAt = nil
    }

    private func scheduleInactivityTimer() {
        inactivityTask?.cancel()
        timerRevision &+= 1
        let revision = timerRevision
        let duration = Duration.seconds(timeout)
        inactivityTask = Task { [weak self, sleep] in
            do {
                try await sleep(duration)
                guard !Task.isCancelled else { return }
                try self?.expireIfCurrent(revision: revision)
            } catch is CancellationError {
                // A newer activity or lifecycle transition owns the timer.
            } catch {
                self?.onError(error)
            }
        }
    }

    private func expireIfCurrent(revision: UInt64) throws {
        guard revision == timerRevision, let deadline else { return }
        try finish(at: deadline)
    }

    private func observedNow() -> Date {
        let current = clock.date()
        let result = max(current, lastObservedDate ?? current)
        lastObservedDate = result
        return result
    }

    private func monotonicDate(at uptime: TimeInterval) -> Date {
        guard let sessionStartDate, let sessionStartUptime else { return observedNow() }
        return max(lastActivityDate ?? sessionStartDate, sessionStartDate.addingTimeInterval(
            max(0, uptime - sessionStartUptime)
        ))
    }
}
