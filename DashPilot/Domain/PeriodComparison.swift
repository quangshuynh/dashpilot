import Foundation

/// Which way a compared figure moved, and nothing about whether that is good.
///
/// The words this becomes are chosen by ``PeriodComparisonMetric/nature``, and
/// none of them is a judgement. DashPilot holds the records a driver entered
/// about work it did not observe: a week with fewer recorded miles may be a
/// quieter week, a week spent on another app, or a week the driver kept the
/// phone locked. Naming any of those "worse" would be a claim about their work
/// from a system that only ever saw their bookkeeping.
nonisolated enum PeriodComparisonDirection: String, Equatable, Sendable, Hashable {
    case increase
    case decrease
    case unchanged
}

/// Whether a compared figure counts records or divides them.
///
/// The distinction decides the only verbs this feature uses. A total is *more*
/// or *less recorded* — the phrase carries its own caveat, because what changed
/// may be the driving or may be the entering. A rate is *higher* or *lower*,
/// which says what the arithmetic did and stops there.
nonisolated enum PeriodComparisonNature: String, Equatable, Sendable, Hashable {
    /// A count, a total or a duration: how much was recorded.
    case recordedVolume

    /// A derived rate: one recorded sum over another.
    case derivedRate
}

/// One figure a period comparison states, and the words it may be stated in.
///
/// The rates delegate their wording to ``PeriodRateKind`` rather than repeating
/// it, so a rate is named and qualified identically whether it is read on its
/// own or beside the period before it.
nonisolated enum PeriodComparisonMetric: Equatable, Sendable, Hashable, Identifiable {
    case completedShifts
    case workingTime
    case deliveryActiveTime
    case recordedGrossEarnings
    case recordedExpenses
    case recordedMileage
    case deliveriesCompleted
    case rate(PeriodRateKind)

    /// The figures a comparison states, in the order the summary reads them.
    ///
    /// A closed list, and the refusals in it are deliberate. **Net after
    /// recorded expenses is not compared**: each side is already the difference
    /// between two floors — earnings over the shifts that carry an amount, costs
    /// over the records that exist — and a difference between two upper bounds
    /// moves with the driver's bookkeeping in a direction nothing can state.
    /// **The median recorded pickup wait is not compared** either: two medians
    /// taken over different pickups are two order statistics, and subtracting
    /// one from the other describes no wait anybody experienced. Non-delivery
    /// time, the pickup-place count and the delivery-earnings subtotal are left
    /// out for the same kind of reason.
    static let allMetrics: [PeriodComparisonMetric] = [
        .completedShifts,
        .workingTime,
        .deliveryActiveTime,
        .recordedGrossEarnings,
        .rate(.perWorkingHour),
        .rate(.perDeliveryActiveHour),
        .recordedExpenses,
        .recordedMileage,
        .rate(.perRecordedMile),
        .deliveriesCompleted
    ]

    var id: String {
        switch self {
        case .completedShifts: "completedShifts"
        case .workingTime: "workingTime"
        case .deliveryActiveTime: "deliveryActiveTime"
        case .recordedGrossEarnings: "recordedGrossEarnings"
        case .recordedExpenses: "recordedExpenses"
        case .recordedMileage: "recordedMileage"
        case .deliveriesCompleted: "deliveriesCompleted"
        case let .rate(kind): "rate.\(kind.rawValue)"
        }
    }

    /// The printed label, matching the one the same figure carries on its own
    /// section of the summary.
    var title: String {
        switch self {
        case .completedShifts: "Completed shifts"
        case .workingTime: "Working"
        case .deliveryActiveTime: "Delivery active"
        case .recordedGrossEarnings: "Recorded gross earnings"
        case .recordedExpenses: "Recorded expenses"
        case .recordedMileage: "Recorded mileage"
        case .deliveriesCompleted: "Delivered"
        case let .rate(kind): kind.title
        }
    }

    /// What VoiceOver hears, which cannot lean on the heading above the row.
    var spokenTitle: String {
        switch self {
        case .completedShifts: "completed shifts"
        case .workingTime: "working shift time"
        case .deliveryActiveTime: "delivery active time"
        case .recordedGrossEarnings: "recorded gross earnings"
        case .recordedExpenses: "recorded expenses"
        case .recordedMileage: "recorded mileage"
        case .deliveriesCompleted: "deliveries delivered"
        case let .rate(kind): kind.spokenTitle
        }
    }

    var nature: PeriodComparisonNature {
        switch self {
        case .rate: .derivedRate
        default: .recordedVolume
        }
    }

    /// What the records behind this figure are called, singular.
    var basisNoun: String {
        switch self {
        case let .rate(kind): kind.basisNoun
        default: "shift"
        }
    }

    var basisPluralNoun: String {
        switch self {
        case let .rate(kind): kind.basisPluralNoun
        default: "shifts"
        }
    }

    /// How a movement in this figure is described.
    ///
    /// Never "better", "worse", "improved" or "down on last week". A total says
    /// what it is a total of — what was **recorded** — and a rate says which way
    /// the quotient went.
    func changeWord(_ direction: PeriodComparisonDirection) -> String {
        switch (nature, direction) {
        case (_, .unchanged): "the same"
        case (.recordedVolume, .increase): "more recorded"
        case (.recordedVolume, .decrease): "less recorded"
        case (.derivedRate, .increase): "higher"
        case (.derivedRate, .decrease): "lower"
        }
    }

    /// The same word for a percentage, which cannot take "recorded" without
    /// reading as a percentage of the records rather than of the figure.
    func percentageWord(_ direction: PeriodComparisonDirection) -> String {
        switch (nature, direction) {
        case (_, .unchanged): "the same"
        case (.recordedVolume, .increase): "more"
        case (.recordedVolume, .decrease): "less"
        case (.derivedRate, .increase): "higher"
        case (.derivedRate, .decrease): "lower"
        }
    }
}

