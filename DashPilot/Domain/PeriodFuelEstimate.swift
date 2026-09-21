import Foundation

/// What a period's shifts are estimated to have spent on fuel, over the shifts
/// that recorded enough to say.
///
/// ## Partial coverage is the whole problem
///
/// A week can hold six shifts of which four recorded a fuel economy, a gas price
/// and a measurable route. Adding those four estimates gives a real figure, and
/// presenting it as *what this week cost in fuel* is a claim about six shifts
/// made from four. That is the failure this type exists to make impossible: the
/// estimate never travels without the counts behind it, and nothing here ever
/// reports the covered subset as though it were the period.
///
/// So the figure is always accompanied by two coverages, because the two answer
/// different questions and either can mislead on its own:
///
/// - **Shifts.** `4 of 6 shifts` says how much of the driver's *work* is behind
///   the figure.
/// - **Recorded miles.** `142.3 of 188.9 recorded miles` says how much of the
///   *driving* is. Two short shifts missing their assumptions cost less coverage
///   than one long one, and only the mileage says so.
///
/// A percentage may be derived from the mileage, because miles are what fuel is
/// consumed over, but it is never the only thing said: a percentage hides which
/// four shifts and how long they were.
///
/// ## It is still not a recorded expense
///
/// Nothing here reads an ``Expense``, and no expense total includes any of it.
/// A driver may well have recorded the fill-ups that paid for these miles, so the
/// two can describe overlapping money in two places, and DashPilot does **not**
/// reconcile them: it does not know which shifts a tank was burned on. At period
/// scope that overlap becomes visible for the first time, because a recorded
/// `fuel` expense and this estimate can appear on one screen. They are kept
/// apart, labelled for what each is, and never added or subtracted from one
/// another. See ``PeriodEstimatedNet`` for what is and is not derived from this.
nonisolated struct PeriodFuelEstimate: Equatable, Sendable {
    /// The sum of the estimates of the shifts that have one, or `nil` when no
    /// shift in the period does.
    ///
    /// **Absent rather than zero.** A period where nobody recorded a fuel
    /// economy is not a period whose driving consumed nothing, and a `$0.00`
    /// there would be read as exactly that.
    let estimatedCost: Money?

    /// The gallons behind ``estimatedCost``, summed over the same shifts, or
    /// `nil` when there is no cost.
    let estimatedGallons: Decimal?

    /// How many of the period's completed shifts contributed, out of how many
    /// there are.
    let shiftCoverage: MetricCoverage

    /// The recorded mileage of the shifts that contributed.
    let coveredDistance: RouteDistance

    /// The recorded mileage of the whole period, which is
    /// ``PeriodMetrics/recordedDistance``.
    ///
    /// Carried here as well so the coverage statement can be built from one
    /// value rather than from two that a caller has to keep in step.
    let totalDistance: RouteDistance

    /// Whether any contributing shift's route is known to be incomplete.
    ///
    /// When it is, the estimate is a **floor**: more miles were driven than were
    /// recorded, so more fuel was used than this estimates. The sentence that
    /// says so travels with the figure.
    let isAnyRoutePartial: Bool

    /// A period with nothing to estimate over.
    static let none = PeriodFuelEstimate(
        estimatedCost: nil,
        estimatedGallons: nil,
        shiftCoverage: .none,
        coveredDistance: .none,
        totalDistance: .none,
        isAnyRoutePartial: false
    )

    /// Whether there is a figure at all.
    var isAvailable: Bool { estimatedCost != nil }

    /// Whether every completed shift in the period contributed.
    ///
    /// The one case where the interface may simplify what it draws. It may not
    /// drop the meaning: a listener is still told the estimate covers every
    /// shift, because "no coverage stated" and "complete coverage" must not look
    /// the same.
    var isComplete: Bool { shiftCoverage.isComplete && shiftCoverage.eligibleCount > 0 }
}

