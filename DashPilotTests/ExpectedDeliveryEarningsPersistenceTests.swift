import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The expected-pay column in the store: the v11 schema, the migration that adds
/// it, and what survives a store being closed and reopened.
///
/// The claim a migration has to prove here is a **negative** one. A v10 store
/// holds delivered deliveries with recorded amounts sitting right beside a new
/// empty column, and the one thing this version must never do is fill it from
/// them. Every assertion below about a `nil` is that claim.
///
/// Every amount and every name is invented.
@MainActor
@Suite("Expected delivery earnings persistence")
struct ExpectedDeliveryEarningsPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotExpectedEarningsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v11 is the current version.
    ///
    /// The repository's convention is that the count of versions and stages
    /// lives in the suite belonging to whichever version is current, so it is
    /// updated in one place rather than in four. It moved here from
    /// `RouteSampleRelationshipTests`, which owned it while v10 was current.
    @Test("Version 11 is the current version, and it is the one that adds expected pay")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV11.versionIdentifier == Schema.Version(11, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 11)
        #expect(DashPilotMigrationPlan.stages.count == 10)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV11.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == ["Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause"],
            "v11 adds no entity"
        )

        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        let properties = Set(delivery.properties.map(\.name))
        #expect(properties.contains("expectedEarningsAmount"), "The new column is the whole of this version")
        #expect(properties.contains("grossEarningsAmount"), "And it is beside the recorded amount, not instead of it")

        // Two columns, deliberately. One flagged column would have left every
        // existing reader of the recorded amount free to report an expectation
        // as earnings.
        #expect(
            properties == [
                "id", "acceptedAt", "arrivedAtPickupAt", "pickedUpAt", "deliveredAt", "cancelledAt",
                "shift", "pickupPlace", "grossEarningsAmount", "expectedEarningsAmount"
            ]
        )

        // Nothing else moved.
        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(
            Set(shift.properties.map(\.name)) == ["id", "startedAt", "endedAt", "deliveries", "pauses", "grossEarningsAmount"]
        )
    }

    @Test("The frozen version 10 still describes a delivery with one monetary column")
    func versionTenHeldNoExpectedAmount() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV10.self)

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let properties = delivery.properties.map(\.name)

        #expect(properties.contains("grossEarningsAmount"), "v10 recorded what a delivery paid")
        #expect(
            !properties.contains("expectedEarningsAmount"),
            "The frozen v10 model must describe the store as it was, not as it is now"
        )

        // The freeze has to be faithful about everything, not only the column
        // this version adds: v10 is the version where a shift stopped holding
        // its route as a collection.
        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let shiftProperties = Set(shift.properties.map(\.name))
        #expect(!shiftProperties.contains("routeSamples"), "v10 is the version that removed the collection")
        #expect(shiftProperties.contains("pauses"))
        #expect(Set(schema.entities.map(\.name)).contains("ShiftPause"))
    }

    // MARK: Migration

    @Test("A version 10 store reaches version 11 with no delivery gaining an invented expectation")
    func migratesFromVersionTen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let unpaidID = UUID()
        let zeroID = UUID()

        do {
            let v10 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV10.self, at: storeURL)
            let context = ModelContext(v10)
            let shift = DashPilotSchemaV10.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(shift)

            // The delivery that makes the temptation concrete: it holds the
            // recorded amount a migration could copy into the new column.
            context.insert(
                DashPilotSchemaV10.Delivery(
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
                DashPilotSchemaV10.Delivery(
                    id: unpaidID,
                    shift: shift,
                    acceptedAt: at(2_000),
                    arrivedAtPickupAt: at(2_300),
                    pickedUpAt: at(2_600),
                    deliveredAt: at(3_000)
                )
            )
            context.insert(
                DashPilotSchemaV10.Delivery(
                    id: zeroID,
                    shift: shift,
                    acceptedAt: at(4_000),
                    arrivedAtPickupAt: at(4_300),
                    cancelledAt: at(4_600),
                    grossEarningsAmount: .zero
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(stored.count == 3)
        for delivery in stored {
            #expect(
                delivery.expectedEarnings == nil,
                "A pre-v11 store records no expectation, and the migration invents none"
            )
        }

        // And every fact the store already held is exactly what it was.
        let paid = try #require(stored.first { $0.id == paidID })
        #expect(paid.grossEarnings == Money(exact: "14.75"), "The exact decimal, not a floating-point neighbour")
        #expect(paid.state == .delivered)
        #expect(paid.deliveredAt == at(1_800))

        let unpaid = try #require(stored.first { $0.id == unpaidID })
        #expect(unpaid.grossEarnings == nil, "Missing stays missing on both columns")

        let zero = try #require(stored.first { $0.id == zeroID })
        #expect(zero.state == .cancelled)
        #expect(zero.grossEarnings == Money.zero, "A recorded zero is still a figure the driver typed")
        #expect(zero.expectedEarnings == nil, "And it did not become an expected zero")

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.grossEarnings == Money(exact: "86.25"), "The shift's own amount is untouched")
    }

    /// The figures a driver already sees must not move because a column was
    /// added beside them.
    @Test("Nothing a migrated shift reports changes value across the version step")
    func aggregatesSurviveTheVersionStep() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v10 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV10.self, at: storeURL)
            let context = ModelContext(v10)
            let shift = DashPilotSchemaV10.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "100.00")
            )
            context.insert(shift)
            context.insert(
                DashPilotSchemaV10.Delivery(
                    shift: shift,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800),
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )
            context.insert(
                DashPilotSchemaV10.Delivery(
                    shift: shift,
                    acceptedAt: at(2_000),
                    arrivedAtPickupAt: at(2_300),
                    pickedUpAt: at(2_600),
                    deliveredAt: at(3_000)
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
        // One of the two terminal deliveries recorded an amount, which is the
        // coverage this shift has always reported.
        #expect(metrics.recordedDeliveryEarnings == Money(exact: "14.75"))
        #expect(metrics.deliveryEarningsCoverage.contributingCount == 1)
        #expect(metrics.deliveryEarningsCoverage.eligibleCount == 2)

        // Two hours of working time against $100.00, exactly as before.
        #expect(shift.metrics(for: .none).grossPerWorkingHour.amount == Money(exact: "50.00"))
    }

    // MARK: Reopening

    @Test("An expected amount survives a reopen as the exact decimal it was")
    func expectationSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)
            let delivery = try deliveries.startDelivery(at: at(300))
            try deliveries.setExpectedEarnings(try #require(Money(exact: "8.55")), on: delivery)
            try deliveries.markArrivedAtPickup(delivery, at: at(600))
            try deliveries.markPickedUp(delivery, at: at(1_020))
            try deliveries.markDelivered(delivery, at: at(1_800))
            try shifts.endActiveShift(at: at(7_200))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)

        #expect(stored.expectedEarnings == Money(exact: "8.55"))
        #expect(stored.expectedEarnings?.amount == Decimal(string: "8.55"), "No binary floating point anywhere")
        #expect(stored.grossEarnings == nil, "The delivery finished with nothing recorded, and still has nothing")
        #expect(stored.hasUnconfirmedExpectedEarnings)
    }

    @Test("Both amounts reopen independently, and an expected zero is not a missing one")
    func bothColumnsSurviveSeparately() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)

            let both = try deliveries.startDelivery(at: at(300))
            try deliveries.setExpectedEarnings(try #require(Money(exact: "8.50")), on: both)

            let expectedZero = try deliveries.startDelivery(at: at(400))
            try deliveries.setExpectedEarnings(.zero, on: expectedZero)

            let neither = try deliveries.startDelivery(at: at(500))

            for (index, delivery) in [both, expectedZero, neither].enumerated() {
                let base = 1_000 + TimeInterval(index) * 1_000
                try deliveries.markArrivedAtPickup(delivery, at: at(base))
                try deliveries.markPickedUp(delivery, at: at(base + 200))
                try deliveries.markDelivered(delivery, at: at(base + 500))
            }
            try shifts.endActiveShift(at: at(20_000))
            try deliveries.setGrossEarnings(try #require(Money(exact: "6.25")), on: both)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(stored.count == 3)
        #expect(stored[0].expectedEarnings == Money(exact: "8.50"))
        #expect(stored[0].grossEarnings == Money(exact: "6.25"), "Two different amounts, both kept")

        #expect(stored[1].expectedEarnings == Money.zero, "An expected zero is a figure the driver typed")
        #expect(stored[1].grossEarnings == nil)

        #expect(stored[2].expectedEarnings == nil, "And a delivery nobody typed one for has none")
        #expect(stored[2].grossEarnings == nil)
    }

    @Test("An edited expectation survives, and so does a removed one")
    func editsAndRemovalsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)

            let edited = try deliveries.startDelivery(at: at(300))
            try deliveries.setExpectedEarnings(try #require(Money(exact: "8.50")), on: edited)
            try deliveries.setExpectedEarnings(try #require(Money(exact: "11.25")), on: edited)

            let removed = try deliveries.startDelivery(at: at(400))
            try deliveries.setExpectedEarnings(try #require(Money(exact: "20.00")), on: removed)
            try deliveries.clearExpectedEarnings(on: removed)

            for (index, delivery) in [edited, removed].enumerated() {
                let base = 1_000 + TimeInterval(index) * 1_000
                try deliveries.markArrivedAtPickup(delivery, at: at(base))
                try deliveries.markPickedUp(delivery, at: at(base + 200))
                try deliveries.markDelivered(delivery, at: at(base + 500))
            }
            try shifts.endActiveShift(at: at(20_000))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)

        #expect(stored.first?.expectedEarnings == Money(exact: "11.25"), "The edit replaced the amount in the store")
        #expect(stored.last?.expectedEarnings == nil, "The removal is a removal, not a zero")
    }

    @Test("Stacked deliveries reopen with their amounts still on the right records")
    func stackedAmountsStayAttachedAcrossAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var firstID = UUID()
        var secondID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let deliveries = DeliveryService(context: context)
            try shifts.startShift(at: start)

            let first = try deliveries.startDelivery(at: at(300))
            let second = try deliveries.startDelivery(at: at(360))
            firstID = first.id
            secondID = second.id

            try deliveries.setExpectedEarnings(try #require(Money(exact: "8.50")), on: first)
            try deliveries.setExpectedEarnings(try #require(Money(exact: "3.25")), on: second)

            // Interleaved, which is what stacked work looks like.
            try deliveries.markArrivedAtPickup(first, at: at(600))
            try deliveries.markArrivedAtPickup(second, at: at(660))
            try deliveries.markPickedUp(second, at: at(900))
            try deliveries.markPickedUp(first, at: at(960))
            try deliveries.markDelivered(second, at: at(1_500))
            try deliveries.markDelivered(first, at: at(1_800))
            try shifts.endActiveShift(at: at(7_200))
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try context.fetch(FetchDescriptor<Delivery>())

        let first = try #require(stored.first { $0.id == firstID })
        let second = try #require(stored.first { $0.id == secondID })
        #expect(first.expectedEarnings == Money(exact: "8.50"))
        #expect(second.expectedEarnings == Money(exact: "3.25"))
    }
}