/// One side of a compared figure: what it was, in the units it is kept in.
///
/// An enum rather than a `Double`, because money is `Decimal` here as it is
/// everywhere else in DashPilot and a comparison is not the place a currency
/// amount starts travelling through binary floating point.
nonisolated enum PeriodComparisonValue: Equatable, Sendable {
    case money(Money)
    case duration(TimeInterval)
    case count(Int)
    case distance(metres: Double)

    /// The value as a `Decimal`, for the one derived statistic that needs a
    /// ratio. Money keeps its exact amount.
    var magnitude: Decimal {
        switch self {
        case let .money(money): money.amount
        case let .duration(seconds): Decimal(seconds)
        case let .count(count): Decimal(count)
        case let .distance(metres): Decimal(metres)
        }
    }

    var isZero: Bool { magnitude.isZero }

    /// This value less `other`, or `nil` when the two are not the same kind of
    /// quantity — which the calculator never produces, and which is refused
    /// rather than coerced.
    func subtracting(_ other: PeriodComparisonValue) -> PeriodComparisonValue? {
        switch (self, other) {
        case let (.money(lhs), .money(rhs)): .money(lhs - rhs)
        case let (.duration(lhs), .duration(rhs)): .duration(lhs - rhs)
        case let (.count(lhs), .count(rhs)): .count(lhs - rhs)
        case let (.distance(lhs), .distance(rhs)): .distance(metres: lhs - rhs)
        default: nil
        }
    }

    /// The same quantity without its sign, for a sentence whose direction is
    /// already carried by a word.
    var magnitudeValue: PeriodComparisonValue {
        switch self {
        case let .money(money): .money(money.isNegative ? -money : money)
        case let .duration(seconds): .duration(abs(seconds))
        case let .count(count): .count(abs(count))
        case let .distance(metres): .distance(metres: abs(metres))
        }
    }

    /// The figure as the screen writes it, in the app's one format for its kind.
    func statement(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case let .money(money): money.formatted(locale: locale)
        case let .duration(seconds): DurationText.short(seconds)
        case let .count(count): "\(count)"
        case let .distance(metres): RouteDistance.formattedMiles(metres: metres, locale: locale)
        }
    }

    /// The figure as VoiceOver hears it: wide units, same rounding.
    func spokenStatement(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case let .money(money): money.formatted(locale: locale)
        case let .duration(seconds): DurationText.spoken(seconds)
        case let .count(count): "\(count)"
        case let .distance(metres): RouteDistance.formattedMiles(metres: metres, width: .wide, locale: locale)
        }
    }
}

