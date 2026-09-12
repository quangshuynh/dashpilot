import Foundation

/// One stretch of a shift the driver had paused.
///
/// ## What a pause claims, and what it does not
///
/// A shift is *paused* from the moment the driver recorded pausing it until the
/// moment they recorded resuming it. That is the whole definition. DashPilot
/// does not know whether they ate, slept, ran an errand or sat in the car, and
/// it records nothing at all during the stretch — route capture is stopped for
/// its whole length. Nothing here is break time, rest time or unpaid time, and
/// calling it any of those would claim a measurement the app does not make.
///
/// What it *is* used for is subtraction: a shift's working duration is its
/// elapsed duration less the time it was paused, which is the one place the
/// distinction matters.
///
/// ## Why the end is optional
///
/// A pause the driver has not ended has no end, and there is nothing truthful
/// to substitute for one. While the shift is still unfinished the pause is
/// measured against the moment it is being read at, which is what makes the
/// working duration stop growing; on a completed shift it is measured against
/// the shift's end, because ending a shift closes the pause at the same instant.
nonisolated struct ShiftPauseInterval: Equatable, Sendable {
    /// When the driver recorded pausing.
    let start: Date

    /// When they recorded resuming, or `nil` for a pause still open.
    let end: Date?

    init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    /// Whether the driver has not recorded resuming.
    var isOpen: Bool { end == nil }

    /// Whether the recorded end precedes the recorded start.
    ///
    /// ``ShiftService`` clamps rather than writes one of these, so it is
    /// unreachable through the app's own API. It is still asked, because a store
    /// that somehow holds such a row must not subtract a negative duration from
    /// a shift and report more working time than the shift lasted.
    var isMalformed: Bool {
        guard let end else { return false }
        return end < start
    }

    /// This pause confined to `window`, or `nil` if it contributes nothing to it.
    ///
    /// An open pause takes the window's own end, which is what makes one rule
    /// serve both readings: on an unfinished shift the window ends at the moment
    /// being read, and on a completed one it ends where the shift did.
    ///
    /// Nothing is written back. The stored timestamps are what the driver
    /// recorded and stay exactly as they are.
    func clipped(to window: ClosedRange<Date>) -> ClosedRange<Date>? {
        let effectiveEnd = end ?? window.upperBound
        guard effectiveEnd >= start else { return nil }
        guard start <= window.upperBound, effectiveEnd >= window.lowerBound else { return nil }
        return max(start, window.lowerBound)...min(effectiveEnd, window.upperBound)
    }
}
