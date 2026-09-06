import Foundation

/// One period duration and the shifts behind it.
///
/// The pairing of a figure with its counts is the point, and it is why a
/// coverage-carrying export is JSON and not a spreadsheet row. `$2.18 per
/// recorded mile` over four of six shifts is a different statement from the same
/// figure over all six, and a file that wrote the figure alone would have turned
/// a subtotal into a claim on its way out of the app. The counts travel with the
/// number, exactly as ``MetricCoverage`` makes them travel on screen.
///
/// The nouns are spelled into the field names — `contributingShiftCount`,
/// `totalShiftCount` — rather than left as a generic `coverage` object, because
/// one block below counts deliveries rather than shifts and a reader must not
/// have to guess which.
nonisolated struct PeriodDurationExport: Equatable, Sendable, Codable {
    /// `null` when no shift in the period has this duration measurable. Never
    /// zero: a period whose shifts recorded no measurable delivery active time
    /// is not a period in which no time was spent on deliveries.
    let seconds: Int?

    let contributingShiftCount: Int
    let totalShiftCount: Int

    init(_ duration: TimeInterval?, coverage: MetricCoverage) {
        seconds = ExportDuration.seconds(duration)
        contributingShiftCount = coverage.contributingCount
        totalShiftCount = coverage.eligibleCount
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, contributingShiftCount, totalShiftCount
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(seconds, forKey: .seconds)
        try container.encode(contributingShiftCount, forKey: .contributingShiftCount)
        try container.encode(totalShiftCount, forKey: .totalShiftCount)
    }
}

/// The period's recorded gross earnings and the shifts that recorded them.
nonisolated struct PeriodEarningsExport: Equatable, Sendable, Codable {
    /// The amounts recorded on the period's **shifts**, added up, or `null`
    /// when no shift in it has one. Delivery amounts are never added in here.
    let recordedGrossEarnings: ExportAmount?

    let contributingShiftCount: Int
    let totalShiftCount: Int

    let currencyCode: String

    init(_ amount: Money?, coverage: MetricCoverage) {
        recordedGrossEarnings = ExportAmount.recorded(amount)
        contributingShiftCount = coverage.contributingCount
        totalShiftCount = coverage.eligibleCount
        currencyCode = Money.displayCurrencyCode
    }

    private enum CodingKeys: String, CodingKey {
        case recordedGrossEarnings, contributingShiftCount, totalShiftCount, currencyCode
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(recordedGrossEarnings, forKey: .recordedGrossEarnings)
        try container.encode(contributingShiftCount, forKey: .contributingShiftCount)
        try container.encode(totalShiftCount, forKey: .totalShiftCount)
        try container.encode(currencyCode, forKey: .currencyCode)
    }
}

/// The amounts recorded against individual deliveries in the period.
///
/// **A separate record, never the period's earnings.** It is here so a driver
/// can see how much of their delivery-by-delivery bookkeeping they filled in.
/// Nothing subtracts it from the shift subtotal, and the file contains no
/// difference between the two: bonuses, adjustments, stacked payouts and
/// unrecorded deliveries all make them differ ordinarily, and a "shortfall"
/// field would call that difference an error.
nonisolated struct PeriodDeliveryEarningsExport: Equatable, Sendable, Codable {
    let recordedTotal: ExportAmount?

    /// Deliveries in the period that carry an amount.
    let contributingDeliveryCount: Int

    /// Finished deliveries in the period, whether or not they carry one.
    let totalDeliveryCount: Int

    let currencyCode: String

    init(_ amount: Money?, coverage: MetricCoverage) {
        recordedTotal = ExportAmount.recorded(amount)
        contributingDeliveryCount = coverage.contributingCount
        totalDeliveryCount = coverage.eligibleCount
        currencyCode = Money.displayCurrencyCode
    }

    private enum CodingKeys: String, CodingKey {
        case recordedTotal, contributingDeliveryCount, totalDeliveryCount, currencyCode
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(recordedTotal, forKey: .recordedTotal)
        try container.encode(contributingDeliveryCount, forKey: .contributingDeliveryCount)
        try container.encode(totalDeliveryCount, forKey: .totalDeliveryCount)
        try container.encode(currencyCode, forKey: .currencyCode)
    }
}

