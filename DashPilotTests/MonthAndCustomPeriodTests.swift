import Foundation
import Testing
@testable import DashPilot

/// Calendar months, which are never a fixed number of days.
///
/// Every test injects its own `Calendar` with an explicit time zone and first
/// weekday, so nothing here depends on the machine it runs on or on when it is
/// run. Dates are built from components rather than from epoch offsets, because
/// the whole point of these rules is that a month is not a fixed number of
/// seconds.
@Suite("Calendar months")
struct CalendarMonthPeriodTests {
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
        in calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func month(_ date: Date, in calendar: Calendar) throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .month, containing: date, calendar: calendar))
    }

    /// The whole days a period covers, asked of the calendar.
    private func days(_ period: ReportingPeriod, in calendar: Calendar) throws -> Int {
        try #require(period.dayCount(using: calendar))
    }

    // MARK: Construction

    @Test("A month runs from the first of the month to the first of the next")
    func monthSpansTheCalendarMonth() throws {
        let calendar = try calendar()
        let period = try month(date(2026, 9, 14, 12, 0, in: calendar), in: calendar)

        #expect(period.start == (try date(2026, 9, 1, 0, 0, in: calendar)))
        #expect(period.end == (try date(2026, 10, 1, 0, 0, in: calendar)))
        #expect(period.unit == .month)
    }

    /// The lengths a fixed 30 or 31 days would get wrong. Asked of the calendar
    /// in every case, never divided out of a span in seconds.
    @Test(
        "A month is as long as the calendar says, never a fixed number of days",
        arguments: [
            (2026, 1, 31),
            (2026, 2, 28),
            (2028, 2, 29),
            (2026, 4, 30),
            (2026, 9, 30),
            (2026, 12, 31)
        ]
    )
    func monthLengthComesFromTheCalendar(year: Int, monthNumber: Int, expectedDays: Int) throws {
        let calendar = try calendar()
        let period = try month(date(year, monthNumber, 15, 12, 0, in: calendar), in: calendar)

        #expect(try days(period, in: calendar) == expectedDays)
    }

    @Test("February in a leap year holds the 29th, and the next February does not")
    func leapFebruaryHoldsTheTwentyNinth() throws {
        let calendar = try calendar()
        let leap = try month(date(2028, 2, 10, 12, 0, in: calendar), in: calendar)

        #expect(leap.contains(try date(2028, 2, 29, 23, 0, in: calendar)))
        #expect(leap.end == (try date(2028, 3, 1, 0, 0, in: calendar)))

        let nonLeap = try month(date(2026, 2, 10, 12, 0, in: calendar), in: calendar)
        #expect(nonLeap.end == (try date(2026, 3, 1, 0, 0, in: calendar)))
    }

    @Test("The month containing a spring-forward transition is an hour short of its days")
    func monthContainingSpringForward() throws {
        let calendar = try calendar()
        // The clocks go forward on 8 March 2026 in New York.
        let period = try month(date(2026, 3, 12, 12, 0, in: calendar), in: calendar)

        #expect(try days(period, in: calendar) == 31)
        #expect(period.end.timeIntervalSince(period.start) == 31 * 86_400 - 3600)
    }

    @Test("The month containing a fall-back transition is an hour longer than its days")
    func monthContainingFallBack() throws {
        let calendar = try calendar()
        // The clocks go back on 1 November 2026 in New York.
        let period = try month(date(2026, 11, 12, 12, 0, in: calendar), in: calendar)

        #expect(try days(period, in: calendar) == 30)
        #expect(period.end.timeIntervalSince(period.start) == 30 * 86_400 + 3600)
    }

    @Test("The injected time zone decides which month a moment belongs to")
    func timeZoneDecidesTheMonth() throws {
        // 02:00 UTC on 1 October is 22:00 on 30 September in New York.
        let utc = try calendar(timeZone: "UTC")
        let newYork = try calendar()
        let moment = try date(2026, 10, 1, 2, 0, in: utc)

        #expect(try month(date(2026, 10, 15, 12, 0, in: utc), in: utc).contains(moment))
        #expect(try month(date(2026, 9, 15, 12, 0, in: newYork), in: newYork).contains(moment))
    }

    // MARK: Membership

    @Test("A month includes its first instant and excludes its last")
    func monthIsHalfOpen() throws {
        let calendar = try calendar()
        let period = try month(date(2026, 9, 14, 12, 0, in: calendar), in: calendar)

        #expect(period.contains(try date(2026, 9, 1, 0, 0, in: calendar)))
        #expect(period.contains(try date(2026, 9, 30, 23, 59, in: calendar)))
        #expect(!period.contains(try date(2026, 10, 1, 0, 0, in: calendar)))
        #expect(!period.contains(try date(2026, 8, 31, 23, 59, in: calendar)))
    }

    /// The membership rule that keeps a shift whole. A shift beginning at 23:00
    /// on 30 September and ending at 02:00 on 1 October is September's, entirely.
    @Test("A shift crossing a month boundary belongs to the month it started in")
    func overnightShiftBelongsToItsStartMonth() throws {
        let calendar = try calendar()
        let startedAt = try date(2026, 9, 30, 23, 0, in: calendar)
        let september = try month(date(2026, 9, 14, 12, 0, in: calendar), in: calendar)
        let october = try month(date(2026, 10, 14, 12, 0, in: calendar), in: calendar)

        #expect(september.contains(startedAt))
        #expect(!october.contains(startedAt))
    }

    @Test("Adjacent months meet exactly, so no shift is counted twice or missed")
    func adjacentMonthsDoNotOverlap() throws {
        let calendar = try calendar()
        let september = try month(date(2026, 9, 14, 12, 0, in: calendar), in: calendar)
        let october = try #require(september.next(using: calendar))

        #expect(september.end == october.start)
        // Walked across the join a second at a time: the instant before belongs
        // to one month, the instant itself to the other, and neither to both.
        let boundary = september.end
        #expect(september.contains(boundary.addingTimeInterval(-1)))
        #expect(!september.contains(boundary))
        #expect(october.contains(boundary))
        #expect(!october.contains(boundary.addingTimeInterval(-1)))
    }

    // MARK: Stepping

    @Test("Stepping back from a 31-day month lands on the whole month before it")
    func stepsBackAcrossAShorterMonth() throws {
        let calendar = try calendar()
        let march = try month(date(2026, 3, 15, 12, 0, in: calendar), in: calendar)
        let february = try #require(march.previous(using: calendar))

        #expect(february.start == (try date(2026, 2, 1, 0, 0, in: calendar)))
        #expect(february.end == march.start)
        // The trap a fixed 30 or 31 days would fall into.
        #expect(try days(february, in: calendar) == 28)
    }

    @Test("Stepping forward from December lands on the following January")
    func stepsAcrossTheYearBoundary() throws {
        let calendar = try calendar()
        let december = try month(date(2026, 12, 20, 12, 0, in: calendar), in: calendar)
        let january = try #require(december.next(using: calendar))

        #expect(january.start == (try date(2027, 1, 1, 0, 0, in: calendar)))
        #expect(january.end == (try date(2027, 2, 1, 0, 0, in: calendar)))
        #expect(january.previous(using: calendar) == december)
    }

    /// Twelve steps forward from January must land on the next January, not
    /// somewhere adrift by the days the months differ by.
    @Test("A year of forward steps returns to the same month of the next year")
    func steppingAYearStaysOnMonthBoundaries() throws {
        let calendar = try calendar()
        var period = try month(date(2027, 1, 10, 12, 0, in: calendar), in: calendar)

        for _ in 0..<12 {
            period = try #require(period.next(using: calendar))
        }

        #expect(period.start == (try date(2028, 1, 1, 0, 0, in: calendar)))
    }

    // MARK: Wording

    @Test("The month the driver is in is named for what it is to them")
    func namesTheCurrentMonth() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 14, 0, in: calendar)

        #expect(try month(now, in: calendar).title(asOf: now, calendar: calendar) == "This Month")
    }

    @Test("An older month is named by its own month and year")
    func namesAnOlderMonthByItsDates() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 14, 0, in: calendar)
        let period = try month(date(2026, 6, 14, 12, 0, in: calendar), in: calendar)

        let title = period.title(asOf: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(title != "This Month")
        #expect(title.contains("June"))
        #expect(title.contains("2026"))
    }

    /// The month's name comes from the locale, not from a list of English words
    /// in this repository.
    @Test("A month's name is the driver's, not one the app hard-coded")
    func monthNameIsLocalised() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 14, 0, in: calendar)
        let period = try month(date(2026, 6, 14, 12, 0, in: calendar), in: calendar)

        let english = period.title(asOf: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        let french = period.title(asOf: now, calendar: calendar, locale: Locale(identifier: "fr_FR"))

        #expect(english != french, "A hard-coded month name would read the same in both: \(english)")
        #expect(!french.contains("June"))
    }

    @Test("A month is named, never described as complete or projected")
    func doesNotCallTheCurrentMonthComplete() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 14, 0, in: calendar)
        let spoken = try month(now, in: calendar)
            .spokenTitle(asOf: now, calendar: calendar, locale: Locale(identifier: "en_US"))
            .lowercased()

        for claim in ["complete", "final", "projected", "forecast", "on track"] {
            #expect(!spoken.contains(claim), "A period title must claim nothing about completeness: \(spoken)")
        }
    }

    @Test("A month says which dates it covers as well as its name")
    func monthStatesItsDates() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 14, 0, in: calendar)
        let period = try month(now, in: calendar)
        let locale = Locale(identifier: "en_US")

        let dates = period.rangeStatement(calendar: calendar, locale: locale)
        // The last day inside the month, never the exclusive boundary after it.
        #expect(dates.contains("30"), "A month's dates end on its last day: \(dates)")
        #expect(!dates.contains("Oct"), "…and not on the first day of the next: \(dates)")
        #expect(period.spokenTitle(asOf: now, calendar: calendar, locale: locale).contains(dates))
    }
}

