import Foundation
import SwiftData

/// Errors raised when a pause transition would violate the model's invariants.
nonisolated enum ShiftPauseError: Error, Equatable {
    /// The pause already has an end timestamp.
    case alreadyEnded
    /// The proposed end timestamp is earlier than the pause's start.
    case endPrecedesStart
}

/// One stretch of a shift the driver recorded as paused.
///
/// ## Why this is a row and not a flag
///
/// A pause is a **fact with two timestamps**, exactly as a shift and a delivery
/// are, and it is stored the same way. A boolean on `Shift` could say that a
/// shift is paused now; it could not say for how long, how many times, or when,
/// and a shift's working duration has to be derived from all of that. An
/// accumulated "paused seconds" column could say how long in total, but it is a
/// running sum the app would have to keep correct across every crash and failed
/// save, and it is the kind of derived value this project deliberately does not
/// persist.
///
/// Rows also mean the shift's own definition of unfinished does not move.
/// `Shift.endedAt` is untouched by pausing, so `endedAt == nil` still means
/// "this shift has not finished", every fetch written against it keeps working,
/// and a paused shift is recovered after a relaunch by the same code that
/// recovers a running one.
///
/// ## What it records
///
/// Only when the driver said they stopped and when they said they started
/// again. Nothing is observed during a pause: route capture is stopped for its
/// whole length, so DashPilot does not know whether the vehicle moved, and it
/// never ends a pause by itself because something happened.
///
/// The domain reading of these two timestamps lives in ``ShiftPauseInterval``,
/// which holds the clipping and malformed-row rules and can be tested without a
/// store.
@Model
nonisolated final class ShiftPause {
    /// Stable identifier, for the reason ``Shift`` has one.
    @Attribute(.unique) private(set) var id: UUID

    private(set) var startedAt: Date

    /// `nil` while the driver has not resumed.
    private(set) var endedAt: Date?

    /// The shift this pause belongs to.
    ///
    /// Optional because SwiftData makes the inverse of a to-many relationship
    /// optional; a pause with no shift describes a store the app cannot write.
    private(set) var shift: Shift?

    init(id: UUID = UUID(), shift: Shift, startedAt: Date, endedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.shift = shift
    }

    /// Whether the driver has not recorded resuming.
    var isOpen: Bool { endedAt == nil }

    /// This pause as the value type the calculations read.
    var interval: ShiftPauseInterval {
        ShiftPauseInterval(start: startedAt, end: endedAt)
    }

    /// Records that the driver resumed.
    ///
    /// - Throws: ``ShiftPauseError/alreadyEnded`` if the pause is already
    ///   closed, or ``ShiftPauseError/endPrecedesStart`` if `date` is before the
    ///   pause began.
    func end(at date: Date) throws {
        guard endedAt == nil else { throw ShiftPauseError.alreadyEnded }
        guard date >= startedAt else { throw ShiftPauseError.endPrecedesStart }
        endedAt = date
    }

    /// Rewrites both timestamps to the stretch the driver corrected this pause
    /// to.
    ///
    /// The correction has already been checked against the shift's own facts by
    /// ``ShiftPauseCorrection``; what is kept here is the one rule that is about
    /// *this row* rather than about the shift around it: **the live pause is not
    /// editable**. A pause with no end is the state the driver is in, and it is
    /// left to Resume and End, which reconcile route capture and the Live
    /// Activity as they close it.
    ///
    /// Both timestamps are written together, so a pause is never momentarily
    /// half corrected, and the row keeps its identity: correcting a pause is not
    /// deleting one and recording another, and nothing that refers to this row
    /// has to be told.
    ///
    /// - Throws: ``ShiftPauseCorrectionRefusal/pauseIsOpen`` for a pause the
    ///   driver has not ended.
    func apply(_ correction: ShiftPauseCorrection) throws {
        guard endedAt != nil else { throw ShiftPauseCorrectionRefusal.pauseIsOpen }
        startedAt = correction.startedAt
        endedAt = correction.endedAt
    }
}
