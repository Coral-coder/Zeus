import AppIntents
import WidgetKit

/// Siri / Shortcuts / Widget entry points for remote commands. Each intent is
/// small and single-purpose so Siri can match natural phrases ("turn my car
/// on") and so the same types can back interactive widget buttons.
///
/// They run through `RemoteCommandService` (UIKit-free), so they execute in the
/// app's background process for Siri and in the widget extension for control
/// widgets — no app launch required.

struct StartVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Car"
    static var description = IntentDescription("Remotely start your Chevy Bolt and precondition the cabin.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.start)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Starting your Bolt. ⚡️")
    }
}

struct StopVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Car"
    static var description = IntentDescription("Turn off the remotely-started engine / climate.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.cancelStart)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Your Bolt is shutting down.")
    }
}

struct LockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Car"
    static var description = IntentDescription("Lock the doors.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.lock)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Doors locked.")
    }
}

struct UnlockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock Car"
    static var description = IntentDescription("Unlock the doors.")
    /// Unlock is sensitive — require the device to be unlocked (Face ID).
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.unlock)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Doors unlocked.")
    }
}

struct ChargeNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Charge Now"
    static var description = IntentDescription("Override the schedule and begin charging immediately.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.chargeOverride)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Charging now. 🔋")
    }
}

struct FindCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Find My Car"
    static var description = IntentDescription("Honk the horn and flash the lights.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RemoteCommandService.shared.perform(.alert)
        return .result(dialog: "Honking and flashing now.")
    }
}

struct BatteryStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Charge"
    static var description = IntentDescription("Ask how much charge and range your Bolt has.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let snap = SnapshotStore.load() else {
            return .result(value: 0, dialog: "I don't have a recent reading yet. Open Zeus to refresh.")
        }
        let pct = Int((snap.batteryLevel * 100).rounded())
        let range = snap.rangeMiles.map { " with about \($0) miles of range" } ?? ""
        return .result(value: pct, dialog: "Your Bolt is at \(pct)%\(range).")
    }
}
