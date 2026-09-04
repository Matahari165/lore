import Foundation
import UserNotifications

/// Service unique des notifications liées à l'objectif quotidien de lecture.
///
/// Règles produit :
/// - aucun titre ni contenu de livre dans les notifications, uniquement des durées ;
/// - une seule notification « objectif atteint » par jour local ;
/// - un rappel programmé à 21 h 00 locale, replanifié à chaque lancement et
///   après chaque fermeture du lecteur, annulé si l'objectif est désactivé ou atteint ;
/// - aucun mode d'arrière-plan requis : `UNNotification` suffit.
///
/// La logique de décision (`shouldNotify`, `shouldRemind21h`, `dayKey`) est pure
/// et testable sans `UNNotificationCenter` réel.
final class DailyGoalNotifier: @unchecked Sendable {
    static let notifiedDayDefaultsKey = "lore.lastGoalNotifiedDay"
    static let reachedIdentifier = "lore.goal.reached"
    static let reminderIdentifier = "lore.goal.reminder-21h"
    static let reminderHour = 21
    static let reminderMinute = 0

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = userDefaults
        self.calendar = calendar
    }

    // MARK: - Logique pure (testable sans iOS)

    /// Clé du jour local (`aaaa-MM-jj`) utilisée pour ne notifier qu'une fois par jour.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Vrai quand l'objectif vient d'être atteint et n'a pas encore été notifié ce jour-là.
    static func shouldNotify(
        isReached: Bool,
        todayDayKey: String,
        lastNotifiedDayKey: String?
    ) -> Bool {
        isReached && todayDayKey != lastNotifiedDayKey
    }

    /// Vrai quand le rappel de 21 h doit être programmé : objectif actif et non atteint.
    /// La vérification du jour même (`todayDuration < target`) est faite par l'appelant
    /// via `isReached` avant de (re)planifier, au lancement puis après fermeture du lecteur.
    static func shouldRemind21h(isEnabled: Bool, isReached: Bool) -> Bool {
        isEnabled && !isReached
    }

    /// Minutes restantes affichées, arrondies au supérieur, minimum 1 (rappel seulement si non atteint).
    static func displayedRemainingMinutes(todayDuration: TimeInterval, targetMinutes: Int) -> Int {
        let remaining = Double(targetMinutes) * 60 - max(0, todayDuration)
        return max(1, Int(ceil(remaining / 60)))
    }

    static func reachedTitle() -> String { "Objectif atteint" }

    static func reachedBody(targetMinutes: Int) -> String {
        "Objectif atteint : \(targetMinutes) min de lecture. Bravo !"
    }

    static func reminderTitle() -> String { "Rappel de lecture" }

    static func reminderBody(remainingMinutes: Int) -> String {
        "Il vous reste \(remainingMinutes) min pour atteindre votre objectif du jour."
    }

    // MARK: - État persistant

    var lastNotifiedDayKey: String? {
        defaults.string(forKey: Self.notifiedDayDefaultsKey)
    }

    // MARK: - Autorisation

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Demande l'autorisation seulement si l'utilisateur ne s'est pas encore prononcé.
    /// L'explication en français est affichée par l'appelant avant cet appel.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Point d'entrée

    /// Met à jour les notifications après `reloadDailyGoal` / `updateTodayDuration` :
    /// notifie immédiatement si l'objectif vient d'être atteint (une fois par jour),
    /// sinon (re)planifie le rappel de 21 h. Annule le rappel si l'objectif est
    /// désactivé (`targetMinutes == nil`) ou vient d'être atteint.
    func refreshGoalState(targetMinutes: Int?, todayDuration: TimeInterval, now: Date = Date()) async {
        guard let targetMinutes else {
            cancelEveningReminder()
            return
        }
        let progress = DailyGoalProgress(readSeconds: todayDuration, targetMinutes: targetMinutes)
        let todayKey = Self.dayKey(for: now, calendar: calendar)
        if Self.shouldNotify(
            isReached: progress.isReached,
            todayDayKey: todayKey,
            lastNotifiedDayKey: lastNotifiedDayKey
        ) {
            await notifyGoalReached(targetMinutes: targetMinutes)
            defaults.set(todayKey, forKey: Self.notifiedDayDefaultsKey)
            cancelEveningReminder()
        } else if Self.shouldRemind21h(isEnabled: true, isReached: progress.isReached) {
            await scheduleEveningReminder(
                remainingMinutes: Self.displayedRemainingMinutes(
                    todayDuration: todayDuration,
                    targetMinutes: targetMinutes
                )
            )
        } else {
            // Objectif atteint mais déjà notifié aujourd'hui : aucun rappel résiduel.
            cancelEveningReminder()
        }
    }

    func cancelEveningReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    // MARK: - Envois privés

    private func notifyGoalReached(targetMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = Self.reachedTitle()
        content.body = Self.reachedBody(targetMinutes: targetMinutes)
        content.sound = .default
        // Déclencheur immédiat : bannière + son, y compris en avant-plan grâce au delegate.
        let request = UNNotificationRequest(
            identifier: Self.reachedIdentifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func scheduleEveningReminder(remainingMinutes: Int) async {
        cancelEveningReminder()
        let content = UNMutableNotificationContent()
        content.title = Self.reminderTitle()
        content.body = Self.reminderBody(remainingMinutes: remainingMinutes)
        content.sound = .default
        var components = DateComponents()
        components.hour = Self.reminderHour
        components.minute = Self.reminderMinute
        // Répété chaque jour ; le contenu (minutes restantes) est recalculé à chaque
        // replanification au lancement et après fermeture du lecteur, et la demande
        // est annulée dès que l'objectif est atteint ou désactivé.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}

/// Présente les rappels Lore au premier plan, sauf pendant une lecture lorsque
/// l'utilisateur a choisi le mode de concentration interne.
/// Conservé en singleton afin de survivre à l'initialisation de `LoreApp`.
final class DailyGoalForegroundDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = DailyGoalForegroundDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await Self.presentationOptions(
            silencesLoreInterruptions: ReadingFocusMode.shared.silencesLoreInterruptions
        )
    }

    nonisolated static func presentationOptions(
        silencesLoreInterruptions: Bool
    ) -> UNNotificationPresentationOptions {
        silencesLoreInterruptions ? [.list] : [.banner, .list, .sound]
    }
}
