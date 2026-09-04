import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Route sample persistence")
struct RouteSamplePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: Schema

    @Test("The current schema is version 2.0.0 and holds both entities")
    func schemaVersion() {
        #expect(DashPilotSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(DashPilotSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 2)
        #expect(DashPilotMigrationPlan.stages.count == 1)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities.contains("Shift"))
        #expect(entities.contains("RouteSample"))
    }

    @Test("Version 1 described shifts only")
    func versionOneHeldShiftsOnly() {
        let entities = Schema(versionedSchema: DashPilotSchemaV1.self).entities.map(\.name)
        #expect(entities == ["Shift"])
    }

    // MARK: Round trip

    @Test("A route sample is read back with its position and accuracy intact")
    func roundTripsARouteSample() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let sample = SyntheticRoute.sample(at: start.addingTimeInterval(30), northMetres: 250, horizontalAccuracy: 12)
        context.insert(RouteSample(shift: shift, sample: sample))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<RouteSample>()).first)

        #expect(stored.timestamp == sample.timestamp)
        #expect(stored.latitude == sample.latitude)
        #expect(stored.longitude == sample.longitude)
        #expect(stored.horizontalAccuracy == 12)
        #expect(stored.locationSample == sample)
    }

    // MARK: Relationship

    @Test("A sample belongs to exactly one shift, reachable from both sides")
    func relatesToItsShift() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        let second = Shift(startedAt: start.addingTimeInterval(7200))
        context.insert(first)
        context.insert(second)
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10))))
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(20), northMetres: 100)))
        context.insert(RouteSample(shift: second, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210))))
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
        context.insert(RouteSample(shift: first, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10))))
        context.insert(RouteSample(shift: second, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210))))
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
        context.insert(RouteSample(shift: kept, sample: SyntheticRoute.sample(at: start.addingTimeInterval(10))))
        context.insert(RouteSample(shift: removed, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7210))))
        context.insert(RouteSample(shift: removed, sample: SyntheticRoute.sample(at: start.addingTimeInterval(7220), northMetres: 80)))
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
            RouteSample(shift: running, sample: SyntheticRoute.sample(at: start.addingTimeInterval(30)))
        )
        try context.save()
        try service.endActiveShift(at: start.addingTimeInterval(3600))

        #expect(running.routeSamples.count == 1)
        #expect(running.completedDuration == 3600)
    }
}
