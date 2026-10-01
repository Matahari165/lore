import SwiftUI

/// Langage de conversation partagé par les discussions IA (livre et bibliothèque).
///
/// Parti pris : une vraie interface de chat. L'utilisateur à droite dans une
/// bulle pleine, Lore à gauche dans une bulle teintée avec son avatar.
/// Aucun dégradé, aucun verre : deux aplats de l'identité Lore, coins
/// resserrés côté queue comme dans les messageries natives.
enum DiscussionChatUI {
    /// Animation d'apparition d'un nouveau message : ressort court depuis le
    /// bas. Opacité seule si Réduire les animations est actif.
    static func insertionAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    static func messageTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
    }
}

/// Bulle de l'utilisateur : pleine, alignée à droite.
struct UserChatBubble: View {
    let text: String
    /// Message en attente d'envoi : même bulle, atténuée.
    var isPending = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 52)
            Text(text)
                .font(.body)
                .foregroundStyle(LoreTheme.canvas)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(LoreTheme.ink, in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 18,
                    style: .continuous
                ))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isPending ? 0.6 : 1.0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPending ? "Message en cours d’envoi : \(text)" : "Vous : \(text)")
    }
}

/// Bulle de Lore : teintée, alignée à gauche, avatar étincelles.
struct AssistantChatBubble<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreTheme.ink)
                .frame(width: 28, height: 28)
                .background(LoreTheme.ink.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(LoreTheme.ink.opacity(0.08), in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            ))

            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Réponse de Lore")
    }
}

/// Indicateur de frappe : trois points qui se relaient. Statique si
/// Réduire les animations est actif.
struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                dots(phase: nil)
            } else {
                PhaseAnimator([0, 1, 2]) { phase in
                    dots(phase: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.4)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lore écrit une réponse")
    }

    private func dots(phase: Int?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(LoreTheme.secondaryInk)
                    .frame(width: 7, height: 7)
                    .opacity(phase.map { $0 == index ? 1.0 : 0.35 } ?? 0.8)
                    .scaleEffect(phase.map { $0 == index ? 1.2 : 0.9 } ?? 1.0)
            }
        }
    }
}
