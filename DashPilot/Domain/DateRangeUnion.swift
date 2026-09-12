import Foundation

/// The union of date ranges, as the fewest disjoint stretches that cover them.
///
/// Extracted so that two different questions about a shift are answered by one
/// rule: how much of it at least one delivery was open for
/// (``DeliveryActiveTimeCalculator``), and how much of it the driver had paused
/// (``ShiftPausedTimeCalculator``). Both are "how much time do these overlapping
/// stretches cover", and a second copy of the sweep would be free to drift from
/// the first in exactly the cases that are hardest to notice.
///
/// Sorting by start is what makes one sweep sufficient: once the ranges are in
/// order, a range either extends the stretch being built or begins a new one,
/// and no earlier stretch can ever be reopened. `O(n log n)` on the sort and
/// linear on the sweep; nothing walks a timeline second by second or discretises
/// it into buckets, both of which would trade exactness for work.
///
/// Two consequences worth stating, because they are asserted rather than
/// assumed:
///
/// - **The result does not depend on input order.** The sort is the only thing
///   that reads order, and merging takes the later of two ends, so ranges
///   sharing a start merge identically whichever arrives first.
/// - **Touching ranges do not leave a gap.** One stretch ending exactly as the
///   next begins is one continuous stretch, so the merge condition is
///   `start <= end` rather than `start < end`.
nonisolated enum DateRangeUnion {
    /// The union of `ranges`, ordered by start.
    static func merged(_ ranges: [ClosedRange<Date>]) -> [ClosedRange<Date>] {
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

    /// How much time the union of `ranges` covers.
    static func coveredDuration(_ ranges: [ClosedRange<Date>]) -> TimeInterval {
        merged(ranges).reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
    }
}
