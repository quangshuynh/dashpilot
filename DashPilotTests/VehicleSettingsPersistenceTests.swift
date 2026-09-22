import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v15: the two new entities, the one new column, and the migration that
/// writes nothing into any of them.
///
/// **The migration's whole claim is an absence.** A v14 store holds no evidence
/// of which vehicle any shift was worked in, because no build that wrote one had
/// vehicles, so a migrated store opens with no profiles, no settings row and no
/// vehicle name anywhere — while every shift keeps the fuel economy, gas price
/// and estimate it already had.
@MainActor
@Suite("Vehicle and settings persistence")
struct VehicleSettingsPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func economy(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v15 is the current version.
    ///
    /// The repository's convention is that the count of versions and stages
    /// lives in the suite belonging to whichever version is current, so it is
    /// updated in one place rather than in several. It moved here from
    /// `FuelAssumptionPersistenceTests`, which owned it while v14 was current.
    @Test("Version 15 is the current version, and it is the one that adds the settings")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV15.versionIdentifier == Schema.Version(15, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 15)
        #expect(DashPilotMigrationPlan.stages.count == 14)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV15.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause", "Offer",
                "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v15 adds exactly two entities and drops none"
        )
    }

    /// The claim the whole design rests on, read straight off the schema:
    /// nothing joins a shift to a vehicle.
    @Test("No relationship connects a shift to a vehicle profile, in either direction")
    func historyDoesNotDependOnAProfile() throws {
        let schema = ModelContainerFactory.currentSchema

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        #expect(
            shift.relationships.allSatisfy { $0.destination != "VehicleProfile" },
            "A shift holding a reference to a preference is a history that can be deleted"
        )
        #expect(shift.properties.map(\.name).contains("fuelVehicleName"))

        let vehicle = try #require(schema.entities.first { $0.name == "VehicleProfile" })
        #expect(vehicle.relationships.isEmpty, "A vehicle points at nothing, so deleting one cascades nowhere")
        #expect(Set(vehicle.properties.map(\.name)) == ["id", "name", "milesPerGallonValue", "createdAt"])

        let settings = try #require(schema.entities.first { $0.name == "DriverSettings" })
        #expect(
            settings.relationships.isEmpty,
            "The selected vehicle is an identifier, so a deleted profile reads as no selection"
        )
        #expect(
            Set(settings.properties.map(\.name)) == ["id", "gasPricePerGallonAmount", "selectedVehicleID"]
        )
    }

    @Test("The frozen version 14 still describes a shift that can record no vehicle")
    func versionFourteenHeldNoVehicle() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV14.self)

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))

        #expect(properties.contains("fuelMilesPerGallonValue"), "v14 is the version that added the assumptions")
        #expect(properties.contains("fuelGasPricePerGallonAmount"))
        #expect(
            !properties.contains("fuelVehicleName"),
            "The frozen v14 model must describe the store as it was, not as it is now"
        )

        let entities = Set(schema.entities.map(\.name))
        #expect(!entities.contains("VehicleProfile"))
        #expect(!entities.contains("DriverSettings"))
        #expect(entities.contains("DeliveryTip"), "And it keeps everything v13 added")
    }

    @Test("The step from version 14 is lightweight, because there is nothing truthful to write")
    func theStepIsLightweight() {
        // Three tempting backfills, all refused: inventing a vehicle profile out
        // of the economies shifts already record, attributing those shifts to a
        // vehicle the store holds no evidence of, and turning one shift's
        // recorded gas price into a current preference.
        #expect(DashPilotMigrationPlan.stages.count == DashPilotMigrationPlan.schemas.count - 1)
    }

    // MARK: Migration

    @Test("Every version 14 shift reaches version 15 with its assumptions intact and no vehicle invented")
    func migratesFromVersionFourteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let estimatedID = UUID()
        let bareID = UUID()

        do {
            let v14 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV14.self, at: storeURL)
            let context = ModelContext(v14)

            let estimated = DashPilotSchemaV14.Shift(
                id: estimatedID,
                startedAt: start,
                endedAt: start.addingTimeInterval(4 * 3_600),
                grossEarningsAmount: Decimal(120),
                fuelMilesPerGallonValue: try economy("34"),
                fuelGasPricePerGallonAmount: try economy("3.19")
            )
            let bare = DashPilotSchemaV14.Shift(
                id: bareID,
                startedAt: start.addingTimeInterval(24 * 3_600),
                endedAt: start.addingTimeInterval(24 * 3_600 + 3_600)
            )
            context.insert(estimated)
            context.insert(bare)
            try context.save()
        }

        let migrated = try ModelContainerFactory.makeContainer(at: storeURL)
        let context = ModelContext(migrated)

        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(shifts.count == 2)

        let estimated = try #require(shifts.first { $0.id == estimatedID })
        #expect(estimated.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(estimated.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))
        #expect(estimated.grossEarnings == Money(minorUnits: 12_000))
        #expect(
            estimated.fuelVehicleName == nil,
            "A v14 store holds no evidence of which vehicle a shift was worked in"
        )

        let bare = try #require(shifts.first { $0.id == bareID })
        #expect(bare.fuelAssumptions == .none, "A shift that recorded nothing still records nothing")
        #expect(bare.fuelVehicleName == nil)

        #expect(try context.fetch(FetchDescriptor<VehicleProfile>()).isEmpty, "No vehicle is invented")
        #expect(
            try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty,
            "The settings row is created when the driver opens Settings, not by a migration"
        )
    }

    @Test("A version 13 store still reaches the current version, recording nothing about fuel or vehicles")
    func migratesFromVersionThirteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()

        do {
            let v13 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV13.self, at: storeURL)
            let context = ModelContext(v13)
            context.insert(
                DashPilotSchemaV13.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(3 * 3_600),
                    grossEarningsAmount: Decimal(90)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.grossEarnings == Money(minorUnits: 9_000), "The v12 and v13 guarantees still hold")
        #expect(shift.fuelAssumptions == .none)
        #expect(shift.fuelVehicleName == nil)
        #expect(try context.fetch(FetchDescriptor<VehicleProfile>()).isEmpty)
    }

    // MARK: Reopening

    @Test("Vehicles, the selection and the gas price all survive being written and read back")
    func settingsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let camryID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let service = SettingsService(context: context)
            try service.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"), createdAt: start)
            let camry = try service.addVehicle(
                name: "2012 Toyota Camry",
                milesPerGallon: try economy("28"),
                createdAt: start.addingTimeInterval(60)
            )
            camryID = camry.id
            try service.selectVehicle(camry)
            try service.setGasPricePerGallon(Money(minorUnits: 319))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let service = SettingsService(context: context)

        #expect(service.vehicleProfiles().map(\.name) == ["2020 Honda Civic", "2012 Toyota Camry"])
        #expect(service.selectedVehicle()?.id == camryID)
        #expect(try service.settings().gasPricePerGallon == Money(minorUnits: 319))

        let defaults = service.currentFuelDefaults()
        #expect(defaults.vehicleName == "2012 Toyota Camry")
        #expect(defaults.assumptions.milesPerGallon == (try economy("28")))
        #expect(defaults.assumptions.gasPricePerGallon == Money(minorUnits: 319))
    }

    @Test("A shift's snapshot survives a reopen, and survives its vehicle being deleted")
    func aSnapshotSurvivesAReopenAndADeletedVehicle() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let settings = SettingsService(context: context)
            let civic = try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"))
            try settings.setGasPricePerGallon(Money(minorUnits: 319))

            let shifts = ShiftService(context: context)
            let shift = try shifts.startShift(at: start)
            try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))
            shiftID = shift.id

            try settings.deleteVehicle(civic)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(
            try context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == shiftID })).first
        )

        #expect(shift.fuelAssumptions.milesPerGallon == (try economy("34")))
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 319))
        #expect(shift.fuelVehicleName == "2020 Honda Civic")
        #expect(try context.fetch(FetchDescriptor<VehicleProfile>()).isEmpty)
    }

    // MARK: Export

    @Test("The shift's recorded vehicle name is exported; the driver's current settings are not")
    func exportCarriesTheSnapshotAndNotThePreferences() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let settings = SettingsService(context: context)
        try settings.addVehicle(name: "2020 Honda Civic", milesPerGallon: try economy("34"))
        try settings.setGasPricePerGallon(Money(minorUnits: 319))

        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(4 * 3_600))

        let record = try shift.exportRecord(for: shift.recordedDistance())
        #expect(record.fuelVehicleName == "2020 Honda Civic")

        let document = ExportDocument(
            scope: .allHistory,
            shifts: [record],
            summary: nil,
            exportedAt: start
        )
        let text = try #require(String(data: try ExportDocumentEncoder().json(for: document), encoding: .utf8))

        #expect(text.contains("\"fuelVehicleName\""))
        // The shift's own snapshot is in the file. Nothing about the driver's
        // current preferences is: an export is a record of work done.
        #expect(!text.contains("selectedVehicleID"))
        #expect(!text.contains("\"vehicles\""))
        #expect(!text.contains("\"settings\""))
    }

    @Test("A shift with no recorded vehicle exports an explicit null")
    func exportWritesAnExplicitNullForNoVehicle() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: start.addingTimeInterval(3_600))

        let record = try shift.exportRecord(for: shift.recordedDistance())
        #expect(record.fuelVehicleName == nil)

        let document = ExportDocument(
            scope: .allHistory,
            shifts: [record],
            summary: nil,
            exportedAt: start
        )
        let text = try #require(String(data: try ExportDocumentEncoder().json(for: document), encoding: .utf8))
        #expect(
            text.contains("\"fuelVehicleName\" : null"),
            "Missing is written explicitly, like every other absent field in the file"
        )
    }

    @Test("The export format version is unchanged: a new field is additive")
    func theExportVersionDoesNotMove() {
        #expect(ExportFormat.version == 4)
    }
}
