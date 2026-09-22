import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// A shift's route without a collection on the shift.
///
/// Schema v10 removes `Shift.routeSamples` and keeps `RouteSample.shift`. The
/// reason was measured — maintaining the collection cost time proportional to
/// the length of the route on every position written, and the cascade that came
/// with it cost the same on the way out — and ``DashPilotSchemaV10`` records
/// the figures. This suite is about everything that had to stay true while that
/// changed.
///
/// **No timing is asserted here.** A number that depends on the machine does not
/// belong in a correctness test, and the thing a timing assertion would really
/// be guarding is structural: that nothing puts a growing collection back on
/// `Shift`. That is asserted directly, and the cost curve lives in the gated
/// `RouteCaptureWritePerformanceTests`.
@MainActor
@Suite("Route sample relationship")
struct RouteSampleRelationshipTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let session = UUID()

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotRelationshipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    /// `count` positions twenty metres apart, one a second, in one session.
    @discardableResult
    private func record(
        _ count: Int,
        for shift: Shift,
        in context: ModelContext,
        session: UUID,
        from index: Int = 0
    ) throws -> Int {
        for step in index..<(index + count) {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(
                        at: at(Double(step) + 1),
                        northMetres: Double(step + 1) * 20
                    ),
                    captureSessionID: session
                )
            )
        }
        try context.save()
        return index + count
    }

    // MARK: The schema

    /// The one place the migration plan's current shape is asserted, by the
    /// convention the pause suite set: the count lives in the suite for
    /// whichever version is current.
    @Test("Version 10 is current, and it is the version that drops the route collection")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV10.versionIdentifier == Schema.Version(10, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.contains { $0 is DashPilotSchemaV10.Type })

        // The plan's own shape, meaning how many versions and stages it has
        // and which one is current, is asserted in the suite belonging to whichever
        // version is current, so it is updated in one place. It moved to
        // `ExpectedDeliveryEarningsPersistenceTests` when v11 was added.
        let entities = Set(Schema(versionedSchema: DashPilotSchemaV10.self).entities.map(\.name))
        #expect(entities == ["Shift", "RouteSample", "Delivery", "PickupPlace", "Expense", "ShiftPause"])
    }

    /// The structural guard that replaces a timing assertion.
    ///
    /// Every measured cost this version removed came from `Shift` holding a
    /// collection that grew with the route. Putting one back — under any name —
    /// brings the cost back, so the absence is asserted rather than left to be
    /// noticed later on a driver's eight-hour shift.
    @Test("The shift holds no collection that grows with its route")
    func shiftHoldsNoRouteCollection() throws {
        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))

        #expect(
            properties == [
                "id", "startedAt", "endedAt", "deliveries", "offers", "pauses", "grossEarningsAmount",
                "fuelMilesPerGallonValue", "fuelGasPricePerGallonAmount", "fuelVehicleName"
            ]
        )
        #expect(!properties.contains("routeSamples"))

        // The relationship itself is intact, declared from the sample's side.
        let sample = try #require(
            ModelContainerFactory.currentSchema.entities.first { $0.name == "RouteSample" }
        )
        #expect(sample.properties.map(\.name).contains("shift"))
    }

    /// v9 is frozen, and frozen means it still describes the store it wrote.
    @Test("The frozen version 9 still describes a shift that held its route")
    func versionNineStillHoldsTheCollection() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV9.self)
        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))

        #expect(properties.contains("routeSamples"), "The frozen v9 model must describe the store as it was")
        #expect(properties.contains("pauses"), "v9 is the version that had pauses")
    }

    // MARK: Migration

    @Test("A version 9 store reaches version 10 with its whole route intact")
    func migratesFromVersionNine() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()
        let firstSession = UUID()
        let secondSession = UUID()
        let positions = 40

        do {
            let v9 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV9.self, at: storeURL)
            let context = ModelContext(v9)
            let shift = DashPilotSchemaV9.Shift(
                id: shiftID,
                startedAt: start,
                endedAt: at(Double(positions) + 1),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(shift)

            // Two capture sessions, so the gap between them is a fact the
            // migrated store has to keep: a route read as one continuous
            // stretch would measure further than it should.
            for step in 0..<positions {
                let sample = SyntheticRoute.sample(
                    at: at(Double(step) + 1),
                    northMetres: Double(step + 1) * 20
                )
                context.insert(
                    DashPilotSchemaV9.RouteSample(
                        shift: shift,
                        timestamp: sample.timestamp,
                        latitude: sample.latitude,
                        longitude: sample.longitude,
                        horizontalAccuracy: sample.horizontalAccuracy,
                        captureSessionID: step < positions / 2 ? firstSession : secondSession
                    )
                )
            }
            // One sample written before capture sessions existed keeps its
            // unproven continuity through the migration as well.
            let legacy = SyntheticRoute.sample(at: at(Double(positions) + 1), northMetres: Double(positions + 1) * 20)
            context.insert(
                DashPilotSchemaV9.RouteSample(
                    shift: shift,
                    timestamp: legacy.timestamp,
                    latitude: legacy.latitude,
                    longitude: legacy.longitude,
                    horizontalAccuracy: legacy.horizontalAccuracy,
                    captureSessionID: nil
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let route = stored.routeSamples()

        #expect(stored.id == shiftID)
        #expect(stored.grossEarnings == Money(minorUnits: 8625))
        #expect(route.count == positions + 1, "Every stored position survives the version step")
        #expect(route.allSatisfy { $0.shift?.id == shiftID }, "Every position still resolves to its shift")
        #expect(route.map(\.timestamp) == (1...(positions + 1)).map { at(Double($0)) }, "In order")
        #expect(route.filter { $0.captureSessionID == firstSession }.count == positions / 2)
        #expect(route.filter { $0.captureSessionID == secondSession }.count == positions / 2)
        #expect(route.filter { $0.captureSessionID == nil }.count == 1, "A legacy sample's continuity stays unproven")
        #expect(stored.routeSampleCount == positions + 1)
    }

    /// The figure a driver sees must not move because the model shape did.
    ///
    /// The same route is measured through the frozen v9 models and again after
    /// the migration, and the two are compared to each other rather than to a
    /// number written into the test.
    @Test("Recorded mileage is the same figure before and after the version step")
    func mileageSurvivesTheVersionStep() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let capture = UUID()
        let positions = 30
        var measuredUnderV9 = RouteDistance.none

        do {
            let v9 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV9.self, at: storeURL)
            let context = ModelContext(v9)
            let shift = DashPilotSchemaV9.Shift(startedAt: start, endedAt: at(Double(positions) + 1))
            context.insert(shift)
            for step in 0..<positions {
                let sample = SyntheticRoute.sample(at: at(Double(step) + 1), northMetres: Double(step + 1) * 20)
                context.insert(
                    DashPilotSchemaV9.RouteSample(
                        shift: shift,
                        timestamp: sample.timestamp,
                        latitude: sample.latitude,
                        longitude: sample.longitude,
                        horizontalAccuracy: sample.horizontalAccuracy,
                        captureSessionID: capture
                    )
                )
            }
            try context.save()

            // Measured through the v9 collection, by the same calculator the
            // app uses, so the comparison is of the route and not of two
            // different calculations.
            measuredUnderV9 = RouteMileageCalculator().distance(
                of: shift.routeSamples
                    .sorted { $0.timestamp < $1.timestamp }
                    .map {
                        RoutePoint(
                            timestamp: $0.timestamp,
                            latitude: $0.latitude,
                            longitude: $0.longitude,
                            captureSessionID: $0.captureSessionID
                        )
                    },
                covering: shift.startedAt...at(Double(positions) + 1)
            )
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(measuredUnderV9.isMeasured)
        #expect(stored.recordedDistance() == measuredUnderV9)
    }

    // MARK: Writing a long route

    /// Thousands of positions on one shift, written and read back whole.
    ///
    /// This is the case the version exists for. It asserts what the store holds
    /// rather than how long it took: every position present, in order, each one
    /// still pointing at its shift, and the distance the route supports.
    @Test("Thousands of positions on one shift are all written and all read back")
    func writesALongRouteWhole() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let positions = 5_000
        let written = try record(positions, for: shift, in: context, session: session)
        #expect(written == positions)

        let route = shift.routeSamples()
        #expect(route.count == positions)
        #expect(shift.routeSampleCount == positions)
        #expect(route.map(\.timestamp) == (1...positions).map { at(Double($0)) })
        #expect(route.allSatisfy { $0.shift?.id == shift.id })
        #expect(Set(route.map(\.captureSessionID)) == [session])

        // 4,999 legs of 20 m, all in one capture session.
        let distance = shift.recordedDistance()
        #expect(distance.isMeasured)
        #expect(distance.segmentCount == 1)
        #expect(distance.gapCount == 0)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: Double(positions - 1) * 20))
    }

    /// Two shifts recorded in the same store do not see each other's routes.
    @Test("One shift's route is only ever its own")
    func routesDoNotLeakBetweenShifts() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        let second = Shift(startedAt: at(100_000))
        context.insert(first)
        context.insert(second)

        try record(500, for: first, in: context, session: session)
        try record(300, for: second, in: context, session: UUID(), from: 100_000)

        #expect(first.routeSamples().count == 500)
        #expect(second.routeSamples().count == 300)
        #expect(first.routeSamples().allSatisfy { $0.shift?.id == first.id })
        #expect(second.routeSamples().allSatisfy { $0.shift?.id == second.id })
    }

    /// A capture session change is still a gap the measurement refuses to cross.
    @Test("A change of capture session is still a gap")
    func captureSessionChangeIsStillAGap() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let firstSession = UUID()
        let secondSession = UUID()
        let next = try record(20, for: shift, in: context, session: firstSession)
        try record(20, for: shift, in: context, session: secondSession, from: next)
        try shift.end(at: at(41))

        let distance = shift.recordedDistance()
        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount == 1)
        #expect(distance.isPartial)
        // Nineteen legs in each session, and nothing measured across the break.
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 2 * 19 * 20))
    }

    // MARK: Deletion

    @Test("Deleting a completed shift removes every one of its positions")
    func deletionRemovesALongRoute() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let kept = Shift(startedAt: start)
        let removed = Shift(startedAt: at(100_000))
        context.insert(kept)
        context.insert(removed)

        try record(200, for: kept, in: context, session: session)
        try record(3_000, for: removed, in: context, session: UUID(), from: 100_000)
        try removed.end(at: at(150_000))
        try context.save()

        try ShiftService(context: context).deleteCompletedShift(removed)

        // Read through a context the service never touched, so only what the
        // store actually holds is visible.
        let reader = ModelContext(container)
        let remaining = try reader.fetch(FetchDescriptor<RouteSample>())
        #expect(remaining.count == 200, "Only the other shift's route is left")
        #expect(remaining.allSatisfy { $0.shift?.id == kept.id })
        #expect(try reader.fetchCount(FetchDescriptor<Shift>()) == 1)
    }

    /// The transaction property, asserted rather than described: a deletion the
    /// store refuses leaves the shift **and** its whole route.
    ///
    /// The refusal is produced by another writer rolling the shared context
    /// back, which is the reachable way a save in this app fails without a
    /// corrupted store. What matters is the pair of outcomes, not the cause.
    @Test("A rolled back deletion leaves the shift and its whole route")
    func rolledBackDeletionLeavesEverything() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(400, for: shift, in: context, session: session)
        try shift.end(at: at(401))
        try context.save()

        let shiftID = shift.id
        let doomed = try context.fetch(
            FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == shiftID })
        )
        for sample in doomed { context.delete(sample) }
        context.delete(shift)
        context.rollback()

        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Shift>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<RouteSample>()) == 400)

        let restored = try #require(try reader.fetch(FetchDescriptor<Shift>()).first)
        #expect(restored.routeSamples().count == 400)
        #expect(restored.recordedDistance().isMeasured)
    }

    @Test("A running shift is still refused, and keeps its route")
    func refusesToDeleteARunningShift() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let running = Shift(startedAt: start)
        context.insert(running)
        try record(50, for: running, in: context, session: session)

        #expect(throws: ShiftLifecycleError.cannotDeleteActiveShift) {
            try ShiftService(context: context).deleteCompletedShift(running)
        }

        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Shift>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<RouteSample>()) == 50)
    }

    // MARK: What must not have moved

    /// The live measurement reads the store directly and never touched the
    /// collection, so removing it must leave the running shift's figure exactly
    /// where it was: the same figure the finished shift is reported with.
    @Test("A running shift's live mileage still matches measuring the whole route")
    func liveMileageIsUnchanged() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(120, for: shift, in: context, session: session)

        let service = ActiveShiftRouteService(context: context)
        var measurement = try service.measurement(extending: nil, of: shift)
        #expect(measurement.recordedDistance == shift.recordedDistance())

        try record(40, for: shift, in: context, session: session, from: 120)
        measurement = try service.measurement(extending: measurement, of: shift)

        #expect(measurement.consumedRowCount == 160)
        #expect(measurement.recordedDistance == shift.recordedDistance())
    }

    /// Export reads a shift's route through the same measurement every screen
    /// does, and still writes no coordinate.
    @Test("An exported shift carries the same recorded mileage and no coordinate")
    func exportIsUnchanged() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(60, for: shift, in: context, session: session)
        try shift.end(at: at(61))
        try context.save()

        let distance = shift.recordedDistance()
        let record = try shift.exportRecord(for: distance)

        #expect(distance.isMeasured)
        #expect(record.route.recordedDistanceMetres == ExportDistance.metres(of: distance))
        #expect(record.route.recordedDistanceMiles == ExportDistance.miles(of: distance))

        // The route reaches the file as a measurement and its coverage. Whether
        // a coordinate could leak anywhere in an export is `ShiftExportPrivacy`
        // tests' whole subject; what this asserts is that removing the
        // collection did not add a way in.
        let encoded = String(decoding: try JSONEncoder().encode(record.route), as: UTF8.self)
        for sample in shift.routeSamples().prefix(10) {
            #expect(!encoded.contains("\(sample.latitude)"))
            #expect(!encoded.contains("\(sample.longitude)"))
        }
        for key in ["latitude", "longitude", "coordinate", "captureSession"] {
            #expect(!encoded.localizedCaseInsensitiveContains(key))
        }
    }
}
