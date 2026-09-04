import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Shift service")
struct ShiftServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    /// A service over its own context, as if the app had just built one.
    private func makeService(for container: ModelContainer) -> ShiftService {
        ShiftService(context: ModelContext(container))
    }

    /// Reads the store through a context the service under test never touched.
    private func storedShifts(in container: ModelContainer) throws -> [Shift] {
        try ModelContext(container).fetch(
            FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)])
        )
    }

    // MARK: Starting

    @Test("Starting with no shift running records one and persists its start time")
    func startsAShift() throws {
        let container = try makeContainer()
        let service = makeService(for: container)

        let shift = try service.startShift(at: start)

        #expect(shift.startedAt == start)
        #expect(shift.isActive)

        let stored = try storedShifts(in: container)
        #expect(stored.count == 1)
        #expect(stored.first?.startedAt == start)
        #expect(stored.first?.endedAt == nil)
    }

    @Test("A second start is refused while a shift is running")
    func refusesASecondShift() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        #expect(throws: ShiftLifecycleError.shiftAlreadyActive(startedAt: start)) {
            try service.startShift(at: start.addingTimeInterval(600))
        }

        // The refusal must leave the store exactly as it was.
        let stored = try storedShifts(in: container)
        #expect(stored.count == 1)
        #expect(stored.first?.startedAt == start)
    }

    @Test("The invariant is enforced against the store, not against one service instance")
    func refusesASecondShiftFromAnotherService() throws {
        let container = try makeContainer()
        try makeService(for: container).startShift(at: start)

        let other = makeService(for: container)
        #expect(throws: ShiftLifecycleError.shiftAlreadyActive(startedAt: start)) {
            try other.startShift(at: start.addingTimeInterval(60))
        }
    }

    // MARK: Ending

    @Test("Ending an active shift persists its end time")
    func endsTheActiveShift() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        let ended = try service.endActiveShift(at: start.addingTimeInterval(3600))

        #expect(ended.endedAt == start.addingTimeInterval(3600))
        #expect(ended.completedDuration == 3600)

        let stored = try storedShifts(in: container)
        #expect(stored.count == 1)
        #expect(stored.first?.endedAt == start.addingTimeInterval(3600))
        #expect(stored.first?.isActive == false)
    }

    @Test("Ending with nothing running is refused")
    func refusesToEndWithoutAnActiveShift() throws {
        let service = makeService(for: try makeContainer())

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try service.endActiveShift(at: start)
        }
    }

    @Test("A shift cannot be ended twice")
    func refusesToEndTwice() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.endActiveShift(at: start.addingTimeInterval(1800))

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try service.endActiveShift(at: start.addingTimeInterval(3600))
        }

        // The first end time stands.
        #expect(try storedShifts(in: container).first?.endedAt == start.addingTimeInterval(1800))
    }

    @Test("A backwards device clock ends the shift at its start rather than trapping it open")
    func clampsAnEndThatPrecedesTheStart() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        let ended = try service.endActiveShift(at: start.addingTimeInterval(-600))

        #expect(ended.endedAt == start)
        #expect(ended.completedDuration == 0)
        #expect(try service.activeShift() == nil)
    }

    // MARK: Active shift resolution

    @Test("A completed shift is not mistaken for an active one")
    func completedShiftsAreNotActive() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.endActiveShift(at: start.addingTimeInterval(3600))

        #expect(try service.activeShift() == nil)

        // And the next shift is a new record, not a revival of the finished one.
        let next = try service.startShift(at: start.addingTimeInterval(7200))
        let stored = try storedShifts(in: container)
        #expect(stored.count == 2)
        #expect(next.startedAt == start.addingTimeInterval(7200))
    }

    @Test("Repeated start and end cycles each record a separate shift")
    func repeatedCycles() throws {
        let container = try makeContainer()
        let service = makeService(for: container)

        for cycle in 0..<3 {
            let offset = TimeInterval(cycle) * 86_400
            try service.startShift(at: start.addingTimeInterval(offset))
            try service.endActiveShift(at: start.addingTimeInterval(offset + 3600))
        }

        let stored = try storedShifts(in: container)
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.completedDuration == 3600 })
        #expect(Set(stored.map(\.id)).count == 3)
        #expect(try service.activeShift() == nil)
    }

    @Test("A store holding more than one unfinished shift resolves to the most recent and still refuses a start")
    func toleratesAnAnomalousStore() throws {
        let container = try makeContainer()
        // Written directly, bypassing the service, to simulate a store damaged
        // by a defect or a future migration.
        let context = ModelContext(container)
        context.insert(Shift(startedAt: start))
        context.insert(Shift(startedAt: start.addingTimeInterval(3600)))
        try context.save()

        let service = makeService(for: container)
        let active = try #require(try service.activeShift())

        #expect(active.startedAt == start.addingTimeInterval(3600))
        #expect(throws: ShiftLifecycleError.shiftAlreadyActive(startedAt: start.addingTimeInterval(3600))) {
            try service.startShift(at: start.addingTimeInterval(7200))
        }
    }

    // MARK: Relaunch recovery

    @Test("A new service recovers the running shift from the store")
    func recoversTheRunningShiftFromANewService() throws {
        let container = try makeContainer()
        let original = try makeService(for: container).startShift(at: start)

        // Stands in for the app rebuilding its object graph.
        let recovered = try #require(try makeService(for: container).activeShift())

        #expect(recovered.id == original.id)
        #expect(recovered.startedAt == start)
        #expect(recovered.isActive)
    }

    @Test("A running shift survives closing and reopening the store")
    func survivesStoreReopen() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        let originalID: UUID
        do {
            let container = try ModelContainerFactory.makeContainer(at: storeURL)
            originalID = try makeService(for: container).startShift(at: start).id
        }

        // A different container over the same file: the closest a test gets to
        // the app being terminated and launched again.
        let reopened = try ModelContainerFactory.makeContainer(at: storeURL)
        let service = makeService(for: reopened)
        let recovered = try #require(try service.activeShift())

        #expect(recovered.id == originalID)
        #expect(recovered.startedAt == start, "Recovery must not rewrite the original start time")

        #expect(throws: ShiftLifecycleError.shiftAlreadyActive(startedAt: start)) {
            try service.startShift(at: start.addingTimeInterval(60))
        }

        // The recovered shift is the one that ends, not a replacement.
        let ended = try service.endActiveShift(at: start.addingTimeInterval(1800))
        #expect(ended.id == originalID)
        #expect(try storedShifts(in: reopened).count == 1)
    }

    // MARK: Concurrency

    @Test("Concurrent start attempts still produce exactly one shift")
    func concurrentStartsProduceOneShift() async throws {
        let container = try makeContainer()
        let service = makeService(for: container)

        // The service is main-actor isolated and its operations contain no
        // suspension point, so a check cannot interleave with the insert that
        // follows it. Eight callers racing must still leave one shift.
        let successes = await withTaskGroup(of: Bool.self) { group in
            for attempt in 0..<8 {
                group.addTask { @MainActor in
                    ((try? service.startShift(at: start.addingTimeInterval(TimeInterval(attempt)))) != nil)
                }
            }
            return await group.reduce(into: 0) { total, started in total += started ? 1 : 0 }
        }

        #expect(successes == 1)
        #expect(try storedShifts(in: container).count == 1)
    }

    @Test("Concurrent end attempts end the shift once")
    func concurrentEndsEndTheShiftOnce() async throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        let successes = await withTaskGroup(of: Bool.self) { group in
            for attempt in 0..<8 {
                group.addTask { @MainActor in
                    ((try? service.endActiveShift(at: start.addingTimeInterval(TimeInterval(60 + attempt)))) != nil)
                }
            }
            return await group.reduce(into: 0) { total, ended in total += ended ? 1 : 0 }
        }

        #expect(successes == 1)
        let stored = try storedShifts(in: container)
        #expect(stored.count == 1)
        #expect(stored.first?.isActive == false)
    }

    // MARK: Error reporting

    @Test("Every lifecycle failure carries a message the UI can show")
    func failuresDescribeThemselves() {
        let failures: [ShiftLifecycleError] = [
            .shiftAlreadyActive(startedAt: start),
            .noActiveShift,
            .invalidTransition(.alreadyEnded),
            .storeUnavailable(underlying: CocoaError(.fileNoSuchFile))
        ]

        for failure in failures {
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }

    @Test("Failures of the same kind compare equal regardless of the wrapped store error")
    func failureEquality() {
        #expect(ShiftLifecycleError.noActiveShift == .noActiveShift)
        #expect(ShiftLifecycleError.noActiveShift != .shiftAlreadyActive(startedAt: start))
        #expect(
            ShiftLifecycleError.shiftAlreadyActive(startedAt: start)
                != .shiftAlreadyActive(startedAt: start.addingTimeInterval(1))
        )
        #expect(
            ShiftLifecycleError.storeUnavailable(underlying: CocoaError(.fileNoSuchFile))
                == .storeUnavailable(underlying: CocoaError(.fileReadCorruptFile))
        )
    }
}
