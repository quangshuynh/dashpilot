import Foundation
import Testing
@testable import DashPilot

/// Money's period selection is worked out from the calendar alone. Every case
/// uses a Sunday-first calendar so the Monday-Sunday week policy is what holds.
@Suite("Money period selection")
struct MoneyPeriodSelectionTests {
    private let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func days(of period: ReportingPeriod?) -> [Int]? {
        guard let period else { return nil }
        let first = calendar.dateComponents([.month, .day], from: period.start)
        let last = calendar.dateComponents([.month, .day], from: period.lastInstant)
        return [first.month!, first.day!, last.month!, last.day!]
    }

    @Test("November 2026 weeks run Monday through Sunday")
    func novemberWeeks() {
        let now = date(2026, 11, 10)
        var selection = MoneyPeriodSelection()
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [11, 9, 11, 15])
        selection.selectPrevious(asOf: now, calendar: calendar)
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [11, 2, 11, 8])
        #expect(selection.preset(asOf: now, calendar: calendar) == .lastWeek)
        selection.selectPrevious(asOf: now, calendar: calendar)
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [10, 26, 11, 1])
        #expect(selection.preset(asOf: now, calendar: calendar) == nil)
    }

    @Test("Three weeks back, record-free or not, and forward to the current week")
    func browsingThreeWeeksAndBack() throws {
        let now = date(2026, 11, 3)
        var selection = MoneyPeriodSelection()
        let current = try #require(selection.period(asOf: now, calendar: calendar))
        #expect(!selection.canSelectNext(asOf: now, calendar: calendar))
        var visited = [current]
        for _ in 1...3 {
            #expect(selection.canSelectPrevious(asOf: now, calendar: calendar))
            selection.selectPrevious(asOf: now, calendar: calendar)
            let period = try #require(selection.period(asOf: now, calendar: calendar))
            #expect(period == visited.last?.previous(using: calendar))
            visited.append(period)
        }
        for expected in visited.dropLast().reversed() {
            #expect(selection.canSelectNext(asOf: now, calendar: calendar))
            selection.selectNext(asOf: now, calendar: calendar)
            #expect(selection.period(asOf: now, calendar: calendar) == expected)
        }
        #expect(selection.preset(asOf: now, calendar: calendar) == .thisWeek)
        selection.selectNext(asOf: now, calendar: calendar)
        #expect(selection.period(asOf: now, calendar: calendar) == current, "Next never passes the week in progress")
        #expect(selection == MoneyPeriodSelection(), "Back at the current week, the selection follows the calendar")
    }

    @Test("This Week follows the real calendar; a browsed week stays put")
    func currentWeekFollowsTheCalendar() throws {
        let sunday = date(2026, 11, 8, 23)
        let monday = date(2026, 11, 9, 1)
        var following = MoneyPeriodSelection()
        #expect(days(of: following.period(asOf: sunday, calendar: calendar)) == [11, 2, 11, 8])
        #expect(days(of: following.period(asOf: monday, calendar: calendar)) == [11, 9, 11, 15])
        var browsed = MoneyPeriodSelection()
        browsed.selectPrevious(asOf: sunday, calendar: calendar)
        #expect(days(of: browsed.period(asOf: monday, calendar: calendar)) == [10, 26, 11, 1])
        browsed.select(.thisWeek, asOf: monday, calendar: calendar)
        #expect(days(of: browsed.period(asOf: monday, calendar: calendar)) == [11, 9, 11, 15])
        following.select(.lastWeek, asOf: monday, calendar: calendar)
        #expect(days(of: following.period(asOf: monday, calendar: calendar)) == [11, 2, 11, 8])
    }

    @Test("This Month is bounded by the first day of this month and of the next")
    func monthBoundaries() throws {
        var selection = MoneyPeriodSelection()
        let lastMinute = date(2026, 11, 30, 23)
        selection.select(.thisMonth, asOf: lastMinute, calendar: calendar)
        let november = try #require(selection.period(asOf: lastMinute, calendar: calendar))
        #expect(november.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(november.end == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        #expect(!selection.browsesWeeks)
        #expect(!selection.canSelectPrevious(asOf: lastMinute, calendar: calendar))
        #expect(!selection.canSelectNext(asOf: lastMinute, calendar: calendar))
        let leap = date(2028, 2, 29)
        #expect(selection.period(asOf: leap, calendar: calendar)?.dayCount(using: calendar) == 29)
        #expect(selection.preset(asOf: leap, calendar: calendar) == .thisMonth)
    }

    @Test("A custom range includes both chosen days, refuses a reversed one and survives other presets")
    func customRange() throws {
        let now = date(2026, 11, 3)
        var selection = MoneyPeriodSelection()
        selection.select(.customRange, asOf: now, calendar: calendar)
        #expect(selection == MoneyPeriodSelection(), "Custom Range without dates changes nothing")
        let applied1 = selection.selectCustom(from: date(2026, 10, 1, 18), through: date(2026, 10, 7, 6), calendar: calendar)
        #expect(applied1)
        let range = try #require(selection.period(asOf: now, calendar: calendar))
        #expect(range.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(range.end == calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        #expect(range.contains(date(2026, 10, 7, 23)))
        #expect(!range.contains(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))!))
        #expect(!selection.browsesWeeks)
        let applied2 = selection.selectCustom(from: date(2026, 10, 9), through: date(2026, 10, 8), calendar: calendar)
        #expect(!applied2)
        #expect(selection.period(asOf: now, calendar: calendar) == range, "A refused range leaves the selection as it was")
        selection.select(.thisMonth, asOf: now, calendar: calendar)
        selection.select(.thisWeek, asOf: now, calendar: calendar)
        selection.select(.customRange, asOf: now, calendar: calendar)
        #expect(selection.period(asOf: now, calendar: calendar) == range)
        #expect(selection.preset(asOf: now, calendar: calendar) == .customRange)
        let single = MoneyPeriodSelection().with(from: date(2026, 10, 7), through: date(2026, 10, 7), calendar: calendar)
        #expect(single?.dayCount(using: calendar) == 1)
    }

    @Test("Ranges across daylight saving and the year end keep whole calendar days")
    func dstAndCrossYear() throws {
        var selection = MoneyPeriodSelection()
        // US daylight saving ends Sunday November 1, 2026: that day lasts 25 hours.
        let applied3 = selection.selectCustom(from: date(2026, 10, 31), through: date(2026, 11, 2), calendar: calendar)
        #expect(applied3)
        let fallBack = try #require(selection.period(asOf: date(2026, 11, 3), calendar: calendar))
        #expect(fallBack.dayCount(using: calendar) == 3)
        #expect(fallBack.end.timeIntervalSince(fallBack.start) == 73 * 3600)
        var week = MoneyPeriodSelection()
        let now = date(2027, 1, 5)
        week.selectPrevious(asOf: now, calendar: calendar)
        #expect(days(of: week.period(asOf: now, calendar: calendar)) == [12, 28, 1, 3])
        week.selectPrevious(asOf: now, calendar: calendar)
        #expect(days(of: week.period(asOf: now, calendar: calendar)) == [12, 21, 12, 27])
        week.selectNext(asOf: now, calendar: calendar)
        week.selectNext(asOf: now, calendar: calendar)
        #expect(days(of: week.period(asOf: now, calendar: calendar)) == [1, 4, 1, 10])
        // The week containing the spring change is 167 hours and still one week.
        var spring = MoneyPeriodSelection()
        let march = date(2027, 3, 16)
        spring.selectPrevious(asOf: march, calendar: calendar)
        let short = try #require(spring.period(asOf: march, calendar: calendar))
        #expect(days(of: short) == [3, 8, 3, 14])
        #expect(short.end.timeIntervalSince(short.start) == 167 * 3600)
    }

    @Test("Switching presets is predictable and never hides a reset")
    func switchingPresets() {
        let now = date(2026, 11, 3)
        var selection = MoneyPeriodSelection()
        selection.select(.lastWeek, asOf: now, calendar: calendar)
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [10, 26, 11, 1])
        #expect(selection.browsesWeeks)
        selection.selectNext(asOf: now, calendar: calendar)
        #expect(selection.preset(asOf: now, calendar: calendar) == .thisWeek)
        selection.select(.thisMonth, asOf: now, calendar: calendar)
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [11, 1, 11, 30])
        selection.select(.lastWeek, asOf: now, calendar: calendar)
        #expect(days(of: selection.period(asOf: now, calendar: calendar)) == [10, 26, 11, 1])
        #expect(days(of: selection.insightsWeek(asOf: now, calendar: calendar)) == [10, 26, 11, 1])
        selection.select(.thisMonth, asOf: now, calendar: calendar)
        #expect(days(of: selection.insightsWeek(asOf: now, calendar: calendar)) == [11, 2, 11, 8],
                "Insights opens on this month's latest week so far, never a future one")
    }
}

private extension MoneyPeriodSelection {
    func with(from start: Date, through end: Date, calendar: Calendar) -> ReportingPeriod? {
        var copy = self
        return copy.selectCustom(from: start, through: end, calendar: calendar) ? copy.customRange : nil
    }
}