/// Ranges the driver chose, by two inclusive calendar dates.
@Suite("Custom date ranges")
struct CustomReportingRangeTests {
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
        in calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func range(_ from: Date, _ through: Date, in calendar: Calendar) throws -> ReportingPeriod {
        try #require(ReportingPeriod(from: from, through: through, calendar: calendar))
    }

    // MARK: Construction

    /// The conversion the whole feature rests on: the driver picks *1 through
    /// 7*, and the domain gets `Sep 1 00:00 ..< Sep 8 00:00`.
    @Test("Inclusive dates become a half-open interval ending the day after the last")
    func inclusiveDatesBecomeAHalfOpenInterval() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 1, 9, 30, in: calendar),
            date(2026, 9, 7, 21, 45, in: calendar),
            in: calendar
        )

        #expect(period.unit == .custom)
        #expect(period.start == (try date(2026, 9, 1, 0, 0, in: calendar)))
        #expect(period.end == (try date(2026, 9, 8, 0, 0, in: calendar)))
        #expect(period.dayCount(using: calendar) == 7)
    }

    /// The times of day a date picker happens to carry must not lengthen or
    /// shorten the selection.
    @Test("The time of day in the chosen dates does not change the range")
    func timeOfDayIsIgnored() throws {
        let calendar = try calendar()
        let early = try range(
            date(2026, 9, 1, 0, 1, in: calendar),
            date(2026, 9, 7, 0, 1, in: calendar),
            in: calendar
        )
        let late = try range(
            date(2026, 9, 1, 23, 59, in: calendar),
            date(2026, 9, 7, 23, 59, in: calendar),
            in: calendar
        )

        #expect(early == late)
    }

    @Test("A range of one calendar day is valid and covers exactly that day")
    func oneDayRangeIsValid() throws {
        let calendar = try calendar()
        let chosen = try date(2026, 9, 4, 15, 0, in: calendar)
        let period = try range(chosen, chosen, in: calendar)

        #expect(period.start == (try date(2026, 9, 4, 0, 0, in: calendar)))
        #expect(period.end == (try date(2026, 9, 5, 0, 0, in: calendar)))
        #expect(period.dayCount(using: calendar) == 1)
        #expect(period.contains(try date(2026, 9, 4, 0, 0, in: calendar)))
        #expect(!period.contains(try date(2026, 9, 5, 0, 0, in: calendar)))
    }

    /// Refused, not reversed. Quietly swapping the dates would answer a question
    /// the driver did not ask and hide the fact that they typed one wrong.
    @Test("An end date before the start date is refused, never swapped")
    func reversedRangeIsRefused() throws {
        let calendar = try calendar()
        let period = ReportingPeriod(
            from: try date(2026, 9, 7, 12, 0, in: calendar),
            through: try date(2026, 9, 1, 12, 0, in: calendar),
            calendar: calendar
        )

        #expect(period == nil)
    }

    /// One second earlier in wall-clock time but on the same day is still a
    /// valid selection: the comparison is between *days*, not instants.
    @Test("An end time earlier in the same day is still a valid one-day range")
    func earlierTimeOnTheSameDayIsValid() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 4, 23, 0, in: calendar),
            date(2026, 9, 4, 1, 0, in: calendar),
            in: calendar
        )

        #expect(period.dayCount(using: calendar) == 1)
    }

    @Test("A range spanning a month boundary is one range")
    func rangeSpansAMonthBoundary() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 8, 28, 12, 0, in: calendar),
            date(2026, 9, 6, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.dayCount(using: calendar) == 10)
        #expect(period.contains(try date(2026, 8, 31, 23, 0, in: calendar)))
        #expect(period.contains(try date(2026, 9, 1, 0, 0, in: calendar)))
        #expect(!period.contains(try date(2026, 9, 7, 0, 0, in: calendar)))
    }

    @Test("A range spanning a year boundary is one range")
    func rangeSpansAYearBoundary() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 12, 29, 12, 0, in: calendar),
            date(2027, 1, 3, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.dayCount(using: calendar) == 6)
        #expect(period.contains(try date(2026, 12, 31, 23, 0, in: calendar)))
        #expect(period.contains(try date(2027, 1, 1, 0, 0, in: calendar)))
        #expect(!period.contains(try date(2027, 1, 4, 0, 0, in: calendar)))
    }

    @Test("A range across the spring transition counts whole days, not fixed seconds")
    func rangeAcrossSpringForward() throws {
        let calendar = try calendar()
        // The clocks go forward on 8 March 2026 in New York.
        let period = try range(
            date(2026, 3, 6, 12, 0, in: calendar),
            date(2026, 3, 10, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.dayCount(using: calendar) == 5)
        #expect(period.end.timeIntervalSince(period.start) == 5 * 86_400 - 3600)
        #expect(period.contains(try date(2026, 3, 8, 3, 0, in: calendar)))
    }

    @Test("A range across the autumn transition counts whole days, not fixed seconds")
    func rangeAcrossFallBack() throws {
        let calendar = try calendar()
        // The clocks go back on 1 November 2026 in New York.
        let period = try range(
            date(2026, 10, 30, 12, 0, in: calendar),
            date(2026, 11, 3, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.dayCount(using: calendar) == 5)
        #expect(period.end.timeIntervalSince(period.start) == 5 * 86_400 + 3600)
        #expect(period.contains(try date(2026, 11, 1, 12, 0, in: calendar)))
    }

    @Test("The injected time zone decides which days a range covers")
    func timeZoneDecidesTheRange() throws {
        let utc = try calendar(timeZone: "UTC")
        let newYork = try calendar()
        // 02:00 UTC on 8 September is 22:00 on 7 September in New York.
        let moment = try date(2026, 9, 8, 2, 0, in: utc)

        let inUTC = try range(date(2026, 9, 8, 12, 0, in: utc), date(2026, 9, 8, 12, 0, in: utc), in: utc)
        let inNewYork = try range(
            date(2026, 9, 7, 12, 0, in: newYork),
            date(2026, 9, 7, 12, 0, in: newYork),
            in: newYork
        )

        #expect(inUTC.contains(moment))
        #expect(inNewYork.contains(moment))
    }

    // MARK: Membership

    @Test("A range includes its exact start and excludes its exclusive end")
    func rangeIsHalfOpen() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.contains(try date(2026, 9, 1, 0, 0, in: calendar)))
        #expect(period.contains(try date(2026, 9, 7, 23, 59, in: calendar)))
        #expect(!period.contains(try date(2026, 9, 8, 0, 0, in: calendar)))
        #expect(!period.contains(try date(2026, 8, 31, 23, 59, in: calendar)))
    }

    @Test("A shift crossing the last night belongs to the range it started in")
    func overnightShiftBelongsByItsStart() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )

        // Started 23:00 on the last selected day, ended at 02:00 the next.
        #expect(period.contains(try date(2026, 9, 7, 23, 0, in: calendar)))
        // Started after the range ended: outside it, whole.
        #expect(!period.contains(try date(2026, 9, 8, 1, 0, in: calendar)))
    }

    @Test("Two ranges that meet at a day boundary never count a shift twice")
    func adjacentRangesDoNotOverlap() throws {
        let calendar = try calendar()
        let first = try range(date(2026, 9, 1, 12, 0, in: calendar), date(2026, 9, 7, 12, 0, in: calendar), in: calendar)
        let second = try range(date(2026, 9, 8, 12, 0, in: calendar), date(2026, 9, 14, 12, 0, in: calendar), in: calendar)

        #expect(first.end == second.start)
        let boundary = first.end
        #expect(first.contains(boundary.addingTimeInterval(-1)))
        #expect(!first.contains(boundary))
        #expect(second.contains(boundary))
    }

    // MARK: Stepping

    /// A chosen range has no neighbour. The range "after" *Sep 1–7* is not
    /// something the driver asked for, and offering one would invent a period.
    @Test("A chosen range has no previous or next period to step to")
    func rangeDoesNotStep() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.previous(using: calendar) == nil)
        #expect(period.next(using: calendar) == nil)
    }

    @Test("A custom range cannot be built from a date and a calendar component")
    func customIsNotACalendarPeriod() throws {
        let calendar = try calendar()

        #expect(ReportingPeriod(unit: .custom, containing: try date(2026, 9, 4, 12, 0, in: calendar), calendar: calendar) == nil)
        #expect(ReportingPeriodUnit.custom.component == nil)
        #expect(!ReportingPeriodUnit.custom.isCalendarPeriod)
        #expect(ReportingPeriodUnit.calendarUnits == [.day, .week, .month])
    }

    // MARK: Wording

    @Test("A range is named by its dates, written by Foundation")
    func rangeIsNamedByItsDates() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 12, 0, in: calendar)
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )
        let locale = Locale(identifier: "en_US")

        let title = period.title(asOf: now, calendar: calendar, locale: locale)
        #expect(title.contains("1") && title.contains("7"), "Both ends are named: \(title)")
        #expect(title.contains("2026"))
        // The last day selected, never the exclusive boundary after it.
        #expect(!title.contains("8"), "A range never names the day after it ends: \(title)")
    }

    @Test("A one-day range reads as one date rather than a pair")
    func oneDayRangeReadsAsOneDate() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 12, 0, in: calendar)
        let chosen = try date(2026, 9, 4, 12, 0, in: calendar)
        let period = try range(chosen, chosen, in: calendar)

        let title = period.title(asOf: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(title.contains("4"))
        #expect(!title.contains("5"))
        #expect(period.rangeStatement(calendar: calendar) == "1 selected day")
    }

    @Test("A range says how many days it selected")
    func rangeStatesItsDayCount() throws {
        let calendar = try calendar()
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )

        #expect(period.rangeStatement(calendar: calendar) == "7 selected days")
    }

    /// The one thing VoiceOver must not have to infer: that these dates are a
    /// selection the driver made, and what they select.
    @Test("A range is spoken as a custom reporting range, not a bare pair of dates")
    func rangeIsSpokenAsWhatItIs() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 12, 0, in: calendar)
        let period = try range(
            date(2026, 9, 1, 12, 0, in: calendar),
            date(2026, 9, 7, 12, 0, in: calendar),
            in: calendar
        )

        let spoken = period.spokenTitle(asOf: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(spoken.hasPrefix("Custom reporting range, "))
        #expect(spoken.contains("7 selected days"))
        for claim in ["complete", "final", "projected", "forecast", "week"] {
            #expect(!spoken.lowercased().contains(claim), "A range claims nothing it is not: \(spoken)")
        }
    }

    /// A rolling selection of seven days is not a week, and nothing in the app
    /// may call it one.
    @Test("A seven-day range is never described as a week")
    func sevenDaysIsNotCalledAWeek() throws {
        let calendar = try calendar()
        let now = try date(2026, 9, 14, 12, 0, in: calendar)
        // Wednesday to Tuesday: seven days, and not a calendar week.
        let period = try range(
            date(2026, 9, 2, 12, 0, in: calendar),
            date(2026, 9, 8, 12, 0, in: calendar),
            in: calendar
        )
        let locale = Locale(identifier: "en_US")

        #expect(!period.title(asOf: now, calendar: calendar, locale: locale).lowercased().contains("week"))
        #expect(!period.rangeStatement(calendar: calendar, locale: locale).lowercased().contains("week"))
    }
}

