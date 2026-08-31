import Foundation

enum YesterdayReadingSummaryState: Equatable {
    case noReading
    case awaiting(activityLine: String)
    case loading(activityLine: String)
    case available(activityLine: String, markdown: String)
    case missingAPIKey(activityLine: String)
    case failed(activityLine: String, message: String)

    var activityLine: String? {
        switch self {
        case .noReading:
            nil
        case let .awaiting(activityLine),
             let .loading(activityLine),
             let .available(activityLine, _),
             let .missingAPIKey(activityLine),
             let .failed(activityLine, _):
            activityLine
        }
    }
}

/// Keeps the generated recap on the phone so returning to Accueil never
/// performs the same paid request again for an unchanged reading day.
struct YesterdayReadingRecapCache {
    private struct Entry: Codable {
        let dayStart: Date
        let fingerprint: String
        let markdown: String
    }

    private static let key = "home-yesterday-ai-recap-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recap(dayStart: Date, fingerprint: String) -> String? {
        guard let data = defaults.data(forKey: Self.key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.dayStart == dayStart,
              entry.fingerprint == fingerprint,
              !entry.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return entry.markdown
    }

    func save(_ markdown: String, dayStart: Date, fingerprint: String) throws {
        let entry = Entry(dayStart: dayStart, fingerprint: fingerprint, markdown: markdown)
        defaults.set(try JSONEncoder().encode(entry), forKey: Self.key)
    }
}
