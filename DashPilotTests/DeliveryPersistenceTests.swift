import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Deliveries in the store: the v5 schema, the v4 migration, and the recovery
/// that follows from the store being the only authority on delivery state.
@MainActor
@Suite("Delivery persistence")
struct DeliveryPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotDeliveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    @Test("Version 5 is current, and adds the delivery entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 5)
        #expect(DashPilotMigrationPlan.stages.count == 4)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities == ["Shift", "RouteSample", "Delivery"])

        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(shift.properties.map(\.name).contains("deliveries"))
    }

    @Test("Version 4 described no deliveries")
    func versionFourHeldNoDeliveries() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV4.self)
        #expect(!schema.entities.map(\.name).contains("Delivery"))

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let properties = shift.properties.map(\.name)

        #expect(properties.contains("grossEarningsAmount"), "The frozen v4 shift still records earnings")
        #expect(properties.contains("routeSamples"))
        #expect(
            !properties.contains("deliveries"),
            "The frozen v4 model must describe the store as it was, not as it is now"
        )
    }

    @Test("A delivery records every lifecycle timestamp it was given")
    func roundTripsADelivery() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let delivery = Delivery(shift: shift, acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(1_020))
        try delivery.markDelivered(at: at(1_800))
        context.insert(delivery)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)

        #expect(stored.acceptedAt == at(300))
        #expect(stored.arrivedAtPickupAt == at(600))
        #expect(stored.pickedUpAt == at(1_020))
        #expect(stored.deliveredAt == at(1_800))
        #expect(stored.cancelledAt == nil)
        #expect(stored.state == .delivered)
        #expect(stored.shift?.id == shift.id)
    }

    // MARK: Relaunch recovery

    @Test("A delivery left in progress is still in progress after the store is reopened")
    func activeDeliverySurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var deliveryID = UUID()

        // A process that started a shift, started a delivery, got as far as the
        // pickup, and was then terminated.
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let service = DeliveryService(context: context)
            try service.startDelivery(at: at(300))
            deliveryID = try service.markArrivedAtPickup(at: at(600)).id
        }

        // A new process, a new container, a new service.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let service = DeliveryService(context: context)
        let recovered = try #require(try service.activeDelivery())

        #expect(recovered.id == deliveryID, "The same delivery, not a replacement")
        #expect(recovered.state == .arrivedAtPickup, "The interface is told the next step is picking up")
        #expect(recovered.acceptedAt == at(300), "Prior timestamps are untouched")
        #expect(recovered.arrivedAtPickupAt == at(600))
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1, "No duplicate delivery is created")

        // And it continues from where it was rather than starting again.
        #expect(throws: DeliveryLifecycleError.deliveryAlreadyActive(state: .arrivedAtPickup)) {
            try service.startDelivery(at: at(900))
        }
        try service.markPickedUp(at: at(900))
        try service.markDelivered(at: at(1_500))
        #expect(try service.activeDelivery() == nil)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
    }

    @Test("A finished delivery does not come back as active after a reopen")
    func finishedDeliveriesStayFinished() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let service = DeliveryService(context: context)
            try service.startDelivery(at: at(300))
            try service.markArrivedAtPickup(at: at(600))
            try service.markPickedUp(at: at(900))
            try service.markDelivered(at: at(1_200))
            try service.startDelivery(at: at(1_500))
            try service.cancelActiveDelivery(at: at(1_800))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try ShiftService(context: context).activeShift())

        #expect(try DeliveryService(context: context).activeDelivery() == nil)
        #expect(shift.deliveries.count == 2)
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
        // And the shift can now be ended, because nothing is in progress.
        try ShiftService(context: context).endActiveShift(at: at(3_600))
        #expect(shift.endedAt == at(3_600))
    }

    // MARK: Migration

    @Test("A version 4 store opens under version 5 with everything it held and no invented deliveries")
    func migratesAVersionFourStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let runningID = UUID()
        let session = UUID()

        // A store exactly as a build without delivery recording would have left
        // one: two shifts, a route in one capture session, and a recorded amount.
        do {
            let v4 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV4.self, at: storeURL)
            let context = ModelContext(v4)
            let paid = DashPilotSchemaV4.Shift(
                id: paidID,
                startedAt: start,
                endedAt: at(3_600),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)
            context.insert(DashPilotSchemaV4.Shift(id: runningID, startedAt: at(7_200)))
            for step in 0..<4 {
                let position = SyntheticRoute.sample(at: at(TimeInterval(step) * 10), northMetres: Double(step) * 100)
                context.insert(
                    DashPilotSchemaV4.RouteSample(
                        shift: paid,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        let samples = try context.fetch(FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [paidID, runningID])
        #expect(shifts.first?.endedAt == at(3_600))
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        #expect(shifts.first?.grossEarnings == Money(exact: "86.25"), "Gross earnings survive exactly")
        #expect(shifts.last?.grossEarnings == nil, "And an absent amount stays absent")
        #expect(samples.count == 4, "Migration must not drop stored positions")
        #expect(samples.allSatisfy { $0.captureSessionID == session }, "Capture continuity survives")
        #expect(samples.allSatisfy { $0.shift?.id == paidID })

        #expect(
            try context.fetch(FetchDescriptor<Delivery>()).isEmpty,
            "A shift recorded before delivery recording existed has no deliveries, not invented ones"
        )
        #expect(shifts.allSatisfy { $0.deliveries.isEmpty })
        #expect(shifts.allSatisfy { $0.deliverySummary.isEmpty })
    }

    @Test("A migrated shift still measures its route, and can then record a delivery")
    func aMigratedShiftStillWorks() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let session = UUID()

        do {
            let v4 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV4.self, at: storeURL)
            let context = ModelContext(v4)
            // Still running when the old build was last used, which is the
            // shift a driver would carry across an update mid-shift.
            let shift = DashPilotSchemaV4.Shift(startedAt: start)
            context.insert(shift)
            for step in 0..<4 {
                let position = SyntheticRoute.sample(at: at(TimeInterval(step) * 10), northMetres: Double(step) * 100)
                context.insert(
                    DashPilotSchemaV4.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try ShiftService(context: context).activeShift())
        let distance = shift.recordedDistance()

        #expect(distance.isMeasured)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 300), "measured \(distance.metres) m")

        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))
        try service.markPickedUp(at: at(900))
        try service.markDelivered(at: at(1_200))

        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 0))
    }

    @Test("Earlier migration paths still reach version 5", arguments: [1, 2, 3])
    func earlierStoresStillMigrate(fromVersion: Int) throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()
        let session = UUID()

        do {
            switch fromVersion {
            case 1:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
                )
                context.insert(DashPilotSchemaV1.Shift(id: shiftID, startedAt: start, endedAt: at(3_600)))
                try context.save()
            case 2:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV2.self, at: storeURL)
                )
                let shift = DashPilotSchemaV2.Shift(id: shiftID, startedAt: start, endedAt: at(3_600))
                context.insert(shift)
                let position = SyntheticRoute.sample(at: at(10), northMetres: 100)
                context.insert(
                    DashPilotSchemaV2.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy
                    )
                )
                try context.save()
            default:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV3.self, at: storeURL)
                )
                let shift = DashPilotSchemaV3.Shift(id: shiftID, startedAt: start, endedAt: at(3_600))
                context.insert(shift)
                let position = SyntheticRoute.sample(at: at(10), northMetres: 100)
                context.insert(
                    DashPilotSchemaV3.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
                try context.save()
            }
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.completedDuration == 3_600)
        #expect(shift.grossEarnings == nil)
        #expect(shift.deliveries.isEmpty, "No version step fabricates a delivery")
        #expect(shift.routeSamples.count == (fromVersion == 1 ? 0 : 1))
        if fromVersion == 3 {
            #expect(shift.routeSamples.first?.captureSessionID == session)
        }
        if fromVersion == 2 {
            #expect(shift.routeSamples.first?.captureSessionID == nil, "A v2 sample's continuity stays unproven")
        }
    }
}
