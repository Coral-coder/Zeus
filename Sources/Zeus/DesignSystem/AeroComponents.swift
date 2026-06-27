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

    @State private var appear = false
    @State private var pulse = false

    private var accent: Color { isCharging ? Aero.aurora : Aero.bolt }
    private var track: LinearGradient { isCharging ? Aero.chargeGradient : Aero.energyGradient }

    var body: some View {
        ZStack {
            // Soft ambient halo behind the ring.
            Circle()
                .fill(accent.opacity(0.18))
                .blur(radius: 40)
                .scaleEffect(pulse ? 1.06 : 0.96)

            // Recessed base groove.
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 18)
            Circle()
                .stroke(Color.black.opacity(0.25), lineWidth: 2)
                .blur(radius: 1)
                .padding(9)

            // Progress arc.
            Circle()
                .trim(from: 0, to: appear ? max(0.001, min(level, 1)) : 0)
                .stroke(track, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.85), radius: 14)

            // Thin inner accent hairline.
            Circle()
                .trim(from: 0, to: appear ? max(0.001, min(level, 1)) : 0)
                .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(8)

            VStack(spacing: 2) {
                HStack(alignment: .top, spacing: 1) {
                    Text("\(Int((level * 100).rounded()))")
                        .font(.aero(64, weight: .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.aero(22, weight: .bold))
                        .foregroundStyle(Aero.textSecondary)
                        .padding(.top, 8)
                }
                if let range = rangeMiles {
                    Text("\(range) mi range")
                        .font(.aero(13, weight: .semibold))
                        .foregroundStyle(Aero.textSecondary)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.aero(12, weight: .bold))
                        .foregroundStyle(Aero.aurora)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Aero.aurora.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(Aero.aurora.opacity(0.5), lineWidth: 1))
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 224, height: 224)
        .padding(6)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { appear = true }
            if isCharging {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

// MARK: - Stat card & grid

/// A compact frosted card showing one labeled statistic with an icon.
struct StatCard: View {
    let stat: StatItem

    private var accent: Color {
        stat.accentHex.map { Color(hex: $0) } ?? Aero.bolt
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon in a tinted, rim-lit chip.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.16))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                Image(systemName: stat.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.label.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Aero.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(stat.value)
                    .font(.aero(19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .aeroGlass(cornerRadius: 18)
    }
}

/// A responsive 2-column grid of stat cards — "all the car stats".
struct StatGrid: View {
    let stats: [StatItem]
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(stats) { StatCard(stat: $0) }
        }
    }
}

// MARK: - Section header

/// A quiet section label: icon + uppercased title + a fading hairline rule.
struct SectionHeader: View {
    let title: String
    var systemImage: String
    var tint: Color = Aero.bolt

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Aero.textSecondary)
                .tracking(1.2)
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.18), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }
}

// MARK: - Metric chip (hero key stats)

/// A small glassy key-metric used beside the hero ring.
struct MetricChip: View {
    let value: String
    let label: String
    var systemImage: String
    var tint: Color = Aero.bolt

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.aero(16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Aero.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
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
