import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The tip entity in the store: the v13 schema, the step up from a real v12
/// store, and what survives a store being closed and reopened.
///
/// The claim the migration has to prove is that **nothing was invented**. A v12
/// store cannot say which of a driver's recorded amounts already had a tip
/// folded into it, so every migrated delivery comes out holding no tip, keeping
/// the amount it was recorded with, and reporting exactly the figures a v12
/// build reported for it.
///
/// Every timestamp and amount is invented.
@MainActor
@Suite("Delivery tip persistence")
struct DeliveryTipPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotTipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v13 is the current version.
    ///
    /// The repository's convention is that the count of versions and stages
    /// lives in the suite belonging to whichever version is current, so it is
    /// updated in one place rather than in several. It moved here from
    /// `DeliveryOfferPersistenceTests`, which owned it while v12 was current.
    @Test("Version 13 is the current version, and it is the one that adds the tip")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV13.versionIdentifier == Schema.Version(13, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 13)
        #expect(DashPilotMigrationPlan.stages.count == 12)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV13.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause", "Offer",
                "DeliveryTip"
            ],
            "v13 adds exactly one entity"
        )

        let tip = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "DeliveryTip" })
        #expect(
            Set(tip.properties.map(\.name)) == ["id", "amountValue", "methodRawValue", "recordedAt", "delivery"],
            "A tip holds an amount, a method, when it was recorded and which delivery it belongs to, and nothing else"
        )

        // The delivery gains the collection and keeps everything it had,
        // including the amount that still means the platform's own figure.
        let delivery = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Delivery" })
        #expect(
            Set(delivery.properties.map(\.name)) == [
                "id", "acceptedAt", "arrivedAtPickupAt", "pickedUpAt", "deliveredAt", "cancelledAt",
                "shift", "offer", "pickupPlace", "grossEarningsAmount", "expectedEarningsAmount",
                "additionalTips"
            ]
        )
    }

    @Test("The frozen version 12 still describes a delivery that can hold no tip")
    func versionTwelveHeldNoTip() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV12.self)

        #expect(
            !Set(schema.entities.map(\.name)).contains("DeliveryTip"),
            "The frozen v12 model must describe the store as it was, not as it is now"
        )

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        let properties = Set(delivery.properties.map(\.name))
        #expect(!properties.contains("additionalTips"))
        #expect(properties.contains("offer"), "v12 is the version that added the offer")
        #expect(properties.contains("grossEarningsAmount"))
        #expect(properties.contains("expectedEarningsAmount"))
    }

    @Test("The step from version 12 is lightweight, because there is nothing to derive")
    func theStepIsLightweight() {
        // A `willMigrate`/`didMigrate` pair that walks a driver's whole history
        // for no reason is a way to lose it. The offer stage had to write; this
        // one has nothing truthful to write.
        #expect(DashPilotMigrationPlan.stages.count == DashPilotMigrationPlan.schemas.count - 1)
    }

    // MARK: Migration

    @Test("Every version 12 delivery reaches version 13 holding no tip and the amount it was recorded with")
    func migratesFromVersionTwelve() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let unpaidID = UUID()
        let cancelledID = UUID()

        do {
            let v12 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV12.self, at: storeURL)
            let context = ModelContext(v12)

            let shift = DashPilotSchemaV12.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(shift)

            let offer = DashPilotSchemaV12.Offer(shift: shift, acceptedAt: at(300))
            context.insert(offer)
            context.insert(
                DashPilotSchemaV12.Delivery(
                    id: paidID,
                    shift: shift,
                    offer: offer,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(1_020),
                    deliveredAt: at(1_800),
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )

            let secondOffer = DashPilotSchemaV12.Offer(shift: shift, acceptedAt: at(2_400))
            context.insert(secondOffer)
            context.insert(
                DashPilotSchemaV12.Delivery(
                    id: unpaidID,
                    shift: shift,
                    offer: secondOffer,
                    acceptedAt: at(2_400),
                    arrivedAtPickupAt: at(2_700),
                    pickedUpAt: at(3_000),
                    deliveredAt: at(3_600),
                    expectedEarningsAmount: Decimal(string: "8.50")
                )
            )

            let thirdOffer = DashPilotSchemaV12.Offer(shift: shift, acceptedAt: at(4_000))
            context.insert(thirdOffer)
            context.insert(
                DashPilotSchemaV12.Delivery(
                    id: cancelledID,
                    shift: shift,
                    offer: thirdOffer,
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
        #expect(try context.fetch(FetchDescriptor<DeliveryTip>()).isEmpty, "Nothing was fabricated")

        for delivery in stored {
            #expect(delivery.additionalTips.isEmpty)
            #expect(
                delivery.effectiveEarnings.additionalTipsTotal == nil,
                "No tip recorded is not a tip of nothing, at any level"
            )
        }

        // Every amount is the exact decimal it was, and every effective figure
        // is the amount a v12 build reported.
        let paid = try #require(stored.first { $0.id == paidID })
        #expect(paid.grossEarnings == Money(exact: "14.75"))
        #expect(paid.effectiveEarnings.amount == Money(exact: "14.75"), "Which is exactly what v12 reported")
        #expect(paid.offer?.deliveryCount == 1, "The offer the previous version gave it is untouched")

        let unpaid = try #require(stored.first { $0.id == unpaidID })
        #expect(unpaid.grossEarnings == nil, "Missing stays missing")
        #expect(unpaid.effectiveEarnings.amount == nil)
        #expect(unpaid.expectedEarnings == Money(exact: "8.50"), "And an expectation is still not earnings")

        let cancelled = try #require(stored.first { $0.id == cancelledID })
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.grossEarnings == Money.zero, "A recorded zero is still a figure the driver typed")
        #expect(cancelled.effectiveEarnings.amount == Money.zero)

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.grossEarnings == Money(exact: "86.25"), "The shift's own amount is untouched")
    }

    @Test("Nothing a migrated shift reports changes value across the version step")
    func aggregatesSurviveTheVersionStep() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v12 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV12.self, at: storeURL)
            let context = ModelContext(v12)
            let shift = DashPilotSchemaV12.Shift(
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "100.00")
            )
            context.insert(shift)

            for (offset, amount) in [(300.0, "14.75"), (2_400.0, "9.25")] {
                let offer = DashPilotSchemaV12.Offer(shift: shift, acceptedAt: at(offset))
                context.insert(offer)
                context.insert(
                    DashPilotSchemaV12.Delivery(
                        shift: shift,
                        offer: offer,
                        acceptedAt: at(offset),
                        arrivedAtPickupAt: at(offset + 300),
                        pickedUpAt: at(offset + 600),
                        deliveredAt: at(offset + 1_800),
                        grossEarningsAmount: Decimal(string: amount)
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let record = shift.periodRecord(for: .none)

        #expect(
            record.recordedDeliveryEarnings == [Money(exact: "14.75")!, Money(exact: "9.25")!],
            "The subtotal reads effective earnings now, and with no tips that is the same list"
        )
        #expect(record.terminalDeliveryCount == 2)
        #expect(record.grossEarnings == Money(exact: "100.00"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [record], in: period)
        #expect(metrics.recordedDeliveryEarnings == Money(exact: "24.00"))
        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
    }

    // MARK: Reopening the store

    @Test("Tips survive the store being closed and reopened, with their methods and moments")
    func tipsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(startedAt: start)
            context.insert(shift)
            let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
            context.insert(recorded.offer)
            let delivery = recorded.deliveries[0]
            context.insert(delivery)
            try delivery.markArrivedAtPickup(at: at(600))
            try delivery.markPickedUp(at: at(1_020))
            try delivery.markDelivered(at: at(1_800))
            try shift.end(at: at(7_200))
            try delivery.setGrossEarnings(Money(exact: "10.00")!)

            let service = DeliveryService(context: context)
            try service.addAdditionalTip(Money(exact: "3.00")!, method: .cash, on: delivery, at: at(1_900))
            try service.addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(5_400))

            #expect(delivery.additionalTips.count == 2)
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        let tips = delivery.additionalTipsInOrder

        #expect(tips.count == 2)
        #expect(tips.map(\.amount) == [Money(exact: "3.00"), Money(exact: "5.00")])
        #expect(tips.map(\.method) == [.cash, .platform])
        #expect(tips.map(\.recordedAt) == [at(1_900), at(5_400)])
        #expect(delivery.grossEarnings == Money(exact: "10.00"), "The platform amount is exactly what was typed")
        #expect(delivery.effectiveEarnings.amount == Money(exact: "18.00"))
    }
}