nonisolated extension PeriodFuelEstimate {
    /// `"4 of 6 shifts"`.
    var shiftCoverageStatement: String { shiftCoverage.statement() }

    /// `"142.3 of 188.9 recorded miles"`, or `nil` where the period measured no
    /// route at all and a mileage coverage would be a ratio of nothing.
    func mileageCoverageStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        guard totalDistance.isMeasured else { return nil }
        return """
            \(coveredDistance.formattedMiles(locale: locale)) of \
            \(totalDistance.formattedMiles(locale: locale)) recorded miles
            """
    }

    /// The share of the period's recorded miles the estimate covers, as a whole
    /// percentage, or `nil` where there are no recorded miles to take a share
    /// of.
    ///
    /// **Derived from mileage rather than from shifts**, because fuel is
    /// consumed over distance. It is deliberately never the only thing said: a
    /// percentage cannot say which shifts are missing or how long they were, and
    /// a caller that shows one must show the counts beside it.
    var mileageCoveragePercentage: Int? {
        guard totalDistance.isMeasured, totalDistance.metres > 0 else { return nil }
        return Int((coveredDistance.metres / totalDistance.metres * 100).rounded())
    }

    /// Why there is no estimate, in one sentence, or `nil` when there is one.
    ///
    /// Never implies the missing figure is zero.
    var unavailableExplanation: String? {
        guard !isAvailable else { return nil }
        guard shiftCoverage.eligibleCount > 0 else {
            return "No completed shift in this period, so there is nothing to estimate fuel over."
        }
        return """
            No completed shift in this period records both a fuel economy and a gas price over a \
            measured route. That is not the same as using no fuel.
            """
    }

    /// The whole figure said out loud, coverage included.
    ///
    /// A listener has no caption in view, so the counts are part of the
    /// sentence rather than something to be read afterwards.
    func spokenStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard let estimatedCost else {
            return "No estimated fuel cost. \(unavailableExplanation ?? "")"
        }

        var statement = "Estimated fuel, \(estimatedCost.formatted(locale: locale)), "
        if isComplete {
            statement += "across every completed shift in this period"
        } else {
            statement += "\(shiftCoverage.spokenStatement())"
        }
        if let mileage = mileageCoverageStatement(locale: locale) {
            statement += ", covering \(mileage)"
        }
        statement += "."
        if isAnyRoutePartial {
            statement += " \(Self.partialStatement)"
        }
        return statement
    }

    /// What a partial route means for a period's estimate, written once so the
    /// eye and the ear are told the same thing.
    static let partialStatement = """
        Some of these routes are partial, so more miles were driven than were recorded and more fuel \
        was used than this estimates.
        """
}

/// Why a period has no estimated net after fuel.
///
/// Its own vocabulary rather than a widening of ``EstimatedNetUnavailability``,
/// which describes one shift, for the reason that one exists rather than reusing
/// ``ShiftRateUnavailability``: the reasons are different facts about different
/// things, and a sentence about a period must not be written as though it were
/// about a shift.
nonisolated enum PeriodEstimatedNetUnavailability: Equatable, Sendable {
    /// The period holds no completed shift.
    case noCompletedShifts
    /// No shift in the period records both what it paid and enough to estimate
    /// its fuel, so there is no shift the subtraction could be performed for.
    case noShiftHasBoth
}

nonisolated extension PeriodEstimatedNetUnavailability {
    var explanation: String {
        switch self {
        case .noCompletedShifts:
            "No completed shift in this period, so there is nothing to work a net out from."
        case .noShiftHasBoth:
            """
            No completed shift in this period records both an amount and enough to estimate its \
            fuel, so there is no shift this could be worked out over. That is not the same as \
            earning nothing or using no fuel.
            """
        }
    }
}

