import SwiftUI

/// Composants et modificateurs fournissant la compatibilité entre iOS 17 et les effets Liquid Glass (iOS 26+).
public struct LoreGlassContainer<Content: View>: View {
    public let spacing: CGFloat?
    @ViewBuilder public let content: () -> Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            VStack(spacing: spacing) {
                content()
            }
        }
    }
}

public extension View {
    /// Applique un effet Liquid Glass si disponible sur l'OS hôte, ou un ultraThinMaterial soigné sous iOS 17.
    @ViewBuilder
    func loreGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// Rétrocompatibilité pour l'identifiant glassEffectID sur iOS 26+.
    @ViewBuilder
    func loreGlassEffectID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Rétrocompatibilité pour la minimisation de la barre d'onglets sur iOS 26+.
    @ViewBuilder
    func loreTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
