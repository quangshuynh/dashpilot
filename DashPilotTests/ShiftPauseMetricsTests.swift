import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a pause does to every derived figure: a shift's rates, a period's
/// totals, the comparison between two periods, and the exported file.
///
/// The claim running through all of it is one sentence: **a shift that was never
/// paused reports exactly what it always did**, and a shift that was paused
/// divides by the time it was actually worked.
@MainActor
@Suite("Shift pause metrics, reporting and export")
struct ShiftPauseMetricsTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! #require(TimeZone(identifier: "America/New_York"))
        return calendar
    }()

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func pausedTime(_ duration: TimeInterval, count: Int = 1) -> ShiftPausedTime {
        ShiftPausedTime(
            duration: duration,
            intervalCount: count,
            openIntervalCount: 0,
            unusableIntervalCount: 0
        )
    }

    // MARK: A shift's own rates

    @Test("The hourly rate divides by working time, not by elapsed time")
    func hourlyRateUsesWorkingTime() throws {
        let metrics = ShiftMetricsCalculator().metrics(
            grossEarnings: try money("90.00"),
            elapsedDuration: 4 * 3600,
            pausedTime: pausedTime(3_600),
            recordedDistance: .none
        )

        #expect(metrics.elapsedDuration == 4 * 3600.0)
        #expect(metrics.workingDuration == 3 * 3600.0)
        #expect(metrics.pausedTime.duration == 3_600)
        #expect(metrics.wasPaused)
        let expected = try money("30.00")
        #expect(metrics.grossPerWorkingHour == .available(expected))
    }

    /// The reason the denominator moved at all: dividing by elapsed time would
    /// report a driver as having earned less per hour for taking a break, which
    /// is a claim about their work the app has no business making.
    @Test("Taking a break does not lower the shift's hourly rate")
    func aBreakDoesNotLowerTheRate() throws {
        let earnings = try money("90.00")
        let unpaused = ShiftMetricsCalculator().metrics(
            grossEarnings: earnings,
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )
        let withABreak = ShiftMetricsCalculator().metrics(
            grossEarnings: earnings,
            elapsedDuration: 4 * 3600,
            pausedTime: pausedTime(3_600),
            recordedDistance: .none
        )

        #expect(unpaused.grossPerWorkingHour == withABreak.grossPerWorkingHour)
    }

    @Test("A shift that was never paused reports the figures it always did")
    func neverPausedIsUnchanged() throws {
        let metrics = ShiftMetricsCalculator().metrics(
            grossEarnings: try money("90.00"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.pausedTime == ShiftPausedTime.none)
        #expect(!metrics.wasPaused)
        #expect(metrics.workingDuration == metrics.elapsedDuration)
        let expected = try money("30.00")
        #expect(metrics.grossPerWorkingHour == .available(expected))
    }

    @Test("A shift paused for the whole of its length has no working hours to divide by")
    func fullyPausedShiftHasNoRate() throws {
        let metrics = ShiftMetricsCalculator().metrics(
            grossEarnings: try money("90.00"),
            elapsedDuration: 4 * 3600,
            pausedTime: pausedTime(4 * 3600),
            recordedDistance: .none
        )

        #expect(metrics.workingDuration == 0)
        #expect(metrics.grossPerWorkingHour == .unavailable(.noWorkingTime))
    }

    @Test("A running shift is reported as running rather than as having no working time")
    func runningShiftReportsItself() throws {
        let metrics = ShiftMetricsCalculator().metrics(
            grossEarnings: try money("90.00"),
            elapsedDuration: nil,
            pausedTime: pausedTime(600),
            recordedDistance: .none
        )

        #expect(metrics.workingDuration == nil)
        #expect(metrics.grossPerWorkingHour == .unavailable(.shiftNotCompleted))
    }

    /// Delivery active time is measured exactly as it always was. What changed
    /// is what the rest of the shift is measured against: non-delivery time is
    /// the working time no delivery covered, so a pause does not reappear as
    /// time the driver spent not delivering.
    @Test("Non-delivery time is the working time no delivery covered")
    func nonDeliveryTimeIsWithinWorkingTime() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        try shifts.startShift(at: start)
        let delivery = try deliveries.startDelivery(at: at(600))
        try deliveries.markArrivedAtPickup(delivery, at: at(900))
        try deliveries.markPickedUp(delivery, at: at(1_200))
        try deliveries.markDelivered(delivery, at: at(2_400))
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(7_200))
        let shift = try shifts.endActiveShift(at: at(10_800))

        let active = shift.deliveryActiveTime()
        #expect(active.duration == 1_800, "Delivery active time is unchanged by the pause")

        let metrics = shift.metrics(for: .none)
        #expect(metrics.elapsedDuration == 10_800)
        #expect(metrics.workingDuration == 7_200)
        #expect(metrics.nonDeliveryDuration == 5_400, "7200 worked less 1800 on a delivery")
    }

    // MARK: A period

    @Test("A period's hours are working hours, and its rate divides by them")
    func periodUsesWorkingHours() throws {
        let day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(
            of: [
                PeriodShiftRecord(startedAt: start, workingDuration: 3 * 3600, grossEarnings: try money("90.00")),
                PeriodShiftRecord(startedAt: at(3_600), workingDuration: 1 * 3600, grossEarnings: try money("30.00"))
            ],
            in: day
        )

        #expect(metrics.workingDuration == 4 * 3600.0)
        #expect(metrics.workingCoverage.isComplete)
        let expected = try money("30.00")
        #expect(metrics.grossPerWorkingHour.amount == expected)
    }

    @Test("A shift's own working duration is what reaches the period aggregation")
    func periodRecordCarriesWorkingDuration() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let service = ShiftService(context: ModelContext(container))

        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))
        try service.resumeActiveShift(at: at(7_200))
        let shift = try service.endActiveShift(at: at(14_400))

        let record = shift.periodRecord(for: .none)

        #expect(record.workingDuration == 10_800)
        #expect(record.usableWorkingDuration == 10_800)
    }

    @Test("The period rate names working hours rather than shift hours")
    func periodRateWording() {
        #expect(PeriodRateKind.perWorkingHour.title == "Per working hour")
        #expect(PeriodRateKind.perWorkingHour.spokenTitle == "gross earnings per working hour")
        #expect(PeriodRateKind.perWorkingHour.basisNoun.contains("working time"))
        #expect(PeriodRateKind.perWorkingHour.unavailableExplanation.contains("working time"))
    }

    @Test("The comparison compares working time, taken from the same result")
    func comparisonUsesWorkingTime() throws {
        let day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let previous = try #require(day.precedingEquivalent(using: calendar))
        let calculator = PeriodMetricsCalculator()

        let selected = calculator.metrics(
            of: [PeriodShiftRecord(startedAt: start, workingDuration: 4 * 3600)],
            in: day
        )
        let before = calculator.metrics(
            of: [PeriodShiftRecord(startedAt: previous.start, workingDuration: 3 * 3600)],
            in: previous
        )

        let comparison = try #require(
            PeriodComparisonCalculator().comparison(
                of: selected,
                with: before,
                asOf: at(30 * 86_400),
                calendar: calendar
            )
        )
        let row = try #require(comparison.entries.first { $0.metric == .workingTime })

        #expect(row.metric.id == "workingTime")
        #expect(row.metric.title == "Working")
        #expect(row.current == .duration(4 * 3600))
        #expect(row.previous == .duration(3 * 3600))
    }

    // MARK: The export

    @Test("A paused shift exports its elapsed, paused and working seconds apart")
    func exportCarriesAllThreeDurations() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let service = ShiftService(context: ModelContext(container))

        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))
        try service.resumeActiveShift(at: at(7_200))
        let shift = try service.endActiveShift(at: at(14_400))
        try shift.setGrossEarnings(try money("90.00"))

        let record = try shift.exportRecord(for: .none)

        #expect(record.elapsedSeconds == 14_400)
        #expect(record.pausedSeconds == 3_600)
        #expect(record.workingSeconds == 10_800)
        #expect(record.pauseCount == 1)
        #expect(record.grossPerWorkingHour?.string == "30.00")
    }

    /// Zero is a measurement here, not a missing value: a shift that was never
    /// paused was paused for no time, and a reader must be able to tell that
    /// from a field that was not written.
    @Test("A shift that was never paused exports zero paused seconds, not null")
    func neverPausedExportsZero() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let service = ShiftService(context: ModelContext(container))

        try service.startShift(at: start)
        let shift = try service.endActiveShift(at: at(10_800))

        let record = try shift.exportRecord(for: .none)

        #expect(record.pausedSeconds == 0)
        #expect(record.pauseCount == 0)
        #expect(record.workingSeconds == record.elapsedSeconds)
    }

    @Test("The CSV carries the paused and working columns beside the elapsed one")
    func csvColumns() throws {
        let columns = ExportDocumentEncoder.columns

        #expect(columns.contains("shiftElapsedSeconds"))
        #expect(columns.contains("shiftPausedSeconds"))
        #expect(columns.contains("shiftWorkingSeconds"))
        #expect(columns.contains("shiftPauseCount"))
        #expect(columns.contains("shiftGrossPerWorkingHour"))
        #expect(!columns.contains("shiftGrossPerElapsedHour"), "The renamed column is gone rather than redefined")
        #expect(columns.count == Set(columns).count, "No column name is repeated")
    }

    /// The version decision, asserted rather than only documented: a rename and
    /// a redefinition are what the format's own rule bumps for.
    @Test("The renamed rate and the redefined non-delivery field moved the format version")
    func formatVersionMoved() {
        // It moved to 3 here and to 4 since, for additional tips. What this
        // asserts is that a rename and a redefinition are bumping changes, and
        // the version has not gone backwards.
        #expect(ExportFormat.version >= 3)
    }
}
