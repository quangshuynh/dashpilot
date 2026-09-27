import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v18: one optional column on the delivery, and a migration that
/// labels nothing.
///
/// **The migration's claim is an absence.** A v17 store could already hold
/// pickups recorded by Park, and holds no trace of which. So every migrated
/// pickup reads as unknown: not manual because most pickups were, not Park's
/// because a suspension began at the same instant, and not either because of
/// what the setting says today.
@MainActor
@Suite("Pickup provenance persistence")
struct PickupProvenancePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotPickupProvenanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v18 is the current version.
    ///
    /// The count of versions and stages lives in the suite belonging to
    /// whichever version is current. It moved here from
    /// `ParkPickupPersistenceTests`, which owned it while v17 was current.
    @Test("Version 18 is the current version, and it adds no entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV18.versionIdentifier == Schema.Version(18, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 18)
        #expect(DashPilotMigrationPlan.stages.count == 17)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV18.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v18 moves one column and no entity"
        )
    }

    @Test("Provenance is a column on the delivery, and on nothing else")
    func provenanceIsADeliveryColumn() throws {
        let schema = ModelContainerFactory.currentSchema

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(delivery.properties.map(\.name).contains("pickupProvenanceRawValue"))

        for name in ["Shift", "RouteSuspension", "DriverSettings", "PickupPlace", "Offer"] {
            let entity = try #require(schema.entities.first { $0.name == name })
            #expect(
                !entity.properties.map(\.name).contains("pickupProvenanceRawValue"),
                "How a pickup was recorded belongs to the pickup, not to \(name)"
            )
        }
        let suspension = try #require(schema.entities.first { $0.name == "RouteSuspension" })
        #expect(suspension.relationships.map(\.destination) == ["Shift"], "Still no delivery joins a suspension")
    }

    // MARK: Round trip

    @Test("Each kind of pickup survives closing and reopening the store")
    func provenancePersists() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        var manualID: UUID?
        var parkedID: UUID?
        var waitingID: UUID?
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)

            let manual = try deliveries.startDelivery(at: at(1))
            try deliveries.markArrivedAtPickup(manual, at: at(2))
            try deliveries.markPickedUp(manual, at: at(8))
            manualID = manual.id

            let parked = try deliveries.startDelivery(at: at(9))
            try deliveries.markArrivedAtPickup(parked, at: at(10))
            try SettingsService(context: context).setRecordsPickupWhenParking(true)
            try ParkVehicleService(context: context).park(at: at(11))
            parkedID = parked.id

            let waiting = try deliveries.startDelivery(at: at(12))
            waitingID = waiting.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>())
        #expect(stored.first { $0.id == manualID }?.pickupProvenance == .manual)
        #expect(stored.first { $0.id == parkedID }?.pickupProvenance == .parkAutomation)
        let waiting = try #require(stored.first { $0.id == waitingID })
        #expect(waiting.pickedUpAt == nil)
        #expect(waiting.pickupProvenance == nil)
    }

    // MARK: Migration

    @Test("Version 17 pickups reach version 18 as unknown, never as manual, whatever surrounds them")
    func migratedPickupsAreUnknown() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()
        let ordinaryID = UUID()
        let coincidentID = UUID()
        let waitingID = UUID()
        let cancelledID = UUID()

        do {
            let v17 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV17.self, at: storeURL)
            let context = ModelContext(v17)
            // The setting was on in v17. That says what Park may do from now
            // on, not what it did to any pickup already in the store.
            context.insert(
                DashPilotSchemaV17.DriverSettings(id: DriverSettings.singletonID, recordsPickupWhenParking: true)
            )
            let shift = DashPilotSchemaV17.Shift(id: shiftID, startedAt: start, endedAt: at(120))
            context.insert(shift)
            // A parked stretch starting at exactly one delivery's pickup
            // instant: the coincidence a migration must not read as a record.
            context.insert(DashPilotSchemaV17.RouteSuspension(shift: shift, startedAt: at(40), endedAt: at(50)))
            context.insert(
                DashPilotSchemaV17.Delivery(
                    id: ordinaryID, shift: shift, acceptedAt: at(1),
                    arrivedAtPickupAt: at(5), pickedUpAt: at(12), deliveredAt: at(30)
                )
            )
            context.insert(
                DashPilotSchemaV17.Delivery(
                    id: coincidentID, shift: shift, acceptedAt: at(31),
                    arrivedAtPickupAt: at(39), pickedUpAt: at(40), deliveredAt: at(70)
                )
            )
            context.insert(
                DashPilotSchemaV17.Delivery(
                    id: waitingID, shift: shift, acceptedAt: at(71), arrivedAtPickupAt: at(75), cancelledAt: at(90)
                )
            )
            context.insert(
                DashPilotSchemaV17.Delivery(
                    id: cancelledID, shift: shift, acceptedAt: at(91),
                    arrivedAtPickupAt: at(95), pickedUpAt: at(100), cancelledAt: at(110)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>())
        #expect(stored.count == 4)

        for id in [ordinaryID, coincidentID, cancelledID] {
            let delivery = try #require(stored.first { $0.id == id })
            #expect(delivery.pickedUpAt != nil, "The pickup instant carries over")
            #expect(delivery.pickupProvenance == nil, "Unknown: the v17 store never said how")
        }
        let coincident = try #require(stored.first { $0.id == coincidentID })
        #expect(coincident.pickedUpAt == at(40))
        #expect(coincident.pickupWait == 60, "Its wait is exactly what it was")

        let waiting = try #require(stored.first { $0.id == waitingID })
        #expect(waiting.pickedUpAt == nil)
        #expect(waiting.pickupProvenance == nil)

        #expect(SettingsService(context: context).recordsPickupWhenParking(), "The preference itself carries over")
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.id == shiftID)
        #expect(shift.routeSuspensions.count == 1)
    }
}
