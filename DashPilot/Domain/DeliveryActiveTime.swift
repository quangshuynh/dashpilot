import Foundation

/// How much of a completed shift was covered by at least one recorded delivery.
///
/// ## The one rule this type exists for
///
/// **Overlapping deliveries are counted once.** A delivery active from 10:00 to
/// 10:30 and another from 10:10 to 10:40 is forty minutes of delivery active
/// time, not the fifty-five their durations add up to. A driver cannot be in two
/// places at once, and stacked work is ordinary work rather than an exception,
/// so the sum of delivery durations is not a duration of anything. See
/// ``DeliveryActiveTimeCalculator``.
///
/// ## What it measures
///
/// Time during which a delivery the driver recorded had not yet reached a
/// terminal state. Nothing more: DashPilot does not know whether they were
/// driving, waiting, parked or shopping, so this is never described as driving,
/// working, productive or billable time.
///
/// ## Nothing here is persisted
///
/// The whole result is derived from the deliveries' own timestamps every time it
/// is asked for, exactly as ``RouteDistance`` and ``ShiftMetrics`` are. A stored
/// `activeDuration` would be a second answer to a question the store can already
/// answer, and it would keep the old answer after the calculation improved.
nonisolated struct DeliveryActiveTime: Equatable, Sendable {
    /// The union of the delivery intervals, in seconds. Overlap is counted once.
    let duration: TimeInterval

    /// Delivery intervals the calculation was given, usable or not.
    let sourceIntervalCount: Int

    /// Intervals that contributed: those with a usable end that fell at least
    /// partly inside the shift.
    let countedIntervalCount: Int

    /// Stretches the counted intervals merged into.
    ///
    /// Fewer than ``countedIntervalCount`` exactly when deliveries overlapped or
    /// met, which is what ``hasOverlappingDeliveries`` reads.
    let mergedIntervalCount: Int

    /// Intervals whose delivery recorded no terminal event.
    ///
    /// Unreachable on a well-formed completed shift, because a shift cannot end
    /// while a delivery is active. Counted rather than filled in: there is no
    /// truthful end to invent for a delivery that never recorded finishing.
    let unfinishedIntervalCount: Int

    /// Intervals left out because their timestamps do not describe a stretch of
    /// this shift: an end before its start, or an interval lying entirely
    /// outside the shift's own window.
    ///
    /// Both are unreachable through the app's API and both are counted rather
    /// than repaired, so a total derived from anomalous rows is visibly short of
    /// its sources instead of quietly wrong.
    let malformedIntervalCount: Int

    /// A shift with no delivery interval to measure.
    static let none = DeliveryActiveTime(
        duration: 0,
        sourceIntervalCount: 0,
        countedIntervalCount: 0,
        mergedIntervalCount: 0,
        unfinishedIntervalCount: 0,
        malformedIntervalCount: 0
    )

    /// Whether any delivery interval could be measured at all.
    ///
    /// False for a shift that recorded no deliveries, and false for one whose
    /// recorded deliveries hold nothing usable. Duration is `0` in both cases
    /// because nothing was measured, which is not the same statement as "no time
    /// was spent on deliveries" — the interface must not present it as one.
    ///
    /// A measured zero is different again, and available: a delivery accepted
    /// and cancelled in the same instant is a real interval of no length.
    var isAvailable: Bool { countedIntervalCount > 0 }

    /// Intervals the calculation could not use, for either reason.
    var unusableIntervalCount: Int { unfinishedIntervalCount + malformedIntervalCount }

    /// Whether any two counted deliveries overlapped or met.
    ///
    /// The fact that makes this figure different from the sum of the deliveries'
    /// own durations, so a caller can say so rather than leaving a driver to
    /// wonder why the numbers do not add up.
    var hasOverlappingDeliveries: Bool { mergedIntervalCount < countedIntervalCount }
}
