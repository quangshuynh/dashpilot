import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v17: one preference column, and a migration that turned nothing on.
///
/// v19 retired the column; the preference that replaced it, and its own
/// migration, are pinned in `PickupWorkflowPersistenceTests`. What stays here
/// is v17's frozen shape and that no migration from before it turns anything on.
///
/// **The migration's whole claim is an absence, again.** A v16 store was
/// written by a build that could not ask whether parking should record a
/// pickup, so no driver chose it, and a migrated settings row reads `false`.
@MainActor
@Suite("Park pickup persistence")
struct ParkPickupPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotParkPickupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// Version 17's own identifier and entities, which stay here now that it is
    /// frozen.
    ///
    /// The **plan's** version and stage counts moved to
    /// `PickupProvenancePersistenceTests` when v18 became current, by the
    /// convention that they live in the current version's suite.
    @Test("Version 17 is the version that added the preference, and it is now frozen")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV17.versionIdentifier == Schema.Version(17, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.contains { $0 is DashPilotSchemaV17.Type })

        let schema = Schema(versionedSchema: DashPilotSchemaV17.self)
        let entities = Set(schema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v17 moves one column and no entity"
        )
        let settings = try #require(schema.entities.first { $0.name == "DriverSettings" })
        #expect(settings.properties.map(\.name).contains("recordsPickupWhenParking"))
        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(
            !delivery.properties.map(\.name).contains("pickupProvenanceRawValue"),
            "The frozen v17 delivery records no provenance; v18 adds it"
        )
    }

    @Test("The frozen version 16 still describes settings with no pickup preference")
    func versionSixteenHeldNoPreference() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV16.self)

        let settings = try #require(schema.entities.first { $0.name == "DriverSettings" })
        #expect(Set(settings.properties.map(\.name)) == ["id", "gasPricePerGallonAmount", "selectedVehicleID"])

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        #expect(
            shift.relationships.contains { $0.destination == "RouteSuspension" },
            "And it keeps what v16 added"
        )
    }

    // MARK: Migration

    @Test("A version 16 settings row reaches version 17 with the automation off and everything else kept")
    func migratesSettingsWithTheAutomationOff() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let vehicleID = UUID()
        let shiftID = UUID()
        let deliveryID = UUID()

        do {
            let v16 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV16.self, at: storeURL)
            let context = ModelContext(v16)
            context.insert(
                DashPilotSchemaV16.VehicleProfile(
                    id: vehicleID,
                    name: "Hatchback",
                    milesPerGallonValue: Decimal(32),
                    createdAt: start
                )
            )
            context.insert(
                DashPilotSchemaV16.DriverSettings(
                    id: DriverSettings.singletonID,
                    gasPricePerGallonAmount: Decimal(string: "3.49"),
                    selectedVehicleID: vehicleID
                )
            )

            // A running shift, parked, with a delivery waiting at its pickup:
            // exactly the state the automation would act on if it were on.
            let shift = DashPilotSchemaV16.Shift(id: shiftID, startedAt: start)
            context.insert(shift)
            context.insert(DashPilotSchemaV16.RouteSuspension(shift: shift, startedAt: start.addingTimeInterval(600)))
            context.insert(
                DashPilotSchemaV16.Delivery(
                    id: deliveryID,
                    shift: shift,
                    acceptedAt: start.addingTimeInterval(60),
                    arrivedAtPickupAt: start.addingTimeInterval(500)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let settings = try #require(try SettingsService(context: context).existingSettings())

        // Opened at the current version, so this row went through v17's `false`
        // and then v19, which carries nothing of it into the workflow.
        #expect(
            SettingsService(context: context).pickupWorkflowPreferences() == .off,
            "Nobody using a v16 build chose any automation"
        )
        #expect(settings.gasPricePerGallon == Money(minorUnits: 349), "The v15 guarantees still hold")
        #expect(settings.selectedVehicleID == vehicleID)

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.id == shiftID)
        #expect(shift.isRouteSuspended, "The open suspension carries over")

        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(delivery.id == deliveryID)
        #expect(delivery.state == .arrivedAtPickup, "No delivery is advanced by migrating")
        #expect(delivery.pickedUpAt == nil)
    }

    @Test("A version 16 store with no settings row reads the automation as off, and reading creates no row")
    func aStoreWithNoSettingsReadsOff() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v16 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV16.self, at: storeURL)
            let context = ModelContext(v16)
            context.insert(DashPilotSchemaV16.Shift(startedAt: start, endedAt: start.addingTimeInterval(3_600)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(SettingsService(context: context).pickupWorkflowPreferences() == .off)
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty, "Reading a preference writes nothing")
    }
}
