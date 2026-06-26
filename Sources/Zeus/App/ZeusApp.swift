import SwiftUI

@main
struct ZeusApp: App {
    @StateObject private var vehicle = VehicleManager.shared

    init() {
        // Must be registered before app launch finishes.
        SmartTimerEngine.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vehicle)
                .preferredColorScheme(.dark)
                .tint(Aero.bolt)
        }
    }
}

/// Decides between onboarding and the main experience.
struct RootView: View {
    @EnvironmentObject private var vehicle: VehicleManager

    var body: some View {
        ZStack {
            if vehicle.isConfigured && vehicle.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: vehicle.isAuthenticated)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Command", systemImage: "bolt.car.fill") }
            LiveView()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
            ChargerMapView()
                .tabItem { Label("Charge", systemImage: "ev.charger.fill") }
            TimersView()
                .tabItem { Label("Timers", systemImage: "clock.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Aero.bolt)
    }
}