/// The point of the interval, in one suite: a month and a chosen range are new
/// **selection boundaries**, and nothing else.
///
/// Every rule these assert is already asserted for a day and a week in
/// `PeriodMetricsTests`. They are repeated here — with fixtures spread across
/// weeks and months rather than hours — because the way this feature could go
/// wrong is by a larger period quietly acquiring its own arithmetic: a month
/// built from its weeks' rates, a range built from its days' medians, a missing
/// amount that becomes a zero once there are thirty of them.
@Suite("Month and range metrics")
struct MonthAndRangeMetricsTests {
    private let calculator = PeriodMetricsCalculator()
    private let calendar: Calendar

    /// One mile in metres, so a test can state a distance in the unit the
    /// per-mile rate is expressed in.
    private static let metresPerMile = 1609.344

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    // MARK: Fixtures

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func september() throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .month, containing: try date(2026, 9, 15), calendar: calendar))
    }

    private func range(_ from: Date, _ through: Date) throws -> ReportingPeriod {
        try #require(ReportingPeriod(from: from, through: through, calendar: calendar))
    }

    private func route(miles: Double, gapCount: Int = 0) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: gapCount,
            usableSampleCount: 40,
            usesInferredContinuity: false
        )
    }

    /// A route that measured nothing: positions exist, but no two of them were
    /// captured continuously.
    private func unmeasurableRoute() -> RouteDistance {
        RouteDistance(
            metres: 0,
            segmentCount: 0,
            gapCount: 1,
            usableSampleCount: 3,
            usesInferredContinuity: false
        )
    }

    private func activeTime(_ duration: TimeInterval, merged: Int = 1) -> DeliveryActiveTime {
        DeliveryActiveTime(
            duration: duration,
            sourceIntervalCount: merged,
            countedIntervalCount: merged,
            mergedIntervalCount: merged,
            unfinishedIntervalCount: 0,
            malformedIntervalCount: 0
        )
    }

    private func record(
        startedAt: Date,
        isCompleted: Bool = true,
        elapsed: TimeInterval? = 3 * 3600,
        earnings: Money? = nil,
        route recordedDistance: RouteDistance = .none,
        active: DeliveryActiveTime = .none,
        deliveries: DeliverySummary = DeliverySummary(completed: 0, cancelled: 0),
        waits: [PickupWaitSample] = [],
        deliveryEarnings: [Money] = [],
        terminalDeliveries: Int = 0
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: startedAt,
            isCompleted: isCompleted,
            elapsedDuration: elapsed,
            grossEarnings: earnings,
            recordedDistance: recordedDistance,
            deliveryActiveTime: active,
            deliverySummary: deliveries,
            pickupWaits: waits,
            pickupPlaceIDs: [],
            recordedDeliveryEarnings: deliveryEarnings,
            terminalDeliveryCount: terminalDeliveries
        )
    }

    private func wait(minutes: Double, on day: Date) -> PickupWaitSample {
        PickupWaitSample(duration: minutes * 60, pickedUpAt: day)
    }

    // MARK: A month is not built from its weeks

    /// The fixture is chosen so the wrong answer is obviously wrong. Two weeks
    /// of the same month, each earning `$100`: one over 1 hour, one over 9. The
    /// weekly rates are `$100.00/hr` and `$11.11/hr`, whose mean is `$55.56`.
    /// The month earned `$200` over 10 hours, so it is **`$20.00/hr`**.
    @Test("A month's rate is its own amounts over its own hours, not a mean of its weeks'")
    func monthRateIsNotAMeanOfWeeklyRates() throws {
        let month = try september()
        let firstWeek = try record(startedAt: date(2026, 9, 2), elapsed: 3600, earnings: try money("100.00"))
        let thirdWeek = try record(startedAt: date(2026, 9, 16), elapsed: 9 * 3600, earnings: try money("100.00"))

        // What each week says on its own, to prove the two answers differ.
        let firstWeekPeriod = try #require(
            ReportingPeriod(unit: .week, containing: try date(2026, 9, 2), calendar: calendar)
        )
        let thirdWeekPeriod = try #require(
            ReportingPeriod(unit: .week, containing: try date(2026, 9, 16), calendar: calendar)
        )
        let locale = Locale(identifier: "en_US")
        let weeklyRates = [
            calculator.metrics(of: [firstWeek], in: firstWeekPeriod).grossPerElapsedHour.amount,
            calculator.metrics(of: [thirdWeek], in: thirdWeekPeriod).grossPerElapsedHour.amount
        ].compactMap { $0 }
        #expect(weeklyRates.map { $0.formatted(locale: locale) } == ["$100.00", "$11.11"])

        // The answer a mean of those two would give, worked out here so the
        // assertion below compares against the actual wrong answer rather than
        // against a number typed from memory.
        let meanOfWeeklyRates = try #require(weeklyRates.reduce(Money.zero, +).divided(by: 2))
        #expect(meanOfWeeklyRates.formatted(locale: locale) == "$55.56")

        let metrics = calculator.metrics(of: [firstWeek, thirdWeek], in: month)
        let monthRate = try #require(metrics.grossPerElapsedHour.amount)

        #expect(monthRate.formatted(locale: locale) == "$20.00")
        #expect(monthRate != meanOfWeeklyRates)
        #expect(metrics.recordedGrossEarnings == (try money("200.00")))
        #expect(metrics.elapsedDuration == 10 * 3600.0)
    }

    @Test("A chosen range's rate is its own amounts over its own hours, not a mean of its days'")
    func rangeRateIsNotAMeanOfDailyRates() throws {
        let period = try range(date(2026, 9, 1), date(2026, 9, 7))
        let short = try record(startedAt: date(2026, 9, 1), elapsed: 3600, earnings: try money("100.00"))
        let long = try record(startedAt: date(2026, 9, 5), elapsed: 9 * 3600, earnings: try money("100.00"))

        let metrics = calculator.metrics(of: [short, long], in: period)
        let rate = try #require(metrics.grossPerElapsedHour.amount)

        #expect(rate.formatted(locale: Locale(identifier: "en_US")) == "$20.00")
        #expect(metrics.elapsedDuration == 10 * 3600.0)
    }

    /// Five ten-minute waits on one day and one forty-minute wait on another are
    /// six samples with a median of 10 minutes. A median of the two days'
    /// medians would be 25.
    @Test("A month's pickup median is the middle of its individual waits, not of its days'")
    func monthPickupMedianUsesIndividualSamples() throws {
        let month = try september()
        let busy = try record(
            startedAt: date(2026, 9, 3),
            waits: try (0..<5).map { _ in wait(minutes: 10, on: try date(2026, 9, 3, 12)) }
        )
        let quiet = try record(startedAt: date(2026, 9, 24), waits: [wait(minutes: 40, on: try date(2026, 9, 24, 12))])

        let metrics = calculator.metrics(of: [busy, quiet], in: month)

        #expect(metrics.pickupWaitSampleCount == 6)
        #expect(metrics.medianPickupWait == 10 * 60.0)
        #expect(metrics.medianPickupWait != 25 * 60.0)
    }

    @Test("A range's pickup median is the middle of its individual waits too")
    func rangePickupMedianUsesIndividualSamples() throws {
        let period = try range(date(2026, 9, 1), date(2026, 9, 30))
        let busy = try record(
            startedAt: date(2026, 9, 3),
            waits: try (0..<5).map { _ in wait(minutes: 10, on: try date(2026, 9, 3, 12)) }
        )
        let quiet = try record(startedAt: date(2026, 9, 24), waits: [wait(minutes: 40, on: try date(2026, 9, 24, 12))])

        let metrics = calculator.metrics(of: [busy, quiet], in: period)

        #expect(metrics.pickupWaitSampleCount == 6)
        #expect(metrics.medianPickupWait == 10 * 60.0)
    }

    // MARK: Coverage survives the larger period

    @Test("A month with missing amounts reports a subtotal and the shifts behind it")
    func monthCoverageStaysVisible() throws {
        let month = try september()
        let records = [
            try record(startedAt: date(2026, 9, 2), earnings: try money("342.25")),
            try record(startedAt: date(2026, 9, 9), earnings: try money("500.00")),
            try record(startedAt: date(2026, 9, 16), earnings: nil),
            try record(startedAt: date(2026, 9, 23), earnings: nil)
        ]

        let metrics = calculator.metrics(of: records, in: month)

        #expect(metrics.recordedGrossEarnings == (try money("842.25")))
        #expect(metrics.earningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 4))
        #expect(metrics.earningsCoverageStatement == "2 of 4 shifts")
        #expect(metrics.earningsStatement(locale: Locale(identifier: "en_US")) == "$842.25 recorded")
    }

    /// The rule that matters most once a period is long enough to hold dozens of
    /// shifts: two shifts with no amount are two shifts the driver has not told
    /// the app about, not two shifts that paid nothing.
    @Test("A missing amount is still excluded rather than counted as zero over a month")
    func missingAmountIsNotZeroOverAMonth() throws {
        let month = try september()
        let missing = calculator.metrics(
            of: [
                try record(startedAt: date(2026, 9, 2), earnings: try money("100.00")),
                try record(startedAt: date(2026, 9, 20), earnings: nil)
            ],
            in: month
        )
        let explicitZero = calculator.metrics(
            of: [
                try record(startedAt: date(2026, 9, 2), earnings: try money("100.00")),
                try record(startedAt: date(2026, 9, 20), earnings: .zero)
            ],
            in: month
        )

        // The same amount, and a different claim about it.
        #expect(missing.recordedGrossEarnings == explicitZero.recordedGrossEarnings)
        #expect(missing.earningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
        #expect(explicitZero.earningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
    }

    @Test("A range's per-delivery amounts stay out of its headline gross")
    func rangeDeliveryEarningsStaySeparate() throws {
        let period = try range(date(2026, 9, 1), date(2026, 9, 30))
        let records = [
            try record(
                startedAt: date(2026, 9, 2),
                earnings: try money("120.00"),
                deliveryEarnings: [try money("9.50"), try money("14.75")],
                terminalDeliveries: 4
            ),
            try record(startedAt: date(2026, 9, 12), earnings: nil, deliveryEarnings: [try money("8.00")], terminalDeliveries: 2)
        ]

        let metrics = calculator.metrics(of: records, in: period)

        #expect(metrics.recordedGrossEarnings == (try money("120.00")))
        #expect(metrics.recordedDeliveryEarnings == (try money("32.25")))
        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 3, eligibleCount: 6))
        // No reconciliation of the two, at any period length.
        let spoken = metrics.spokenDeliveryEarningsStatement(locale: Locale(identifier: "en_US")) ?? ""
        for claim in ["missing", "shortfall", "unallocated", "discrepancy"] {
            #expect(!spoken.lowercased().contains(claim), "Two records are not a gap: \(spoken)")
        }
    }

    @Test("A month's mileage keeps its partial routes visible and leaves the unmeasured out")
    func monthMileageCoverageIsUnchanged() throws {
        let month = try september()
        let records = [
            try record(startedAt: date(2026, 9, 2), route: route(miles: 20)),
            try record(startedAt: date(2026, 9, 9), route: route(miles: 30, gapCount: 2)),
            try record(startedAt: date(2026, 9, 16), route: unmeasurableRoute())
        ]

        let metrics = calculator.metrics(of: records, in: month)

        #expect(abs(metrics.recordedDistance.miles - 50) < 0.0001)
        #expect(metrics.routeCoverage.measuredShiftCount == 2)
        #expect(metrics.routeCoverage.partialShiftCount == 1)
        #expect(metrics.routeCoverage.unmeasurableShiftCount == 1)
        #expect(metrics.routeCoverage.totalShiftCount == 3)
    }

    @Test("A month's active time is the sum of each shift's own union")
    func monthActiveTimeSumsPerShiftUnions() throws {
        let month = try september()
        let records = [
            // Two deliveries overlapping inside one shift, already counted once.
            try record(startedAt: date(2026, 9, 2), elapsed: 4 * 3600, active: activeTime(2 * 3600, merged: 2)),
            try record(startedAt: date(2026, 9, 20), elapsed: 4 * 3600, active: activeTime(3600))
        ]

        let metrics = calculator.metrics(of: records, in: month)

        #expect(metrics.deliveryActiveDuration == 3 * 3600.0)
        #expect(metrics.nonDeliveryDuration == 5 * 3600.0)
        #expect(metrics.deliveryActiveCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
    }

    @Test("A month's rates use the shifts carrying both halves and no others")
    func monthRatesUsePairedSubsets() throws {
        let month = try september()
        let records = [
            try record(startedAt: date(2026, 9, 2), earnings: try money("60.00"), route: route(miles: 20)),
            // An amount with no measurable route: it contributes to neither half
            // of the per-mile rate.
            try record(startedAt: date(2026, 9, 12), earnings: try money("500.00"), route: unmeasurableRoute()),
            // A route with no amount: likewise.
            try record(startedAt: date(2026, 9, 22), earnings: nil, route: route(miles: 400))
        ]

        let metrics = calculator.metrics(of: records, in: month)

        #expect(metrics.grossPerRecordedMile.amount == (try money("3.00")))
        #expect(metrics.grossPerRecordedMile.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
        #expect(metrics.rateBasisStatement(.perRecordedMile).contains("1 of 3"))
    }

    // MARK: Which shifts a month or range holds

    @Test("A running shift is excluded from a range that contains today")
    func runningShiftIsExcludedFromARange() throws {
        let period = try range(date(2026, 9, 1), date(2026, 9, 30))
        let records = [
            try record(startedAt: date(2026, 9, 2), earnings: try money("100.00")),
            try record(startedAt: date(2026, 9, 30, 8), isCompleted: false, elapsed: 3600, earnings: try money("40.00"))
        ]

        let metrics = calculator.metrics(of: records, in: period)

        #expect(metrics.completedShiftCount == 1)
        #expect(metrics.recordedGrossEarnings == (try money("100.00")))
    }

    /// The overnight shift, whole, on one side of the boundary and absent from
    /// the other. Nothing is split: not the money, not the miles, not the hours.
    @Test("A shift crossing into October is counted whole in September and not at all in October")
    func overnightShiftIsNotSplitAcrossMonths() throws {
        let september = try september()
        let october = try #require(ReportingPeriod(unit: .month, containing: try date(2026, 10, 15), calendar: calendar))
        let overnight = try record(
            startedAt: date(2026, 9, 30, 23),
            elapsed: 3 * 3600,
            earnings: try money("75.00"),
            route: route(miles: 18),
            deliveries: DeliverySummary(completed: 4, cancelled: 0)
        )

        let inSeptember = calculator.metrics(of: [overnight], in: september)
        let inOctober = calculator.metrics(of: [overnight], in: october)

        #expect(inSeptember.completedShiftCount == 1)
        #expect(inSeptember.recordedGrossEarnings == (try money("75.00")))
        #expect(inSeptember.elapsedDuration == 3 * 3600.0)
        #expect(abs(inSeptember.recordedDistance.miles - 18) < 0.0001)
        #expect(inSeptember.deliverySummary.completed == 4)

        #expect(inOctober.isEmpty)
        #expect(inOctober.completedShiftCount == 0)
    }

    @Test("A shift starting on the exclusive end of a range is outside it")
    func shiftAtTheExclusiveEndIsOutside() throws {
        let period = try range(date(2026, 9, 1), date(2026, 9, 7))
        let atStart = try record(startedAt: #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        let atEnd = try record(startedAt: #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))))

        let metrics = calculator.metrics(of: [atStart, atEnd], in: period)

        #expect(metrics.completedShiftCount == 1)
    }

    @Test("An empty month and an empty range say so rather than showing zeroes")
    func emptyPeriodsSayWhatTheyAre() throws {
        let month = calculator.metrics(of: [], in: try september())
        let period = calculator.metrics(of: [], in: try range(date(2026, 9, 1), date(2026, 9, 7)))

        #expect(month.isEmpty)
        #expect(month.emptyStatement == "No completed shifts recorded this month.")
        #expect(month.recordedGrossEarnings == nil)

        #expect(period.isEmpty)
        #expect(period.emptyStatement == "No completed shifts recorded in this range.")
        #expect(period.recordedGrossEarnings == nil)
    }

    /// The same records, the same calculator, the same answer. A month that
    /// happens to cover exactly the days a range covers cannot disagree with it.
    @Test("A range covering a whole month agrees with the month, figure for figure")
    func aRangeOverAWholeMonthMatchesTheMonth() throws {
        let month = try september()
        let equivalent = try range(date(2026, 9, 1), date(2026, 9, 30))
        let records = [
            try record(startedAt: date(2026, 9, 2), earnings: try money("120.00"), route: route(miles: 30)),
            try record(startedAt: date(2026, 9, 18), earnings: nil, route: route(miles: 12, gapCount: 1)),
            try record(startedAt: date(2026, 9, 30, 22), earnings: try money("80.00"))
        ]

        let byMonth = calculator.metrics(of: records, in: month)
        let byRange = calculator.metrics(of: records, in: equivalent)

        #expect(month.start == equivalent.start)
        #expect(month.end == equivalent.end)
        #expect(byMonth.completedShiftCount == byRange.completedShiftCount)
        #expect(byMonth.recordedGrossEarnings == byRange.recordedGrossEarnings)
        #expect(byMonth.earningsCoverage == byRange.earningsCoverage)
        #expect(byMonth.recordedDistance == byRange.recordedDistance)
        #expect(byMonth.routeCoverage == byRange.routeCoverage)
        #expect(byMonth.grossPerElapsedHour == byRange.grossPerElapsedHour)
        #expect(byMonth.grossPerRecordedMile == byRange.grossPerRecordedMile)
    }
}
