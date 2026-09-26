import Foundation

/// How a whole week went, for the heading of that week in History.
///
/// ## It defines nothing
///
/// This type is an **adapter**, and that is the whole of its job. Every figure
/// it reports is `PeriodMetrics`, derived by `PeriodMetricsCalculator` over
/// `HistoryWeek`'s own `ReportingPeriod`: the same aggregation, the same
/// paired-subset rules, the same coverage and the same wording the period
/// summary screen shows. A second definition of "what a week came to" is
/// exactly the drift this project designs against, and History is the screen it
/// would have appeared on.
///
/// What it adds is a **selection**: which of a period summary's figures belong
/// above a list of shifts. A driver about to open individual shifts wants to
/// know how the week went, not to read a second period summary, so the handful of
/// figures here are the ones that answer that question and the rest stay on the
/// screen built for them.
///
/// ## Coverage travels with every figure
///
/// A week's earnings are the subtotal of the shifts that recorded an amount, its
/// working time the total of the shifts that have a usable one, its mileage what
/// the routes measured. None of those is necessarily every shift, so each line
/// that can be short of its sources carries the count behind it, exactly as the
/// period summary does. `4 of 6 shifts` beside a subtotal is the difference
/// between a subtotal and a claim about the week.
nonisolated struct HistoryWeekSummary: Equatable, Sendable {
    /// The week being summarised.
    let week: HistoryWeek

    /// Everything the week came to, in the app's one period vocabulary.
    ///
    /// Held whole rather than unpacked into stored figures, so that a
    /// caller needing something this type does not surface reaches the
    /// authoritative value rather than a copy of it.
    let metrics: PeriodMetrics

    /// Summarises one week's completed shifts.
    ///
    /// The records are filtered by the calculator, not here: `metrics(of:in:)`
    /// drops anything that is not completed or does not fall inside the period,
    /// so the rule holds however this is called and a caller that hands over its
    /// whole history gets the same answer as one that pre-filtered.
    init(
        week: HistoryWeek,
        records: some Sequence<PeriodShiftRecord>,
        calculator: PeriodMetricsCalculator = PeriodMetricsCalculator()
    ) {
        self.week = week
        self.metrics = calculator.metrics(of: records, in: week.period)
    }

    /// How many completed shifts the week holds.
    var completedShiftCount: Int { metrics.completedShiftCount }

    /// Whether there is anything to show. A week holding no completed shift
    /// never reaches History, which drops empty weeks rather than drawing them.
    var isEmpty: Bool { metrics.isEmpty }
}

