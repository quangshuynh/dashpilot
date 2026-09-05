import Foundation

/// The stretch of a shift one recorded delivery was open for.
///
/// ## What "active" claims, and what it does not
///
/// A delivery is *active* from the moment the driver recorded accepting it
/// until the moment they recorded it delivered or cancelled. That is the whole
/// definition. DashPilot does not know whether the driver was moving, waiting
/// at a counter, shopping, parked, or doing something else entirely during
/// those minutes — it knows only that a delivery they recorded had not yet
/// reached a terminal state. Nothing here is driving time, working time or
/// productive time, and calling it any of those would claim a measurement the
/// app does not make.
///
/// ## Why the end is optional
///
/// A delivery with no terminal timestamp has no end, and there is nothing
/// truthful to substitute for one: "now" is not when it finished, and the
/// shift's end is a guess about a delivery that never recorded finishing. On a
/// completed shift this should be unreachable — a shift cannot end while any of
/// its deliveries are active — so an interval with no end describes a store
/// holding data the app cannot produce. ``DeliveryActiveTimeCalculator`` counts
/// those rather than filling them in.
nonisolated struct DeliveryActiveInterval: Equatable, Sendable {
    /// When the delivery became active: its `acceptedAt`.
    let start: Date

    /// When it stopped being active: `deliveredAt` for a completed delivery,
    /// `cancelledAt` for a cancelled one, and `nil` for one that recorded
    /// neither.
    ///
    /// A cancelled delivery ends here exactly as a completed one does. The
    /// driver really was working that delivery from accepting it until it fell
    /// through, and dropping the interval because the order did not arrive
    /// would erase time they spent.
    let end: Date?

    init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    /// Whether the delivery recorded no terminal event.
    var isUnfinished: Bool { end == nil }

    /// Whether the recorded end precedes the recorded start.
    ///
    /// The lifecycle transitions refuse a backwards timestamp, so this is
    /// unreachable through the app's own API. It is still asked, because a
    /// store that somehow holds such a row must not contribute a negative
    /// duration to a driver's shift.
    var isMalformed: Bool {
        guard let end else { return false }
        return end < start
    }

    /// The interval as a range, or `nil` when it has no usable end.
    ///
    /// `nil` covers both anomalies above, and neither is repaired: an interval
    /// that cannot say when it ended is left out of the total rather than given
    /// an invented end or a duration of zero that would look like a measurement.
    var bounds: ClosedRange<Date>? {
        guard let end, end >= start else { return nil }
        return start...end
    }

    /// This interval confined to `window`, or `nil` if it falls entirely outside
    /// it.
    ///
    /// Delivery events are already constrained by the lifecycle — a delivery is
    /// created on a running shift and the shift cannot end while it is active —
    /// so on well-formed data this returns the interval unchanged. It exists for
    /// data that is not well formed, where clipping keeps the result honest to
    /// its own name: delivery active time is time *within this shift*, so an
    /// interval reaching past either edge contributes only the part that lies
    /// inside, and one lying wholly outside contributes nothing.
    ///
    /// Nothing is written back. The stored timestamps are what the driver
    /// recorded and stay exactly as they are; the clipping applies to this
    /// derived reading of them and to nothing else.
    func clipped(to window: ClosedRange<Date>) -> ClosedRange<Date>? {
        guard let bounds else { return nil }
        guard bounds.lowerBound <= window.upperBound, bounds.upperBound >= window.lowerBound else { return nil }
        return max(bounds.lowerBound, window.lowerBound)...min(bounds.upperBound, window.upperBound)
    }
}

nonisolated extension DeliveryActiveInterval {
    /// The interval a recorded delivery describes.
    ///
    /// The adapter between the persisted model and the calculation: it reads
    /// the delivery's own timestamps and holds no rule of its own, so the union
    /// can be tested with plain values and no store.
    init(_ delivery: Delivery) {
        self.init(start: delivery.acceptedAt, end: delivery.deliveredAt ?? delivery.cancelledAt)
    }
}
