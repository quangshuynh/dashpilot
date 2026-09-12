import Foundation

/// Where a shift is in its life: running, paused, or ended.
///
/// ## Derived, never stored as a word
///
/// This is the same rule ``DeliveryState`` keeps. A shift's state is read from
/// the facts the store holds — its end timestamp and its recorded pauses — and
/// never from a status column the app would then have to keep in step with
/// them. A stored word can disagree with the timestamps beside it after a
/// crash, a failed save or a migration; a derived one cannot.
///
/// The two facts are:
///
/// - **`endedAt == nil` still means the shift is unfinished.** Pausing does not
///   touch it, so every query, fetch and invariant written against that
///   definition keeps working unchanged, and a paused shift is recovered on
///   relaunch by the same code that recovers a running one.
/// - **A pause with no end is what paused means.** It is a row, so it survives
///   termination exactly as the shift does.
///
/// ## What paused claims
///
/// Only that the driver said they stopped working and have not said they
/// started again. DashPilot observes nothing during a pause: route capture is
/// stopped, so it does not know whether the vehicle moved, and it never infers
/// that a pause ended because something happened.
nonisolated enum ShiftLifecycleState: String, CaseIterable, Equatable, Sendable {
    /// Unfinished, with no open pause. Route capture may run.
    case running
    /// Unfinished, with a pause the driver has not ended. Route capture is
    /// stopped and the working duration is not growing.
    case paused
    /// Finished. Nothing is recorded against it again.
    case ended

    /// Whether the shift is unfinished, in either of the two ways it can be.
    ///
    /// The direct reading of `endedAt == nil`, named so that a caller asking
    /// "is there a shift to work with" does not have to enumerate the two live
    /// cases and accidentally leave one out.
    var isUnfinished: Bool { self != .ended }

    /// Whether the driver's working duration is currently growing.
    var isAccumulatingWorkingTime: Bool { self == .running }

    /// What the interface calls this state.
    var title: String {
        switch self {
        case .running: "Shift in Progress"
        case .paused: "Shift Paused"
        case .ended: "Shift Ended"
        }
    }
}
