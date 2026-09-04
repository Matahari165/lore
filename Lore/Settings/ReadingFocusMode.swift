import Foundation

@MainActor
final class ReadingFocusMode {
    static let shared = ReadingFocusMode()

    private static let enabledKey = "reading.focus-mode.enabled.v1"

    private let defaults: UserDefaults
    private(set) var isReaderActive = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var silencesLoreInterruptions: Bool {
        Self.shouldSilenceLoreInterruptions(
            isEnabled: isEnabled,
            isReaderActive: isReaderActive
        )
    }

    func setEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func setReaderActive(_ isActive: Bool) {
        isReaderActive = isActive
    }

    nonisolated static func shouldSilenceLoreInterruptions(
        isEnabled: Bool,
        isReaderActive: Bool
    ) -> Bool {
        isEnabled && isReaderActive
    }
}

struct ReadingFocusGuide: Equatable, Sendable {
    struct Step: Equatable, Identifiable, Sendable {
        let id: Int
        let title: String
        let detail: String
    }

    static let steps = [
        Step(
            id: 1,
            title: "Créez un mode Lecture",
            detail: "Dans Réglages, ouvrez Concentration, touchez +, puis Personnalisé. Choisissez les personnes et apps qui peuvent vous interrompre."
        ),
        Step(
            id: 2,
            title: "Associez-le à Lore",
            detail: "Dans ce mode, touchez Ajouter un programme, puis App, et sélectionnez Lore."
        ),
        Step(
            id: 3,
            title: "Gardez le contrôle",
            detail: "iOS utilise alors ce mode pendant que Lore est ouverte, puis l’arrête lorsque vous la quittez. Supprimez ce programme à tout moment pour arrêter l’automatisation."
        )
    ]

    static let limitation = "Lore ne peut pas activer Ne pas déranger directement. Ce réglage iOS suit donc l’app entière, pas seulement l’écran du lecteur."
}
