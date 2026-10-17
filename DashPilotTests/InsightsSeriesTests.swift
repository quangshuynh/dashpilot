import Foundation
import SwiftData
import Testing
@testable import DashPilot

@Suite("Insights weekly series")
struct InsightsSeriesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func window(_ date: Date? = nil) throws -> InsightsWindow {
        try #require(InsightsWindow(endingAt: date ?? self.date(), calendar: calendar))
    }
    private func record(_ period: ReportingPeriod, money: Money? = nil, duration: TimeInterval? = 3600, completed: Bool = true) -> PeriodShiftRecord {
        PeriodShiftRecord(startedAt: period.start, isCompleted: completed, workingDuration: duration, grossEarnings: money)
    }
    private func build(_ shifts: [PeriodShiftRecord] = [], expenses: [ExpenseRecord] = [], window: InsightsWindow? = nil) throws -> InsightsSeries {
        try InsightsSeriesBuilder.build(shifts: shifts, expenses: expenses, window: window ?? self.window())
    }

    @Test func eightOrderedMondayWeeksAndOneBoundedComparisonWeek() throws {
        let window = try window()
        #expect(window.weeks.count == 8)
        #expect(window.weeks.map(\.start) == window.weeks.map(\.start).sorted())
        for week in window.weeks {
            #expect(calendar.component(.weekday, from: week.start) == 2)
            #expect(calendar.component(.weekday, from: week.lastInstant) == 1)
            #expect(!week.contains(week.end))
        }
        #expect(window.fetchPeriod.start == window.precedingWeek.start)
        #expect(window.fetchPeriod.end == window.weeks.last?.end)
        #expect(window.weeks.last?.start == calendar.startOfDay(for: date(2026, 10, 12)))
    }

    @Test(arguments: [(2026, 3, 8, 167), (2026, 11, 1, 169), (2027, 1, 1, 168)])
    func calendarBoundariesAcrossDSTAndYear(values: (Int, Int, Int, Int)) throws {
        let window = try window(date(values.0, values.1, values.2))
        let last = try #require(window.weeks.last)
        #expect(last.end.timeIntervalSince(last.start) == Double(values.3 * 3600))
        #expect(last.dayCount(using: calendar) == 7)
        #expect(last.previous(using: calendar)?.end == last.start)
        #expect(window.weeks[6].end == last.start)
    }

    @Test func labelsRetainReportingTimezoneAndAreDeterministic() throws {
        let week = try #require(window(date(2027, 1, 1)).weeks.last)
        let locale = Locale(identifier: "en_US")
        let label = week.rangeStatement(calendar: calendar, locale: locale)
        #expect(label.contains("2026"))
        #expect(label.contains("2027"))
        #expect(label == week.rangeStatement(calendar: calendar, locale: locale))
    }

    @Test(arguments: ["America/New_York", "America/Los_Angeles", "Pacific/Kiritimati"])
    func mondayRolloverUsesReportingTimezone(zone: String) throws {
        var calendar = self.calendar
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let before = try #require(InsightsWindow(endingAt: monday.addingTimeInterval(-1), calendar: calendar))
        let after = try #require(InsightsWindow(endingAt: monday, calendar: calendar))
        #expect(before.weeks.last?.end == monday)
        #expect(after.weeks.last?.start == monday)
        #expect(Array(before.weeks.dropFirst()) == Array(after.weeks.dropLast()))
        let shifts = [
            PeriodShiftRecord(startedAt: monday.addingTimeInterval(-1), isCompleted: true,
                              workingDuration: 7200, grossEarnings: Money(amount: 40)),
            PeriodShiftRecord(startedAt: monday, isCompleted: true,
                              workingDuration: 3600, grossEarnings: .zero)
        ]
        let series = try InsightsSeriesBuilder.build(shifts: shifts, expenses: [], window: after)
        #expect(series.weeks[6].metrics.recordedGrossEarnings == Money(amount: 40))
        #expect(series.weeks[7].metrics.recordedGrossEarnings == .zero)
        // An overnight shift remains wholly in its starting week.
        #expect(series.weeks[6].metrics.workingDuration == 7200)
    }

    @Test func sameInstantCanBelongToDifferentLocalWeeks() throws {
        var west = calendar
        west.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let instant = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 1)))
        let eastWeek = try #require(InsightsWindow(endingAt: instant, calendar: calendar)?.weeks.last)
        let westWeek = try #require(InsightsWindow(endingAt: instant, calendar: west)?.weeks.last)
        #expect(calendar.component(.day, from: eastWeek.start) == 19)
        #expect(west.component(.day, from: westWeek.start) == 12)
        #expect(eastWeek.contains(instant) && westWeek.contains(instant))
    }

    @Test func largeExactAmountsKeepCentsAndCoverage() throws {
        let window = try window()
        let week = try #require(window.weeks.last)
        let amount = try #require(Money(exact: "99999999.99"))
        let series = try build([record(week, money: amount), record(week, money: .zero), record(week)], window: window)
        let metrics = try #require(series.weeks.last?.metrics)
        #expect(metrics.recordedGrossEarnings == amount)
        #expect(metrics.earningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 3))
        #expect(metrics.recordedGrossEarnings?.formatted(locale: Locale(identifier: "en_US")) == "$99,999,999.99")
        #expect(metrics.grossPerWorkingHour.amount == Money(exact: "49999999.995"))
    }

    @Test func emptyAndSparseWeeksStayMissing() throws {
        let window = try window()
        let empty = try build(window: window)
        #expect(empty.weeks.count == 8)
        #expect(!empty.hasRecords)
        #expect(empty.weeks.allSatisfy { $0.metrics.recordedGrossEarnings == nil })
        let sparse = try build([record(window.weeks[2], money: Money(amount: 20))], window: window)
        #expect(sparse.weeks.filter { $0.metrics.recordedGrossEarnings != nil }.count == 1)
        #expect(sparse.weeks[2].metrics.recordedGrossEarnings == Money(amount: 20))
    }

    @Test func missingAndZeroRetainPartialCoverage() throws {
        let week = try window().weeks[0]
        let point = try build([record(week, money: .zero), record(week), record(week, money: Money(amount: 999), completed: false)]).weeks[0]
        #expect(point.metrics.recordedGrossEarnings == .zero)
        #expect(point.metrics.completedShiftCount == 2)
        #expect(point.metrics.earningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
        #expect(point.metrics.grossPerWorkingHour.amount == .zero)
    }

    @Test func hourlyRatesUsePairedSumsAndExcludeInvalidDurations() throws {
        let week = try window().weeks[0]
        let records = [record(week, money: Money(amount: 20), duration: 3600),
                       record(week, money: Money(amount: 120), duration: 10800),
                       record(week, duration: 36000), record(week, money: Money(amount: 50), duration: 0),
                       record(week, money: Money(amount: 50), duration: -1), record(week, money: Money(amount: 50), duration: .infinity)]
        let point = try build(records).weeks[0]
        #expect(point.metrics.grossPerWorkingHour.amount == Money(amount: 35))
        #expect(point.metrics.grossPerWorkingHour.coverage == MetricCoverage(contributingCount: 2, eligibleCount: 6))
        #expect(point.metrics.recordedGrossEarnings == Money(amount: 290))
    }

    @Test func deliveryGrossNeverEntersShiftTrend() throws {
        let week = try window().weeks[0]
        let record = PeriodShiftRecord(startedAt: week.start, workingDuration: 3600,
                                       recordedDeliveryEarnings: [Money(amount: 99)], terminalDeliveryCount: 1)
        let point = try build([record]).weeks[0]
        #expect(point.metrics.recordedGrossEarnings == nil)
        #expect(point.metrics.grossPerWorkingHour.amount == nil)
    }

    @Test func expensesReconcileAndZeroCategoryIsKept() throws {
        let week = try window().weeks[0]
        let expenses = ExpenseCategory.allCases.enumerated().map { index, category in
            ExpenseRecord(occurredAt: week.start, amount: Money(minorUnits: index * 123), category: category)
        }
        let point = try build(expenses: expenses).weeks[0]
        #expect(point.metrics.expenses.recordedTotal == Money(minorUnits: 1230))
        #expect(point.rankedExpenses.map(\.total).reduce(.zero, +) == point.metrics.expenses.recordedTotal)
        #expect(point.rankedExpenses.count == 5)
        #expect(point.rankedExpenses.last?.total == .zero)
        #expect(point.metrics.recordedGrossEarnings == nil)
        #expect(point.metrics.netAfterRecordedExpenses.amount == nil)
    }

    @Test func negativeQualifiedNetDoesNotChangeGrossOrExpenses() throws {
        let week = try window().weeks[0]
        let point = try build([record(week, money: Money(amount: 10))], expenses: [ExpenseRecord(occurredAt: week.start, amount: Money(amount: 30), category: .other)]).weeks[0]
        #expect(point.metrics.netAfterRecordedExpenses.amount == Money(amount: -20))
        #expect(point.metrics.recordedGrossEarnings == Money(amount: 10))
        #expect(point.metrics.expenses.recordedTotal == Money(amount: 30))
    }

    @Test func fullPriorWeeksCompareButCurrentWeekNeverGetsPercentage() throws {
        let window = try window()
        let shifts = (window.weeks + [window.precedingWeek]).enumerated().map { record($0.element, money: Money(amount: Decimal(($0.offset + 1) * 20))) }
        let series = try build(shifts, window: window)
        let past = try #require(series.weeks[6].comparison(asOf: date(), calendar: calendar))
        #expect(past.entry(.recordedGrossEarnings)?.percentChange != nil)
        let current = try #require(series.weeks[7].comparison(asOf: date(), calendar: calendar))
        #expect(current.isCurrentPeriodInProgress)
        #expect(current.entry(.recordedGrossEarnings)?.percentageRefusal == .currentPeriodInProgress)
        #expect(current.entries.allSatisfy { $0.percentChange == nil })
    }

    @Test(arguments: [true, false])
    func zeroBaselineAndIncompleteRecordsRefusePercent(zero: Bool) throws {
        let window = try window()
        var records = [record(window.weeks[0], money: zero ? .zero : Money(amount: 20)), record(window.weeks[1], money: Money(amount: 40))]
        if !zero { records.append(record(window.weeks[1])) }
        let point = try build(records).weeks[1]
        let comparison = try #require(point.comparison(asOf: date(), calendar: calendar))
        #expect(comparison.entry(.recordedGrossEarnings)?.percentageRefusal == (zero ? .previousIsZero : .completenessUnknown))
    }

    @Test func boundariesUseStartsAndExpenseDates() throws {
        let window = try window()
        let first = window.weeks[0]
        let shifts = [record(first, money: Money(amount: 10), duration: 604800),
                      PeriodShiftRecord(startedAt: first.end, workingDuration: 3600, grossEarnings: Money(amount: 20)),
                      record(window.precedingWeek, money: Money(amount: 5))]
        let expenses = [ExpenseRecord(occurredAt: first.end, amount: Money(amount: 3), category: .fuel)]
        let series = try build(shifts, expenses: expenses)
        #expect(series.weeks[0].metrics.recordedGrossEarnings == Money(amount: 10))
        #expect(series.weeks[0].metrics.expenses.recordedTotal == nil)
        #expect(series.weeks[1].metrics.recordedGrossEarnings == Money(amount: 20))
        #expect(series.weeks[1].metrics.expenses.recordedTotal == Money(amount: 3))
        #expect(series.weeks[0].previous.recordedGrossEarnings == Money(amount: 5))
    }
}

