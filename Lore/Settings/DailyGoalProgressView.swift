import SwiftUI

struct DailyGoalProgressView: View {
    let state: DailyGoalState
    var showsDisabledState = true
    var compact = false
    /// Optional navigation hook used by Accueil and Statistiques. Keeping it
    /// optional preserves the compact, non-interactive presentation elsewhere.
    var onTap: (() -> Void)?

    init(
        state: DailyGoalState,
        showsDisabledState: Bool = true,
        compact: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.state = state
        self.showsDisabledState = showsDisabledState
        self.compact = compact
        self.onTap = onTap
    }

    var body: some View {
        switch state {
        case .disabled:
            if showsDisabledState {
                Label("Aucun objectif quotidien", systemImage: "circle.dashed")
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .accessibilityHint("Vous pouvez en définir un dans Réglages")
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(LoreTheme.secondaryInk)
                .accessibilityLabel("Objectif indisponible. \(message)")
        case let .active(progress):
            if let onTap {
                Button(action: onTap) {
                    progressContent(progress)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Affiche les minutes de lecture par jour")
            } else {
                progressContent(progress)
            }
        }
    }

    private func progressContent(_ progress: DailyGoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Objectif du jour", systemImage: progress.isReached ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text("\(progress.displayedReadMinutes) / \(progress.targetMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            LoreProgressBar(value: progress.visualFraction, height: 8)

            if !compact {
                Text(progress.isReached ? "Objectif atteint" : "Objectif en cours")
                    .font(.caption)
                    .foregroundStyle(LoreTheme.secondaryInk)
            }

            Label(streakLabel(progress.streak.currentDays), systemImage: "flame")
                .font(.caption.weight(.medium))
                .foregroundStyle(LoreTheme.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Objectif quotidien")
        .accessibilityValue(accessibilityValue(progress))
    }

    private func streakLabel(_ days: Int) -> String {
        if compact {
            return days == 1 ? "1 jour" : "\(days) jours"
        }
        return days == 1 ? "Flamme 1 jour" : "Flamme \(days) jours"
    }

    private func accessibilityValue(_ progress: DailyGoalProgress) -> String {
        let status = compact
            ? (progress.isReached ? "Atteint." : "En cours.")
            : (progress.isReached ? "Atteint." : "Objectif en cours.")
        return "\(status) \(progress.displayedReadMinutes) minutes lues sur \(progress.targetMinutes). \(streakLabel(progress.streak.currentDays))."
    }
}
