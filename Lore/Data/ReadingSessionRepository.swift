import Foundation
import SwiftData

@MainActor
protocol ReadingSessionStore: AnyObject {
    func begin(bookID: UUID, at date: Date) throws -> UUID
    func recordActivity(sessionID: UUID, at date: Date) throws
    func finish(sessionID: UUID, at date: Date) throws
}

struct ReadingTimeSummary: Sendable, Equatable {
    let today: TimeInterval
    let thisWeek: TimeInterval
    let thisMonth: TimeInterval
}

@MainActor
final class ReadingSessionRepository: ReadingSessionStore {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(context: ModelContext, save: ((ModelContext) throws -> Void)? = nil) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func begin(bookID: UUID, at date: Date) throws -> UUID {
        let session = ReadingSessionRecord(bookID: bookID, startedAt: date)
        context.insert(session)
        do {
            try saveContext(context)
            return session.id
        } catch {
            context.delete(session)
            throw error
        }
    }

    func recordActivity(sessionID: UUID, at date: Date) throws {
        guard let session = try session(id: sessionID), session.endedAt == nil else {
            throw ReadingSessionRepositoryError.sessionNotFound
        }
        let previous = session.lastActivityAt
        session.lastActivityAt = max(previous, max(date, session.startedAt))
        do {
            try saveContext(context)
        } catch {
            session.lastActivityAt = previous
            throw error
        }
    }

    func finish(sessionID: UUID, at date: Date) throws {
        guard let session = try session(id: sessionID) else {
            throw ReadingSessionRepositoryError.sessionNotFound
        }
        if session.endedAt != nil { return }
        session.endedAt = max(session.startedAt, date)
        do {
            try saveContext(context)
        } catch {
            session.endedAt = nil
            throw error
        }
    }

    @discardableResult
    func recoverOpenSessions(now: Date) throws -> Int {
        let descriptor = FetchDescriptor<ReadingSessionRecord>(predicate: #Predicate { $0.endedAt == nil })
        let sessions = try context.fetch(descriptor)
        let previousEnds = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.endedAt) })
        for session in sessions {
            session.endedAt = max(session.startedAt, min(now, session.lastActivityAt))
        }
        if !sessions.isEmpty {
            do {
                try saveContext(context)
            } catch {
                for session in sessions { session.endedAt = previousEnds[session.id] ?? nil }
                throw error
            }
        }
        return sessions.count
    }

    func summary(
        containing now: Date,
        calendar: Calendar = .current,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout
    ) throws -> ReadingTimeSummary {
        var localCalendar = calendar
        localCalendar.firstWeekday = 2
        let today = localCalendar.startOfDay(for: now)
        guard let week = localCalendar.dateInterval(of: .weekOfYear, for: now),
              let month = localCalendar.dateInterval(of: .month, for: now),
              let tomorrow = localCalendar.date(byAdding: .day, value: 1, to: today) else {
            return ReadingTimeSummary(today: 0, thisWeek: 0, thisMonth: 0)
        }
        let sessions = try context.fetch(FetchDescriptor<ReadingSessionRecord>())
        return ReadingTimeSummary(
            today: ReadingSessionDuration.total(
                sessions, in: DateInterval(start: today, end: tomorrow), now: now,
                inactivityTimeout: inactivityTimeout
            ),
            thisWeek: ReadingSessionDuration.total(
                sessions, in: week, now: now, inactivityTimeout: inactivityTimeout
            ),
            thisMonth: ReadingSessionDuration.total(
                sessions, in: month, now: now, inactivityTimeout: inactivityTimeout
            )
        )
    }

    func sessions(for bookID: UUID? = nil) throws -> [ReadingSessionRecord] {
        let records: [ReadingSessionRecord]
        if let bookID {
            records = try context.fetch(FetchDescriptor(predicate: #Predicate { $0.bookID == bookID }))
        } else {
            records = try context.fetch(FetchDescriptor())
        }
        return records.sorted { $0.startedAt < $1.startedAt }
    }

    func firstSessionDate(for bookID: UUID) throws -> Date? {
        try sessions(for: bookID).first?.startedAt
    }

    private func session(id: UUID) throws -> ReadingSessionRecord? {
        var descriptor = FetchDescriptor<ReadingSessionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum ReadingSessionDuration {
    static func total(
        _ sessions: [ReadingSessionRecord],
        in interval: DateInterval,
        now: Date,
        inactivityTimeout: TimeInterval
    ) -> TimeInterval {
        sessions.reduce(0) { result, session in
            let sessionEnd = min(
                now,
                session.endedAt ?? session.lastActivityAt.addingTimeInterval(inactivityTimeout)
            )
            let overlapStart = max(interval.start, session.startedAt)
            let overlapEnd = min(interval.end, sessionEnd)
            return result + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }
}

enum ReadingSessionRepositoryError: LocalizedError, Equatable {
    case sessionNotFound

    var errorDescription: String? {
        "La session de lecture active est introuvable."
    }
}
