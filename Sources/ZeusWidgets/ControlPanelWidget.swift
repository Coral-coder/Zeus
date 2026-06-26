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
                if snap.climateOn {
                    Button(intent: StopVehicleIntent()) {
                        buttonLabel("Stop", "stop.fill")
                    }
                    .tint(Aero.flare)
                } else {
                    Button(intent: StartVehicleIntent()) {
                        buttonLabel("Start", "power")
                    }
                    .tint(Aero.bolt)
                }

                if snap.locked {
                    Button(intent: UnlockVehicleIntent()) {
                        buttonLabel("Unlock", "lock.open.fill")
                    }
                    .tint(Aero.ember)
                } else {
                    Button(intent: LockVehicleIntent()) {
                        buttonLabel("Lock", "lock.fill")
                    }
                    .tint(Aero.aurora)
                }

                Button(intent: ChargeNowIntent()) {
                    buttonLabel("Charge", "bolt.fill")
                }
                .tint(Aero.aurora)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(8)
    }

    private func buttonLabel(_ title: String, _ image: String) -> some View {
        Label(title, systemImage: image)
            .font(.aero(15, weight: .bold))
            .frame(maxWidth: .infinity)
    }
}
