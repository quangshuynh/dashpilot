import Foundation
import Testing
@testable import DashPilot

/// Money's activity slices: how a period is divided, and that the slices add
/// back up to the period's own figures. Every amount is synthetic.
@Suite("Money activity")
struct MoneyActivityTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func range(_ start: Date, _ end: Date) throws -> ReportingPeriod {
        try #require(ReportingPeriod(from: start, through: end, calendar: calendar))
    }

    private func shift(_ start: Date, hours: Double = 2, gross: Decimal? = 50) -> PeriodShiftRecord {
        PeriodShiftRecord(startedAt: start, workingDuration: hours * 3_600, grossEarnings: gross.map(Money.init(amount:)))
    }

    private func expense(_ date: Date, _ amount: Decimal, _ category: ExpenseCategory = .fuel) -> ExpenseRecord {
        ExpenseRecord(occurredAt: date, amount: Money(amount: amount), category: category)
    }

    private func build(_ shifts: [PeriodShiftRecord], _ expenses: [ExpenseRecord], _ period: ReportingPeriod) throws -> MoneyActivity {
        try #require(try MoneyActivityBuilder.build(shifts: shifts, expenses: expenses, in: period, calendar: calendar))
    }

    // MARK: Division

    @Test("Days up to a month, weeks up to six months, months beyond")
    func granularityFollowsLength() throws {
        let start = day(2026, 1, 1)
        func granularity(days: Int) throws -> MoneyActivityGranularity? {
            let end = try #require(calendar.date(byAdding: .day, value: days - 1, to: start))
            return MoneyActivityGranularity(for: try range(start, end), calendar: calendar)
        }
        #expect(try granularity(days: 1) == .day)
        #expect(try granularity(days: 31) == .day)
        #expect(try granularity(days: 32) == .week)
        #expect(try granularity(days: 186) == .week)
        #expect(try granularity(days: 187) == .month)
        #expect(try granularity(days: 365 * 5) == .month)
    }

    @Test("A week holding the end of daylight saving still has seven whole days")
    func daylightSavingEndWeek() throws {
        // Monday October 26 to Sunday November 1, 2026; clocks fall back on the 1st.
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 28), calendar: calendar))
        let slices = MoneyActivityBuilder.slices(of: week, by: .day, calendar: calendar)
        #expect(slices.count == 7)
        #expect(slices.first?.start == week.start)
        #expect(slices.last?.end == week.end)
        #expect(slices.allSatisfy { $0.unit == .day })
        #expect(slices.last.map { $0.end.timeIntervalSince($0.start) } == TimeInterval(25 * 3_600))
        for (earlier, later) in zip(slices, slices.dropFirst()) { #expect(earlier.end == later.start) }
    }

    @Test("A month holding the start of daylight saving has one 23-hour day")
    func daylightSavingStartMonth() throws {
        let march = try #require(ReportingPeriod(unit: .month, containing: day(2026, 3, 15), calendar: calendar))
        let slices = MoneyActivityBuilder.slices(of: march, by: .day, calendar: calendar)
        #expect(slices.count == 31)
        #expect(slices.filter { $0.end.timeIntervalSince($0.start) == TimeInterval(23 * 3_600) }.count == 1)
        #expect(slices.first?.start == march.start && slices.last?.end == march.end)
    }

    @Test("Weekly slices of a range are clipped to it and cover it exactly")
    func weeklySlicesClipToTheRange() throws {
        // Thursday February 5 through Tuesday April 7, 2026: 62 days.
        let period = try range(day(2026, 2, 5), day(2026, 4, 7))
        let activity = try build([], [], period)
        #expect(activity.granularity == .week)
        let slices = activity.buckets.map(\.period)
        #expect(slices.first?.start == period.start)
        #expect(slices.first?.unit == .custom, "Thursday to Sunday is part of a week")
        #expect(slices.last?.end == period.end)
        #expect(slices.last?.unit == .custom)
        #expect(slices.dropFirst().dropLast().allSatisfy { $0.unit == .week })
        for (earlier, later) in zip(slices, slices.dropFirst()) { #expect(earlier.end == later.start) }
    }

    @Test("Monthly slices of a long range cross a year boundary")
    func monthlySlices() throws {
        let period = try range(day(2025, 11, 20), day(2026, 8, 3))
        let slices = try build([], [], period).buckets.map(\.period)
        #expect(slices.count == 10)
        #expect(slices.first?.unit == .custom && slices.last?.unit == .custom)
        #expect(slices.dropFirst().dropLast().allSatisfy { $0.unit == .month })
    }

    // MARK: Membership

    @Test("A shift belongs wholly to the day it started, even past midnight")
    func overnightShiftStaysOnItsStartDay() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let activity = try build([shift(day(2026, 10, 13, 23, 30), hours: 3, gross: 90),
                                  shift(day(2026, 10, 14), gross: 10)], [], week)
        let tuesday = try #require(activity.buckets.first { $0.period.contains(day(2026, 10, 13, 12)) })
        let wednesday = try #require(activity.buckets.first { $0.period.contains(day(2026, 10, 14, 12)) })
        #expect(tuesday.metrics.recordedGrossEarnings == Money(amount: 90))
        #expect(wednesday.metrics.recordedGrossEarnings == Money(amount: 10), "Midnight begins the new day")
        #expect(wednesday.metrics.completedShiftCount == 1)
    }

    @Test("An expense-only day is recorded, with no earnings and no net")
    func expenseOnlyDay() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let activity = try build([shift(day(2026, 10, 12, 9))], [expense(day(2026, 10, 15, 8), 40)], week)
        let thursday = try #require(activity.buckets.first { $0.period.contains(day(2026, 10, 15, 8)) })
        #expect(thursday.hasRecords)
        #expect(thursday.metrics.isEmpty)
        #expect(thursday.metrics.recordedGrossEarnings == nil)
        #expect(thursday.metrics.expenses.recordedTotal == Money(amount: 40))
        #expect(thursday.metrics.netAfterRecordedExpenses.amount == nil)
        #expect(activity.recordedBuckets.map(\.id) == [thursday.id, day(2026, 10, 12)], "Newest first")
    }

    @Test("A shift with no amount stays missing; a recorded zero stays zero")
    func missingAndZeroEarnings() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let missing = try build([shift(day(2026, 10, 12, 9), gross: nil)], [], week)
        #expect(!missing.hasChartableAmounts)
        #expect(missing.recordedBuckets.count == 1, "The shift is still a record")
        #expect(missing.recordedBuckets[0].metrics.recordedGrossEarnings == nil)
        #expect(missing.recordedBuckets[0].metrics.earningsCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 1))
        let zero = try build([shift(day(2026, 10, 12, 9), gross: 0)], [], week)
        #expect(zero.hasChartableAmounts)
        #expect(zero.recordedBuckets[0].metrics.recordedGrossEarnings == .zero)
    }

    @Test("A running shift contributes to no slice")
    func runningShiftsAreExcluded() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let running = PeriodShiftRecord(startedAt: day(2026, 10, 13, 9), isCompleted: false, workingDuration: nil,
                                        grossEarnings: Money(amount: 25))
        #expect(try build([running], [], week).recordedBuckets.isEmpty)
    }

    @Test("Days still to come are not drawn, unless they hold a record")
    func futureSlices() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let now = day(2026, 10, 14, 12)
        let empty = try build([], [], week)
        #expect(empty.buckets(startedBy: now).count == 3, "Monday through Wednesday")
        let dated = try build([], [expense(day(2026, 10, 17, 9), 5)], week)
        #expect(dated.buckets(startedBy: now).count == 4)
    }

    // MARK: Reconciliation

    /// Overlapping shifts, overnight starts, zero and missing amounts, and
    /// expense-only days, across a month and the days around it.
    private func mixedFixture() -> (shifts: [PeriodShiftRecord], expenses: [ExpenseRecord]) {
        var shifts: [PeriodShiftRecord] = []
        var expenses: [ExpenseRecord] = []
        for offset in -3..<34 {
            let date = calendar.date(byAdding: .day, value: offset, to: day(2026, 10, 1))!
            let slot = (offset + 3) % 5
            if slot != 4 {
                let gross: Decimal? = slot == 1 ? nil : slot == 2 ? 0 : Decimal(offset * 7) + Decimal(string: "12.34")!
                shifts.append(shift(calendar.date(byAdding: .hour, value: 10, to: date)!, gross: gross))
                // An overlapping second shift, recorded as such.
                shifts.append(shift(calendar.date(byAdding: .hour, value: 11, to: date)!, hours: 3, gross: Decimal(string: "8.05")!))
                shifts.append(shift(calendar.date(byAdding: .minute, value: 23 * 60 + 59, to: date)!, hours: 1, gross: 3))
            }
            if offset % 3 == 0 {
                expenses.append(expense(calendar.date(byAdding: .hour, value: 18, to: date)!, Decimal(offset + 3) + Decimal(string: "0.99")!,
                                        ExpenseCategory.allCases[(offset + 3) % ExpenseCategory.allCases.count]))
            }
        }
        return (shifts, expenses)
    }

    @Test("Slices add back up to the period's own figures", arguments: [6, 31, 62, 200])
    func slicesReconcileWithThePeriod(days: Int) throws {
        let (shifts, expenses) = mixedFixture()
        let period = try range(day(2026, 9, 29), try #require(calendar.date(byAdding: .day, value: days - 1, to: day(2026, 9, 29))))
        let whole = PeriodMetricsCalculator().metrics(of: shifts, expenses: expenses, in: period)
        let buckets = try build(shifts, expenses, period).buckets
        let gross = buckets.compactMap(\.metrics.recordedGrossEarnings)
        #expect((gross.isEmpty ? nil : gross.reduce(.zero, +)) == whole.recordedGrossEarnings)
        let spent = buckets.compactMap(\.metrics.expenses.recordedTotal)
        #expect((spent.isEmpty ? nil : spent.reduce(.zero, +)) == whole.expenses.recordedTotal)
        #expect(buckets.map(\.metrics.completedShiftCount).reduce(0, +) == whole.completedShiftCount)
        #expect(buckets.map(\.metrics.expenses.recordCount).reduce(0, +) == whole.expenses.recordCount)
        #expect(buckets.map(\.metrics.earningsCoverage.contributingCount).reduce(0, +) == whole.earningsCoverage.contributingCount)
        let working = buckets.compactMap(\.metrics.workingDuration).reduce(0, +)
        #expect(abs(working - (whole.workingDuration ?? 0)) < 0.001)
    }

    @Test("Five years of history divide into months and still reconcile")
    func historicalScale() throws {
        var shifts: [PeriodShiftRecord] = []
        var expenses: [ExpenseRecord] = []
        let first = day(2021, 11, 1)
        for offset in 0..<(365 * 5) {
            let date = calendar.date(byAdding: .day, value: offset, to: first)!
            for hour in [8, 13, 19] {
                shifts.append(shift(calendar.date(byAdding: .hour, value: hour, to: date)!, gross: Decimal(hour) + Decimal(string: "0.25")!))
            }
            if offset % 2 == 0 { expenses.append(expense(date.addingTimeInterval(3_600), Decimal(string: "4.10")!)) }
        }
        let period = try range(first, try #require(calendar.date(byAdding: .day, value: 365 * 5 - 1, to: first)))
        let activity = try build(shifts, expenses, period)
        #expect(activity.granularity == .month)
        #expect(activity.buckets.count == 60)
        let whole = PeriodMetricsCalculator().metrics(of: shifts, expenses: expenses, in: period)
        #expect(activity.buckets.compactMap(\.metrics.recordedGrossEarnings).reduce(.zero, +) == whole.recordedGrossEarnings)
        #expect(activity.buckets.compactMap(\.metrics.expenses.recordedTotal).reduce(.zero, +) == whole.expenses.recordedTotal)
    }

    // MARK: Tips

    @Test("Tips add up separately and never change shift gross")
    func tipSubtotal() throws {
        let week = try #require(ReportingPeriod(unit: .week, containing: day(2026, 10, 14), calendar: calendar))
        let tipped = PeriodShiftRecord(startedAt: day(2026, 10, 13, 9), workingDuration: 3_600, grossEarnings: Money(amount: 20),
                                       recordedDeliveryEarnings: [Money(amount: 11)],
                                       recordedAdditionalTips: [Money(amount: 2), Money(amount: 1)], terminalDeliveryCount: 1)
        let untipped = PeriodShiftRecord(startedAt: day(2026, 10, 14, 9), workingDuration: 3_600, grossEarnings: nil,
                                         recordedDeliveryEarnings: [Money(amount: 7)], terminalDeliveryCount: 2)
        let metrics = PeriodMetricsCalculator().metrics(of: [tipped, untipped], in: week)
        #expect(metrics.recordedAdditionalTips == Money(amount: 3))
        #expect(metrics.additionalTipCount == 2)
        #expect(metrics.recordedGrossEarnings == Money(amount: 20))
        #expect(metrics.recordedDeliveryEarnings == Money(amount: 18))
        let none = PeriodMetricsCalculator().metrics(of: [untipped], in: week)
        #expect(none.recordedAdditionalTips == nil, "No tip is absent, not zero")
        #expect(none.additionalTipCount == 0)
        #expect(PeriodMetrics.empty(week).recordedAdditionalTips == nil)
    }
}