/// What one side of a compared figure was derived from.
///
/// A comparison is where differing coverage does its worst work: `$310` against
/// `$284.50` is a fall of `$25.50` if both periods recorded every shift, and is
/// no statement at all if one of them recorded three shifts out of six. So both
/// sides' bases travel with every entry, are printed whether or not they
/// differ, and decide on their own whether a percentage may be stated.
nonisolated enum PeriodComparisonBasis: Equatable, Sendable {
    /// Records that contributed, out of the records that could have.
    case coverage(MetricCoverage)

    /// The route coverage of a period, which is missing in two different ways.
    case routes(PeriodRouteCoverage)

    /// A count of the records themselves, with no denominator anywhere:
    /// recorded expenses. Completeness is unknowable, never complete.
    case recordCount(Int)

    /// The figure **is** the count of its records, so nothing within it is
    /// short. What the driver never recorded is not in it at all, which is what
    /// "more recorded" says rather than "more".
    case exactCount

    /// Whether every record this figure could have used is in it.
    ///
    /// The gate on a percentage. A ratio between two subtotals of unknown
    /// completeness is a ratio of the driver's bookkeeping as much as of their
    /// work, and there is no way to say by how much.
    var isComplete: Bool {
        switch self {
        case let .coverage(coverage): coverage.isComplete
        // A partial route contributes real distance that is nonetheless known
        // to be short, so a period holding one is never a complete basis even
        // when every shift measured something.
        case let .routes(routes): routes.measuredCoverage.isComplete && routes.partialShiftCount == 0
        case .recordCount: false
        case .exactCount: true
        }
    }

    /// The counts as the screen writes them, or `nil` when the figure is its own
    /// count and there is nothing to qualify.
    func statement(noun: String = "shift", pluralNoun: String? = nil) -> String? {
        switch self {
        case let .coverage(coverage): coverage.statement(noun: noun, pluralNoun: pluralNoun)
        case let .routes(routes): routes.statement
        case let .recordCount(count): count == 1 ? "1 recorded expense" : "\(count) recorded expenses"
        case .exactCount: nil
        }
    }
}

/// Why a comparison is stating no percentage change.
///
/// Stated rather than left blank. A missing percentage with no reason beside it
/// reads as an omission; the reason is usually the most informative thing on the
/// row, because it says which of the two periods the app cannot fully see.
nonisolated enum PeriodPercentageRefusal: String, Equatable, Sendable, Hashable {
    /// One of the two periods has no figure at all. There is no difference
    /// either: a missing value is not a zero, so nothing is subtracted from it.
    case valueMissing

    /// The previous figure is zero. Division by it has no answer, and "infinite
    /// growth" is not one.
    case previousIsZero

    /// The current period has not finished. A part of a period against the whole
    /// of one is a ratio of two different amounts of time.
    case currentPeriodInProgress

    /// One of the two figures does not cover all of its records, or has no
    /// denominator at all.
    case completenessUnknown

    /// The change rounds to nothing at this scale. The difference itself is
    /// still stated.
    case tooSmallToState

    /// Whether the reason belongs on the figure's own row.
    ///
    /// Three of these are about one figure: a side that is missing, a previous
    /// value of zero, a change too small to state. The other two are about the
    /// **pair of periods** — one of them has not finished, or the records behind
    /// them are short — and are said once for the whole comparison rather than
    /// repeated down every row of it, where the repetition would bury the
    /// reasons that differ.
    var isStatedOnTheRow: Bool {
        switch self {
        case .valueMissing, .previousIsZero, .tooSmallToState: true
        case .currentPeriodInProgress, .completenessUnknown: false
        }
    }
}

