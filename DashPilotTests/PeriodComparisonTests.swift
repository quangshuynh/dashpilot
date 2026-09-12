import Foundation
import Testing
@testable import DashPilot

/// A period beside the equivalent period before it, and the far longer list of
/// things that comparison refuses to say.
///
/// Both sides of every comparison here are built by the real
/// ``PeriodMetricsCalculator`` from plain shift and expense records, so a test
/// that passes proves the comparison over the figures the summary itself shows
/// rather than over numbers a fixture invented at the end of the pipeline.
@Suite("Period comparison")
struct PeriodComparisonTests {
    private let calculator = PeriodMetricsCalculator()
    private let comparisons = PeriodComparisonCalculator()

    /// A calendar with everything that changes an answer pinned.
    private func calendar(timeZone: String = "UTC", firstWeekday: Int = 1) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        in calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private static let metresPerMile = 1609.344

    /// One completed shift, reduced to the facts a period aggregates.
    private func shift(
        at start: Date,
        hours: Double? = 4,
        earnings: Money? = nil,
        miles: Double? = nil,
        gapCount: Int = 0,
        activeHours: Double? = nil,
        delivered: Int = 0
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: start,
            workingDuration: hours.map { $0 * 3600 },
            grossEarnings: earnings,
            recordedDistance: miles.map { miles in
                RouteDistance(
                    metres: miles * Self.metresPerMile,
                    segmentCount: 1,
                    gapCount: gapCount,
                    usableSampleCount: 40,
                    usesInferredContinuity: false
                )
            } ?? .none,
            deliveryActiveTime: activeHours.map { hours in
                DeliveryActiveTime(
                    duration: hours * 3600,
                    sourceIntervalCount: 1,
                    countedIntervalCount: 1,
                    mergedIntervalCount: 1,
                    unfinishedIntervalCount: 0,
                    malformedIntervalCount: 0
                )
            } ?? .none,
            deliverySummary: DeliverySummary(completed: delivered, cancelled: 0)
        )
    }

    private func metrics(
        _ records: [PeriodShiftRecord],
        expenses: [ExpenseRecord] = [],
        in period: ReportingPeriod
    ) -> PeriodMetrics {
        calculator.metrics(of: records, expenses: expenses, in: period)
    }

    /// The comparison of two adjacent periods, built the way the screen builds
    /// one: each side through the metrics calculator, then the pair.
    private func comparison(
        current: [PeriodShiftRecord],
        currentExpenses: [ExpenseRecord] = [],
        previous: [PeriodShiftRecord],
        previousExpenses: [ExpenseRecord] = [],
        of period: ReportingPeriod,
        asOf now: Date,
        calendar: Calendar
    ) throws -> PeriodComparison {
        let preceding = try #require(period.precedingEquivalent(using: calendar))
        return try #require(
            comparisons.comparison(
                of: metrics(current, expenses: currentExpenses, in: period),
                with: metrics(previous, expenses: previousExpenses, in: preceding),
                asOf: now,
                calendar: calendar
            )
        )
    }

    // MARK: The preceding equivalent period

    /// A day, a week and a month are compared with the calendar unit before
    /// them, which is the same span the back chevron steps to.
    @Test("A calendar period is compared with the one the calendar puts before it")
    func calendarPeriodsAreComparedWithTheirCalendarPredecessor() throws {
        let calendar = try calendar()
        let moment = try date(2026, 6, 17, 14, in: calendar)

        for unit in ReportingPeriodUnit.calendarUnits {
            let period = try #require(ReportingPeriod(unit: unit, containing: moment, calendar: calendar))
            #expect(period.precedingEquivalent(using: calendar) == period.previous(using: calendar))
            let preceding = try #require(period.precedingEquivalent(using: calendar))
            #expect(preceding.end == period.start, "The preceding period ends exactly where this one begins")
            #expect(preceding.unit == unit)
        }
    }

    /// February is not shortened to fit March, and March is not stretched to fit
    /// April. The lengths differ, and the comparison says so.
    @Test("A month is compared with the whole of the month before it, whatever its length")
    func monthsKeepTheirOwnLengths() throws {
        let calendar = try calendar()
        let march = try #require(
            ReportingPeriod(unit: .month, containing: try date(2026, 3, 10, in: calendar), calendar: calendar)
        )
        let february = try #require(march.precedingEquivalent(using: calendar))

        #expect(february.start == (try date(2026, 2, 1, in: calendar)))
        #expect(february.end == march.start)
        #expect(march.dayCount(using: calendar) == 31)
        #expect(february.dayCount(using: calendar) == 28)
    }

    /// A chosen range has no *neighbour to step to* and still has an equivalent
    /// span to be compared with: the same number of calendar days, immediately
    /// before it.
    @Test("A custom range is compared with the same number of days before it")
    func customRangesAreComparedWithAnEqualLengthRangeBeforeThem() throws {
        let calendar = try calendar()
        let range = try #require(
            ReportingPeriod(
                from: try date(2026, 9, 8, in: calendar),
                through: try date(2026, 9, 14, in: calendar),
                calendar: calendar
            )
        )
        let preceding = try #require(range.precedingEquivalent(using: calendar))

        #expect(preceding.unit == .custom)
        #expect(preceding.start == (try date(2026, 9, 1, in: calendar)))
        #expect(preceding.end == range.start)
        #expect(preceding.dayCount(using: calendar) == range.dayCount(using: calendar))
        #expect(preceding.dayCount(using: calendar) == 7)
    }

    /// One day is a range like any other.
    @Test("A one-day range is compared with the day before it")
    func aOneDayRangeIsComparedWithTheDayBefore() throws {
        let calendar = try calendar()
        let day = try date(2026, 9, 8, in: calendar)
        let range = try #require(ReportingPeriod(from: day, through: day, calendar: calendar))
        let preceding = try #require(range.precedingEquivalent(using: calendar))

        #expect(preceding.start == (try date(2026, 9, 7, in: calendar)))
        #expect(preceding.end == range.start)
        #expect(preceding.dayCount(using: calendar) == 1)
    }

    /// The step is calendar-day arithmetic, so a range holding a 23-hour day is
    /// still compared with seven whole days rather than with seven times 86,400
    /// seconds.
    @Test("A range across a daylight saving change keeps whole days on both sides")
    func rangesAcrossADaylightSavingChangeKeepWholeDays() throws {
        let calendar = try calendar(timeZone: "America/New_York")
        // 8 March 2026 is a 23-hour day in this zone.
        let range = try #require(
            ReportingPeriod(
                from: try date(2026, 3, 6, in: calendar),
                through: try date(2026, 3, 12, in: calendar),
                calendar: calendar
            )
        )
        let preceding = try #require(range.precedingEquivalent(using: calendar))

        #expect(range.dayCount(using: calendar) == 7)
        #expect(preceding.dayCount(using: calendar) == 7)
        #expect(preceding.end == range.start)
        #expect(preceding.end.timeIntervalSince(preceding.start) != range.end.timeIntervalSince(range.start))
    }

    /// Comparing a range does not turn it into a period the driver can step
    /// through: the selection rule is untouched.
    @Test("A custom range still has no previous or next selection")
    func steppingACustomRangeIsStillRefused() throws {
        let calendar = try calendar()
        let range = try #require(
            ReportingPeriod(
                from: try date(2026, 9, 8, in: calendar),
                through: try date(2026, 9, 14, in: calendar),
                calendar: calendar
            )
        )

        #expect(range.previous(using: calendar) == nil)
        #expect(range.next(using: calendar) == nil)
        #expect(range.precedingEquivalent(using: calendar) != nil)
    }

    // MARK: Comparing results, not averages

    /// The comparison is between two period results. Neither side is an average
    /// of the smaller periods inside it, and the difference is the difference of
    /// the period rates.
    @Test("Period rates are compared directly, never as averages of their shifts")
    func periodRatesAreComparedDirectly() throws {
        let calendar = try calendar()
        let march = try #require(
            ReportingPeriod(unit: .month, containing: try date(2026, 3, 10, in: calendar), calendar: calendar)
        )
        let now = try date(2026, 4, 2, in: calendar)

        // March: $200 over 10 hours is $20.00 per hour. The mean of the two
        // shifts' own rates would be $55.56.
        let current = [
            shift(at: try date(2026, 3, 3, in: calendar), hours: 1, earnings: try money("100.00")),
            shift(at: try date(2026, 3, 4, in: calendar), hours: 9, earnings: try money("100.00"))
        ]
        // February: $100 over 10 hours is $10.00 per hour. The mean of its
        // shifts' rates would be $27.78.
        let previous = [
            shift(at: try date(2026, 2, 3, in: calendar), hours: 1, earnings: try money("50.00")),
            shift(at: try date(2026, 2, 4, in: calendar), hours: 9, earnings: try money("50.00"))
        ]

        let comparison = try comparison(
            current: current,
            previous: previous,
            of: march,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.rate(.perWorkingHour)))

        #expect(entry.current == .money(try money("20.00")))
        #expect(entry.previous == .money(try money("10.00")))
        #expect(entry.difference == .money(try money("10.00")))
        #expect(entry.direction == .increase)
        #expect(entry.percentChange == 100)
        // The averaged answer, written down so a regression to it is visible.
        #expect(entry.difference != .money(try money("27.78")))
    }

    /// Each rate keeps the paired subset the period derived it from, on both
    /// sides.
    @Test("A compared rate carries the paired subset each period used")
    func comparedRatesCarryTheirPairedSubsets() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [
                shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("60.00"), miles: 20),
                shift(at: try date(2026, 6, 17, 15, in: calendar), earnings: try money("40.00"))
            ],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("50.00"), miles: 25)],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.rate(.perRecordedMile)))
        let basis = try #require(entry.basisStatement)

        #expect(basis.contains("1 of 2 shifts with both earnings and a measurable route"))
        #expect(basis.contains("1 of 1 shift with both earnings and a measurable route"))
        #expect(entry.current == .money(try money("3.00")))
        #expect(entry.previous == .money(try money("2.00")))
    }

    // MARK: Missing data

    /// A period with no recorded amount has not earned nothing, so nothing is
    /// subtracted from it and nothing is subtracted from the period before it.
    @Test("A missing figure is never compared as a zero")
    func aMissingFigureIsNeverComparedAsZero() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("86.25"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.current == .money(try money("86.25")))
        #expect(entry.previous == nil)
        #expect(entry.difference == nil)
        #expect(entry.direction == nil)
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .valueMissing)
        #expect(entry.changeStatement() == nil)
        #expect(entry.valuesStatement(locale: Locale(identifier: "en_US")).contains("Not recorded"))
    }

    /// A route that measured nothing contributes no distance, and a period
    /// without one is compared as having no mileage rather than zero miles.
    @Test("A period whose routes measured nothing has no mileage to compare")
    func unmeasuredMileageIsAbsentRatherThanZero() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), miles: 12)],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedMileage))

        #expect(entry.previous == nil)
        #expect(entry.difference == nil)
        #expect(entry.percentageRefusal == .valueMissing)
        #expect(entry.valuesStatement().contains("No route measured"))
    }

    /// A figure neither period holds is not printed as two absences.
    @Test("A figure absent from both periods is left out")
    func figuresAbsentFromBothPeriodsAreLeftOut() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar))],
            of: day,
            asOf: now,
            calendar: calendar
        )

        #expect(comparison.entry(.recordedMileage) == nil)
        #expect(comparison.entry(.recordedGrossEarnings) == nil)
        #expect(comparison.entry(.recordedExpenses) == nil)
        // The counts are always there: a count of records is never missing.
        #expect(comparison.entry(.completedShifts) != nil)
        #expect(comparison.entry(.workingTime) != nil)
    }

    // MARK: Percentages

    /// Both sides complete, the period finished: the one case a percentage is
    /// stated.
    @Test("A percentage is stated when both sides are complete and the period has finished")
    func aPercentageIsStatedWhenBothSidesAreComplete() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("64.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.difference == .money(try money("16.00")))
        #expect(entry.percentChange == 25)
        #expect(entry.percentageRefusal == nil)
        #expect(entry.changeStatement(locale: Locale(identifier: "en_US")) == "$16.00 more recorded")
        #expect(entry.percentStatement(locale: Locale(identifier: "en_US")) == "25% more")
    }

    /// Zero is a recorded amount, and it is not a denominator.
    @Test("No percentage when the previous figure is a recorded zero")
    func noPercentageWhenThePreviousFigureIsZero() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("42.00"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: .zero)],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        // The difference is still a fact, and is still stated.
        #expect(entry.difference == .money(try money("42.00")))
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .previousIsZero)
        #expect(entry.refusalStatement(noun: "day")?.contains("percentage of") == true)
    }

    /// Part of a period against the whole of one is not a percentage of
    /// anything.
    @Test("No percentage while the selected period is still in progress")
    func noPercentageWhileTheSelectedPeriodIsInProgress() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 17, 15, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("64.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(comparison.isCurrentPeriodInProgress)
        #expect(entry.difference == .money(try money("16.00")))
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .currentPeriodInProgress)
        #expect(comparison.inProgressStatement?.contains("still in progress") == true)
    }

    /// A ratio between two subtotals of unknown completeness is a ratio of the
    /// bookkeeping as much as of the work.
    @Test("No percentage when either side is short of its records")
    func noPercentageWhenCoverageIsShort() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [
                shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00")),
                shift(at: try date(2026, 6, 17, 15, in: calendar))
            ],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("64.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .completenessUnknown)
        #expect(entry.basesDiffer)
        #expect(comparison.coverageDiffers)
        #expect(try #require(entry.basisStatement).contains("1 of 2 shifts, compared with 1 of 1 shift"))
    }

    /// A partial route is real distance that is known to be short, so a period
    /// holding one is never a complete basis for a ratio.
    @Test("A partial route withholds a percentage and stays visible")
    func partialRoutesWithholdAPercentage() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), miles: 20, gapCount: 2)],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), miles: 10)],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedMileage))

        #expect(entry.direction == .increase)
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .completenessUnknown)
        #expect(try #require(entry.basisStatement).contains("1 partial"))
    }

    /// Nothing knows how many costs went unrecorded, so no expense figure can
    /// ever be a complete basis.
    @Test("Recorded expenses never carry a percentage")
    func recordedExpensesNeverCarryAPercentage() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar))],
            currentExpenses: [
                ExpenseRecord(
                    occurredAt: try date(2026, 6, 17, 10, in: calendar),
                    amount: try money("40.00"),
                    category: .fuel
                )
            ],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar))],
            previousExpenses: [
                ExpenseRecord(
                    occurredAt: try date(2026, 6, 16, 10, in: calendar),
                    amount: try money("20.00"),
                    category: .fuel
                )
            ],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedExpenses))

        #expect(entry.difference == .money(try money("20.00")))
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .completenessUnknown)
        #expect(try #require(entry.basisStatement).contains("1 recorded expense, compared with 1 recorded expense"))
    }

    /// A change that rounds to nothing is refused rather than printed as `0%`
    /// beside a difference that is not zero.
    @Test("A change under one percent is stated as a difference and not as a percentage")
    func changesUnderOnePercentAreNotPrintedAsAPercentage() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("100.10"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("100.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.difference == .money(try money("0.10")))
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .tooSmallToState)
    }

    /// The ratio is taken from the exact recorded amounts, not from a binary
    /// approximation of them.
    @Test("A money percentage is taken from the exact decimal amounts")
    func moneyPercentagesUseExactAmounts() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("0.30"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("0.10"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.difference == .money(try money("0.20")))
        #expect(entry.percentChange == 200)
    }

    /// An unchanged figure says so, and is not dressed as a movement.
    @Test("An unchanged figure is stated as no change")
    func unchangedFiguresAreStatedAsSuch() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("80.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(entry.direction == .unchanged)
        #expect(entry.changeStatement() == "No change")
        #expect(entry.percentChange == nil)
        #expect(entry.percentageRefusal == .tooSmallToState)
        // Nothing argues with "No change" by calling it a change under 1%.
        #expect(entry.refusalStatement(noun: "day") == nil)
    }

    // MARK: What is compared, and what is refused

    /// A comparison is between neighbours. Anything else is refused rather than
    /// answered.
    @Test("Two periods that are not neighbours are refused")
    func periodsThatAreNotNeighboursAreRefused() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let weekBefore = try #require(
            ReportingPeriod(unit: .week, containing: try date(2026, 6, 10, in: calendar), calendar: calendar)
        )
        let twoDaysBefore = try #require(
            ReportingPeriod(unit: .day, containing: try date(2026, 6, 15, in: calendar), calendar: calendar)
        )
        let now = try date(2026, 6, 18, in: calendar)

        #expect(
            comparisons.comparison(
                of: metrics([], in: day),
                with: metrics([], in: weekBefore),
                asOf: now,
                calendar: calendar
            ) == nil
        )
        #expect(
            comparisons.comparison(
                of: metrics([], in: day),
                with: metrics([], in: twoDaysBefore),
                asOf: now,
                calendar: calendar
            ) == nil
        )
        #expect(
            comparisons.comparison(
                of: metrics([], in: day),
                with: metrics([], in: day),
                asOf: now,
                calendar: calendar
            ) == nil
        )
    }

    /// The closed list of compared figures, and the ones deliberately outside
    /// it.
    @Test("Net after recorded expenses and the median wait are not compared")
    func derivedFiguresThatCannotBeComparedAreNotCompared() {
        let ids = PeriodComparisonMetric.allMetrics.map(\.id)

        #expect(!ids.contains { $0.lowercased().contains("net") })
        #expect(!ids.contains { $0.lowercased().contains("wait") })
        #expect(!ids.contains { $0.lowercased().contains("median") })
        #expect(!ids.contains { $0.lowercased().contains("place") })
        #expect(ids.count == Set(ids).count, "Each figure appears once")
    }

    /// Two spans of different lengths are stated as such rather than scaled to
    /// each other.
    @Test("Differing period lengths are stated, never corrected")
    func differingLengthsAreStatedRatherThanScaled() throws {
        let calendar = try calendar()
        let march = try #require(
            ReportingPeriod(unit: .month, containing: try date(2026, 3, 10, in: calendar), calendar: calendar)
        )
        let now = try date(2026, 4, 2, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 3, 3, in: calendar), earnings: try money("310.00"))],
            previous: [shift(at: try date(2026, 2, 3, in: calendar), earnings: try money("280.00"))],
            of: march,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))
        let statement = try #require(comparison.lengthStatement)

        #expect(comparison.lengthsDiffer)
        #expect(statement.contains("31"))
        #expect(statement.contains("28"))
        // The raw difference, not one adjusted for the three extra days.
        #expect(entry.difference == .money(try money("30.00")))
    }

    /// A period with nothing in it before it is said to hold nothing, and the
    /// counts that are always present are still compared.
    @Test("An empty previous period is stated, and counts are still compared")
    func anEmptyPreviousPeriodIsStated() throws {
        let calendar = try calendar()
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [
                shift(at: try date(2026, 6, 17, 9, in: calendar), delivered: 3),
                shift(at: try date(2026, 6, 17, 15, in: calendar), delivered: 1)
            ],
            previous: [],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let shifts = try #require(comparison.entry(.completedShifts))
        let delivered = try #require(comparison.entry(.deliveriesCompleted))

        #expect(!comparison.previousHasRecords)
        #expect(comparison.previousEmptyStatement?.contains("previous day") == true)
        #expect(shifts.current == .count(2))
        #expect(shifts.previous == .count(0))
        #expect(shifts.changeStatement() == "2 more recorded")
        #expect(shifts.percentageRefusal == .previousIsZero)
        #expect(delivered.difference == .count(4))
    }

    // MARK: Wording

    /// More recorded is not better, and less recorded is not worse. Nothing in
    /// this feature is allowed to say otherwise, and the only line permitted to
    /// use those words at all is the one that refuses them.
    @Test("Nothing in a comparison is called better, worse or a trend")
    func nothingIsCalledBetterOrWorse() throws {
        let calendar = try calendar()
        let locale = Locale(identifier: "en_US")
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00"), miles: 20, activeHours: 2, delivered: 4)],
            currentExpenses: [
                ExpenseRecord(
                    occurredAt: try date(2026, 6, 17, 10, in: calendar),
                    amount: try money("12.00"),
                    category: .fuel
                )
            ],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("64.00"), miles: 30, activeHours: 3, delivered: 6)],
            of: day,
            asOf: now,
            calendar: calendar
        )

        // The caution sentence is where those words are allowed, and only in a
        // refusal: it is the one line that has to say a difference is not a
        // judgement, which it cannot do without naming the judgement.
        #expect(comparison.cautionStatement.contains("More recorded is not better"))
        #expect(comparison.cautionStatement.contains("less recorded is not worse"))
        #expect(comparison.cautionStatement.contains("Nothing here is a goal, a target, a trend or a prediction"))

        var sentences = [
            comparison.title,
            comparison.previousPeriodStatement(asOf: now, calendar: calendar, locale: locale),
            comparison.spokenPreviousPeriodStatement(asOf: now, calendar: calendar, locale: locale),
            comparison.coverageStatement,
            comparison.lengthStatement,
            comparison.inProgressStatement,
            comparison.previousEmptyStatement
        ].compactMap { $0 }

        for entry in comparison.entries {
            sentences.append(entry.valuesStatement(locale: locale))
            sentences.append(entry.spokenStatement(noun: comparison.periodNoun, locale: locale))
            sentences.append(contentsOf: [
                entry.changeStatement(locale: locale),
                entry.percentStatement(locale: locale),
                entry.basisStatement,
                entry.refusalStatement(noun: comparison.periodNoun)
            ].compactMap { $0 })
        }

        let forbidden = [
            "better", "worse", "improv", "declin", "beat", "goal", "target", "trend",
            "forecast", "predict", "on track", "streak", "rank", "score", "progress toward",
            "profit", "take-home", "deductible"
        ]
        for sentence in sentences {
            let text = sentence.lowercased()
            for word in forbidden {
                #expect(!text.contains(word), "\"\(sentence)\" must not say \"\(word)\"")
            }
        }
        #expect(sentences.contains { $0.contains("less recorded") })
        #expect(sentences.contains { $0.contains("more recorded") })
    }

    /// A total moves by "more" or "less recorded"; a rate moves by "higher" or
    /// "lower". Neither claims anything about the driving.
    @Test("A total and a rate are described in different words")
    func totalsAndRatesUseDifferentWords() throws {
        let calendar = try calendar()
        let locale = Locale(identifier: "en_US")
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar), hours: 4, earnings: try money("80.00"))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), hours: 4, earnings: try money("40.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let total = try #require(comparison.entry(.recordedGrossEarnings))
        let rate = try #require(comparison.entry(.rate(.perWorkingHour)))

        #expect(total.changeStatement(locale: locale) == "$40.00 more recorded")
        #expect(rate.changeStatement(locale: locale) == "$10.00 higher")
        #expect(total.percentStatement(locale: locale) == "100% more")
        #expect(rate.percentStatement(locale: locale) == "100% higher")
    }

    /// VoiceOver hears both figures, the change and the records behind both
    /// sides, without having to infer any of them from a nearby row.
    @Test("A spoken row carries both figures and the records behind them")
    func spokenRowsCarryBothSidesAndTheirRecords() throws {
        let calendar = try calendar()
        let locale = Locale(identifier: "en_US")
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 18, 9, in: calendar)

        let comparison = try comparison(
            current: [
                shift(at: try date(2026, 6, 17, 9, in: calendar), earnings: try money("80.00")),
                shift(at: try date(2026, 6, 17, 15, in: calendar))
            ],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar), earnings: try money("64.00"))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let spoken = try #require(comparison.entry(.recordedGrossEarnings)).spokenStatement(
            noun: comparison.periodNoun,
            locale: locale
        )

        #expect(spoken.contains("recorded gross earnings"))
        #expect(spoken.contains("$80.00"))
        #expect(spoken.contains("$64.00"))
        #expect(spoken.contains("more recorded"))
        #expect(spoken.contains("1 of 2 shifts"))
        #expect(spoken.contains("1 of 1 shift"))
        #expect(spoken.contains("do not cover all of their records"))
    }

    /// The previous span is named and dated in the period's own calendar, so a
    /// driver can see which days the second figure came from.
    @Test("The previous period is named and dated")
    func thePreviousPeriodIsNamedAndDated() throws {
        let calendar = try calendar()
        let locale = Locale(identifier: "en_US")
        let day = try #require(ReportingPeriod(unit: .day, containing: try date(2026, 6, 17, in: calendar), calendar: calendar))
        let now = try date(2026, 6, 17, 15, in: calendar)

        let comparison = try comparison(
            current: [shift(at: try date(2026, 6, 17, 9, in: calendar))],
            previous: [shift(at: try date(2026, 6, 16, 9, in: calendar))],
            of: day,
            asOf: now,
            calendar: calendar
        )
        let statement = comparison.previousPeriodStatement(asOf: now, calendar: calendar, locale: locale)

        #expect(comparison.title == "Compared with the previous day")
        #expect(statement.contains("Yesterday"))
        #expect(statement.contains("16"))
    }

    /// A custom range is compared through exactly the same calculator and says
    /// so in the driver's own noun.
    @Test("A custom range is compared like every other period")
    func customRangesAreComparedThroughTheSamePath() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 16, in: calendar)
        let range = try #require(
            ReportingPeriod(
                from: try date(2026, 9, 8, in: calendar),
                through: try date(2026, 9, 14, in: calendar),
                calendar: calendar
            )
        )

        let comparison = try comparison(
            current: [shift(at: try date(2026, 9, 9, in: calendar), earnings: try money("120.00"))],
            previous: [shift(at: try date(2026, 9, 2, in: calendar), earnings: try money("100.00"))],
            of: range,
            asOf: now,
            calendar: calendar
        )
        let entry = try #require(comparison.entry(.recordedGrossEarnings))

        #expect(comparison.periodNoun == "range")
        #expect(comparison.title == "Compared with the previous range")
        #expect(!comparison.lengthsDiffer)
        #expect(entry.difference == .money(try money("20.00")))
        #expect(entry.percentChange == 20)
    }
}
