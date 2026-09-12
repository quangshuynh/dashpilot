import AppIntents
import Foundation

/// The four actions a driver can take from the shift's Live Activity.
///
/// Named apart from the intents themselves so there is exactly one switch over
/// them, in ``ShiftActivityIntentBridge``, rather than a lifecycle call buried
/// in each intent's body.
nonisolated enum ShiftActivityAction: String, CaseIterable, Sendable {
    case pauseShift
    case resumeShift
    case endShift
    case recordDeliveryProgress
}

#if DASHPILOT_WIDGET

/// Raised if a Live Activity action is ever performed outside the app process.
///
/// Not expected: `LiveActivityIntent` is performed **in the app**, which is what
/// lets it reach the store every other writer uses. This exists so that the
/// unexpected is a stated refusal rather than a button that reports success
/// having written nothing.
nonisolated struct ShiftActivityActionUnavailable: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "DashPilot could not record that from the Lock Screen. Open DashPilot and try again."
    }
}

/// The widget extension's half of the bridge: declarations, and a body that
/// cannot run.
///
/// The extension is a renderer. It has no store, no services and no lifecycle
/// rules, and this is where that is enforced rather than merely intended.
@MainActor
enum ShiftActivityIntentBridge {
    static func perform(_ action: ShiftActivityAction) throws {
        throw ShiftActivityActionUnavailable()
    }
}

#else

/// Where a Live Activity control's tap becomes a write.
///
/// **It owns no lifecycle logic whatsoever.** Every case below calls
/// ``IntentLifecycleService``, which is the same composition the spoken actions
/// use and which itself adds nothing to ``ShiftService`` and ``DeliveryService``.
/// A shift paused from the Lock Screen is therefore refused by the same rule,
/// with the same sentence, as one paused by voice or by the button in the app.
/// There is no third definition of what pausing means, and this file is where
/// that claim is kept true.
@MainActor
enum ShiftActivityIntentBridge {
    /// Performs one action against the app's own lifecycle services.
    ///
    /// The outcome's confirmation sentence is discarded on purpose: a Lock
    /// Screen button has no dialog to say it in, and the surface it updates is
    /// the report. A **refusal** is not discarded — it is thrown, and the
    /// service layer's own sentence is what the driver is shown.
    static func perform(_ action: ShiftActivityAction) throws {
        let service = try IntentLifecycleService.forIntent()
        switch action {
        case .pauseShift: _ = try service.pauseShift()
        case .resumeShift: _ = try service.resumeShift()
        case .endShift: _ = try service.endShift()
        case .recordDeliveryProgress: _ = try service.recordDeliveryProgress()
        }
    }
}

#endif

/// Pausing the shift from the Lock Screen.
///
/// ## What every intent in this file has in common
///
/// `supportedModes` is `.background`: the point of the surface is that the
/// driver never has to look at the app.
///
/// `authenticationPolicy` is `.alwaysAllowed`, and that is the whole reason
/// these controls are worth having. A phone in a cradle is locked for most of a
/// shift, and a control that first demands a passcode is slower than opening the
/// app would have been. What each one writes is a timestamp the driver just
/// witnessed.
///
/// `isDiscoverable` is `false`, because Siri and the Shortcuts app already offer
/// these actions through ``PauseShiftIntent`` and its neighbours. Two tiles that
/// do the same thing would be two things to learn and one more place for the
/// vocabulary to drift.
///
/// ## This one
///
/// Refused, with the count named, while any delivery is open. That rule is
/// ``ShiftService``'s. The Live Activity does not offer the control in that
/// state either, but the layer that matters is this one: a snapshot on screen
/// can be a moment out of date, and the store never is.
struct PauseShiftFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Shift from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Pauses the shift in progress from its Live Activity. Paused time is not counted as working \
        time, and route recording stops until you resume. A shift with deliveries still in progress \
        is not paused.
        """,
        categoryName: "Shift"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.pauseShift)
        return .result()
    }
}

/// Resuming the paused shift from the Lock Screen.
///
/// Worth knowing, and stated in the app rather than here: a shift resumed while
/// DashPilot is not on screen records no route until it is opened, because a
/// capture session can only be *started* in the foreground. A Lock Screen has no
/// room for that sentence, and the app's capture status line says it plainly the
/// moment the driver looks.
struct ResumeShiftFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Shift from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Resumes a paused shift from its Live Activity so its working time counts again. Route \
        recording begins again when you open DashPilot, as a new recording.
        """,
        categoryName: "Shift"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.resumeShift)
        return .result()
    }
}

/// Ending the shift from the Lock Screen.
///
/// Offered only under the lifecycle rules that already govern it: refused while
/// any delivery is open, and permitted on a paused shift, where it closes the
/// pause at the end instant rather than making the driver resume work they did
/// not do.
struct EndShiftFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Shift from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Ends the shift in progress from its Live Activity and records its end time on this device. \
        A shift with deliveries still in progress is not ended.
        """,
        categoryName: "Shift"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.endShift)
        return .result()
    }
}

/// Recording the next step of the one delivery in progress.
///
/// **This is the interval's central refusal, on a second surface.** A Lock
/// Screen button names no particular order, so it acts only while exactly one
/// delivery is running; with two, ``IntentLifecycleService`` refuses and names
/// the count rather than choosing the newest, the oldest or the one furthest
/// along. The control is not offered in that state either, and neither layer
/// guesses.
struct RecordDeliveryProgressFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Record Delivery Progress from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Records the next step of the delivery in progress from the shift's Live Activity: arrived at \
        the pickup, picked up, then delivered. If more than one delivery is in progress, nothing is \
        recorded, because the step could belong to either of them.
        """,
        categoryName: "Delivery"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.recordDeliveryProgress)
        return .result()
    }
}
