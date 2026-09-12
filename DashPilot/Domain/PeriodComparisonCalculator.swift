import Foundation

/// Puts one period's results beside the equivalent period before it.
///
/// ## It aggregates nothing
///
/// Both sides arrive as finished ``PeriodMetrics``, each produced by
/// ``PeriodMetricsCalculator`` from the shifts and expenses that belong to its
/// own span. This type subtracts, divides once for a percentage, and decides
/// what may be said. **There is no second aggregation system**: a figure
/// compared here is the same figure the summary shows, derived by the same rule,
/// over the same paired subsets, carrying the same coverage.
///
/// That is also why nothing here averages. A month is compared with the month
/// before it, not with the mean of its weeks; a week's per-hour rate is its own
/// amounts over its own hours on both sides of the comparison.
///
/// ## What it refuses
///
/// - **A pair of periods that are not neighbours.** The previous side must be
///   exactly ``ReportingPeriod/precedingEquivalent(using:)`` of the current one,
///   so nothing can quietly compare a week with a month, a period with itself,
///   or two spans a caller assembled by hand.
/// - **A percentage that would mislead.** See ``PeriodPercentageRefusal``: a
///   missing figure, a previous figure of zero, a period that has not finished,
///   coverage short of its records, and a change that rounds to nothing.
/// - **Every judgement.** No score, rank, streak, projection, target or trend.
///   Two periods and the differences between their records is the whole output.
nonisolated struct PeriodComparisonCalculator: Equatable, Sendable {
    init() {}

    /// The comparison between `current` and the period before it, or `nil` when
    /// the two are not that pair.
    ///
    /// - Parameters:
    ///   - current: the selected period's metrics.
    ///   - previous: the metrics of the span
    ///     ``ReportingPeriod/precedingEquivalent(using:)`` names. Passed in
    ///     rather than derived here, because deriving it would mean reading a
    ///     store, and this layer reads none.
    ///   - now: what the clock says, for deciding whether the selected period
    ///     has finished.
    ///   - calendar: the driver's own calendar, used for the preceding-period
    ///     check and for counting each span's days.
    func comparison(
        of current: PeriodMetrics,
        with previous: PeriodMetrics,
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> PeriodComparison? {
        guard let expected = current.period.precedingEquivalent(using: calendar),
              expected == previous.period else { return nil }

        let isInProgress = current.period.isCurrent(asOf: now)

        let entries = PeriodComparisonMetric.allMetrics.compactMap { metric in
            entry(metric, of: current, with: previous, isCurrentPeriodInProgress: isInProgress)
        }

        return PeriodComparison(
            current: current,
            previous: previous,
            isCurrentPeriodInProgress: isInProgress,
            currentDayCount: current.period.dayCount(using: calendar),
            previousDayCount: previous.period.dayCount(using: calendar),
            entries: entries
        )
    }

    // MARK: One figure

    /// One compared figure, or `nil` when neither period holds it.
    ///
    /// A metric absent from both sides is left out rather than printed as two
    /// absences: there is nothing to compare and nothing was recorded, and a row
    /// saying so twice would bury the rows that do say something.
    private func entry(
        _ metric: PeriodComparisonMetric,
        of current: PeriodMetrics,
        with previous: PeriodMetrics,
        isCurrentPeriodInProgress: Bool
    ) -> PeriodComparisonEntry? {
        let currentValue = Self.value(metric, in: current)
        let previousValue = Self.value(metric, in: previous)
        guard currentValue != nil || previousValue != nil else { return nil }

        let currentBasis = Self.basis(metric, in: current)
        let previousBasis = Self.basis(metric, in: previous)

        // A difference exists only when both sides do. A missing figure is not a
        // zero at this level either: subtracting last week's total from a week
        // whose shifts carry no amount would manufacture a fall out of an
        // absence.
        let difference = currentValue.flatMap { currentValue in
            previousValue.flatMap(currentValue.subtracting)
        }
        let direction = difference.map(Self.direction)

        let (percent, refusal) = Self.percentChange(
            current: currentValue,
            previous: previousValue,
            currentBasis: currentBasis,
            previousBasis: previousBasis,
            isCurrentPeriodInProgress: isCurrentPeriodInProgress
        )

        return PeriodComparisonEntry(
            metric: metric,
            current: currentValue,
            previous: previousValue,
            currentBasis: currentBasis,
            previousBasis: previousBasis,
            difference: difference,
            direction: direction,
            percentChange: percent,
            percentageRefusal: refusal
        )
    }

    private static func direction(of difference: PeriodComparisonValue) -> PeriodComparisonDirection {
        if difference.isZero { return .unchanged }
        return difference.magnitude > 0 ? .increase : .decrease
    }

    // MARK: Reading a figure out of a period

    /// The figure, exactly as ``PeriodMetrics`` already holds it.
    ///
    /// Nothing is recomputed here and nothing is substituted: an absent figure
    /// stays absent, a recorded `$0.00` stays a recorded zero, and a route that
    /// measured nothing yields no distance rather than zero miles.
    private static func value(_ metric: PeriodComparisonMetric, in metrics: PeriodMetrics) -> PeriodComparisonValue? {
        switch metric {
        case .completedShifts:
            return .count(metrics.completedShiftCount)
        case .workingTime:
            return metrics.workingDuration.map(PeriodComparisonValue.duration)
        case .deliveryActiveTime:
            return metrics.deliveryActiveDuration.map(PeriodComparisonValue.duration)
        case .recordedGrossEarnings:
            return metrics.recordedGrossEarnings.map(PeriodComparisonValue.money)
        case .recordedExpenses:
            return metrics.expenses.recordedTotal.map(PeriodComparisonValue.money)
        case .recordedMileage:
            // A route that measured nothing has no distance. Its metres are
            // zero because there is nothing to measure, which is not the
            // statement "no distance was driven".
            guard metrics.recordedDistance.isMeasured else { return nil }
            return .distance(metres: metrics.recordedDistance.metres)
        case .deliveriesCompleted:
            return .count(metrics.deliverySummary.completed)
        case let .rate(kind):
            return metrics.rate(kind).amount.map(PeriodComparisonValue.money)
        }
    }

    /// What that figure was derived from, taken from the same result.
    private static func basis(_ metric: PeriodComparisonMetric, in metrics: PeriodMetrics) -> PeriodComparisonBasis {
        switch metric {
        case .completedShifts, .deliveriesCompleted:
            return .exactCount
        case .workingTime:
            return .coverage(metrics.workingCoverage)
        case .deliveryActiveTime:
            return .coverage(metrics.deliveryActiveCoverage)
        case .recordedGrossEarnings:
            return .coverage(metrics.earningsCoverage)
        case .recordedExpenses:
            return .recordCount(metrics.expenses.recordCount)
        case .recordedMileage:
            return .routes(metrics.routeCoverage)
        case let .rate(kind):
            return .coverage(metrics.rate(kind).coverage)
        }
    }

    // MARK: Percentage

    /// The change as a whole percentage of the previous figure, or the reason
    /// there is none.
    ///
    /// Exactly one of the two is returned. The order the refusals are checked in
    /// is the order they matter to a driver: what is missing first, what cannot
    /// be divided next, then what the two spans are, then what the records
    /// behind them are, and only then the size of the change itself.
    ///
    /// Rounded to whole percent because that is the precision the inputs
    /// support: both sides are subtotals of hand-entered records over spans that
    /// may differ in length, and a tenth of a percent on that would be
    /// decoration. A change that rounds to zero is refused rather than printed
    /// as `0%`, which would read as "no change" over a difference that is
    /// stated on the same row.
    private static func percentChange(
        current: PeriodComparisonValue?,
        previous: PeriodComparisonValue?,
        currentBasis: PeriodComparisonBasis,
        previousBasis: PeriodComparisonBasis,
        isCurrentPeriodInProgress: Bool
    ) -> (Int?, PeriodPercentageRefusal?) {
        guard let current, let previous else { return (nil, .valueMissing) }
        guard !previous.isZero else { return (nil, .previousIsZero) }
        guard !isCurrentPeriodInProgress else { return (nil, .currentPeriodInProgress) }
        guard currentBasis.isComplete, previousBasis.isComplete else { return (nil, .completenessUnknown) }

        let percent = wholePercent(from: previous.magnitude, to: current.magnitude)
        guard percent != 0 else { return (nil, .tooSmallToState) }
        return (percent, nil)
    }

    /// `(to − from) / |from| × 100`, rounded half away from zero.
    ///
    /// `Decimal` throughout, so a money ratio is taken from the exact recorded
    /// amounts rather than from a binary approximation of them.
    private static func wholePercent(from previous: Decimal, to current: Decimal) -> Int {
        let magnitude = previous < 0 ? -previous : previous
        var raw = (current - previous) / magnitude * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
