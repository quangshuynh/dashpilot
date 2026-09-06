import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Pickup identity in the store: the v6 schema, the migration that adds it, and
/// what survives a store being closed and reopened.
///
/// Every name below is invented. The repository names no real business.
@MainActor
@Suite("Pickup place persistence")
struct PickupPlacePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotPickupPlaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// What v6 added, and nothing about the plan's overall shape: the version
    /// count and the stage count are asserted once, in the suite for whichever
    /// version is current — `DeliveryEarningsPersistenceTests` today. A count
    /// repeated across suites is one that gets updated in four places and
    /// forgotten in the fifth.
    @Test("Version 6 is the version that adds pickup places")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))

        // Read from the frozen v6 schema rather than from whichever version is
        // current: this test is about what v6 held, and a later version adding
        // an entity beside those four does not change that.
        let schema = Schema(versionedSchema: DashPilotSchemaV6.self)
        let entities = Set(schema.entities.map(\.name))
        #expect(entities == ["Shift", "RouteSample", "Delivery", "PickupPlace"])

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(delivery.properties.map(\.name).contains("pickupPlace"))

        let place = try #require(schema.entities.first { $0.name == "PickupPlace" })
        let properties = Set(place.properties.map(\.name))
        #expect(properties == ["id", "displayName", "normalizedName", "createdAt", "deliveries"])
        #expect(
            !properties.contains("visitCount") && !properties.contains("lastUsedAt"),
            "Nothing aggregated is stored on a place; every such figure is derived from its deliveries"
        )
    }

    @Test("Version 5 described no pickup identity")
    func versionFiveHeldNoPickupPlaces() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV5.self)
        #expect(!schema.entities.map(\.name).contains("PickupPlace"))

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let properties = delivery.properties.map(\.name)

        #expect(properties.contains("acceptedAt"), "The frozen v5 delivery still records its lifecycle")
        #expect(properties.contains("cancelledAt"))
        #expect(
            !properties.contains("pickupPlace"),
            "The frozen v5 model must describe the store as it was, not as it is now"
        )

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let shiftProperties = shift.properties.map(\.name)
        #expect(shiftProperties.contains("deliveries"), "v5 is the version that had deliveries")
        #expect(shiftProperties.contains("grossEarningsAmount"))
        #expect(shiftProperties.contains("routeSamples"))
    }

    @Test("A place records the name it was given and the key it is matched by")
    func roundTripsAPlace() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let name = try PickupPlaceName("  Nowhere   Noodles ")
        context.insert(PickupPlace(name: name, createdAt: start))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<PickupPlace>()).first)

        #expect(stored.displayName == "Nowhere Noodles")
        #expect(stored.normalizedName == "nowhere noodles")
        #expect(stored.createdAt == start)
        #expect(stored.deliveries.isEmpty)
    }

    // MARK: Reopening

    @Test("An assigned pickup place is still assigned after the store is reopened")
    func assignmentSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var deliveryID = UUID()
        var placeID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let delivery = try DeliveryService(context: context).startDelivery(at: at(300))
            let place = try PickupPlaceService(context: context)
                .assignPlace(named: "Nowhere Noodles", to: delivery, at: at(300))
            deliveryID = delivery.id
            placeID = place.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let delivery = try #require(try DeliveryService(context: context).activeDeliveries().first)

        #expect(delivery.id == deliveryID)
        #expect(delivery.pickupPlace?.id == placeID, "The same place, not a replacement")
        #expect(delivery.pickupPlace?.displayName == "Nowhere Noodles")
        #expect(try context.fetch(FetchDescriptor<PickupPlace>()).count == 1)
    }

    @Test("A reopened store reuses the place it already holds rather than adding a second")
    func reuseSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var placeID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: start)
            let delivery = try DeliveryService(context: context).startDelivery(at: at(300))
            placeID = try PickupPlaceService(context: context)
                .assignPlace(named: "Nowhere Noodles", to: delivery, at: at(300)).id
        }

        // A new process typing the same name a different way.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let second = try DeliveryService(context: context).startDelivery(at: at(900))
        let resolved = try PickupPlaceService(context: context)
            .assignPlace(named: "  NOWHERE noodles  ", to: second, at: at(900))

        #expect(resolved.id == placeID, "The normalised key matched a place written by the earlier process")
        #expect(resolved.displayName == "Nowhere Noodles", "And the original spelling was not rewritten")
        #expect(try context.fetch(FetchDescriptor<PickupPlace>()).count == 1)
    }

    @Test("Several deliveries pointing at one place all point at it after a reopen")
    func sharedPlaceSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            let places = PickupPlaceService(context: context)
            try shifts.startShift(at: start)

            for step in 0..<3 {
                let delivery = try deliveries.startDelivery(at: at(Double(step) * 600))
                try places.assignPlace(named: step == 1 ? "Example Diner" : "nowhere noodles", to: delivery)
                try deliveries.markArrivedAtPickup(delivery, at: at(Double(step) * 600 + 60))
                try deliveries.markPickedUp(delivery, at: at(Double(step) * 600 + 120))
                try deliveries.markDelivered(delivery, at: at(Double(step) * 600 + 180))
            }
            try shifts.endActiveShift(at: at(3_600))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let stored = shift.deliveriesInOrder

        #expect(stored.count == 3)
        #expect(try context.fetch(FetchDescriptor<PickupPlace>()).count == 2, "Two places, not three")
        let shared = try #require(stored.first?.pickupPlace)
        #expect(stored[2].pickupPlace?.id == shared.id, "The first and third still share one identity")
        #expect(stored[1].pickupPlace?.id != shared.id)
        #expect(Set(shared.deliveries.map(\.id)) == [stored[0].id, stored[2].id], "And the place knows both")
        #expect(shared.lastUsedAt == stored[2].acceptedAt)
    }

    // MARK: Derived pickup waits

    /// A place's recorded waits are read back from its relationships, so what
    /// they add up to must be identical either side of a reopen — and no
    /// aggregate may appear in the store to make it so.
    @Test("Pickup wait metrics after a reopen equal the metrics before it")
    func waitMetricsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let before: PickupWaitMetrics
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            let places = PickupPlaceService(context: context)
            try shifts.startShift(at: start)

            // Waits of 6, 11 and 41 minutes at one place, plus one delivery that
            // arrived there and cancelled without ever picking up.
            for (step, wait) in [360.0, 660.0, 2_460.0].enumerated() {
                let accepted = Double(step) * 3_600
                let delivery = try deliveries.startDelivery(at: at(accepted))
                try places.assignPlace(named: "Nowhere Noodles", to: delivery)
                try deliveries.markArrivedAtPickup(delivery, at: at(accepted + 300))
                try deliveries.markPickedUp(delivery, at: at(accepted + 300 + wait))
                try deliveries.markDelivered(delivery, at: at(accepted + 900 + wait))
            }

            let abandoned = try deliveries.startDelivery(at: at(12_000))
            try places.assignPlace(named: "nowhere noodles", to: abandoned)
            try deliveries.markArrivedAtPickup(abandoned, at: at(12_300))
            try deliveries.cancelDelivery(abandoned, at: at(14_100))

            try shifts.endActiveShift(at: at(18_000))

            let place = try #require(try context.fetch(FetchDescriptor<PickupPlace>()).first)
            before = place.pickupWaitMetrics()
            #expect(before.sampleCount == 3, "The cancelled delivery recorded no wait")
            #expect(before.medianDuration == 660)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let place = try #require(try context.fetch(FetchDescriptor<PickupPlace>()).first)
        let after = place.pickupWaitMetrics()

        #expect(after == before, "Reopening the store changes nothing that is derived from it")
        #expect(place.deliveries.count == 4, "All four deliveries still name the place")
        #expect(after.sampleCount == 3)
        #expect(after.medianDuration == 660)
        #expect(after.longestDuration == 2_460, "The long wait is still on the record")
        #expect(!context.hasChanges, "Reading a place's history writes nothing back")
    }

    @Test("Two places reopened from one store keep their own histories")
    func twoPlacesKeepSeparateHistoriesAcrossAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            let places = PickupPlaceService(context: context)
            try shifts.startShift(at: start)

            for (step, wait) in [300.0, 900.0, 1_800.0].enumerated() {
                let accepted = Double(step) * 3_600
                let delivery = try deliveries.startDelivery(at: at(accepted))
                try places.assignPlace(named: step == 2 ? "Example Diner" : "Nowhere Noodles", to: delivery)
                try deliveries.markArrivedAtPickup(delivery, at: at(accepted + 120))
                try deliveries.markPickedUp(delivery, at: at(accepted + 120 + wait))
                try deliveries.markDelivered(delivery, at: at(accepted + 600 + wait))
            }
            try shifts.endActiveShift(at: at(18_000))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<PickupPlace>()).sorted(by: PickupPlace.namedBefore)
        let noodles = try #require(stored.first { $0.displayName == "Nowhere Noodles" })
        let diner = try #require(stored.first { $0.displayName == "Example Diner" })

        #expect(noodles.pickupWaitMetrics().sampleCount == 2)
        #expect(noodles.pickupWaitMetrics().medianDuration == 600, "The midpoint of 5 and 15 minutes")
        #expect(noodles.pickupWaitMetrics().availability == .available)

        #expect(diner.pickupWaitMetrics().sampleCount == 1)
        #expect(diner.pickupWaitMetrics().medianDuration == 1_800)
        #expect(
            diner.pickupWaitMetrics().availability == .insufficientHistory,
            "One recorded pickup is a fact, not a typical wait"
        )
        #expect(diner.pickupWaitMetrics().typicalDuration == nil)
    }

    // MARK: Correction

    @Test("A renamed place is still one place, under its new name, after a reopen")
    func renameSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var placeID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let deliveries = DeliveryService(context: context)
            let places = PickupPlaceService(context: context)
            try ShiftService(context: context).startShift(at: start)

            let delivery = try deliveries.startDelivery(at: at(300))
            let place = try places.assignPlace(named: "Nowhere Noodle", to: delivery, at: at(300))
            try deliveries.markArrivedAtPickup(delivery, at: at(420))
            try deliveries.markPickedUp(delivery, at: at(780))
            try deliveries.markDelivered(delivery, at: at(1_200))

            try places.rename(place, to: "Nowhere Noodles")
            placeID = place.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<PickupPlace>())

        #expect(stored.count == 1, "A rename corrected a row rather than leaving two behind")
        let place = try #require(stored.first)
        #expect(place.id == placeID, "The same row, not a replacement")
        #expect(place.displayName == "Nowhere Noodles")
        #expect(place.deliveries.count == 1)
        #expect(place.pickupWaitMetrics().sampleCount == 1)
        #expect(place.pickupWaitMetrics().medianDuration == 360, "The six-minute wait recorded before the rename")

        // The persisted key moved with the spelling, so the new name is what
        // finds this place in a later process.
        let resolved = try PickupPlaceService(context: context).resolvePlace(named: "nowhere noodles", at: at(3_600))
        #expect(resolved.id == placeID)
        #expect(try context.fetch(FetchDescriptor<PickupPlace>()).count == 1)
    }

    @Test("A reopened store holds only the destination, with both places' deliveries")
    func mergeSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var destinationID = UUID()
        var sourceID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            let places = PickupPlaceService(context: context)
            try shifts.startShift(at: start)

            // Waits of 5, 15 and 30 minutes: the first two at the destination,
            // the third at the place merged into it.
            for (step, wait) in [300.0, 900.0, 1_800.0].enumerated() {
                let accepted = Double(step) * 3_600
                let delivery = try deliveries.startDelivery(at: at(accepted))
                try places.assignPlace(named: step == 2 ? "Example Diner" : "Nowhere Noodles", to: delivery)
                try deliveries.markArrivedAtPickup(delivery, at: at(accepted + 120))
                try deliveries.markPickedUp(delivery, at: at(accepted + 120 + wait))
                try deliveries.markDelivered(delivery, at: at(accepted + 600 + wait))
            }
            try shifts.endActiveShift(at: at(18_000))

            let stored = try context.fetch(FetchDescriptor<PickupPlace>())
            let destination = try #require(stored.first { $0.displayName == "Nowhere Noodles" })
            let source = try #require(stored.first { $0.displayName == "Example Diner" })
            destinationID = destination.id
            sourceID = source.id

            try places.merge(source, into: destination)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<PickupPlace>())

        #expect(stored.map(\.id) == [destinationID], "The source is gone from the store, not just from a relationship")
        #expect(!stored.contains { $0.id == sourceID })

        let destination = try #require(stored.first)
        #expect(destination.displayName == "Nowhere Noodles", "The destination's own spelling survived")
        #expect(destination.deliveries.count == 3)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 3, "No delivery was deleted with the place")
        #expect(try context.fetch(FetchDescriptor<Delivery>()).allSatisfy { $0.pickupPlace?.id == destinationID })

        // 5, 15 and 30 minutes, recomputed from the relationship rather than
        // read from anything the merge wrote.
        let metrics = destination.pickupWaitMetrics()
        #expect(metrics.sampleCount == 3)
        #expect(metrics.medianDuration == 900)
        #expect(metrics.shortestDuration == 300)
        #expect(metrics.longestDuration == 1_800)
    }

    // MARK: Migration

    @Test("A version 5 store opens under version 6 with everything it held and no invented places")
    func migratesAVersionFiveStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let runningID = UUID()
        let deliveredID = UUID()
        let cancelledID = UUID()
        let session = UUID()

        // A store exactly as a build without pickup identity would have left
        // one: two shifts, a route, a recorded amount and two deliveries.
        do {
            let v5 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV5.self, at: storeURL)
            let context = ModelContext(v5)
            let paid = DashPilotSchemaV5.Shift(
                id: paidID,
                startedAt: start,
                endedAt: at(3_600),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)
            context.insert(DashPilotSchemaV5.Shift(id: runningID, startedAt: at(7_200)))

            for step in 0..<4 {
                let position = SyntheticRoute.sample(at: at(TimeInterval(step) * 10), northMetres: Double(step) * 100)
                context.insert(
                    DashPilotSchemaV5.RouteSample(
                        shift: paid,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }

            context.insert(
                DashPilotSchemaV5.Delivery(
                    id: deliveredID,
                    shift: paid,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800)
                )
            )
            context.insert(
                DashPilotSchemaV5.Delivery(
                    id: cancelledID,
                    shift: paid,
                    acceptedAt: at(2_400),
                    arrivedAtPickupAt: at(2_700),
                    cancelledAt: at(3_000)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        let samples = try context.fetch(FetchDescriptor<RouteSample>())
        let deliveries = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [paidID, runningID])
        #expect(shifts.first?.grossEarnings == Money(exact: "86.25"), "Gross earnings survive exactly")
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        #expect(samples.count == 4, "Migration must not drop stored positions")
        #expect(samples.allSatisfy { $0.captureSessionID == session }, "Capture continuity survives")

        #expect(deliveries.map(\.id) == [deliveredID, cancelledID], "Migration must not drop deliveries")
        #expect(deliveries.map(\.state) == [.delivered, .cancelled], "Every lifecycle timestamp survives")
        #expect(deliveries.first?.pickupWait == 420)
        #expect(deliveries.first?.completedDuration == 1_500)
        #expect(deliveries.last?.arrivedAtPickupAt == at(2_700))
        #expect(shifts.first?.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))

        #expect(
            try context.fetch(FetchDescriptor<PickupPlace>()).isEmpty,
            "A store written before pickup identity existed names no place, and none is invented for it"
        )
        #expect(
            deliveries.allSatisfy { $0.pickupPlace == nil },
            "No delivery is attributed to a business the driver never named"
        )
    }

    @Test("A migrated delivery can then be given a pickup place")
    func aMigratedDeliveryAcceptsAPlace() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v5 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV5.self, at: storeURL)
            let context = ModelContext(v5)
            let shift = DashPilotSchemaV5.Shift(startedAt: start, endedAt: at(3_600))
            context.insert(shift)
            context.insert(
                DashPilotSchemaV5.Delivery(
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

        try PickupPlaceService(context: context).assignPlace(named: "Nowhere Noodles", to: delivery, at: at(4_000))

        #expect(delivery.pickupPlace?.displayName == "Nowhere Noodles")
        #expect(delivery.deliveredAt == at(1_800), "Naming it changed nothing that was migrated")
    }

    @Test("Every earlier store still reaches version 6, with no fabricated place", arguments: [1, 2, 3, 4])
    func earlierStoresStillMigrate(fromVersion: Int) throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()
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
            default:
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
            }
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.completedDuration == 3_600)
        #expect(shift.routeSamples.count == (fromVersion == 1 ? 0 : 1))
        #expect(shift.grossEarnings == (fromVersion == 4 ? Money(exact: "86.25") : nil))
        #expect(shift.deliveries.isEmpty, "No version step fabricates a delivery")
        #expect(
            try context.fetch(FetchDescriptor<PickupPlace>()).isEmpty,
            "And no version step fabricates a pickup place"
        )
        if fromVersion == 2 {
            #expect(shift.routeSamples.first?.captureSessionID == nil, "A v2 sample's continuity stays unproven")
        }
        if fromVersion >= 3 {
            #expect(shift.routeSamples.first?.captureSessionID == session)
        }
    }
}
