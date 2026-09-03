import Foundation

@MainActor
final class DailyReadingRecapEngine {
    typealias SessionLoader = @MainActor (UUID) throws -> [ReadingRecapSession]

    private let store: any ReadingRecapStateStore
    private let loadSessions: SessionLoader
    private var calendar: Calendar
    private let inactivityTimeout: TimeInterval

    init(
        store: any ReadingRecapStateStore,
        calendar: Calendar = .current,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout,
        loadSessions: @escaping SessionLoader
    ) {
        self.store = store
        self.calendar = calendar
        self.inactivityTimeout = inactivityTimeout
        self.loadSessions = loadSessions
    }

    convenience init(
        store: any ReadingRecapStateStore,
        calendar: Calendar = .current,
        inactivityTimeout: TimeInterval = ReadingActivityPolicy.defaultInactivityTimeout,
        sessionRepository: ReadingSessionRepository
    ) {
        self.init(store: store, calendar: calendar, inactivityTimeout: inactivityTimeout) { bookID in
            try sessionRepository.sessions(for: bookID).map {
                ReadingRecapSession(
                    startedAt: $0.startedAt,
                    lastActivityAt: $0.lastActivityAt,
                    endedAt: $0.endedAt
                )
            }
        }
    }

    /// Enregistre les deux bornes de lecture d'une journée. Le premier Locator est immuable ;
    /// les appels suivants ne déplacent que le dernier Locator.
    /// 100 % local (UserDefaults + SwiftData via le store) : aucun appel réseau, donc
    /// utilisable dès la première ouverture du jour, même hors-ligne et sans session active.
    /// Un saut de navigation (`didJumpTo` : sommaire, surlignage) n'appelle jamais cette
    /// méthode : seuls le premier Locator immuable et le dernier Locator mobile définissent
    /// l'intervalle résumé.
    func recordCheckpoint(bookID: UUID, locator: StoredLocator, at date: Date) throws {
        let dayStart = calendar.startOfDay(for: date)
        let recapLocator = ReadingRecapLocator(locator)

        if let existing = try store.checkpoint(for: bookID, localDayStart: dayStart) {
            let isNewer = date >= existing.lastRecordedAt
            try store.saveCheckpoint(ReadingRecapCheckpoint(
                bookID: bookID,
                localDayStart: dayStart,
                firstLocator: existing.firstLocator,
                lastLocator: isNewer ? recapLocator : existing.lastLocator,
                firstRecordedAt: existing.firstRecordedAt,
                lastRecordedAt: max(existing.lastRecordedAt, date)
            ))
        } else {
            try store.saveCheckpoint(ReadingRecapCheckpoint(
                bookID: bookID,
                localDayStart: dayStart,
                firstLocator: recapLocator,
                lastLocator: recapLocator,
                firstRecordedAt: date,
                lastRecordedAt: date
            ))
        }
    }

    /// À appeler avant de commencer une nouvelle activité de lecture. Cette méthode ne marque
    /// jamais le résumé comme vu : seul `markShown` le fait après succès ou fermeture explicite.
    func eligibility(for bookID: UUID, at now: Date) throws -> ReadingRecapEligibility {
        let today = calendar.startOfDay(for: now)
        if let shownDay = try store.lastShownDay(for: bookID),
           calendar.isDate(shownDay, inSameDayAs: today) {
            return .alreadyShownToday
        }

        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: today),
              let previousDayEnd = calendar.date(byAdding: .day, value: 1, to: previousDay) else {
            return .unavailable(.noPreviousDay)
        }
        let dayInterval = DateInterval(start: previousDay, end: previousDayEnd)
        let overlaps = try overlapsDuring(dayInterval, for: bookID)
        guard let firstActivityAt = overlaps.map(\.start).min(),
              let lastActivityAt = overlaps.map(\.end).max() else {
            return .unavailable(.noReadingOnPreviousDay)
        }
        guard let checkpoint = try store.checkpoint(for: bookID, localDayStart: previousDay) else {
            return .unavailable(.missingLocatorCheckpoints)
        }

        return .eligible(ReadingRecapWindow(
            bookID: bookID,
            localDayInterval: dayInterval,
            firstActivityAt: firstActivityAt,
            lastActivityAt: lastActivityAt,
            exactReadingDuration: overlaps.reduce(0) { $0 + $1.duration },
            firstLocator: checkpoint.firstLocator,
            lastLocator: checkpoint.lastLocator
        ))
    }

    /// Un échec ne bloque pas une nouvelle tentative. Un succès ou une fermeture volontaire
    /// évite toute nouvelle proposition pour ce livre pendant la même journée locale.
    /// Concrètement : `.failed` ne marque rien (`markShown` est un no-op), donc le résumé
    /// de veille en échec hors-ligne est réessayé à la prochaine connexion via l'action
    /// « Réessayer » (appel avec `force: true`) ; `.delivered` et `.dismissed` marquent le jour.
    func markShown(for bookID: UUID, at date: Date, completion: ReadingRecapCompletion) throws {
        guard completion != .failed else { return }
        try store.saveLastShownDay(calendar.startOfDay(for: date), for: bookID)
    }

    /// Jours passés (J-1, J-2, …) disposant à la fois de sessions recoupant le jour civil
    /// et de checkpoints first/last Locator, du plus récent au plus ancien.
    /// Contrat de données pour un futur historique multi-jours (persistance :
    /// `YesterdayReadingRecapCache.recapHistory()`). Ne marque jamais un jour comme vu,
    /// ne fait aucun appel réseau et ne touche pas à l'UI : réutiliser
    /// `eligibility(for:at:)` pour la veille, `availableDays` pour l'historique.
    func availableDays(for bookID: UUID, lastN: Int, at now: Date) throws -> [ReadingRecapWindow] {
        guard lastN > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var windows: [ReadingRecapWindow] = []
        for offset in 1...lastN {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { continue }
            let dayInterval = DateInterval(start: dayStart, end: dayEnd)
            let overlaps = try overlapsDuring(dayInterval, for: bookID)
            guard let firstActivityAt = overlaps.map(\.start).min(),
                  let lastActivityAt = overlaps.map(\.end).max(),
                  let checkpoint = try store.checkpoint(for: bookID, localDayStart: dayStart)
            else { continue }
            windows.append(ReadingRecapWindow(
                bookID: bookID,
                localDayInterval: dayInterval,
                firstActivityAt: firstActivityAt,
                lastActivityAt: lastActivityAt,
                exactReadingDuration: overlaps.reduce(0) { $0 + $1.duration },
                firstLocator: checkpoint.firstLocator,
                lastLocator: checkpoint.lastLocator
            ))
        }
        return windows
    }

    private func overlapsDuring(_ dayInterval: DateInterval, for bookID: UUID) throws -> [DateInterval] {
        try loadSessions(bookID).compactMap { session -> DateInterval? in
            let effectiveEnd = session.endedAt
                ?? session.lastActivityAt.addingTimeInterval(inactivityTimeout)
            let start = max(session.startedAt, dayInterval.start)
            let end = min(effectiveEnd, dayInterval.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
    }
}