@MainActor @Suite("Insights bounded persistence")
struct InsightsLoaderTests {
    @Test func cancelledAndSupersededRangesCannotPublish() async throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let calendar = Calendar(identifier: .gregorian)
        let first = try #require(InsightsWindow(endingAt: Date(timeIntervalSince1970: 1792000000), calendar: calendar))
        let second = try #require(InsightsWindow(endingAt: first.precedingWeek.start, calendar: calendar))
        let firstRequest = PeriodLoadRequest(period: first.fetchPeriod, insightsWindow: first)
        let secondRequest = PeriodLoadRequest(period: second.fetchPeriod, insightsWindow: second)
        let old = try await Task.detached { try PeriodDataLoader.load(firstRequest, in: container) }.value
        let new = try await Task.detached { try PeriodDataLoader.load(secondRequest, in: container) }.value
        let store = PeriodLoadStore()
        let gate = InsightsLoadGate()
        let oldTask = Task { await store.load(key: .init(request: firstRequest)) { await gate.wait(); return old } }
        await gate.awaitStarted()
        await store.load(key: .init(request: secondRequest)) { new }
        await gate.release()
        await oldTask.value
        #expect(store.state == .loaded(new))
        let cancelledGate = InsightsLoadGate()
        let cancelled = Task { await store.load(key: .init(request: firstRequest)) { await cancelledGate.wait(); return old } }
        await cancelledGate.awaitStarted()
        cancelled.cancel()
        await cancelledGate.release()
        await cancelled.value
        #expect(store.state != .loaded(old))
        await store.load(key: .init(request: firstRequest)) { old }
        #expect(store.state == .loaded(old))
        await store.load(key: .init(request: firstRequest)) { throw CancellationError() }
        #expect(store.state == .loaded(old))
    }

    @Test func boundedFetchCorrectionsAndWorkingTime() async throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let window = try #require(InsightsWindow(endingAt: Date(timeIntervalSince1970: 1792000000), calendar: Calendar(identifier: .gregorian)))
        let week = try #require(window.weeks.last)
        for start in [window.fetchPeriod.start.addingTimeInterval(-1), window.fetchPeriod.end] {
            let shift = Shift(startedAt: start); context.insert(shift)
            try shift.end(at: start.addingTimeInterval(3600)); try shift.setGrossEarnings(Money(amount: 999))
            context.insert(try Expense(occurredAt: start, amount: Money(amount: 999), category: .other))
        }
        let shift = Shift(startedAt: week.start); context.insert(shift)
        let pause = try shift.beginPause(at: week.start.addingTimeInterval(1800))
        context.insert(pause)
        _ = try shift.endOpenPause(at: week.start.addingTimeInterval(5400))
        try shift.end(at: week.start.addingTimeInterval(7200)); try shift.setGrossEarnings(Money(amount: 40))
        context.insert(Shift(startedAt: week.start.addingTimeInterval(100)))
        let expense = try Expense(occurredAt: week.start, amount: Money(amount: 5), category: .fuel); context.insert(expense)
        try context.save()
        #expect(try context.fetch(PeriodDataLoader.shifts(in: window.fetchPeriod)).count == 1)
        #expect(try context.fetch(PeriodDataLoader.expenses(in: window.fetchPeriod)).count == 1)
        let request = PeriodLoadRequest(period: window.fetchPeriod, insightsWindow: window)
        func load() async throws -> InsightsSeries {
            let result = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
            #expect(result.current == nil && result.money == nil)
            return try #require(result.insights)
        }
        let original = try await load()
        #expect(original.weeks.last?.metrics.grossPerWorkingHour.amount == Money(amount: 40))
        try shift.setGrossEarnings(Money(amount: 80))
        try ExpenseService(context: context).update(expense, amount: Money(amount: 15), category: .supplies, occurredAt: week.start, noteText: "Synthetic correction")
        let corrected = try await load()
        #expect(corrected.weeks.last?.metrics.recordedGrossEarnings == Money(amount: 80))
        #expect(corrected.weeks.last?.metrics.expenses.recordedTotal == Money(amount: 15))
        #expect(original.weeks.last?.metrics.expenses.recordedTotal == Money(amount: 5))
        #expect(corrected.weeks.last?.metrics.recordedDistance == RouteDistance.none)
    }
}

private actor InsightsLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume(); started = nil
        }
    }
    func awaitStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
