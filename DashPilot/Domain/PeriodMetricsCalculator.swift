import Foundation

/// One completed shift, reduced to the facts a period summary needs.
///
/// A plain value rather than a `Shift`, for the reason ``ShiftMetricsCalculator``
/// takes plain values: the aggregation can then be tested — every coverage case,
/// every paired-subset rule, every calendar boundary — without a store, a
/// container or a rendered view. ``Shift/periodRecord(for:)`` is the adapter that
/// reads a model into one.
///
/// It carries results rather than raw rows. Delivery active time arrives already
/// unioned for its shift, and the route already measured, because both are
/// answers this app has already defined elsewhere and re-deriving them here
/// would be a second definition free to drift.
nonisolated struct PeriodShiftRecord: Equatable, Sendable {
    /// What decides which period the shift belongs to. See
    /// ``ReportingPeriod/contains(_:)``.
    let startedAt: Date

    /// Whether the shift has ended. A running shift never enters a historical
    /// period total.
    let isCompleted: Bool

    /// The shift's elapsed wall-clock length, or `nil` when it has none to
    /// contribute — a running shift, or a stored row whose duration is not a
    /// usable measurement.
    let elapsedDuration: TimeInterval?

    /// What the driver recorded the shift paid, or `nil` if they have not.
    /// Never read as zero.
    let grossEarnings: Money?

    /// What the shift's retained route measured.
    let recordedDistance: RouteDistance

    /// The union of the shift's own delivery intervals, already counting
    /// deliveries worked at the same time once.
    let deliveryActiveTime: DeliveryActiveTime

    /// How many deliveries the shift recorded, and how they ended.
    let deliverySummary: DeliverySummary

    /// Every recorded pickup wait in the shift, as individual samples.
    ///
    /// Samples rather than a median: a period's median is taken over all of its
    /// pickups, and a median of per-shift medians is the middle of nothing.
    let pickupWaits: [PickupWaitSample]

    /// The distinct pickup places the shift's deliveries named.
    let pickupPlaceIDs: Set<UUID>

    /// The amounts recorded against individual finished deliveries, one entry
    /// each. A delivery with no amount contributes no entry — never a zero.
    let recordedDeliveryEarnings: [Money]

    /// Finished deliveries in the shift, whether or not they carry an amount.
    /// The denominator of the delivery-earnings coverage.
    let terminalDeliveryCount: Int

    init(
        startedAt: Date,
        isCompleted: Bool = true,
        elapsedDuration: TimeInterval?,
        grossEarnings: Money? = nil,
        recordedDistance: RouteDistance = .none,
        deliveryActiveTime: DeliveryActiveTime = .none,
        deliverySummary: DeliverySummary = DeliverySummary(completed: 0, cancelled: 0),
        pickupWaits: [PickupWaitSample] = [],
        pickupPlaceIDs: Set<UUID> = [],
        recordedDeliveryEarnings: [Money] = [],
        terminalDeliveryCount: Int = 0
    ) {
        self.startedAt = startedAt
        self.isCompleted = isCompleted
        self.elapsedDuration = elapsedDuration
        self.grossEarnings = grossEarnings
        self.recordedDistance = recordedDistance
        self.deliveryActiveTime = deliveryActiveTime
        self.deliverySummary = deliverySummary
        self.pickupWaits = pickupWaits
        self.pickupPlaceIDs = pickupPlaceIDs
        self.recordedDeliveryEarnings = recordedDeliveryEarnings
        self.terminalDeliveryCount = terminalDeliveryCount
    }

    /// The shift's elapsed time, but only when it is a usable measurement.
    ///
    /// A duration that is not finite, or is negative, describes a stored row the
    /// app cannot have written. It is excluded rather than clamped to zero: a
    /// zero would enter the period's elapsed total as a real shift of no length
    /// and would drag every rate derived from it.
    var usableElapsedDuration: TimeInterval? {
        guard let elapsedDuration, elapsedDuration.isFinite, elapsedDuration >= 0 else { return nil }
        return elapsedDuration
    }

    /// The shift's delivery active time, when it was measurable at all.
    var measuredDeliveryActiveDuration: TimeInterval? {
        guard deliveryActiveTime.isAvailable, deliveryActiveTime.duration.isFinite else { return nil }
        return max(0, deliveryActiveTime.duration)
    }

    /// The part of the shift no recorded delivery covers, by the one rule that
    /// defines it.
    var nonDeliveryDuration: TimeInterval? {
        deliveryActiveTime.nonDeliveryDuration(inElapsed: usableElapsedDuration)
    }

    /// The shift's recorded miles, when its route measured a positive distance.
    ///
    /// A measured zero is a real measurement and is *not* returned here: a rate
    /// cannot divide by it, and this property exists to answer "can this shift be
    /// half of a per-mile rate".
    var positiveRecordedMiles: Double? {
        guard recordedDistance.isMeasured else { return nil }
        let miles = recordedDistance.miles
        guard miles.isFinite, miles > 0 else { return nil }
        return miles
    }
}

