import SwiftUI

/// Live OBD-II dashboard: connect to a Bluetooth ELM327 adapter and watch the
/// car's real-time parameters stream in.
struct LiveView: View {
    @ObservedObject private var obd = OBDManager.shared

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            AeroBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    statusCard

                    if obd.isConnected {
                        liveReadings
                    } else if case .scanning = obd.phase {
                        deviceList
                    } else {
                        explainer
                    }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE")
                    .font(.aero(34, weight: .heavy))
                    .foregroundStyle(Aero.energyGradient)
                Text("OBD-II Telemetry")
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textSecondary)
            }
            Spacer()
            connectionDot
        }
    }

    private var connectionDot: some View {
        Circle()
            .fill(obd.isConnected ? Aero.aurora : Aero.textTertiary)
            .frame(width: 12, height: 12)
            .shadow(color: obd.isConnected ? Aero.aurora : .clear, radius: 8)
    }

    private var statusCard: some View {
        GlassCard(glow: obd.isConnected ? Aero.aurora : nil) {
            HStack(spacing: 14) {
                if case .scanning = obd.phase {
                    ProgressView().tint(Aero.bolt)
                } else if case .connecting = obd.phase {
                    ProgressView().tint(Aero.bolt)
                } else if case .initializing = obd.phase {
                    ProgressView().tint(Aero.bolt)
                } else {
                    Image(systemName: obd.isConnected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(obd.isConnected ? Aero.aurora : Aero.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(obd.phase.label)
                        .font(.aeroBody)
                        .foregroundStyle(.white)
                    if obd.isConnected {
                        Text("\(obd.latestReadable.count) live parameters")
                            .font(.aeroCaption)
                            .foregroundStyle(Aero.textSecondary)
                    }
                }
                Spacer()
                actionButton
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if obd.isConnected {
            Button(role: .destructive) { obd.disconnect() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .tint(Aero.flare)
        } else if case .scanning = obd.phase {
            Button { obd.disconnect() } label: {
                Image(systemName: "stop.circle.fill").font(.title2)
            }
        } else {
            Button { obd.startScan() } label: {
                Image(systemName: "magnifyingglass.circle.fill").font(.title2)
            }
            .tint(Aero.bolt)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select your adapter")
                .font(.aeroHeading).foregroundStyle(.white)
            if obd.discovered.isEmpty {
                Text("Make sure your OBD-II dongle is plugged into the car's port and powered. Bolt's port is under the steering column.")
                    .font(.aeroCaption).foregroundStyle(Aero.textTertiary)
            }
            ForEach(obd.discovered) { device in
                Button { obd.connect(device) } label: {
                    HStack {
                        Image(systemName: "cpu.fill").foregroundStyle(Aero.bolt)
                        Text(device.name).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Aero.textTertiary)
                    }
                    .padding(14)
                    .aeroGlass(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var liveReadings: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(obd.latestReadable) { reading in
                StatCard(stat: StatItem(label: reading.label,
                                        value: reading.formatted,
                                        systemImage: reading.systemImage,
                                        accentHex: nil))
            }
        }
    }

    private var explainer: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "car.side.and.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(Aero.bolt)
                Text("Plug a Bluetooth OBD-II adapter (ELM327) into your Bolt, then tap the search button above to stream live data: state of charge, speed, 12V battery, temperatures and more.")
                    .font(.aeroBody)
                    .foregroundStyle(Aero.textSecondary)
                    .multilineTextAlignment(.center)
                Button { obd.startScan() } label: {
                    Label("Find Adapter", systemImage: "magnifyingglass")
                }
                .buttonStyle(GlossyButtonStyle())
            }
        }
    }
}

#Preview {
    LiveView()
}