/// One figure, in both periods, with what each side was derived from.
///
/// The difference is present only when **both** sides have a figure. A missing
/// value is never read as zero here, exactly as it is not read as zero inside a
/// period: a week whose shifts carry no amount has not earned nothing, and
/// subtracting last week's total from it would manufacture a fall.
nonisolated struct PeriodComparisonEntry: Equatable, Sendable, Identifiable {
    let metric: PeriodComparisonMetric

    /// The selected period's figure, or `nil` when it has none.
    let current: PeriodComparisonValue?

    /// The preceding period's figure, or `nil` when it has none.
    let previous: PeriodComparisonValue?

    let currentBasis: PeriodComparisonBasis
    let previousBasis: PeriodComparisonBasis

    /// `current − previous`, or `nil` when either side is missing.
    let difference: PeriodComparisonValue?

    /// Which way the figure moved, or `nil` when there is no difference to have
    /// a direction.
    let direction: PeriodComparisonDirection?

    /// The change as a whole percentage of the previous figure, signed, or `nil`
    /// when one may not be stated.
    let percentChange: Int?

    /// Why there is no percentage. Exactly one of this and ``percentChange`` is
    /// non-`nil`.
    let percentageRefusal: PeriodPercentageRefusal?

    var id: String { metric.id }

    /// Whether either period holds this figure at all.
    var hasAnyValue: Bool { current != nil || previous != nil }

    /// Whether the two sides rest on records of different completeness.
    ///
    /// The case the section footer has to name: a figure can move entirely
    /// because one of the two periods is better filled in.
    var basesDiffer: Bool { currentBasis != previousBasis }
}

/// A period beside the equivalent period immediately before it.
///
/// ## What it is, and the one thing it is not
///
/// Two ``PeriodMetrics`` results and the differences between their figures. It
/// runs no aggregation of its own: both sides come from
/// ``PeriodMetricsCalculator`` by the same path, over the same rules, so a
/// month's figure here is its own shifts' amounts over its own shifts' hours and
/// never an average of the weeks inside it.
///
/// It is **not a judgement, a goal, a score, a rank, a trend or a forecast**.
/// Nothing here says a period was good, nothing extrapolates a period that has
/// not finished, and nothing draws a line through more than two points. Two
/// periods and their differences is the whole of it.
///
/// ## What can stop a figure being compared
///
/// - **A missing figure on either side.** No difference, no percentage.
/// - **A previous figure of zero.** No percentage; the difference stands.
/// - **A current period still in progress.** Part of a period against the whole
///   of one, so no percentage.
/// - **Coverage short of its records on either side**, including a period whose
///   routes are partial. No percentage; the counts are printed anyway.
///
/// The differences in period length and in coverage are **stated rather than
/// corrected**. Nothing here scales February up to March's length or a
/// three-shift week up to a six-shift one: a scaled figure is an estimate, and
/// this app does not present estimates as records.
nonisolated struct PeriodComparison: Equatable, Sendable {
    /// The period the driver selected.
    let current: PeriodMetrics

    /// The equivalent period immediately before it, by
    /// ``ReportingPeriod/precedingEquivalent(using:)``.
    let previous: PeriodMetrics

    /// Whether the selected period is the one the driver is living in, and so
    /// has not finished.
    let isCurrentPeriodInProgress: Bool

    /// How many calendar days each period covers, when the calendar could say.
    let currentDayCount: Int?
    let previousDayCount: Int?

    /// The compared figures, in reading order, holding only those at least one
    /// of the two periods has.
    let entries: [PeriodComparisonEntry]

    /// The entry for one metric, when the comparison holds it.
    func entry(_ metric: PeriodComparisonMetric) -> PeriodComparisonEntry? {
        entries.first { $0.metric == metric }
    }

    /// Whether the previous period recorded anything at all.
    var previousHasRecords: Bool { previous.hasAnyRecords }

    /// Whether the two periods cover different numbers of calendar days.
    ///
    /// True for most adjacent month pairs, and false for every custom range,
    /// which is compared against the same number of days by construction.
    var lengthsDiffer: Bool {
        guard let currentDayCount, let previousDayCount else { return false }
        return currentDayCount != previousDayCount
    }

    /// Whether any compared figure rests on records of different completeness.
    var coverageDiffers: Bool { entries.contains(where: \.basesDiffer) }
}

