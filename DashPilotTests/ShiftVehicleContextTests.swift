import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What the running shift says about the vehicle it is being estimated under.
///
/// The claims under test are all one claim in different shapes: **it reads the
/// shift's own snapshot and never a preference**. A screen that filled the gap
/// from the current selection, or that followed a profile being renamed, would
/// be telling a driver their shift was worked under assumptions it was not.
@MainActor
@Suite("Active shift vehicle context")
struct ShiftVehicleContextTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: What it says

    @Test("A shift started under a selected vehicle names it and its economy")
    func namesTheVehicleTheShiftRecorded() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))

        let shift = try ShiftService(context: context).startShift(at: start)

        let vehicle = shift.vehicleContext
        #expect(vehicle.isRecorded)
        #expect(vehicle.title == "2020 Honda Civic")
        #expect(vehicle.economyStatement(locale: locale) == "34 MPG")
        #expect(vehicle.spokenLabel == "Shift vehicle")
        #expect(vehicle.spokenValue(locale: locale) == "2020 Honda Civic, 34 miles per gallon")
    }

    /// The fractional case, in the app's one fuel-economy vocabulary rather than
    /// in a second formatter written for a row.
    @Test("The economy is written the way Settings writes it")
    func writesTheEconomyInTheAppsOwnWords() {
        let vehicle = ShiftVehicleContext(vehicleName: "The van", milesPerGallon: Decimal(string: "18.50"))

        #expect(vehicle.economyStatement(locale: locale) == "18.5 MPG")
        #expect(vehicle.spokenValue(locale: locale) == "The van, 18.5 miles per gallon")
    }

    @Test("A shift that recorded nothing says so and borrows nothing")
    func saysNothingWasRecordedRatherThanBorrowing() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)

        // A vehicle and a price exist, and are selected, but they are recorded
        // *after* the shift began, so the shift recorded neither.
        let shift = try ShiftService(context: context).startShift(at: start)
        try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(60))
        try settings.setGasPricePerGallon(Money(amount: Decimal(string: "3.79")!))

        let vehicle = shift.vehicleContext
        #expect(vehicle.isRecorded == false)
        #expect(vehicle.vehicleName == nil)
        #expect(vehicle.milesPerGallon == nil)
        #expect(vehicle.title == "No vehicle recorded")
        #expect(vehicle.economyStatement(locale: locale) == nil)
        #expect(
            !vehicle.spokenValue(locale: locale).contains("Camry"),
            "The currently selected vehicle is a fact about the next shift, not this one"
        )
        #expect(!vehicle.spokenValue(locale: locale).contains("28"))
    }

    /// A driver with a current gas price and no selected vehicle. The store
    /// really holds an economy-less snapshot, so the row has to be able to say
    /// one half without the other.
    @Test("A shift that recorded a price and no vehicle still says no vehicle")
    func handlesAPriceWithNoVehicle() throws {
        let context = try makeContext()
        try SettingsService(context: context).setGasPricePerGallon(Money(amount: Decimal(string: "3.79")!))

        let shift = try ShiftService(context: context).startShift(at: start)

        #expect(shift.fuelAssumptions.gasPricePerGallon != nil, "The price was snapshotted")
        #expect(shift.vehicleContext.isRecorded == false)
        #expect(shift.vehicleContext.title == "No vehicle recorded")
        #expect(
            !shift.vehicleContext.spokenValue(locale: locale).contains("3.79"),
            "A gas price is not on the driving surface, spoken or printed"
        )
    }

    // MARK: What cannot move it

    @Test("Selecting a different vehicle mid-shift leaves the running shift where it is")
    func selectingAnotherVehicleDoesNotMoveTheRunningShift() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-300))

        let shift = try ShiftService(context: context).startShift(at: start)
        let before = shift.vehicleContext

        try settings.selectVehicle(camry)

        #expect(shift.vehicleContext == before)
        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(settings.selectedVehicle()?.name == "2012 Toyota Camry", "The next shift will record the Camry")
    }

    @Test("Renaming or correcting the profile leaves the running shift's snapshot alone")
    func editingTheProfileDoesNotMoveTheRunningShift() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))

        let shift = try ShiftService(context: context).startShift(at: start)

        try settings.updateVehicle(civic, name: "The Civic", milesPerGallon: 41)

        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.vehicleContext.milesPerGallon == 34)
        #expect(shift.fuelAssumptions.milesPerGallon == 34, "And the figure the estimate divides by is unmoved")
    }

    @Test("Deleting the profile leaves the running shift naming the vehicle it recorded")
    func deletingTheProfileLeavesTheSnapshotIntelligible() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))

        let shift = try ShiftService(context: context).startShift(at: start)
        try settings.deleteVehicle(civic)

        #expect(settings.selectedVehicle() == nil)
        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.vehicleContext.economyStatement(locale: locale) == "34 MPG")
    }

    @Test("Changing the current gas price moves nothing the row says")
    func changingTheGasPriceMovesNothing() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.setGasPricePerGallon(Money(amount: Decimal(string: "3.29")!))

        let shift = try ShiftService(context: context).startShift(at: start)
        let before = shift.vehicleContext

        try settings.setGasPricePerGallon(Money(amount: Decimal(string: "4.99")!))

        #expect(shift.vehicleContext == before)
        #expect(
            shift.fuelAssumptions.gasPricePerGallon?.amount == Decimal(string: "3.29"),
            "And the shift's own price snapshot did not follow it either"
        )
    }

    // MARK: Across a relaunch

    /// The store is the only place this lives, so a new process reads it back
    /// with no recovery code. Proved against a real reopened store rather than
    /// against a second context over the same one.
    @Test("A relaunch reads the running shift's vehicle back off the store")
    func survivesReopeningTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vehicle-context-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let shiftID: UUID
        do {
            let container = try ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            try SettingsService(context: context).addVehicle(
                name: "2020 Honda Civic",
                milesPerGallon: 34,
                createdAt: at(-600)
            )
            let shift = try ShiftService(context: context).startShift(at: start)
            shiftID = shift.id
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let shift = try #require(
            try reopened.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == shiftID })).first
        )

        #expect(shift.isActive, "Still running, which is the surface this row is on")
        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(shift.vehicleContext.economyStatement(locale: locale) == "34 MPG")
    }
}
