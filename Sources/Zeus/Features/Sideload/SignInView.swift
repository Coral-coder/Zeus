import SwiftUI

/// The sign-in page: paste your App Store Connect API key once and Zeus does the
/// rest (mints the cert, registers the device, makes the profile, re-signs).
/// Nothing is imported per app; this is the only credential entry.
struct SignInView: View {
    @EnvironmentObject private var sideload: SideloadModel
    @Environment(\.dismiss) private var dismiss

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var appleEmail = ""
    @State private var p8 = ""

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 20) {
                    GlassCard(glow: Aero.bolt) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "App Store Connect key", systemImage: "key.fill", tint: Aero.bolt)
                            Text("From developer.apple.com → Users and Access → Integrations → App Store Connect API. Zeus uses it to sign for your device via Apple's official API — nothing that risks your account.")
                                .font(.aeroCaption).foregroundStyle(Aero.textSecondary)

                            field("Issuer ID", text: $issuerID)
                            field("Key ID", text: $keyID)
                            field("Apple ID email", text: $appleEmail)

                            Text("Private key (.p8 contents)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Aero.textTertiary)
                            TextEditor(text: $p8)
                                .font(.aeroMono)
                                .frame(height: 120)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))

                            Button(sideload.busy ? "Verifying…" : "Sign in") {
                                let (i, k, e, key) = (issuerID, keyID, appleEmail, p8)
                                Task { await sideload.signIn(issuerID: i, keyID: k, p8: key, appleEmail: e); if sideload.signedIn { dismiss() } }
                            }
                            .buttonStyle(GlossyButtonStyle())
                            .disabled(sideload.busy || issuerID.isEmpty || keyID.isEmpty || p8.isEmpty)
                        }
                    }

                    Text(sideload.status)
                        .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .foregroundStyle(.white)
    }
}
