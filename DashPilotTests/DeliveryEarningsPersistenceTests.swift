import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Per-delivery earnings in the store: the v7 schema, the migration that adds
/// them, and what survives a store being closed and reopened.
///
/// Every amount and every name below is invented. The repository holds no real
/// driver history and names no real business.
@MainActor
@Suite("Delivery earnings persistence")
struct DeliveryEarningsPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotDeliveryEarningsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    /// One completed shift holding `count` delivered deliveries, written through
    /// the real services.
    @discardableResult
    private func seedDeliveries(_ count: Int, in context: ModelContext) throws -> [Delivery] {
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        try shifts.startShift(at: start)

        let recorded = try (0..<count).map { index in
            let accepted = at(TimeInterval(index) * 3_600 + 300)
            let delivery = try deliveries.startDelivery(at: accepted)
            try deliveries.markArrivedAtPickup(delivery, at: accepted.addingTimeInterval(300))
            try deliveries.markPickedUp(delivery, at: accepted.addingTimeInterval(720))
            try deliveries.markDelivered(delivery, at: accepted.addingTimeInterval(1_800))
            return delivery
        }

        try shifts.endActiveShift(at: at(TimeInterval(count) * 3_600 + 3_600))
        return recorded
    }

    // MARK: Schema

    /// The one place the migration plan's shape is asserted.
    ///
    /// Deliberately a single authoritative check rather than a count repeated
    /// across suites: a schema version is added by one interval, and a figure
    /// scattered over unrelated files is one that gets updated in four places
    /// and forgotten in the fifth.
    @Test("Version 7 is current, and it is the version that adds per-delivery earnings")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 7)
        #expect(DashPilotMigrationPlan.stages.count == 6)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV7.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities == ["Shift", "RouteSample", "Delivery", "PickupPlace"], "v7 adds no entity")

        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        let properties = Set(delivery.properties.map(\.name))
        #expect(properties.contains("grossEarningsAmount"), "The amount is real new shape, which is why this is v7")
        #expect(properties.contains("pickupPlace"), "And everything v6 held is still held")
        #expect(properties.contains("acceptedAt"))
        #expect(properties.contains("deliveredAt"))
        #expect(properties.contains("cancelledAt"))
    }

    @Test("Version 6 described no per-delivery amount")
    func versionSixHeldNoDeliveryEarnings() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV6.self)

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let properties = delivery.properties.map(\.name)

        #expect(properties.contains("acceptedAt"), "The frozen v6 delivery still records its lifecycle")
        #expect(properties.contains("pickupPlace"), "v6 is the version that had pickup places")
        #expect(
            !properties.contains("grossEarningsAmount"),
            "The frozen v6 model must describe the store as it was, not as it is now"
        )

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        #expect(shift.properties.map(\.name).contains("grossEarningsAmount"), "The shift's own amount is older")
        #expect(schema.entities.map(\.name).contains("PickupPlace"))
    }

    // MARK: Reopening

    @Test("A delivered delivery's amount is still there after the store is reopened")
    func amountSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var deliveryID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let delivery = try #require(try seedDeliveries(1, in: context).first)
            try DeliveryService(context: context)
                .setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)
            deliveryID = delivery.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)

        #expect(stored.id == deliveryID)
        #expect(stored.grossEarnings == Money(exact: "14.75"), "The exact decimal, not a floating-point neighbour")
        #expect(stored.grossEarnings?.amount == Decimal(string: "14.75"))
    }

    @Test("A cancelled delivery's amount survives a reopen too")
    func cancelledAmountSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)
            let cancelled = try deliveries.startDelivery(at: at(300))
            try deliveries.markArrivedAtPickup(cancelled, at: at(600))
            try deliveries.cancelDelivery(cancelled, at: at(1_200))
            try shifts.endActiveShift(at: at(3_600))
            try deliveries.setGrossEarnings(try #require(Money(exact: "3.25")), on: cancelled)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)

        #expect(stored.state == .cancelled)
        #expect(stored.grossEarnings == Money(exact: "3.25"))
    }

    @Test("A delivery with no amount reopens with none, and one recorded as zero reopens as zero")
    func missingAndZeroStayApartAcrossAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var zeroID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let deliveries = try seedDeliveries(2, in: context)
            try DeliveryService(context: context).setGrossEarnings(.zero, on: deliveries[1])
            zeroID = deliveries[1].id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(stored.count == 2)
        #expect(stored.first?.grossEarnings == nil, "No amount was recorded, and none was invented on the way out")
        #expect(stored.last?.id == zeroID)
        #expect(stored.last?.grossEarnings == Money.zero, "A recorded zero is a figure the driver typed")
    }

    @Test("An edited amount survives, and so does a removed one")
    func editsAndRemovalsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let deliveries = try seedDeliveries(2, in: context)
            let service = DeliveryService(context: context)
            try service.setGrossEarnings(try #require(Money(exact: "14.75")), on: deliveries[0])
            try service.setGrossEarnings(try #require(Money(exact: "9.50")), on: deliveries[0])
            try service.setGrossEarnings(try #require(Money(exact: "20.00")), on: deliveries[1])
            try service.clearGrossEarnings(on: deliveries[1])
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(stored.first?.grossEarnings == Money(exact: "9.50"), "The edit replaced the amount in the store")
        #expect(stored.last?.grossEarnings == nil, "The removal is a removal, not a zero")
    }

    @Test("A shift's amount and its deliveries' amounts reopen independently")
    func bothAmountsSurviveSeparately() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let deliveries = try seedDeliveries(2, in: context)
            let shift = try #require(deliveries.first?.shift)
            try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "86.25")), on: shift)
            try DeliveryService(context: context)
                .setGrossEarnings(try #require(Money(exact: "14.75")), on: deliveries[0])
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let stored = shift.deliveriesInOrder

        #expect(shift.grossEarnings == Money(exact: "86.25"))
        #expect(stored.first?.grossEarnings == Money(exact: "14.75"))
        #expect(stored.last?.grossEarnings == nil, "The store keeps three separate facts, and adds up none of them")
    }

    // MARK: Migration

    @Test("A version 6 store opens under version 7 with everything it held and no invented amounts")
    func migratesAVersionSixStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let runningID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let cancelledID = UUID()
        let placeID = UUID()
        let session = UUID()

        // A store exactly as a build without per-delivery earnings would have
        // left one: two shifts, a route, a recorded shift amount, three
        // deliveries and a pickup place two of them share.
        do {
            let v6 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV6.self, at: storeURL)
            let context = ModelContext(v6)

            let paid = DashPilotSchemaV6.Shift(
                id: paidID,
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)
            context.insert(DashPilotSchemaV6.Shift(id: runningID, startedAt: at(10_800)))

            for step in 0..<4 {
                let position = SyntheticRoute.sample(at: at(TimeInterval(step) * 10), northMetres: Double(step) * 100)
                context.insert(
                    DashPilotSchemaV6.RouteSample(
                        shift: paid,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }

            let noodles = DashPilotSchemaV6.PickupPlace(
                id: placeID,
                displayName: "Nowhere Noodles",
                normalizedName: PickupPlaceName.comparisonKey(of: "Nowhere Noodles"),
                createdAt: start
            )
            context.insert(noodles)

            // Waits of 7 and 12 minutes at the same place, and a cancellation
            // that recorded no pickup at all — the metrics below have to come
            // out of the migrated store unchanged.
            context.insert(
                DashPilotSchemaV6.Delivery(
                    id: firstID,
                    shift: paid,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800),
                    pickupPlace: noodles
                )
            )
            context.insert(
                DashPilotSchemaV6.Delivery(
                    id: secondID,
                    shift: paid,
                    acceptedAt: at(2_400),
                    arrivedAtPickupAt: at(2_700),
                    pickedUpAt: at(3_420),
                    deliveredAt: at(4_200),
                    pickupPlace: noodles
                )
            )
            context.insert(
                DashPilotSchemaV6.Delivery(
                    id: cancelledID,
                    shift: paid,
                    acceptedAt: at(5_400),
                    arrivedAtPickupAt: at(5_700),
                    cancelledAt: at(6_000)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        let samples = try context.fetch(FetchDescriptor<RouteSample>())
        let deliveries = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)
        let places = try context.fetch(FetchDescriptor<PickupPlace>())

        // Everything the store already held.
        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [paidID, runningID])
        #expect(shifts.first?.grossEarnings == Money(exact: "86.25"), "Shift earnings survive exactly")
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        #expect(samples.count == 4, "Migration must not drop stored positions")
        #expect(samples.allSatisfy { $0.captureSessionID == session }, "Capture continuity survives")

        #expect(deliveries.map(\.id) == [firstID, secondID, cancelledID], "Migration must not drop deliveries")
        #expect(deliveries.map(\.state) == [.delivered, .delivered, .cancelled], "Every lifecycle timestamp survives")
        #expect(deliveries.map(\.pickupWait) == [420, 720, nil], "Pickup waits are unchanged")
        #expect(deliveries.first?.completedDuration == 1_500)

        // Pickup identity, by row rather than by spelling.
        #expect(places.count == 1, "Migration must not duplicate a place")
        #expect(places.first?.id == placeID)
        #expect(places.first?.displayName == "Nowhere Noodles")
        #expect(places.first?.normalizedName == PickupPlaceName.comparisonKey(of: "Nowhere Noodles"))
        #expect(deliveries.map { $0.pickupPlace?.id } == [placeID, placeID, nil], "Relationships survive")

        // The derived figures come out of the migrated store identical.
        let place = try #require(places.first)
        let waits = place.pickupWaitMetrics()
        #expect(waits.sampleCount == 2)
        #expect(waits.medianDuration == 570, "The midpoint of 7 and 12 minutes, exactly as before")
        #expect(waits.shortestDuration == 420)
        #expect(waits.longestDuration == 720)

        let activeTime = try #require(shifts.first).deliveryActiveTime()
        #expect(activeTime.duration == 1_500 + 1_800 + 600, "The union of three non-overlapping lifecycles")
        #expect(activeTime.sourceIntervalCount == 3)
        #expect(!activeTime.hasOverlappingDeliveries)

        // And the one thing this version step must not do.
        #expect(
            deliveries.allSatisfy { $0.grossEarnings == nil },
            "A store written before per-delivery earnings existed records none, and none is invented for it"
        )
        #expect(
            deliveries.allSatisfy { $0.grossEarnings != Money.zero },
            "Not even a zero: a delivery nobody recorded a figure for did not record one of nothing"
        )
    }

    @Test("A shift's recorded amount is not divided among the deliveries under it")
    func migrationSplitsNoShiftTotal() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        // The store that makes the mistake tempting: one shift, one round
        // amount, and exactly four deliveries to divide it by.
        do {
            let v6 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV6.self, at: storeURL)
            let context = ModelContext(v6)
            let shift = DashPilotSchemaV6.Shift(
                startedAt: start,
                endedAt: at(14_400),
                grossEarningsAmount: Decimal(string: "100.00")
            )
            context.insert(shift)

            for index in 0..<4 {
                let accepted = at(TimeInterval(index) * 3_600 + 300)
                context.insert(
                    DashPilotSchemaV6.Delivery(
                        shift: shift,
                        acceptedAt: accepted,
                        arrivedAtPickupAt: accepted.addingTimeInterval(300),
                        pickedUpAt: accepted.addingTimeInterval(720),
                        deliveredAt: accepted.addingTimeInterval(1_800)
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let deliveries = shift.deliveriesInOrder

        #expect(shift.grossEarnings == Money(exact: "100.00"), "The one amount the driver typed is untouched")
        #expect(deliveries.count == 4)
        #expect(
            deliveries.allSatisfy { $0.grossEarnings == nil },
            "$25.00 each would be four figures the driver never typed, and nothing could tell them apart afterwards"
        )
        #expect(deliveries.allSatisfy { $0.grossPerDeliveryHour == .unavailable(.earningsNotRecorded) })
    }

    @Test("A migrated delivery can then be given an amount")
    func aMigratedDeliveryAcceptsAnAmount() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v6 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV6.self, at: storeURL)
            let context = ModelContext(v6)
            let shift = DashPilotSchemaV6.Shift(startedAt: start, endedAt: at(3_600))
            context.insert(shift)
            context.insert(
                DashPilotSchemaV6.Delivery(
                    shift: shift,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)

        try DeliveryService(context: context).setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(delivery.grossEarnings == Money(exact: "14.75"))
        #expect(delivery.deliveredAt == at(1_800), "Recording it changed nothing that was migrated")
        #expect(delivery.grossPerDeliveryHour == .available(try #require(Money(exact: "35.4"))))
    }

    @Test("Every earlier store still reaches version 7, with no fabricated amount", arguments: [1, 2, 3, 4, 5, 6])
    func earlierStoresStillMigrate(fromVersion: Int) throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()
        let deliveryID = UUID()
        let session = UUID()
        let position = SyntheticRoute.sample(at: at(10), northMetres: 100)

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
            case 3:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV3.self, at: storeURL)
                )
                let shift = DashPilotSchemaV3.Shift(id: shiftID, startedAt: start, endedAt: at(3_600))
                context.insert(shift)
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
            case 4:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV4.self, at: storeURL)
                )
                let shift = DashPilotSchemaV4.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: at(3_600),
                    grossEarningsAmount: Decimal(string: "86.25")
                )
                context.insert(shift)
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
                try context.save()
            case 5:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV5.self, at: storeURL)
                )
                let shift = DashPilotSchemaV5.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: at(3_600),
                    grossEarningsAmount: Decimal(string: "86.25")
                )
                context.insert(shift)
                context.insert(
                    DashPilotSchemaV5.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
                context.insert(
                    DashPilotSchemaV5.Delivery(
                        id: deliveryID,
                        shift: shift,
                        acceptedAt: at(300),
                        arrivedAtPickupAt: at(600),
                        pickedUpAt: at(1_020),
                        deliveredAt: at(1_800)
                    )
                )
                try context.save()
            default:
                let context = ModelContext(
                    try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV6.self, at: storeURL)
                )
                let shift = DashPilotSchemaV6.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: at(3_600),
                    grossEarningsAmount: Decimal(string: "86.25")
                )
                context.insert(shift)
                context.insert(
                    DashPilotSchemaV6.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
                let place = DashPilotSchemaV6.PickupPlace(
                    displayName: "Nowhere Noodles",
                    normalizedName: PickupPlaceName.comparisonKey(of: "Nowhere Noodles"),
                    createdAt: start
                )
                context.insert(place)
                context.insert(
                    DashPilotSchemaV6.Delivery(
                        id: deliveryID,
                        shift: shift,
                        acceptedAt: at(300),
                        arrivedAtPickupAt: at(600),
                        pickedUpAt: at(1_020),
                        deliveredAt: at(1_800),
                        pickupPlace: place
                    )
                )
                try context.save()
            }
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.completedDuration == 3_600)
        #expect(shift.routeSamples.count == (fromVersion == 1 ? 0 : 1))
        #expect(shift.grossEarnings == (fromVersion >= 4 ? Money(exact: "86.25") : nil))
        #expect(shift.deliveries.count == (fromVersion >= 5 ? 1 : 0), "No version step fabricates a delivery")
        #expect(
            shift.deliveries.allSatisfy { $0.grossEarnings == nil },
            "And no version step fabricates an amount for one"
        )
        #expect(
            try context.fetch(FetchDescriptor<PickupPlace>()).count == (fromVersion == 6 ? 1 : 0),
            "A v6 store's place survives, and no earlier store gains one"
        )
        if fromVersion >= 5 {
            #expect(shift.deliveries.first?.id == deliveryID)
            #expect(shift.deliveries.first?.pickupWait == 420, "Pickup waits survive every step")
        }
        if fromVersion == 6 {
            #expect(shift.deliveries.first?.pickupPlace?.displayName == "Nowhere Noodles")
        }
    }
}