// MARK: Wording

/// The words a comparison is written and spoken in.
///
/// Kept beside the arithmetic for the reason ``PeriodMetrics``'s wording is:
/// the failure mode of a comparison is a **claim**, not a crash. "Down 12% on
/// last week" over two differently recorded weeks is wrong in a way no
/// arithmetic test would catch, so what may be said is decided here, once, and
/// asserted by tests rather than assembled in a view body.
nonisolated extension PeriodComparisonMetric {
    /// What a row says when a period holds no figure for it.
    ///
    /// The same phrase the figure's own row on the summary uses, so a driver
    /// reading both does not meet two different words for one absence.
    var absentStatement: String {
        switch self {
        case .rate: "Not available"
        case .recordedMileage: "No route measured"
        default: "Not recorded"
        }
    }
}

nonisolated extension PeriodComparisonEntry {
    /// The two figures, in order: `"$284.50 compared with $310.00"`.
    ///
    /// A missing figure is written as the absence it is and never as a zero, on
    /// either side.
    func valuesStatement(locale: Locale = .autoupdatingCurrent) -> String {
        let currentText = current?.statement(locale: locale) ?? metric.absentStatement
        let previousText = previous?.statement(locale: locale) ?? metric.absentStatement
        return "\(currentText) compared with \(previousText)"
    }

    /// The difference, in the words the metric's nature allows:
    /// `"$25.50 less recorded"`, `"$0.32 higher"`, `"No change"`.
    ///
    /// `nil` when a side is missing. Nothing is subtracted from an absence.
    func changeStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        guard let difference, let direction else { return nil }
        guard direction != .unchanged else { return "No change" }
        return "\(difference.magnitudeValue.statement(locale: locale)) \(metric.changeWord(direction))"
    }

    /// The change as a percentage of the previous figure: `"8% less"`.
    ///
    /// `nil` whenever ``percentageRefusal`` says one may not be stated.
    func percentStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        guard let percentChange, let direction else { return nil }
        let fraction = Double(abs(percentChange)) / 100
        return "\(fraction.formatted(.percent.locale(locale))) \(metric.percentageWord(direction))"
    }

    /// Why no percentage is shown, in the driver's own period noun.
    func refusalStatement(noun: String) -> String? {
        switch percentageRefusal {
        case nil:
            return nil
        case .valueMissing:
            return """
                One of the two \(noun)s has no figure here, so nothing is subtracted from it and no \
                percentage is shown.
                """
        case .previousIsZero:
            return """
                The previous \(noun)'s figure is zero, so there is nothing for a percentage to be a \
                percentage of.
                """
        case .currentPeriodInProgress:
            return """
                This \(noun) is still in progress, so a percentage against a complete \(noun) would \
                compare different amounts of time.
                """
        case .completenessUnknown:
            return """
                These figures do not cover all of their records, so a percentage between them would \
                be a percentage of what was entered rather than of the \(noun).
                """
        case .tooSmallToState:
            // Nothing to say about a figure that did not move: "no change" is
            // already on the row, and calling it a change under one percent
            // would argue with it.
            return direction == .unchanged ? nil : "The change is under 1%."
        }
    }

    /// What both sides were derived from: `"3 of 4 shifts, compared with 4 of 4
    /// shifts"`, or `nil` when the figure is its own count on both sides.
    ///
    /// Printed whether or not the two agree, for the reason
    /// ``MetricCoverage/statement(noun:pluralNoun:)`` is printed when coverage is
    /// complete: the shape stays the same wherever a driver reads it, and a
    /// fully recorded pair is stated rather than being the case where the
    /// caveat quietly disappears.
    var basisStatement: String? {
        let noun = metric.basisNoun
        let plural = metric.basisPluralNoun
        guard let currentText = currentBasis.statement(noun: noun, pluralNoun: plural) else { return nil }
        guard let previousText = previousBasis.statement(noun: noun, pluralNoun: plural) else {
            return currentText
        }
        return "\(currentText), compared with \(previousText)"
    }

    /// The whole row as VoiceOver hears it, which cannot lean on the row above
    /// it or on the section heading.
    func spokenStatement(noun: String, locale: Locale = .autoupdatingCurrent) -> String {
        var parts = [
            "\(metric.spokenTitle), \(current?.spokenStatement(locale: locale) ?? metric.absentStatement), "
                + "compared with \(previous?.spokenStatement(locale: locale) ?? metric.absentStatement)"
        ]
        if let difference, let direction {
            parts.append(
                direction == .unchanged
                    ? "no change"
                    : "\(difference.magnitudeValue.spokenStatement(locale: locale)) \(metric.changeWord(direction))"
            )
        }
        if let percent = percentStatement(locale: locale) {
            parts.append(percent)
        }
        if let basisStatement {
            parts.append("based on \(basisStatement)")
        }
        var statement = parts.joined(separator: ", ") + "."
        if let refusal = refusalStatement(noun: noun) {
            statement += " \(refusal)"
        }
        return statement
    }
}

