import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @State private var showSettings = false

    private var snap: VehicleSnapshot { vehicle.snapshot ?? .placeholder() }

    var body: some View {
        ZStack {
            AeroBackground()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    heroCard

                    CommandGrid()

                    statsSections

                    if let error = vehicle.lastError {
                        Text(error)
                            .font(.aeroCaption)
                            .foregroundStyle(Aero.flare)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ZEUS")
                    .font(.aero(32, weight: .heavy))
                    .foregroundStyle(Aero.energyGradient)
                Text(vehicle.selectedVehicle?.displayName ?? "Chevy Bolt")
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textSecondary)
            }
            Spacer()
            if let updated = vehicle.snapshot?.updatedAt {
                Label {
                    Text(updated, format: .relative(presentation: .named))
                } icon: {
                    Circle().fill(Aero.aurora).frame(width: 6, height: 6)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Aero.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Aero.textSecondary)
                    .padding(9)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        GlassCard(glow: snap.isCharging ? Aero.aurora : Aero.bolt) {
            VStack(spacing: 18) {
                EnergyRing(level: snap.batteryLevel,
                           rangeMiles: snap.rangeMiles,
                           isCharging: snap.isCharging)

                if !heroMetrics.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(heroMetrics, id: \.label) { m in
                            MetricChip(value: m.value, label: m.label,
                                       systemImage: m.icon, tint: m.tint)
                        }
                    }
                }

                statusRow
            }
        }
    }

    private struct Metric { let value: String; let label: String; let icon: String; let tint: Color }

    private var heroMetrics: [Metric] {
        var out: [Metric] = []
        if let r = snap.rangeMiles {
            out.append(Metric(value: "\(r) mi", label: "Range", icon: "road.lanes", tint: Aero.bolt))
        }
        if snap.isCharging, let m = snap.minutesToFull, m > 0 {
            out.append(Metric(value: "\(m/60)h \(m%60)m", label: "To Full",
                              icon: "bolt.fill", tint: Aero.aurora))
        } else if let v = snap.voltage12V {
            out.append(Metric(value: String(format: "%.1f V", v), label: "12V Batt",
                              icon: "minus.plus.batteryblock.fill", tint: Aero.ember))
        }
        if let odo = snap.odometerMiles {
            out.append(Metric(value: odo.formatted(), label: "Odometer",
                              icon: "gauge.with.dots.needle.bottom.50percent", tint: Aero.iris))
        }
        return Array(out.prefix(3))
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

    // MARK: - Stats

    private var statsSections: some View {
        let all = snap.stats ?? []
        let tires = all.filter { $0.label.lowercased().contains("tire") }
        let rest = all.filter { !$0.label.lowercased().contains("tire") }
        return VStack(alignment: .leading, spacing: 24) {
            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Telemetry", systemImage: "waveform.path.ecg", tint: Aero.bolt)
                    StatGrid(stats: rest)
                }
            }
            if !tires.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Tire Pressure", systemImage: "car.side", tint: Aero.aurora)
                    StatGrid(stats: tires)
                }
            }
        }
    }
}

#Preview {
    HomeView().environmentObject(VehicleManager.shared)
}
