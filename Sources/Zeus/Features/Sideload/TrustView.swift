import SwiftUI

/// One-time trust setup: walks the user through installing + enabling Zeus's
/// local root certificate so iOS accepts the loopback OTA install. Native port
/// of `ipa_sideload`'s `/trust` page.
struct TrustView: View {
    @EnvironmentObject private var sideload: SideloadModel

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 20) {
                    GlassCard(glow: Aero.iris) {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Trust this device", systemImage: "lock.shield.fill", tint: Aero.iris)
                            step(1, "Tap the button below — Safari opens Zeus's local trust page.")
                            step(2, "Tap “Download the profile”, then Settings → Profile Downloaded → Install.")
                            step(3, "Settings → General → About → Certificate Trust Settings → enable “Zeus local root”.")
                            Text("It will show “Not Verified” — that's expected for a self-signed local certificate.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Aero.textTertiary)
                        }
                    }

                    Button("Open trust page in Safari") { sideload.openTrust() }
                        .buttonStyle(GlossyButtonStyle(
                            gradient: LinearGradient(colors: [Aero.iris, Aero.signal], startPoint: .leading, endPoint: .trailing),
                            glow: Aero.iris))

                    Text("You only need to do this once. After that, staged builds install with a single tap.")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Device Trust")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.aero(15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Aero.iris.opacity(0.3)))
                .overlay(Circle().strokeBorder(Aero.iris.opacity(0.6), lineWidth: 1))
            Text(text)
                .font(.aeroBody)
                .foregroundStyle(Aero.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
