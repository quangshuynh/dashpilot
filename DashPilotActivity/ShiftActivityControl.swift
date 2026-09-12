import Foundation

/// A step of a delivery that the Live Activity may offer a control for.
///
/// A mirror of the app's own `DeliveryAction`, minus `start`, carried across the
/// module boundary because the extension cannot see the app's domain types. It
/// mirrors and never decides: which step comes next is
/// `DeliveryState.nextAction`'s answer in the app, and a test pins every case
/// here to the action it stands for so the two cannot drift.
///
/// `start` is absent because starting a delivery is not a step of one. It is
/// also the one delivery action that is never ambiguous, and the reason it is
/// still not offered here is space and safety rather than ambiguity: the Lock
/// Screen carries the controls a driver needs *while* an order is running.
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
    /// Record the next step of the one delivery in progress.
    case deliveryStep(ShiftActivityDeliveryStep)

    /// The printed button label.
    var title: String {
        switch self {
        case .pause: "Pause Shift"
        case .resume: "Resume Shift"
        case .end: "End Shift"
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
        case let .deliveryStep(step): step.spokenLabel
        }
    }

    var symbolName: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .end: "stop.fill"
        case let .deliveryStep(step): step.symbolName
        }
    }

    /// Whether this is the control a driver most likely reached for.
    ///
    /// Exactly one control is emphasised at a time, and it is never `end`:
    /// emphasising the rarer, harder-to-undo action over the frequent one is how
    /// a shift gets ended by mistake. That is the same judgement the app's own
    /// panel makes about the same three buttons.
    var isProminent: Bool {
        switch self {
        case .resume, .deliveryStep: true
        case .pause, .end: false
        }
    }
}
