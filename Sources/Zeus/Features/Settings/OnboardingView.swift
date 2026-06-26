import SwiftUI

/// First-run flow: a single tap opens GM's official OnStar login on-device.
/// We read the account's vehicle (and VIN) automatically after sign-in, so
/// there's nothing to type here.
struct OnboardingView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var signingIn = false

    var body: some View {
        ZStack {
            AeroBackground()
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 60)

                    Image(systemName: "bolt.car.circle.fill")
                        .font(.system(size: 86))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Aero.bolt, .white.opacity(0.15))
                        .shadow(color: Aero.bolt.opacity(0.7), radius: 24)

                    VStack(spacing: 6) {
                        Text("ZEUS")
                            .font(.aero(46, weight: .heavy))
                            .foregroundStyle(Aero.energyGradient)
                        Text("Command your Bolt")
                            .font(.aeroBody)
                            .foregroundStyle(Aero.textSecondary)
                    }

                    GlassCard {
                        VStack(spacing: 16) {
                            Button {
                                start()
                            } label: {
                                if signingIn {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Sign in with OnStar", systemImage: "link")
                                }
                            }
                            .buttonStyle(GlossyButtonStyle())
                            .disabled(signingIn)
                        }
                    }

                    Text("Tapping Sign in opens GM's official OnStar login on-device. Sign in with your email, password, and MFA — Zeus never sees your password and reads your vehicle automatically. Unofficial; for personal use with your own vehicle.")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textTertiary)
                        .multilineTextAlignment(.center)

                    if let error = vehicle.lastError {
                        Text(error).font(.aeroCaption).foregroundStyle(Aero.flare)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
            }
        }
    }

    private func start() {
        signingIn = true
        Task {
            await vehicle.signIn()
            signingIn = false
        }
    }
}
