import Foundation

/// What the pickup workflow did at the last Park or Resume Driving pressed on
/// the running shift's screen, and whether it can still be taken back.
///
/// Screen state rather than a stored fact: the delivery's own timestamps are
/// the record, and this is only the sentence saying the tap wrote them. It is
/// keyed to the vehicle state it describes, so it is shown only while that
/// state lasts and never under a stretch parked or resumed from the Lock Screen
/// or by voice, and it is gone after a relaunch, which is when the offer to
/// undo is meant to be gone too.
struct PickupWorkflowFeedback: Equatable, Identifiable {
    /// Which press it describes, by the instant the vehicle state was recorded.
    enum Moment: Equatable {
        case parked(at: Date)
        case resumed(at: Date)
    }

    let id = UUID()
    let moment: Moment
    var notice: PickupWorkflowNotice
    /// The events that can still be taken back, together, or `nil` once they
    /// have been, once the window has passed, or when nothing was recorded.
    var undoableAction: AutomatedPickupAction?

    /// Whether it still describes `shift`'s vehicle state.
    ///
    /// A Park line belongs to the stretch that began at its instant, and a
    /// Resume line to a vehicle that is driving again after the stretch that
    /// ended at its instant.
    func describes(_ shift: Shift) -> Bool {
        switch moment {
        case let .parked(at):
            shift.openRouteSuspension?.startedAt == at
        case let .resumed(at):
            !shift.isRouteSuspended && shift.routeSuspensionsInOrder.last?.endedAt == at
        }
    }
}
