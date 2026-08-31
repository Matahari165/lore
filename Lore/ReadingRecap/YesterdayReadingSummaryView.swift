import SwiftUI

struct YesterdayReadingSummaryView: View {
    let state: YesterdayReadingSummaryState
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Hier")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            switch state {
            case .noReading:
                Text("Rien n’a été lu hier.")
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
                    Button("Réessayer", action: onRetry)
                }
                .font(.subheadline.weight(.semibold))

            case let .failed(activityLine, message):
                activityText(activityLine)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
                Button("Réessayer", action: onRetry)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(LoreTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func recapText(_ markdown: String) -> some View {
        if let attributed = ReaderMarkdownRenderer.attributedString(from: markdown) {
            Text(attributed)
                .font(.subheadline)
                .foregroundStyle(LoreTheme.ink)
                .lineLimit(9)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Résumé de la lecture d’hier. \(markdown)")
        } else {
            Text(markdown)
                .font(.subheadline)
                .foregroundStyle(LoreTheme.ink)
                .lineLimit(9)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
