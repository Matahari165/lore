import Foundation
import SwiftData

@MainActor
final class StatisticsDataAdapter {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func snapshot(
        containing now: Date,
        referenceMonth: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout
    ) throws -> StatisticsSnapshot {
        var localCalendar = calendar
        localCalendar.firstWeekday = 2

        let requestedMonth = referenceMonth ?? now
        guard let day = localCalendar.dateInterval(of: .day, for: now),
              let week = localCalendar.dateInterval(of: .weekOfYear, for: now),
              let month = localCalendar.dateInterval(of: .month, for: now),
              let referenceMonthInterval = localCalendar.dateInterval(of: .month, for: requestedMonth)
        else {
            throw StatisticsDataAdapterError.invalidCalendar
        }

        let sessions = try context.fetch(FetchDescriptor<ReadingSessionRecord>())
        let books = try context.fetch(FetchDescriptor<BookRecord>())
        if let invalidBook = books.first(where: { book in
            guard let rating = book.rating else { return false }
            return !(0...10).contains(rating)
        }) {
            throw StatisticsDataAdapterError.invalidRating(bookID: invalidBook.id)
        }
        let firstSessions = Dictionary(grouping: sessions, by: \.bookID)
            .mapValues { records in records.map(\.startedAt).min() }

        let bookSummaries = books.map { book in
            StatisticsBookSummary(
                id: book.id,
                title: book.title,
                author: book.author,
                coverData: book.coverData,
                progress: book.lastProgression,
                startedAt: firstSessions[book.id] ?? nil,
                finishedAt: book.finishedAt,
                readingYear: book.readingYear,
                rating: book.rating
            )
        }

        return StatisticsSnapshot(
            referenceMonth: referenceMonthInterval.start,
            todayDuration: ReadingSessionDuration.total(
                sessions, in: day, now: now, inactivityTimeout: inactivityTimeout
            ),
            weekDuration: ReadingSessionDuration.total(
                sessions, in: week, now: now, inactivityTimeout: inactivityTimeout
            ),
            monthDuration: ReadingSessionDuration.total(
                sessions, in: month, now: now, inactivityTimeout: inactivityTimeout
            ),
            readingDays: readingDays(
                sessions,
                in: referenceMonthInterval,
                now: now,
                calendar: localCalendar,
                inactivityTimeout: inactivityTimeout
            ),
            inProgressBooks: bookSummaries
                .filter { $0.startedAt != nil && $0.finishedAt == nil }
                .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) },
            finishedBooks: bookSummaries
                .filter { $0.finishedAt != nil }
                .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        )
    }

    /// Returns one point for every local calendar day in the requested range.
    /// The adapter owns the aggregation so chart views never reinterpret sessions.
    func activityPoints(
        range: ReadingActivityChartRange,
        containing now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout
    ) throws -> [ReadingActivityPoint] {
        var localCalendar = calendar
        localCalendar.firstWeekday = 2

        let interval: DateInterval?
        switch range {
        case .week:
            interval = localCalendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            interval = localCalendar.dateInterval(of: .month, for: now)
        }
        guard let interval else { throw StatisticsDataAdapterError.invalidCalendar }

        let sessions = try context.fetch(FetchDescriptor<ReadingSessionRecord>())
        var points: [ReadingActivityPoint] = []
        var start = interval.start
        while start < interval.end,
              let end = localCalendar.date(byAdding: .day, value: 1, to: start) {
            let day = DateInterval(start: start, end: min(end, interval.end))
            points.append(ReadingActivityPoint(
                date: start,
                duration: ReadingSessionDuration.total(
                    sessions,
                    in: day,
                    now: now,
                    inactivityTimeout: inactivityTimeout
                )
            ))
            start = end
        }
        return points
    }

    /// Evaluates every completed local day with the currently configured goal.
    /// Today may extend a streak, but an unfinished today does not break yesterday's streak.
    func goalStreak(
        targetMinutes: Int,
        containing now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout
    ) throws -> DailyGoalStreak {
        guard DailyReadingGoal.allowedMinutes.contains(targetMinutes) else {
            throw DailyReadingGoalError.invalidMinutes(targetMinutes)
        }

        var localCalendar = calendar
        localCalendar.firstWeekday = 2
        let sessions = try context.fetch(FetchDescriptor<ReadingSessionRecord>())
        guard let firstStart = sessions.map(\.startedAt).min() else { return .empty }

        let firstDay = localCalendar.startOfDay(for: firstStart)
        let today = localCalendar.startOfDay(for: now)
        let requiredSeconds = TimeInterval(targetMinutes * 60)
        var reachedDays: Set<Date> = []
        var best = 0
        var running = 0
        var dayStart = firstDay

        while dayStart <= today,
              let nextDay = localCalendar.date(byAdding: .day, value: 1, to: dayStart) {
            let duration = ReadingSessionDuration.total(
                sessions,
                in: DateInterval(start: dayStart, end: nextDay),
                now: now,
                inactivityTimeout: inactivityTimeout
            )
            if duration >= requiredSeconds {
                reachedDays.insert(dayStart)
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
            dayStart = nextDay
        }

        let currentAnchor: Date
        if reachedDays.contains(today) {
            currentAnchor = today
        } else if let yesterday = localCalendar.date(byAdding: .day, value: -1, to: today) {
            currentAnchor = yesterday
        } else {
            return DailyGoalStreak(currentDays: 0, bestDays: best)
        }

        var current = 0
        var cursor = currentAnchor
        while reachedDays.contains(cursor) {
            current += 1
            guard let previous = localCalendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return DailyGoalStreak(currentDays: current, bestDays: best)
    }

    private func readingDays(
        _ sessions: [ReadingSessionRecord],
        in month: DateInterval,
        now: Date,
        calendar: Calendar,
        inactivityTimeout: TimeInterval
    ) -> [ReadingDaySummary] {
        var summaries: [ReadingDaySummary] = []
        var start = month.start
        while start < month.end,
              let end = calendar.date(byAdding: .day, value: 1, to: start) {
            let duration = ReadingSessionDuration.total(
                sessions,
                in: DateInterval(start: start, end: min(end, month.end)),
                now: now,
                inactivityTimeout: inactivityTimeout
            )
            if duration > 0 {
                summaries.append(ReadingDaySummary(date: start, duration: duration))
            }
            start = end
        }
        return summaries
    }
}

enum StatisticsDataAdapterError: Error, Equatable {
    case invalidCalendar
    case invalidRating(bookID: UUID)
}