/// Aggregates completed shifts into what a calendar period can honestly be said
/// to show.
///
/// ## The two rules this type exists for
///
/// **1. A missing input never becomes a zero.** A shift with no amount recorded
/// does not enter the earnings total as `$0.00`, and a shift with no measurable
/// route does not enter the mileage total as zero miles. Each figure carries the
/// count of shifts that actually contributed to it, so a subtotal can never be
/// read as a total.
///
/// **2. A rate is an aggregate over an aggregate, never a mean of rates.** Each
/// rate sums the amounts of the shifts that carry *both* halves of it and
/// divides by the sum of those same shifts' denominators. Averaging the shifts'
/// own rates would weight a 30-minute shift the same as an eight-hour one and
/// would answer a question nobody asked; the tests construct fixtures where the
/// two give visibly different answers.
///
/// ## What it does not do
///
/// - **No store access.** It takes values, holds no context and runs no fetch.
/// - **No forecasting, scoring or ranking.** There is no projection to the end of
///   the week, no comparison against another period, no best or worst shift and
///   no merchant analysis.
/// - **No cross-shift union.** Delivery active time is summed from per-shift
///   unions. Two shifts are two recorded work sessions, and merging their clock
///   times would silently repair a store holding overlapping shifts instead of
///   leaving the anomaly visible.
nonisolated struct PeriodMetricsCalculator: Equatable, Sendable {
    init() {}

    /// Derives everything a period summary shows from the records it is given.
    ///
    /// - Parameters:
    ///   - records: candidate shifts, in any order. Records that are not
    ///     completed, and records whose `startedAt` falls outside `period`, are
    ///     excluded here — a caller may pre-filter for cost, but the rule is
    ///     applied here so it holds however the calculator is called.
    ///   - period: the calendar span being summarised.
    func metrics(of records: some Sequence<PeriodShiftRecord>, in period: ReportingPeriod) -> PeriodMetrics {
        let shifts = records.filter { $0.isCompleted && period.contains($0.startedAt) }
        guard !shifts.isEmpty else { return .empty(period) }

        let shiftCount = shifts.count

        let elapsed = total(of: shifts, using: \.usableElapsedDuration, eligibleCount: shiftCount)
        let active = total(of: shifts, using: \.measuredDeliveryActiveDuration, eligibleCount: shiftCount)
        let nonDelivery = total(of: shifts, using: \.nonDeliveryDuration, eligibleCount: shiftCount)

        let earnings = shifts.compactMap(\.grossEarnings)
        let waits = shifts.flatMap(\.pickupWaits)
        let waitMetrics = PickupWaitCalculator().metrics(of: waits)
        let deliveryEarnings = shifts.flatMap(\.recordedDeliveryEarnings)

        return PeriodMetrics(
            period: period,
            completedShiftCount: shiftCount,
            elapsedDuration: elapsed.value,
            elapsedCoverage: elapsed.coverage,
            // The sum of the amounts that were recorded, over the count that
            // recorded them. Absent — not zero — when nobody recorded one.
            recordedGrossEarnings: earnings.isEmpty ? nil : earnings.reduce(Money.zero, +),
            earningsCoverage: MetricCoverage(contributingCount: earnings.count, eligibleCount: shiftCount),
            deliveryActiveDuration: active.value,
            deliveryActiveCoverage: active.coverage,
            nonDeliveryDuration: nonDelivery.value,
            nonDeliveryCoverage: nonDelivery.coverage,
            recordedDistance: Self.distance(of: shifts),
            routeCoverage: Self.routeCoverage(of: shifts),
            deliverySummary: DeliverySummary(combining: shifts.map(\.deliverySummary)),
            pickupPlaceCount: shifts.reduce(into: Set<UUID>()) { $0.formUnion($1.pickupPlaceIDs) }.count,
            medianPickupWait: waitMetrics.medianDuration,
            pickupWaitSampleCount: waitMetrics.sampleCount,
            recordedDeliveryEarnings: deliveryEarnings.isEmpty ? nil : deliveryEarnings.reduce(Money.zero, +),
            deliveryEarningsCoverage: MetricCoverage(
                contributingCount: deliveryEarnings.count,
                eligibleCount: shifts.reduce(0) { $0 + $1.terminalDeliveryCount }
            ),
            grossPerElapsedHour: Self.hourlyRate(
                of: shifts,
                eligibleCount: shiftCount,
                seconds: \.usableElapsedDuration
            ),
            grossPerDeliveryActiveHour: Self.hourlyRate(
                of: shifts,
                eligibleCount: shiftCount,
                seconds: \.measuredDeliveryActiveDuration
            ),
            grossPerRecordedMile: Self.mileageRate(of: shifts, eligibleCount: shiftCount)
        )
    }

    // MARK: Durations

    /// Adds up one duration across the shifts that have it, keeping the count
    /// that did.
    ///
    /// Absent rather than zero when nothing contributed: a period whose shifts
    /// recorded no measurable delivery active time is not a period in which no
    /// time was spent on deliveries.
    private func total(
        of shifts: [PeriodShiftRecord],
        using duration: (PeriodShiftRecord) -> TimeInterval?,
        eligibleCount: Int
    ) -> (value: TimeInterval?, coverage: MetricCoverage) {
        let durations = shifts.compactMap(duration)
        let coverage = MetricCoverage(contributingCount: durations.count, eligibleCount: eligibleCount)
        return (durations.isEmpty ? nil : durations.reduce(0, +), coverage)
    }

    // MARK: Mileage

    /// The period's route, summed from its shifts' routes.
    ///
    /// The counts are added as well as the metres: segments and gaps are facts
    /// about capture, and a period's totals of them are facts about the period's
    /// capture. A shift with nothing measurable contributes a zero distance
    /// because it *has* nothing, and ``PeriodMetrics/routeCoverage`` is what
    /// keeps that from reading as a shift that drove nowhere.
    private static func distance(of shifts: [PeriodShiftRecord]) -> RouteDistance {
        RouteDistance(
            metres: shifts.reduce(0) { $0 + $1.recordedDistance.metres },
            segmentCount: shifts.reduce(0) { $0 + $1.recordedDistance.segmentCount },
            gapCount: shifts.reduce(0) { $0 + $1.recordedDistance.gapCount },
            usableSampleCount: shifts.reduce(0) { $0 + $1.recordedDistance.usableSampleCount },
            usesInferredContinuity: shifts.contains { $0.recordedDistance.usesInferredContinuity }
        )
    }

    private static func routeCoverage(of shifts: [PeriodShiftRecord]) -> PeriodRouteCoverage {
        let measured = shifts.filter(\.recordedDistance.isMeasured)
        return PeriodRouteCoverage(
            measuredShiftCount: measured.count,
            // Only a route that measured something can be *partial*: a shift
            // with no usable route is missing entirely, which the unmeasurable
            // count already states and which "partial" would understate.
            partialShiftCount: measured.filter(\.recordedDistance.isPartial).count,
            unmeasurableShiftCount: shifts.count - measured.count,
            totalShiftCount: shifts.count
        )
    }

    // MARK: Rates

    /// Gross earnings per hour, over the shifts that carry both an amount and a
    /// positive duration.
    ///
    /// The paired subset is the whole point: a shift whose amount is missing
    /// contributes neither its amount nor its hours, and a shift whose hours
    /// cannot be measured contributes neither either. Taking one half from one
    /// shift and the other from another would produce a figure describing no
    /// period at all.
    ///
    /// A recorded `$0.00` is a real numerator and stays in. A duration of zero
    /// is not a denominator and takes its shift out with it.
    private static func hourlyRate(
        of shifts: [PeriodShiftRecord],
        eligibleCount: Int,
        seconds: (PeriodShiftRecord) -> TimeInterval?
    ) -> PeriodRate {
        var total = Money.zero
        var duration: TimeInterval = 0
        var contributing = 0

        for shift in shifts {
            guard let earnings = shift.grossEarnings, let shiftSeconds = seconds(shift), shiftSeconds > 0 else {
                continue
            }
            total = total + earnings
            duration += shiftSeconds
            contributing += 1
        }

        let coverage = MetricCoverage(contributingCount: contributing, eligibleCount: eligibleCount)
        guard contributing > 0, let rate = ShiftMetricsCalculator.grossPerHour(of: total, over: duration) else {
            return PeriodRate(amount: nil, coverage: coverage)
        }
        return PeriodRate(amount: rate, coverage: coverage)
    }

    /// Gross earnings per recorded mile, over the shifts that carry both an
    /// amount and a positive measurable recorded distance.
    private static func mileageRate(of shifts: [PeriodShiftRecord], eligibleCount: Int) -> PeriodRate {
        var total = Money.zero
        var miles: Double = 0
        var contributing = 0

        for shift in shifts {
            guard let earnings = shift.grossEarnings, let shiftMiles = shift.positiveRecordedMiles else { continue }
            total = total + earnings
            miles += shiftMiles
            contributing += 1
        }

        let coverage = MetricCoverage(contributingCount: contributing, eligibleCount: eligibleCount)
        guard contributing > 0, let rate = ShiftMetricsCalculator.grossPerMile(of: total, over: miles) else {
            return PeriodRate(amount: nil, coverage: coverage)
        }
        return PeriodRate(amount: rate, coverage: coverage)
    }
}

