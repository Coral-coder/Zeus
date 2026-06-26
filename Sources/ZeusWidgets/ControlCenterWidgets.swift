import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / Lock Screen / Action Button controls (iOS 18+).
/// One tap fires the App Intent directly.
@available(iOS 18.0, *)
struct StartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ZeusStartControl") {
            ControlWidgetButton(action: WidgetStartIntent()) {
                Label("Start Bolt", systemImage: "power")
            }
        }
        .displayName("Start Bolt")
        .description("Remotely start your Chevy Bolt.")
    }
}

@available(iOS 18.0, *)
struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ZeusLockControl") {
            ControlWidgetButton(action: WidgetLockIntent()) {
                Label("Lock Bolt", systemImage: "lock.fill")
            }
        }
        .displayName("Lock Bolt")
        .description("Lock your Chevy Bolt.")
    }
}
