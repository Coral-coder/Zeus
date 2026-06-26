import WidgetKit
import SwiftUI

/// Read-only home-screen + lock-screen widget showing battery, range and lock
/// state from the shared snapshot cache.
struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleSnapshot
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .placeholder())
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: SnapshotStore.load() ?? .placeholder()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: SnapshotStore.load() ?? .placeholder())
        // Refresh roughly every 30 min; the app/Siri also reload on demand.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZeusStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Aero.spaceGradient }
        }
        .configurationDisplayName("Bolt Status")
        .description("Battery, range and lock state at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry
    private var snap: VehicleSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(pct)% • \(snap.rangeMiles ?? 0) mi", systemImage: "bolt.car.fill")
        case .accessoryCircular:
            Gauge(value: snap.batteryLevel) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                Text("\(pct)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("\(pct)%", systemImage: "bolt.car.fill").font(.headline)
                Text("\(snap.rangeMiles ?? 0) mi • \(snap.locked ? "Locked" : "Unlocked")")
                    .font(.caption)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 8) {
                    Text("ZEUS").font(.aero(20, weight: .heavy))
                        .foregroundStyle(Aero.energyGradient)
                    stat("Range", "\(snap.rangeMiles ?? 0) mi", "road.lanes")
                    stat("Doors", snap.locked ? "Locked" : "Unlocked",
                         snap.locked ? "lock.fill" : "lock.open.fill")
                    if snap.isCharging { stat("Charging", "Yes", "bolt.fill") }
                }
                Spacer()
            }
            .padding(4)
        default:
            VStack(spacing: 6) {
                ring
                Text("\(snap.rangeMiles ?? 0) mi")
                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
            }
        }
    }

    private var pct: Int { Int((snap.batteryLevel * 100).rounded()) }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.01, snap.batteryLevel))
                .stroke(snap.isCharging ? Aero.chargeGradient : Aero.energyGradient,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%").font(.aero(22, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 84, height: 84)
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        Label("\(title): \(value)", systemImage: icon)
            .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
    }
}
