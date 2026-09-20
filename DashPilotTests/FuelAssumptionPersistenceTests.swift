import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The fuel assumptions in the store: the v14 schema, the step up from a real
/// v13 store, and what survives a store being closed and reopened.
///
/// The claim the migration has to prove is that **nothing was invented**. A v13
/// store holds no fuel economy and no gas price, because no build that wrote one
/// could estimate fuel, so every migrated shift comes out recording neither,
/// reporting no estimate rather than an estimate of nothing, and reporting
/// exactly the mileage, durations and rates a v13 build reported for it.
///
/// Backfilling would have been the failure. Copying whatever fuel economy the
/// driver types first into their whole history would put an assumption they
/// never made behind every shift they have ever worked, and would be the dynamic
/// dependence on a current global figure this version exists to prevent.
///
/// Every timestamp, amount and coordinate is invented.
@MainActor
@Suite("Fuel assumption persistence")
struct FuelAssumptionPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotFuelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v14 is the current version.
    ///
    /// The repository's convention is that the count of versions and stages
    /// lives in the suite belonging to whichever version is current, so it is
    /// updated in one place rather than in several. It moved here from
    /// `DeliveryTipPersistenceTests`, which owned it while v13 was current.
    @Test("Version 14 is the current version, and it is the one that adds the assumptions")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV14.versionIdentifier == Schema.Version(14, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 14)
        #expect(DashPilotMigrationPlan.stages.count == 13)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV14.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause", "Offer",
                "DeliveryTip"
            ],
            "v14 adds no entity: it adds two columns to one that already exists"
        )

        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(
            Set(shift.properties.map(\.name)) == [
                "id", "startedAt", "endedAt", "deliveries", "offers", "pauses", "grossEarningsAmount",
                "fuelMilesPerGallonValue", "fuelGasPricePerGallonAmount"
            ],
            "The shift gains exactly two columns, and keeps everything it had"
        )
    }

    @Test("The frozen version 13 still describes a shift that can record no fuel assumption")
    func versionThirteenHeldNoAssumptions() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV13.self)

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))

        #expect(
            !properties.contains("fuelMilesPerGallonValue"),
            "The frozen v13 model must describe the store as it was, not as it is now"
        )
        #expect(!properties.contains("fuelGasPricePerGallonAmount"))
        #expect(properties.contains("grossEarningsAmount"))
        #expect(properties.contains("offers"), "v12 is the version that added the offer, and v13 kept it")

        #expect(
            Set(schema.entities.map(\.name)).contains("DeliveryTip"),
            "v13 is the version that added the tip, and the frozen copy has to hold it"
        )
    }

    @Test("The step from version 13 is lightweight, because there is nothing truthful to write")
    func theStepIsLightweight() {
        // A `willMigrate`/`didMigrate` pair that walks a driver's whole history
        // for no reason is a way to lose it. The offer stage had to write,
        // because a delivery holding no offer was a row the app could not
        // produce; a shift recording no fuel assumption is the ordinary shape in
        // this build too.
        #expect(DashPilotMigrationPlan.stages.count == DashPilotMigrationPlan.schemas.count - 1)
    }

    // MARK: Migration

    @Test("Every version 13 shift reaches version 14 recording no assumption, and no estimate is invented")
    func migratesFromVersionThirteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidID = UUID()
        let unpaidID = UUID()

        do {
            let v13 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV13.self, at: storeURL)
            let context = ModelContext(v13)

            let paid = DashPilotSchemaV13.Shift(
                id: paidID,
                startedAt: start,
                endedAt: at(7_200),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)

            // A route in one continuous capture session, so the migrated shift
            // has a measured distance to be estimated over — or rather, not to
            // be estimated over, since it records no assumption.
            let session = UUID()
            for step in 0..<10 {
                context.insert(
                    DashPilotSchemaV13.RouteSample(
                        shift: paid,
                        timestamp: at(600 + Double(step) * 20),
                        latitude: SyntheticRoute.originLatitude + Double(step) * 400 / SyntheticRoute.metresPerDegreeLatitude,
                        longitude: SyntheticRoute.originLongitude,
                        horizontalAccuracy: 8,
                        captureSessionID: session
                    )
                )
            }

            let offer = DashPilotSchemaV13.Offer(shift: paid, acceptedAt: at(900))
            context.insert(offer)
            let delivery = DashPilotSchemaV13.Delivery(
                shift: paid,
                offer: offer,
                acceptedAt: at(900),
                arrivedAtPickupAt: at(1_200),
                pickedUpAt: at(1_500),
                deliveredAt: at(2_400),
                grossEarningsAmount: Decimal(string: "14.75")
            )
            context.insert(delivery)
            context.insert(
                DashPilotSchemaV13.DeliveryTip(
                    delivery: delivery,
                    amountValue: Decimal(string: "5.00") ?? .zero,
                    methodRawValue: "cash",
                    recordedAt: at(2_500)
                )
            )

            // A shift with no amount at all, so the absence that is not a zero
            // is checked on both sides of the step.
            context.insert(DashPilotSchemaV13.Shift(id: unpaidID, startedAt: at(86_400), endedAt: at(93_600)))

            context.insert(
                DashPilotSchemaV13.Expense(
                    occurredAt: at(3_000),
                    amountValue: Decimal(string: "42.10") ?? .zero,
                    categoryRawValue: "fuel",
                    note: nil
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>())
        #expect(shifts.count == 2)

        for shift in shifts {
            #expect(shift.fuelAssumptions == .none, "Nothing was fabricated")
            #expect(
                shift.fuelEstimate(for: shift.recordedDistance()) == .unavailable(.milesPerGallonNotRecorded),
                "A shift recorded before fuel estimation existed has no estimate, not an estimate of nothing"
            )
        }

        // Everything a v13 build reported for the paid shift is the figure it
        // still reports.
        let paid = try #require(shifts.first { $0.id == paidID })
        #expect(paid.grossEarnings == Money(exact: "86.25"))
        #expect(paid.completedDuration == 7_200)
        let distance = paid.recordedDistance()
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 3_600), "The route measures what it always did")
        #expect(distance.segmentCount == 1)
        // Kept at the calculation's own scale, as it always was: $86.25 over
        // two hours, rounded once when it reaches a screen.
        #expect(paid.metrics(for: distance).grossPerWorkingHour.amount?.amount == Decimal(string: "43.125"))

        let delivery = try #require(paid.deliveriesInOrder.first)
        #expect(delivery.grossEarnings == Money(exact: "14.75"), "The platform amount is untouched")
        #expect(delivery.effectiveEarnings.amount == Money(exact: "19.75"), "And so is the tip beside it")

        let unpaid = try #require(shifts.first { $0.id == unpaidID })
        #expect(unpaid.grossEarnings == nil, "Missing stays missing")

        // The one row whose meaning this version sits closest to, and it did not
        // move either.
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.category == .fuel)
        #expect(expenses.first?.amount == Money(exact: "42.10"), "A recorded fuel purchase is not an estimate")
    }

    @Test("A store stepped up from version 12 arrives holding no assumption either")
    func migratesFromVersionTwelve() throws {
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

            let offer = DashPilotSchemaV12.Offer(shift: shift, acceptedAt: at(300))
            context.insert(offer)
            context.insert(
                DashPilotSchemaV12.Delivery(
                    shift: shift,
                    offer: offer,
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(900),
                    deliveredAt: at(1_800),
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )
            try context.save()
        }

        // Two stages in one open, which is the path a device that skipped a
        // build actually takes.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.fuelAssumptions == .none)
        #expect(shift.grossEarnings == Money(exact: "100.00"))
        #expect(shift.deliveriesInOrder.count == 1)
        #expect(shift.deliveriesInOrder.first?.additionalTips.isEmpty == true, "And the tip stage invented nothing")
    }

    // MARK: Round trip

    @Test("A recorded pair survives closing and reopening the store")
    func assumptionsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(id: shiftID, startedAt: start)
            context.insert(shift)
            try shift.end(at: at(7_200))
            try ShiftService(context: context).setFuelAssumptions(
                milesPerGallon: Decimal(string: "28.5"),
                gasPricePerGallon: Money(minorUnits: 329),
                on: shift
            )
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.fuelAssumptions.milesPerGallon == Decimal(string: "28.5"))
        #expect(
            stored.fuelAssumptions.gasPricePerGallon?.amount == Decimal(string: "3.29"),
            "The exact decimal survives, with no binary floating point in the store"
        )
    }

    @Test("A recorded gas price of zero survives as a zero, not as an absence")
    func zeroPriceSurvivesAsAFigure() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(startedAt: start)
            context.insert(shift)
            try shift.end(at: at(7_200))
            try ShiftService(context: context).setFuelAssumptions(
                milesPerGallon: Decimal(25),
                gasPricePerGallon: .zero,
                on: shift
            )
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(stored.fuelAssumptions.gasPricePerGallon == Money.zero)
        #expect(stored.fuelAssumptions.gasPricePerGallon != nil)
    }
}
