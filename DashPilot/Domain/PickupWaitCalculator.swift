import Foundation

/// Turns recorded pickup waits into the figures a place's history shows.
///
/// A pure value type with no store, no view and no state, so the arithmetic that
/// decides what a driver is told can be tested without launching anything.
///
/// ## What it does not do
///
/// - **No trimming.** No outlier rejection, no winsorisation, no "unusually
///   long" filter. A 40-minute wait whose two timestamps are in order is a wait
///   that happened, and removing it would quietly make a slow place look fast.
/// - **No repair.** Rows whose lifecycle does not describe a wait are skipped
///   where they are read, by ``PickupWaitSample``; nothing is patched, filled in
///   or written back.
/// - **No prediction.** Nothing here models a next pickup, and no figure it
///   produces is weighted, decayed or extrapolated.
nonisolated struct PickupWaitCalculator: Equatable, Sendable {
    init() {}

    /// Aggregates recorded waits into one place's history.
    ///
    /// Order-independent: the samples are sorted here, so whatever order the
    /// store hands relationships back in cannot change a figure.
    func metrics(of samples: some Sequence<PickupWaitSample>) -> PickupWaitMetrics {
        let durations = samples.map(\.duration).sorted()
        guard !durations.isEmpty else { return .none }

        return PickupWaitMetrics(
            sampleCount: durations.count,
            medianDuration: Self.median(ofSorted: durations),
            shortestDuration: durations.first,
            longestDuration: durations.last,
            mostRecentSampleAt: samples.map(\.pickedUpAt).max()
        )
    }

    /// The median of any durations, sorting them first.
    ///
    /// Exposed so the rule can be tested directly on numbers, without a store or
    /// a delivery in the way.
    static func median(of durations: some Sequence<TimeInterval>) -> TimeInterval? {
        median(ofSorted: durations.sorted())
    }

    /// An odd count takes the middle value; an even count takes the midpoint of
    /// the two middle values.
    ///
    /// The midpoint is kept **exact**, fractional seconds and all: two waits of
    /// 10 and 11 minutes have a median of 10 minutes 30 seconds, and rounding it
    /// here would bake a presentation choice into the arithmetic. Rounding is
    /// ``DurationText``'s job, at the edge of the screen.
    private static func median(ofSorted durations: [TimeInterval]) -> TimeInterval? {
        guard !durations.isEmpty else { return nil }

        let middle = durations.count / 2
        guard durations.count.isMultiple(of: 2) else { return durations[middle] }
        // Halving each side rather than halving the sum: two very large
        // intervals cannot overflow their way to a wrong midpoint.
        return durations[middle - 1] / 2 + durations[middle] / 2
    }
}

extension PickupPlace {
    /// Every recorded wait at this place, oldest first.
    ///
    /// Read straight from the deliveries that reference it. The relationship is
    /// the only source: nothing is cached on the place, and no separate query
    /// exists to fall out of step with it. A driver's catalogue is bounded by
    /// how many places they have named and each place by how often they have
    /// been there, so this stays small; a stored counter would buy nothing here
    /// except a second answer free to drift.
    var pickupWaitSamples: [PickupWaitSample] {
        deliveries.compactMap(PickupWaitSample.init).sorted(by: PickupWaitSample.recordedBefore)
    }

    /// What this place's recorded waits add up to.
    ///
    /// Derived on demand and never persisted — see ``PickupWaitMetrics``.
    func pickupWaitMetrics(using calculator: PickupWaitCalculator = PickupWaitCalculator()) -> PickupWaitMetrics {
        calculator.metrics(of: pickupWaitSamples)
    }
}
