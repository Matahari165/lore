import Foundation

enum YesterdayReadingSummaryState: Equatable {
    case noReading
    case awaiting(activityLine: String)
    case loading(activityLine: String)
    case available(activityLine: String, markdown: String)
    case missingAPIKey(activityLine: String)
    /// Échec non bloquant (`failedWillRetry`) : rien n'est mis en cache et le jour n'est
    /// jamais marqué comme vu, donc l'utilisateur peut taper « Réessayer » une fois
    /// connecté (appel avec `force: true`) pour relancer la génération.
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

/// Une entrée d'historique de résumé par jour civil local.
struct YesterdayRecapHistoryEntry: Equatable {
    let dayStart: Date
    let fingerprint: String
    let markdown: String
}

/// Keeps the generated recaps on the phone so returning to Accueil never
/// performs the same paid request again for an unchanged reading day.
/// Les résumés réussis sont conservés par jour (`dayStart` + `fingerprint`) et purgés
/// au-delà de 30 jours. Les échecs (hors-ligne, erreur IA, clé illisible) ne sont
/// jamais mis en cache : l'état `.failed` reste réessayable à la prochaine connexion.
struct YesterdayReadingRecapCache {
    private struct Entry: Codable {
        let dayStart: Date
        let fingerprint: String
        let markdown: String
    }

    private static let legacyKey = "home-yesterday-ai-recap-v1"
    private static let key = "home-ai-recap-v2"
    /// Nombre maximal de jours d'historique conservés.
    static let maxKeptDays = 30

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func recap(dayStart: Date, fingerprint: String) -> String? {
        if let markdown = entries()[Self.dayKey(dayStart: dayStart, fingerprint: fingerprint)]?.markdown,
           !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return markdown
        }
        // Migration lue depuis l'ancien format mono-jour.
        guard let data = defaults.data(forKey: Self.legacyKey),
              let legacy = try? JSONDecoder().decode(Entry.self, from: data),
              legacy.dayStart == dayStart,
              legacy.fingerprint == fingerprint,
              !legacy.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return legacy.markdown
    }

    /// Ne met en cache que les résumés réussis non vides. Un texte vide ou un message
    /// d'erreur n'est jamais persisté (no-op silencieux) afin de ne pas masquer une
    /// future tentative réussie.
    func save(_ markdown: String, dayStart: Date, fingerprint: String) throws {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var stored = entries()
        // Migration de l'éventuelle entrée legacy vers le dictionnaire multi-jours.
        if let data = defaults.data(forKey: Self.legacyKey),
           let legacy = try? JSONDecoder().decode(Entry.self, from: data),
           !legacy.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stored[Self.dayKey(dayStart: legacy.dayStart, fingerprint: legacy.fingerprint)] = legacy
        }
        stored[Self.dayKey(dayStart: dayStart, fingerprint: fingerprint)] = Entry(
            dayStart: dayStart,
            fingerprint: fingerprint,
            markdown: markdown
        )
        try persist(purged(stored))
        defaults.removeObject(forKey: Self.legacyKey)
    }

    /// Historique des résumés réussis (J-1, J-2, …), du plus récent au plus ancien.
    /// Contrat de données pour une future UI d'historique ; ne fait aucun appel réseau.
    func recapHistory() -> [YesterdayRecapHistoryEntry] {
        entries().values
            .filter { !$0.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.dayStart > $1.dayStart }
            .map { YesterdayRecapHistoryEntry(dayStart: $0.dayStart, fingerprint: $0.fingerprint, markdown: $0.markdown) }
    }

    private func entries() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return stored
    }

    private func persist(_ stored: [String: Entry]) throws {
        defaults.set(try JSONEncoder().encode(stored), forKey: Self.key)
    }

    /// Purge les entrées dont le jour est à plus de `maxKeptDays` avant l'entrée la plus
    /// récente, en jours civils du calendrier local. La purge a lieu à chaque sauvegarde.
    private func purged(_ stored: [String: Entry]) -> [String: Entry] {
        guard let newest = stored.values.map(\.dayStart).max(),
              let cutoff = calendar.date(byAdding: .day, value: -Self.maxKeptDays, to: newest)
        else { return stored }
        return stored.filter { $0.value.dayStart >= cutoff }
    }

    private static func dayKey(dayStart: Date, fingerprint: String) -> String {
        "\(dayStart.timeIntervalSinceReferenceDate)|\(fingerprint)"
    }
}
