import Foundation

/// Where a delivery has reached in the lifecycle a driver can truthfully record.
///
/// The five states are the whole model. DashPilot observes no delivery
/// platform, reads no order, and detects nothing automatically: every state
/// below is reached because the driver tapped something. A state the app cannot
/// witness is not represented at all.
///
/// The state is **derived** from a delivery's recorded timestamps rather than
/// stored beside them. That leaves one authoritative answer to "what is this
/// delivery doing" — the timestamps — instead of a persisted state that could
/// disagree with the events it claims to summarise, and it means the historical
/// record and the current state are the same fact read two ways.
nonisolated enum DeliveryState: String, CaseIterable, Sendable, Hashable {
    /// The driver accepted the offer and is on the way to the pickup.
    case accepted
    /// The driver reached the pickup and is waiting for the order.
    case arrivedAtPickup
    /// The order is in the car and on the way to the customer.
    case pickedUp
    /// The delivery was completed. Terminal.
    case delivered
    /// The delivery ended without being completed. Terminal.
    ///
    /// Real delivery work ends this way — an order is cancelled, unassigned or
    /// returned — and pretending otherwise would force a driver either to lie
    /// about a delivery or to leave one running forever. The timestamps that
    /// genuinely occurred before the cancellation are kept.
    case cancelled

    /// Whether the delivery has reached a terminal state.
    var isFinished: Bool { self == .delivered || self == .cancelled }

    var isActive: Bool { !isFinished }

    /// The one lifecycle action a driver may take from here, or `nil` if the
    /// delivery has finished.
    ///
    /// This is what keeps the running-shift interface to a single primary
    /// control: the screen asks the state what comes next rather than deciding
    /// for itself which of four buttons to show.
    var nextAction: DeliveryAction? {
        switch self {
        case .accepted: .arriveAtPickup
        case .arrivedAtPickup: .pickUp
        case .pickedUp: .complete
        case .delivered, .cancelled: nil
        }
    }

    /// A short phrase describing what the driver is doing, for the running
    /// shift's status line.
    var statusDescription: String {
        switch self {
        case .accepted: "Heading to the pickup"
        case .arrivedAtPickup: "Waiting at the pickup"
        case .pickedUp: "Heading to the customer"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    /// How a finished delivery is named in history.
    var historyDescription: String {
        switch self {
        case .accepted: "Accepted"
        case .arrivedAtPickup: "Arrived at the pickup"
        case .pickedUp: "Picked up"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    /// A symbol that distinguishes the state without relying on colour.
    var symbolName: String {
        switch self {
        case .accepted: "car.fill"
        case .arrivedAtPickup: "clock.fill"
        case .pickedUp: "shippingbox.fill"
        case .delivered: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }
}

/// The one lifecycle control the running shift offers, and what it says.
///
/// The wording lives here rather than in a view for the reason every other
/// piece of DashPilot's vocabulary does: it is asserted by tests, and a driver
/// hears the spoken form rather than reads the printed one. `Next` is
/// deliberately not a label anywhere — a button that does not name the event it
/// records is unusable by voice and ambiguous by sight.
nonisolated enum DeliveryAction: String, CaseIterable, Sendable, Hashable {
    /// Begin recording a delivery. Available only while no delivery is active.
    case start
    case arriveAtPickup
    case pickUp
    case complete

    /// The printed button label. Short enough to be read at a glance.
    var title: String {
        switch self {
        case .start: "Start Delivery"
        case .arriveAtPickup: "Arrived at Pickup"
        case .pickUp: "Picked Up"
        case .complete: "Delivered"
        }
    }

    /// What VoiceOver says. A verb, because the control performs an action
    /// rather than describing a state.
    var spokenLabel: String {
        switch self {
        case .start: "Start delivery"
        case .arriveAtPickup: "Mark arrived at pickup"
        case .pickUp: "Mark order picked up"
        case .complete: "Mark delivery completed"
        }
    }

    /// The state this action records, or `nil` for ``start``, which creates the
    /// delivery rather than advancing one.
    var recordedState: DeliveryState? {
        switch self {
        case .start: nil
        case .arriveAtPickup: .arrivedAtPickup
        case .pickUp: .pickedUp
        case .complete: .delivered
        }
    }
}
