import Foundation

/// How much of a shift the driver had it paused, and what that figure is short
/// of.
///
/// Nothing here is stored. It is recomputed from the shift's own pause rows
/// every time it is asked for, for the reason every other derived figure in this
/// app is: a stored total would be a second answer to a question the store can
/// already answer, and it would keep the old answer after the rule improved.
nonisolated struct ShiftPausedTime: Equatable, Sendable {
    /// The union of the shift's pauses, in seconds.
    ///
    /// A union rather than a sum, so that overlapping rows — which the service
    /// cannot write but a damaged store could hold — cannot subtract the same
    /// minute twice and report a shift as having worked less than it did.
    let duration: TimeInterval

    /// How many pause rows the shift holds.
    let intervalCount: Int

    /// How many of them the driver has not ended.
    ///
    /// One, on a paused shift. Never more than one through the app's own API,
    /// because pausing an already paused shift is refused.
    let openIntervalCount: Int

    /// How many rows could not be measured at all: an end before its start, or a
    /// stretch lying wholly outside the shift.
    ///
    /// Counted rather than repaired, and counted rather than dropped silently,
    /// because dropping one **overstates** working time. That is the direction
    /// that matters: an unusable pause quietly becomes time the driver is told
    /// they worked.
    let unusableIntervalCount: Int

    /// A shift with no pauses at all.
    ///
    /// Zero here is a measurement and not a missing value: a shift the driver
    /// never paused really was paused for no time. That is what makes a shift
    /// recorded before pausing existed keep exactly the duration it always had.
    static let none = ShiftPausedTime(
        duration: 0,
        intervalCount: 0,
        openIntervalCount: 0,
        unusableIntervalCount: 0
    )

    /// Whether the shift was ever paused.
    var hasPauses: Bool { intervalCount > 0 }

    /// Whether every pause row the shift holds contributed to ``duration``.
    var isComplete: Bool { unusableIntervalCount == 0 }
}

/// Measures the stretches of a shift the driver had paused.
///
/// It takes plain intervals and a window rather than a `Shift`, so every case
/// below is testable without a store, a container or a rendered view.
/// ``Shift/pausedTime(asOf:using:)`` is the adapter that reads the model into it.
nonisolated struct ShiftPausedTimeCalculator: Equatable, Sendable {
    init() {}

    /// Derives the paused time covered by `intervals` within `window`.
    ///
    /// - Parameters:
    ///   - intervals: one per recorded pause, in any order.
    ///   - window: the stretch of the shift being measured — its start to its
    ///     end for a completed shift, and its start to the moment being read at
    ///     for an unfinished one. Pauses are clipped to it, so the result can
    ///     never exceed the elapsed time it will be subtracted from.
    func pausedTime(
        of intervals: some Sequence<ShiftPauseInterval>,
        within window: ClosedRange<Date>
    ) -> ShiftPausedTime {
        var usable: [ClosedRange<Date>] = []
        var sourceCount = 0
        var openCount = 0
        var unusableCount = 0

        for interval in intervals {
            sourceCount += 1
            if interval.isOpen { openCount += 1 }

            guard let bounds = interval.clipped(to: window) else {
                unusableCount += 1
                continue
            }
            usable.append(bounds)
        }

        return ShiftPausedTime(
            duration: DateRangeUnion.coveredDuration(usable),
            intervalCount: sourceCount,
            openIntervalCount: openCount,
            unusableIntervalCount: unusableCount
        )
    }
}
