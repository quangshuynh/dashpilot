import Foundation

/// A rate derived across a period, with the shifts it was derived from.
///
/// The coverage is not decoration. Every period rate divides a **sum of
/// numerators** by a **sum of denominators** taken from the *same* shifts, and
/// which shifts those were is part of the answer: `$2.18 per recorded mile` over
/// four of six shifts is a different statement from the same figure over all
/// six, and a caller must be able to tell them apart.
///
/// There is one reason a period rate is unavailable — no shift carried both the
/// amount and a usable denominator — and the coverage already says so by
/// counting zero contributors. That is why this has no unavailability enum where
/// ``ShiftRate`` has one: a single shift can be missing an amount, or a route, or
/// time, and each is a different thing to tell the driver, while a period is
/// either made of contributing shifts or is not.
nonisolated struct PeriodRate: Equatable, Sendable {
    /// The quotient of the aggregate numerator and the aggregate denominator, or
    /// `nil` when no shift contributed both.
    let amount: Money?

    /// The shifts that carried both halves of this rate, out of the completed
    /// shifts in the period.
    let coverage: MetricCoverage

    var isAvailable: Bool { amount != nil }

    /// A rate no shift could contribute to.
    static func unavailable(eligibleCount: Int) -> PeriodRate {
        PeriodRate(amount: nil, coverage: MetricCoverage(contributingCount: 0, eligibleCount: eligibleCount))
    }
}

/// What the routes of a period's completed shifts can honestly be said to show.
///
/// Mileage gets its own coverage type rather than a ``MetricCoverage``, because
/// a route is missing in more than one way and the ways matter differently. A
/// shift with no measurable route contributes no distance at all; a shift with a
/// *partial* route contributes real, factual distance that is nonetheless known
/// to be less than what was driven. Flattening those into one "contributed /
/// did not" pair would hide the second, which is the one that makes a period's
/// mileage a floor rather than a total.
nonisolated struct PeriodRouteCoverage: Equatable, Sendable {
    /// Completed shifts in the period whose route measured a distance.
    let measuredShiftCount: Int

    /// Of those, how many are known to be missing part of the shift — capture
    /// stopped at least once, or the route predates recorded continuity.
    let partialShiftCount: Int

    /// Completed shifts in the period whose route measured nothing: no usable
    /// position, or no two positions captured continuously.
    let unmeasurableShiftCount: Int

    /// Completed shifts in the period, measured or not.
    let totalShiftCount: Int

    static let none = PeriodRouteCoverage(
        measuredShiftCount: 0,
        partialShiftCount: 0,
        unmeasurableShiftCount: 0,
        totalShiftCount: 0
    )

    /// Whether any route in the period measured a distance.
    var hasMeasuredRoute: Bool { measuredShiftCount > 0 }

    /// The measured shifts as an ordinary coverage pair, for the callers that
    /// only need "how many of how many".
    var measuredCoverage: MetricCoverage {
        MetricCoverage(contributingCount: measuredShiftCount, eligibleCount: totalShiftCount)
    }
}