/// One category's share of the period's recorded expenses.
nonisolated struct PeriodExpenseCategoryExport: Equatable, Sendable, Codable {
    /// One of ``ExpenseCategory``'s closed set.
    let category: ExpenseCategory

    /// The recorded amounts in this category, added up.
    let total: ExportAmount

    /// How many records that was.
    let recordCount: Int

    init(_ total: ExpenseCategoryTotal) {
        category = total.category
        self.total = ExportAmount(total.total)
        recordCount = total.recordCount
    }
}

/// What the driver recorded the period cost.
///
/// **A subtotal of entered records, never the period's costs.** There is no
/// coverage pair here, and its absence is deliberate rather than an oversight: a
/// coverage pair needs a denominator, and nothing on the device knows how many
/// costs a driver incurred and did not enter. A count of what was entered is the
/// whole of what can honestly be stated, and a reader must not turn it into
/// completeness.
///
/// Nothing here is per hour, per mile or per delivery. See
/// ``ExpenseTotalsCalculator`` for why no such rate exists anywhere in the app.
nonisolated struct PeriodExpensesExport: Equatable, Sendable, Codable {
    /// The recorded amounts added up, or `null` when nothing was recorded in the
    /// period. Never `0.00`: a period with no expense recorded is not a period
    /// that cost nothing.
    let recordedTotal: ExportAmount?

    /// How many expense records the total came from.
    let recordCount: Int

    let currencyCode: String

    /// The same total split by category, holding only the categories with a
    /// record in the period.
    let byCategory: [PeriodExpenseCategoryExport]

    init(_ totals: PeriodExpenseTotals) {
        recordedTotal = ExportAmount.recorded(totals.recordedTotal)
        recordCount = totals.recordCount
        currencyCode = Money.displayCurrencyCode
        byCategory = totals.categoryTotals.map(PeriodExpenseCategoryExport.init)
    }

    private enum CodingKeys: String, CodingKey {
        case recordedTotal, recordCount, currencyCode, byCategory
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(recordedTotal, forKey: .recordedTotal)
        try container.encode(recordCount, forKey: .recordCount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(byCategory, forKey: .byCategory)
    }
}

/// The period's recorded gross earnings less its recorded expenses.
///
/// The field is named for exactly what the figure is, and the name is the
/// contract: a reader relabelling `netAfterRecordedExpenses` as profit, take-home
/// pay or a taxable amount is making a claim this file does not. Both halves are
/// subtotals of what the driver entered, so the difference is an **upper bound**
/// on what the period netted, and the counts beside it are what say how partial
/// each half was.
///
/// `null` unless both halves were recorded — see ``PeriodNetAfterExpenses`` for
/// why each refusal exists.
nonisolated struct PeriodNetAfterExpensesExport: Equatable, Sendable, Codable {
    let amount: ExportAmount?

    /// Shifts that carried a recorded amount, out of the completed shifts in the
    /// period.
    let contributingShiftCount: Int
    let totalShiftCount: Int

    /// How many expense records were subtracted.
    let expenseRecordCount: Int

    let currencyCode: String

    init(_ net: PeriodNetAfterExpenses) {
        amount = ExportAmount.recorded(net.amount)
        contributingShiftCount = net.earningsCoverage.contributingCount
        totalShiftCount = net.earningsCoverage.eligibleCount
        expenseRecordCount = net.expenseRecordCount
        currencyCode = Money.displayCurrencyCode
    }

    private enum CodingKeys: String, CodingKey {
        case amount, contributingShiftCount, totalShiftCount, expenseRecordCount, currencyCode
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(amount, forKey: .amount)
        try container.encode(contributingShiftCount, forKey: .contributingShiftCount)
        try container.encode(totalShiftCount, forKey: .totalShiftCount)
        try container.encode(expenseRecordCount, forKey: .expenseRecordCount)
        try container.encode(currencyCode, forKey: .currencyCode)
    }
}

/// One period rate and the shifts that carried **both** halves of it.
///
/// A shift missing either the amount or the denominator contributed neither, so
/// this count is not the same as the earnings coverage above it. Exporting the
/// figure without it would publish a naked `$2.18/mi`, which is the one thing a
/// period export must not do.
nonisolated struct PeriodRateExport: Equatable, Sendable, Codable {
    let amount: ExportAmount?
    let contributingShiftCount: Int
    let totalShiftCount: Int

    init(_ rate: PeriodRate) {
        amount = ExportAmount.recorded(rate.amount)
        contributingShiftCount = rate.coverage.contributingCount
        totalShiftCount = rate.coverage.eligibleCount
    }

    private enum CodingKeys: String, CodingKey {
        case amount, contributingShiftCount, totalShiftCount
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(amount, forKey: .amount)
        try container.encode(contributingShiftCount, forKey: .contributingShiftCount)
        try container.encode(totalShiftCount, forKey: .totalShiftCount)
    }
}

/// What the period's routes measured, and how many of them are known to be
/// short.
///
/// The partial count is not a footnote. A partial route contributes real
/// distance to the total beside it and is the reason that total is a floor
/// rather than the miles driven.
nonisolated struct PeriodRouteExport: Equatable, Sendable, Codable {
    /// `null` when no route in the period measured anything.
    let recordedDistanceMetres: Double?
    let recordedDistanceMiles: Double?

    /// Completed shifts whose route measured a distance.
    let measuredShiftCount: Int

    /// Of those, how many are known to be missing part of the shift.
    let partialShiftCount: Int

    /// Completed shifts whose route measured nothing at all.
    let unmeasurableShiftCount: Int

    let totalShiftCount: Int

    /// Capture segments and gaps totalled across the period's shifts.
    let segmentCount: Int
    let gapCount: Int

    /// True when any route in the period predates recorded capture continuity.
    let usesInferredContinuity: Bool

    init(_ distance: RouteDistance, coverage: PeriodRouteCoverage) {
        recordedDistanceMetres = ExportDistance.metres(of: distance)
        recordedDistanceMiles = ExportDistance.miles(of: distance)
        measuredShiftCount = coverage.measuredShiftCount
        partialShiftCount = coverage.partialShiftCount
        unmeasurableShiftCount = coverage.unmeasurableShiftCount
        totalShiftCount = coverage.totalShiftCount
        segmentCount = distance.segmentCount
        gapCount = distance.gapCount
        usesInferredContinuity = distance.usesInferredContinuity
    }

    private enum CodingKeys: String, CodingKey {
        case recordedDistanceMetres, recordedDistanceMiles
        case measuredShiftCount, partialShiftCount, unmeasurableShiftCount, totalShiftCount
        case segmentCount, gapCount, usesInferredContinuity
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAlways(recordedDistanceMetres, forKey: .recordedDistanceMetres)
        try container.encodeAlways(recordedDistanceMiles, forKey: .recordedDistanceMiles)
        try container.encode(measuredShiftCount, forKey: .measuredShiftCount)
        try container.encode(partialShiftCount, forKey: .partialShiftCount)
        try container.encode(unmeasurableShiftCount, forKey: .unmeasurableShiftCount)
        try container.encode(totalShiftCount, forKey: .totalShiftCount)
        try container.encode(segmentCount, forKey: .segmentCount)
        try container.encode(gapCount, forKey: .gapCount)
        try container.encode(usesInferredContinuity, forKey: .usesInferredContinuity)
    }
}

/// The period's deliveries, counted by how they ended, with its recorded pickup
/// waits.
nonisolated struct PeriodDeliveriesExport: Equatable, Sendable, Codable {
    /// Counted apart and never summed into one "completed" figure.
    let deliveredCount: Int
    let cancelledCount: Int

    /// Should be zero — a shift cannot end while a delivery is running — and is
    /// carried so an anomalous stored row is visible rather than reclassified.
    let inProgressCount: Int

    /// Distinct pickup places named. A count and nothing more: places are never
    /// ranked, scored or compared, here or anywhere.
    let pickupPlaceCount: Int

    /// The middle of the **individual** recorded waits in the period, not an
    /// average of each place's median. `null` when none was recorded.
    let medianPickupWaitSeconds: Int?

    /// How many recorded waits that median is the middle of.
    let pickupWaitSampleCount: Int

    init(_ metrics: PeriodMetrics) {
        deliveredCount = metrics.deliverySummary.completed
        cancelledCount = metrics.deliverySummary.cancelled
        inProgressCount = metrics.deliverySummary.inProgress
        pickupPlaceCount = metrics.pickupPlaceCount
        medianPickupWaitSeconds = ExportDuration.seconds(metrics.medianPickupWait)
        pickupWaitSampleCount = metrics.pickupWaitSampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case deliveredCount, cancelledCount, inProgressCount, pickupPlaceCount
        case medianPickupWaitSeconds, pickupWaitSampleCount
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deliveredCount, forKey: .deliveredCount)
        try container.encode(cancelledCount, forKey: .cancelledCount)
        try container.encode(inProgressCount, forKey: .inProgressCount)
        try container.encode(pickupPlaceCount, forKey: .pickupPlaceCount)
        try container.encodeAlways(medianPickupWaitSeconds, forKey: .medianPickupWaitSeconds)
        try container.encode(pickupWaitSampleCount, forKey: .pickupWaitSampleCount)
    }
}

