import SwiftUI

/// The ambient living backdrop: a deep-space gradient with slow drifting
/// glass "bubbles" and a soft holographic aurora — the signature Frutiger
/// Aero 2088 atmosphere. Drop this behind any screen.
struct AeroBackground: View {
    /// Set false in widgets / CarPlay where animation isn't allowed.
    var animated: Bool = true

    @State private var drift = false

    var body: some View {
        ZStack {
            Aero.spaceGradient
                .ignoresSafeArea()

            // Aurora wash — two large blurred holographic blobs.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                Circle()
                    .fill(Aero.bolt.opacity(0.35))
                    .frame(width: w * 0.9)
                    .blur(radius: 120)
                    .offset(x: drift ? -w * 0.25 : -w * 0.1,
                            y: drift ? -h * 0.15 : -h * 0.05)

                Circle()
                    .fill(Aero.iris.opacity(0.30))
                    .frame(width: w * 0.8)
                    .blur(radius: 130)
                    .offset(x: drift ? w * 0.35 : w * 0.2,
                            y: drift ? h * 0.4 : h * 0.55)

                Circle()
                    .fill(Aero.aurora.opacity(0.22))
                    .frame(width: w * 0.6)
                    .blur(radius: 110)
                    .offset(x: drift ? w * 0.1 : -w * 0.05,
                            y: drift ? h * 0.2 : h * 0.3)
            }
            .ignoresSafeArea()

            // Floating glass bubbles.
            BubbleField()
                .ignoresSafeArea()
                .opacity(0.5)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}

/// A scatter of slowly-rising translucent bubbles — pure Aero nostalgia.
private struct BubbleField: View {
    private let bubbles: [Bubble] = (0..<14).map { i in
        // Deterministic pseudo-random layout (no Date/random needed).
        let x = Double((i * 9301 + 49297) % 233280) / 233280.0
        let size = 24 + Double((i * 6151) % 90)
        let delay = Double(i) * 0.7
        let dur = 8 + Double((i * 31) % 10)
        return Bubble(x: x, size: size, delay: delay, duration: dur)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bubbles) { bubble in
                    BubbleView(bubble: bubble, height: geo.size.height)
                        .position(x: bubble.x * geo.size.width, y: geo.size.height + 100)
                }
            }
        }
    }
}

private struct Bubble: Identifiable {
    let id = UUID()
    let x: Double
    let size: Double
    let delay: Double
    let duration: Double
}

private struct BubbleView: View {
    let bubble: Bubble
    let height: CGFloat
    @State private var rise = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.04), .clear],
                    center: .topLeading,
                    startRadius: 1,
                    endRadius: bubble.size
                )
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(width: bubble.size, height: bubble.size)
            .offset(y: rise ? -(height + 200) : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: bubble.duration)
                        .repeatForever(autoreverses: false)
                        .delay(bubble.delay)
                ) { rise = true }
            }
    }
}

#Preview {
    AeroBackground()
}