/// What DashPilot can honestly say about a calendar period, read from the
/// completed shifts that belong to it.
///
/// ## The question it answers
///
/// *"What do the records DashPilot actually has say about this period?"* — never
/// *"what happened during this period"*. The app sees only what the driver
/// recorded, and a period is where that gap is easiest to forget: four shifts
/// with three amounts between them still produce a total, and the total looks
/// like a week's earnings unless the result itself refuses to let it.
///
/// So every figure that can be short of its sources is paired with the count it
/// came from, in the value rather than in a view. **A missing input is never a
/// zero**, at any level: a shift with no amount is not a shift that paid
/// nothing, and a shift with no measurable route is not a shift that drove
/// nowhere.
///
/// ## Nothing here is stored
///
/// Every field is derived from the period's shifts each time it is asked for,
/// exactly as ``ShiftMetrics``, ``RouteDistance`` and ``DeliveryActiveTime``
/// are. No weekly total, count or rate is persisted, so the schema is untouched
/// by this type and an improved calculation improves every past period at once.
///
/// ## Completed shifts only
///
/// A running shift is excluded. Its elapsed time is still growing, it has no
/// finalised amount, and including it would make a period's figures change every
/// second the driver is working.
nonisolated struct PeriodMetrics: Equatable, Sendable {
    /// The calendar span these figures describe.
    let period: ReportingPeriod

    // MARK: Shift coverage

    /// Completed shifts whose `startedAt` falls in the period.
    let completedShiftCount: Int

    /// The elapsed wall-clock time of those shifts, added up, or `nil` when none
    /// of them has a usable duration.
    ///
    /// Elapsed, not worked — the same claim ``ShiftMetrics/elapsedDuration``
    /// makes, summed. It includes waiting, repositioning and breaks.
    let elapsedDuration: TimeInterval?

    /// The shifts behind ``elapsedDuration``.
    let elapsedCoverage: MetricCoverage

    // MARK: Earnings

    /// The recorded gross earnings of the period's shifts, added up, or `nil`
    /// when no shift in it has an amount recorded.
    ///
    /// **The period's earnings source is the shift amount**, never a total of
    /// the amounts recorded against individual deliveries. Those are optional,
    /// routinely absent, and may not map one-to-one onto payouts; adding them up
    /// here would silently read every unrecorded delivery as one that paid
    /// nothing. The delivery amounts appear in this result only as their own
    /// separately labelled subtotal — see ``recordedDeliveryEarnings``.
    ///
    /// `nil` and zero stay different at this level too: a period where nobody
    /// recorded an amount has no total, while a period of shifts all recorded as
    /// paying nothing has a total of `$0.00`.
    let recordedGrossEarnings: Money?

    /// The shifts behind ``recordedGrossEarnings``, out of the completed shifts
    /// in the period. This is what stops a subtotal being read as a period total.
    let earningsCoverage: MetricCoverage

    // MARK: Delivery activity

    /// The per-shift unioned delivery active times, added up, or `nil` when no
    /// shift in the period has a measurable one.
    ///
    /// Each shift's figure already counts its own overlapping deliveries once.
    /// Nothing unions *across* shifts: two shifts are two recorded work
    /// sessions, and merging their clock times would treat a store holding
    /// overlapping shifts as one longer shift rather than as the anomaly it is.
    let deliveryActiveDuration: TimeInterval?

    /// The shifts behind ``deliveryActiveDuration``.
    let deliveryActiveCoverage: MetricCoverage

    /// The per-shift `elapsed − delivery active` durations, added up, or `nil`
    /// when no shift in the period has both.
    ///
    /// Summed per shift rather than derived as `period elapsed − period active`:
    /// those two sums can come from different sets of shifts, and subtracting
    /// one from the other would produce a duration belonging to neither.
    ///
    /// **Not idle time**, for the reason
    /// ``DeliveryActiveTime/nonDeliveryDuration(inElapsed:)`` states.
    let nonDeliveryDuration: TimeInterval?

    /// The shifts behind ``nonDeliveryDuration``.
    let nonDeliveryCoverage: MetricCoverage

    // MARK: Mileage

    /// The distance the period's routes recorded, added across the shifts whose
    /// routes measured something.
    ///
    /// A ``RouteDistance`` so the miles conversion and the formatting stay the
    /// ones the rest of the app uses, with the counts summed: segments and gaps
    /// are totals across the period's shifts. A shift with nothing measurable
    /// contributes nothing at all — never a zero.
    ///
    /// **Recorded, not driven.** Partial routes are included because their
    /// distance is factual, and ``routeCoverage`` is what says how many of them
    /// there were.
    let recordedDistance: RouteDistance

    /// How much of the period's driving the routes actually account for.
    let routeCoverage: PeriodRouteCoverage

    // MARK: Deliveries

    /// The deliveries recorded across the period's shifts, counted by how they
    /// ended.
    ///
    /// Delivered and cancelled are counted apart and never summed into one
    /// "completed" figure. `inProgress` should be zero — a shift cannot end
    /// while a delivery is running — and is carried because a store can hold
    /// anomalous rows that must be visible rather than silently reclassified.
    let deliverySummary: DeliverySummary

    /// Distinct pickup places named by the period's deliveries.
    ///
    /// A count and nothing more. Places are never ranked, scored or compared
    /// here.
    let pickupPlaceCount: Int

    // MARK: Pickup wait

    /// The median of every recorded pickup wait in the period, or `nil` when
    /// none was recorded.
    ///
    /// Taken over the **individual samples**, not over each place's median. A
    /// median of medians weights a place visited once the same as one visited
    /// twenty times and is not the middle of anything the driver experienced.
    let medianPickupWait: TimeInterval?

    /// How many recorded waits the median is the middle of.
    let pickupWaitSampleCount: Int

    // MARK: Delivery earnings coverage

    /// The amounts recorded against individual deliveries in the period, added
    /// up, or `nil` when none was recorded.
    ///
    /// **A separate fact, never the period's earnings.** It is reported so a
    /// driver can see how much of their delivery-by-delivery record they have
    /// filled in, and it is labelled as a subtotal across deliveries wherever it
    /// appears. Nothing subtracts it from ``recordedGrossEarnings``: the
    /// difference between the two is ordinary — bonuses, adjustments, stacked
    /// payouts, unrecorded deliveries — and presenting it as a shortfall would
    /// call an ordinary difference an error.
    let recordedDeliveryEarnings: Money?

    /// The deliveries behind ``recordedDeliveryEarnings``, out of the terminal
    /// deliveries in the period.
    let deliveryEarningsCoverage: MetricCoverage

    // MARK: Expenses

    /// The operating costs the driver recorded in this period, added up and
    /// split by category.
    ///
    /// Selected by their **own** timestamps rather than by a shift: an expense
    /// belongs to the period containing the moment it happened, and nothing
    /// attaches one to a shift or a delivery. See ``Expense``.
    ///
    /// A period with no expense recorded is not a period that cost nothing, and
    /// this total is a floor rather than the period's costs — the same claim
    /// ``recordedDistance`` makes about miles.
    let expenses: PeriodExpenseTotals

    /// Recorded gross earnings less recorded expenses, when both halves were
    /// recorded.
    ///
    /// **Never called profit**, and never a rate: see ``PeriodNetAfterExpenses``
    /// for what the figure may be said to be and
    /// ``ExpenseTotalsCalculator`` for why no cost-per-hour or cost-per-mile
    /// exists anywhere in the app.
    let netAfterRecordedExpenses: PeriodNetAfterExpenses

    // MARK: Rates

    /// Period gross earnings per elapsed shift hour.
    ///
    /// Aggregate over aggregate: the amounts of the shifts that have both an
    /// amount and a positive elapsed duration, divided by the elapsed time of
    /// **those same shifts**. Never the mean of the shifts' own hourly rates,
    /// which would weight a 30-minute shift the same as an eight-hour one.
    let grossPerElapsedHour: PeriodRate

    /// Period gross earnings per delivery active hour, over the shifts that have
    /// both an amount and a positive measurable delivery active time.
    ///
    /// The numerator is the **shift** amount, as everywhere else here. Amounts
    /// recorded against individual deliveries never enter it.
    let grossPerDeliveryActiveHour: PeriodRate

    /// Period gross earnings per recorded mile, over the shifts that have both
    /// an amount and a positive measurable recorded distance.
    ///
    /// The denominator is recorded mileage, which is normally less than the
    /// mileage driven, so this rate is normally higher than earnings per mile
    /// driven. A caller must not describe it as the latter.
    let grossPerRecordedMile: PeriodRate

    /// A period with no completed shift in it.
    ///
    /// Every figure is absent rather than zero. A week nobody drove is not a
    /// week of no earnings, no miles and no deliveries — it is a week with no
    /// records, and the interface says so instead of printing a grid of zeros.
    ///
    /// Expenses are carried in rather than emptied, because they do not depend
    /// on a shift: a driver can buy fuel on a day they did not drive, and that
    /// record must not disappear because no shift shares its date.
    static func empty(_ period: ReportingPeriod, expenses: PeriodExpenseTotals = .none) -> PeriodMetrics {
        PeriodMetrics(
            period: period,
            completedShiftCount: 0,
            elapsedDuration: nil,
            elapsedCoverage: .none,
            recordedGrossEarnings: nil,
            earningsCoverage: .none,
            deliveryActiveDuration: nil,
            deliveryActiveCoverage: .none,
            nonDeliveryDuration: nil,
            nonDeliveryCoverage: .none,
            recordedDistance: .none,
            routeCoverage: .none,
            deliverySummary: DeliverySummary(completed: 0, cancelled: 0),
            pickupPlaceCount: 0,
            medianPickupWait: nil,
            pickupWaitSampleCount: 0,
            recordedDeliveryEarnings: nil,
            deliveryEarningsCoverage: .none,
            expenses: expenses,
            netAfterRecordedExpenses: .unavailable(
                earningsCoverage: .none,
                expenseRecordCount: expenses.recordCount
            ),
            grossPerElapsedHour: .unavailable(eligibleCount: 0),
            grossPerDeliveryActiveHour: .unavailable(eligibleCount: 0),
            grossPerRecordedMile: .unavailable(eligibleCount: 0)
        )
    }

    /// Whether the period holds no completed shift at all.
    ///
    /// Says nothing about expenses, deliberately: it is the flag every figure
    /// derived from shifts depends on, and a period can hold a recorded cost
    /// with no shift beside it. Use ``hasAnyRecords`` to decide whether the
    /// period holds anything at all.
    var isEmpty: Bool { completedShiftCount == 0 }

    /// Whether DashPilot recorded anything at all in this period — a completed
    /// shift, an expense, or both.
    ///
    /// The two are independent records. A day off with a tank of fuel on it is
    /// not an empty day, and a day of driving with no cost recorded is not
    /// empty either.
    var hasAnyRecords: Bool { completedShiftCount > 0 || expenses.hasRecords }
}

