import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The store reads History's two screens are drawn from.
///
/// **The claim under test is that narrowing the fetch moved no boundary.** The
/// root screen used to fetch every completed shift and keep the current week
/// through ``HistoryWeek/partition(_:by:asOf:calendar:)``; it now asks the store
/// for that week alone. So several tests here build the same store, read it both
/// ways, and assert the two agree row for row, in order. Everything else is the
/// edge the predicate itself could get wrong: the half-open Monday boundary, a
/// week holding a daylight-saving change, the rollover, a shift dated after the
/// week, a running shift, and export still meaning the whole store.
///
/// The calendar is New York with a Sunday first weekday, so History's Monday
/// rule is exercised rather than inherited, and a real daylight-saving change
/// is reachable.
@MainActor
@Suite("History fetch scope")
struct HistoryFetchScopeTests {
    private let calendar: Calendar
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        self.calendar = calendar
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: Fixtures

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )))
    }

    private func week(_ date: Date) throws -> HistoryWeek {
        try #require(HistoryWeek(containing: date, calendar: calendar))
    }

    @discardableResult
    private func completedShift(at start: Date, hours: Double = 2) throws -> Shift {
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.end(at: start.addingTimeInterval(hours * 3_600))
        return shift
    }

    private func fetch(_ descriptor: FetchDescriptor<Shift>) throws -> [Shift] {
        try context.fetch(descriptor)
    }

    private func starts(_ shifts: [Shift]) -> [Date] { shifts.map(\.startedAt) }

    // MARK: The week

    @Test("The week's fetch holds its own completed shifts, newest first, and nothing else")
    func currentWeekHoldsOnlyTheWeek() throws {
        let now = try date(2026, 9, 23, 15)
        try completedShift(at: try date(2026, 9, 21, 9))
        try completedShift(at: try date(2026, 9, 22, 17))
        try completedShift(at: try date(2026, 9, 18, 11))
        try completedShift(at: try date(2025, 3, 4, 11))
        try context.save()

        let shifts = try fetch(HistoryFetchScope.currentWeek(try week(now)))

        #expect(starts(shifts) == [try date(2026, 9, 22, 17), try date(2026, 9, 21, 9)])
    }

    @Test("A running shift is in neither of History's reads")
    func runningShiftIsNotHistory() throws {
        let now = try date(2026, 9, 23, 15)
        try completedShift(at: try date(2026, 9, 21, 9))
        context.insert(Shift(startedAt: try date(2026, 9, 23, 14)))
        context.insert(Shift(startedAt: try date(2026, 9, 10, 14)))
        try context.save()

        let thisWeek = try week(now)
        #expect(try fetch(HistoryFetchScope.currentWeek(thisWeek)).count == 1)
        #expect(try fetch(HistoryFetchScope.otherWeeks(thisWeek)).isEmpty)
        #expect(try HistoryFetchScope.otherWeekShiftCount(outside: thisWeek, in: context) == 0)
    }

    @Test("Monday 00:00 opens the week and Sunday 23:59:59 closes the one before")
    func mondayBoundaryIsHalfOpen() throws {
        let monday = try date(2026, 9, 21, 0)
        let sunday = try date(2026, 9, 20, 23, 59, 59)
        let nextMonday = try date(2026, 9, 28, 0)
        try completedShift(at: monday)
        try completedShift(at: sunday)
        try completedShift(at: nextMonday)
        try context.save()

        let thisWeek = try week(try date(2026, 9, 23, 15))

        #expect(starts(try fetch(HistoryFetchScope.currentWeek(thisWeek))) == [monday])
        #expect(Set(starts(try fetch(HistoryFetchScope.otherWeeks(thisWeek)))) == [sunday, nextMonday])
    }

    @Test("A week holding the autumn clock change still runs Monday to Monday")
    func daylightSavingWeek() throws {
        // New York falls back on Sunday 1 November 2026, so this week is 169
        // hours long. A boundary written as 168 hours from Monday would drop
        // the last hour of Sunday into the next week.
        let lateSunday = try date(2026, 11, 1, 23, 30)
        let nextMonday = try date(2026, 11, 2, 0, 0)
        try completedShift(at: lateSunday)
        try completedShift(at: nextMonday)
        try context.save()

        let dstWeek = try week(try date(2026, 10, 28, 12))
        #expect(dstWeek.end.timeIntervalSince(dstWeek.start) == 169 * 3_600)
        #expect(starts(try fetch(HistoryFetchScope.currentWeek(dstWeek))) == [lateSunday])
        #expect(starts(try fetch(HistoryFetchScope.otherWeeks(dstWeek))) == [nextMonday])
    }

    @Test("When the week rolls over, a shift moves from the week to the weeks before it")
    func rolloverMovesTheShift() throws {
        let sundayNight = try date(2026, 9, 27, 22)
        try completedShift(at: sundayNight, hours: 3)
        try context.save()

        let before = try week(try date(2026, 9, 27, 23, 59))
        let after = try week(try date(2026, 9, 28, 0, 1))

        #expect(starts(try fetch(HistoryFetchScope.currentWeek(before))) == [sundayNight])
        #expect(try fetch(HistoryFetchScope.currentWeek(after)).isEmpty)
        #expect(starts(try fetch(HistoryFetchScope.otherWeeks(after))) == [sundayNight])
        #expect(try HistoryFetchScope.otherWeekShiftCount(outside: after, in: context) == 1)
    }

    @Test("A shift a moved clock dated after this week stays reachable, under the other weeks")
    func futureDatedShiftIsReachable() throws {
        let future = try date(2026, 10, 14, 9)
        try completedShift(at: try date(2026, 9, 21, 9))
        try completedShift(at: future)
        try context.save()

        let thisWeek = try week(try date(2026, 9, 23, 15))
        #expect(starts(try fetch(HistoryFetchScope.otherWeeks(thisWeek))) == [future])

        let summary = try HistoryFetchScope.otherWeeksSummary(outside: thisWeek, in: container, calendar: calendar)
        #expect(summary == HistoryOtherWeeksSummary(weekCount: 1, shiftCount: 1))
    }

    // MARK: Agreement with the partition

    @Test("The two reads are the partition's two sides, row for row and in order")
    func agreesWithThePartition() throws {
        let now = try date(2026, 9, 23, 15)
        var moment = try date(2024, 1, 1, 10)
        let end = try date(2026, 10, 20, 0)
        while moment < end {
            try completedShift(at: moment)
            moment = try #require(calendar.date(byAdding: DateComponents(day: 3, hour: 7), to: moment))
        }
        try context.save()

        let all = try fetch(HistoryFetchScope.allCompleted)
        let partition = try #require(HistoryWeek.partition(all, by: \.startedAt, asOf: now, calendar: calendar))
        let thisWeek = try week(now)

        let current = try fetch(HistoryFetchScope.currentWeek(thisWeek))
        let others = try fetch(HistoryFetchScope.otherWeeks(thisWeek))

        #expect(current.map(\.id) == partition.currentWeek.elements.map(\.id))
        #expect(others.map(\.id) == partition.otherWeeks.flatMap(\.elements).map(\.id))
        #expect(current.count + others.count == all.count)
        #expect(Set(current.map(\.id)).isDisjoint(with: others.map(\.id)))

        let summary = try HistoryFetchScope.otherWeeksSummary(outside: thisWeek, in: container, calendar: calendar)
        #expect(summary.weekCount == partition.otherWeeks.count)
        #expect(summary.shiftCount == partition.otherWeekRecordCount)
        #expect(try HistoryFetchScope.otherWeekShiftCount(outside: thisWeek, in: context) == others.count)
    }

    @Test("Other weeks are counted as Monday-to-Sunday weeks, not the device's weeks")
    func otherWeeksAreMondayWeeks() throws {
        // A Sunday and the Monday before it are one History week and two weeks
        // on this Sunday-first calendar.
        try completedShift(at: try date(2026, 9, 13, 18))
        try completedShift(at: try date(2026, 9, 7, 10))
        try completedShift(at: try date(2026, 8, 31, 10))
        try context.save()

        let summary = try HistoryFetchScope.otherWeeksSummary(
            outside: try week(try date(2026, 9, 23, 15)),
            in: container,
            calendar: calendar
        )
        #expect(summary == HistoryOtherWeeksSummary(weekCount: 2, shiftCount: 3))
        #expect(summary.statement == "2 weeks · 3 shifts")
        #expect(HistoryOtherWeeksSummary(weekCount: 1, shiftCount: 1).statement == "1 week · 1 shift")
    }

    @Test("A calendar with no week lists every completed shift and claims no other week")
    func noWeekFallsBackToEverything() throws {
        try completedShift(at: try date(2026, 9, 21, 9))
        try completedShift(at: try date(2025, 9, 21, 9))
        try context.save()

        #expect(try fetch(HistoryFetchScope.currentWeek(nil)).count == 2)
        #expect(try fetch(HistoryFetchScope.otherWeeks(nil)).isEmpty)
    }

    // MARK: Export

    /// The regression the narrower root read makes possible and must not
    /// happen: an export that followed the screen would carry one week.
    @Test("Export All History still carries every completed shift, whatever the screen holds")
    func exportAllHistoryIsEverything() throws {
        let now = try date(2026, 9, 23, 15)
        var moment = try date(2023, 9, 4, 10)
        var expected = 0
        while moment < now {
            try completedShift(at: moment)
            expected += 1
            moment = try #require(calendar.date(byAdding: .day, value: 5, to: moment))
        }
        // One after the week, as a moved clock leaves, and one still running.
        try completedShift(at: try date(2026, 11, 2, 9))
        expected += 1
        context.insert(Shift(startedAt: now))
        try context.save()

        let onScreen = try fetch(HistoryFetchScope.currentWeek(try week(now)))
        let document = try ShiftExportService(context: context, calendar: calendar).document(for: .allHistory)

        #expect(onScreen.count < 3)
        #expect(document.shifts.count == expected)
    }

    // MARK: A week's summary, off the main actor

    @Test("A week summarised through its own context is the same summary, and skips a deleted shift")
    func weekSummaryThroughItsOwnContext() throws {
        let monday = try date(2026, 9, 14, 9)
        let first = try completedShift(at: monday)
        try first.setGrossEarnings(Money(minorUnits: 8_000))
        let second = try completedShift(at: try date(2026, 9, 16, 17), hours: 3)
        try second.setGrossEarnings(Money(minorUnits: 6_000))
        try context.save()

        let week = try week(monday)
        let direct = HistoryWeekSummary(
            week: week,
            records: [first, second].map { $0.periodRecord(for: $0.recordedDistance()) }
        )
        let ids = [first, second].map(\.id)

        #expect(HistoryFetchScope.weekSummary(of: week, shiftIDs: ids, in: container) == direct)

        context.delete(second)
        try context.save()
        let afterDeletion = HistoryFetchScope.weekSummary(of: week, shiftIDs: ids, in: container)
        #expect(afterDeletion.completedShiftCount == 1)
        #expect(afterDeletion.metrics.recordedGrossEarnings == Money(minorUnits: 8_000))
    }
}
