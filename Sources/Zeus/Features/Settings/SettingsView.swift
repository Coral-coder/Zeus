import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var pin = ""

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