/// The three rates a period derives, and what each one may be called.
///
/// A rate's name is a claim, so the names live here beside the coverage phrase
/// that qualifies them rather than in a view body. `Per recorded mile` and
/// `basis` are the pair that keeps `$2.18` from reading as earnings per mile
/// driven across the whole period, and neither is much use without the other.
nonisolated enum PeriodRateKind: String, CaseIterable, Sendable, Hashable, Identifiable {
    case perElapsedHour
    case perDeliveryActiveHour
    case perRecordedMile

    var id: String { rawValue }

    /// The printed label. Short, because three sit under one heading.
    var title: String {
        switch self {
        case .perElapsedHour: "Per shift hour"
        case .perDeliveryActiveHour: "Per active delivery hour"
        case .perRecordedMile: "Per recorded mile"
        }
    }

    /// What VoiceOver hears. The visible label under an "Earnings" heading can
    /// leave the numerator implied; a spoken one cannot.
    var spokenTitle: String {
        switch self {
        case .perElapsedHour: "gross earnings per shift hour"
        case .perDeliveryActiveHour: "gross earnings per delivery active hour"
        case .perRecordedMile: "gross earnings per recorded mile"
        }
    }

    /// What the shifts behind this rate had to have, singular.
    ///
    /// Both halves, always: a rate whose numerator came from one set of shifts
    /// and whose denominator came from another would be a number about no
    /// period at all.
    var basisNoun: String {
        switch self {
        case .perElapsedHour: "shift with both earnings and elapsed time"
        case .perDeliveryActiveHour: "shift with both earnings and measurable delivery active time"
        case .perRecordedMile: "shift with both earnings and a measurable route"
        }
    }

    var basisPluralNoun: String {
        switch self {
        case .perElapsedHour: "shifts with both earnings and elapsed time"
        case .perDeliveryActiveHour: "shifts with both earnings and measurable delivery active time"
        case .perRecordedMile: "shifts with both earnings and a measurable route"
        }
    }

    /// Why there is no figure, stated as the fact it is rather than as a fault.
    var unavailableExplanation: String {
        switch self {
        case .perElapsedHour:
            "No completed shift in this period has both a recorded amount and measurable elapsed time."
        case .perDeliveryActiveHour:
            "No completed shift in this period has both a recorded amount and measurable delivery active time."
        case .perRecordedMile:
            "No completed shift in this period has both a recorded amount and a measurable recorded route."
        }
    }
}

