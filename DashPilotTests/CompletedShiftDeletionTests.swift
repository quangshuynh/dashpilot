import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Deleting a finished shift, and everything that must and must not go with it.
///
/// Deletion is the one operation in DashPilot that destroys data a driver cannot
/// re-enter, so the tests here are about blast radius as much as about the happy
/// path: the shift's own route goes, another shift's route stays, and a refused
/// delete changes nothing at all.
@MainActor
@Suite("Completed shift deletion")
struct CompletedShiftDeletionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let session = UUID()

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotDeletionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    /// A finished shift with `sampleCount` synthetic positions on it.
    @discardableResult
    private func insertCompletedShift(
        into context: ModelContext,
        startingAt shiftStart: Date,
        sampleCount: Int
    ) -> Shift {
        let shift = Shift(startedAt: shiftStart)
        try? shift.end(at: shiftStart.addingTimeInterval(3 * 3600))
        context.insert(shift)
        for step in 0..<sampleCount {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(
                        at: shiftStart.addingTimeInterval(Double(step) * 20),
                        northMetres: Double(step) * 400
                    ),
                    captureSessionID: session
                )
            )
        }
        return shift
    }

    /// Reads the store through a context the service under test never touched.
    private func storedShifts(in container: ModelContainer) throws -> [Shift] {
        try ModelContext(container).fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    private func storedSamples(in container: ModelContainer) throws -> [RouteSample] {
        try ModelContext(container).fetch(FetchDescriptor<RouteSample>())
    }

    // MARK: Deleting

    @Test("A completed shift is deleted from the store")
    func deletesACompletedShift() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shift = insertCompletedShift(into: context, startingAt: start, sampleCount: 0)
        try context.save()

        try ShiftService(context: context).deleteCompletedShift(shift)

        #expect(try storedShifts(in: container).isEmpty)
    }

    @Test("Deleting a shift deletes the route positions recorded during it")
    func deletesTheRouteWithTheShift() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shift = insertCompletedShift(into: context, startingAt: start, sampleCount: 5)
        try context.save()
        #expect(try storedSamples(in: container).count == 5)

        try ShiftService(context: context).deleteCompletedShift(shift)

        // Not one orphaned coordinate belonging to a shift that no longer exists.
        #expect(try storedSamples(in: container).isEmpty)
    }

    @Test("Deleting one shift leaves another shift and its route untouched")
    func leavesOtherShiftsAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let kept = insertCompletedShift(into: context, startingAt: start, sampleCount: 3)
        let removed = insertCompletedShift(into: context, startingAt: start.addingTimeInterval(30 * 3600), sampleCount: 4)
        try? kept.setGrossEarnings(Money(minorUnits: 8625))
        try context.save()

        try ShiftService(context: context).deleteCompletedShift(removed)

        let remainingShifts = try storedShifts(in: container)
        #expect(remainingShifts.count == 1)
        #expect(remainingShifts.first?.id == kept.id)
        #expect(remainingShifts.first?.grossEarnings == Money(minorUnits: 8625))

        let remainingSamples = try storedSamples(in: container)
        #expect(remainingSamples.count == 3)
        #expect(remainingSamples.allSatisfy { $0.shift?.id == kept.id })
    }

    @Test("A deleted shift stays deleted, with its route, after the store is reopened")
    func deletionSurvivesAReopen() throws {
        let (url, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let container = try ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let kept = insertCompletedShift(into: context, startingAt: start, sampleCount: 2)
            let removed = insertCompletedShift(into: context, startingAt: start.addingTimeInterval(30 * 3600), sampleCount: 6)
            try context.save()

            try ShiftService(context: context).deleteCompletedShift(removed)
            #expect(kept.routeSamples.count == 2)
        }

        let reopened = try ModelContainerFactory.makeContainer(at: url)
        let shifts = try storedShifts(in: reopened)
        #expect(shifts.count == 1)
        #expect(shifts.first?.startedAt == start)

        let samples = try storedSamples(in: reopened)
        #expect(samples.count == 2)
        #expect(samples.allSatisfy { $0.shift?.startedAt == start })
    }

    // MARK: Refusing

    @Test("A running shift cannot be deleted, whatever the interface offers")
    func refusesToDeleteARunningShift() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ShiftService(context: context)
        let running = try service.startShift(at: start)
        context.insert(
            RouteSample(
                shift: running,
                sample: SyntheticRoute.sample(at: start.addingTimeInterval(10)),
                captureSessionID: session
            )
        )
        try context.save()

        #expect(throws: ShiftLifecycleError.cannotDeleteActiveShift) {
            try service.deleteCompletedShift(running)
        }

        // The refusal must leave the store exactly as it was, route included.
        let stored = try storedShifts(in: container)
        #expect(stored.count == 1)
        #expect(stored.first?.isActive == true)
        #expect(try storedSamples(in: container).count == 1)
    }

    @Test("A refused delete does not touch any other shift either")
    func refusalLeavesHistoryIntact() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let completed = insertCompletedShift(into: context, startingAt: start, sampleCount: 3)
        try context.save()

        let service = ShiftService(context: context)
        let running = try service.startShift(at: start.addingTimeInterval(30 * 3600))

        #expect(throws: ShiftLifecycleError.cannotDeleteActiveShift) {
            try service.deleteCompletedShift(running)
        }

        #expect(try storedShifts(in: container).count == 2)
        let samples = try storedSamples(in: container)
        #expect(samples.count == 3)
        #expect(samples.allSatisfy { $0.shift?.id == completed.id })
    }

    @Test("A shift ended and then deleted is gone; ending it is not what protects it")
    func deletesAShiftEndedThroughTheService() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ShiftService(context: context)
        try service.startShift(at: start)
        let ended = try service.endActiveShift(at: start.addingTimeInterval(3600))

        try service.deleteCompletedShift(ended)

        #expect(try storedShifts(in: container).isEmpty)
        #expect(try service.activeShift() == nil)
    }

    // MARK: The error it reports

    @Test("The refusal explains itself in a sentence a driver can act on")
    func refusalIsExplained() {
        let description = ShiftLifecycleError.cannotDeleteActiveShift.errorDescription

        #expect(description?.contains("in progress") == true)
        #expect(description?.contains("End it first") == true)
    }
}
