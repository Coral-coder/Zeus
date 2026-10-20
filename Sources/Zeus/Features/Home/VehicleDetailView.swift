import SwiftUI

/// The full information screen — everything that used to crowd the Command page:
/// key metrics, all telemetry, and tire pressures. Pushed from HomeView so the
/// main page stays minimal.
struct VehicleDetailView: View {
    @EnvironmentObject private var vehicle: VehicleManager

    private var snap: VehicleSnapshot { vehicle.snapshot ?? .placeholder() }

    var body: some View {
        ZStack {
            AeroBackground(animated: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    keyMetrics
                    statsSections
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
            .refreshable { await vehicle.refresh() }
        }
        .navigationTitle("Vehicle Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vehicle.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Key metrics

    private struct Metric { let value: String; let label: String; let icon: String; let tint: Color }

    private var metrics: [Metric] {
        var out: [Metric] = []
        out.append(Metric(value: "\(Int((snap.batteryLevel * 100).rounded()))%",
                          label: "Battery", icon: "battery.75", tint: Aero.aurora))
        if let r = snap.rangeMiles {
            out.append(Metric(value: "\(r) mi", label: "Range", icon: "road.lanes", tint: Aero.bolt))
        }
        if snap.isCharging, let m = snap.minutesToFull, m > 0 {
            out.append(Metric(value: "\(m / 60)h \(m % 60)m", label: "To Full",
                              icon: "bolt.fill", tint: Aero.aurora))
        }
        if let v = snap.voltage12V {
            out.append(Metric(value: String(format: "%.1f V", v), label: "12V Batt",
                              icon: "minus.plus.batteryblock.fill", tint: Aero.ember))
        }
        if let odo = snap.odometerMiles {
            out.append(Metric(value: odo.formatted(), label: "Odometer",
                              icon: "gauge.with.dots.needle.bottom.50percent", tint: Aero.iris))
        }
        if let t = snap.cabinTempF {
            out.append(Metric(value: "\(t)°F", label: "Cabin", icon: "thermometer.medium", tint: Aero.ember))
        }
        return out
    }

    private let metricColumns = [GridItem(.flexible(), spacing: 12),
                                 GridItem(.flexible(), spacing: 12)]

    private var keyMetrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            ForEach(metrics, id: \.label) { m in
                MetricChip(value: m.value, label: m.label, systemImage: m.icon, tint: m.tint)
            }
        }
    }

    // MARK: - Full telemetry + tires

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
            if all.isEmpty {
                Text("No detailed telemetry yet. Pull to refresh, or connect an OBD-II adapter on the Live tab.")
                    .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView().environmentObject(VehicleManager.shared)
    }
}
