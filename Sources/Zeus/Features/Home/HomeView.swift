import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var showSettings = false

    private var snap: VehicleSnapshot { vehicle.snapshot ?? .placeholder() }

    var body: some View {
        ZStack {
            AeroBackground()

            ScrollView {
                VStack(spacing: 22) {
                    header

                    // Hero energy ring inside a glass card.
                    GlassCard(glow: snap.isCharging ? Aero.aurora : Aero.bolt) {
                        VStack(spacing: 16) {
                            EnergyRing(level: snap.batteryLevel,
                                       rangeMiles: snap.rangeMiles,
                                       isCharging: snap.isCharging)
                            statusRow
                        }
                    }

                    CommandGrid()

                    if let stats = snap.stats, !stats.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Vehicle Stats", systemImage: "chart.bar.doc.horizontal.fill")
                                .font(.aeroHeading)
                                .foregroundStyle(.white)
                            StatGrid(stats: stats)
                        }
                    }

                    if let error = vehicle.lastError {
                        Text(error)
                            .font(.aeroCaption)
                            .foregroundStyle(Aero.flare)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(20)
            }
            .refreshable { await vehicle.refresh() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(vehicle)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ZEUS")
                    .font(.aero(34, weight: .heavy))
                    .foregroundStyle(Aero.energyGradient)
                Text(vehicle.selectedVehicle?.displayName ?? "Chevy Bolt")
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Aero.textSecondary)
                }
                if let updated = vehicle.snapshot?.updatedAt {
                    Text(updated, format: .relative(presentation: .named))
                        .font(.aeroCaption)
                        .foregroundStyle(Aero.textTertiary)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            StatusPill(text: snap.locked ? "Locked" : "Unlocked",
                       systemImage: snap.locked ? "lock.fill" : "lock.open.fill",
                       color: snap.locked ? Aero.bolt : Aero.ember)
            if snap.pluggedIn {
                StatusPill(text: "Plugged In", systemImage: "powerplug.fill", color: Aero.aurora)
            }
            if snap.climateOn {
                StatusPill(text: "Climate", systemImage: "fan.fill", color: Aero.ember)
            }
        }
    }
}

#Preview {
    HomeView().environmentObject(VehicleManager.shared)
}
