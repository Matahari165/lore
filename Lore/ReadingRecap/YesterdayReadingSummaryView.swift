import SwiftUI

struct YesterdayReadingSummaryView: View {
    let state: YesterdayReadingSummaryState
    let dayTitle: String?
    let isHistoryDay: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    @State private var isExpanded = false

    init(
        state: YesterdayReadingSummaryState,
        dayTitle: String? = nil,
        isHistoryDay: Bool = false,
        canGoPrevious: Bool = false,
        canGoNext: Bool = false,
        onPrevious: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {},
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.state = state
        self.dayTitle = dayTitle
        self.isHistoryDay = isHistoryDay
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle ?? "Hier")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            historyNavigation

            switch state {
            case .noReading:
                Text(isHistoryDay ? "Aucun résumé pour ce jour." : "Rien n’a été lu hier.")
                    .foregroundStyle(LoreTheme.secondaryInk)

            case let .awaiting(activityLine), let .loading(activityLine):
                activityText(activityLine)
                HStack(spacing: 9) {
                    ProgressView()
                    Text("Lore prépare un résumé court…")
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)

            case let .available(activityLine, markdown):
                activityText(activityLine)
                recapText(markdown)

            case let .missingAPIKey(activityLine):
                activityText(activityLine)
                Text("Ajoutez votre clé OpenAI pour résumer le contenu lu.")
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
                HStack(spacing: 14) {
                    Button("Ouvrir les réglages", action: onOpenSettings)
                        .frame(minWidth: 44, minHeight: 44)
                    Button("Réessayer", action: onRetry)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .font(.subheadline.weight(.semibold))

            case let .failed(activityLine, message):
                activityText(activityLine)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
                Button("Réessayer", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: dayTitle ?? "") { _, _ in isExpanded = false }
    }

    private var historyNavigation: some View {
        HStack {
            Button(action: onPrevious) {
                Label("Jour précédent", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoPrevious)
            .accessibilityHint("Voir le résumé du jour précédent")

            Spacer(minLength: 8)

            Button(action: onNext) {
                HStack(spacing: 4) {
                    Text("Jour suivant")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Jour suivant")
            .accessibilityHint("Revenir vers un jour plus récent")
        }
        .foregroundStyle(LoreTheme.secondaryInk)
    }

    private func activityText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(LoreTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func recapText(_ markdown: String) -> some View {
        // Le Markdown natif rend les listes « - » avec leurs retours ligne.
        // conciseRecap renvoie déjà des puces courtes ; on les affiche telles
        // quelles, sans parser maison. lineSpacing élargit la lecture sans
        // hauteur fixe pour que le conteneur grandisse dans le ScrollView.
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let attributed = ReaderMarkdownRenderer.attributedString(from: markdown) {
                    Text(attributed)
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.ink)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityLabel("Résumé de la lecture. \(markdown)")
                } else {
                    Text(markdown)
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.ink)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityLabel("Résumé de la lecture. \(markdown)")
                }
            }
            .onChange(of: markdown) { _, _ in isExpanded = false }

            Button(isExpanded ? "Voir moins" : "Voir plus") {
                isExpanded.toggle()
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHint(isExpanded ? "Réduit le résumé à six lignes" : "Affiche le résumé complet")
        }
    }
}
