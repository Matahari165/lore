import Foundation
import Observation

protocol DailyReadingGoalStore {
    func loadMinutes() throws -> Int?
    func saveMinutes(_ minutes: Int?) throws
}

enum DailyReadingGoalError: LocalizedError, Equatable {
    case invalidMinutes(Int)
    case unreadableValue

    var errorDescription: String? {
        switch self {
        case .invalidMinutes:
            "L’objectif doit être compris entre 5 et 180 minutes."
        case .unreadableValue:
            "L’objectif enregistré ne peut pas être lu."
        }
    }
}

struct UserDefaultsDailyReadingGoalStore: DailyReadingGoalStore {
    static let key = "dailyReadingGoalMinutes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMinutes() throws -> Int? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        guard let number = defaults.object(forKey: Self.key) as? NSNumber else {
            throw DailyReadingGoalError.unreadableValue
        }
        let minutes = number.intValue
        guard DailyReadingGoal.allowedMinutes.contains(minutes) else {
            throw DailyReadingGoalError.invalidMinutes(minutes)
        }
        return minutes
    }

    func saveMinutes(_ minutes: Int?) throws {
        if let minutes, !DailyReadingGoal.allowedMinutes.contains(minutes) {
            throw DailyReadingGoalError.invalidMinutes(minutes)
        }
        if let minutes {
            defaults.set(minutes, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}

enum DailyReadingGoal {
    static let allowedMinutes = 5...180
    static let defaultMinutes = 20
}

struct DailyGoalProgress: Equatable, Sendable {
    let readSeconds: TimeInterval
    let targetMinutes: Int
    let streak: DailyGoalStreak

    init(
        readSeconds: TimeInterval,
        targetMinutes: Int,
        streak: DailyGoalStreak = .empty
    ) {
        self.readSeconds = max(0, readSeconds)
        self.targetMinutes = min(max(targetMinutes, DailyReadingGoal.allowedMinutes.lowerBound), DailyReadingGoal.allowedMinutes.upperBound)
        self.streak = streak
    }

    var exactFraction: Double { readSeconds / (Double(targetMinutes) * 60) }
    var visualFraction: Double { min(1, exactFraction) }
    var remainingSeconds: TimeInterval { max(0, Double(targetMinutes) * 60 - readSeconds) }
    var isReached: Bool { remainingSeconds == 0 }
    var displayedReadMinutes: Int { Int(floor(readSeconds / 60)) }
    var displayedRemainingMinutes: Int { Int(ceil(remainingSeconds / 60)) }
}

struct DailyGoalStreak: Equatable, Sendable {
    let currentDays: Int
    let bestDays: Int

    static let empty = DailyGoalStreak(currentDays: 0, bestDays: 0)
}

enum DailyGoalState: Equatable {
    case disabled
    case active(DailyGoalProgress)
    case failed(message: String)
}

@MainActor
@Observable
final class DailyReadingGoalModel {
    private let store: any DailyReadingGoalStore
    private(set) var minutes: Int?
    private(set) var errorMessage: String?
    private(set) var todayDuration: TimeInterval = 0
    private(set) var progressErrorMessage: String?
    private(set) var streak: DailyGoalStreak = .empty

    init(store: any DailyReadingGoalStore) {
        self.store = store
        reload()
    }

    var isEnabled: Bool { minutes != nil }

    var state: DailyGoalState {
        if let errorMessage { return .failed(message: errorMessage) }
        guard let minutes else { return .disabled }
        if let progressErrorMessage { return .failed(message: progressErrorMessage) }
        return .active(DailyGoalProgress(
            readSeconds: todayDuration,
            targetMinutes: minutes,
            streak: streak
        ))
    }

    func updateTodayDuration(_ duration: TimeInterval) {
        todayDuration = max(0, duration)
        progressErrorMessage = nil
    }

    func updateStreak(_ streak: DailyGoalStreak) {
        self.streak = streak
    }

    func markProgressUnavailable() {
        progressErrorMessage = "La progression du jour n’est pas disponible pour le moment."
    }

    func reload() {
        do {
            minutes = try store.loadMinutes()
            errorMessage = nil
        } catch {
            minutes = nil
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool) {
        save(enabled ? (minutes ?? DailyReadingGoal.defaultMinutes) : nil)
    }

    func setMinutes(_ minutes: Int) {
        save(minutes)
    }

    private func save(_ minutes: Int?) {
        do {
            try store.saveMinutes(minutes)
            self.minutes = minutes
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
