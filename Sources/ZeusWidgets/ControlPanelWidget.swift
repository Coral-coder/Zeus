import WidgetKit
import SwiftUI
import AppIntents

/// Interactive home-screen widget: battery ring + tappable Start / Lock buttons
/// that fire App Intents in-place (no app launch). iOS 17+.
struct ControlPanelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZeusControlPanel", provider: StatusProvider()) { entry in
            ControlPanelView(entry: entry)
                .containerBackground(for: .widget) { Aero.spaceGradient }
        }
        .configurationDisplayName("Bolt Controls")
        .description("Start and lock your Bolt right from the home screen.")
        .supportedFamilies([.systemMedium])
    }
}

struct ControlPanelView: View {
    let entry: StatusEntry
    private var snap: VehicleSnapshot { entry.snapshot }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: max(0.01, snap.batteryLevel))
                        .stroke(snap.isCharging ? Aero.chargeGradient : Aero.energyGradient,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(snap.batteryLevel * 100))%")
                        .font(.aero(20, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 78, height: 78)
                Text("\(snap.rangeMiles ?? 0) mi")
                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
            }

            VStack(spacing: 10) {
                Button(intent: snap.climateOn ? StopVehicleIntent() : StartVehicleIntent()) {
                    Label(snap.climateOn ? "Stop" : "Start",
                          systemImage: snap.climateOn ? "stop.fill" : "power")
                        .font(.aero(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(snap.climateOn ? Aero.flare : Aero.bolt)

                Button(intent: snap.locked ? UnlockVehicleIntent() : LockVehicleIntent()) {
                    Label(snap.locked ? "Unlock" : "Lock",
                          systemImage: snap.locked ? "lock.open.fill" : "lock.fill")
                        .font(.aero(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(snap.locked ? Aero.ember : Aero.aurora)

                Button(intent: ChargeNowIntent()) {
                    Label("Charge", systemImage: "bolt.fill")
                        .font(.aero(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Aero.aurora)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(8)
    }
}
