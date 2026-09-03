import Foundation
import Testing
@testable import Lore

/// Logique de déclenchement des notifications d'objectif, sans UNNotificationCenter réel.
struct DailyGoalNotificationTests {
    @Test func notifiesOnlyOncePerLocalDayWhenGoalIsReached() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))!
        let todayKey = DailyGoalNotifier.dayKey(for: today, calendar: calendar)

        // Première atteinte du jour : on notifie.
        #expect(DailyGoalNotifier.shouldNotify(
            isReached: true,
            todayDayKey: todayKey,
            lastNotifiedDayKey: nil
        ))
        // Déjà notifié aujourd'hui : silence.
        #expect(!DailyGoalNotifier.shouldNotify(
            isReached: true,
            todayDayKey: todayKey,
            lastNotifiedDayKey: todayKey
        ))
        // Notifié un autre jour : on notifie à nouveau.
        #expect(DailyGoalNotifier.shouldNotify(
            isReached: true,
            todayDayKey: todayKey,
            lastNotifiedDayKey: "2026-09-02"
        ))
    }

    @Test func neverNotifiesWhileGoalIsUnreached() {
        #expect(!DailyGoalNotifier.shouldNotify(
            isReached: false,
            todayDayKey: "2026-09-03",
            lastNotifiedDayKey: nil
        ))
        #expect(!DailyGoalNotifier.shouldNotify(
            isReached: false,
            todayDayKey: "2026-09-03",
            lastNotifiedDayKey: "2026-09-02"
        ))
    }

    @Test func schedulesEveningReminderOnlyWhenEnabledAndUnreached() {
        #expect(DailyGoalNotifier.shouldRemind21h(isEnabled: true, isReached: false))
        #expect(!DailyGoalNotifier.shouldRemind21h(isEnabled: true, isReached: true))
        #expect(!DailyGoalNotifier.shouldRemind21h(isEnabled: false, isReached: false))
        #expect(!DailyGoalNotifier.shouldRemind21h(isEnabled: false, isReached: true))
    }

    @Test func dayKeyFollowsTheLocalCalendar() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        // 2 septembre 23 h 30 UTC = 3 septembre 1 h 30 à Paris : jour local différent.
        let late = Date(timeIntervalSince1970: 1_788_391_800)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        #expect(DailyGoalNotifier.dayKey(for: late, calendar: paris) == "2026-09-03")
        #expect(DailyGoalNotifier.dayKey(for: late, calendar: utc) == "2026-09-02")
        #expect(DailyGoalNotifier.dayKey(for: late, calendar: paris)
            != DailyGoalNotifier.dayKey(for: late, calendar: utc))
    }

    @Test func notificationBodiesContainOnlyDurations() {
        let reached = DailyGoalNotifier.reachedBody(targetMinutes: 20)
        let reminder = DailyGoalNotifier.reminderBody(remainingMinutes: 8)

        #expect(reached == "Objectif atteint : 20 min de lecture. Bravo !")
        #expect(reminder == "Il vous reste 8 min pour atteindre votre objectif du jour.")
        #expect(!reached.contains("Deep Work"))
        #expect(!reminder.contains("Deep Work"))
    }

    @Test func remainingMinutesRoundUpWithAFloorOfOne() {
        #expect(DailyGoalNotifier.displayedRemainingMinutes(todayDuration: 12 * 60, targetMinutes: 20) == 8)
        #expect(DailyGoalNotifier.displayedRemainingMinutes(todayDuration: 19 * 60 + 31, targetMinutes: 20) == 1)
        #expect(DailyGoalNotifier.displayedRemainingMinutes(todayDuration: 25 * 60, targetMinutes: 20) == 1)
    }
}
