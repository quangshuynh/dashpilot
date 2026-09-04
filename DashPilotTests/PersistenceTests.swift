import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ModelContext(container)
    }

    @Test("The current schema is version 1.0.0 and contains the shift model")
    func schemaVersion() {
        #expect(DashPilotSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 1)
        #expect(ModelContainerFactory.currentSchema.entities.contains { $0.name == "Shift" })
    }

    @Test("A saved shift is read back with its timestamps intact")
    func roundTripsAShift() throws {
        let context = try makeContext()
        let id = UUID()
        let shift = Shift(id: id, startedAt: start)
        try shift.end(at: start.addingTimeInterval(7200))
        context.insert(shift)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Shift>())

        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.id == id)
        #expect(stored.startedAt == start)
        #expect(stored.completedDuration == 7200)
        #expect(!stored.isActive)
    }

    @Test("A running shift persists without an end timestamp")
    func persistsRunningShift() throws {
        let context = try makeContext()
        context.insert(Shift(startedAt: start))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Shift>())
        let stored = try #require(fetched.first)

        #expect(stored.isActive)
        #expect(stored.endedAt == nil)
    }

    @Test("Shifts can be fetched newest first")
    func sortsByStartDescending() throws {
        let context = try makeContext()
        let older = Shift(startedAt: start)
        let newer = Shift(startedAt: start.addingTimeInterval(86_400))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.startedAt) == [newer.startedAt, older.startedAt])
    }

    @Test("Only active shifts are returned by an active-shift predicate")
    func fetchesActiveShiftsOnly() throws {
        let context = try makeContext()
        let finished = Shift(startedAt: start)
        try finished.end(at: start.addingTimeInterval(3600))
        let running = Shift(startedAt: start.addingTimeInterval(7200))
        context.insert(finished)
        context.insert(running)
        try context.save()

        let descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.endedAt == nil })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == running.id)
    }

    @Test("Deleting a shift removes it from the store")
    func deletesAShift() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try context.save()

        context.delete(shift)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Shift>()).isEmpty)
    }

    @Test("Separate in-memory containers do not share data")
    func inMemoryContainersAreIsolated() throws {
        let first = try makeContext()
        first.insert(Shift(startedAt: start))
        try first.save()

        let second = try makeContext()

        #expect(try second.fetch(FetchDescriptor<Shift>()).isEmpty)
    }
}
