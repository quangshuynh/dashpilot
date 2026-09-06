import AppIntents
import Foundation

/// Starting a shift without touching the phone.
///
/// This is the driving-safety case the whole intent layer exists for: the
/// driver says one sentence at the kerb and the start time is recorded
/// accurately, instead of being recorded late because the app had to be found,
/// opened and tapped.
///
/// ``AppIntent/openAppWhenRun`` is `false` on every intent here. Bringing
/// DashPilot to the screen would replace one interaction with a longer one, and
/// the whole point is that the driver never looks at it.
struct StartShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shift"

    static let description = IntentDescription(
        """
        Starts a shift and records its start time on this device. \
        DashPilot records your route only while the app is open, so a shift started this way \
        records no mileage until you open it.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "start", "driving", "work"]
    )

    static let openAppWhenRun = false

    /// Runs with the device locked. A phone in a cradle is locked most of a
    /// shift, and requiring it to be unlocked first would make the spoken
    /// action slower than the tap it replaces. What the intent writes is one
    /// timestamp the driver just witnessed, and what it says back is that same
    /// fact.
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().startShift().dialog)
    }
}

/// Ending the shift in progress.
///
/// Refused, with the count named, while any delivery is still running: that
/// rule is ``ShiftService``'s and applies to a spoken request exactly as it
/// applies to the button.
struct EndShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "End Shift"

    static let description = IntentDescription(
        """
        Ends the shift in progress and records its end time on this device. \
        A shift with deliveries still in progress is not ended.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "end", "stop", "finish"]
    )

    static let openAppWhenRun = false

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().endShift().dialog)
    }
}

nonisolated extension IntentLifecycleOutcome {
    /// The confirmation as a system surface takes it.
    ///
    /// The sentence is built and tested in ``IntentLifecycleOutcome``; this only
    /// hands it over.
    var dialog: IntentDialog { IntentDialog(stringLiteral: confirmation) }
}
