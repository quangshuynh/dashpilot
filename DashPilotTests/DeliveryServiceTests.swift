import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The delivery lifecycle service: what it refuses, what it enforces against
/// the store, and how it coordinates with a shift.
///
/// Every operation is given its timestamp, so nothing here depends on how long
/// the test took to run.
@MainActor
@Suite("Delivery service")
struct DeliveryServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A context with a shift already running, which is the precondition for
    /// almost everything below.
    private func makeRunningShift() throws -> (context: ModelContext, shift: Shift) {
        let context = try makeContext()
        let shift = try ShiftService(context: context).startShift(at: start)
        return (context, shift)
    }

    // MARK: Starting

    @Test("A delivery begins during a running shift and belongs to it")
    func startsDuringARunningShift() throws {
        let (context, shift) = try makeRunningShift()

        let delivery = try DeliveryService(context: context).startDelivery(at: at(300))

        #expect(delivery.state == .accepted)
        #expect(delivery.acceptedAt == at(300))
        #expect(delivery.shift?.id == shift.id)
        #expect(shift.deliveries.count == 1)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
    }

    @Test("A delivery cannot begin with no shift running")
    func refusesWithoutAShift() throws {
        let context = try makeContext()

        #expect(throws: DeliveryLifecycleError.noActiveShift) {
            try DeliveryService(context: context).startDelivery(at: start)
        }
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
    }

    @Test("A delivery cannot begin once every shift has ended")
    func refusesOnACompletedShift() throws {
        let (context, _) = try makeRunningShift()
        try ShiftService(context: context).endActiveShift(at: at(3_600))

        #expect(throws: DeliveryLifecycleError.noActiveShift) {
            try DeliveryService(context: context).startDelivery(at: at(3_700))
        }
        #expect(
            try context.fetch(FetchDescriptor<Delivery>()).isEmpty,
            "A completed shift must not gain a delivery"
        )
    }

    @Test("A second delivery is refused while one is in progress")
    func refusesASecondActiveDelivery() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))

        #expect(throws: DeliveryLifecycleError.deliveryAlreadyActive(state: .arrivedAtPickup)) {
            try service.startDelivery(at: at(900))
        }
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
    }

    @Test("A new delivery may begin once the previous one has finished", arguments: [true, false])
    func allowsANewDeliveryAfterTheLastFinished(byDelivering: Bool) throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))
        if byDelivering {
            try service.markPickedUp(at: at(900))
            try service.markDelivered(at: at(1_500))
        } else {
            try service.cancelActiveDelivery(at: at(900))
        }

        let second = try service.startDelivery(at: at(1_800))

        let active = try #require(try service.activeDelivery())
        #expect(second.state == .accepted)
        #expect(shift.deliveries.count == 2)
        #expect(active.id == second.id)
    }

    @Test("A delivery accepted before its shift began is clamped to the shift start")
    func clampsAStartBeforeTheShift() throws {
        let (context, shift) = try makeRunningShift()

        // The device clock moved behind the recorded shift start.
        let delivery = try DeliveryService(context: context).startDelivery(at: at(-600))

        #expect(delivery.acceptedAt == shift.startedAt, "A delivery cannot predate the shift it belongs to")
    }

    // MARK: Transitions

    @Test("A delivery moves through accepted, arrived, picked up and delivered")
    func advancesThroughTheLifecycle() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))

        #expect(try service.markArrivedAtPickup(at: at(600)).state == .arrivedAtPickup)
        #expect(try service.markPickedUp(at: at(1_020)).state == .pickedUp)
        let delivered = try service.markDelivered(at: at(1_800))

        #expect(delivered.state == .delivered)
        #expect(delivered.arrivedAtPickupAt == at(600))
        #expect(delivered.pickedUpAt == at(1_020))
        #expect(delivered.deliveredAt == at(1_800))
        #expect(delivered.pickupWait == 420)
        #expect(delivered.completedDuration == 1_500)
        #expect(try service.activeDelivery() == nil, "A delivered delivery is no longer active")
    }

    @Test("Skipping a lifecycle step is refused through the service")
    func refusesSkippedSteps() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.outOfOrder(missing: .arrivedAtPickup))) {
            try service.markPickedUp(at: at(600))
        }
        #expect(throws: DeliveryLifecycleError.invalidTransition(.outOfOrder(missing: .pickedUp))) {
            try service.markDelivered(at: at(600))
        }
        let unchanged = try #require(try service.activeDelivery())
        #expect(unchanged.state == .accepted)
    }

    @Test("Repeating a transition is refused")
    func refusesRepeatedTransitions() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.alreadyRecorded(.arrivedAtPickup))) {
            try service.markArrivedAtPickup(at: at(700))
        }
        let stillArrived = try #require(try service.activeDelivery())
        #expect(stillArrived.arrivedAtPickupAt == at(600))
    }

    @Test("A completed delivery cannot be advanced or cancelled afterwards")
    func refusesTransitionsAfterCompletion() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))
        try service.markPickedUp(at: at(900))
        try service.markDelivered(at: at(1_500))

        // There is no active delivery to address any more, which is what makes
        // an out-of-order transition unrepresentable rather than merely refused.
        #expect(throws: DeliveryLifecycleError.noActiveDelivery) {
            try service.markDelivered(at: at(1_800))
        }
        #expect(throws: DeliveryLifecycleError.noActiveDelivery) {
            try service.cancelActiveDelivery(at: at(1_800))
        }
        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(stored.deliveredAt == at(1_500))
    }

    @Test("A transition with no delivery in progress is refused")
    func refusesTransitionsWithNoDelivery() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)

        #expect(throws: DeliveryLifecycleError.noActiveDelivery) {
            try service.markArrivedAtPickup(at: at(300))
        }
    }

    @Test("An event timestamped before the previous one is clamped forward")
    func clampsBackwardsEvents() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(at: at(1_200))

        // The device clock moved behind the arrival that was already recorded.
        let pickedUp = try service.markPickedUp(at: at(900))

        #expect(pickedUp.pickedUpAt == at(1_200), "Clamped to the previous event rather than refused")
        #expect(pickedUp.pickupWait == 0, "A clamped event records a zero-length wait, never a negative one")

        let delivered = try service.markDelivered(at: at(300))
        let duration = try #require(delivered.completedDuration)
        #expect(delivered.deliveredAt == at(1_200))
        #expect(duration >= 0)
    }

    // MARK: Cancellation

    @Test("A cancelled delivery is kept in its shift's history")
    func keepsCancelledDeliveries() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(at: at(600))

        let cancelled = try service.cancelActiveDelivery(at: at(1_200))

        #expect(cancelled.state == .cancelled)
        #expect(cancelled.arrivedAtPickupAt == at(600), "The arrival that happened is preserved")
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1, "Cancelling is not deleting")
        #expect(shift.deliverySummary == DeliverySummary(completed: 0, cancelled: 1))
        #expect(try service.activeDelivery() == nil)
    }

    // MARK: Shift interaction

    @Test("One shift can hold several completed deliveries")
    func holdsSeveralDeliveries() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)

        for index in 0..<3 {
            let base = TimeInterval(index) * 1_800
            try service.startDelivery(at: at(base + 300))
            try service.markArrivedAtPickup(at: at(base + 600))
            try service.markPickedUp(at: at(base + 900))
            try service.markDelivered(at: at(base + 1_500))
        }

        #expect(shift.deliveries.count == 3)
        #expect(shift.deliverySummary == DeliverySummary(completed: 3, cancelled: 0))
        #expect(shift.deliveriesInOrder.map(\.acceptedAt) == [at(300), at(2_100), at(3_900)])
    }

    @Test("A delivery belongs to the shift that was running, and never to another")
    func deliveriesNeverCrossShifts() throws {
        let (context, first) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(at: at(600))
        try deliveries.markPickedUp(at: at(900))
        try deliveries.markDelivered(at: at(1_200))
        try shifts.endActiveShift(at: at(3_600))

        let second = try shifts.startShift(at: at(7_200))
        try deliveries.startDelivery(at: at(7_500))

        #expect(first.deliveries.count == 1)
        #expect(second.deliveries.count == 1)
        #expect(first.deliveries.first?.id != second.deliveries.first?.id)
        #expect(second.deliveries.allSatisfy { $0.shift?.id == second.id })
    }

    @Test("A shift cannot end while one of its deliveries is in progress")
    func refusesToEndWithAnActiveDelivery() throws {
        let (context, shift) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        try DeliveryService(context: context).startDelivery(at: at(300))

        #expect(throws: ShiftLifecycleError.activeDeliveryInProgress) {
            try shifts.endActiveShift(at: at(3_600))
        }
        #expect(shift.isActive, "The shift is still running")
        #expect(shift.endedAt == nil)
        #expect(
            shift.activeDelivery?.state == .accepted,
            "The delivery is neither silently delivered nor silently discarded"
        )
    }

    @Test("The shift ends once the delivery is resolved", arguments: [true, false])
    func endsOnceTheDeliveryIsResolved(byDelivering: Bool) throws {
        let (context, shift) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(at: at(600))

        if byDelivering {
            try deliveries.markPickedUp(at: at(900))
            try deliveries.markDelivered(at: at(1_200))
        } else {
            try deliveries.cancelActiveDelivery(at: at(1_200))
        }
        try shifts.endActiveShift(at: at(3_600))

        #expect(!shift.isActive)
        #expect(shift.endedAt == at(3_600))
        #expect(shift.deliveries.count == 1, "The delivery stays in the shift either way")
    }

    @Test("Deleting a completed shift deletes its deliveries and leaves other shifts alone")
    func deletionCascadesToDeliveries() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        let removed = try shifts.startShift(at: start)
        try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(at: at(600))
        try deliveries.cancelActiveDelivery(at: at(900))
        try shifts.endActiveShift(at: at(3_600))

        try shifts.startShift(at: at(7_200))
        try deliveries.startDelivery(at: at(7_500))
        try deliveries.markArrivedAtPickup(at: at(7_800))
        try deliveries.markPickedUp(at: at(8_100))
        try deliveries.markDelivered(at: at(8_400))
        let keptDeliveryID = try #require(try context.fetch(FetchDescriptor<Delivery>())
            .first { $0.shift?.startedAt == at(7_200) })
            .id
        try shifts.endActiveShift(at: at(10_800))

        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)

        try shifts.deleteCompletedShift(removed)

        let remaining = try context.fetch(FetchDescriptor<Delivery>())
        #expect(remaining.count == 1, "The deleted shift's deliveries go with it rather than being orphaned")
        #expect(remaining.first?.id == keptDeliveryID)
        #expect(remaining.allSatisfy { $0.shift != nil }, "No delivery is left without a shift")
    }

    // MARK: Anomalous data

    @Test("More than one unfinished delivery resolves deterministically to the most recent")
    func resolvesAnomalousStoreDeterministically() throws {
        let (context, shift) = try makeRunningShift()
        // Written straight into the store, which the service API cannot produce.
        // The rule still has to hold against data the service did not create.
        let older = Delivery(shift: shift, acceptedAt: at(300))
        let newer = Delivery(shift: shift, acceptedAt: at(900))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let service = DeliveryService(context: context)

        let firstRead = try #require(try service.activeDelivery())
        // Repeatable, and nothing is closed, cancelled or deleted to tidy up.
        let secondRead = try #require(try service.activeDelivery())
        #expect(firstRead.id == newer.id)
        #expect(secondRead.id == newer.id)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)
        #expect(throws: DeliveryLifecycleError.deliveryAlreadyActive(state: .accepted)) {
            try service.startDelivery(at: at(1_200))
        }
        #expect(throws: ShiftLifecycleError.activeDeliveryInProgress) {
            try ShiftService(context: context).endActiveShift(at: at(3_600))
        }
    }
}
