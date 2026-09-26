import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// An older week's summary follows an edit to one of its shifts.
///
/// The summary is worked out off the main actor and keyed on the week and a
/// ``HistoryWeekRevision`` of the facts its shifts record. So each test here
/// makes one real edit through the service a screen would use, and asserts
/// two things: the week's revision moved (which is what restarts the work on
/// screen), and the summary worked out through the same off-main path now
/// says what the store says. The last tests assert what must **not** move.
@MainActor
@Suite("History week refresh after an edit")
struct HistoryWeekRefreshTests {
    private let calendar: Calendar
    private let container: ModelContainer
    private let context: ModelContext
    private let monday: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = container.mainContext
        monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
    }

    private func at(day: Int, hour: Double) -> Date {
        monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
    }

    private var week: HistoryWeek {
        get throws { try #require(HistoryWeek(containing: monday, calendar: calendar)) }
    }

    /// A completed four-hour shift paying `amount`, with an unbroken route of
    /// one position a minute, 400 m apart, for its whole length.
    @discardableResult
    private func shift(day: Int, amount: Int, routed: Bool = false) throws -> Shift {
        let start = at(day: day, hour: 10)
        let shift = Shift(startedAt: start)
        context.insert(shift)
        if routed {
            let session = UUID()
            for step in 0...240 {
                context.insert(RouteSample(
                    shift: shift,
                    timestamp: start.addingTimeInterval(Double(step) * 60),
                    latitude: 40 + Double(step) * 400 / 111_320,
                    longitude: -75,
                    horizontalAccuracy: 8,
                    captureSessionID: session
                ))
            }
        }
        try shift.end(at: start.addingTimeInterval(4 * 3_600))
        try shift.setGrossEarnings(Money(minorUnits: amount))
        try context.save()
        return shift
    }

    private func summary(of shifts: [Shift]) throws -> HistoryWeekSummary {
        HistoryFetchScope.weekSummary(of: try week, shiftIDs: shifts.map(\.id), in: container)
    }

    @Test("Editing a shift's amount moves the week's revision and its earnings")
    func earningsEdit() throws {
        let first = try shift(day: 0, amount: 8_000)
        let second = try shift(day: 2, amount: 6_000)
        let before = HistoryWeekRevision([first, second])

        try ShiftService(context: context).setGrossEarnings(Money(minorUnits: 6_500), on: second)

        #expect(HistoryWeekRevision([first, second]) != before)
        #expect(try summary(of: [first, second]).metrics.recordedGrossEarnings == Money(minorUnits: 14_500))
    }

    @Test("Correcting an end moves the working time, and an earlier end the mileage with it")
    func endCorrection() throws {
        let routed = try shift(day: 1, amount: 8_000, routed: true)
        let before = HistoryWeekRevision([routed])
        let milesBefore = try summary(of: [routed]).metrics.recordedDistance.metres

        try ShiftEndCorrectionService(context: context).correct(routed, to: at(day: 1, hour: 12))

        #expect(HistoryWeekRevision([routed]) != before)
        let after = try summary(of: [routed]).metrics
        #expect(after.workingDuration == TimeInterval(2 * 3_600))
        #expect(after.recordedDistance.metres < milesBefore, "The route after the new end is gone")
    }

    @Test("Adding a missed pause moves the working time")
    func pauseAdded() throws {
        let worked = try shift(day: 3, amount: 5_000)
        let before = HistoryWeekRevision([worked])

        try ShiftPauseCorrectionService(context: context)
            .addMissedPause(on: worked, from: at(day: 3, hour: 11), to: at(day: 3, hour: 12))

        #expect(HistoryWeekRevision([worked]) != before)
        #expect(try summary(of: [worked]).metrics.workingDuration == TimeInterval(3 * 3_600))
    }

    @Test("Recording fuel assumptions moves the week's fuel coverage and its net")
    func fuelAssumptions() throws {
        let routed = try shift(day: 1, amount: 8_000, routed: true)
        let plain = try shift(day: 2, amount: 6_000, routed: true)
        #expect(!(try summary(of: [routed, plain]).metrics.fuel.isAvailable))
        let before = HistoryWeekRevision([routed, plain])

        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: 25,
            gasPricePerGallon: Money(minorUnits: 400),
            on: routed
        )

        #expect(HistoryWeekRevision([routed, plain]) != before)
        let metrics = try summary(of: [routed, plain]).metrics
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
        #expect(metrics.estimatedNetAfterFuel.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    @Test("Deleting a shift drops it from the week's count and total, and the revision moves")
    func deletion() throws {
        let kept = try shift(day: 0, amount: 8_000)
        let deleted = try shift(day: 2, amount: 6_000)
        let ids = [kept, deleted]
        let before = HistoryWeekRevision(ids)

        try ShiftService(context: context).deleteCompletedShift(deleted)

        // The list a screen holds may still contain the deleted model for a
        // moment; the revision skips it rather than reading it.
        #expect(HistoryWeekRevision(ids) != before)
        let after = try summary(of: ids)
        #expect(after.completedShiftCount == 1)
        #expect(after.metrics.recordedGrossEarnings == Money(minorUnits: 8_000))
    }

    @Test("Correcting a completion to a cancellation moves the week's delivery outcomes")
    func completionCorrectedToCancellation() throws {
        // Built through the shipping services rather than by hand, so the
        // correction is applied to a store the app really produces.
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        let worked = try shifts.startShift(at: at(day: 2, hour: 10))
        let offer = try deliveries.startOffer(deliveryCount: 2, at: at(day: 2, hour: 10.1))
        for (index, delivery) in offer.deliveriesInOrder.enumerated() {
            let step = Double(index) * 0.05
            try deliveries.markArrivedAtPickup(delivery, at: at(day: 2, hour: 10.2 + step))
            try deliveries.markPickedUp(delivery, at: at(day: 2, hour: 10.4 + step))
            try deliveries.markDelivered(delivery, at: at(day: 2, hour: 10.8 + step))
        }
        try shifts.endActiveShift(at: at(day: 2, hour: 12))

        let beforeSummary = try summary(of: [worked]).metrics.deliverySummary
        #expect(beforeSummary.completed == 2)
        #expect(beforeSummary.cancelled == 0)
        let before = HistoryWeekRevision([worked])

        try deliveries.correctCompletionToCancellation(try #require(offer.deliveriesInOrder.last))

        #expect(HistoryWeekRevision([worked]) != before)
        let after = try summary(of: [worked])
        #expect(after.metrics.deliverySummary.completed == 1)
        #expect(after.metrics.deliverySummary.cancelled == 1)
        #expect(after.activityStatement.contains("1 cancelled"), "Showed: \(after.activityStatement)")
    }

    @Test("A running shift's route batch moves no completed week's revision")
    func runningRouteBatchIsNotAnEdit() throws {
        let completed = try shift(day: 0, amount: 8_000)
        let before = HistoryWeekRevision([completed])

        // What a save during a running shift looks like: positions added to a
        // shift that is not in any completed week's list.
        let running = try ShiftService(context: context).startShift(at: at(day: 1, hour: 9))
        let session = UUID()
        for step in 0..<30 {
            context.insert(RouteSample(
                shift: running,
                timestamp: at(day: 1, hour: 9).addingTimeInterval(Double(step) * 5),
                latitude: 40 + Double(step) * 50 / 111_320,
                longitude: -75,
                horizontalAccuracy: 8,
                captureSessionID: session
            ))
        }
        try context.save()

        #expect(HistoryWeekRevision([completed]) == before)
    }

    @Test("An edit to a shift in another week leaves this week's revision alone")
    func unrelatedWeekIsUntouched() throws {
        let thisWeek = try shift(day: 1, amount: 8_000)
        let nextWeek = try shift(day: 8, amount: 6_000)
        let before = HistoryWeekRevision([thisWeek])

        try ShiftService(context: context).setGrossEarnings(Money(minorUnits: 9_900), on: nextWeek)

        #expect(HistoryWeekRevision([thisWeek]) == before)
    }

    @Test("Saving without changing anything leaves the revision alone")
    func unchangedFactsKeepTheRevision() throws {
        let worked = try shift(day: 1, amount: 8_000)
        let before = HistoryWeekRevision([worked])
        try context.save()
        #expect(HistoryWeekRevision([worked]) == before)
    }
}
