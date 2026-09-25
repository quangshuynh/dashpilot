import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a completed shift says about the vehicle it was worked in.
///
/// Every test here is the same claim in a different shape: **History reads the
/// shift's own snapshot and never a preference.** A finished shift that
/// followed a renamed profile, borrowed today's selection, or read a missing
/// figure as zero would be rewriting a driver's history after the fact.
@MainActor
@Suite("Recorded shift vehicle")
struct RecordedShiftVehicleTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    /// A shift started under a selected Civic and a current price, then ended.
    private func completedCivicShift(in context: ModelContext) throws -> (Shift, VehicleProfile) {
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.setGasPricePerGallon(try money("3.29"))
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        _ = try service.endActiveShift(at: at(3_600))
        return (shift, civic)
    }

    @Test("A completed shift reads the vehicle, economy and price it recorded")
    func readsItsOwnSnapshot() throws {
        let context = try makeContext()
        let (shift, _) = try completedCivicShift(in: context)

        let vehicle = shift.recordedVehicle
        #expect(vehicle.isRecorded)
        #expect(vehicle.title == "2020 Honda Civic")
        #expect(vehicle.detail(locale: locale) == "34 MPG · Gas $3.29/gal")
        #expect(
            vehicle.spokenLabel(locale: locale)
                == "Vehicle recorded with this shift: 2020 Honda Civic, 34 miles per gallon, gas $3.29 per gallon"
        )
    }

    @Test("Changing, renaming, reselecting and deleting in Settings rewrites nothing in History")
    func settingsCannotRewriteHistory() throws {
        let context = try makeContext()
        let (shift, civic) = try completedCivicShift(in: context)
        let before = shift.recordedVehicle

        let settings = SettingsService(context: context)
        try settings.updateVehicle(civic, name: "Renamed Car", milesPerGallon: 12)
        try settings.setGasPricePerGallon(try money("9.99"))
        let van = try settings.addVehicle(name: "Delivery Van", milesPerGallon: 18, createdAt: at(7_200))
        try settings.selectVehicle(van)
        try settings.deleteVehicle(civic)

        #expect(shift.recordedVehicle == before)

        // Read back through a fresh context, so the claim is about the store
        // and not about an object this test is still holding.
        let fresh = ModelContext(context.container)
        let id = shift.id
        let stored = try #require(try fresh.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.recordedVehicle == before)
        #expect(stored.recordedVehicle.title == "2020 Honda Civic")
    }

    @Test("A shift that recorded no vehicle stays unnamed while a vehicle is selected today")
    func noVehicleIsNeverBorrowed() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        _ = try service.endActiveShift(at: at(3_600))

        // Selected and priced only afterwards.
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(7_200))
        try settings.setGasPricePerGallon(try money("3.49"))

        let vehicle = shift.recordedVehicle
        #expect(!vehicle.isRecorded)
        #expect(vehicle.title == "Not recorded")
        #expect(vehicle.detail(locale: locale) == nil)
        #expect(vehicle.spokenLabel(locale: locale) == "No vehicle recorded for this shift")
    }

    @Test("An economy typed by hand is shown with no name, and no name is inferred from it")
    func handTypedEconomyHasNoName() throws {
        let context = try makeContext()
        // A profile exists whose economy matches exactly. That is not evidence
        // the shift was worked in it.
        try SettingsService(context: context).addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.end(at: at(3_600))
        try shift.setFuelAssumptions(milesPerGallon: 34, gasPricePerGallon: nil)

        let vehicle = shift.recordedVehicle
        #expect(vehicle.title == "Not recorded")
        #expect(vehicle.detail(locale: locale) == "34 MPG")
    }

    @Test("A recorded gas price of zero is said as a zero")
    func zeroGasPriceIsRecorded() throws {
        let vehicle = RecordedShiftVehicle(
            context: ShiftVehicleContext(vehicleName: "Synthetic Van", milesPerGallon: 20),
            gasPricePerGallon: .zero
        )

        #expect(vehicle.detail(locale: locale) == "20 MPG · Gas $0.00/gal")
        #expect(vehicle.spokenLabel(locale: locale).hasSuffix("gas $0.00 per gallon"))
    }

    @Test("A missing economy or price is left out, never shown as zero")
    func missingIsNotZero() throws {
        let priceOnly = RecordedShiftVehicle(
            context: ShiftVehicleContext(vehicleName: nil, milesPerGallon: nil),
            gasPricePerGallon: try money("3.29")
        )
        #expect(priceOnly.isRecorded)
        #expect(priceOnly.detail(locale: locale) == "Gas $3.29/gal")
        #expect(priceOnly.detail(locale: locale)?.contains("0 MPG") == false)

        let economyOnly = RecordedShiftVehicle(
            context: ShiftVehicleContext(vehicleName: "Synthetic Hatchback", milesPerGallon: 25),
            gasPricePerGallon: nil
        )
        #expect(economyOnly.detail(locale: locale) == "25 MPG")
        #expect(!economyOnly.spokenLabel(locale: locale).contains("$0.00"))
    }

    @Test("A name recorded afterwards is described as recorded with the shift, not at its start")
    func wordingIsTrueOfLaterEntries() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.end(at: at(3_600))
        try shift.setFuelAssumptions(
            milesPerGallon: 34,
            gasPricePerGallon: try money("3.29"),
            vehicleName: "2020 Honda Civic"
        )

        let spoken = shift.recordedVehicle.spokenLabel(locale: locale)
        #expect(spoken.hasPrefix("Vehicle recorded with this shift: 2020 Honda Civic"))
        #expect(!spoken.contains("started"))
    }
}
