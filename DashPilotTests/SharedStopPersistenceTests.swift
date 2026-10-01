import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v20: deliveries the driver recorded as sharing a pickup or a
/// drop-off, the others a parked stretch was for because they share its
/// pickup, and a migration that groups nothing.
///
/// **The migration's claim is an absence.** A v19 store holds deliveries
/// accepted together, deliveries naming the same pickup place and deliveries a
/// second apart, and none of that is a statement from the driver that two of
/// them shared a stop.
@MainActor
@Suite("Shared stop persistence")
struct SharedStopPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotSharedStopTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The frozen v20's own facts. The plan's counts moved to
    /// `ParkedProgressPersistenceTests` when v21 became current.
    @Test("Version 20 is frozen with eleven models and adds no entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV20.versionIdentifier == Schema.Version(20, 0, 0))
        #expect(DashPilotSchemaV20.models.count == 11)

        let entities = Set(Schema(versionedSchema: DashPilotSchemaV20.self).entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v20 moves three columns and no entity"
        )
        let delivery = try #require(Schema(versionedSchema: DashPilotSchemaV20.self).entities.first { $0.name == "Delivery" })
        #expect(Set(delivery.properties.map(\.name)).isSuperset(of: ["sharedPickupID", "sharedDropOffID"]))
    }

    @Test("A delivery holds two opaque identities and nothing about a customer or a place")
    func theDeliveryColumns() throws {
        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        let names = Set(delivery.properties.map(\.name))
        #expect(names.isSuperset(of: ["sharedPickupID", "sharedDropOffID"]))
        for leak in ["customerName", "address", "dropOffAddress", "sharedPickupName", "sharedDropOffName"] {
            #expect(!names.contains(leak), "Stored \(leak)")
        }
        #expect(
            delivery.relationships.map(\.destination).sorted() == ["DeliveryTip", "Offer", "PickupPlace", "Shift"],
            "Grouping is an identity, not a new relationship"
        )
    }

    @Test("A suspension names every delivery it was for by identifier and still belongs to the shift alone")
    func theSuspensionColumns() throws {
        let suspension = try #require(
            ModelContainerFactory.currentSchema.entities.first { $0.name == "RouteSuspension" }
        )
        #expect(
            Set(suspension.properties.map(\.name)) == [
                "id", "startedAt", "endedAt", "shift", "pickupWorkflowDeliveryID", "pickupWorkflowSharedPickupDeliveryIDs"
            ]
        )
        #expect(suspension.relationships.map(\.destination) == ["Shift"])
    }

    @Test("The frozen version 19 describes a delivery sharing nothing and a stretch for one delivery")
    func versionNineteenIsFrozen() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV19.self)

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let names = Set(delivery.properties.map(\.name))
        #expect(!names.contains("sharedPickupID"))
        #expect(!names.contains("sharedDropOffID"))
        #expect(names.contains("pickupProvenanceRawValue"), "Everything v18 added is still there")

        let suspension = try #require(schema.entities.first { $0.name == "RouteSuspension" })
        #expect(
            Set(suspension.properties.map(\.name)) == ["id", "startedAt", "endedAt", "shift", "pickupWorkflowDeliveryID"]
        )
    }

    // MARK: Migration

    @Test("A version 19 store reaches version 20 with every delivery independent and every stretch unchanged")
    func migratesFromNineteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let firstID = UUID()
        let secondID = UUID()
        let laterID = UUID()

        do {
            let v19 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV19.self, at: storeURL)
            let context = ModelContext(v19)
            context.insert(
                DashPilotSchemaV19.DriverSettings(
                    id: DriverSettings.singletonID,
                    usesParkAndResumeForPickups: true,
                    handlesStackedOrdersInOrder: true
                )
            )
            let shift = DashPilotSchemaV19.Shift(startedAt: start)
            context.insert(shift)
            let place = DashPilotSchemaV19.PickupPlace(displayName: "Nowhere Noodles", normalizedName: "nowhere noodles", createdAt: start)
            context.insert(place)
            // Everything a migration could mistake for a shared stop: one offer,
            // one instant, one named place, consecutive numbers, and a parked
            // stretch recorded for the first.
            let offer = DashPilotSchemaV19.Offer(shift: shift, acceptedAt: at(1))
            context.insert(offer)
            context.insert(
                DashPilotSchemaV19.Delivery(
                    id: firstID, shift: shift, offer: offer, acceptedAt: at(1), arrivedAtPickupAt: at(10), pickupPlace: place
                )
            )
            context.insert(
                DashPilotSchemaV19.Delivery(
                    id: secondID, shift: shift, offer: offer, acceptedAt: at(1), arrivedAtPickupAt: at(10), pickupPlace: place
                )
            )
            let later = DashPilotSchemaV19.Offer(shift: shift, acceptedAt: at(2))
            context.insert(later)
            context.insert(DashPilotSchemaV19.Delivery(id: laterID, shift: shift, offer: later, acceptedAt: at(2)))
            context.insert(
                DashPilotSchemaV19.RouteSuspension(shift: shift, startedAt: at(10), pickupWorkflowDeliveryID: firstID)
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let deliveries = try context.fetch(FetchDescriptor<Delivery>())
        #expect(deliveries.count == 3)
        #expect(deliveries.allSatisfy { $0.sharedPickupID == nil }, "Nothing is inferred from one offer or one place")
        #expect(deliveries.allSatisfy { $0.sharedDropOffID == nil })
        #expect(deliveries.filter { $0.pickupPlace != nil }.count == 2, "Everything else is kept")

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let suspension = try #require(shift.openRouteSuspension)
        #expect(suspension.pickupWorkflowDeliveryID == firstID, "The one delivery it named")
        #expect(suspension.pickupWorkflowSharedPickupDeliveryIDs.isEmpty, "And no other, however alike they look")
        #expect(suspension.pickupWorkflowDeliveryIDs == [firstID])

        // Resuming the migrated stretch under the workflow picks up the one
        // delivery Park chose in v19, and not its look-alike sibling.
        // The two share an acceptance instant, so which is numbered first is the
        // identity tie-break; the number is read from the shift, not assumed.
        let firstNumber = shift.numberedDeliveries.first { $0.id == firstID }?.number
        let resumed = try ParkVehicleService(context: context).resumeDriving(at: at(20))
        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: firstNumber))
        let first = try #require(deliveries.first { $0.id == firstID })
        let second = try #require(deliveries.first { $0.id == secondID })
        #expect(first.state == .pickedUp)
        #expect(second.state == .arrivedAtPickup, "Not picked up because it looks like it shares a pickup")
    }

    @Test("A version 18 store reaches version 20 through both stages and groups nothing")
    func migratesFromEighteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v18 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV18.self, at: storeURL)
            let context = ModelContext(v18)
            let shift = DashPilotSchemaV18.Shift(startedAt: start)
            context.insert(shift)
            let offer = DashPilotSchemaV18.Offer(shift: shift, acceptedAt: at(1))
            context.insert(offer)
            context.insert(DashPilotSchemaV18.Delivery(shift: shift, offer: offer, acceptedAt: at(1)))
            context.insert(DashPilotSchemaV18.Delivery(shift: shift, offer: offer, acceptedAt: at(1)))
            context.insert(DashPilotSchemaV18.RouteSuspension(shift: shift, startedAt: at(5)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(try context.fetch(FetchDescriptor<Delivery>()).allSatisfy { $0.sharedPickupID == nil && $0.sharedDropOffID == nil })
        let suspension = try #require(try context.fetch(FetchDescriptor<RouteSuspension>()).first)
        #expect(suspension.pickupWorkflowDeliveryIDs.isEmpty)
    }

    // MARK: Round trips

    @Test("Shared stops survive closing and reopening the store")
    func sharedStopsPersist() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        var pickup: UUID?
        var dropOff: UUID?
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let offer = try DeliveryService(context: context).startOffer(
                deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1)
            )
            pickup = offer.deliveries.first?.sharedPickupID
            dropOff = offer.deliveries.first?.sharedDropOffID
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let deliveries = try context.fetch(FetchDescriptor<Delivery>())
        #expect(deliveries.count == 2)
        #expect(deliveries.allSatisfy { $0.sharedPickupID == pickup && $0.sharedDropOffID == dropOff })
    }
}
