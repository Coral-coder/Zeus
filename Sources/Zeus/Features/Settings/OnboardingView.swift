import SwiftUI

/// First-run flow: collect the GM account email + VIN, then launch the secure
/// OnStar web login (which handles password + MFA on GM's own page).
struct OnboardingView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var email = ""
    @State private var vin = ""
    @State private var signingIn = false

    var body: some View {
        ZStack {
            AeroBackground()
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 40)

                    Image(systemName: "bolt.car.circle.fill")
                        .font(.system(size: 76))
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
                            field("OnStar Email", text: $email, icon: "envelope.fill")
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            field("VIN", text: $vin, icon: "number")
                                .textInputAutocapitalization(.characters)

                            Button {
                                start()
                            } label: {
                                if signingIn {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Link OnStar Account", systemImage: "link")
                                }
                            }
                            .buttonStyle(GlossyButtonStyle())
                            .disabled(!canSubmit || signingIn)
                            .opacity(canSubmit ? 1 : 0.5)
                        }
                    }

                    Text("Zeus signs in through OnStar's own secure page — your password and MFA never touch this app. Unofficial; for personal use with your own vehicle.")
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textTertiary)
                        .multilineTextAlignment(.center)

                    if let error = vehicle.lastError {
                        Text(error).font(.aeroCaption).foregroundStyle(Aero.flare)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && vin.trimmingCharacters(in: .whitespaces).count == 17
    }

    private func start() {
        signingIn = true
        Task {
            do { try vehicle.saveConfig(email: email, vin: vin) } catch { }
            await vehicle.signIn()
            signingIn = false
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Aero.bolt).frame(width: 22)
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Aero.textTertiary))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.15)))
    }
}
