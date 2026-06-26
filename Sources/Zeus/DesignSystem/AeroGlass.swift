import SwiftUI

/// Glassmorphism surface — frosted, glossy, rim-lit. The core panel material
/// for the whole app. Use via `.aeroGlass()`.
struct AeroGlass: ViewModifier {
    var cornerRadius: CGFloat = 28
    var tint: Color = Aero.glassTint
    var strokeOpacity: Double = 0.30
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Frosted base.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Subtle color tint over the frost.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(0.06))

                    // Top gloss highlight (Aqua-style).
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Aero.glassGloss)
                        .blendMode(.screen)
                        .mask(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                }
            }
            .overlay {
                // Iridescent rim light.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(strokeOpacity),
                                .white.opacity(strokeOpacity * 0.2),
                                Aero.bolt.opacity(strokeOpacity * 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
            .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.5),
                    radius: 24, x: 0, y: 0)
    }
}

extension View {
    /// Apply the standard frosted-glass Aero surface.
    func aeroGlass(cornerRadius: CGFloat = 28,
                   tint: Color = Aero.glassTint,
                   glow: Color? = nil) -> some View {
        modifier(AeroGlass(cornerRadius: cornerRadius, tint: tint, glow: glow))
    }
}

/// A ready-made glass card container.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var glow: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .aeroGlass(cornerRadius: cornerRadius, glow: glow)
    }
}
