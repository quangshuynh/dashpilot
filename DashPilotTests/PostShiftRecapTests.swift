import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The recap repeats figures the shift's own calculators produce, and words
/// their absence instead of inventing a value.
@MainActor
@Suite("Post-shift recap")
struct PostShiftRecapTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// Four hours with a thirty-minute pause, so working time is 3.5 hours.
    private func completedShift(in context: ModelContext, gross: Money? = nil) throws -> Shift {
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))
        try service.resumeActiveShift(at: at(5_400))
        try service.endActiveShift(at: at(14_400))
        if let gross { try shift.setGrossEarnings(gross) }
        return shift
    }

    private func distance(miles: Double, gaps: Int = 0) -> RouteDistance {
        RouteDistance(metres: miles * 1_609.344, segmentCount: gaps + 1, gapCount: gaps,
                      usableSampleCount: 100, usesInferredContinuity: false)
    }

    @Test("A running shift has no recap")
    func runningShiftHasNoRecap() throws {
        let context = try makeContext()
        let shift = try ShiftService(context: context).startShift(at: start)
        #expect(PostShiftRecap(shift: shift, recordedDistance: .none) == nil)
    }

    @Test("Gross per working hour is the shift calculator's figure, pauses excluded")
    func rateMatchesTheShiftCalculator() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context, gross: Money(minorUnits: 10_500))
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: .none))

        #expect(recap.grossStatement(locale: locale) == "$105.00")
        #expect(recap.workingDuration == 12_600)
        #expect(recap.grossPerWorkingHour == shift.metrics(for: .none).grossPerWorkingHour)
        #expect(recap.rateStatement(locale: locale) == "$30.00/hr")
        #expect(recap.rateDetail == nil)
    }

    @Test("Missing earnings say Not recorded and leave the rate unavailable, never zero")
    func missingEarningsAreNotZero() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: .none))

        #expect(recap.grossStatement(locale: locale) == "Not recorded")
        #expect(recap.rateStatement(locale: locale) == "Not available")
        #expect(recap.rateDetail == ShiftRateUnavailability.earningsNotRecorded.explanation)
    }

    @Test("A recorded zero is shown as the zero it is")
    func explicitZeroIsAValue() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context, gross: .zero)
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: .none))

        #expect(recap.grossStatement(locale: locale) == "$0.00")
        #expect(recap.rateStatement(locale: locale) == "$0.00/hr")
    }

    @Test("Delivery earnings are never read as the shift's gross")
    func deliveryEarningsAreNotInferred() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(delivery, at: at(120))
        try deliveries.markPickedUp(delivery, at: at(180))
        try deliveries.markDelivered(delivery, at: at(240))
        try delivery.setGrossEarnings(Money(minorUnits: 1_250))
        try service.endActiveShift(at: at(3_600))

        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: .none))
        #expect(recap.grossEarnings == nil)
        #expect(recap.grossStatement(locale: locale) == "Not recorded")
    }

    @Test("No route says Not recorded, and the fuel estimate says why it is missing")
    func noRouteIsNotZeroMiles() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context, gross: Money(minorUnits: 5_000))
        try shift.setFuelAssumptions(milesPerGallon: 30, gasPricePerGallon: Money(minorUnits: 300))
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: .none))

        #expect(recap.mileageStatement(locale: locale) == "Not recorded")
        #expect(recap.mileageDetail == "No route recorded")
        #expect(recap.fuelStatement(locale: locale) == "Not available")
        #expect(recap.fuelDetail == FuelEstimateUnavailability.noRouteRecorded.explanation)
    }

    @Test("A partial route keeps its qualification on the mileage and the estimate")
    func partialRouteIsQualified() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try shift.setFuelAssumptions(milesPerGallon: 30, gasPricePerGallon: Money(minorUnits: 300))
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: distance(miles: 30, gaps: 1)))

        #expect(recap.mileageStatement(locale: locale).contains("30"))
        #expect(recap.mileageDetail.contains("partial"))
        #expect(recap.spokenMileage(locale: locale).contains("recorded"))
        #expect(recap.fuelEstimate == shift.fuelEstimate(for: distance(miles: 30, gaps: 1)))
        #expect(recap.fuelStatement(locale: locale) == "$3.00")
        #expect(recap.fuelDetail.contains("Estimated"))
        #expect(recap.fuelDetail.contains("partial"))
    }

    @Test("A complete route's estimate is labelled estimated and not an expense")
    func completeRouteEstimateIsLabelled() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try shift.setFuelAssumptions(milesPerGallon: 30, gasPricePerGallon: Money(minorUnits: 300))
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: distance(miles: 60)))

        #expect(recap.mileageDetail == "Recorded mileage")
        #expect(recap.fuelStatement(locale: locale) == "$6.00")
        #expect(recap.fuelDetail.hasPrefix("Estimated"))
        #expect(recap.fuelDetail.contains("Not a recorded expense"))
    }

    @Test("Missing fuel assumptions leave the estimate unavailable, never $0.00")
    func missingAssumptionsAreNotZero() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        let recap = try #require(PostShiftRecap(shift: shift, recordedDistance: distance(miles: 60)))

        #expect(recap.fuelStatement(locale: locale) == "Not available")
        #expect(!recap.fuelDetail.isEmpty)
    }

    @Test("Recorded expenses neither appear in nor change the recap")
    func recordedExpensesAreSeparate() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context, gross: Money(minorUnits: 10_000))
        try shift.setFuelAssumptions(milesPerGallon: 30, gasPricePerGallon: Money(minorUnits: 300))
        let before = try #require(PostShiftRecap(shift: shift, recordedDistance: distance(miles: 60)))

        context.insert(try Expense(occurredAt: at(7_200), amount: Money(minorUnits: 4_000), category: .fuel))
        try context.save()

        let after = try #require(PostShiftRecap(shift: shift, recordedDistance: distance(miles: 60)))
        #expect(after == before)
        #expect(after.fuelStatement(locale: locale) == "$6.00", "The estimate is not added to or replaced by the expense")
    }
}
