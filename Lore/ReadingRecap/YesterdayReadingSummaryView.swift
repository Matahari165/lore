import SwiftUI

/// Presentation-only component for the home feed. The owner of the recap
/// pipeline supplies the already-generated local/AI text and controls loading;
/// this keeps LibraryView free of extraction and network concerns.
struct YesterdayReadingSummaryView: View {
    let summary: String?
    var isLoading = false
    var onRequestSummary: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Résumé de votre lecture d’hier…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LoreTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hier")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(.body)
                    .foregroundStyle(LoreTheme.ink)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Résumé de votre lecture d’hier. \(summary)")
        } else if let onRequestSummary {
            Button("Afficher le résumé d’hier", action: onRequestSummary)
                .font(.subheadline.weight(.medium))
                .accessibilityHint("Génère un résumé à partir de votre lecture de la veille")
        }
    }
}