/// What a period's shifts are estimated to have been left with after fuel, over
/// the shifts that recorded enough to say **both** halves.
///
/// ## Like with like, which is the whole design
///
/// The tempting arithmetic is `period earnings - period estimated fuel`, and it
/// is wrong whenever the two have different coverage: it takes a fuel figure
/// from four shifts off an earnings figure from six and labels the result as the
/// period's. So the subtraction is performed over the **paired subset** — the
/// shifts that recorded an amount *and* have an estimate — which is the rule
/// every rate in this app already follows, and the coverage of that subset
/// travels with the result.
///
/// Both halves of the subtraction are carried, so a reader can see the figures
/// it was performed on rather than having to trust that they were the right
/// ones. Neither is the period's headline earnings unless the coverage says the
/// subset is the whole period.
///
/// ## What it is not
///
/// **It is not net after recorded expenses.** ``PeriodNetAfterExpenses``
/// subtracts costs the driver actually recorded paying; this subtracts an
/// estimate. The two are shown separately and **never combined**, because a
/// recorded `fuel` expense and this estimate may describe the same fuel, and
/// subtracting both under one label would count it twice. DashPilot does not
/// know which shifts a tank was burned on and does not guess.
///
/// **It is not profit.** No vehicle cost, no depreciation, no insurance, no tax
/// and no unrecorded expense is in it.
nonisolated struct PeriodEstimatedNet: Equatable, Sendable {
    /// The recorded earnings of the paired subset, or `nil` when it is empty.
    let recordedEarnings: Money?

    /// The estimated fuel of the same subset, or `nil` when it is empty.
    let estimatedFuel: Money?

    /// `recordedEarnings - estimatedFuel`, or `nil` when there is no subset.
    ///
    /// May be negative, which is a real outcome and is shown as one.
    let amount: Money?

    /// How many shifts contributed, out of the period's completed shifts.
    let coverage: MetricCoverage

    /// Why there is no figure, or `nil` when there is one.
    let unavailability: PeriodEstimatedNetUnavailability?

    /// Whether the recorded mileage behind any contributing estimate is partial.
    ///
    /// When it is, the fuel is a floor and this net is therefore a **ceiling**.
    let isAnyRoutePartial: Bool

    static let none = PeriodEstimatedNet(
        recordedEarnings: nil,
        estimatedFuel: nil,
        amount: nil,
        coverage: .none,
        unavailability: .noCompletedShifts,
        isAnyRoutePartial: false
    )

    var isAvailable: Bool { amount != nil }

    /// Whether every completed shift in the period contributed both halves.
    var isComplete: Bool { coverage.isComplete && coverage.eligibleCount > 0 }
}

nonisolated extension PeriodEstimatedNet {
    var coverageStatement: String { coverage.statement() }

    /// The one sentence that keeps this from being read as the period's net.
    ///
    /// Said whenever the subset is not the whole period, which is exactly when
    /// the figure describes less work than the screen around it.
    var subsetCautionStatement: String? {
        guard isAvailable, !isComplete else { return nil }
        return """
            Worked out over the \(coverageStatement) that record both an amount and enough to \
            estimate their fuel. It is not this period's earnings less this period's fuel.
            """
    }

    /// The sentence that travels with the figure wherever it is shown.
    static let cautionStatement = """
        An estimate, not a recorded cost. It does not include recorded expenses, and a fuel purchase \
        you recorded under Expenses may be the same fuel, so the two are never added together.
        """

    func spokenStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard let amount else {
            return "No estimated net after fuel. \(unavailability?.explanation ?? "")"
        }

        var statement = "Estimated net after fuel, \(amount.formatted(locale: locale)), "
        statement += isComplete
            ? "across every completed shift in this period"
            : coverage.spokenStatement()
        statement += ". \(Self.cautionStatement)"
        if let caution = subsetCautionStatement {
            statement += " \(caution)"
        }
        if isAnyRoutePartial {
            statement += " Some of these routes are partial, so the fuel is a floor and this net is a ceiling."
        }
        return statement
    }
}
