import SwiftUI

/// The Command screen — deliberately minimal: a glanceable battery hero, vehicle
/// status, and the remote controls. Everything else (full telemetry, tires, trip
/// data) lives one tap away on `VehicleDetailView`, so this page stays clean.
struct HomeView: View {
    @EnvironmentObject private var vehicle: VehicleManager
    @EnvironmentObject private var sideload: SideloadModel
    @State private var showSettings = false
    @State private var showSideload = false

    private var snap: VehicleSnapshot { vehicle.snapshot ?? .placeholder() }

    var body: some View {
        NavigationStack {
            ZStack {
                AeroBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        hero

                        if !vehicle.isAuthenticated {
                            reconnectCard
                        } else if let error = vehicle.lastError {
                            errorBanner(error)
                        }

                        CommandGrid()
                        detailsLink

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .refreshable { await vehicle.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $showSideload) {
            NavigationStack {
                SideloadView()
                    .environmentObject(sideload)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSideload = false }
                        }
                    }
            }
        }
        // Surface the hidden panel automatically when an .ipa is opened into Zeus.
        .onChange(of: sideload.presentSideload) { _, present in
            if present { showSideload = true; sideload.presentSideload = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ZEUS")
                    .font(.aero(32, weight: .heavy))
                    .foregroundStyle(Aero.energyGradient)
                    // Hidden entry to the on-device sideloader: long-press the logo.
                    .onLongPressGesture(minimumDuration: 0.6) { showSideload = true }
                Text(vehicle.selectedVehicle?.displayName ?? "Chevy Bolt")
                    .font(.aeroCaption)
                    .foregroundStyle(Aero.textSecondary)
            }
            Spacer()
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

    // MARK: - Hero (glanceable battery only)

    private var hero: some View {
        GlassCard(glow: snap.isCharging ? Aero.aurora : Aero.bolt) {
            VStack(spacing: 16) {
                EnergyRing(level: snap.batteryLevel,
                           rangeMiles: snap.rangeMiles,
                           isCharging: snap.isCharging)
                statusRow
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

    // MARK: - Details entry (information lives here, not on the main page)

    private var detailsLink: some View {
        NavigationLink {
            VehicleDetailView()
                .environmentObject(vehicle)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Aero.bolt)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vehicle details")
                        .font(.aeroBody).foregroundStyle(.white)
                    if let updated = vehicle.snapshot?.updatedAt {
                        Text(updated, format: .relative(presentation: .named))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Aero.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Aero.textTertiary)
            }
            .padding(14)
            .aeroGlass(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session / error states (no more permanent red strip)

    private var reconnectCard: some View {
        GlassCard(glow: Aero.ember) {
            VStack(spacing: 12) {
                Label("OnStar session expired", systemImage: "link.badge.plus")
                    .font(.aeroHeading).foregroundStyle(.white)
                Text("Reconnect to resume live status and commands.")
                    .font(.aeroCaption).foregroundStyle(Aero.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await vehicle.signIn() }
                } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlossyButtonStyle(gradient: Aero.chargeGradient, glow: Aero.aurora))
            }
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Aero.flare)
            Text(error)
                .font(.aeroCaption).foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button { vehicle.lastError = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Aero.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Aero.flare.opacity(0.4)))
    }
}

#Preview {
    HomeView()
        .environmentObject(VehicleManager.shared)
        .environmentObject(SideloadModel())
}
