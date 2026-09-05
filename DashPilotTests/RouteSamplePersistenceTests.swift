import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Route sample persistence")
struct RouteSamplePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// One capture session for tests that only need samples to exist.
    private let session = UUID()

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: Schema

    @Test("The schema versions are ordered, and the current one holds both entities")
    func schemaVersion() {
        // The current version and what it added are covered by
        // `ShiftEarningsPersistenceTests`.
        #expect(DashPilotSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(DashPilotSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(DashPilotSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities.contains("Shift"))
        #expect(entities.contains("RouteSample"))
    }

    @Test("Version 1 described shifts only")
    func versionOneHeldShiftsOnly() {
        let entities = Schema(versionedSchema: DashPilotSchemaV1.self).entities.map(\.name)
        #expect(entities == ["Shift"])
    }

    @Test("Version 2 route samples had no capture session")
    func versionTwoHeldNoCaptureSession() throws {
        let routeSample = try #require(
            Schema(versionedSchema: DashPilotSchemaV2.self).entities.first { $0.name == "RouteSample" }
        )
        let properties = routeSample.properties.map(\.name)

        #expect(properties.contains("timestamp"))
        #expect(properties.contains("horizontalAccuracy"))
        #expect(
            !properties.contains("captureSessionID"),
            "The frozen v2 model must describe the store as it was, not as it is now"
        )
    }

    // MARK: Round trip

    @Test("A route sample is read back with its position, accuracy and capture session intact")
    func roundTripsARouteSample() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let sample = SyntheticRoute.sample(at: start.addingTimeInterval(30), northMetres: 250, horizontalAccuracy: 12)
        context.insert(RouteSample(shift: shift, sample: sample, captureSessionID: session))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<RouteSample>()).first)

        #expect(stored.timestamp == sample.timestamp)
        #expect(stored.latitude == sample.latitude)
        #expect(stored.longitude == sample.longitude)
        #expect(stored.horizontalAccuracy == 12)
        #expect(stored.captureSessionID == session)
        #expect(stored.locationSample == sample)
        #expect(stored.routePoint.captureSessionID == session)
    }

    // MARK: Relationship

    @Test("A sample belongs to exactly one shift, reachable from both sides")
    func relatesToItsShift() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        let second = Shift(startedAt: start.addingTimeInterval(7200))
        context.insert(first)
        context.insert(second)
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10)), captureSessionID: session))
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(20), northMetres: 100), captureSessionID: session))
        context.insert(RouteSample(shift: second, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210)), captureSessionID: session))
        try context.save()

        #expect(first.routeSamples.count == 2)
        #expect(second.routeSamples.count == 1)
        #expect(first.routeSamples.allSatisfy { $0.shift?.id == first.id })
        #expect(second.routeSamples.first?.shift?.id == second.id)
    }

    @Test("Samples can be fetched for one shift without loading the others")
    func fetchesSamplesForOneShift() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        let second = Shift(startedAt: start.addingTimeInterval(7200))
        context.insert(first)
        context.insert(second)
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10)), captureSessionID: session))
        context.insert(RouteSample(shift: second, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210)), captureSessionID: session))
        try context.save()

        let firstID = first.id
        let fetched = try context.fetch(
            FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == firstID })
        )

        #expect(fetched.count == 1)
        #expect(fetched.first?.timestamp == start.addingTimeInterval(10))
    }

    @Test("Deleting a shift deletes its route rather than orphaning it")
    func deletingAShiftCascadesToItsSamples() throws {
        let context = try makeContext()
        let kept = Shift(startedAt: start)
        let removed = Shift(startedAt: start.addingTimeInterval(7200))
        context.insert(kept)
        context.insert(removed)
        context.insert(RouteSample(shift: kept, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10)), captureSessionID: session))
        context.insert(RouteSample(shift: removed, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210)), captureSessionID: session))
        context.insert(RouteSample(shift: removed, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7220), northMetres: 80), captureSessionID: session))
        try context.save()

        context.delete(removed)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<RouteSample>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.shift?.id == kept.id)
        // No coordinate is left behind belonging to a shift that no longer exists.
        #expect(remaining.allSatisfy { $0.shift != nil })
    }

    // MARK: Migration

    @Test("A version 1 store opens under version 2 with its shifts intact")
    func migratesAVersionOneStore() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        let completedID = UUID()
        let runningID = UUID()

        // A store exactly as a build without route capture would have left it.
        do {
            let v1 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
            let context = ModelContext(v1)
            context.insert(
                DashPilotSchemaV1.Shift(
                    id: completedID,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(3600)
                )
            )
            context.insert(DashPilotSchemaV1.Shift(id: runningID, startedAt: start.addingTimeInterval(7200)))
            try context.save()
        }

        let migrated = try ModelContainerFactory.makeContainer(at: storeURL)
        let context = ModelContext(migrated)
        let shifts = try context.fetch(
            FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)])
        )

        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [completedID, runningID])
        #expect(shifts.first?.startedAt == start)
        #expect(shifts.first?.endedAt == start.addingTimeInterval(3600))
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        // The new relationship starts empty: a shift recorded before route
        // capture existed genuinely has no route.
        #expect(shifts.allSatisfy { $0.routeSamples.isEmpty })
        #expect(try context.fetch(FetchDescriptor<RouteSample>()).isEmpty)
    }

    @Test("A migrated shift can record a route and be ended normally")
    func aMigratedShiftStillWorks() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        let runningID = UUID()
        do {
            let v1 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
            let context = ModelContext(v1)
            context.insert(DashPilotSchemaV1.Shift(id: runningID, startedAt: start))
            try context.save()
        }

        let migrated = try ModelContainerFactory.makeContainer(at: storeURL)
        let context = ModelContext(migrated)
        let service = ShiftService(context: context)
        let running = try #require(try service.activeShift())

        #expect(running.id == runningID, "The shift resumes rather than being replaced")

        context.insert(
            RouteSample(shift: running, sample: SyntheticRoute.sample(at: start.addingTimeInterval(30)), captureSessionID: session)
        )
        try context.save()
        try service.endActiveShift(at: start.addingTimeInterval(3600))

        #expect(running.routeSamples.count == 1)
        #expect(running.completedDuration == 3600)
    }

    @Test("A version 2 store opens under version 3 with its shifts and route intact")
    func migratesAVersionTwoStore() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        let completedID = UUID()
        let runningID = UUID()

        // A store exactly as a build without capture continuity would have left
        // it: shifts, and a route with no session on any sample.
        do {
            let v2 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV2.self, at: storeURL)
            let context = ModelContext(v2)
            let completed = DashPilotSchemaV2.Shift(
                id: completedID,
                startedAt: start,
                endedAt: start.addingTimeInterval(3600)
            )
            context.insert(completed)
            context.insert(DashPilotSchemaV2.Shift(id: runningID, startedAt: start.addingTimeInterval(7200)))
            for step in 0..<4 {
                let position = SyntheticRoute.sample(
                    at: start.addingTimeInterval(TimeInterval(step) * 10),
                    northMetres: Double(step) * 100
                )
                context.insert(
                    DashPilotSchemaV2.RouteSample(
                        shift: completed,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy
                    )
                )
            }
            try context.save()
        }

        let migrated = try ModelContainerFactory.makeContainer(at: storeURL)
        let context = ModelContext(migrated)
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        let samples = try context.fetch(FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [completedID, runningID])
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        #expect(samples.count == 4, "Migration must not drop stored positions")
        #expect(samples.first?.latitude == SyntheticRoute.originLatitude)
        #expect(
            samples.allSatisfy { $0.captureSessionID == nil },
            "Nothing may invent continuity a v2 store never recorded"
        )
        #expect(samples.allSatisfy { $0.shift?.id == completedID })
    }

    @Test("A migrated version 2 route is measured, and reported as inferred")
    func measuresAMigratedRoute() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        do {
            let v2 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV2.self, at: storeURL)
            let context = ModelContext(v2)
            let shift = DashPilotSchemaV2.Shift(startedAt: start, endedAt: start.addingTimeInterval(60))
            context.insert(shift)
            for step in 0..<4 {
                let position = SyntheticRoute.sample(
                    at: start.addingTimeInterval(TimeInterval(step) * 10),
                    northMetres: Double(step) * 100
                )
                context.insert(
                    DashPilotSchemaV2.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let distance = shift.recordedDistance()

        #expect(distance.isMeasured)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 300), "measured \(distance.metres) m")
        #expect(distance.usesInferredContinuity, "A legacy route cannot prove it has no gaps")
        #expect(distance.isPartial)
    }

    // MARK: Derived mileage

    @Test("A completed shift measures only its own route, not the next shift's")
    func measuresOneShiftAtATime() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        try first.end(at: start.addingTimeInterval(60))
        let second = Shift(startedAt: start.addingTimeInterval(7200))
        try second.end(at: start.addingTimeInterval(7260))
        context.insert(first)
        context.insert(second)

        let firstSession = UUID()
        let secondSession = UUID()
        for step in 0..<4 {
            context.insert(
                RouteSample(
                    shift: first,
                    sample: SyntheticRoute.sample(
                        at: start.addingTimeInterval(TimeInterval(step) * 10),
                        northMetres: Double(step) * 100
                    ),
                    captureSessionID: firstSession
                )
            )
            context.insert(
                RouteSample(
                    shift: second,
                    sample: SyntheticRoute.sample(
                        at: start.addingTimeInterval(7200 + TimeInterval(step) * 10),
                        northMetres: 50_000 + Double(step) * 250
                    ),
                    captureSessionID: secondSession
                )
            )
        }
        try context.save()

        #expect(SyntheticRoute.isCloseEnough(first.recordedDistance().metres, to: 300))
        #expect(SyntheticRoute.isCloseEnough(second.recordedDistance().metres, to: 750))
    }

    @Test("A shift measures the same distance after the store is closed and reopened")
    func measuresTheSameDistanceAfterAReopen() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotMileageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        let shiftID = UUID()
        let firstSession = UUID()
        let secondSession = UUID()
        let before: RouteDistance

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(id: shiftID, startedAt: start)
            context.insert(shift)
            // Two captured stretches with a backgrounded hour between them.
            for step in 0..<4 {
                context.insert(
                    RouteSample(
                        shift: shift,
                        sample: SyntheticRoute.sample(
                            at: start.addingTimeInterval(TimeInterval(step) * 10),
                            northMetres: Double(step) * 100
                        ),
                        captureSessionID: firstSession
                    )
                )
                context.insert(
                    RouteSample(
                        shift: shift,
                        sample: SyntheticRoute.sample(
                            at: start.addingTimeInterval(3_600 + TimeInterval(step) * 10),
                            northMetres: 20_000 + Double(step) * 100
                        ),
                        captureSessionID: secondSession
                    )
                )
            }
            try shift.end(at: start.addingTimeInterval(3_640))
            try context.save()
            before = shift.recordedDistance()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let reopened = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(reopened.id == shiftID)
        #expect(reopened.recordedDistance() == before)
        #expect(SyntheticRoute.isCloseEnough(before.metres, to: 600), "measured \(before.metres) m")
        #expect(before.segmentCount == 2)
        #expect(before.gapCount == 1, "The backgrounded hour is a gap, not twenty kilometres of driving")
    }
}
