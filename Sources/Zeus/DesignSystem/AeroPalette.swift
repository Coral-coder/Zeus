import SwiftUI

/// Frutiger Aero 2088 — the color language.
///
/// The original Frutiger Aero (c. 2007) was glossy aqua, lush nature greens,
/// water, glass and sky. The "2088" reinterpretation keeps the glossy/wet glass
/// feeling but pushes it into a deep, neon-lit, holographic future: ink-black
/// space backdrops, electric cyan and aurora green accents, and oily
/// iridescent highlights.
enum Aero {

    // MARK: - Core hues

    /// Electric "Bolt" cyan — the primary accent. Used for live / charged / go states.
    static let bolt      = Color(hex: 0x2BE8FF)
    /// Deeper signal blue used for resting interactive elements.
    static let signal    = Color(hex: 0x1E7CFF)
    /// Aurora green — nature/charging/eco state.
    static let aurora    = Color(hex: 0x3BFFB0)
    /// Warm amber — warming/climate/attention.
    static let ember     = Color(hex: 0xFFB23B)
    /// Alert magenta — errors and stop actions.
    static let flare     = Color(hex: 0xFF3B86)
    /// Iridescent violet used in holographic gradients.
    static let iris      = Color(hex: 0x9B5BFF)

    // MARK: - Surfaces

    /// Near-black space background, top of the gradient.
    static let voidTop    = Color(hex: 0x05080F)
    /// Deep ocean blue, bottom of the gradient.
    static let voidBottom = Color(hex: 0x0A1A2E)
    /// Tint used inside glass panels.
    static let glassTint  = Color.white

    // MARK: - Text

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary  = Color.white.opacity(0.40)

    // MARK: - Gradients

    /// The full-screen ambient background gradient.
    static var spaceGradient: LinearGradient {
        LinearGradient(
            colors: [voidTop, voidBottom, Color(hex: 0x06121F)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The hero "go / live" gradient used on primary actions and the energy ring.
    static var energyGradient: LinearGradient {
        LinearGradient(
            colors: [bolt, signal, iris],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Eco / charging gradient.
    static var chargeGradient: LinearGradient {
        LinearGradient(
            colors: [aurora, bolt],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Oily, holographic sheen used for highlights and rims.
    static var holoSheen: LinearGradient {
        LinearGradient(
            colors: [
                bolt.opacity(0.9),
                aurora.opacity(0.6),
                iris.opacity(0.7),
                flare.opacity(0.5),
                bolt.opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The classic Aqua-style top-gloss highlight (white -> clear).
    static var glassGloss: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.45), Color.white.opacity(0.05), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
