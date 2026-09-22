import AppIntents
import Foundation

/// Starting a shift without touching the phone.
///
/// This is the driving-safety case the whole intent layer exists for: the
/// driver says one sentence at the kerb and the start time is recorded
/// accurately, instead of being recorded late because the app had to be found,
/// opened and tapped.
///
/// ``AppIntent/supportedModes`` is ``IntentModes/background`` on every intent
/// here, which is what `openAppWhenRun = false` said before iOS 26 deprecated
/// it. Bringing DashPilot to the screen would replace one interaction with a
/// longer one, and the whole point is that the driver never looks at it.
struct StartShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shift"

    static let description: IntentDescription? = IntentDescription(
        """
        Starts a shift and records its start time on this device. \
        Route recording begins when you open DashPilot and then continues while you use other \
        apps, so a shift started this way records no mileage until you open it.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "start", "driving", "work"]
    )

    static let supportedModes: IntentModes = .background

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

    static let description: IntentDescription? = IntentDescription(
        """
        Ends the shift in progress and records its end time on this device. \
        A shift with deliveries still in progress is not ended.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "end", "stop", "finish"]
    )

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().endShift().dialog)
    }
}

/// Pausing the shift in progress.
///
/// The driving-safety case is the same one starting a shift makes: a driver
/// stopping for a meal or an errand should not have to find and unlock the phone
/// to record it, because the alternative is that they do not record it at all
/// and the shift reports an hour of work that did not happen.
///
/// Refused, with the count named, while any delivery is still running: that rule
/// is ``ShiftService``'s and applies to a spoken request exactly as it applies
/// to the button.
struct PauseShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Shift"

    static let description: IntentDescription? = IntentDescription(
        """
        Pauses the shift in progress without ending it. Paused time is not counted as working time, \
        and route recording stops until you resume. A shift with deliveries still in progress is not \
        paused.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "pause", "break", "stop"]
    )

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().pauseShift().dialog)
    }
}

/// Resuming a paused shift.
///
/// The confirmation says that recording has to be started with the app on
/// screen, for the reason a spoken start says it: resuming by voice from behind
/// another app leaves the shift running and the route unrecorded, and there is
/// no screen in front of the driver to show them that.
struct ResumeShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Shift"

    static let description: IntentDescription? = IntentDescription(
        """
        Resumes a paused shift so its working time counts again. Route recording begins again when \
        you open DashPilot, as a new recording: the distance between where you paused and where you \
        resumed is not counted.
        """,
        categoryName: "Shift",
        searchKeywords: ["shift", "resume", "continue", "unpause"]
    )

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().resumeShift().dialog)
    }
}

/// Recording that the vehicle is parked and the driver is away from it.
///
/// ## The interaction this exists to remove
///
/// A driver pulling up outside a shop has two bags to carry and a phone to
/// unlock. Until this intent, saying "I have parked" meant finding DashPilot,
/// opening it and tapping, which is exactly the interaction this project designs
/// against and exactly the one that makes forgetting likely. The state is worth
/// nothing unless the driver can enter it without looking.
///
/// ## It adds no rule and infers no reason
///
/// Every refusal is ``ShiftService/parkActiveShift(at:)``'s, reached through
/// ``IntentLifecycleService`` exactly as the button in the app reaches it.
/// DashPilot does not ask, guess or record **why** the vehicle is parked, and
/// this is a shift operation rather than a delivery one: no delivery need be in
/// progress, and no number of them refuses it.
struct ParkVehicleIntent: AppIntent {
    static let title: LocalizedStringResource = "Park Vehicle"

    static let description: IntentDescription? = IntentDescription(
        """
        Records that you have parked and are away from the vehicle. Route recording stops until you \
        resume driving, and the distance across the stretch is not counted. Your shift keeps running \
        and its working time keeps counting.
        """,
        categoryName: "Shift",
        searchKeywords: ["park", "parked", "vehicle", "pickup"]
    )

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().parkVehicle().dialog)
    }
}

/// Recording that the driver is driving again.
///
/// The other half of the pair, and the half that matters most: forgetting to
/// leave the parked state costs the rest of the shift's route, so leaving it has
/// to be at least as easy as entering it was.
///
/// Route recording begins again as a **new** capture session, which is the
/// existing behaviour rather than a new one: nothing was recorded across the
/// stretch, so nothing may be measured across it, and the straight line from the
/// parking space to wherever the driver pulls away is never drawn.
struct ResumeDrivingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Driving"

    static let description: IntentDescription? = IntentDescription(
        """
        Records that you are driving again after parking. Route recording begins again when you open \
        DashPilot, as a new recording: the distance between where you parked and where you drove off \
        is not counted.
        """,
        categoryName: "Shift",
        searchKeywords: ["driving", "resume", "unpark", "vehicle"]
    )

    static let supportedModes: IntentModes = .background

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().resumeDriving().dialog)
    }
}

nonisolated extension IntentLifecycleOutcome {
    /// The confirmation as a system surface takes it.
    ///
    /// The sentence is built and tested in ``IntentLifecycleOutcome``; this only
    /// hands it over.
    var dialog: IntentDialog { IntentDialog(stringLiteral: confirmation) }
}
