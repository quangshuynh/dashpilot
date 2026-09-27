import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v19: the Park and Resume pickup workflow's two preferences, the
/// delivery a parked stretch was for, and a migration that turns nothing on and
/// associates nothing.
///
/// **The migration's claim is an absence, twice.** A driver who agreed to v17's
/// Park-records-Picked-Up has not agreed to Park recording Arrived at Pickup and
/// Resume Driving recording Picked Up, so the workflow reads off. And no parked
/// stretch recorded before v19 was for any delivery as far as the store knows,
/// however its instants line up with one.
@MainActor
@Suite("Pickup workflow persistence")
struct PickupWorkflowPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotPickupWorkflowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// What is still true of v19 now that v20 is current.
    ///
    /// The count of versions and stages lives in the suite belonging to
    /// whichever version is current, and moved to `SharedStopPersistenceTests`
    /// with v20.
    @Test("Version 19 is frozen, and it added no entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV19.versionIdentifier == Schema.Version(19, 0, 0))

        let entities = Set(Schema(versionedSchema: DashPilotSchemaV19.self).entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v19 moves three columns and no entity"
        )
    }

    @Test("The settings row asks the two new questions, has dropped the old one, and joins nothing")
    func theSettingsColumns() throws {
        // Unchanged by v20, so the current schema is still the one described.
        let settings = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "DriverSettings" })
        #expect(
            Set(settings.properties.map(\.name)) == [
                "id", "gasPricePerGallonAmount", "selectedVehicleID",
                "usesParkAndResumeForPickups", "handlesStackedOrdersInOrder"
            ]
        )
        #expect(settings.relationships.isEmpty, "A preference points at no shift and no delivery")
    }

    /// Pinned because this feature is the one most tempted to break it: the
    /// stretch now names a delivery, and that must stay an identifier.
    @Test("A suspension names its delivery by identifier and still belongs to the shift alone")
    func theSuspensionStaysShiftOwned() throws {
        // The frozen v19 shape: v20 adds the others sharing the pickup, which
        // `SharedStopPersistenceTests` pins.
        let schema = Schema(versionedSchema: DashPilotSchemaV19.self)

        let suspension = try #require(schema.entities.first { $0.name == "RouteSuspension" })
        #expect(
            Set(suspension.properties.map(\.name))
                == ["id", "startedAt", "endedAt", "shift", "pickupWorkflowDeliveryID"]
        )
        #expect(suspension.relationships.map(\.destination) == ["Shift"])

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(delivery.relationships.allSatisfy { $0.destination != "RouteSuspension" })
        #expect(
            !delivery.properties.map(\.name).contains("arrivalProvenanceRawValue"),
            "An arrival's provenance is not stored: nothing that reads it needs it"
        )
    }

    @Test("The frozen version 18 still holds the retired preference and a suspension that names nothing")
    func versionEighteenIsFrozen() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV18.self)

        let settings = try #require(schema.entities.first { $0.name == "DriverSettings" })
        #expect(
            Set(settings.properties.map(\.name))
                == ["id", "gasPricePerGallonAmount", "selectedVehicleID", "recordsPickupWhenParking"]
        )
        let suspension = try #require(schema.entities.first { $0.name == "RouteSuspension" })
        #expect(Set(suspension.properties.map(\.name)) == ["id", "startedAt", "endedAt", "shift"])
    }

    // MARK: Migration

    @Test("A version 18 store reaches version 19 with the workflow off, nothing associated, and everything else kept")
    func migratesFromEighteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let vehicleID = UUID()
        let arrivedID = UUID()
        let manualID = UUID()
        let parkedID = UUID()

        do {
            let v18 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV18.self, at: storeURL)
            let context = ModelContext(v18)
            // The old switch was on: that was consent to a different automation.
            context.insert(
                DashPilotSchemaV18.DriverSettings(
                    id: DriverSettings.singletonID,
                    gasPricePerGallonAmount: Decimal(string: "3.49"),
                    selectedVehicleID: vehicleID,
                    recordsPickupWhenParking: true
                )
            )
            let shift = DashPilotSchemaV18.Shift(startedAt: start)
            context.insert(shift)
            // Parked at exactly the instant one delivery arrived: the
            // coincidence a migration must not read as an association.
            context.insert(DashPilotSchemaV18.RouteSuspension(shift: shift, startedAt: at(10)))
            context.insert(
                DashPilotSchemaV18.Delivery(id: arrivedID, shift: shift, acceptedAt: at(1), arrivedAtPickupAt: at(10))
            )
            context.insert(
                DashPilotSchemaV18.Delivery(
                    id: manualID, shift: shift, acceptedAt: at(2),
                    arrivedAtPickupAt: at(3), pickedUpAt: at(6), pickupProvenanceRawValue: "manual"
                )
            )
            context.insert(
                DashPilotSchemaV18.Delivery(
                    id: parkedID, shift: shift, acceptedAt: at(3),
                    arrivedAtPickupAt: at(4), pickedUpAt: at(5), pickupProvenanceRawValue: "parkAutomation"
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let settingsService = SettingsService(context: context)
        #expect(settingsService.pickupWorkflowPreferences() == .off, "Agreeing to v17's switch was not agreeing to this")
        let settings = try #require(try settingsService.existingSettings())
        #expect(settings.gasPricePerGallon == Money(minorUnits: 349))
        #expect(settings.selectedVehicleID == vehicleID)

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let suspension = try #require(shift.openRouteSuspension)
        #expect(suspension.startedAt == at(10), "The vehicle is still parked")
        #expect(suspension.pickupWorkflowDeliveryID == nil, "Nothing is inferred from matching instants")

        let deliveries = try context.fetch(FetchDescriptor<Delivery>())
        #expect(deliveries.first { $0.id == manualID }?.pickupProvenance == .manual)
        #expect(deliveries.first { $0.id == parkedID }?.pickupProvenance == .parkAutomation, "Provenance is untouched")
        let arrived = try #require(deliveries.first { $0.id == arrivedID })
        #expect(arrived.state == .arrivedAtPickup)

        // Even with the workflow turned on afterwards, a stretch parked before
        // v19 was for no delivery, so resuming it picks nothing up.
        try settingsService.setUsesParkAndResumeForPickups(true)
        let resumed = try ParkVehicleService(context: context).resumeDriving(at: at(20))
        #expect(resumed.pickup == .noParkedPickup)
        #expect(arrived.state == .arrivedAtPickup)
    }

    @Test("A version 17 store reaches version 19 through both stages with the workflow off")
    func migratesFromSeventeen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v17 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV17.self, at: storeURL)
            let context = ModelContext(v17)
            context.insert(DashPilotSchemaV17.DriverSettings(id: DriverSettings.singletonID, recordsPickupWhenParking: true))
            let shift = DashPilotSchemaV17.Shift(startedAt: start)
            context.insert(shift)
            context.insert(DashPilotSchemaV17.RouteSuspension(shift: shift, startedAt: at(10)))
            context.insert(DashPilotSchemaV17.Delivery(shift: shift, acceptedAt: at(1), arrivedAtPickupAt: at(2), pickedUpAt: at(10)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(SettingsService(context: context).pickupWorkflowPreferences() == .off)
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.openRouteSuspension?.pickupWorkflowDeliveryID == nil)
        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(delivery.pickedUpAt == at(10))
        #expect(delivery.pickupProvenance == nil, "Still unknown, as v18 left it")
    }

    // MARK: The preferences

    @Test("A new settings row starts with both answers off, and reading creates no row")
    func aNewRowStartsOff() throws {
        #expect(DriverSettings().pickupWorkflowPreferences == .off)

        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        #expect(SettingsService(context: context).pickupWorkflowPreferences() == .off)
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty, "Reading a preference writes nothing")
        let created = try SettingsService(context: context).settings()
        #expect(created.pickupWorkflowPreferences == .off)
    }

    @Test("Both answers survive closing and reopening the store, and each keeps its own value")
    func thePreferencesPersist() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let service = SettingsService(context: ModelContext(try ModelContainerFactory.makeContainer(at: storeURL)))
            try service.setUsesParkAndResumeForPickups(true)
            try service.setHandlesStackedOrdersInOrder(true)
        }
        do {
            let service = SettingsService(context: ModelContext(try ModelContainerFactory.makeContainer(at: storeURL)))
            #expect(service.pickupWorkflowPreferences() == .init(usesParkAndResume: true, handlesStackedOrdersInOrder: true))
            // Turning the workflow off keeps the stacked answer for when it is
            // turned on again.
            try service.setUsesParkAndResumeForPickups(false)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(
            SettingsService(context: context).pickupWorkflowPreferences()
                == .init(usesParkAndResume: false, handlesStackedOrdersInOrder: true)
        )
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).count == 1, "Still one row")
    }

    // MARK: Relaunch

    /// The reason the association is stored: Park in one process, Resume in a
    /// later one, and the delivery Park chose is still the one picked up.
    @Test("A stretch parked before a relaunch is resumed after it for the delivery Park chose")
    func theAssociationOutlivesTheProcess() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        var chosenID: UUID?
        var otherID: UUID?
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let settings = SettingsService(context: context)
            try settings.setUsesParkAndResumeForPickups(true)
            try settings.setHandlesStackedOrdersInOrder(true)
            let deliveries = DeliveryService(context: context)
            chosenID = try deliveries.startDelivery(at: at(1)).id
            otherID = try deliveries.startDelivery(at: at(2)).id

            let parked = try ParkVehicleService(context: context).park(at: at(10))
            #expect(parked.pickup == .markedArrived(deliveryNumber: 1))
        }

        // A new container stands in for a new process.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.openRouteSuspension?.pickupWorkflowDeliveryID == chosenID)
        // Inside, the driver records the other order's arrival by hand.
        let otherDeliveryID = try #require(otherID)
        let chosenDeliveryID = try #require(chosenID)
        let other = try #require(try DeliveryService(context: context).delivery(withID: otherDeliveryID))
        try DeliveryService(context: context).markArrivedAtPickup(other, at: at(12))

        let resumed = try ParkVehicleService(context: context).resumeDriving(at: at(18))

        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: 1))
        let chosen = try #require(try DeliveryService(context: context).delivery(withID: chosenDeliveryID))
        #expect(chosen.pickedUpAt == at(18))
        #expect(other.state == .arrivedAtPickup, "The other order is not picked up by a second choice")
    }
}
