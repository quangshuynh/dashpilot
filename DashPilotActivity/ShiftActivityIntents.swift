import AppIntents
import Foundation

/// The seven actions a driver can take from the shift's Live Activity.
///
/// Named apart from the intents themselves so there is exactly one switch over
/// them, in ``ShiftActivityIntentBridge``, rather than a lifecycle call buried
/// in each intent's body.
nonisolated enum ShiftActivityAction: String, CaseIterable, Sendable {
    case pauseShift
    case resumeShift
    case endShift
    case startDelivery
    case recordDeliveryProgress
    case parkVehicle
    case resumeDriving
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
    /// the report. A **refusal** is not discarded: it is thrown, and the
    /// service layer's own sentence is what the driver is shown.
    static func perform(_ action: ShiftActivityAction) throws {
        let service = try IntentLifecycleService.forIntent()
        switch action {
        case .pauseShift: _ = try service.pauseShift()
        case .resumeShift: _ = try service.resumeShift()
        case .endShift: _ = try service.endShift()
        case .startDelivery: _ = try service.startDelivery()
        case .recordDeliveryProgress: _ = try service.recordDeliveryProgress()
        case .parkVehicle: _ = try service.parkVehicle()
        case .resumeDriving: _ = try service.resumeDriving()
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

/// Starting one more delivery from the Lock Screen.
///
/// **The one control on this surface that names no existing record**, and the
/// reason it is offered however many orders the driver is already carrying.
/// Stacked deliveries are supported, so a second start is not a correction of
/// the first: it creates exactly one new delivery beside the ones already
/// running, and it changes none of them. The ambiguity that withholds
/// ``RecordDeliveryProgressFromActivityIntent`` does not apply to it, because
/// there is no delivery for it to pick the wrong one of.
///
/// It records **only** that a delivery was accepted, at the instant the button
/// was pressed. No amount, no expected amount, no pickup place: those are a
/// keyboard's work, and the delivery the driver started is the fact this
/// control is in a position to state.
///
/// Refused, by ``DeliveryService``'s own rule, while the shift is paused or
/// once it has ended. The card does not offer the control in either state, but
/// the layer that matters is this one: a snapshot on screen can be a moment out
/// of date, and the store never is.
struct StartDeliveryFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Delivery from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Records that you accepted a delivery on the shift in progress, from its Live Activity. \
        Deliveries already in progress are not changed. A paused shift records no delivery until \
        you resume it.
        """,
        categoryName: "Delivery"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.startDelivery)
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

/// Recording that the vehicle is parked, from the Lock Screen.
///
/// ## Why this control is the one the surface most needed
///
/// A driver pulls up outside a shop with the phone in a cradle and locked. The
/// state is worth nothing unless they can enter it there, and the expensive
/// failure of the whole feature is forgetting to leave it, which costs the rest
/// of the shift's route. Both halves therefore belong on the surface the driver
/// is already looking at.
///
/// ## It is not a pause, and the card must never let it read as one
///
/// A parked shift keeps running, keeps counting working time and keeps its
/// deliveries open. Pausing is a separate control with a separate label sitting
/// on the same card, and the two are told apart by their words and their symbols
/// rather than by which one happens to be emphasised.
///
/// Refused by ``ShiftService/parkActiveShift(at:)``, through
/// ``IntentLifecycleService``, exactly as the app's own button and the spoken
/// action are. The card does not offer the control on a shift that is already
/// parked or paused either, but the layer that matters is this one: a snapshot
/// on screen can be a moment out of date, and the store never is.
struct ParkVehicleFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Park Vehicle from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Records that you have parked and are away from the vehicle, from the shift's Live Activity. \
        Route recording stops until you resume driving. Your shift keeps running and its working time \
        keeps counting.
        """,
        categoryName: "Shift"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.parkVehicle)
        return .result()
    }
}

/// Recording that the driver is driving again, from the Lock Screen.
///
/// The half that matters most, and the reason the card replaces Park with it for
/// exactly as long as the state lasts: a driver walking back to the vehicle sees
/// one control, and it is the one that starts recording again.
///
/// Recording resumes as a **new** capture session, which is the existing rule
/// rather than a new one: nothing was recorded across the stretch, so nothing is
/// measured across it, and no line is drawn from the parking space to wherever
/// the vehicle pulls away. As with resuming a paused shift, a session can only
/// be *started* with the app on screen, and the app's own capture status line
/// says so the moment the driver looks.
struct ResumeDrivingFromActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Driving from Live Activity"

    static let description: IntentDescription? = IntentDescription(
        """
        Records that you are driving again after parking, from the shift's Live Activity. Route \
        recording begins again when you open DashPilot, as a new recording: the distance between \
        where you parked and where you drove off is not counted.
        """,
        categoryName: "Shift"
    )

    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try ShiftActivityIntentBridge.perform(.resumeDriving)
        return .result()
    }
}
