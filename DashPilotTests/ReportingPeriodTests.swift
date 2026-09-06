import Foundation
import Testing
@testable import DashPilot

/// The calendar rules a period summary rests on.
///
/// Every test injects its own `Calendar` with an explicit time zone and first
/// weekday, so nothing here depends on the machine it runs on or on when it is
/// run. Dates are built from components rather than from epoch offsets, because
/// the whole point of these rules is that a day is not a fixed number of
/// seconds.
@Suite("Reporting periods")
struct ReportingPeriodTests {
    /// A calendar with everything that changes an answer pinned.
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

    private func day(_ date: Date, in calendar: Calendar) throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .day, containing: date, calendar: calendar))
    }

    private func week(_ date: Date, in calendar: Calendar) throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .week, containing: date, calendar: calendar))
    }

    // MARK: Membership

    @Test("A shift that started during the day belongs to that day")
    func dayContainsAShiftThatStartedInIt() throws {
        let calendar = try calendar()
        let period = try day(date(2026, 3, 10, 12, 0, in: calendar), in: calendar)

        #expect(period.contains(try date(2026, 3, 10, 0, 0, in: calendar)))
        #expect(period.contains(try date(2026, 3, 10, 9, 30, in: calendar)))
        #expect(period.contains(try date(2026, 3, 10, 23, 59, in: calendar)))
    }

    @Test("A day excludes the days either side of it")
    func dayExcludesTheNeighbouringDays() throws {
        let calendar = try calendar()
        let period = try day(date(2026, 3, 10, 12, 0, in: calendar), in: calendar)

        #expect(!period.contains(try date(2026, 3, 9, 23, 59, in: calendar)))
        #expect(!period.contains(try date(2026, 3, 11, 0, 0, in: calendar)))
    }

    @Test("Midnight belongs to the day that is beginning, and to that day only")
    func midnightBelongsToOneDay() throws {
        let calendar = try calendar()
        let midnight = try date(2026, 3, 11, 0, 0, in: calendar)

        #expect(try day(date(2026, 3, 11, 12, 0, in: calendar), in: calendar).contains(midnight))
        #expect(!(try day(date(2026, 3, 10, 12, 0, in: calendar), in: calendar).contains(midnight)))
    }

    /// The membership rule for the whole feature: a shift is assigned by where
    /// it *started*, and is never split across the boundary it crossed.
    @Test("A shift crossing midnight belongs to the day it started on")
    func crossMidnightShiftBelongsToItsStartDay() throws {
        let calendar = try calendar()
        let startedAt = try date(2026, 3, 10, 22, 0, in: calendar)

        #expect(try day(date(2026, 3, 10, 12, 0, in: calendar), in: calendar).contains(startedAt))
        #expect(!(try day(date(2026, 3, 11, 12, 0, in: calendar), in: calendar).contains(startedAt)))
    }

    @Test("The time zone decides which day a moment belongs to")
    func timeZoneDecidesTheDay() throws {
        // 03:00 UTC on 11 March is 22:00 on 10 March in New York.
        let utc = try calendar(timeZone: "UTC")
        let newYork = try calendar()
        let moment = try date(2026, 3, 11, 3, 0, in: utc)

        #expect(try day(date(2026, 3, 11, 12, 0, in: utc), in: utc).contains(moment))
        #expect(try day(date(2026, 3, 10, 12, 0, in: newYork), in: newYork).contains(moment))
    }

    // MARK: Daylight saving

    @Test("The day the clocks go forward is 23 hours, not 24")
    func springForwardDayIsShort() throws {
        let calendar = try calendar()
        let period = try day(date(2026, 3, 8, 12, 0, in: calendar), in: calendar)

        #expect(period.end.timeIntervalSince(period.start) == 23 * 3600)
    }

    @Test("The day the clocks go back is 25 hours, not 24")
    func fallBackDayIsLong() throws {
        let calendar = try calendar()
        let period = try day(date(2026, 11, 1, 12, 0, in: calendar), in: calendar)

        #expect(period.end.timeIntervalSince(period.start) == 25 * 3600)
    }

    @Test("A shift started in the repeated hour still belongs to the fall-back day")
    func fallBackDayContainsItsWholeSpan() throws {
        let calendar = try calendar()
        let period = try day(date(2026, 11, 1, 12, 0, in: calendar), in: calendar)

        // Every hour of a 25-hour day, walked from its own start rather than
        // from an assumed midnight.
        for hour in 0..<25 {
            #expect(period.contains(period.start.addingTimeInterval(Double(hour) * 3600)))
        }
        #expect(!period.contains(period.start.addingTimeInterval(25 * 3600)))
    }

    @Test("Stepping back from the day after a transition lands on the transition day")
    func stepsAcrossADaylightSavingTransition() throws {
        let calendar = try calendar()
        let after = try day(date(2026, 3, 9, 12, 0, in: calendar), in: calendar)
        let transition = try day(date(2026, 3, 8, 12, 0, in: calendar), in: calendar)

        #expect(after.previous(using: calendar) == transition)
        #expect(transition.next(using: calendar) == after)
    }

    @Test("The week containing a transition is 167 hours, and still one week")
    func weekContainingATransitionIsStillOneWeek() throws {
        let calendar = try calendar()
        let period = try week(date(2026, 3, 8, 12, 0, in: calendar), in: calendar)

        #expect(period.end.timeIntervalSince(period.start) == 167 * 3600)
        #expect(period.contains(try date(2026, 3, 8, 12, 0, in: calendar)))
        #expect(period.contains(try date(2026, 3, 14, 23, 0, in: calendar)))
    }

    // MARK: Weeks

    @Test("A week starts on the calendar's own first weekday")
    func weekRespectsTheFirstWeekday() throws {
        let sundayFirst = try calendar(firstWeekday: 1)
        let mondayFirst = try calendar(firstWeekday: 2)
        // Wednesday, 11 March 2026.
        let midweek = try date(2026, 3, 11, 12, 0, in: sundayFirst)

        let sundayWeek = try week(midweek, in: sundayFirst)
        let mondayWeek = try week(midweek, in: mondayFirst)

        #expect(sundayWeek.start == (try date(2026, 3, 8, 0, 0, in: sundayFirst)))
        #expect(mondayWeek.start == (try date(2026, 3, 9, 0, 0, in: mondayFirst)))
        #expect(sundayWeek != mondayWeek)
    }

    @Test("A shift on the first day of the week is in that week, not the one before")
    func weekBoundaryIsHalfOpen() throws {
        let calendar = try calendar()
        let sunday = try date(2026, 3, 8, 0, 0, in: calendar)

        #expect(try week(date(2026, 3, 11, 12, 0, in: calendar), in: calendar).contains(sunday))
        #expect(!(try week(date(2026, 3, 4, 12, 0, in: calendar), in: calendar).contains(sunday)))
    }

    @Test("A week spanning a month boundary is one week")
    func weekSpansAMonthBoundary() throws {
        let calendar = try calendar()
        let period = try week(date(2026, 3, 31, 12, 0, in: calendar), in: calendar)

        #expect(period.contains(try date(2026, 3, 31, 20, 0, in: calendar)))
        #expect(period.contains(try date(2026, 4, 1, 8, 0, in: calendar)))
    }

    @Test("A week spanning a year boundary is one week")
    func weekSpansAYearBoundary() throws {
        let calendar = try calendar()
        let period = try week(date(2026, 12, 31, 12, 0, in: calendar), in: calendar)

        #expect(period.contains(try date(2026, 12, 31, 20, 0, in: calendar)))
        #expect(period.contains(try date(2027, 1, 1, 8, 0, in: calendar)))
    }

    // MARK: Stepping

    @Test("Stepping forward and back returns to the same period")
    func stepsAreInverses() throws {
        let calendar = try calendar()

        for unit in ReportingPeriodUnit.calendarUnits {
            let period = try #require(
                ReportingPeriod(unit: unit, containing: try date(2026, 6, 17, 12, 0, in: calendar), calendar: calendar)
            )
            #expect(period.next(using: calendar)?.previous(using: calendar) == period)
            #expect(period.previous(using: calendar)?.next(using: calendar) == period)
        }
    }

    @Test("Consecutive periods meet exactly, with no gap and no overlap")
    func consecutivePeriodsMeet() throws {
        let calendar = try calendar()

        for unit in ReportingPeriodUnit.calendarUnits {
            let period = try #require(
                // The week of a daylight saving transition, so the arithmetic is
                // exercised where a fixed-length assumption would break.
                ReportingPeriod(unit: unit, containing: try date(2026, 11, 1, 12, 0, in: calendar), calendar: calendar)
            )
            let next = try #require(period.next(using: calendar))
            #expect(period.end == next.start)
        }
    }

    // MARK: Wording

    @Test("The period the driver is in is named for what it is to them")
    func namesTheCurrentPeriod() throws {
        let calendar = try calendar()
        let now = try date(2026, 6, 17, 14, 0, in: calendar)

        #expect(try day(now, in: calendar).title(asOf: now, calendar: calendar) == "Today")
        #expect(try week(now, in: calendar).title(asOf: now, calendar: calendar) == "This Week")
    }

    @Test("The day before today is named Yesterday")
    func namesYesterday() throws {
        let calendar = try calendar()
        let now = try date(2026, 6, 17, 14, 0, in: calendar)
        let yesterday = try #require(day(now, in: calendar).previous(using: calendar))

        #expect(yesterday.title(asOf: now, calendar: calendar) == "Yesterday")
    }

    @Test("An older period is named by its dates rather than relatively")
    func namesOlderPeriodsByDate() throws {
        let calendar = try calendar()
        let now = try date(2026, 6, 17, 14, 0, in: calendar)
        let older = try day(date(2026, 6, 10, 12, 0, in: calendar), in: calendar)
        let olderWeek = try week(date(2026, 6, 3, 12, 0, in: calendar), in: calendar)

        let dayTitle = older.title(asOf: now, calendar: calendar)
        #expect(dayTitle != "Today" && dayTitle != "Yesterday")
        #expect(!dayTitle.isEmpty)

        let weekTitle = olderWeek.title(asOf: now, calendar: calendar)
        #expect(weekTitle != "This Week")
        #expect(weekTitle.hasPrefix("Week of "))
    }

    /// A week must never be described as finished. `This Week` is a name; "the
    /// completed week" would be a claim about records that are still arriving.
    @Test("A current week is named, never described as complete or final")
    func doesNotCallTheCurrentWeekComplete() throws {
        let calendar = try calendar()
        let now = try date(2026, 6, 17, 14, 0, in: calendar)
        let period = try week(now, in: calendar)

        let spoken = period.spokenTitle(asOf: now, calendar: calendar).lowercased()
        for claim in ["complete", "final", "total week", "projected", "forecast"] {
            #expect(!spoken.contains(claim), "A period title must claim nothing about completeness: \(spoken)")
        }
    }

    @Test("A week says which dates it covers, so its name is never the only clue")
    func weekStatesItsRange() throws {
        let calendar = try calendar()
        let now = try date(2026, 6, 17, 14, 0, in: calendar)
        let period = try week(now, in: calendar)

        let range = period.rangeStatement(calendar: calendar)
        #expect(range.contains("14") && range.contains("20"), "A week's range names both ends: \(range)")
        #expect(period.spokenTitle(asOf: now, calendar: calendar).contains(range))
    }

    /// The one dependency these strings must not have on the machine running
    /// them.
    ///
    /// A period's boundaries are instants its own calendar computed, and the
    /// last one is 23:59:59 on its last day. Read back in a time zone further
    /// east, that instant is already the following day, so wording left on the
    /// ambient zone names a date the period does not contain: a September month
    /// ends on 1 October, and a one-day range becomes a pair. A test pinning
    /// only the zone the machine is already in cannot see that, which is why
    /// several zones either side of any plausible one are checked here.
    @Test("Dates are written in the period's own time zone, not the machine's")
    func datesAreWrittenInThePeriodsOwnTimeZone() throws {
        let locale = Locale(identifier: "en_US")

        for zone in ["Pacific/Kiritimati", "Asia/Tokyo", "Europe/London", "America/New_York", "Pacific/Midway"] {
            let calendar = try calendar(timeZone: zone)
            let now = try date(2026, 6, 17, 14, 0, in: calendar)
            let later = try date(2026, 9, 14, 12, 0, in: calendar)

            let weekDates = try week(now, in: calendar).rangeStatement(calendar: calendar, locale: locale)
            #expect(weekDates.hasPrefix("Jun 14"), "A week starts on its own first day in \(zone): \(weekDates)")
            #expect(weekDates.hasSuffix("20, 2026"), "…and ends on its own last day: \(weekDates)")
            #expect(!weekDates.contains("21"), "…never the boundary after it: \(weekDates)")

            let month = try #require(ReportingPeriod(unit: .month, containing: now, calendar: calendar))
            let monthDates = month.rangeStatement(calendar: calendar, locale: locale)
            #expect(monthDates.hasPrefix("Jun 1"), "A month starts on its own first day in \(zone): \(monthDates)")
            #expect(monthDates.hasSuffix("30, 2026"), "…and ends on its own last day: \(monthDates)")
            #expect(!monthDates.contains("Jul"), "…never in the month after it: \(monthDates)")
            #expect(month.title(asOf: later, calendar: calendar, locale: locale) == "June 2026")

            let oneDay = try #require(ReportingPeriod(from: now, through: now, calendar: calendar))
                .title(asOf: now, calendar: calendar, locale: locale)
            #expect(oneDay.hasPrefix("Jun 17"), "A one-day range is one date in \(zone): \(oneDay)")
            #expect(!oneDay.contains("18"), "…never a pair: \(oneDay)")

            let dayTitle = try day(now, in: calendar).title(asOf: later, calendar: calendar, locale: locale)
            #expect(dayTitle == "Wed, Jun 17", "A day is named for its own date in \(zone): \(dayTitle)")
        }
    }
}

