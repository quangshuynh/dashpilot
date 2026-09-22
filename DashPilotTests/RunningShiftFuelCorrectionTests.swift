import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Correcting the vehicle assumptions a **running** shift recorded when it
/// started.
///
/// Two claims carry the whole feature. **It is allowed only before the route has
/// measured a distance**, judged by ``RouteDistance/isMeasured`` rather than by
/// any interval since the start. And **it changes nothing but this shift's own
/// three columns**: no route sample, no vehicle profile, no settings row, and no
/// shift but this one.
@MainActor
@Suite("Running shift fuel correction")
struct RunningShiftFuelCorrectionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func money(_ text: String) -> Money {
        Money(amount: Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!)
    }

    /// `count` positions 40 m apart in one capture session, which is a route
    /// that measures a distance.
    @discardableResult
    private func record(
        _ count: Int,
        from index: Int = 0,
        for shift: Shift,
        in session: UUID = UUID(),
        context: ModelContext
    ) throws -> [RouteSample] {
        let samples = (index..<(index + count)).map { step in
            RouteSample(
                shift: shift,
                sample: SyntheticRoute.sample(at: at(Double(step)), northMetres: Double(step) * 40),
                captureSessionID: session
            )
        }
        for sample in samples { context.insert(sample) }
        try context.save()
        return samples
    }

    // MARK: A fresh shift can be corrected

    @Test("A fresh running shift can be moved to another vehicle")
    func correctsAFreshShiftToAnotherVehicle() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.mayCorrectRunningFuelAssumptions())

        try shifts.correctRunningShiftFuelAssumptions(
            camry.defaults(gasPricePerGallon: shift.fuelAssumptions.gasPricePerGallon),
            on: shift
        )

        #expect(shift.vehicleContext.title == "2012 Toyota Camry")
        #expect(shift.fuelAssumptions.milesPerGallon == 28)
        #expect(shift.vehicleContext.economyStatement(locale: locale) == "28 MPG")
    }

    @Test("A fresh running shift that recorded nothing can have its assumptions filled")
    func fillsMissingAssumptionsOnAFreshShift() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)

        // Started before the driver had entered anything at all.
        let shift = try shifts.startShift(at: start)
        #expect(shift.fuelAssumptions.hasAny == false)

        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(60))
        try settings.setGasPricePerGallon(money("3.79"))

        try shifts.correctRunningShiftFuelAssumptions(settings.currentFuelDefaults(), on: shift)

        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.fuelAssumptions.milesPerGallon == 34)
        #expect(shift.fuelAssumptions.gasPricePerGallon == money("3.79"))
        #expect(civic.name == "2020 Honda Civic", "And the profile is exactly as it was")
    }

    @Test("The current gas price can be copied without moving the vehicle")
    func copiesTheCurrentGasPriceAlone() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.setGasPricePerGallon(money("3.29"))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        #expect(shift.fuelAssumptions.gasPricePerGallon == money("3.29"))

        try settings.setGasPricePerGallon(money("4.19"))
        #expect(
            shift.fuelAssumptions.gasPricePerGallon == money("3.29"),
            "Changing the setting does not reach a running shift on its own"
        )

        try shifts.correctRunningShiftFuelAssumptions(
            FuelDefaults(
                vehicleName: shift.vehicleContext.vehicleName,
                milesPerGallon: shift.vehicleContext.milesPerGallon,
                gasPricePerGallon: settings.currentFuelDefaults().assumptions.gasPricePerGallon
            ),
            on: shift
        )

        #expect(shift.fuelAssumptions.gasPricePerGallon == money("4.19"), "Only the explicit correction copies it")
        #expect(shift.vehicleContext.title == "2020 Honda Civic", "And the vehicle is untouched")
        #expect(shift.fuelAssumptions.milesPerGallon == 34)
    }

    @Test("A correction can also remove the assumptions entirely")
    func clearsTheAssumptions() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)

        try shifts.correctRunningShiftFuelAssumptions(.none, on: shift)

        #expect(shift.fuelAssumptions.hasAny == false)
        #expect(shift.vehicleContext.isRecorded == false)
        #expect(shift.vehicleContext.title == "No vehicle recorded")
    }

    // MARK: Recorded driving closes it

    @Test("Once the route has measured a distance the correction is refused")
    func refusesOnceDrivingIsRecorded() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try record(6, for: shift, context: context)

        #expect(shift.recordedDistance().isMeasured, "The route measures a distance")
        #expect(shift.mayCorrectRunningFuelAssumptions() == false)

        #expect(throws: ShiftLifecycleError.invalidTransition(.recordedDrivingHasBegun)) {
            try shifts.correctRunningShiftFuelAssumptions(
                camry.defaults(gasPricePerGallon: nil),
                on: shift
            )
        }
    }

    /// The refusal leaves the shift exactly as it was, which is the part a
    /// partial write would break.
    @Test("A refused correction moves nothing on the shift")
    func aRefusedCorrectionWritesNothing() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.setGasPricePerGallon(money("3.29"))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try record(6, for: shift, context: context)

        #expect(throws: ShiftLifecycleError.self) {
            try shifts.correctRunningShiftFuelAssumptions(
                camry.defaults(gasPricePerGallon: money("9.99")),
                on: shift
            )
        }

        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.fuelAssumptions.milesPerGallon == 34)
        #expect(shift.fuelAssumptions.gasPricePerGallon == money("3.29"), "Both halves stayed, not one of them")
    }

    /// The rule is about measured distance rather than about samples existing,
    /// and this is the case that tells the two apart.
    @Test("Raw positions that measure no distance do not close the correction")
    func rawPositionsThatMeasureNothingDoNotRefuse() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        // One position. There is no second one to measure to, so the route
        // supports no distance at all.
        try record(1, for: shift, context: context)

        #expect(shift.routeSampleCount == 1)
        #expect(shift.recordedDistance().isMeasured == false)
        #expect(shift.mayCorrectRunningFuelAssumptions())

        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: nil), on: shift)

        #expect(shift.vehicleContext.title == "2012 Toyota Camry")
        #expect(shift.routeSampleCount == 1, "And the position it did record is still there")
    }

    /// The rule refuses on measured distance and not on elapsed time, which is
    /// the decision the brief asked to be made explicitly.
    @Test("A shift that has been running for hours without moving can still be corrected")
    func timeAloneDoesNotCloseTheCorrection() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        #expect(shift.workingDuration(asOf: at(14_400)) == 14_400, "Four hours of a shift nobody drove")

        #expect(shift.mayCorrectRunningFuelAssumptions())
        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: nil), on: shift)
        #expect(shift.vehicleContext.title == "2012 Toyota Camry")
    }

    @Test("A finished shift is refused here, because it has its own editor")
    func refusesAFinishedShift() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(3_600))

        #expect(shift.mayCorrectRunningFuelAssumptions() == false)
        #expect(throws: ShiftLifecycleError.invalidTransition(.shiftAlreadyEnded)) {
            try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: nil), on: shift)
        }

        // And the finished shift's own editor still applies, which is the pair's
        // whole division of labour.
        try shifts.setFuelAssumptions(milesPerGallon: 28, gasPricePerGallon: money("3.79"), on: shift)
        #expect(shift.fuelAssumptions.milesPerGallon == 28)
    }

    @Test("The refusal says what changed, in the words the screen shows")
    func theRefusalSaysWhyRatherThanThatItCannot() throws {
        let sentence = try #require(
            ShiftLifecycleError.invalidTransition(.recordedDrivingHasBegun).errorDescription
        )

        #expect(sentence.contains("cannot be changed after recorded driving has begun"))
        #expect(sentence.contains("once the shift has ended"), "And it names the remedy")
    }

    // MARK: Nothing else moves

    @Test("No route sample is deleted, moved or rewritten")
    func touchesNoRouteEvidence() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        // A route with a gap in it, so nothing is measured across it and the
        // correction is allowed while positions exist.
        try record(1, from: 0, for: shift, in: UUID(), context: context)
        try record(1, from: 900, for: shift, in: UUID(), context: context)

        let before = shift.routeSamples().map { [$0.timestamp, Date(timeIntervalSince1970: $0.latitude)] }
        #expect(shift.recordedDistance().isMeasured == false)

        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: nil), on: shift)

        let after = shift.routeSamples().map { [$0.timestamp, Date(timeIntervalSince1970: $0.latitude)] }
        #expect(after == before)
        #expect(shift.routeSampleCount == 2)
    }

    @Test("The vehicle profile and the settings row are not written")
    func touchesNoPreference() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))
        try settings.setGasPricePerGallon(money("3.29"))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: money("4.19")), on: shift)

        #expect(civic.name == "2020 Honda Civic")
        #expect(civic.milesPerGallon == 34)
        #expect(camry.milesPerGallon == 28)
        #expect(
            settings.selectedVehicle()?.id == civic.id,
            "Correcting a shift is not choosing a vehicle for the next one"
        )
        #expect(
            (try settings.existingSettings())?.gasPricePerGallon == money("3.29"),
            "And the current price is what the driver set, not what this shift now records"
        )
    }

    @Test("Deleting the profile afterwards leaves the corrected shift intelligible")
    func survivesTheProfileBeingDeleted() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: money("3.79")), on: shift)

        try settings.deleteVehicle(camry)

        #expect(shift.vehicleContext.title == "2012 Toyota Camry")
        #expect(shift.fuelAssumptions.milesPerGallon == 28)
        #expect(shift.fuelAssumptions.gasPricePerGallon == money("3.79"))
    }

    @Test("Changing Settings after the correction does not move the corrected shift")
    func laterSettingsChangesDoNotFollow() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: money("3.79")), on: shift)

        try settings.updateVehicle(camry, name: "The Camry", milesPerGallon: 21)
        try settings.setGasPricePerGallon(money("5.49"))

        #expect(shift.vehicleContext.title == "2012 Toyota Camry")
        #expect(shift.fuelAssumptions.milesPerGallon == 28)
        #expect(shift.fuelAssumptions.gasPricePerGallon == money("3.79"))
    }

    @Test("Only the shift being corrected moves")
    func correctsExactlyOneShift() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-1_200))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-1_100))

        let shifts = ShiftService(context: context)
        let earlier = try shifts.startShift(at: at(-3_600))
        try shifts.endActiveShift(at: at(-1_800))
        let running = try shifts.startShift(at: start)

        try shifts.correctRunningShiftFuelAssumptions(camry.defaults(gasPricePerGallon: nil), on: running)

        #expect(running.vehicleContext.title == "2012 Toyota Camry")
        #expect(earlier.vehicleContext.title == "2020 Honda Civic", "The shift already worked is untouched")
        #expect(earlier.fuelAssumptions.milesPerGallon == 34)
    }

    // MARK: The estimate follows the corrected snapshot

    @Test("The shift's fuel estimate is worked out under the corrected assumptions")
    func theEstimateFollowsTheCorrection() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 40, createdAt: at(-600))
        try settings.setGasPricePerGallon(money("4.00"))
        let van = try settings.addVehicle(name: "The van", milesPerGallon: 20, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)

        // Corrected before anything is driven, then the driving is recorded.
        try shifts.correctRunningShiftFuelAssumptions(van.defaults(gasPricePerGallon: money("4.00")), on: shift)
        try record(200, for: shift, context: context)
        try shifts.endActiveShift(at: at(3_600))

        let recorded = shift.recordedDistance()
        let cost = try #require(shift.fuelEstimate(for: recorded).cost)
        let miles = recorded.miles
        #expect(miles > 4, "The synthetic route covers a measurable distance")

        // gallons = miles / 20, cost = gallons * 4.00. Worked out under the
        // corrected pair, never under the one the shift started with.
        let underTheCorrection = Decimal(miles / 20 * 4)
        let underTheOriginal = Decimal(miles / 40 * 4)
        #expect(abs(cost.amount - underTheCorrection) < Decimal(string: "0.02")!)
        #expect(abs(cost.amount - underTheOriginal) > Decimal(string: "0.02")!)
    }

    /// The export is the shift's own snapshot, so a corrected shift exports the
    /// corrected figures with no export change at all.
    @Test("The export carries the corrected snapshot")
    func theExportFollowsTheCorrection() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let van = try settings.addVehicle(name: "The van", milesPerGallon: 20, createdAt: at(-300))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.correctRunningShiftFuelAssumptions(van.defaults(gasPricePerGallon: money("4.00")), on: shift)
        try shifts.endActiveShift(at: at(3_600))

        let record = try shift.exportRecord(for: shift.recordedDistance())

        #expect(record.fuelVehicleName == "The van")
        #expect(record.fuelMilesPerGallon?.value == 20)
        #expect(record.fuelGasPricePerGallon?.money == money("4.00"))
    }
}
