import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var pin = ""
    @State private var scClientId = ""
    @State private var scSecret = ""
    @State private var connectingSmartcar = false

    var body: some View {
        ZStack {
            AeroBackground(animated: false)
            ScrollView {
                VStack(spacing: 18) {
                    Text("Settings")
                        .font(.aeroTitle)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Vehicle picker.
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Vehicle").font(.aeroHeading).foregroundStyle(.white)
                            ForEach(vehicle.vehicles) { v in
                                Button {
                                    vehicle.selectedVehicle = v
                                } label: {
                                    HStack {
                                        Text(v.displayName).foregroundStyle(.white)
                                        Spacer()
                                        if v == vehicle.selectedVehicle {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Aero.bolt)
                                        }
                                    }
                                }
                            }
                            if vehicle.vehicles.isEmpty {
                                Text("No vehicles loaded yet.")
                                    .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
                            }
                        }
                    }

                    // Connection method — OnStar (default) or the official
                    // Smartcar API. Additive: OnStar stays the default.
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connection").font(.aeroHeading).foregroundStyle(.white)
                            Text("Active: \(vehicle.backend.displayName)")
                                .font(.aeroCaption).foregroundStyle(Aero.textSecondary)

                            if vehicle.backend == .smartcar {
                                Button {
                                    vehicle.setBackend(.onStar)
                                } label: { Label("Switch back to OnStar", systemImage: "arrow.uturn.backward") }
                                    .buttonStyle(GlossyButtonStyle())
                            } else {
                                Text("Smartcar is the official, more reliable vehicle API (EV status, lock/unlock, charge, location). Create a free app at dashboard.smartcar.com, register the redirect URI  sc<ClientID>://exchange, then paste the keys here.")
                                    .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
                                TextField("Smartcar Client ID", text: $scClientId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                                    .foregroundStyle(.white)
                                SecureField("Smartcar Client Secret", text: $scSecret)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                                    .foregroundStyle(.white)
                                Button {
                                    connectingSmartcar = true
                                    Task {
                                        await vehicle.connectSmartcar(clientId: scClientId, clientSecret: scSecret)
                                        connectingSmartcar = false
                                    }
                                } label: {
                                    Label(connectingSmartcar ? "Connecting…" : "Connect with Smartcar",
                                          systemImage: "bolt.horizontal.circle.fill")
                                }
                                .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))
                                .disabled(scClientId.isEmpty || scSecret.isEmpty || connectingSmartcar)
                            }
                        }
                    }

                    // OnStar PIN for command authorization.
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("OnStar Command PIN").font(.aeroHeading).foregroundStyle(.white)
                            SecureField("PIN", text: $pin)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                                .foregroundStyle(.white)
                            Button("Save PIN") {
                                vehicle.saveCommandPIN(pin); pin = ""
                            }
                            .buttonStyle(GlossyButtonStyle())
                        }
                    }

                    GlassCard {
                        VStack(spacing: 12) {
                            Button {
                                Task { await vehicle.refresh() }
                            } label: { Label("Refresh Vehicle", systemImage: "arrow.clockwise") }
                                .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))

                            Button(role: .destructive) {
                                Task { await vehicle.signOut() }
                            } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
                                .buttonStyle(GlossyButtonStyle(
                                    gradient: LinearGradient(colors: [Aero.flare, Aero.iris],
                                                             startPoint: .leading, endPoint: .trailing),
                                    glow: Aero.flare))
                        }
                    }

                    Text("Zeus • Unofficial OnStar client • v0.1.0")
                        .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
                }
                .padding(20)
            }
        }
    }
}
