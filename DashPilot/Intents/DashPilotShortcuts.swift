import AppIntents

/// The spoken phrases the system offers without the driver configuring
/// anything.
///
/// Four, and they are the four short lifecycle actions. Everything else
/// DashPilot does (an amount, a cost, a pickup name, a summary) either needs a
/// value dictated or needs a screen read, and neither belongs in a sentence
/// said while driving.
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
struct DashPilotShortcuts: AppShortcutsProvider {
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
