import Foundation

/// Unions a shift's delivery intervals into the time it actually covered.
///
/// ## Why a union and not a sum
///
/// Delivery work is routinely stacked, and two deliveries open at once are two
/// records of the same minutes. Adding their durations would let a driver's
/// "active time" exceed the shift it happened in, and would make a rate divided
/// by it smaller the more orders they carried at once — the opposite of what
/// stacking does. The union counts each minute of the shift once, however many
/// deliveries were open during it.
///
/// ## The algorithm
///
/// Collect the intervals that can be used, sort by start, sweep once merging
/// each interval into the previous stretch when it starts at or before that
/// stretch's end, then add the merged lengths. `O(n log n)` on the sort and
/// linear on the sweep; nothing walks a timeline second by second or discretises
/// the shift into buckets, both of which would trade exactness for work.
///
/// Two consequences worth stating, because they are asserted rather than
/// assumed:
///
/// - **The result does not depend on input order.** The sort is the only thing
///   that reads order, and merging takes the later of two ends, so intervals
///   sharing a start merge identically whichever arrives first.
/// - **Touching intervals do not leave a gap.** One delivery ending exactly as
///   the next begins is a continuous stretch of delivery activity, so the merge
///   condition is `start <= end` rather than `start < end`.
///
/// ## What it refuses to do
///
/// Nothing is invented for an interval the data cannot support. An interval with
/// no end is not given one, an end before its start is not swapped, and neither
/// becomes a zero-length contribution that would look like a measurement. They
/// are counted on the result so a caller can see the total is short of its
/// sources.
///
/// It takes plain intervals rather than deliveries or a shift, imports neither
/// SwiftUI nor SwiftData, and makes no store query, so every case below is
/// testable without a container or a rendered view.
nonisolated struct DeliveryActiveTimeCalculator: Equatable, Sendable {
    init() {}

    /// Derives the delivery active time covered by `intervals`.
    ///
    /// - Parameters:
    ///   - intervals: one per recorded delivery, in any order.
    ///   - window: the completed shift's own start-to-end range, when the caller
    ///     has one. Intervals are clipped to it, so the result is time within
    ///     *this* shift and can never exceed the shift's elapsed duration. `nil`
    ///     measures the intervals as given, which is what a pure union test
    ///     wants and what a caller without a finished shift has.
    func activeTime(
        of intervals: some Sequence<DeliveryActiveInterval>,
        within window: ClosedRange<Date>? = nil
    ) -> DeliveryActiveTime {
        var usable: [ClosedRange<Date>] = []
        var sourceCount = 0
        var unfinishedCount = 0
        var malformedCount = 0

        for interval in intervals {
            sourceCount += 1

            guard !interval.isUnfinished else {
                unfinishedCount += 1
                continue
            }

            let bounds = window.map { interval.clipped(to: $0) } ?? interval.bounds
            guard let bounds else {
                // Either an end before its start, or an interval lying wholly
                // outside the shift it is attached to. Both describe a store the
                // app cannot have written, and neither is repaired here.
                malformedCount += 1
                continue
            }

            usable.append(bounds)
        }

        let merged = Self.merged(usable)

        return DeliveryActiveTime(
            duration: merged.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) },
            sourceIntervalCount: sourceCount,
            countedIntervalCount: usable.count,
            mergedIntervalCount: merged.count,
            unfinishedIntervalCount: unfinishedCount,
            malformedIntervalCount: malformedCount
        )
    }

    /// The union of `ranges`, as the fewest disjoint stretches that cover them.
    ///
    /// Sorting by start is what makes one sweep sufficient: once the ranges are
    /// in order, a range either extends the stretch being built or begins a new
    /// one, and no earlier stretch can ever be reopened.
    private static func merged(_ ranges: [ClosedRange<Date>]) -> [ClosedRange<Date>] {
        guard !ranges.isEmpty else { return [] }

        var merged: [ClosedRange<Date>] = []
        merged.reserveCapacity(ranges.count)

        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard let open = merged.last, range.lowerBound <= open.upperBound else {
                merged.append(range)
                continue
            }
            // Extending, not replacing: a range nested entirely inside the open
            // stretch must not shorten it.
            merged[merged.index(before: merged.endIndex)] =
                open.lowerBound...max(open.upperBound, range.upperBound)
        }

        return merged
    }
}

extension Shift {
    /// The interval each of this shift's deliveries was active for.
    var deliveryActiveIntervals: [DeliveryActiveInterval] {
        deliveriesInOrder.map(DeliveryActiveInterval.init)
    }

    /// How much of this shift at least one delivery was active for.
    ///
    /// The adapter between the model and ``DeliveryActiveTimeCalculator``: it
    /// reads the shift's own deliveries and its own window and hands them over,
    /// holding no rule of its own. Nothing is stored — the figure is recomputed
    /// from the deliveries every time it is asked for.
    ///
    /// A running shift has no window, so its unfinished deliveries are measured
    /// as they stand and contribute nothing. Final active-time figures are for
    /// completed shifts; ``ShiftMetrics`` is where that is enforced.
    func deliveryActiveTime(
        using calculator: DeliveryActiveTimeCalculator = DeliveryActiveTimeCalculator()
    ) -> DeliveryActiveTime {
        calculator.activeTime(of: deliveryActiveIntervals, within: completedWindow)
    }
}
