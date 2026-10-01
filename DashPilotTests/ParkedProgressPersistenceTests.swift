import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v21: one settings column, `resumesDrivingAfterDeliveryProgress`, and
/// a migration that turns it on for nobody.
@MainActor
@Suite("Resume after delivery progress persistence")
struct ParkedProgressPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotParkedProgressTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    /// The plan's own shape, asserted here because v21 is the current version.
    ///
    /// The count of versions and stages lives in the suite belonging to
    /// whichever version is current. It moved here from
    /// `SharedStopPersistenceTests`, which owned it while v20 was current.
    @Test("Version 21 is the current version, and it adds no entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV21.versionIdentifier == Schema.Version(21, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 21)
        #expect(DashPilotMigrationPlan.stages.count == 20)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV21.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ]
        )
    }

    @Test("The frozen v20 has no answer to the question; v21 has it on the settings row only")
    func theColumn() throws {
        let frozen = try #require(
            Schema(versionedSchema: DashPilotSchemaV20.self).entities.first { $0.name == "DriverSettings" }
        )
        #expect(!frozen.properties.map(\.name).contains("resumesDrivingAfterDeliveryProgress"))

        let current = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "DriverSettings" })
        #expect(current.properties.map(\.name).contains("resumesDrivingAfterDeliveryProgress"))
        for entity in ModelContainerFactory.currentSchema.entities where entity.name != "DriverSettings" {
            #expect(!entity.properties.map(\.name).contains("resumesDrivingAfterDeliveryProgress"))
        }
    }

    @Test("A version 20 store migrates with the answer off, the workflow answers kept, and nothing recorded moved")
    func migratesFromTwenty() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let deliveryID = UUID()
        let pickupGroup = UUID()

        do {
            let v20 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV20.self, at: storeURL)
            let context = ModelContext(v20)
            // A driver who turned everything on that existed: still not an
            // answer to this question.
            context.insert(
                DashPilotSchemaV20.DriverSettings(
                    id: DriverSettings.singletonID,
                    usesParkAndResumeForPickups: true,
                    handlesStackedOrdersInOrder: true
                )
            )
            let shift = DashPilotSchemaV20.Shift(startedAt: start)
            context.insert(shift)
            let offer = DashPilotSchemaV20.Offer(shift: shift, acceptedAt: at(1))
            context.insert(offer)
            context.insert(
                DashPilotSchemaV20.Delivery(
                    id: deliveryID, shift: shift, offer: offer, acceptedAt: at(1), arrivedAtPickupAt: at(5),
                    sharedPickupID: pickupGroup
                )
            )
            context.insert(
                DashPilotSchemaV20.RouteSuspension(
                    shift: shift, startedAt: at(6), pickupWorkflowDeliveryID: deliveryID,
                    pickupWorkflowSharedPickupDeliveryIDs: []
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let settings = try #require(try context.fetch(FetchDescriptor<DriverSettings>()).first)
        #expect(settings.resumesDrivingAfterDeliveryProgress == false, "Off for every migrated driver")
        #expect(settings.usesParkAndResumeForPickups && settings.handlesStackedOrdersInOrder)
        #expect(SettingsService(context: context).resumesDrivingAfterDeliveryProgress() == false)

        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(delivery.sharedPickupID == pickupGroup && delivery.arrivedAtPickupAt == at(5))
        let suspension = try #require(try context.fetch(FetchDescriptor<RouteSuspension>()).first)
        #expect(suspension.isOpen && suspension.pickupWorkflowDeliveryIDs == [deliveryID])

        // And a pickup recorded on the migrated, still-parked shift resumes nothing.
        let result = try DeliveryProgressService(context: context).record(.pickedUp, of: delivery, at: at(9))
        #expect(result.parked == .notApplicable)
        #expect(suspension.isOpen)
    }

    @Test("A version 19 store reaches version 21 through both stages with the answer off")
    func migratesFromNineteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v19 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV19.self, at: storeURL)
            let context = ModelContext(v19)
            context.insert(DashPilotSchemaV19.DriverSettings(id: DriverSettings.singletonID, usesParkAndResumeForPickups: true))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let settings = try #require(try context.fetch(FetchDescriptor<DriverSettings>()).first)
        #expect(settings.resumesDrivingAfterDeliveryProgress == false)
        #expect(settings.usesParkAndResumeForPickups)
    }

    @Test("The answer survives closing and reopening the store")
    func roundTrip() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try SettingsService(context: context).setResumesDrivingAfterDeliveryProgress(true)
        }
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(SettingsService(context: context).resumesDrivingAfterDeliveryProgress())
    }
}
