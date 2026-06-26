import SwiftUI

/// The primary command surface: a grid of glass command tiles plus a big
/// glossy Start/Stop hero button.
struct CommandGrid: View {
    @EnvironmentObject private var vehicle: VehicleManager

    private var snap: VehicleSnapshot { vehicle.snapshot ?? .placeholder() }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                           GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 18) {
            // Hero start/stop.
            Button {
                Task { await vehicle.perform(snap.climateOn ? .cancelStart : .start) }
            } label: {
                Label(snap.climateOn ? "Stop Engine" : "Start Engine",
                      systemImage: snap.climateOn ? "stop.circle.fill" : "power.circle.fill")
            }
            .buttonStyle(GlossyButtonStyle(
                gradient: snap.climateOn
                    ? LinearGradient(colors: [Aero.flare, Aero.ember], startPoint: .leading, endPoint: .trailing)
                    : Aero.energyGradient,
                glow: snap.climateOn ? Aero.flare : Aero.bolt))
            .overlay(alignment: .trailing) {
                if vehicle.busyCommand == .start || vehicle.busyCommand == .cancelStart {
                    ProgressView().tint(.white).padding(.trailing, 24)
                }
            }

            // Command tiles.
            LazyVGrid(columns: columns, spacing: 18) {
                tile(.lock, active: snap.locked)
                tile(.unlock, active: !snap.locked, accent: Aero.ember)
                tile(.alert, accent: Aero.flare)
                tile(.chargeOverride, active: snap.isCharging, accent: Aero.aurora)
                tile(.location, accent: Aero.signal)
                tile(.diagnostics)
            }
        }
    }

    private func tile(_ command: VehicleCommand,
                      active: Bool = false,
                      accent: Color = Aero.bolt) -> some View {
        CommandTile(
            title: command.title,
            systemImage: command.systemImage,
            accent: accent,
            isBusy: vehicle.busyCommand == command,
            isActive: active
        ) {
            Task { await vehicle.perform(command) }
        }
    }
}
