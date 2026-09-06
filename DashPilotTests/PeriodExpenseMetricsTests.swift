import Foundation
import Testing
@testable import DashPilot

/// What a period says about recorded costs, and about what recorded earnings
/// come to after them.
///
/// Every amount and date below is invented. The calendar is pinned so a boundary
/// assertion is an assertion about the rule rather than about the machine.
@Suite("Period expenses")
struct PeriodExpenseMetricsTests {
    private let calculator = PeriodMetricsCalculator()
    private let expenseCalculator = ExpenseTotalsCalculator()

    /// New York, so both directions of a daylight-saving change are reachable.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        )
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func day(_ date: Date) throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .day, containing: date, calendar: calendar))
    }

    private func expense(
        _ amount: String,
        _ category: ExpenseCategory = .fuel,
        at date: Date
    ) throws -> ExpenseRecord {
        ExpenseRecord(occurredAt: date, amount: try money(amount), category: category)
    }

    private func shift(
        startingAt date: Date,
        hours: Double = 4,
        earnings: String? = nil
    ) throws -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: date,
            elapsedDuration: hours * 3600,
            grossEarnings: try earnings.map(money)
        )
    }

    // MARK: Totals

    @Test("A period's recorded expenses are the amounts entered in it, added up")
    func totalsWhatWasRecorded() throws {
        let today = try date(2026, 9, 6, 9)
        let period = try day(today)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [
                try expense("42.10", .fuel, at: today),
                try expense("6.50", .parkingAndTolls, at: today.addingTimeInterval(3 * 3600))
            ],
            in: period
        )

        #expect(metrics.expenses.recordedTotal == Money(exact: "48.60"))
        #expect(metrics.expenses.recordCount == 2)
        #expect(metrics.expenseStatement(locale: Locale(identifier: "en_US")) == "$48.60 recorded")
        #expect(metrics.expenseBasisStatement == "Across 2 recorded expenses")
    }

    @Test("A period with no expense recorded reports no total rather than zero")
    func missingIsNotZero() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [ExpenseRecord](),
            in: try day(today)
        )

        #expect(metrics.expenses.recordedTotal == nil, "Absent, never $0.00")
        #expect(!metrics.expenses.hasRecords)
        #expect(metrics.expenseStatement() == nil)
        #expect(metrics.expenseBasisStatement == "No expenses recorded")
        #expect(metrics.spokenExpenseStatement().contains("not the same as spending nothing"))
    }

    @Test("A recorded zero is a recorded expense, and differs from having recorded none")
    func explicitZeroIsCoverage() throws {
        let today = try date(2026, 9, 6, 9)
        let period = try day(today)
        let shifts = [try shift(startingAt: today, earnings: "86.25")]

        let zero = calculator.metrics(of: shifts, expenses: [try expense("0.00", at: today)], in: period)
        let none = calculator.metrics(of: shifts, expenses: [ExpenseRecord](), in: period)

        #expect(zero.expenses.recordedTotal == Money.zero)
        #expect(zero.expenses.recordCount == 1)
        #expect(none.expenses.recordedTotal == nil)
        // The pair that matters: one produces a net figure and the other cannot.
        #expect(zero.netAfterRecordedExpenses.amount == Money(exact: "86.25"))
        #expect(none.netAfterRecordedExpenses.amount == nil)
    }

    @Test("Categories are subtotalled in the enum's order, and an empty one is left out")
    func categoryTotals() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "100.00")],
            expenses: [
                try expense("89.99", .maintenance, at: today),
                try expense("6.50", .parkingAndTolls, at: today),
                try expense("42.10", .fuel, at: today),
                try expense("7.90", .fuel, at: today.addingTimeInterval(600))
            ],
            in: try day(today)
        )

        #expect(metrics.expenses.categoryTotals.map(\.category) == [.fuel, .parkingAndTolls, .maintenance])
        #expect(metrics.expenses.categoryTotals.first?.total == Money(exact: "50.00"))
        #expect(metrics.expenses.categoryTotals.first?.recordCount == 2)
        #expect(
            !metrics.expenses.categoryTotals.contains { $0.category == .supplies },
            "A category with nothing recorded is absent, never listed at $0.00"
        )
    }

    // MARK: Membership

    @Test("An expense belongs to the period containing its own timestamp")
    func membershipUsesTheExpenseTimestamp() throws {
        let today = try date(2026, 9, 6, 9)
        let yesterday = try date(2026, 9, 5, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [
                try expense("42.10", at: today),
                // Bought the day before, during no shift at all. It belongs to
                // its own day, not to the shift that came next.
                try expense("89.99", .maintenance, at: yesterday)
            ],
            in: try day(today)
        )

        #expect(metrics.expenses.recordedTotal == Money(exact: "42.10"))
        #expect(metrics.expenses.recordCount == 1)
    }

    @Test("The period boundary is half-open for an expense, exactly as for a shift")
    func halfOpenBoundary() throws {
        let period = try day(try date(2026, 9, 6, 9))
        let atStart = period.start
        let atEnd = period.end

        let metrics = calculator.metrics(
            of: [PeriodShiftRecord](),
            expenses: [try expense("10.00", at: atStart), try expense("20.00", at: atEnd)],
            in: period
        )

        #expect(metrics.expenses.recordCount == 1, "Midnight belongs to the day beginning, and to it only")
        #expect(metrics.expenses.recordedTotal == Money(exact: "10.00"))
    }

    @Test("A day whose clocks change still selects expenses by the calendar")
    func daylightSaving() throws {
        // 8 March 2026 is 23 hours long in New York. An expense at 23:30 that
        // evening is in that day; one at 00:30 the next morning is not.
        let springForward = try #require(ReportingPeriod(
            unit: .day,
            containing: try date(2026, 3, 8, 12),
            calendar: calendar
        ))

        let metrics = calculator.metrics(
            of: [PeriodShiftRecord](),
            expenses: [
                try expense("10.00", at: try date(2026, 3, 8, 23, 30)),
                try expense("20.00", at: try date(2026, 3, 9, 0, 30))
            ],
            in: springForward
        )

        #expect(springForward.end.timeIntervalSince(springForward.start) == 23 * 3600.0)
        #expect(metrics.expenses.recordCount == 1)
        #expect(metrics.expenses.recordedTotal == Money(exact: "10.00"))
    }

    @Test("A month totals its own expenses, not a sum of its weeks' answers")
    func monthTotalsIndividualRecords() throws {
        let month = try #require(ReportingPeriod(
            unit: .month,
            containing: try date(2026, 9, 15),
            calendar: calendar
        ))

        let metrics = calculator.metrics(
            of: [try shift(startingAt: try date(2026, 9, 15), earnings: "500.00")],
            expenses: [
                try expense("42.10", .fuel, at: try date(2026, 9, 2)),
                try expense("6.50", .parkingAndTolls, at: try date(2026, 9, 15)),
                try expense("89.99", .maintenance, at: try date(2026, 9, 28)),
                // Outside the month by one day at each end.
                try expense("11.11", .fuel, at: try date(2026, 8, 31)),
                try expense("22.22", .fuel, at: try date(2026, 10, 1))
            ],
            in: month
        )

        #expect(metrics.expenses.recordedTotal == Money(exact: "138.59"))
        #expect(metrics.expenses.recordCount == 3)
    }

    // MARK: A period with costs but no work

    @Test("A day with an expense and no completed shift keeps the expense")
    func expensesWithoutShifts() throws {
        let dayOff = try date(2026, 9, 6, 11)

        let metrics = calculator.metrics(
            of: [PeriodShiftRecord](),
            expenses: [try expense("42.10", at: dayOff)],
            in: try day(dayOff)
        )

        #expect(metrics.isEmpty, "It still holds no completed shift")
        #expect(metrics.hasAnyRecords, "But it is not a day with nothing recorded in it")
        #expect(metrics.expenses.recordedTotal == Money(exact: "42.10"))
        #expect(metrics.recordedGrossEarnings == nil)
        #expect(metrics.netAfterRecordedExpenses.amount == nil, "There are no recorded earnings to net")
    }

    @Test("A period with nothing at all has nothing at all")
    func trulyEmpty() throws {
        let metrics = calculator.metrics(
            of: [PeriodShiftRecord](),
            expenses: [ExpenseRecord](),
            in: try day(try date(2026, 9, 6))
        )

        #expect(metrics.isEmpty)
        #expect(!metrics.hasAnyRecords)
        #expect(metrics.expenses == .none)
    }

    // MARK: Net after recorded expenses

    @Test("The net is the recorded gross earnings less the recorded expenses")
    func netSubtracts() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [
                try shift(startingAt: today, earnings: "86.25"),
                // No amount recorded, so it contributes nothing and is counted.
                try shift(startingAt: today.addingTimeInterval(5 * 3600))
            ],
            expenses: [
                try expense("42.10", .fuel, at: today),
                try expense("6.50", .parkingAndTolls, at: today)
            ],
            in: try day(today)
        )

        let net = metrics.netAfterRecordedExpenses
        #expect(net.amount == Money(exact: "37.65"))
        #expect(net.earningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
        #expect(net.expenseRecordCount == 2)
        #expect(metrics.netBasisStatement == "Recorded gross earnings across 1 of 2 shifts, less 2 recorded expenses")
    }

    @Test("The earnings half of the net is the same subtotal the period reports")
    func netUsesThePeriodSubtotal() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [
                try shift(startingAt: today, earnings: "86.25"),
                try shift(startingAt: today.addingTimeInterval(5 * 3600), earnings: "120.00")
            ],
            expenses: [try expense("48.60", at: today)],
            in: try day(today)
        )

        let gross = try #require(metrics.recordedGrossEarnings)
        let net = try #require(metrics.netAfterRecordedExpenses.amount)
        #expect(gross == Money(exact: "206.25"))
        #expect(net == gross - (try money("48.60")))
        #expect(metrics.netAfterRecordedExpenses.earningsCoverage == metrics.earningsCoverage)
    }

    @Test("With no expense recorded there is no net, because the gross is not one")
    func noNetWithoutExpenses() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [ExpenseRecord](),
            in: try day(today)
        )

        #expect(metrics.netAfterRecordedExpenses.amount == nil)
        #expect(metrics.netStatement() == nil)
        #expect(
            metrics.netUnavailableExplanation.contains("nothing to subtract"),
            "And it says why, rather than printing the gross figure again under a different name"
        )
    }

    @Test("With no recorded earnings there is no net, rather than a negative one")
    func noNetWithoutEarnings() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today)],
            expenses: [try expense("42.10", at: today)],
            in: try day(today)
        )

        #expect(metrics.netAfterRecordedExpenses.amount == nil, "Never -$42.10 presented beside a day's work")
        #expect(metrics.netAfterRecordedExpenses.expenseRecordCount == 1)
        #expect(metrics.netUnavailableExplanation.contains("no recorded"))
    }

    @Test("A period whose recorded costs exceed its recorded earnings reports a negative net")
    func netCanBeNegative() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "40.00")],
            expenses: [try expense("89.99", .maintenance, at: today)],
            in: try day(today)
        )

        #expect(metrics.netAfterRecordedExpenses.amount == Money(exact: "-49.99"))
        #expect(metrics.netStatement(locale: Locale(identifier: "en_US")) == "-$49.99")
    }

    @Test("Nothing subtracts an expense from the period's gross figures")
    func grossIsUntouched() throws {
        let today = try date(2026, 9, 6, 9)
        let shifts = [try shift(startingAt: today, hours: 5, earnings: "100.00")]

        let without = calculator.metrics(of: shifts, expenses: [ExpenseRecord](), in: try day(today))
        let with = calculator.metrics(of: shifts, expenses: [try expense("42.10", at: today)], in: try day(today))

        #expect(with.recordedGrossEarnings == without.recordedGrossEarnings)
        #expect(with.grossPerElapsedHour == without.grossPerElapsedHour)
        #expect(with.grossPerDeliveryActiveHour == without.grossPerDeliveryActiveHour)
        #expect(with.grossPerRecordedMile == without.grossPerRecordedMile)
        #expect(with.recordedGrossEarnings == Money(exact: "100.00"))
        #expect(with.grossPerElapsedHour.amount == Money(exact: "20.00"), "Gross per hour, still gross")
    }

    // MARK: Wording

    @Test("The net is never called profit, and never appears without its caution")
    func wordingMakesNoProfitClaim() throws {
        let today = try date(2026, 9, 6, 9)
        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [try expense("42.10", at: today)],
            in: try day(today)
        )

        let sentences = [
            metrics.netTitle,
            metrics.netBasisStatement,
            metrics.netCautionStatement,
            metrics.spokenNetStatement(locale: Locale(identifier: "en_US")),
            metrics.expensesIncompleteExplanation,
            metrics.spokenExpenseStatement(locale: Locale(identifier: "en_US"))
        ]

        for sentence in sentences {
            let lowered = sentence.lowercased()
            for claim in ["profit", "take-home", "take home", "deductible", "tax deduction", "earnings after costs"] {
                // "not profit" is the one place the word may appear.
                let isDisclaimer = lowered.contains("not profit") && claim == "profit"
                #expect(isDisclaimer || !lowered.contains(claim), "\(claim) must not be claimed: \(sentence)")
            }
        }

        #expect(metrics.netTitle == "Net after recorded expenses")
        #expect(metrics.netCautionStatement.contains("did not enter are not subtracted"))
        #expect(metrics.spokenNetStatement().contains("not profit"))
    }

    @Test("A recorded total is always called recorded, and never the period's costs")
    func expenseWordingStaysRecorded() throws {
        let today = try date(2026, 9, 6, 9)
        let metrics = calculator.metrics(
            of: [PeriodShiftRecord](),
            expenses: [try expense("42.10", at: today)],
            in: try day(today)
        )

        #expect(try #require(metrics.expenseStatement(locale: Locale(identifier: "en_US"))).contains("recorded"))
        #expect(metrics.spokenExpenseStatement().hasPrefix("Recorded expenses"))
        #expect(metrics.expensesIncompleteExplanation.contains("not counted as zero"))
    }

    @Test("Expenses carry a count of what was entered, never a coverage pair")
    func noFabricatedCoverage() throws {
        let today = try date(2026, 9, 6, 9)
        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: [try expense("42.10", at: today), try expense("6.50", .parkingAndTolls, at: today)],
            in: try day(today)
        )

        // Nothing on the device knows how many costs went unrecorded, so no
        // "2 of 2" may ever be written about expenses.
        #expect(!metrics.expenseBasisStatement.contains(" of "))
        #expect(!metrics.spokenExpenseStatement().contains(" of "))
    }

    // MARK: The calculator on its own

    @Test("The totals calculator is the one definition, and the metrics agree with it")
    func calculatorAgreesWithMetrics() throws {
        let today = try date(2026, 9, 6, 9)
        let period = try day(today)
        let records = [
            try expense("42.10", .fuel, at: today),
            try expense("6.50", .parkingAndTolls, at: today)
        ]

        let totals = expenseCalculator.totals(of: records, in: period)
        let metrics = calculator.metrics(
            of: [try shift(startingAt: today, earnings: "86.25")],
            expenses: records,
            in: period
        )

        #expect(metrics.expenses == totals)
        #expect(
            metrics.netAfterRecordedExpenses == expenseCalculator.net(
                of: Money(exact: "86.25"),
                coverage: MetricCoverage(contributingCount: 1, eligibleCount: 1),
                after: totals
            )
        )
    }

    @Test("Summarising shifts without expenses reports none rather than inventing any")
    func shiftsOnlyOverload() throws {
        let today = try date(2026, 9, 6, 9)

        let metrics = calculator.metrics(of: [try shift(startingAt: today, earnings: "86.25")], in: try day(today))

        #expect(metrics.expenses == .none)
        #expect(metrics.netAfterRecordedExpenses.amount == nil)
        #expect(metrics.recordedGrossEarnings == Money(exact: "86.25"))
    }
}
