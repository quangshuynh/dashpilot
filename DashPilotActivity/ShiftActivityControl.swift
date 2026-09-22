import Foundation

/// A step of a delivery that the Live Activity may offer a control for.
///
/// A mirror of the app's own `DeliveryAction`, minus `start`, carried across the
/// module boundary because the extension cannot see the app's domain types. It
/// mirrors and never decides: which step comes next is
/// `DeliveryState.nextAction`'s answer in the app, and a test pins every case
/// here to the action it stands for so the two cannot drift.
///
/// `start` is absent because starting a delivery is not a step of one. The Lock
/// Screen does offer it, as ``ShiftActivityControl/startDelivery``, and it is
/// deliberately not a member of this enum: every case here names an existing
/// delivery, and the one that creates one must not be reachable by the code
/// paths that resolve which delivery a step belongs to.
nonisolated enum ShiftActivityDeliveryStep: String, Codable, Hashable, Sendable, CaseIterable {
    case arriveAtPickup
    case pickUp
    case complete

    /// The printed button label. The same words the app's own card prints, so a
    /// driver who learns the button in one place recognises it in the other.
    var title: String {
        switch self {
        case .arriveAtPickup: "Arrived at Pickup"
        case .pickUp: "Picked Up"
        case .complete: "Delivered"
        }
    }

    /// What VoiceOver says. A verb, because the control records an event.
    var spokenLabel: String {
        switch self {
        case .arriveAtPickup: "Mark arrived at pickup"
        case .pickUp: "Mark order picked up"
        case .complete: "Mark delivery completed"
        }
    }

    /// A symbol that distinguishes the step without relying on colour.
    var symbolName: String {
        switch self {
        case .arriveAtPickup: "clock.fill"
        case .pickUp: "shippingbox.fill"
        case .complete: "checkmark.circle.fill"
        }
    }
}

/// One control the Live Activity offers.
///
/// The list of them is built by the app, from the store, and this type is only
/// the vocabulary for drawing one. It is deliberately a closed set: a Lock
/// Screen read from a cradle is not a screen to put an open-ended toolbar on,
/// and every case here is a short lifecycle action whose consequences a driver
/// can predict without looking.
///
/// **Nothing here can cancel a delivery, delete anything, or enter an amount.**
/// A cancellation cannot be undone and a monetary figure is not an interaction
/// to ask for from a moving car, which is the same line the voice surface draws.
nonisolated enum ShiftActivityControl: Codable, Hashable, Sendable {
    /// Pause the running shift. Offered only when no delivery is open, because
    /// that is the app's rule and the app is what decides this list.
    case pause
    /// Resume the paused shift.
    case resume
    /// End the shift.
    case end
    /// Start one more delivery on the running shift.
    ///
    /// **The one control here that names no existing record**, which is exactly
    /// why it is safe on a surface with nothing to tap: it always means create
    /// one delivery, whether the driver is carrying none or three. The
    /// ambiguity that withholds ``deliveryStep`` does not apply to it, because
    /// there is no delivery for it to pick the wrong one of.
    ///
    /// Offered only while the shift is **running**, since a paused shift is one
    /// the driver said they had stopped working, and ``DeliveryService``
    /// refuses a start on one.
    case startDelivery
    /// Record that the driver has parked and is away from the vehicle.
    ///
    /// **Never ``pause``, and the vocabulary is what keeps the two apart.** A
    /// parked shift is still running, still counting working time and still
    /// carrying its deliveries; what has stopped is the route. Offered on every
    /// running shift that is not already parked, including one carrying orders,
    /// because parking at a pickup is exactly when a driver needs it and their
    /// hands are exactly as full.
    case park
    /// Record that the driver is driving again.
    ///
    /// Replaces ``park`` while the shift is parked, and the two are never on the
    /// card together: one of them is always a statement the store would refuse.
    case resumeDriving
    /// Record the next step of the one delivery in progress.
    case deliveryStep(ShiftActivityDeliveryStep)

    /// The printed button label.
    var title: String {
        switch self {
        case .pause: "Pause Shift"
        case .resume: "Resume Shift"
        case .end: "End Shift"
        case .startDelivery: "Start Delivery"
        case .park: "Park Vehicle"
        case .resumeDriving: "Resume Driving"
        case let .deliveryStep(step): step.title
        }
    }

    /// What VoiceOver says.
    ///
    /// The shift controls name their subject, because "Pause" alone on a Lock
    /// Screen holding several cards says nothing about what is being paused.
    var spokenLabel: String {
        switch self {
        case .pause: "Pause shift"
        case .resume: "Resume shift"
        case .end: "End shift"
        case .startDelivery: "Start delivery"
        // Explicit about the subject and about the verb. "Pause" would be the
        // one label on this card that could be acted on under a wrong belief,
        // because parking subtracts nothing and pausing subtracts everything.
        case .park: "Park vehicle"
        case .resumeDriving: "Resume driving"
        case let .deliveryStep(step): step.spokenLabel
        }
    }

    var symbolName: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .end: "stop.fill"
        // Not one of the step symbols: this control adds a delivery rather than
        // moving one along, and a driver carrying an order must be able to tell
        // the two apart without reading either label.
        case .startDelivery: "plus.circle.fill"
        // Not a pause glyph and not a play glyph: the pair the driver must not
        // confuse these with is the shift's own pause and resume, which sit on
        // the same card.
        case .park: "parkingsign.circle.fill"
        case .resumeDriving: "car.fill"
        case let .deliveryStep(step): step.symbolName
        }
    }

    /// Whether this is the control a driver most likely reached for.
    ///
    /// At most one control is emphasised at a time, and it is never `end`:
    /// emphasising the rarer, harder-to-undo action over the frequent one is how
    /// a shift gets ended by mistake. That is the same judgement the app's own
    /// panel makes about the same three buttons.
    ///
    /// ``startDelivery`` is deliberately **not** emphasised while a delivery is
    /// running: the step of the order already in the car is what that driver
    /// reached for, and the card would otherwise emphasise two controls at once.
    /// The emphasis is therefore decided for the list rather than for the case,
    /// by ``ShiftActivityControl/emphasised(in:)``.
    var isProminent: Bool {
        switch self {
        // ``resumeDriving`` is emphasised for the reason ``resume`` is, and it
        // is the app's own panel's judgement: leaving the parked state is the
        // tap that matters, because forgetting to is what costs the rest of the
        // shift's route. ``park`` is not, for the reason ``pause`` is not.
        case .resume, .resumeDriving, .deliveryStep, .startDelivery: true
        case .pause, .park, .end: false
        }
    }

    /// The one control in `controls` to emphasise, or `nil`.
    ///
    /// The first that would take emphasis on its own, which is the order the app
    /// put them in: a delivery's next step outranks starting another, and both
    /// outrank the two lifecycle controls, which are never emphasised at all.
    static func emphasised(in controls: [ShiftActivityControl]) -> ShiftActivityControl? {
        controls.first { $0.isProminent }
    }
}