// MARK: Wording

/// The words a period is written and spoken in.
///
/// Kept next to the arithmetic for the reason ``RouteQuality``'s wording is: the
/// failure mode of an aggregate is a *claim*, not a crash. "This week: $284.50"
/// over three of four shifts is wrong in a way no arithmetic test would catch,
/// so what may be said about each figure is decided here, once, and asserted by
/// tests instead of being assembled from fragments in a view body.
nonisolated extension PeriodMetrics {
    /// How many completed shifts the period holds: `"4 completed shifts"`.
    var shiftCountStatement: String {
        "\(completedShiftCount) completed \(Self.shiftNoun(completedShiftCount))"
    }

    /// What a period with no completed shift says instead of a grid of zeros.
    var emptyStatement: String {
        switch period.unit {
        case .day: "No completed shifts recorded on this day."
        case .week: "No completed shifts recorded this week."
        case .month: "No completed shifts recorded this month."
        case .custom: "No completed shifts recorded in this range."
        }
    }

    // MARK: Earnings

    /// The recorded subtotal: `"$284.50 recorded"`, or `nil` when no shift in
    /// the period has an amount.
    ///
    /// The word `recorded` is not decoration. It is the difference between a
    /// subtotal of the shifts that answered and a claim about the period.
    func earningsStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        recordedGrossEarnings.map { "\($0.formatted(locale: locale)) recorded" }
    }

    /// The shifts behind the subtotal: `"3 of 4 shifts"`.
    var earningsCoverageStatement: String {
        earningsCoverage.statement()
    }

    /// Why a period with completed shifts still shows no amount.
    var noEarningsExplanation: String {
        "No completed shift in this period has an amount recorded. That is not the same as earning nothing."
    }

    func spokenEarningsStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard let amount = recordedGrossEarnings else {
            return "No recorded gross earnings. \(noEarningsExplanation)"
        }
        return "Recorded gross earnings, \(amount.formatted(locale: locale)), "
            + "\(earningsCoverage.spokenStatement())."
    }

    // MARK: Mileage

    /// What the period's routes measured: `"42.6 mi recorded"`.
    ///
    /// A period whose routes measured nothing says so rather than showing
    /// `0.0 mi`, which a driver reads as "you did not drive".
    func mileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard recordedDistance.isMeasured else { return "No route measured" }
        return "\(recordedDistance.formattedMiles(locale: locale)) recorded"
    }

    /// How much of the period's driving the routes account for:
    /// `"5 of 6 shifts measured · 3 partial"`.
    ///
    /// The partial count is a second clause rather than a footnote, because a
    /// partial route contributes real distance to the total above it and is the
    /// reason that total is a floor.
    var mileageCoverageStatement: String {
        var parts = ["\(routeCoverage.measuredCoverage.statement()) measured"]
        if routeCoverage.partialShiftCount > 0 {
            parts.append("\(routeCoverage.partialShiftCount) partial")
        }
        return parts.joined(separator: " · ")
    }

    /// The sentence that keeps a period's mileage from being read as the miles
    /// driven, or `nil` when no route in it is known to be incomplete.
    var mileagePartialExplanation: String? {
        guard routeCoverage.partialShiftCount > 0 else { return nil }
        let noun = routeCoverage.partialShiftCount == 1 ? "shift" : "shifts"
        return """
            \(routeCoverage.partialShiftCount) \(noun) recorded only part of the route. \
            DashPilot leaves the distance across a gap out rather than guessing at it, \
            so more miles were driven in this period than were recorded.
            """
    }

    func spokenMileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard recordedDistance.isMeasured else {
            return "No recorded mileage. No completed shift in this period has a measurable route."
        }
        var statement = "Recorded mileage, \(recordedDistance.formattedMiles(width: .wide, locale: locale)), "
            + "measured \(routeCoverage.measuredCoverage.spokenStatement())"
        if routeCoverage.partialShiftCount > 0 {
            statement += ", \(routeCoverage.partialShiftCount) with partial route capture"
        }
        return statement + "."
    }

    // MARK: Rates

    /// The rate of a given kind.
    func rate(_ kind: PeriodRateKind) -> PeriodRate {
        switch kind {
        case .perElapsedHour: grossPerElapsedHour
        case .perDeliveryActiveHour: grossPerDeliveryActiveHour
        case .perRecordedMile: grossPerRecordedMile
        }
    }

    /// The figure itself, or `nil` when no shift contributed both halves of it.
    func rateStatement(_ kind: PeriodRateKind, locale: Locale = .autoupdatingCurrent) -> String? {
        rate(kind).amount?.formatted(locale: locale)
    }

    /// What the rate was worked out from:
    /// `"Based on 4 of 6 shifts with both earnings and a measurable route"`.
    func rateBasisStatement(_ kind: PeriodRateKind) -> String {
        let coverage = rate(kind).coverage
        return "Based on \(coverage.statement(noun: kind.basisNoun, pluralNoun: kind.basisPluralNoun))"
    }

    func spokenRateStatement(_ kind: PeriodRateKind, locale: Locale = .autoupdatingCurrent) -> String {
        let rate = rate(kind)
        guard let amount = rate.amount else {
            return "No \(kind.spokenTitle). \(kind.unavailableExplanation)"
        }
        return "\(amount.formatted(locale: locale)) \(kind.spokenTitle), "
            + "based on \(rate.coverage.statement(noun: kind.basisNoun, pluralNoun: kind.basisPluralNoun))."
    }

    // MARK: Expenses

    /// The recorded costs: `"$48.60 recorded"`, or `nil` when the driver
    /// recorded none in this period.
    ///
    /// `recorded` is doing the same work it does under earnings, and more of it:
    /// there is no denominator here at all, so the word is the whole of what
    /// keeps a subtotal of typed-in costs from reading as what the period cost.
    func expenseStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        expenses.recordedTotal.map { "\($0.formatted(locale: locale)) recorded" }
    }

    /// How many records the total came from: `"Across 3 recorded expenses"`.
    ///
    /// A count and never a coverage pair. Nothing on the device knows how many
    /// costs a driver incurred, so `"3 of 3"` would state a completeness the app
    /// cannot observe.
    var expenseBasisStatement: String {
        guard expenses.hasRecords else { return "No expenses recorded" }
        return "Across \(expenses.recordCount) recorded \(Self.expenseNoun(expenses.recordCount))"
    }

    /// The sentence that keeps a recorded total from being read as the period's
    /// costs. Always present when there is a total: unlike a partial route,
    /// there is no count that could make it unnecessary.
    var expensesIncompleteExplanation: String {
        """
        These are the expenses you entered. DashPilot records no purchase of its own, so anything you \
        have not entered is not here and is not counted as zero.
        """
    }

    func spokenExpenseStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard let amount = expenses.recordedTotal else {
            return "No expenses recorded in this period. That is not the same as spending nothing."
        }
        return "Recorded expenses, \(amount.formatted(locale: locale)), "
            + "across \(expenses.recordCount) recorded \(Self.expenseNoun(expenses.recordCount))."
    }

    /// One category's share: `"Fuel, $42.10, 1 expense"`, spoken and written the
    /// same way because a row this short reads correctly either way.
    func categoryStatement(_ total: ExpenseCategoryTotal, locale: Locale = .autoupdatingCurrent) -> String {
        "\(total.category.title), \(total.total.formatted(locale: locale)), "
            + "\(total.recordCount) recorded \(Self.expenseNoun(total.recordCount))"
    }

    // MARK: Net after recorded expenses

    /// The figure itself, or `nil` when the period's records cannot support one.
    ///
    /// Deliberately not named on its own anywhere: every call site pairs it with
    /// ``netTitle``, which is the phrase that makes it honest.
    func netStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        netAfterRecordedExpenses.amount.map { $0.formatted(locale: locale) }
    }

    /// What the figure is called, in full, every time: `"Net after recorded
    /// expenses"`.
    ///
    /// Never shortened to "Net", and never "profit", "take-home" or "earnings
    /// after costs". The three words after "net" are the ones that stop it being
    /// a claim about what the driver actually made.
    var netTitle: String { "Net after recorded expenses" }

    /// What the net was worked out from: `"Recorded gross earnings across 2 of 3
    /// shifts, less 3 recorded expenses"`.
    var netBasisStatement: String {
        let net = netAfterRecordedExpenses
        return "Recorded gross earnings \(net.earningsCoverage.spokenStatement(noun: "shift")), "
            + "less \(net.expenseRecordCount) recorded \(Self.expenseNoun(net.expenseRecordCount))"
    }

    /// The sentence that has to sit under the figure wherever it appears.
    ///
    /// Both halves are floors — earnings over the shifts that recorded an
    /// amount, costs over the expenses that were entered — so their difference
    /// is an upper bound rather than a result. Saying so is what separates this
    /// figure from profit.
    var netCautionStatement: String {
        """
        Both halves are what you recorded: shifts with no amount are not counted, and costs you did \
        not enter are not subtracted. This is not profit, and it is not a tax figure.
        """
    }

    /// Why a period with records still shows no net figure.
    var netUnavailableExplanation: String {
        if !expenses.hasRecords {
            return """
                No expense is recorded in this period, so there is nothing to subtract. DashPilot does \
                not treat that as costing nothing.
                """
        }
        return """
            No completed shift in this period has an amount recorded, so there are no recorded \
            earnings to subtract these expenses from.
            """
    }

    func spokenNetStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard let amount = netStatement(locale: locale) else {
            return "No net after recorded expenses. \(netUnavailableExplanation)"
        }
        return "\(amount) net after recorded expenses. \(netBasisStatement). \(netCautionStatement)"
    }

    // MARK: Deliveries and pickups

    /// The middle recorded wait: `"9 min"`, or `nil` when none was recorded.
    var pickupWaitStatement: String? {
        medianPickupWait.map(DurationText.short)
    }

    /// What the median is the middle of: `"Based on 12 pickups"`.
    var pickupWaitBasisStatement: String {
        guard pickupWaitSampleCount > 0 else { return "No recorded pickup waits" }
        return "Based on \(pickupWaitSampleCount) recorded \(Self.pickupNoun(pickupWaitSampleCount))"
    }

    var spokenPickupWaitStatement: String {
        guard let median = medianPickupWait else {
            return "No recorded pickup waits in this period."
        }
        return "Median recorded pickup wait, \(DurationText.spoken(median)), "
            + "based on \(pickupWaitSampleCount) recorded \(Self.pickupNoun(pickupWaitSampleCount))."
    }

    /// The distinct places named, as a count and nothing else:
    /// `"5 pickup places recorded"`.
    var pickupPlaceStatement: String? {
        guard pickupPlaceCount > 0 else { return nil }
        return "\(pickupPlaceCount) pickup \(pickupPlaceCount == 1 ? "place" : "places") recorded"
    }

    /// The delivery amounts recorded in the period, labelled as what they are:
    /// `"$24.25 recorded across 2 of 3 deliveries"`.
    ///
    /// Never called the period's earnings, and never subtracted from the shift
    /// subtotal — see ``recordedDeliveryEarnings``.
    func deliveryEarningsStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        guard let amount = recordedDeliveryEarnings else { return nil }
        return "\(amount.formatted(locale: locale)) recorded "
            + "\(deliveryEarningsCoverage.spokenStatement(noun: "delivery", pluralNoun: "deliveries"))"
    }

    func spokenDeliveryEarningsStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        guard let amount = recordedDeliveryEarnings else { return nil }
        return "Amounts recorded against individual deliveries, \(amount.formatted(locale: locale)), "
            + "\(deliveryEarningsCoverage.spokenStatement(noun: "delivery", pluralNoun: "deliveries")). "
            + "This is a separate record from the shift amounts above and is not added to them."
    }

    private static func shiftNoun(_ count: Int) -> String {
        count == 1 ? "shift" : "shifts"
    }

    private static func pickupNoun(_ count: Int) -> String {
        count == 1 ? "pickup" : "pickups"
    }

    private static func expenseNoun(_ count: Int) -> String {
        count == 1 ? "expense" : "expenses"
    }
}