extension Shift {
    /// This shift, reduced to the facts a period summary aggregates.
    ///
    /// The adapter between the model and ``PeriodMetricsCalculator``, holding no
    /// rule of its own: it reads the shift's recorded facts and hands them over.
    ///
    /// `recordedDistance` is passed in rather than measured here for the reason
    /// ``Shift/metrics(for:using:)`` takes it — measuring a route walks every
    /// position it holds, and a period can hold a week of them, so the caller
    /// measures once, off the main path, and reuses the result.
    func periodRecord(for recordedDistance: RouteDistance) -> PeriodShiftRecord {
        let deliveries = deliveriesInOrder

        return PeriodShiftRecord(
            startedAt: startedAt,
            isCompleted: !isActive,
            elapsedDuration: completedDuration,
            grossEarnings: grossEarnings,
            recordedDistance: recordedDistance,
            deliveryActiveTime: deliveryActiveTime(),
            deliverySummary: deliverySummary,
            pickupWaits: deliveries.compactMap(PickupWaitSample.init),
            pickupPlaceIDs: Set(deliveries.compactMap { $0.pickupPlace?.id }),
            recordedDeliveryEarnings: deliveries.compactMap(\.grossEarnings),
            terminalDeliveryCount: deliveries.filter(\.state.isFinished).count
        )
    }
}