nonisolated extension PeriodComparison {
    /// The noun the compared spans are called by, in the driver's own terms.
    var periodNoun: String { current.period.unit.stepNoun }

    /// What the section is called: `"Compared with the previous week"`.
    var title: String { "Compared with the previous \(periodNoun)" }

    /// Which span the second figure in every row came from:
    /// `"Yesterday, Saturday, Sep 6"`.
    ///
    /// Named as well as dated, and written with the period's **own** calendar
    /// and time zone by ``ReportingPeriod``'s wording, so the days named here
    /// are the days the figures were selected from.
    func previousPeriodStatement(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let period = previous.period
        let name = period.title(asOf: now, calendar: calendar, locale: locale)
        let dates = period.rangeStatement(calendar: calendar, locale: locale)
        return name == dates ? name : "\(name), \(dates)"
    }

    /// The spoken form of the same, which says what the second span *is* before
    /// reading its dates.
    func spokenPreviousPeriodStatement(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "Compared with the previous \(periodNoun), \(previousPeriodStatement(asOf: now, calendar: calendar, locale: locale))."
    }

    /// That the two spans are different lengths, when they are:
    /// `"This month covers 31 days; the previous month covers 30."`
    ///
    /// Stated rather than corrected. Scaling one month to the other's length
    /// would replace a record with an estimate, and every figure on this screen
    /// is a record.
    var lengthStatement: String? {
        guard lengthsDiffer, let currentDayCount, let previousDayCount else { return nil }
        return "This \(periodNoun) covers \(currentDayCount) days; the previous \(periodNoun) covers "
            + "\(previousDayCount)."
    }

    /// That the selected span has not finished, when it has not.
    var inProgressStatement: String? {
        guard isCurrentPeriodInProgress else { return nil }
        return """
            This \(periodNoun) is still in progress and the previous one is complete, so the two \
            cover different amounts of time. No percentage change is shown while that is true.
            """
    }

    /// That the previous span holds nothing, when it holds nothing.
    var previousEmptyStatement: String? {
        guard !previousHasRecords else { return nil }
        return "No completed shift and no recorded expense in the previous \(periodNoun)."
    }

    /// That the two spans are not recorded to the same extent, when they are
    /// not.
    var coverageStatement: String? {
        guard coverageDiffers else { return nil }
        return """
            The two \(periodNoun)s are not recorded to the same extent. Each figure carries the \
            records behind both sides, and a figure can move because one \(periodNoun) is more \
            completely filled in than the other.
            """
    }

    /// The sentence that has to sit under the whole section.
    ///
    /// The one claim this feature could make and must not: that a difference
    /// between two sets of records is a difference in how well the driver
    /// worked.
    var cautionStatement: String {
        """
        These are the differences between what you recorded in the two \(periodNoun)s. More recorded \
        is not better and less recorded is not worse: DashPilot holds the records you entered, not \
        the work you did. Nothing here is a goal, a target, a trend or a prediction.
        """
    }
}