/// The two counts that keep an aggregate from being read as a total.
@Suite("Metric coverage")
struct MetricCoverageTests {
    @Test("Coverage is complete only when every eligible record contributed")
    func completenessNeedsEveryRecord() {
        #expect(MetricCoverage(contributingCount: 4, eligibleCount: 4).isComplete)
        #expect(!MetricCoverage(contributingCount: 3, eligibleCount: 4).isComplete)
    }

    /// Nothing eligible is not the same as everything covered. A caller reading
    /// "complete" over no records would be reading a claim about data that does
    /// not exist.
    @Test("An empty period is not complete coverage")
    func emptyCoverageIsNotComplete() {
        #expect(!MetricCoverage.none.isComplete)
        #expect(!MetricCoverage.none.hasContributors)
        #expect(MetricCoverage.none.missingCount == 0)
    }

    @Test("Coverage counts what is missing without turning it into a value")
    func countsWhatIsMissing() {
        let coverage = MetricCoverage(contributingCount: 3, eligibleCount: 4)

        #expect(coverage.missingCount == 1)
        #expect(coverage.hasContributors)
    }

    @Test("The written form always names both counts")
    func statementNamesBothCounts() {
        #expect(MetricCoverage(contributingCount: 3, eligibleCount: 4).statement() == "3 of 4 shifts")
        #expect(MetricCoverage(contributingCount: 1, eligibleCount: 1).statement() == "1 of 1 shift")
    }

    /// Complete coverage keeps the same shape rather than dropping the
    /// denominator: the caveat must not be the thing that quietly disappears
    /// exactly when a figure looks most like a total.
    @Test("Complete coverage still states its denominator")
    func completeCoverageStillStatesTheDenominator() {
        #expect(MetricCoverage(contributingCount: 4, eligibleCount: 4).statement() == "4 of 4 shifts")
    }

    @Test("The spoken form is a phrase a sentence can end with")
    func spokenFormIsAPhrase() {
        let coverage = MetricCoverage(contributingCount: 3, eligibleCount: 4)

        #expect(coverage.spokenStatement() == "across 3 of 4 completed shifts")
        #expect(
            coverage.spokenStatement(noun: "delivery", pluralNoun: "deliveries")
                == "across 3 of 4 deliveries"
        )
    }

    @Test("The counted noun is the call site's to name")
    func nounIsSuppliedByTheCaller() {
        let coverage = MetricCoverage(contributingCount: 2, eligibleCount: 3)

        #expect(
            coverage.statement(noun: "shift with both earnings and a measurable route",
                               pluralNoun: "shifts with both earnings and a measurable route")
                == "2 of 3 shifts with both earnings and a measurable route"
        )
    }
}