nonisolated extension HistoryWeekSummary {
    /// The lines the summary draws, in reading order, each with what it is,
    /// what is behind it, and how prominently it is drawn.
    ///
    /// ## The hierarchy, and what it answers
    ///
    /// The question is *what did this week look like?*, so three figures lead
    /// and are drawn larger: what the week recorded paying, how long it was
    /// worked, and what its routes recorded. Under them, smaller: how many
    /// shifts and deliveries it held, and, only where the week has them, the
    /// estimated fuel and the net after it. That is six lines at most, and it
    /// stops there on purpose: the rates, delivery active time, pickup waits and
    /// the comparison are the period summary's, one tap away.
    ///
    /// ## Deliberately not here
    ///
    /// - **Elapsed time.** Working time is the figure every rate in the app
    ///   divides by, and a second duration beside it invites a driver to look
    ///   for a difference the shift detail already explains.
    /// - **Net after recorded expenses.** An expense belongs to a date, not to a
    ///   shift, and this card summarises a list of shifts. It also stays off
    ///   this card so that exactly one net sits here: the estimated net is
    ///   worked out over its paired subset, the recorded-expense net over a
    ///   different pair of inputs, and two nets on one small card is exactly
    ///   where they would be read as one. Nothing anywhere subtracts both.
    /// - **Any vehicle.** A week can hold shifts worked in different vehicles,
    ///   and a name is a snapshot label rather than an identity, so counting or
    ///   merging names would claim which vehicle was which. Each shift's detail
    ///   says what that shift recorded.
    func lines(locale: Locale = .autoupdatingCurrent) -> [HistoryWeekSummaryLine] {
        var lines: [HistoryWeekSummaryLine] = []

        // Recorded shift earnings, which is the app's one definition of what a
        // period paid. Absent rather than zero where no shift recorded an
        // amount, because a week nobody wrote a figure down for is not a week
        // that paid nothing.
        lines.append(
            HistoryWeekSummaryLine(
                id: .earnings,
                prominence: .primary,
                title: "Recorded earnings",
                value: metrics.recordedGrossEarnings?.formatted(locale: locale) ?? "Not recorded",
                detail: metrics.recordedGrossEarnings == nil
                    ? nil
                    : metrics.earningsCoverageStatement,
                spoken: metrics.spokenEarningsStatement(locale: locale)
            )
        )

        lines.append(
            HistoryWeekSummaryLine(
                id: .working,
                prominence: .primary,
                title: "Working time",
                value: metrics.workingDuration.map(DurationText.short) ?? "Not available",
                detail: metrics.workingDuration == nil ? nil : metrics.workingCoverage.statement(),
                spoken: spokenWorking
            )
        )

        lines.append(
            HistoryWeekSummaryLine(
                id: .mileage,
                prominence: .primary,
                title: "Recorded miles",
                value: metrics.recordedDistance.isMeasured
                    ? metrics.recordedDistance.formattedMiles(locale: locale)
                    : "Not measured",
                detail: metrics.recordedDistance.isMeasured ? metrics.mileageCoverageStatement : nil,
                spoken: metrics.spokenMileageStatement(locale: locale)
            )
        )

        // One line for the work itself: the shifts, and what their deliveries
        // came to, each outcome named rather than summed.
        lines.append(
            HistoryWeekSummaryLine(
                id: .activity,
                prominence: .secondary,
                title: "Shifts",
                value: "\(metrics.completedShiftCount)",
                detail: metrics.deliverySummary.statement,
                spoken: "\(metrics.shiftCountStatement). \(spokenDeliveries)"
            )
        )

        // Fuel and the net after it are shown only where the week has them.
        //
        // Absent rather than present-and-unavailable, unlike every figure above,
        // and the reason is that this is a **summary above a list**: a driver
        // who has never entered a fuel economy would otherwise carry two lines
        // saying so on every week they scroll past. The shift's own detail
        // screen is where an absent estimate is explained, because that is
        // where it can be acted on. Absent is never drawn as `$0.00`.
        if metrics.fuel.isAvailable {
            lines.append(
                HistoryWeekSummaryLine(
                    id: .estimatedFuel,
                    prominence: .secondary,
                    title: "Estimated fuel",
                    value: metrics.fuel.estimatedCost?.formatted(locale: locale) ?? "Not available",
                    detail: fuelCoverageDetail(locale: locale),
                    spoken: metrics.fuel.spokenStatement(locale: locale)
                )
            )
        }

        if metrics.estimatedNetAfterFuel.isAvailable {
            lines.append(
                HistoryWeekSummaryLine(
                    id: .estimatedNet,
                    prominence: .secondary,
                    title: "Estimated net after fuel",
                    value: metrics.estimatedNetAfterFuel.amount?.formatted(locale: locale) ?? "Not available",
                    detail: netCoverageDetail,
                    spoken: metrics.estimatedNetAfterFuel.spokenStatement(locale: locale)
                )
            )
        }

        return lines
    }

    /// Both coverages, because either alone can mislead: the shift count says
    /// how much of the week's work is behind the figure, the mileage how much of
    /// its driving. A partial route makes the estimate a floor, and the card
    /// says so rather than leaving it to the spoken form.
    private func fuelCoverageDetail(locale: Locale) -> String {
        var parts = [metrics.fuel.shiftCoverageStatement]
        if let mileage = metrics.fuel.mileageCoverageStatement(locale: locale) {
            parts.append(mileage)
        }
        if metrics.fuel.isAnyRoutePartial {
            parts.append("partial routes, so a floor")
        }
        return parts.joined(separator: " · ")
    }

    /// The coverage of the paired subset, and the two things the figure is
    /// not: it is before recorded expenses, and over partial routes it is a
    /// ceiling.
    private var netCoverageDetail: String {
        let net = metrics.estimatedNetAfterFuel
        var parts = [net.isComplete ? "Every shift this week" : net.coverageStatement]
        parts.append("before recorded expenses")
        if net.isAnyRoutePartial {
            parts.append("a ceiling")
        }
        return parts.joined(separator: " · ")
    }

    /// The whole week in one sentence, for a listener who has no columns to
    /// scan: which week it is, then how many shifts, then each figure with its
    /// unit and its coverage said in full.
    ///
    /// Spoken in the order a listener needs rather than the order drawn: the
    /// shift count comes first, because every figure after it is "of" those
    /// shifts.
    func spokenSummary(weekTitle: String? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        let lines = lines(locale: locale)
        let ordered = lines.filter { $0.id == .activity } + lines.filter { $0.id != .activity }
        var sentences = ordered.map(\.spoken)
        if let weekTitle {
            sentences.insert("\(weekTitle).", at: 0)
        }
        return sentences.joined(separator: " ")
    }

    private var spokenWorking: String {
        guard let duration = metrics.workingDuration else {
            return "No working time available. No completed shift in this week has a usable duration."
        }
        return "\(DurationText.spoken(duration)) working time, \(metrics.workingCoverage.spokenStatement())."
    }

    private var spokenDeliveries: String {
        guard !metrics.deliverySummary.isEmpty else { return "No deliveries recorded." }
        return "\(metrics.deliverySummary.spokenStatement)."
    }
}

/// One line of a weekly summary: what it is, what it says, and what is behind
/// it.
nonisolated struct HistoryWeekSummaryLine: Equatable, Sendable, Identifiable {
    /// Which figure this is, so a view and a test can name one without matching
    /// on its title.
    nonisolated enum Kind: String, Equatable, Sendable {
        case earnings
        case working
        case mileage
        /// The shift count and the deliveries' outcomes, on one line.
        case activity
        case estimatedFuel
        case estimatedNet
    }

    /// How a line is drawn. Colour and weight are never the only difference:
    /// primary figures are also larger, and the order says the same thing.
    nonisolated enum Prominence: Equatable, Sendable {
        /// The three figures that answer "what did this week look like".
        case primary
        /// Context under them.
        case secondary
    }

    let id: Kind

    let prominence: Prominence

    /// What the figure is called on screen.
    let title: String

    /// The figure, or the words that stand in for one that was never recorded.
    /// **Never a zero standing in for a missing value.**
    let value: String

    /// What is behind the figure: the coverage, the split, or nothing where
    /// there is nothing to qualify.
    let detail: String?

    /// The whole line as one sentence, with every unit and every coverage said
    /// in full. A listener has no caption in view to read afterwards.
    let spoken: String
}