/// What a day or a week adds up to, written into the file with every count the
/// screen shows.
///
/// It is the same ``PeriodMetrics`` the summary screen reads, reshaped and not
/// recalculated: ``PeriodMetricsCalculator`` remains the only place a period
/// figure is derived, so a file and the screen it was exported from cannot
/// disagree.
///
/// Nothing is added here that the screen does not show. There is no total the
/// coverage does not qualify, no difference between the two kinds of amount, and
/// no projection to the end of the week.
nonisolated struct PeriodExportSummary: Equatable, Sendable, Codable {
    /// Completed shifts whose `startedAt` falls in the period. A shift running
    /// past midnight is counted whole, on the day it began.
    let completedShiftCount: Int

    let elapsed: PeriodDurationExport
    let deliveryActive: PeriodDurationExport

    /// **Not idle time.** See ``PeriodMetrics/nonDeliveryDuration``.
    let nonDelivery: PeriodDurationExport

    let earnings: PeriodEarningsExport
    let deliveryEarnings: PeriodDeliveryEarningsExport

    /// What the driver recorded the period cost, selected by the expenses' own
    /// dates rather than by any shift.
    let expenses: PeriodExpensesExport

    /// **Not profit.** See ``PeriodNetAfterExpensesExport``.
    let netAfterRecordedExpenses: PeriodNetAfterExpensesExport

    let route: PeriodRouteExport
    let deliveries: PeriodDeliveriesExport

    let grossPerElapsedHour: PeriodRateExport
    let grossPerDeliveryActiveHour: PeriodRateExport
    let grossPerRecordedMile: PeriodRateExport

    init(_ metrics: PeriodMetrics) {
        completedShiftCount = metrics.completedShiftCount
        elapsed = PeriodDurationExport(metrics.elapsedDuration, coverage: metrics.elapsedCoverage)
        deliveryActive = PeriodDurationExport(
            metrics.deliveryActiveDuration,
            coverage: metrics.deliveryActiveCoverage
        )
        nonDelivery = PeriodDurationExport(metrics.nonDeliveryDuration, coverage: metrics.nonDeliveryCoverage)
        earnings = PeriodEarningsExport(metrics.recordedGrossEarnings, coverage: metrics.earningsCoverage)
        deliveryEarnings = PeriodDeliveryEarningsExport(
            metrics.recordedDeliveryEarnings,
            coverage: metrics.deliveryEarningsCoverage
        )
        expenses = PeriodExpensesExport(metrics.expenses)
        netAfterRecordedExpenses = PeriodNetAfterExpensesExport(metrics.netAfterRecordedExpenses)
        route = PeriodRouteExport(metrics.recordedDistance, coverage: metrics.routeCoverage)
        deliveries = PeriodDeliveriesExport(metrics)
        grossPerElapsedHour = PeriodRateExport(metrics.grossPerElapsedHour)
        grossPerDeliveryActiveHour = PeriodRateExport(metrics.grossPerDeliveryActiveHour)
        grossPerRecordedMile = PeriodRateExport(metrics.grossPerRecordedMile)
    }
}
