import Foundation
import Testing
@testable import DashPilot

/// The week History is scoped to, and the split that decides which screen a
/// record is drawn on.
///
/// Every test injects its own `Calendar` with an explicit time zone and an
/// explicit first weekday, so nothing here depends on the machine it runs on or
/// on the day it is run. Dates are built from components rather than from epoch
/// offsets, because the rule under test is a calendar rule.
///
/// What is deliberately **not** re-proved here: that a week is half-open, that
/// it is 167 hours across a spring-forward, that it survives a month boundary,
/// or that a calendar's own first weekday is honoured. ``ReportingPeriod`` owns
/// all of that and `ReportingPeriodTests` already holds it. These tests cover
/// what this type adds: Monday whatever the device says, and the split.
@Suite("History weeks")
struct HistoryWeekTests {
    /// A record with a date and a name, standing in for a completed shift.
    ///
    /// A plain value rather than a `Shift`, because the partition is generic
    /// over what it arranges and nothing here needs a store to say whether a
    /// week holds a record.
    private struct Record: Equatable {
        let name: String
        let date: Date
    }

    private func calendar(timeZone: String = "America/New_York", firstWeekday: Int = 1) throws -> Calendar {
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
        _ minute: Int = 0,
        _ second: Int = 0,
        in calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            )
        )
    }

    private func week(_ date: Date, in calendar: Calendar) throws -> HistoryWeek {
        try #require(HistoryWeek(containing: date, calendar: calendar))
    }

    // MARK: Monday

    /// The one rule this type adds on top of `ReportingPeriod`.
    @Test("A History week starts on Monday whatever the device's first weekday is")
    func weekAlwaysStartsOnMonday() throws {
        // Wednesday, 16 September 2026.
        let midweek = DateComponents(year: 2026, month: 9, day: 16, hour: 12)

        for firstWeekday in 1...7 {
            let calendar = try calendar(firstWeekday: firstWeekday)
            let anchor = try #require(calendar.date(from: midweek))
            let week = try week(anchor, in: calendar)

            #expect(week.start == (try date(2026, 9, 14, 0, 0, in: calendar)))
            #expect(week.end == (try date(2026, 9, 21, 0, 0, in: calendar)))
            #expect(calendar.component(.weekday, from: week.start) == 2)
        }
    }

    @Test("Monday 00:00 opens the week, and Sunday 23:59:59 closes it")
    func mondayThroughSunday() throws {
        let calendar = try calendar()
        let week = try week(try date(2026, 9, 16, 12, 0, in: calendar), in: calendar)

        #expect(week.contains(try date(2026, 9, 14, 0, 0, 0, in: calendar)))
        #expect(week.contains(try date(2026, 9, 20, 23, 59, 59, in: calendar)))
        #expect(!week.contains(try date(2026, 9, 13, 23, 59, 59, in: calendar)))
        #expect(!week.contains(try date(2026, 9, 21, 0, 0, 0, in: calendar)))
    }

    /// The transition the driver on a Sunday night shift actually meets.
    @Test("A shift started at Monday midnight is in the week beginning, not the one ending")
    func mondayMidnightBelongsToTheWeekBeginning() throws {
        let calendar = try calendar()
        let midnight = try date(2026, 9, 21, 0, 0, in: calendar)

        let ending = try week(try date(2026, 9, 16, 12, 0, in: calendar), in: calendar)
        let beginning = try week(try date(2026, 9, 23, 12, 0, in: calendar), in: calendar)

        #expect(!ending.contains(midnight))
        #expect(beginning.contains(midnight))
        #expect(ending.end == beginning.start)
    }

    /// Sunday, in a calendar that thinks a week starts on Sunday, is the case
    /// Monday-pinning exists for: it must stay at the **end** of the week the
    /// driver has been working, not open a new one.
    @Test("Sunday closes the working week rather than opening the next one")
    func sundayClosesTheWeek() throws {
        let sundayFirst = try calendar(firstWeekday: 1)
        let sunday = try date(2026, 9, 20, 18, 0, in: sundayFirst)

        let week = try week(sunday, in: sundayFirst)

        #expect(week.start == (try date(2026, 9, 14, 0, 0, in: sundayFirst)))
        #expect(week.contains(try date(2026, 9, 14, 6, 0, in: sundayFirst)))
        #expect(week.contains(sunday))
    }

    // MARK: Boundaries the calendar decides

    @Test("A week straddling New Year is one week, in both years")
    func weekSpansAYearBoundary() throws {
        let calendar = try calendar()
        // Monday 28 December 2026 through Sunday 3 January 2027.
        let week = try week(try date(2026, 12, 30, 12, 0, in: calendar), in: calendar)

        #expect(week.start == (try date(2026, 12, 28, 0, 0, in: calendar)))
        #expect(week.contains(try date(2026, 12, 31, 22, 0, in: calendar)))
        #expect(week.contains(try date(2027, 1, 1, 2, 0, in: calendar)))
        #expect(!week.contains(try date(2027, 1, 4, 0, 0, in: calendar)))
    }

    /// The boundary is a wall-clock Monday midnight, so a week losing an hour
    /// still ends when the driver's Sunday does rather than an hour early.
    @Test("A week holding a daylight-saving change still runs Monday to Monday")
    func weekAcrossADaylightSavingChange() throws {
        let calendar = try calendar()
        // The clocks go forward on Sunday 8 March 2026 in New York.
        let week = try week(try date(2026, 3, 4, 12, 0, in: calendar), in: calendar)

        #expect(week.start == (try date(2026, 3, 2, 0, 0, in: calendar)))
        #expect(week.end == (try date(2026, 3, 9, 0, 0, in: calendar)))
        #expect(week.end.timeIntervalSince(week.start) == 167 * 3600)
        #expect(week.contains(try date(2026, 3, 8, 23, 0, in: calendar)))
    }

    @Test("The time zone decides which week a moment belongs to")
    func timeZoneDecidesTheWeek() throws {
        // 02:00 UTC on Monday 21 September is 22:00 on Sunday 20 September in
        // New York, which is the week before.
        let utc = try calendar(timeZone: "UTC")
        let newYork = try calendar()
        let moment = try date(2026, 9, 21, 2, 0, in: utc)

        #expect(try week(try date(2026, 9, 23, 12, 0, in: utc), in: utc).contains(moment))
        #expect(try week(try date(2026, 9, 16, 12, 0, in: newYork), in: newYork).contains(moment))
    }

    // MARK: The split

    private func record(_ name: String, _ date: Date) -> Record { Record(name: name, date: date) }

    private func partition(
        _ records: [Record],
        asOf now: Date,
        in calendar: Calendar
    ) throws -> HistoryWeekPartition<Record> {
        try #require(HistoryWeek.partition(records, by: \.date, asOf: now, calendar: calendar))
    }

    @Test("Only this week's records are in the current week, and in the order given")
    func currentWeekHoldsThisWeekOnly() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = [
            record("Thursday", try date(2026, 9, 17, 9, 0, in: calendar)),
            record("Tuesday", try date(2026, 9, 15, 9, 0, in: calendar)),
            record("last week", try date(2026, 9, 10, 9, 0, in: calendar))
        ]

        let split = try partition(records, asOf: now, in: calendar)

        #expect(split.currentWeek.elements.map(\.name) == ["Thursday", "Tuesday"])
        #expect(split.currentWeek.week.start == (try date(2026, 9, 14, 0, 0, in: calendar)))
        #expect(split.otherWeeks.flatMap { $0.elements }.map(\.name) == ["last week"])
    }

    @Test("Older records are grouped by their own week, newest week first")
    func olderRecordsAreGroupedNewestWeekFirst() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = [
            record("this week", try date(2026, 9, 15, 9, 0, in: calendar)),
            record("three weeks ago, Thursday", try date(2026, 8, 27, 16, 0, in: calendar)),
            record("last week", try date(2026, 9, 9, 10, 0, in: calendar)),
            record("three weeks ago, Tuesday", try date(2026, 8, 25, 11, 0, in: calendar))
        ]

        let split = try partition(records, asOf: now, in: calendar)

        #expect(split.otherWeeks.count == 2)
        #expect(split.otherWeeks[0].week.start == (try date(2026, 9, 7, 0, 0, in: calendar)))
        #expect(split.otherWeeks[0].elements.map(\.name) == ["last week"])
        #expect(split.otherWeeks[1].week.start == (try date(2026, 8, 24, 0, 0, in: calendar)))
        // Both of that week's records, under one heading, in the order given.
        #expect(
            split.otherWeeks[1].elements.map(\.name)
                == ["three weeks ago, Thursday", "three weeks ago, Tuesday"]
        )
    }

    /// A week nothing was worked in is not a group. An empty heading over an
    /// empty list would be the screen inventing a week the driver did not work.
    @Test("A week holding nothing is absent rather than shown empty")
    func emptyWeeksAreNotGrouped() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = [
            record("nine weeks ago", try date(2026, 7, 15, 9, 0, in: calendar))
        ]

        let split = try partition(records, asOf: now, in: calendar)

        #expect(split.otherWeeks.count == 1)
        #expect(split.otherWeekRecordCount == 1)
    }

    @Test("A current week holding nothing is still the current week")
    func currentWeekIsPresentWhenEmpty() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = [record("last week", try date(2026, 9, 10, 9, 0, in: calendar))]

        let split = try partition(records, asOf: now, in: calendar)

        #expect(split.currentWeek.isEmpty)
        #expect(split.currentWeek.week.start == (try date(2026, 9, 14, 0, 0, in: calendar)))
        #expect(split.hasOtherWeeks)
    }

    @Test("Nothing at all leaves an empty current week and no older weeks")
    func emptyHistory() throws {
        let calendar = try calendar()
        let split = try partition([], asOf: try date(2026, 9, 17, 12, 0, in: calendar), in: calendar)

        #expect(split.currentWeek.isEmpty)
        #expect(!split.hasOtherWeeks)
        #expect(split.otherWeekRecordCount == 0)
    }

    /// The split has to agree with itself at the instant it is most likely to be
    /// read: a driver finishing at one minute past Monday midnight.
    @Test("A record at Monday midnight moves into the new current week, not out of reach")
    func theMondayTransitionMovesARecordBetweenSides() throws {
        let calendar = try calendar()
        let midnight = try date(2026, 9, 21, 0, 0, in: calendar)
        let justBefore = try date(2026, 9, 20, 23, 59, 59, in: calendar)
        let records = [record("Monday 00:00", midnight), record("Sunday 23:59:59", justBefore)]

        let sunday = try partition(records, asOf: try date(2026, 9, 20, 22, 0, in: calendar), in: calendar)
        #expect(sunday.currentWeek.elements.map(\.name) == ["Sunday 23:59:59"])
        #expect(sunday.otherWeeks.flatMap { $0.elements }.map(\.name) == ["Monday 00:00"])

        let monday = try partition(records, asOf: midnight, in: calendar)
        #expect(monday.currentWeek.elements.map(\.name) == ["Monday 00:00"])
        #expect(monday.otherWeeks.flatMap { $0.elements }.map(\.name) == ["Sunday 23:59:59"])
    }

    /// Every record is on exactly one side of the split. A record on neither
    /// would be work the driver can no longer reach from any screen.
    @Test("Every record is claimed by exactly one side")
    func nothingIsLost() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = (0..<40).map { index in
            record("\(index)", now.addingTimeInterval(Double(-index) * 30 * 3600))
        }

        let split = try partition(records, asOf: now, in: calendar)

        let claimed = split.currentWeek.elements + split.otherWeeks.flatMap { $0.elements }
        #expect(claimed.count == records.count)
        #expect(Set(claimed.map(\.name)) == Set(records.map(\.name)))
    }

    /// A completed shift cannot truthfully be in the future, but a device clock
    /// moved backwards can leave one in a store. It is listed rather than
    /// hidden, which is the one outcome worth ruling out.
    @Test("A record dated after this week is still reachable, at the top")
    func aLaterWeekIsStillListed() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let records = [
            record("next week", try date(2026, 9, 22, 9, 0, in: calendar)),
            record("last week", try date(2026, 9, 10, 9, 0, in: calendar))
        ]

        let split = try partition(records, asOf: now, in: calendar)

        #expect(split.currentWeek.isEmpty)
        #expect(split.otherWeeks.map { $0.elements.map(\.name) } == [["next week"], ["last week"]])
    }

    // MARK: Wording

    @Test("The week the driver is in is named for what it is to them")
    func currentWeekIsNamed() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)

        #expect(try week(now, in: calendar).title(asOf: now, calendar: calendar) == "This Week")
    }

    @Test("An older week is named by its dates rather than relatively")
    func olderWeekIsNamedByItsDates() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let older = try week(try date(2026, 9, 10, 12, 0, in: calendar), in: calendar)

        let title = older.title(asOf: now, calendar: calendar)
        #expect(title != "This Week")
        #expect(!title.isEmpty)
    }

    /// A heading that is a bare pair of dates says nothing about what it is a
    /// heading for, so the spoken form names the week as well.
    @Test("The spoken form names the week and the days it covers")
    func spokenTitleNamesBoth() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 17, 12, 0, in: calendar)
        let week = try week(now, in: calendar)

        let spoken = week.spokenTitle(asOf: now, calendar: calendar)
        #expect(spoken.contains("This Week"))
        #expect(spoken.contains(week.rangeStatement(calendar: calendar)))
    }

    /// The wording must describe the Monday week, not the week the device's own
    /// first weekday would have produced.
    @Test("The dates a week states are its own Monday-to-Sunday dates")
    func wordingFollowsTheMondayWeek() throws {
        let sundayFirst = try calendar(firstWeekday: 1)
        let now = try date(2026, 9, 17, 12, 0, in: sundayFirst)
        let week = try week(now, in: sundayFirst)

        // 14 September 2026 is the Monday. A Sunday-first calendar would have
        // started this week on the 13th and said so here.
        let statement = week.rangeStatement(calendar: sundayFirst, locale: Locale(identifier: "en_US"))
        #expect(statement.contains("14"))
        #expect(!statement.contains("13"))
    }
}
