import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What the Home screen says the next shift will record, before it is started.
///
/// The claims under test are one claim in different shapes: **the row beside
/// `Start Shift` says exactly what the start copies**, and it stops mattering
/// the moment the shift exists. Every agreement test builds the context the way
/// the screen does, from the observed rows through
/// ``SettingsService/fuelDefaults(settings:vehicles:)``, and compares it with the
/// snapshot ``ShiftService/startShift(at:)`` actually wrote.
@MainActor
@Suite("Next shift vehicle context")
struct NextShiftVehicleContextTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func price(_ text: String) -> Money { Money(amount: Decimal(string: text)!) }

    /// The context the Home screen draws: every profile and the settings row,
    /// resolved by the shared rule, exactly as `StartShiftPanel` observes them.
    private func nextShiftVehicle(in context: ModelContext) throws -> NextShiftVehicleContext {
        let settings = SettingsService(context: context)
        return NextShiftVehicleContext(
            defaults: SettingsService.fuelDefaults(
                settings: try settings.existingSettings(),
                vehicles: settings.vehicleProfiles()
            )
        )
    }

    /// Asserts the shift recorded exactly what the row said it would.
    private func expectAgreement(_ shown: NextShiftVehicleContext, with shift: Shift) {
        #expect(shift.fuelVehicleName == shown.vehicleName)
        #expect(shift.fuelMilesPerGallonValue == shown.milesPerGallon)
        #expect(shift.fuelAssumptions.gasPricePerGallon == shown.gasPricePerGallon)
    }

    // MARK: Agreement with the start

    @Test("The selected profile is what the row names and what the start snapshots")
    func selectedProfileIsWhatTheStartSnapshots() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.setGasPricePerGallon(price("3.29"))

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.title == "2020 Honda Civic")
        #expect(shown.detail(locale: locale) == "34 MPG · Gas $3.29/gal")
        #expect(shown.spokenLabel == "Next shift vehicle")
        #expect(shown.spokenValue(locale: locale) == "2020 Honda Civic, 34 miles per gallon, gas $3.29 per gallon")

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
        #expect(shift.vehicleContext.title == shown.title)
    }

    /// The screen reads every profile and the service reads only the selected
    /// one. The shared rule is what makes those two inputs give one answer.
    @Test("The screen's reading and the start's reading are the same value")
    func screenAndStartReadTheSameDefaults() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "The van", milesPerGallon: 18, createdAt: at(-900))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-600))
        try settings.selectVehicle(camry)
        try settings.setGasPricePerGallon(price("3.79"))

        let shown = try nextShiftVehicle(in: context)
        #expect(shown == NextShiftVehicleContext(defaults: settings.currentFuelDefaults()))
        #expect(shown.vehicleName == "2012 Toyota Camry")
    }

    @Test("Changing the selection before starting changes what the next shift receives")
    func changedSelectionBeforeStartIsWhatTheShiftReceives() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-900))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-600))
        #expect(try nextShiftVehicle(in: context).vehicleName == "2020 Honda Civic")

        try settings.selectVehicle(camry)
        let shown = try nextShiftVehicle(in: context)
        #expect(shown.vehicleName == "2012 Toyota Camry")
        #expect(shown.detail(locale: locale) == "28 MPG")

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
    }

    // MARK: Missing and incomplete

    @Test("No selected vehicle is said, and does not prevent a start")
    func noSelectedVehicleDoesNotPreventAStart() throws {
        let context = try makeContext()

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.hasVehicle == false)
        #expect(shown.title == "No vehicle selected")
        #expect(shown.detail(locale: locale) == nil, "Nothing known is nothing written, never 0 MPG or $0.00")
        #expect(shown.spokenValue(locale: locale) == "No vehicle selected for the next shift")

        let shift = try ShiftService(context: context).startShift(at: start)
        #expect(shift.endedAt == nil)
        #expect(shift.fuelAssumptions.hasAny == false)
        #expect(shift.vehicleContext == .none, "The shift invents no vehicle either")
        expectAgreement(shown, with: shift)
    }

    /// Profiles exist but none is selected, because the selection was cleared.
    /// The row does not pick one on the driver's behalf.
    @Test("Profiles with none selected choose nothing")
    func profilesWithNoSelectionChooseNothing() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.selectVehicle(nil)

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.vehicleName == nil)
        #expect(shown.milesPerGallon == nil)

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
    }

    @Test("A price with no vehicle says both halves as they are, and still starts")
    func incompleteDefaultsAreSaidTruthfully() throws {
        let context = try makeContext()
        try SettingsService(context: context).setGasPricePerGallon(price("3.29"))

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.title == "No vehicle selected")
        #expect(shown.detail(locale: locale) == "Gas $3.29/gal")
        #expect(!shown.detail(locale: locale)!.contains("MPG"), "A missing economy is left out, not written as 0")
        #expect(
            shown.spokenValue(locale: locale) == "No vehicle selected for the next shift, gas $3.29 per gallon"
        )

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
    }

    @Test("A vehicle with no price leaves the price out rather than writing $0.00")
    func vehicleWithNoPriceWritesNoPrice() throws {
        let context = try makeContext()
        try SettingsService(context: context).addVehicle(name: "The van", milesPerGallon: 18, createdAt: at(-600))

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.detail(locale: locale) == "18 MPG")
        #expect(!shown.spokenValue(locale: locale).contains("$"))

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
    }

    /// Zero is a price the settings may hold, so it is a recorded fact and is
    /// said, unlike a missing one.
    @Test("A recorded zero price is said, because it is a fact")
    func recordedZeroPriceIsSaid() throws {
        let context = try makeContext()
        try SettingsService(context: context).setGasPricePerGallon(price("0"))

        #expect(try nextShiftVehicle(in: context).detail(locale: locale) == "Gas $0.00/gal")
    }

    @Test("Deleting the selected profile reads as no vehicle, and borrows nothing")
    func deletingTheSelectedProfileResolvesSafely() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "The van", milesPerGallon: 18, createdAt: at(-900))
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        try settings.selectVehicle(civic)
        try settings.deleteVehicle(civic)

        let shown = try nextShiftVehicle(in: context)
        #expect(shown.vehicleName == nil, "Neither the deleted profile nor the remaining one is chosen")
        #expect(shown.milesPerGallon == nil)

        let shift = try ShiftService(context: context).startShift(at: start)
        expectAgreement(shown, with: shift)
    }

    /// The rule itself, with an identifier no profile carries: what a selection
    /// left pointing at a deleted row would look like if anything left one.
    @Test("A selection naming no profile is no vehicle")
    func danglingSelectionIsNoVehicle() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-600))
        let row = try settings.settings()
        row.selectVehicle(id: UUID())

        let defaults = SettingsService.fuelDefaults(settings: row, vehicles: [civic])
        #expect(defaults.vehicleName == nil)
        #expect(defaults.assumptions.milesPerGallon == nil)
    }

    // MARK: After the start

    @Test("After the start, changing Settings changes the next shift and never this one")
    func settingsChangesAfterStartDoNotMoveTheSnapshot() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: 34, createdAt: at(-900))
        let camry = try settings.addVehicle(name: "2012 Toyota Camry", milesPerGallon: 28, createdAt: at(-600))
        try settings.setGasPricePerGallon(price("3.29"))

        let shown = try nextShiftVehicle(in: context)
        let shift = try ShiftService(context: context).startShift(at: start)

        try settings.selectVehicle(camry)
        try settings.updateVehicle(civic, name: "Renamed", milesPerGallon: 40)
        try settings.setGasPricePerGallon(price("4.09"))

        expectAgreement(shown, with: shift)
        #expect(shift.vehicleContext.title == "2020 Honda Civic")
        #expect(try nextShiftVehicle(in: context).vehicleName == "2012 Toyota Camry")

        try settings.deleteVehicle(civic)
        expectAgreement(shown, with: shift)
    }

    // MARK: Reading writes nothing

    /// A driver who has never opened Settings looks at Home on every launch, so
    /// looking must not create the settings row or anything else.
    @Test("Reading the next shift's vehicle writes nothing")
    func readingWritesNothing() throws {
        let context = try makeContext()

        _ = try nextShiftVehicle(in: context)
        _ = SettingsService(context: context).currentFuelDefaults()

        #expect(context.hasChanges == false)
        let rows = try context.fetch(FetchDescriptor<DriverSettings>())
        let shifts = try context.fetch(FetchDescriptor<Shift>())
        #expect(rows.isEmpty)
        #expect(shifts.isEmpty, "Nothing is started early to show what would be recorded")
    }

    @Test("Still no relationship joins a shift to a vehicle profile")
    func noShiftToProfileRelationship() throws {
        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(shift.relationships.allSatisfy { $0.destination != "VehicleProfile" })
    }
}
