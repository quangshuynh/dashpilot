import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The driver's reusable settings: their vehicles, the one they are working in,
/// the gas price they last entered, and the snapshot a starting shift takes of
/// all three.
///
/// **The tests that matter most here assert an absence.** A vehicle can be
/// renamed, re-measured, deselected and deleted, and the gas price can move
/// every day, and none of it may touch a shift already recorded. Each of those
/// is checked by recording a shift, changing the setting, and asserting the
/// shift's economy, price, vehicle name, estimate and net are the figures they
/// were, rather than by asserting that some rule was consulted.
@MainActor
@Suite("Vehicle profiles and driver settings")
struct VehicleSettingsTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ModelContext(container)
    }

    private func economy(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    /// A measured route covering `miles`, with no detected gap. The same helper
    /// `FuelEstimateTests` uses, so a distance here is stated in miles.
    private func route(miles: Double) -> RouteDistance {
        RouteDistance(
            metres: miles * 1_609.344,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 10,
            usesInferredContinuity: false
        )
    }

    // MARK: Profiles

    @Test("A profile records the name and the fuel economy exactly as entered")
    func createsAProfile() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let profile = try service.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"))

        #expect(profile.name == "2020 Honda Civic")
        #expect(profile.milesPerGallon == (try economy("34")))
        #expect(service.vehicleProfiles().map(\.name) == ["2020 Honda Civic"])
    }

    @Test("A name is trimmed, and an empty one is refused rather than stored as absence")
    func refusesAnEmptyName() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let profile = try service.addVehicle(name: "  the van  ", milesPerGallon: try economy("22"))
        #expect(profile.name == "the van", "Invisible whitespace must not make two identical names different")

        #expect(throws: SettingsError.invalidVehicle(.invalidName(.empty))) {
            try service.addVehicle(name: "   ", milesPerGallon: try economy("22"))
        }
        #expect(service.vehicleProfiles().count == 1, "A refused profile writes nothing")
    }

    @Test("A name longer than the limit is refused")
    func refusesAnOverlongName() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let tooLong = String(repeating: "a", count: VehicleName.maximumLength + 1)
        #expect(
            throws: SettingsError.invalidVehicle(
                .invalidName(.tooLong(maximumLength: VehicleName.maximumLength))
            )
        ) {
            try service.addVehicle(name: tooLong, milesPerGallon: try economy("22"))
        }
    }

    @Test("A fuel economy of zero or less is refused, because it is the divisor")
    func refusesAnInvalidFuelEconomy() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        #expect(throws: SettingsError.invalidVehicle(.invalidFuelEconomy)) {
            try service.addVehicle(name: "Zero", milesPerGallon: .zero)
        }
        #expect(throws: SettingsError.invalidVehicle(.invalidFuelEconomy)) {
            try service.addVehicle(name: "Negative", milesPerGallon: Decimal(-5))
        }
        #expect(service.vehicleProfiles().isEmpty)
    }

    @Test("Several profiles are kept, in the order they were added")
    func keepsSeveralProfiles() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        try service.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"), createdAt: start)
        try service.addVehicle(
            name: "2012 Toyota Camry",
            milesPerGallon: try economy("28"),
            createdAt: start.addingTimeInterval(60)
        )
        try service.addVehicle(
            name: "the van",
            milesPerGallon: try economy("18"),
            createdAt: start.addingTimeInterval(120)
        )

        #expect(service.vehicleProfiles().map(\.name) == ["2020 Honda Civic", "2012 Toyota Camry", "the van"])
    }

    @Test("An edit moves both facts, or neither")
    func editsAProfile() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)
        let profile = try service.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"))

        try service.updateVehicle(profile, name: "2020 Honda Civic Hybrid", milesPerGallon: try economy("42"))
        #expect(profile.name == "2020 Honda Civic Hybrid")
        #expect(profile.milesPerGallon == (try economy("42")))

        #expect(throws: SettingsError.invalidVehicle(.invalidFuelEconomy)) {
            try service.updateVehicle(profile, name: "A name that was fine", milesPerGallon: .zero)
        }
        #expect(profile.name == "2020 Honda Civic Hybrid", "A refused edit leaves the name it had")
        #expect(profile.milesPerGallon == (try economy("42")))
    }

    @Test("The first profile is selected; a later one is not, until it is asked for")
    func selectsTheFirstProfileOnly() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let first = try service.addVehicle(name: "First", milesPerGallon: try economy("30"), createdAt: start)
        #expect(service.selectedVehicle()?.id == first.id)

        let second = try service.addVehicle(
            name: "Second",
            milesPerGallon: try economy("20"),
            createdAt: start.addingTimeInterval(60)
        )
        #expect(service.selectedVehicle()?.id == first.id, "Adding a vehicle is not choosing one")

        try service.selectVehicle(second)
        #expect(service.selectedVehicle()?.id == second.id)

        try service.selectVehicle(nil)
        #expect(service.selectedVehicle() == nil, "There has to be a way back to no vehicle selected")
    }

    @Test("Deleting a profile removes it, and clears the selection when it was the selected one")
    func deletesAProfile() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let civic = try service.addVehicle(name: "Civic", milesPerGallon: try economy("34"), createdAt: start)
        let camry = try service.addVehicle(
            name: "Camry",
            milesPerGallon: try economy("28"),
            createdAt: start.addingTimeInterval(60)
        )
        try service.selectVehicle(camry)

        try service.deleteVehicle(camry)
        #expect(service.vehicleProfiles().map(\.name) == ["Civic"])
        #expect(service.selectedVehicle() == nil, "A selection pointing at a deleted row is no selection")

        try service.deleteVehicle(civic)
        #expect(service.vehicleProfiles().isEmpty)
    }

    // MARK: The current gas price

    @Test("The gas price is recorded, corrected and removed, and zero is not missing")
    func recordsTheCurrentGasPrice() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        #expect(try service.settings().gasPricePerGallon == nil)

        try service.setGasPricePerGallon(Money(minorUnits: 319))
        #expect(try service.settings().gasPricePerGallon == Money(minorUnits: 319))

        try service.setGasPricePerGallon(Money(minorUnits: 335))
        #expect(try service.settings().gasPricePerGallon == Money(minorUnits: 335))

        // A recorded zero is a fact: the fuel is recorded as costing nothing.
        try service.setGasPricePerGallon(.zero)
        #expect(try service.settings().gasPricePerGallon == Money.zero)

        try service.clearGasPricePerGallon()
        #expect(try service.settings().gasPricePerGallon == nil, "Removed is not zero")
    }

    @Test("A negative gas price is refused, and nothing is written")
    func refusesANegativeGasPrice() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)
        try service.setGasPricePerGallon(Money(minorUnits: 319))

        #expect(throws: SettingsError.invalidSettings(.negativeGasPrice)) {
            try service.setGasPricePerGallon(Money(minorUnits: -100))
        }
        #expect(try service.settings().gasPricePerGallon == Money(minorUnits: 319))
    }

    @Test("There is one settings row however many times it is asked for")
    func settingsAreASingleton() throws {
        let context = try makeContext()
        let service = SettingsService(context: context)

        let first = try service.settings()
        let second = try service.settings()
        #expect(first.id == second.id)
        #expect(first.id == DriverSettings.singletonID)

        let all = try context.fetch(FetchDescriptor<DriverSettings>())
        #expect(all.count == 1)
    }

    // MARK: The snapshot a shift takes

    @Test("Starting a shift records the selected vehicle's economy, the gas price and the vehicle's name")
    func startingAShiftTakesTheSnapshot() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        let shift = try ShiftService(context: context).startShift(at: start)

        #expect(shift.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))
        #expect(shift.fuelVehicleName == "2020 Honda Civic")
    }

    @Test("With nothing set, a shift starts recording nothing, exactly as it always did")
    func startingAShiftWithNoDefaultsRecordsNothing() throws {
        let context = try makeContext()
        let shift = try ShiftService(context: context).startShift(at: start)

        #expect(shift.fuelAssumptions == .none)
        #expect(shift.fuelVehicleName == nil)
        #expect(
            shift.fuelEstimate(for: route(miles: 50)) == .unavailable(.milesPerGallonNotRecorded),
            "No assumption is not an assumption of zero"
        )
    }

    @Test("Each half of the snapshot is independent: a vehicle with no price, a price with no vehicle")
    func eachHalfOfTheSnapshotIsIndependent() throws {
        let vehicleOnly = try makeContext()
        try SettingsService(context: vehicleOnly).addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        let withVehicle = try ShiftService(context: vehicleOnly).startShift(at: start)
        #expect(withVehicle.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(withVehicle.fuelAssumptions.gasPricePerGallon == nil)
        #expect(withVehicle.fuelVehicleName == "Civic")

        let priceOnly = try makeContext()
        try SettingsService(context: priceOnly).setGasPricePerGallon(Money(minorUnits: 319))
        let withPrice = try ShiftService(context: priceOnly).startShift(at: start)
        #expect(withPrice.fuelAssumptions.milesPerGallon == nil)
        #expect(withPrice.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))
        #expect(withPrice.fuelVehicleName == nil, "A name without an economy would name nothing")
    }

    @Test("A deselected vehicle stops reaching new shifts")
    func aDeselectedVehicleStopsReachingNewShifts() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let shifts = ShiftService(context: context)
        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))

        let before = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))
        #expect(before.fuelAssumptions.milesPerGallon == (try economy("34")))

        try settings.selectVehicle(nil)
        let after = try shifts.startShift(at: start.addingTimeInterval(7_200))
        #expect(after.fuelAssumptions.milesPerGallon == nil)
        #expect(before.fuelAssumptions.milesPerGallon == (try economy("34")), "And the earlier shift keeps its own")
    }

    @Test("The snapshot fills an empty pair and never overwrites a recorded one")
    func theSnapshotOnlyEverFillsAnEmptyPair() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))
        try shifts.setFuelAssumptions(
            milesPerGallon: try economy("25"),
            gasPricePerGallon: Money(minorUnits: 350),
            on: shift
        )

        #expect(throws: ShiftError.shiftAlreadyEnded) {
            try shift.recordStartingFuelDefaults(
                FuelDefaults(vehicleName: "Other", milesPerGallon: try economy("50"), gasPricePerGallon: .zero)
            )
        }
        #expect(shift.fuelAssumptions.milesPerGallon == (try economy("25")))

        let running = try shifts.startShift(at: start.addingTimeInterval(7_200))
        try running.recordStartingFuelDefaults(
            FuelDefaults(vehicleName: "First", milesPerGallon: try economy("30"), gasPricePerGallon: nil)
        )
        #expect(throws: ShiftError.fuelAssumptionsAlreadyRecorded) {
            try running.recordStartingFuelDefaults(
                FuelDefaults(vehicleName: "Second", milesPerGallon: try economy("40"), gasPricePerGallon: nil)
            )
        }
        #expect(running.fuelVehicleName == "First")
    }

    // MARK: Historical stability, which is what the whole design is for

    @Test("Editing a vehicle's fuel economy does not move a shift recorded under the old one")
    func editingAVehicleLeavesRecordedShiftsAlone() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let shifts = ShiftService(context: context)

        let civic = try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 300))
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        let before = try #require(shift.fuelEstimate(for: route(miles: 68)).consumption)

        try settings.updateVehicle(civic, name: "Civic Hybrid", milesPerGallon: try economy("50"))

        #expect(shift.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(shift.fuelVehicleName == "Civic", "The shift recorded what the vehicle was called at the time")
        let after = try #require(shift.fuelEstimate(for: route(miles: 68)).consumption)
        #expect(after.cost == before.cost)
        #expect(after.gallons == before.gallons)
    }

    @Test("Deleting a vehicle does not damage a shift recorded under it")
    func deletingAVehicleLeavesRecordedShiftsAlone() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let shifts = ShiftService(context: context)

        let civic = try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 300))
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))
        try shifts.setGrossEarnings(Money(minorUnits: 12_000), on: shift)

        let before = try #require(shift.fuelEstimate(for: route(miles: 68)).consumption)
        let netBefore = shift.profitability(for: route(miles: 68)).estimatedNetAfterFuel

        try settings.deleteVehicle(civic)

        #expect(shift.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 300))
        #expect(shift.fuelVehicleName == "Civic", "A shift stays intelligible with no profile behind it")
        let after = try #require(shift.fuelEstimate(for: route(miles: 68)).consumption)
        #expect(after.cost == before.cost)
        #expect(shift.profitability(for: route(miles: 68)).estimatedNetAfterFuel == netBefore)
    }

    @Test("Changing the current gas price does not move a shift recorded under the old one")
    func changingTheGasPriceLeavesRecordedShiftsAlone() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let shifts = ShiftService(context: context)

        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))
        let yesterday = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        try settings.setGasPricePerGallon(Money(minorUnits: 500))

        #expect(yesterday.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))

        let today = try shifts.startShift(at: start.addingTimeInterval(24 * 3_600))
        #expect(today.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 500), "The next shift gets the new one")
    }

    @Test("Switching the selected vehicle moves the next shift and nothing before it")
    func switchingVehiclesMovesOnlyTheNextShift() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let shifts = ShiftService(context: context)

        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"), createdAt: start)
        let camry = try settings.addVehicle(
            name: "Camry",
            milesPerGallon: try economy("28"),
            createdAt: start.addingTimeInterval(60)
        )
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        let inTheCivic = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        try settings.selectVehicle(camry)
        let inTheCamry = try shifts.startShift(at: start.addingTimeInterval(24 * 3_600))

        #expect(inTheCivic.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(inTheCivic.fuelVehicleName == "Civic")
        #expect(inTheCamry.fuelAssumptions.milesPerGallon == (try economy("28")))
        #expect(inTheCamry.fuelVehicleName == "Camry")
    }

    @Test("An older shift with no assumptions keeps none, whatever the settings say")
    func anOlderShiftWithNoAssumptionsStaysMissing() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let settings = SettingsService(context: context)

        // Worked before there were any settings to copy.
        let old = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))
        #expect(old.fuelAssumptions == .none)

        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        #expect(old.fuelAssumptions == .none, "Nothing backfills a shift the driver never entered figures for")
        #expect(old.fuelVehicleName == nil)
        #expect(old.fuelEstimate(for: route(miles: 68)) == .unavailable(.milesPerGallonNotRecorded))
    }

    @Test("Applying the current defaults to an older shift is a write the driver makes, and it snapshots")
    func applyingTheCurrentDefaultsToAnOlderShift() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let settings = SettingsService(context: context)

        let old = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))
        let defaults = settings.currentFuelDefaults()

        // What the editor's `Use Current Defaults` produces: the fields filled
        // from the defaults, then an ordinary save.
        try shifts.setFuelAssumptions(
            milesPerGallon: defaults.assumptions.milesPerGallon,
            gasPricePerGallon: defaults.assumptions.gasPricePerGallon,
            vehicleName: defaults.vehicleName(accompanying: defaults.assumptions.milesPerGallon),
            on: old
        )

        #expect(old.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(old.fuelVehicleName == "Civic")

        // And it is a snapshot from that moment, not a subscription.
        try settings.setGasPricePerGallon(Money(minorUnits: 999))
        #expect(old.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))
    }

    // MARK: The vehicle name follows the economy

    @Test("A hand-typed economy records no vehicle, because DashPilot does not know which one it is")
    func aHandTypedEconomyNamesNoVehicle() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))
        #expect(shift.fuelVehicleName == "Civic")

        let defaults = settings.currentFuelDefaults()
        let typed = try economy("21")
        try shifts.setFuelAssumptions(
            milesPerGallon: typed,
            gasPricePerGallon: Money(minorUnits: 319),
            vehicleName: defaults.vehicleName(accompanying: typed),
            on: shift
        )

        #expect(shift.fuelAssumptions.milesPerGallon == typed)
        #expect(shift.fuelVehicleName == nil, "A different economy is a different vehicle as far as the app can tell")
    }

    @Test("Correcting only the gas price keeps the vehicle the shift already named")
    func correctingThePriceKeepsTheVehicle() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))

        try shifts.setFuelAssumptions(
            milesPerGallon: try economy("34"),
            gasPricePerGallon: Money(minorUnits: 289),
            on: shift
        )

        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 289))
        #expect(shift.fuelVehicleName == "Civic", "The economy did not move, so the label it describes still holds")
    }

    @Test("Removing the assumptions removes the vehicle name with them")
    func removingTheAssumptionsRemovesTheName() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("34"))

        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))
        #expect(shift.fuelVehicleName == "Civic")

        try shifts.clearFuelAssumptions(on: shift)
        #expect(shift.fuelVehicleName == nil)
        #expect(shift.fuelAssumptions == .none)
    }

    @Test("A name accompanies an economy only when it is that vehicle's economy")
    func theNameRuleIsOwnedByTheDefaults() throws {
        let defaults = FuelDefaults(
            vehicleName: "Civic",
            milesPerGallon: try economy("34"),
            gasPricePerGallon: Money(minorUnits: 319)
        )

        #expect(defaults.vehicleName(accompanying: try economy("34")) == "Civic")
        #expect(defaults.vehicleName(accompanying: try economy("34.0")) == "Civic", "Trailing zeroes are the same number")
        #expect(defaults.vehicleName(accompanying: try economy("28")) == nil)
        #expect(defaults.vehicleName(accompanying: nil) == nil)
        #expect(FuelDefaults.none.vehicleName(accompanying: try economy("34")) == nil)
    }

    // MARK: The estimate still follows the route

    @Test("A snapshotted shift's estimate is still derived from its recorded mileage")
    func theEstimateStillFollowsRecordedMileage() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "Civic", milesPerGallon: try economy("25"))
        try settings.setGasPricePerGallon(Money(minorUnits: 400))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        // 50 recorded miles at 25 MPG is 2 gallons, at $4.00 is $8.00.
        let consumption = try #require(shift.fuelEstimate(for: route(miles: 50)).consumption)
        #expect(consumption.cost == Money(minorUnits: 800))

        // Half the recorded mileage, half the fuel. Nothing about the snapshot
        // changes that the numerator is what the route measured.
        let half = try #require(shift.fuelEstimate(for: route(miles: 25)).consumption)
        #expect(half.cost == Money(minorUnits: 400))
    }
}
