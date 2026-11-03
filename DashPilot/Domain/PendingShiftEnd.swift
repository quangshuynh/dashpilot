import Foundation

/// A request to end one shift that has not been confirmed yet.
///
/// The Live Activity's End Shift asks rather than acts: its first tap creates
/// one of these, and the shift ends only when a second tap presents the same
/// shift and token while it is still valid. It is deliberately short-lived and
/// held only in memory. A confirmation that did not survive the app being
/// terminated is a confirmation the driver gives again, which is the safe way
/// for that to fail.
nonisolated struct PendingShiftEnd: Equatable, Sendable {
    /// How long the second tap is accepted for. Long enough to read Confirm End
    /// and press it, short enough that a card left showing it is not an armed
    /// control later in the shift.
    static let window: TimeInterval = 8

    let shiftID: UUID
    let token: UUID
    let requestedAt: Date

    var expiresAt: Date { requestedAt.addingTimeInterval(Self.window) }

    var reference: ShiftActivityEndConfirmation {
        ShiftActivityEndConfirmation(shiftID: shiftID, token: token)
    }

    /// Whether a confirmation presented at `date` may still end the shift.
    ///
    /// A clock that has moved behind the request is not taken as time remaining:
    /// the window is measured forward from the tap, and a date before it is
    /// refused rather than extending the window by however far the clock moved.
    func isValid(at date: Date) -> Bool {
        date >= requestedAt && date < expiresAt
    }

    func matches(_ reference: ShiftActivityEndConfirmation) -> Bool {
        reference.shiftID == shiftID && reference.token == token
    }
}

/// What checking a presented confirmation found.
nonisolated enum PendingShiftEndCheck: Equatable, Sendable {
    /// The confirmation was pending, matched and in time, and is now used.
    case confirmed(PendingShiftEnd)
    /// Nothing matching is pending: it expired, was withdrawn, was already used,
    /// or was never made in this process.
    case expired
    /// It names another shift, or an earlier confirmation than the one pending.
    case stale
}
