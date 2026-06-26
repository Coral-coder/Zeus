import SwiftUI

// MARK: - Typography

extension Font {
    /// Frutiger Aero leaned on clean humanist sans (Frutiger / Myriad). SF Pro
    /// Rounded is the closest system stand-in and reads "friendly futuristic".
    static func aero(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let aeroTitle   = Font.aero(30, weight: .bold)
    static let aeroHeading = Font.aero(20, weight: .semibold)
    static let aeroBody    = Font.aero(16, weight: .medium)
    static let aeroCaption = Font.aero(13, weight: .medium)
    static let aeroMono    = Font.system(size: 15, weight: .semibold, design: .monospaced)
}

// MARK: - Glossy capsule button

/// The primary tactile button: glossy, rim-lit, with a press "depress" feel.
struct GlossyButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Aero.energyGradient
    var glow: Color = Aero.bolt

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.aero(17, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Capsule().fill(gradient)
                    // Top gloss.
                    Capsule()
                        .fill(Aero.glassGloss)
                        .blendMode(.screen)
                        .padding(1)
                    Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1)
                }
            }
            .shadow(color: glow.opacity(configuration.isPressed ? 0.2 : 0.55),
                    radius: configuration.isPressed ? 8 : 20, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Circular command button

/// Round glass action used in the command grid (lock, start, climate, etc.).
struct CommandTile: View {
    let title: String
    let systemImage: String
    var accent: Color = Aero.bolt
    var isBusy: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(accent.opacity(isActive ? 0.35 : 0.12)))
                        .overlay(Circle().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                        .overlay(Circle().fill(Aero.glassGloss).blendMode(.screen).padding(2))
                        .frame(width: 66, height: 66)
                        .shadow(color: accent.opacity(isActive ? 0.7 : 0.0), radius: 18)

                    if isBusy {
                        ProgressView().tint(accent)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isActive ? accent : .white)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                Text(title)
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

// MARK: - Energy ring (battery / charge)

/// A glowing circular gauge — the home screen's hero element. Shows battery %
/// and (optionally) estimated range.
struct EnergyRing: View {
    /// 0...1
    var level: Double
    var rangeMiles: Int?
    var isCharging: Bool

    @State private var sweep = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 16)

            Circle()
                .trim(from: 0, to: max(0.001, min(level, 1)))
                .stroke(
                    isCharging ? Aero.chargeGradient : Aero.energyGradient,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (isCharging ? Aero.aurora : Aero.bolt).opacity(0.8), radius: 16)

            VStack(spacing: 4) {
                Text("\(Int((level * 100).rounded()))")
                    .font(.aero(56, weight: .bold))
                    .foregroundStyle(.white)
                    + Text("%").font(.aero(24, weight: .bold)).foregroundStyle(Aero.textSecondary)

                if let range = rangeMiles {
                    Label("\(range) mi", systemImage: "road.lanes")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textSecondary)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.aurora)
                }
            }
        }
        .frame(width: 220, height: 220)
        .padding(8)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    var systemImage: String
    var color: Color = Aero.bolt

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.aeroCaption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}
