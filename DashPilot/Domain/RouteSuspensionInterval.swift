import Foundation

/// One stretch of a shift the driver recorded the vehicle as parked.
///
/// ## What it claims, and what it does not
///
/// The driver said they had parked and walked away from the vehicle, and later
/// said they were driving again. That is the whole of it. DashPilot does not
/// know where the vehicle was, whether the driver went into a shop, how far they
/// walked or whether the vehicle moved at all: **route capture is stopped for
/// the whole stretch**, exactly as it is for a pause, so the app observes
/// nothing during one and never ends one by itself.
///
/// ## It is not a pause, and the difference is the point
///
/// A ``ShiftPauseInterval`` says the driver **stopped working**, and a shift's
/// working duration is its elapsed duration less the union of those. Parking to
/// collect an order is working: the driver is inside a shop doing the job.
/// Nothing here is ever subtracted from working time, no hourly rate moves
/// because of one, and a shift that parked twice reports exactly the working
/// duration it would have reported without this feature.
///
/// What it changes is **route evidence**, and it changes it by recording less:
/// capture stops, so no walking is written into a coordinate history, and
/// resuming mints a new capture session, so ``RouteMileageCalculator`` refuses
/// to measure across the stretch. The recorded mileage that results is lower and
/// the route is reported as partial, which is the truth about what was captured.
///
/// ## Why the vehicle rather than a delivery
///
/// Whether the car is moving is a fact about the driver and their vehicle, not
/// about any one order. A driver shopping for one delivery while carrying
/// another has one vehicle, and it is parked. So a suspension belongs to the
/// **shift**, there is at most one open at a time, and stacked deliveries
/// neither multiply it nor divide it.
nonisolated struct RouteSuspensionInterval: Equatable, Sendable {
    /// When the driver recorded parking.
    let start: Date

    /// When they recorded driving again, or `nil` while they have not.
    let end: Date?

    init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    /// Whether the driver has not recorded resuming.
    var isOpen: Bool { end == nil }

    /// Whether the recorded end precedes the recorded start.
    ///
    /// Unreachable through the app's own API, which clamps exactly as the pause
    /// service does. It is still asked, for the reason
    /// ``ShiftPauseInterval/isMalformed`` is: a damaged store must not produce a
    /// negative duration on a driver's screen.
    var isMalformed: Bool {
        guard let end else { return false }
        return end < start
    }

    /// This stretch confined to `window`, or `nil` if it contributes nothing to
    /// it.
    ///
    /// An open stretch takes the window's own end, which is the same rule
    /// ``ShiftPauseInterval/clipped(to:)`` applies and for the same reason: on an
    /// unfinished shift the window ends at the moment being read, and on a
    /// completed one it ends where the shift did.
    ///
    /// Nothing is written back.
    func clipped(to window: ClosedRange<Date>) -> ClosedRange<Date>? {
        let effectiveEnd = end ?? window.upperBound
        guard effectiveEnd >= start else { return nil }
        guard start <= window.upperBound, effectiveEnd >= window.lowerBound else { return nil }
        return max(start, window.lowerBound)...min(effectiveEnd, window.upperBound)
    }
}

/// How much of a shift the driver recorded the vehicle as parked, and how many
/// stretches that was.
///
/// Nothing here is stored, for the reason ``ShiftPausedTime`` is not: it is
/// recomputed from the shift's own rows every time it is asked for.
///
/// **It is never subtracted from anything.** The figure exists so that a route's
/// coverage can say why part of a shift was not recorded, and so that a driver
/// reading a partial route is told that some of it was theirs on purpose. No
/// duration, rate or period figure anywhere reads it.
nonisolated struct RouteSuspendedTime: Equatable, Sendable {
    /// The union of the shift's suspensions, in seconds.
    ///
    /// A union rather than a sum, exactly as paused time is one: the service
    /// cannot write two overlapping rows, and a damaged store must not be able
    /// to report more parked time than the shift lasted.
    let duration: TimeInterval

    /// How many suspension rows the shift holds.
    let intervalCount: Int

    /// How many of them the driver has not ended. One, while parked.
    let openIntervalCount: Int

    /// How many rows could not be measured at all.
    ///
    /// Counted rather than repaired and never dropped silently. The direction
    /// matters less here than it does for a pause, because nothing is
    /// subtracted; it is counted so that a shift cannot quietly report fewer
    /// parked stretches than it holds.
    let unusableIntervalCount: Int

    /// A shift the driver never parked.
    ///
    /// Zero here is a measurement: such a shift really was parked for no time.
    static let none = RouteSuspendedTime(
        duration: 0,
        intervalCount: 0,
        openIntervalCount: 0,
        unusableIntervalCount: 0
    )

    /// Whether the driver parked at all during this shift.
    var hasSuspensions: Bool { intervalCount > 0 }

    /// Whether the driver has the vehicle parked right now.
    var isSuspended: Bool { openIntervalCount > 0 }

    /// Whether every row the shift holds contributed to ``duration``.
    var isComplete: Bool { unusableIntervalCount == 0 }
}

/// Measures the stretches of a shift the driver recorded as parked.
///
/// Plain intervals and a window rather than a `Shift`, so every case is testable
/// without a store. ``Shift/suspendedTime(asOf:using:)`` is the adapter.
nonisolated struct RouteSuspendedTimeCalculator: Equatable, Sendable {
    init() {}

    func suspendedTime(
        of intervals: some Sequence<RouteSuspensionInterval>,
        within window: ClosedRange<Date>
    ) -> RouteSuspendedTime {
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

        return RouteSuspendedTime(
            duration: DateRangeUnion.coveredDuration(usable),
            intervalCount: sourceCount,
            openIntervalCount: openCount,
            unusableIntervalCount: unusableCount
        )
    }
}
