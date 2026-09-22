import AppIntents

/// The spoken phrases the system offers without the driver configuring
/// anything.
///
/// Eight, and they are the eight short lifecycle actions. Everything else
/// DashPilot does (an amount, a cost, a pickup name, a summary) either needs a
/// value dictated or needs a screen read, and neither belongs in a sentence
/// said while driving.
///
/// The last two are the parked pair. They are here rather than left to the app's
/// own buttons because a driver with two bags in their hands is exactly the
/// driver who cannot unlock a phone, and a state nobody can enter or leave
/// hands-free is a state that gets forgotten. They name the **vehicle**, never a
/// delivery and never a break: parking is not pausing, and no phrase here may
/// let the two be said the same way.
///
/// ## Nothing is donated
///
/// DashPilot does not donate performed intents to the system. App Shortcuts are
/// offered from the moment the app is installed, which is the discovery this
/// interval needs; a donation additionally feeds the system's prediction of
/// what a driver does and when, and building a model of somebody's working
/// pattern is not something to switch on as a side effect of adding four voice
/// commands.
///
/// ## Nothing here carries a value
///
/// No intent takes a parameter, so no phrase, suggestion or shortcut tile ever
/// holds an amount, a place or a position.
/// `nonisolated` deliberately: the system reads this list off the main thread,
/// and the project's default main-actor isolation would otherwise make a
/// background read of `appShortcuts` an isolation violation rather than a
/// property access. Nothing here touches the store or the interface.
nonisolated struct DashPilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartShiftIntent(),
            phrases: [
                "Start a shift in \(.applicationName)",
                "Start my \(.applicationName) shift",
                "Begin a shift in \(.applicationName)"
            ],
            shortTitle: "Start Shift",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: EndShiftIntent(),
            phrases: [
                "End my shift in \(.applicationName)",
                "End my \(.applicationName) shift",
                "Finish my \(.applicationName) shift"
            ],
            shortTitle: "End Shift",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: PauseShiftIntent(),
            phrases: [
                "Pause my shift in \(.applicationName)",
                "Pause my \(.applicationName) shift",
                "Take a break in \(.applicationName)"
            ],
            shortTitle: "Pause Shift",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ResumeShiftIntent(),
            phrases: [
                "Resume my shift in \(.applicationName)",
                "Resume my \(.applicationName) shift",
                "Start working again in \(.applicationName)"
            ],
            shortTitle: "Resume Shift",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: ParkVehicleIntent(),
            phrases: [
                "Park my vehicle in \(.applicationName)",
                "Park my \(.applicationName) vehicle",
                "I have parked in \(.applicationName)"
            ],
            shortTitle: "Park Vehicle",
            systemImageName: "parkingsign.circle"
        )
        AppShortcut(
            intent: ResumeDrivingIntent(),
            phrases: [
                "Resume driving in \(.applicationName)",
                "I am driving again in \(.applicationName)",
                "Start driving again in \(.applicationName)"
            ],
            shortTitle: "Resume Driving",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: StartDeliveryIntent(),
            phrases: [
                "Start a delivery in \(.applicationName)",
                "Start a \(.applicationName) delivery",
                "Accept a delivery in \(.applicationName)"
            ],
            shortTitle: "Start Delivery",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: RecordDeliveryProgressIntent(),
            phrases: [
                "Record delivery progress in \(.applicationName)",
                "Record my next \(.applicationName) delivery step",
                "Update my delivery in \(.applicationName)"
            ],
            shortTitle: "Record Delivery Progress",
            systemImageName: "checkmark.circle"
        )
    }
}
