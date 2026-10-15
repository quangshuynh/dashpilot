import Foundation
import Testing
@testable import DashPilot

@Suite("Universal Monday reporting")
struct MondayReportingTests {
    @Test(arguments: ["America/New_York", "Pacific/Auckland", "Asia/Tokyo", "UTC"], [1, 2])
    func octoberWeeks(zone: String, firstWeekday: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = firstWeekday
        let locale = Locale(identifier: "en_US")
        for monday in [5, 12, 19] {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: monday, hour: 12)))
            let period = try #require(ReportingPeriod(unit: .week, containing: date, calendar: calendar))
            #expect(calendar.component(.day, from: period.start) == monday)
            #expect(calendar.component(.day, from: period.lastInstant) == monday + 6)
            #expect(calendar.component(.weekday, from: period.start) == 2)
            #expect(period == HistoryWeek(containing: date, calendar: calendar)?.period)
            let displayed = period.rangeStatement(calendar: calendar, locale: locale)
            // ICU can use a thin space around the range dash; date content is exact.
            let compact = displayed.filter { !$0.isWhitespace }
            #expect(compact == "Oct\(monday)–\(monday + 6),2026")
            #expect(period.next(using: calendar)?.previous(using: calendar) == period)
            #expect(period.precedingEquivalent(using: calendar) == period.previous(using: calendar))
        }
    }

    @Test(arguments: [(2026, 3, 8, 167), (2026, 11, 1, 169), (2024, 2, 29, 168), (2026, 12, 31, 168)])
    func calendarEdges(_ sample: (Int, Int, Int, Int)) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        let date = try #require(calendar.date(from: DateComponents(year: sample.0, month: sample.1, day: sample.2, hour: 12)))
        let period = try #require(ReportingPeriod(unit: .week, containing: date, calendar: calendar))
        #expect(period.dayCount(using: calendar) == 7)
        #expect(period.end.timeIntervalSince(period.start) == Double(sample.3 * 3600))
        #expect(calendar.component(.weekday, from: period.lastInstant) == 1)
        #expect(!period.contains(period.end))
    }
}
