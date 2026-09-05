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

    /// The delivery lifecycle's own shape, wherever the current version happens
    /// to be.
    ///
    /// Version 5 added the `Delivery` entity and the to-many `Shift.deliveries`
    /// relationship, and allowing several concurrent deliveries needed no
    /// version of its own: the store could always describe more than one
    /// unfinished delivery for a shift, and "at most one active" was an
    /// application invariant rather than a shape the database imposed. What the
    /// current schema is, and what v6 added to it, is asserted in
    /// `PickupPlacePersistenceTests`.
    @Test("Deliveries are their own entity, related to a shift as a to-many")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities.contains("Delivery"))

        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(shift.properties.map(\.name).contains("deliveries"))

        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        let properties = Set(delivery.properties.map(\.name))
        #expect(
            properties.isSuperset(of: ["acceptedAt", "arrivedAtPickupAt", "pickedUpAt", "deliveredAt", "cancelledAt"]),
            "State is derived from these timestamps, so all five are stored and no state column is"
        )
        #expect(!properties.contains("state"))
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
            let delivery = try service.startDelivery(at: at(300))
            deliveryID = try service.markArrivedAtPickup(delivery, at: at(600)).id
        }

        // A new process, a new container, a new service.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let service = DeliveryService(context: context)
        let recovered = try #require(try service.activeDeliveries().first)

        #expect(recovered.id == deliveryID, "The same delivery, not a replacement")
        #expect(recovered.state == .arrivedAtPickup, "The interface is told the next step is picking up")
        #expect(recovered.acceptedAt == at(300), "Prior timestamps are untouched")
        #expect(recovered.arrivedAtPickupAt == at(600))
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1, "No duplicate delivery is created")

        // And it continues from where it was.
        try service.markPickedUp(recovered, at: at(900))
        try service.markDelivered(recovered, at: at(1_500))
        #expect(try service.activeDeliveries().isEmpty)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
    }

    @Test("Several deliveries left in progress all come back, independently")
    func stackedActiveDeliveriesSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var expectedIDs: [UUID] = []

        // A process carrying three orders at once, at three different points in
        // their lifecycles, terminated mid-shift.
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let service = DeliveryService(context: context)
            let first = try service.startDelivery(at: at(300))
            let second = try service.startDelivery(at: at(600))
            let third = try service.startDelivery(at: at(900))
            try service.markArrivedAtPickup(second, at: at(1_200))
            try service.markArrivedAtPickup(third, at: at(1_500))
            try service.markPickedUp(third, at: at(1_800))
            expectedIDs = [first.id, second.id, third.id]
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let service = DeliveryService(context: context)
        let shift = try #require(try ShiftService(context: context).activeShift())
        let recovered = try service.activeDeliveries(for: shift)

        #expect(recovered.map(\.id) == expectedIDs, "Every one of them, in the order they were accepted")
        #expect(recovered.count == 3, "None is collapsed into another and none is chosen as authoritative")
        #expect(
            try context.fetch(FetchDescriptor<Delivery>()).count == 3,
            "And none is duplicated by the reopen"
        )
        #expect(
            recovered.map(\.state) == [.accepted, .arrivedAtPickup, .pickedUp],
            "Each keeps the state its own timestamps describe"
        )
        #expect(
            recovered.map(\.state.nextAction) == [.arriveAtPickup, .pickUp, .complete],
            "So each is offered its own next step"
        )
        #expect(recovered.map(\.acceptedAt) == [at(300), at(600), at(900)], "Timestamps are untouched")
        #expect(recovered[1].arrivedAtPickupAt == at(1_200))
        #expect(recovered[2].pickedUpAt == at(1_800))
        #expect(shift.numberedActiveDeliveries.map(\.number) == [1, 2, 3], "And they are numbered the same way")

        // They continue independently from where they were, and the shift stays
        // blocked until the last one is resolved.
        try service.markDelivered(recovered[2], at: at(2_100))
        #expect(recovered[0].state == .accepted)
        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 2)) {
            try ShiftService(context: context).endActiveShift(at: at(3_600))
        }
    }

    @Test("A finished delivery does not come back as active after a reopen")
    func finishedDeliveriesStayFinished() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let service = DeliveryService(context: context)
            // Worked as a stack: both accepted before either finished.
            let first = try service.startDelivery(at: at(300))
            let second = try service.startDelivery(at: at(600))
            try service.markArrivedAtPickup(first, at: at(900))
            try service.markPickedUp(first, at: at(1_020))
            try service.markDelivered(first, at: at(1_200))
            try service.cancelDelivery(second, at: at(1_800))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try ShiftService(context: context).activeShift())

        #expect(try DeliveryService(context: context).activeDeliveries().isEmpty)
        #expect(shift.deliveries.count == 2)
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
        // And the shift can now be ended, because nothing is in progress.
        try ShiftService(context: context).endActiveShift(at: at(3_600))
        #expect(shift.endedAt == at(3_600))
    }

    @Test("Overlapping deliveries stay separate records with their own intervals")
    func overlappingDeliveriesRoundTripSeparately() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            try shifts.startShift(at: start)
            let service = DeliveryService(context: context)
            let first = try service.startDelivery(at: at(0))
            let second = try service.startDelivery(at: at(600))
            try service.markArrivedAtPickup(first, at: at(300))
            try service.markPickedUp(first, at: at(900))
            try service.markArrivedAtPickup(second, at: at(1_200))
            try service.markPickedUp(second, at: at(1_500))
            try service.markDelivered(first, at: at(1_800))
            try service.markDelivered(second, at: at(2_100))
            try shifts.endActiveShift(at: at(3_600))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let stored = shift.deliveriesInOrder

        #expect(stored.count == 2, "Two overlapping deliveries are two rows, never merged into one")
        #expect(stored.map(\.completedDuration) == [1_800, 1_500], "Each keeps its own duration")
        #expect(stored.map(\.pickupWait) == [600, 300], "And its own wait")
        let firstDeliveredAt = try #require(stored.first?.deliveredAt)
        #expect(
            stored[1].acceptedAt < firstDeliveredAt,
            "The second was accepted while the first was still open, and that is not a fault"
        )
        #expect(shift.numberedDeliveries.map(\.title) == ["Delivery 1", "Delivery 2"])
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
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(first, at: at(900))
        try service.markPickedUp(first, at: at(1_020))
        try service.markDelivered(first, at: at(1_200))
        try service.markArrivedAtPickup(second, at: at(1_500))
        try service.markPickedUp(second, at: at(1_800))
        try service.markDelivered(second, at: at(2_100))

        #expect(
            shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 0),
            "A migrated shift can hold stacked deliveries like any other"
        )
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
