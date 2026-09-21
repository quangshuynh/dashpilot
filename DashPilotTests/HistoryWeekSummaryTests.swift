import Foundation
import Testing
@testable import DashPilot

/// What a week in History adds up to above its list of shifts.
///
/// **The claim under test is mostly that nothing new was defined.** Every figure
/// here is `PeriodMetricsCalculator` over the week's own `ReportingPeriod`, so
/// several of these tests derive the same week twice — once through
/// ``HistoryWeekSummary`` and once through the calculator directly — and assert
/// the two agree. A weekly total that drifted from the period summary's would be
/// the interface disagreeing with itself about a driver's own week.
///
/// The calendar is fixed to UTC with a Sunday first weekday, so that
/// ``HistoryWeek``'s Monday rule is exercised rather than inherited from the
/// machine the suite runs on.
@Suite("History week summaries")
struct HistoryWeekSummaryTests {
    private let calendar: Calendar
    private let calculator = PeriodMetricsCalculator()

    /// Monday, 14 September 2026, midnight UTC. The fixture week runs from here
    /// to the end of Sunday the 20th.
    private let monday: Date

    private static let metresPerMile = 1609.344

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // Deliberately *not* Monday: History pins its own week to Monday, and a
        // calendar that already starts there would hide it.
        calendar.firstWeekday = 1
        self.calendar = calendar

        monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
    }

    // MARK: Fixtures

    private func week(containing date: Date) throws -> HistoryWeek {
        try #require(HistoryWeek(containing: date, calendar: calendar))
    }

    private var fixtureWeek: HistoryWeek {
        get throws { try week(containing: monday) }
    }

    private func at(day: Int, hour: Double) -> Date {
        monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
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

    private func activeTime(_ duration: TimeInterval) -> DeliveryActiveTime {
        DeliveryActiveTime(
            duration: duration,
            sourceIntervalCount: 1,
            countedIntervalCount: 1,
            mergedIntervalCount: 1,
            unfinishedIntervalCount: 0,
            malformedIntervalCount: 0
        )
    }

    private func record(
        startedAt: Date,
        isCompleted: Bool = true,
        working: TimeInterval? = 3 * 3_600,
        earnings: Money? = nil,
        route recordedDistance: RouteDistance = .none,
        delivered: Int = 0,
        cancelled: Int = 0
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: startedAt,
            isCompleted: isCompleted,
            workingDuration: working,
            grossEarnings: earnings,
            recordedDistance: recordedDistance,
            deliveryActiveTime: activeTime(3_600),
            deliverySummary: DeliverySummary(completed: delivered, cancelled: cancelled),
            pickupWaits: [],
            pickupPlaceIDs: [],
            recordedDeliveryEarnings: [],
            terminalDeliveryCount: delivered + cancelled
        )
    }

    private func line(
        _ kind: HistoryWeekSummaryLine.Kind,
        in summary: HistoryWeekSummary
    ) throws -> HistoryWeekSummaryLine {
        try #require(summary.lines(locale: Locale(identifier: "en_US")).first { $0.id == kind })
    }

    // MARK: One shift, and several

    @Test("A week holding one shift reports that shift's own figures")
    func oneShift() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(
                    startedAt: at(day: 1, hour: 9),
                    working: 4 * 3_600,
                    earnings: try money("120.00"),
                    route: route(miles: 40),
                    delivered: 6
                )
            ]
        )

        #expect(summary.completedShiftCount == 1)
        #expect(try line(.shifts, in: summary).value == "1")
        #expect(try line(.earnings, in: summary).value == "$120.00")
        #expect(try line(.working, in: summary).value == DurationText.short(4 * 3_600))
        #expect(try line(.mileage, in: summary).value.contains("40"))
        #expect(try line(.deliveries, in: summary).value == "6")
    }

    @Test("Several shifts are added up, and the total is the calculator's own")
    func severalShifts() throws {
        let records = [
            record(
                startedAt: at(day: 0, hour: 9),
                working: 4 * 3_600,
                earnings: try money("120.00"),
                route: route(miles: 40),
                delivered: 6
            ),
            record(
                startedAt: at(day: 2, hour: 17),
                working: 3 * 3_600 + 1_800,
                earnings: try money("98.50"),
                route: route(miles: 31.2),
                delivered: 5,
                cancelled: 1
            ),
            record(
                startedAt: at(day: 5, hour: 11),
                working: 5 * 3_600,
                earnings: try money("164.25"),
                route: route(miles: 62),
                delivered: 9
            )
        ]

        let summary = HistoryWeekSummary(week: try fixtureWeek, records: records)
        let direct = calculator.metrics(of: records, in: try fixtureWeek.period)

        // The whole point: the summary is the period aggregation, not a second
        // one that happens to agree today.
        #expect(summary.metrics == direct)

        #expect(summary.completedShiftCount == 3)
        #expect(summary.metrics.recordedGrossEarnings == (try money("382.75")))
        #expect(summary.metrics.workingDuration == TimeInterval(12 * 3_600 + 1_800))
        #expect(summary.metrics.deliverySummary.recorded == 21)
        #expect(
            abs(summary.metrics.recordedDistance.metres - 133.2 * Self.metresPerMile) < 0.001,
            "The week's mileage is the sum of the shifts' recorded mileage"
        )
    }

    // MARK: The Monday-to-Sunday boundary

    @Test("The week runs Monday to Sunday, whatever the device says a week starts on")
    func mondayToSundayBoundary() throws {
        let week = try fixtureWeek

        // One second before the Monday, one second before the following Monday,
        // and the first second of it.
        let sundayBefore = monday.addingTimeInterval(-1)
        let lastSecond = monday.addingTimeInterval(7 * 86_400 - 1)
        let nextMonday = monday.addingTimeInterval(7 * 86_400)

        let summary = HistoryWeekSummary(
            week: week,
            records: [
                record(startedAt: sundayBefore, earnings: try money("11.00")),
                record(startedAt: monday, earnings: try money("22.00")),
                record(startedAt: lastSecond, earnings: try money("33.00")),
                record(startedAt: nextMonday, earnings: try money("44.00"))
            ]
        )

        #expect(summary.completedShiftCount == 2, "The half-open week holds the Monday and the Sunday night")
        #expect(
            summary.metrics.recordedGrossEarnings == (try money("55.00")),
            "The shift before the Monday and the one after the Sunday belong to other weeks"
        )
    }

    @Test("A shift is placed by when it started, so one worked past midnight Sunday stays in its week")
    func membershipIsByStart() throws {
        // Started at 23:00 on the Sunday, and still running into the Monday.
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [record(startedAt: at(day: 6, hour: 23), working: 4 * 3_600, earnings: try money("70.00"))]
        )

        #expect(summary.completedShiftCount == 1)
        #expect(summary.metrics.recordedGrossEarnings == (try money("70.00")))
    }

    // MARK: What is excluded

    @Test("A running shift is not in a week's totals")
    func runningShiftsAreExcluded() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(startedAt: at(day: 1, hour: 9), earnings: try money("120.00")),
                record(startedAt: at(day: 2, hour: 9), isCompleted: false, earnings: try money("500.00"))
            ]
        )

        #expect(summary.completedShiftCount == 1)
        #expect(summary.metrics.recordedGrossEarnings == (try money("120.00")))
    }

    @Test("A week holding nothing reports nothing, and no figure reads as a zero")
    func anEmptyWeek() throws {
        let summary = HistoryWeekSummary(week: try fixtureWeek, records: [PeriodShiftRecord]())

        #expect(summary.isEmpty)
        #expect(summary.completedShiftCount == 0)
        #expect(summary.metrics.recordedGrossEarnings == nil, "No earnings recorded is not earnings of zero")
        #expect(summary.metrics.workingDuration == nil)
        #expect(!summary.metrics.recordedDistance.isMeasured)
    }

    // MARK: Missing is not zero

    @Test("A week where nobody recorded an amount says so rather than showing a subtotal")
    func missingEarningsAreNotZero() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(startedAt: at(day: 1, hour: 9), route: route(miles: 20), delivered: 3),
                record(startedAt: at(day: 3, hour: 9), route: route(miles: 25), delivered: 4)
            ]
        )

        let earnings = try line(.earnings, in: summary)
        #expect(earnings.value == "Not recorded")
        #expect(!earnings.value.contains("0.00"))
        #expect(earnings.spoken.contains("not the same as earning nothing"))
    }

    @Test("A partly recorded week carries the count behind the subtotal")
    func partialEarningsCarryTheirCoverage() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(startedAt: at(day: 0, hour: 9), earnings: try money("100.00")),
                record(startedAt: at(day: 1, hour: 9), earnings: try money("80.00")),
                record(startedAt: at(day: 2, hour: 9)),
                record(startedAt: at(day: 3, hour: 9))
            ]
        )

        let earnings = try line(.earnings, in: summary)
        #expect(earnings.value == "$180.00")
        #expect(earnings.detail == "2 of 4 shifts", "A subtotal that is not the whole week says which shifts it is")
        #expect(earnings.spoken.contains("across 2 of 4 completed shifts"))
    }

    @Test("A week whose routes measured nothing says so rather than showing no miles")
    func unmeasuredMileageIsNotZero() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [record(startedAt: at(day: 1, hour: 9), earnings: try money("90.00"))]
        )

        let mileage = try line(.mileage, in: summary)
        #expect(mileage.value == "Not measured")
        #expect(!mileage.value.contains("0.0"))
    }

    @Test("A partial route in the week is stated, because the miles are a floor")
    func partialRoutesAreStated() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(startedAt: at(day: 1, hour: 9), route: route(miles: 30, gapCount: 2)),
                record(startedAt: at(day: 2, hour: 9), route: route(miles: 20))
            ]
        )

        #expect(summary.metrics.routeCoverage.partialShiftCount == 1)
        let mileage = try line(.mileage, in: summary)
        #expect(mileage.detail?.contains("partial") == true, "Showed: \(mileage.detail ?? "nothing")")
        #expect(mileage.spoken.contains("partial"))
    }

    // MARK: Reading order and spoken form

    @Test("The lines are in reading order, and each says its own unit out loud")
    func readingOrderAndSpokenForm() throws {
        let summary = HistoryWeekSummary(
            week: try fixtureWeek,
            records: [
                record(
                    startedAt: at(day: 1, hour: 9),
                    working: 4 * 3_600,
                    earnings: try money("120.00"),
                    route: route(miles: 40),
                    delivered: 6
                )
            ]
        )

        let lines = summary.lines(locale: Locale(identifier: "en_US"))
        #expect(lines.map(\.id) == [.shifts, .earnings, .working, .mileage, .deliveries])

        let spoken = summary.spokenSummary(locale: Locale(identifier: "en_US"))
        #expect(spoken.contains("completed shift"))
        #expect(spoken.contains("$120.00"))
        #expect(spoken.contains("working time"))
        #expect(spoken.contains("Recorded mileage"))
        #expect(spoken.contains("6 deliveries completed"))
        // Abbreviations that read well are poor to hear.
        #expect(!spoken.contains(" mi,"), "A listener is told miles rather than mi: \(spoken)")
    }

    // MARK: A week dated ahead of the clock

    @Test("A week the calendar places in the future is summarised exactly like any other")
    func aFutureDatedWeekBehavesTheSame() throws {
        // Only a device clock moved backwards produces one, and History lists it
        // rather than dropping it. Nothing about the aggregation changes.
        let nextWeek = try week(containing: monday.addingTimeInterval(7 * 86_400))
        let summary = HistoryWeekSummary(
            week: nextWeek,
            records: [
                record(
                    startedAt: monday.addingTimeInterval(8 * 86_400),
                    working: 2 * 3_600,
                    earnings: try money("45.00"),
                    route: route(miles: 12),
                    delivered: 2
                )
            ]
        )

        #expect(summary.completedShiftCount == 1)
        #expect(summary.metrics.recordedGrossEarnings == (try money("45.00")))
        #expect(try line(.deliveries, in: summary).value == "2")
    }
}
