import AppIntents

/// Predefined Siri phrases. These show up automatically in the Shortcuts app
/// and let the user say things like "Hey Siri, start my Bolt". `\(.applicationName)`
/// resolves to "Zeus", so "turn on my car with Zeus" also works.
struct ZeusShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVehicleIntent(),
            phrases: [
                "Start my car with \(.applicationName)",
                "Turn on my car with \(.applicationName)",
                "Start my Bolt with \(.applicationName)",
                "\(.applicationName) start the car"
            ],
            shortTitle: "Start Car",
            systemImageName: "power.circle.fill"
        )
        AppShortcut(
            intent: StopVehicleIntent(),
            phrases: [
                "Turn off my car with \(.applicationName)",
                "Stop my Bolt with \(.applicationName)",
                "\(.applicationName) stop the car"
            ],
            shortTitle: "Stop Car",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: LockVehicleIntent(),
            phrases: [
                "Lock my car with \(.applicationName)",
                "Lock my Bolt with \(.applicationName)"
            ],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockVehicleIntent(),
            phrases: [
                "Unlock my car with \(.applicationName)",
                "Unlock my Bolt with \(.applicationName)"
            ],
            shortTitle: "Unlock",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: ChargeNowIntent(),
            phrases: [
                "Charge my car with \(.applicationName)",
                "Start charging my Bolt with \(.applicationName)"
            ],
            shortTitle: "Charge Now",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: BatteryStatusIntent(),
            phrases: [
                "What's my car's charge with \(.applicationName)",
                "How much range does my Bolt have with \(.applicationName)"
            ],
            shortTitle: "Check Charge",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: FindCarIntent(),
            phrases: [
                "Find my car with \(.applicationName)",
                "\(.applicationName) honk the horn"
            ],
            shortTitle: "Find Car",
            systemImageName: "bell.and.waves.left.and.right.fill"
        )
    }
}
