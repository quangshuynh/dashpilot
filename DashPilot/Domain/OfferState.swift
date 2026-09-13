import Foundation

/// Where an accepted offer has reached, read from the deliveries it contains.
///
/// ## It is derived, and it counts rather than decides
///
/// An offer has no lifecycle timestamps of its own beyond the moment it was
/// accepted, and it deliberately never gains any. Everything below is read from
/// the states of the deliveries the offer holds, so there is one authoritative
/// answer to what an offer is doing and it is the same data each delivery
/// derives its own state from. A stored offer state could disagree with the
/// deliveries it claims to summarise; a derived one cannot.
///
/// ## Cancellation is explicit here
///
/// Cancelling a delivery cancels **that delivery**. There is no control
/// anywhere in the app that cancels an offer, and an offer is never deleted
/// when its deliveries end: it is what happened. What the driver did to each
/// delivery is therefore what an offer's own ending is read from:
///
/// - every delivery delivered: ``completed``
/// - every delivery cancelled: ``cancelled``
/// - some of each: ``partiallyCompleted``, which is neither of the two above
///   and must not be reported as either. An offer whose second delivery fell
///   through is not a cancelled offer, and an offer whose first delivery fell
///   through is not a completed one.
nonisolated enum OfferState: String, CaseIterable, Sendable, Hashable {
    /// At least one of the offer's deliveries is still active.
    case inProgress
    /// Every delivery was delivered.
    case completed
    /// Every delivery is terminal, with at least one delivered and at least one
    /// cancelled.
    case partiallyCompleted
    /// Every delivery was cancelled.
    case cancelled
    /// The offer holds no deliveries at all.
    ///
    /// Unreachable through the app, which records an offer and the deliveries
    /// it contains in one write and never removes a delivery from one. It
    /// describes a store holding a row the app cannot produce, and it is
    /// deliberately **not** treated as terminal: an offer holding no deliveries
    /// records no work that could have finished, and reporting it as complete
    /// would be a vacuous truth standing in for a measurement.
    case empty

    /// Whether every delivery this offer contains has finished.
    ///
    /// The definition the interval was asked for: an offer is complete only
    /// when all of its deliveries are terminal. ``empty`` is excluded for the
    /// reason given on the case itself.
    var isTerminal: Bool {
        switch self {
        case .completed, .partiallyCompleted, .cancelled: true
        case .inProgress, .empty: false
        }
    }

    /// Whether the driver is still working at least one of this offer's
    /// deliveries.
    var isActive: Bool { self == .inProgress }

    /// The state an offer holding these delivery states is in.
    init(deliveryStates: some Sequence<DeliveryState>) {
        var delivered = 0
        var cancelled = 0
        var active = 0
        for state in deliveryStates {
            switch state {
            case .delivered: delivered += 1
            case .cancelled: cancelled += 1
            case .accepted, .arrivedAtPickup, .pickedUp: active += 1
            }
        }

        if delivered + cancelled + active == 0 {
            self = .empty
        } else if active > 0 {
            self = .inProgress
        } else if cancelled == 0 {
            self = .completed
        } else if delivered == 0 {
            self = .cancelled
        } else {
            self = .partiallyCompleted
        }
    }

    /// How a finished offer is named in history.
    ///
    /// ``partiallyCompleted`` says both halves rather than picking the
    /// flattering one, for the reason the app never folds a cancelled delivery
    /// into a completed count.
    var historyDescription: String {
        switch self {
        case .inProgress: "In progress"
        case .completed: "All deliveries completed"
        case .partiallyCompleted: "Partly completed, partly cancelled"
        case .cancelled: "All deliveries cancelled"
        case .empty: "No deliveries recorded"
        }
    }
}
