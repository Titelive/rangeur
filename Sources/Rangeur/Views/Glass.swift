import SwiftUI

/// Liquid Glass (macOS 26) quand il est disponible, sinon le rendu classique fourni en `fallback`.
/// Compile aussi avec un Xcode plus ancien grâce à la vérification du compilateur.
enum LiquidGlass {
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    @ViewBuilder
    func glassOr<S: Shape, F: View>(_ shape: S,
                                    tint: Color? = nil,
                                    interactive: Bool = false,
                                    @ViewBuilder fallback: () -> F) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(fallback())
        }
        #else
        self.background(fallback())
        #endif
    }

    /// Regroupe des éléments en verre pour qu'ils se fondent entre eux (macOS 26).
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
