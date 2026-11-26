import SwiftUI

/// Effets au survol, partagés par toute l'app. Ils s'effacent si « Réduire les animations » est activé.

/// Soulève légèrement un élément (cartes, tuiles, pastilles).
struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.02
    var lift: CGFloat = 2
    var shadow = true
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !reduceMotion ? scale : 1)
            .offset(y: on && !reduceMotion ? -lift : 0)
            .shadow(color: .black.opacity(shadow && on ? 0.12 : 0), radius: on ? 14 : 0, y: on ? 6 : 0)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { on = hovering }
                    }
            )
    }
}

/// Surligne une ligne (historique, exceptions, faits).
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = -4
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(on ? 0.06 : 0))
                    .padding(inset)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { on = hovering }
            }
    }
}

/// Fait rebondir un petit bouton ou une icône.
struct HoverPop: ViewModifier {
    var scale: CGFloat = 1.15
    var angle: Double = 0
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !reduceMotion ? scale : 1)
            .rotationEffect(.degrees(on && !reduceMotion ? angle : 0))
            // La zone de survol ne grossit pas avec l'icône : pas d'aller-retour sur les bords.
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { on = hovering }
                    }
            )
    }
}

/// Pour les grands blocs : contour et ombre douce, sans aucun mouvement (le texte ne bouge pas).
struct HoverGlow: ViewModifier {
    var cornerRadius: CGFloat = 14
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(on ? 0.35 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .background(
                // léger voile, sans ombre : rien ne floute ni ne bouge dans le texte
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(on ? 0.04 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.18)) { on = hovering }
            }
    }
}

extension View {
    func hoverGlow(cornerRadius: CGFloat = 14) -> some View {
        modifier(HoverGlow(cornerRadius: cornerRadius))
    }

    func hoverLift(scale: CGFloat = 1.02, lift: CGFloat = 2, shadow: Bool = true) -> some View {
        modifier(HoverLift(scale: scale, lift: lift, shadow: shadow))
    }
    func hoverHighlight(cornerRadius: CGFloat = 8, inset: CGFloat = -4) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, inset: inset))
    }
    func hoverPop(scale: CGFloat = 1.15, angle: Double = 0) -> some View {
        modifier(HoverPop(scale: scale, angle: angle))
    }
}
