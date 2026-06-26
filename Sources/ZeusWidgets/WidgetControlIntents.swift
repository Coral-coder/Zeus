import AppIntents
import WidgetKit

/// Widget-local App Intents that back the interactive control buttons and the
/// iOS 18 Control Center controls.
///
/// These are intentionally **separate types** from the app's Siri intents
/// (`StartVehicleIntent`, etc.). App Intents metadata / SSU training fails when
/// the same intent types are compiled into both an app and its embedded
/// extension, so each target owns its intents. Both funnel through the shared
/// `RemoteCommandService` in `Core`.

struct WidgetStartIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Bolt"
    static var description = IntentDescription("Remotely start your Chevy Bolt.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        try await RemoteCommandService.shared.perform(.start)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Bolt"
    static var description = IntentDescription("Stop the remotely-started engine / climate.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        try await RemoteCommandService.shared.perform(.cancelStart)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetLockIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Bolt"
    static var description = IntentDescription("Lock the doors.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        try await RemoteCommandService.shared.perform(.lock)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetUnlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock Bolt"
    static var description = IntentDescription("Unlock the doors.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        try await RemoteCommandService.shared.perform(.unlock)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetChargeIntent: AppIntent {
    static var title: LocalizedStringResource = "Charge Bolt"
    static var description = IntentDescription("Begin charging immediately.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        try await RemoteCommandService.shared.perform(.chargeOverride)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
