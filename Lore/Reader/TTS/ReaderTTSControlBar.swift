import SwiftUI

/// Barre de contrôle compacte et flottante pour la lecture vocale dans Lore.
///
/// Style sobre en verre liquide (Liquid Glass), commandes 44×44 accessibles,
/// affichage de la vitesse et navigation par phrase.
struct ReaderTTSControlBar: View {
    let tts: ReaderTTSPlaybackController
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { tts.cyclePlaybackRate() }) {
                Text(tts.playbackRateLabel)
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vitesse de lecture vocale : \(tts.playbackRateLabel)")

            Divider().frame(height: 20)

            Button(action: { tts.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Phrase précédente")

            Button(action: { tts.togglePlayback() }) {
                Image(systemName: tts.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tts.isPlaying ? "Mettre en pause la lecture vocale" : "Reprendre la lecture vocale")

            Button(action: { tts.next() }) {
                Image(systemName: "forward.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Phrase suivante")

            Divider().frame(height: 20)

            Button(action: { tts.stop() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrêter la lecture vocale")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .readerGlass(in: Capsule(), reduceTransparency: reduceTransparency, interactive: true)
    }
}
