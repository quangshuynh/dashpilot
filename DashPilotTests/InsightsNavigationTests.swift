import Foundation
import Testing
@testable import DashPilot

/// Which eight Monday-Sunday weeks Insights shows, and which one is selected.
///
/// The navigation is decided from the calendar alone, never from loaded data,
/// so it cannot be stranded by a load in flight, an empty range or a refresh.
/// Every date is fixed, in a time zone with daylight saving.
@Suite("Insights week navigation")
struct InsightsNavigationTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private var calendar: Calendar { Self.calendar }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Wednesday, November 4, 2026: three days after daylight saving ended.
    private var now: Date { date(2026, 11, 4) }

    private func week(containing date: Date) -> ReportingPeriod {
        ReportingPeriod(unit: .week, containing: date, calendar: calendar)!
    }

    private func selected(_ navigation: InsightsNavigation, asOf date: Date? = nil) -> ReportingPeriod? {
        navigation.selectedPeriod(asOf: date ?? now, calendar: calendar)
    }

    private func window(_ navigation: InsightsNavigation, asOf date: Date? = nil) -> InsightsWindow {
        navigation.window(asOf: date ?? now, calendar: calendar)!
    }

    // MARK: Opening

    @Test("Opening on the current week selects it, with nothing later to go to")
    func opensOnTheCurrentWeek() {
        let navigation = InsightsNavigation(initialPeriod: week(containing: now), asOf: now)
        #expect(selected(navigation) == week(containing: now))
        #expect(window(navigation).weeks.last == week(containing: now))
        #expect(!navigation.canSelectNext(asOf: now, calendar: calendar))
        #expect(navigation.canSelectPrevious(asOf: now, calendar: calendar))
        #expect(!navigation.canShowLatestWeeks(asOf: now, calendar: calendar))
    }

    @Test("Opening from a historical Money week selects that week")
    func opensOnAHistoricalWeek() {
        let historical = week(containing: date(2026, 9, 9))
        let navigation = InsightsNavigation(initialPeriod: historical, asOf: now)
        #expect(selected(navigation) == historical)
        #expect(window(navigation).weeks.last == historical)
        #expect(navigation.canShowLatestWeeks(asOf: now, calendar: calendar))
    }

    // MARK: Earlier and Latest

    @Test("Earlier Weeks moves back eight weeks each time and selects the adjacent week")
    func earlierWeeksMovesBackward() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        let latest = window(navigation)

        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        let earlier = window(navigation)
        #expect(earlier.weeks.last == latest.precedingWeek)
        #expect(selected(navigation) == latest.precedingWeek)
        #expect(navigation.canShowLatestWeeks(asOf: now, calendar: calendar))
        #expect(navigation.canSelectNext(asOf: now, calendar: calendar), "Later weeks exist")

        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        #expect(window(navigation).weeks.last == earlier.precedingWeek)
    }

    @Test("Latest Weeks returns to the current week from any distance")
    func latestWeeksReturnsForward() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        for _ in 0..<5 { navigation.showEarlierWeeks(asOf: now, calendar: calendar) }

        navigation.showLatestWeeks()
        #expect(window(navigation).weeks.last == week(containing: now))
        #expect(selected(navigation) == week(containing: now))
        #expect(!navigation.canShowLatestWeeks(asOf: now, calendar: calendar))
    }

    // MARK: Previous and Next

    @Test("Previous Week visits every week of the window, then continues into earlier weeks")
    func previousWeekCrossesTheWindow() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        let latest = window(navigation)

        for expected in latest.weeks.reversed().dropFirst() {
            navigation.selectPrevious(asOf: now, calendar: calendar)
            #expect(selected(navigation) == expected)
            #expect(window(navigation) == latest, "Stepping inside the window does not move it")
        }

        #expect(navigation.canSelectPrevious(asOf: now, calendar: calendar), "The first week is not a dead end")
        navigation.selectPrevious(asOf: now, calendar: calendar)
        #expect(selected(navigation) == latest.precedingWeek)
        #expect(window(navigation).weeks.last == latest.precedingWeek)
    }

    @Test("Next Week returns from earlier weeks to the current week and stops there")
    func nextWeekReturnsForward() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        var visited: [ReportingPeriod] = [selected(navigation)!]

        while navigation.canSelectNext(asOf: now, calendar: calendar) {
            navigation.selectNext(asOf: now, calendar: calendar)
            visited.append(selected(navigation)!)
            #expect(visited.count <= 17, "Next always reaches the current week")
            if visited.count > 17 { break }
        }

        #expect(visited.last == week(containing: now))
        #expect(visited.count == 17, "Every week from the earlier window's last to today, once")
        for (earlier, later) in zip(visited, visited.dropFirst()) {
            #expect(earlier.end == later.start, "No week is skipped or repeated")
        }
        #expect(!navigation.canShowLatestWeeks(asOf: now, calendar: calendar), "Reaching today is the latest window")
    }

    // MARK: Selection that has to survive

    @Test("A chosen week survives the current week ending while the latest weeks are shown")
    func selectionSurvivesTheWeekRollingOver() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        navigation.selectPrevious(asOf: now, calendar: calendar)
        navigation.selectPrevious(asOf: now, calendar: calendar)
        let chosen = selected(navigation)

        let nextMonday = date(2026, 11, 9, hour: 8)
        #expect(selected(navigation, asOf: nextMonday) == chosen, "Refreshing on a new week keeps the chosen week")
        #expect(window(navigation, asOf: nextMonday).weeks.last == week(containing: nextMonday))
    }

    @Test("A selected week outside the window resolves to the nearest week, not the newest")
    func outOfWindowSelectionResolvesToNearest() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        let oldest = window(navigation).weeks.first!
        navigation.select(oldest.start, asOf: now, calendar: calendar)

        // Nine weeks later the chosen week has left the latest window.
        let later = calendar.date(byAdding: .weekOfYear, value: 9, to: now)!
        #expect(selected(navigation, asOf: later) == window(navigation, asOf: later).weeks.first)
    }

    @Test("Selecting a week from the menu selects exactly that week")
    func menuSelectionIsExact() {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        let target = window(navigation).weeks[2]
        navigation.select(target.start, asOf: now, calendar: calendar)
        #expect(selected(navigation) == target)

        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        navigation.showLatestWeeks()
        navigation.select(target.start, asOf: now, calendar: calendar)
        #expect(selected(navigation) == target, "Still exact after the window moved and came back")
    }

    // MARK: Calendar boundaries

    @Test("Navigation across months, a year end and daylight saving keeps Monday-Sunday weeks contiguous")
    func calendarBoundaries() {
        let january = date(2027, 1, 6)
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: january)
        var walked: [ReportingPeriod] = [selected(navigation, asOf: january)!]
        // Back through December, the year end, November's DST change, October
        // and into September: twenty weeks crosses every one of them.
        for _ in 0..<20 {
            navigation.selectPrevious(asOf: january, calendar: calendar)
            walked.append(selected(navigation, asOf: january)!)
        }

        for period in walked {
            #expect(calendar.component(.weekday, from: period.start) == 2, "\(period.start) is a Monday")
            #expect(calendar.component(.hour, from: period.start) == 0)
            #expect(period.dayCount(using: calendar) == 7)
        }
        for (later, earlier) in zip(walked, walked.dropFirst()) {
            #expect(earlier.end == later.start)
        }
        #expect(walked.contains { calendar.component(.year, from: $0.start) == 2026 })
        #expect(walked.contains { $0.contains(date(2026, 11, 1)) }, "The DST week is visited")
    }

    // MARK: Loaded data

    @Test("A series loaded for another window is never shown for this one")
    func staleSeriesIsNotShown() throws {
        var navigation = InsightsNavigation(initialPeriod: nil, asOf: now)
        let latest = window(navigation)
        let series = try InsightsSeriesBuilder.build(shifts: [], expenses: [], window: latest)
        #expect(series.showing(latest) == series)

        navigation.showEarlierWeeks(asOf: now, calendar: calendar)
        #expect(series.showing(window(navigation)) == nil, "A late result for the old window cannot replace the new one")
    }

    // MARK: Axis labels

    @Test("The chart labels four alternating weeks, ending with the newest")
    func axisLabelsAlternateAndIncludeTheNewest() {
        let weeks = window(InsightsNavigation(initialPeriod: nil, asOf: now)).weeks
        let labels = InsightsAxisLabels.labels(for: weeks, calendar: calendar, locale: Locale(identifier: "en_US"))

        #expect(labels.count == 4)
        #expect(labels.last?.week == weeks.last)
        #expect(labels.map(\.week) == [weeks[1], weeks[3], weeks[5], weeks[7]])
    }

    @Test("A label names its month only where the month changes, including across a year end")
    func axisLabelsAreShortAndUnambiguous() {
        let january = date(2027, 1, 20)
        let weeks = window(InsightsNavigation(initialPeriod: nil, asOf: january), asOf: january).weeks
        let labels = InsightsAxisLabels.labels(for: weeks, calendar: calendar, locale: Locale(identifier: "en_US"))
            .map(\.label)

        // Weeks starting Nov 30 to Jan 18; labelled: Dec 7, Dec 21, Jan 4, Jan 18.
        #expect(labels == ["Dec 7", "21", "Jan 4", "18"])
        #expect(labels.allSatisfy { $0.count <= 6 })
    }
}
