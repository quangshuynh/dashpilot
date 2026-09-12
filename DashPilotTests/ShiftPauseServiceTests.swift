import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The lifecycle authority for pausing and resuming: which transitions are
/// refused, what each one writes, how a pause interacts with deliveries and with
/// ending a shift, and what a failed write leaves behind.
@MainActor
@Suite("Shift pause service")
struct ShiftPauseServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    private func makeService(for container: ModelContainer) -> ShiftService {
        ShiftService(context: ModelContext(container))
    }

    /// Reads the store through a context the service under test never touched.
    private func storedShifts(in container: ModelContainer) throws -> [Shift] {
        try ModelContext(container).fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    // MARK: Pausing

    @Test("Pausing a running shift records a pause and leaves the shift unfinished")
    func pausesARunningShift() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        let shift = try service.pauseActiveShift(at: at(3_600))

        #expect(shift.lifecycleState == .paused)
        #expect(shift.endedAt == nil)

        // Read back through a fresh context: the pause is in the store, not only
        // in the object the service happened to hold.
        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.lifecycleState == .paused)
        #expect(stored.openPause?.startedAt == at(3_600))
        #expect(stored.pauses.count == 1)
    }

    @Test("A paused shift is still the shift the service considers active")
    func pausedShiftIsStillActive() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(600))

        let active = try #require(try makeService(for: container).activeShift())

        #expect(active.startedAt == start)
        #expect(active.isPaused)
    }

    @Test("Pausing an already paused shift is refused and writes nothing")
    func refusesASecondPause() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(600))

        #expect(throws: ShiftLifecycleError.shiftAlreadyPaused(pausedAt: at(600))) {
            try service.pauseActiveShift(at: at(1_200))
        }

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.pauses.count == 1)
        #expect(stored.openPause?.startedAt == at(600))
    }

    @Test("Pausing with no shift running is refused")
    func refusesPauseWithNoShift() throws {
        let container = try makeContainer()

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try makeService(for: container).pauseActiveShift(at: start)
        }
    }

    /// The interval's central refusal. Pausing says the driver stopped working;
    /// an open delivery says they had not. Recording both would produce a shift
    /// whose delivery active time runs through time the app reports as unworked.
    @Test("Pausing is refused while a delivery is in progress, and names how many")
    func refusesPauseOverAnOpenDelivery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        try shifts.startShift(at: start)
        try deliveries.startDelivery(at: at(600))

        #expect(throws: ShiftLifecycleError.activeDeliveriesBlockPause(count: 1)) {
            try shifts.pauseActiveShift(at: at(900))
        }

        try deliveries.startDelivery(at: at(960))
        #expect(throws: ShiftLifecycleError.activeDeliveriesBlockPause(count: 2)) {
            try shifts.pauseActiveShift(at: at(1_200))
        }

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.pauses.isEmpty, "A refused pause writes nothing")
        #expect(stored.lifecycleState == .running)
    }

    /// The refusal has to name what was refused. A driver who asked to pause and
    /// is told to finish their deliveries "before ending the shift" has been
    /// answered about something they did not ask for.
    @Test("The pause refusal talks about pausing, not about ending")
    func pauseRefusalNamesPausing() {
        let one = ShiftLifecycleError.activeDeliveriesBlockPause(count: 1).errorDescription ?? ""
        let several = ShiftLifecycleError.activeDeliveriesBlockPause(count: 3).errorDescription ?? ""

        #expect(one.contains("before pausing the shift"))
        #expect(!one.contains("ending"))
        #expect(several.contains("3 deliveries"))
        #expect(several.contains("before pausing the shift"))
        #expect(
            ShiftLifecycleError.activeDeliveriesInProgress(count: 1).errorDescription?.contains("ending the shift")
                == true,
            "The end refusal is unchanged"
        )
    }

    @Test("Deliveries cannot be started while the shift is paused")
    func refusesADeliveryWhilePaused() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(600))

        #expect(throws: DeliveryLifecycleError.shiftPaused) {
            try deliveries.startDelivery(at: at(900))
        }

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.deliveries.isEmpty)

        // Resuming lifts the refusal, rather than the driver being stuck.
        try shifts.resumeActiveShift(at: at(1_200))
        try deliveries.startDelivery(at: at(1_500))
        #expect(try #require(try storedShifts(in: container).first).deliveries.count == 1)
    }

    // MARK: Resuming

    @Test("Resuming closes the pause and returns the shift to running")
    func resumesAPausedShift() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))

        let shift = try service.resumeActiveShift(at: at(5_400))

        #expect(shift.lifecycleState == .running)
        #expect(shift.openPause == nil)

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.lifecycleState == .running)
        #expect(stored.pauses.count == 1)
        #expect(stored.pausesInOrder.first?.endedAt == at(5_400))
        #expect(stored.pausedTime(asOf: at(7_200)).duration == 1_800)
        #expect(stored.workingDuration(asOf: at(7_200)) == 5_400)
    }

    @Test("Resuming a shift that is not paused is refused")
    func refusesResumeWhenRunning() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        #expect(throws: ShiftLifecycleError.shiftNotPaused) {
            try service.resumeActiveShift(at: at(600))
        }
    }

    @Test("Resuming with no shift running is refused")
    func refusesResumeWithNoShift() throws {
        let container = try makeContainer()

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try makeService(for: container).resumeActiveShift(at: start)
        }
    }

    @Test("Pausing and resuming several times records each stretch")
    func severalPauses() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        try service.pauseActiveShift(at: at(3_600))
        try service.resumeActiveShift(at: at(5_400))
        try service.pauseActiveShift(at: at(9_000))
        try service.resumeActiveShift(at: at(10_800))
        try service.endActiveShift(at: at(14_400))

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.pauses.count == 2)
        #expect(stored.completedPausedTime?.duration == 3_600)
        #expect(stored.completedDuration == 14_400)
        #expect(stored.completedWorkingDuration == 10_800)
    }

    // MARK: Ending a paused shift

    /// The explicit semantics: a driver who has finished has finished, and
    /// making them resume a shift they are not working in order to end it would
    /// record work that did not happen. So the pause is closed at the end
    /// instant, and its whole length stays out of the working duration.
    @Test("Ending a paused shift closes the pause at the end time")
    func endingAPausedShiftClosesThePause() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))

        let shift = try service.endActiveShift(at: at(7_200))

        #expect(shift.lifecycleState == .ended)
        #expect(shift.endedAt == at(7_200))

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.openPause == nil, "No pause is left open on a finished shift")
        #expect(stored.pausesInOrder.first?.endedAt == at(7_200))
        #expect(stored.completedDuration == 7_200)
        #expect(stored.completedPausedTime?.duration == 3_600)
        #expect(stored.completedWorkingDuration == 3_600, "Every second between pausing and ending stays out")
    }

    @Test("A shift paused immediately and then ended has no working time at all")
    func aShiftPausedThroughoutRecordsNoWorkingTime() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: start)
        try service.endActiveShift(at: at(7_200))

        let stored = try #require(try storedShifts(in: container).first)
        #expect(stored.completedDuration == 7_200)
        #expect(stored.completedWorkingDuration == 0)

        let metrics = stored.metrics(for: .none)
        #expect(metrics.grossPerWorkingHour == .unavailable(.earningsNotRecorded))
    }

    // MARK: Clocks that move backwards

    @Test("A pause timestamp before the shift start is clamped to the start")
    func pauseTimestampIsClamped() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)

        let shift = try service.pauseActiveShift(at: at(-600))

        #expect(shift.openPause?.startedAt == start)
    }

    @Test("A resume timestamp before the pause began is clamped to the pause start")
    func resumeTimestampIsClamped() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))

        let shift = try service.resumeActiveShift(at: at(1_800))

        #expect(shift.pausesInOrder.first?.endedAt == at(3_600), "A zero-length pause, not a refusal")
        #expect(shift.lifecycleState == .running)
    }

    /// A driver must always be able to end a shift. A clock that moved back
    /// since the pause must not make the model refuse the pause closure and
    /// leave them stuck paused.
    @Test("Ending a paused shift with a backwards clock still ends it")
    func endingWithABackwardsClockStillWorks() throws {
        let container = try makeContainer()
        let service = makeService(for: container)
        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_600))

        let shift = try service.endActiveShift(at: at(1_800))

        #expect(shift.endedAt == at(3_600), "Clamped forward to the open pause's start")
        #expect(shift.openPause == nil)
        #expect(shift.completedWorkingDuration == 3_600)
        #expect(shift.completedPausedTime?.duration == 0)
    }

    // MARK: Deletion

    @Test("Deleting a completed shift takes its pauses with it")
    func deletionCascades() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ShiftService(context: context)

        try service.startShift(at: start)
        try service.pauseActiveShift(at: at(600))
        try service.resumeActiveShift(at: at(1_200))
        let shift = try service.endActiveShift(at: at(3_600))

        #expect(try context.fetch(FetchDescriptor<ShiftPause>()).count == 1)

        try service.deleteCompletedShift(shift)

        #expect(try ModelContext(container).fetch(FetchDescriptor<ShiftPause>()).isEmpty)
    }

    @Test("A paused shift cannot be deleted, because it has not finished")
    func pausedShiftCannotBeDeleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = ShiftService(context: context)

        try service.startShift(at: start)
        let shift = try service.pauseActiveShift(at: at(600))

        #expect(throws: ShiftLifecycleError.cannotDeleteActiveShift) {
            try service.deleteCompletedShift(shift)
        }
    }
}
