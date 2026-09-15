import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedSave: Error {}

/// The offer entity in the store: the v12 schema, the custom migration that
/// gives every historical delivery its own one-delivery offer, and what survives
/// a store being closed and reopened.
///
/// The claim the migration has to prove is a pair. Every pre-v12 delivery must
/// come out of it grouped, because a delivery holding no offer is a row this
/// build cannot produce; and no two of them may come out grouped **together**,
/// because a v11 store holds no evidence that any two deliveries arrived in one
/// acceptance.
///
/// Every timestamp, amount and name is invented.
@MainActor
@Suite("Delivery offer persistence")
struct DeliveryOfferPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotOfferTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// Version 12's own shape, now that it is frozen.
    ///
    /// The plan's version and stage counts moved to `DeliveryTipPersistenceTests`
    /// with v13, by the repository's convention that they live in the suite
    /// belonging to whichever version is current. What stays here is the claim
    /// this suite exists for: the current store still carries the offer, and the
    /// frozen v12 describes exactly the shape a v12 store had.
    @Test("Version 12 is the one that adds the offer, and the current store still carries it")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV12.versionIdentifier == Schema.Version(12, 0, 0))

        let frozen = Schema(versionedSchema: DashPilotSchemaV12.self)
        #expect(
            Set(frozen.entities.map(\.name))
                == ["Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause", "Offer"],
            "v12 adds exactly one entity, and held no tip"
        )

        let offer = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Offer" })
        #expect(
            Set(offer.properties.map(\.name)) == ["id", "acceptedAt", "shift", "deliveries"],
            "An offer holds an acceptance and its deliveries, and no money, duration or platform field"
        )

        // The delivery gains the reference and keeps everything it had,
        // including the shift it is still fetched, aggregated and deleted by.
        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        #expect(
            Set(delivery.properties.map(\.name)) == [
                "id", "acceptedAt", "arrivedAtPickupAt", "pickedUpAt", "deliveredAt", "cancelledAt",
                "shift", "offer", "pickupPlace", "grossEarningsAmount", "expectedEarningsAmount",
                "additionalTips"
            ]
        )

        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(
            Set(shift.properties.map(\.name))
                == ["id", "startedAt", "endedAt", "deliveries", "offers", "pauses", "grossEarningsAmount"]
        )
    }

    @Test("The frozen version 11 still describes a delivery that belongs to no offer")
    func versionElevenHeldNoOffer() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV11.self)

        #expect(
            !Set(schema.entities.map(\.name)).contains("Offer"),
            "The frozen v11 model must describe the store as it was, not as it is now"
        )

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let properties = Set(delivery.properties.map(\.name))
        #expect(!properties.contains("offer"))
        #expect(properties.contains("expectedEarningsAmount"), "v11 is the version that added expected pay")
        #expect(properties.contains("grossEarningsAmount"))

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let shiftProperties = Set(shift.properties.map(\.name))
        #expect(!shiftProperties.contains("offers"))
        #expect(!shiftProperties.contains("routeSamples"), "v10 removed the collection, and v11 kept it removed")
        #expect(shiftProperties.contains("deliveries"))
        #expect(shiftProperties.contains("pauses"))
    }

    // MARK: Migration

    @Test("Every version 11 delivery reaches version 12 inside a one-delivery offer of its own")
    func migratesFromVersionEleven() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let expectingID = UUID()
        let cancelledID = UUID()
        let secondShiftDeliveryID = UUID()

        do {
            let v11 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV11.self, at: storeURL)
            let context = ModelContext(v11)

            let shift = DashPilotSchemaV11.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(shift)

            // Two deliveries accepted one second apart on the same shift. This
            // is the shape the migration must not read as a stacked offer: a
            // driver tapping Start Delivery twice produces exactly it.
            context.insert(
                DashPilotSchemaV11.Delivery(
                    id: paidID,
                    shift: shift,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800),
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )
            context.insert(
                DashPilotSchemaV11.Delivery(
                    id: expectingID,
                    shift: shift,
                    acceptedAt: at(301),
                    arrivedAtPickupAt: at(620),
                    pickedUpAt: at(1_040),
                    deliveredAt: at(1_900),
                    expectedEarningsAmount: Decimal(string: "8.50")
                )
            )
            context.insert(
                DashPilotSchemaV11.Delivery(
                    id: cancelledID,
                    shift: shift,
                    acceptedAt: at(4_000),
                    arrivedAtPickupAt: at(4_300),
                    cancelledAt: at(4_600),
                    grossEarningsAmount: .zero
                )
            )

            let otherShift = DashPilotSchemaV11.Shift(startedAt: at(20_000), endedAt: at(27_200))
            context.insert(otherShift)
            context.insert(
                DashPilotSchemaV11.Delivery(
                    id: secondShiftDeliveryID,
                    shift: otherShift,
                    acceptedAt: at(20_300),
                    arrivedAtPickupAt: at(20_600),
                    pickedUpAt: at(21_000),
                    deliveredAt: at(21_800)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)
        #expect(stored.count == 4)

        // Grouped, every one of them.
        for delivery in stored {
            let offer = try #require(delivery.offer, "A migrated delivery is not left holding no offer")
            #expect(offer.deliveryCount == 1, "One delivery per historical offer, and never two")
            #expect(
                offer.acceptedAt == delivery.acceptedAt,
                "The offer takes the only acceptance the store records, which is the delivery's own"
            )
            #expect(offer.shift?.id == delivery.shift?.id, "And it belongs to the shift the delivery does")
        }

        // And no two of them together, including the pair a second apart.
        let offerIDs = stored.compactMap { $0.offer?.id }
        #expect(Set(offerIDs).count == 4, "Four deliveries, four offers")
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 4)

        // Every fact the store already held is exactly what it was.
        let paid = try #require(stored.first { $0.id == paidID })
        #expect(paid.grossEarnings == Money(exact: "14.75"), "The exact decimal, not a floating-point neighbour")
        #expect(paid.state == .delivered)
        #expect(paid.deliveredAt == at(1_800))
        #expect(paid.expectedEarnings == nil)

        let expecting = try #require(stored.first { $0.id == expectingID })
        #expect(expecting.expectedEarnings == Money(exact: "8.50"))
        #expect(expecting.grossEarnings == nil, "Missing stays missing")

        let cancelled = try #require(stored.first { $0.id == cancelledID })
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.grossEarnings == Money.zero, "A recorded zero is still a figure the driver typed")
        #expect(cancelled.offer?.state == .cancelled, "Its offer ended the way its one delivery did")

        // Each shift holds only its own offers.
        let shifts = try context.fetch(FetchDescriptor<Shift>()).sorted { $0.startedAt < $1.startedAt }
        #expect(shifts.count == 2)
        #expect(shifts[0].offers.count == 3)
        #expect(shifts[1].offers.count == 1)
        #expect(shifts[0].grossEarnings == Money(exact: "86.25"), "The shift's own amount is untouched")
    }

    @Test("Nothing a migrated shift reports changes value across the version step")
    func aggregatesSurviveTheVersionStep() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v11 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV11.self, at: storeURL)
            let context = ModelContext(v11)
            let shift = DashPilotSchemaV11.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "100.00")
            )
            context.insert(shift)
            // Two deliveries that overlap completely, so the unioned active time
            // is the one figure a grouping mistake would move.
            context.insert(
                DashPilotSchemaV11.Delivery(
                    shift: shift,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800),
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )
            context.insert(
                DashPilotSchemaV11.Delivery(
                    shift: shift,
                    acceptedAt: at(400),
                    arrivedAtPickupAt: at(700),
                    pickedUpAt: at(1_100),
                    deliveredAt: at(1_700)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        #expect(metrics.recordedGrossEarnings == Money(exact: "100.00"))
        #expect(metrics.recordedDeliveryEarnings == Money(exact: "14.75"))
        #expect(metrics.deliveryEarningsCoverage.contributingCount == 1)
        #expect(metrics.deliveryEarningsCoverage.eligibleCount == 2)

        // The union of 300 to 1,800 and 400 to 1,700, which is 1,500 seconds and
        // is what it was before offers existed.
        #expect(shift.deliveryActiveTime().duration == 1_500)
        #expect(shift.metrics(for: .none).grossPerWorkingHour.amount == Money(exact: "50.00"))
        #expect(shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 0))
    }

    @Test("A migrated delivery's offer survives being read through a fresh container")
    func migratedOffersSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v11 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV11.self, at: storeURL)
            let context = ModelContext(v11)
            let shift = DashPilotSchemaV11.Shift(startedAt: start, endedAt: at(7_200))
            context.insert(shift)
            context.insert(DashPilotSchemaV11.Delivery(shift: shift, acceptedAt: at(300), deliveredAt: at(900)))
            try context.save()
        }

        // The migrating open.
        _ = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))

        // A second open does no further work and must not add a second offer.
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(try reopened.fetch(FetchDescriptor<Offer>()).count == 1)
        let delivery = try #require(try reopened.fetch(FetchDescriptor<Delivery>()).first)
        #expect(delivery.offer != nil)
        #expect(delivery.offer?.deliveryCount == 1)
    }

    // MARK: Reopening a store this build wrote

    @Test("An offer of two survives a reopen with both deliveries still in it")
    func groupedOfferSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let offerID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)
            let offer = try deliveries.startOffer(deliveryCount: 2, at: at(300))
            offerID = offer.id
            let ordered = offer.deliveriesInOrder
            try deliveries.markArrivedAtPickup(ordered[0], at: at(600))
            try deliveries.markPickedUp(ordered[0], at: at(900))
            try deliveries.markDelivered(ordered[0], at: at(1_500))
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try reopened.fetch(FetchDescriptor<Offer>())
        #expect(stored.count == 1)

        let offer = try #require(stored.first { $0.id == offerID })
        #expect(offer.deliveryCount == 2)
        #expect(offer.acceptedAt == at(300))
        #expect(offer.state == .inProgress, "One delivered, one still running")
        #expect(offer.activeDeliveries.count == 1)

        // The delivery left running is recovered as running, with its own offer,
        // which is what relaunch recovery has to produce.
        let shift = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.activeDeliveries.count == 1)
        #expect(shift.activeDeliveries.first?.offer?.id == offerID)
        #expect(shift.numberedOffers.first?.deliveries.map(\.number) == [1, 2])
    }

    @Test("Deleting a completed shift takes its offers with it")
    func deletingAShiftTakesItsOffers() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        let shift = try shifts.startShift(at: start)
        let offer = try deliveries.startOffer(deliveryCount: 2, at: at(300))
        for delivery in offer.deliveriesInOrder {
            try deliveries.markArrivedAtPickup(delivery, at: at(600))
            try deliveries.markPickedUp(delivery, at: at(900))
            try deliveries.markDelivered(delivery, at: at(1_500))
        }
        try shifts.endActiveShift(at: at(7_200))

        try shifts.deleteCompletedShift(shift)

        #expect(try context.fetch(FetchDescriptor<Shift>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty, "No offer is left describing a shift that is gone")
    }

    @Test("A rollback leaves the offers and deliveries the store holds agreeing with each other")
    func rollbackLeavesRelationshipsCoherent() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let first = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(300))
        let firstID = first.id

        let refusing = DeliveryService(context: context, commit: { _ in throw RefusedSave() })
        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try refusing.startOffer(deliveryCount: 3, at: at(900))
        }

        // Read through a fresh context: after a rollback the authoritative store
        // and a held relationship cache can differ, and the store is what a
        // relaunch would show.
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())
        let stored = try reopened.fetch(FetchDescriptor<Delivery>())

        #expect(offers.count == 1)
        #expect(stored.count == 2)
        #expect(offers.first?.id == firstID)
        #expect(offers.first?.deliveryCount == 2)
        #expect(stored.allSatisfy { $0.offer?.id == firstID }, "No delivery is left pointing at a discarded offer")
        #expect(stored.allSatisfy { $0.shift != nil })

        let shift = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.offers.count == 1)
        #expect(shift.deliveries.count == 2)
    }
}
