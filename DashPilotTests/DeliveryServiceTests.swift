import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The delivery lifecycle service: what it refuses, what it enforces against
/// the store, and how several concurrent deliveries stay independent of each
/// other.
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

    // MARK: Concurrent creation

    @Test("A second delivery begins while the first is still active, and changes nothing about it")
    func startsASecondWhileTheFirstIsActive() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(first, at: at(600))

        let second = try service.startDelivery(at: at(900))

        #expect(second.id != first.id, "Two orders are two records, never one merged delivery")
        #expect(second.state == .accepted)
        #expect(first.state == .arrivedAtPickup, "Starting another delivery does not touch the first")
        #expect(first.arrivedAtPickupAt == at(600))
        #expect(second.arrivedAtPickupAt == nil)
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [first.id, second.id])
        #expect(shift.deliverySummary == DeliverySummary(completed: 0, cancelled: 0, inProgress: 2))
    }

    @Test("A third delivery begins while two are active, all on the same shift")
    func startsAThirdWhileTwoAreActive() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        let third = try service.startDelivery(at: at(900))

        let active = try service.activeDeliveries(for: shift)

        #expect(active.map(\.id) == [first.id, second.id, third.id])
        #expect(active.allSatisfy { $0.shift?.id == shift.id }, "Every concurrent delivery is on the running shift")
        #expect(active.allSatisfy { $0.state == .accepted })
        #expect(Set(active.map(\.id)).count == 3, "No delivery is duplicated")
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
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))

        #expect(try service.markArrivedAtPickup(delivery, at: at(600)).state == .arrivedAtPickup)
        #expect(try service.markPickedUp(delivery, at: at(1_020)).state == .pickedUp)
        let delivered = try service.markDelivered(delivery, at: at(1_800))

        #expect(delivered.id == delivery.id)
        #expect(delivered.state == .delivered)
        #expect(delivered.arrivedAtPickupAt == at(600))
        #expect(delivered.pickedUpAt == at(1_020))
        #expect(delivered.deliveredAt == at(1_800))
        #expect(delivered.pickupWait == 420)
        #expect(delivered.completedDuration == 1_500)
        #expect(try service.activeDeliveries(for: shift).isEmpty, "A delivered delivery is no longer active")
    }

    @Test("Skipping a lifecycle step is refused through the service")
    func refusesSkippedSteps() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.outOfOrder(missing: .arrivedAtPickup))) {
            try service.markPickedUp(delivery, at: at(600))
        }
        #expect(throws: DeliveryLifecycleError.invalidTransition(.outOfOrder(missing: .pickedUp))) {
            try service.markDelivered(delivery, at: at(600))
        }
        #expect(delivery.state == .accepted)
    }

    @Test("Repeating a transition is refused")
    func refusesRepeatedTransitions() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.alreadyRecorded(.arrivedAtPickup))) {
            try service.markArrivedAtPickup(delivery, at: at(700))
        }
        #expect(delivery.arrivedAtPickupAt == at(600))
    }

    @Test("A finished delivery cannot be advanced or cancelled afterwards")
    func refusesTransitionsAfterCompletion() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.markPickedUp(delivery, at: at(900))
        try service.markDelivered(delivery, at: at(1_500))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.alreadyFinished(.delivered))) {
            try service.markDelivered(delivery, at: at(1_800))
        }
        #expect(throws: DeliveryLifecycleError.invalidTransition(.alreadyFinished(.delivered))) {
            try service.cancelDelivery(delivery, at: at(1_800))
        }
        let stored = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(stored.deliveredAt == at(1_500))
    }

    @Test("An event timestamped before the previous one is clamped forward")
    func clampsBackwardsEvents() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(delivery, at: at(1_200))

        // The device clock moved behind the arrival that was already recorded.
        let pickedUp = try service.markPickedUp(delivery, at: at(900))

        #expect(pickedUp.pickedUpAt == at(1_200), "Clamped to the previous event rather than refused")
        #expect(pickedUp.pickupWait == 0, "A clamped event records a zero-length wait, never a negative one")

        let delivered = try service.markDelivered(delivery, at: at(300))
        let duration = try #require(delivered.completedDuration)
        #expect(delivered.deliveredAt == at(1_200))
        #expect(duration >= 0)
    }

    @Test("The clamp reads the delivery's own last event, not another delivery's")
    func clampsAgainstTheTargetedDeliveryAlone() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let early = try service.startDelivery(at: at(300))
        let late = try service.startDelivery(at: at(3_000))
        try service.markArrivedAtPickup(late, at: at(3_300))

        // Earlier than the other delivery's last event, but later than this
        // one's, so nothing is clamped.
        let arrived = try service.markArrivedAtPickup(early, at: at(600))

        #expect(arrived.arrivedAtPickupAt == at(600), "A concurrent delivery's clock does not move this one's")
        #expect(late.arrivedAtPickupAt == at(3_300))
    }

    // MARK: Independence

    @Test("Advancing one delivery leaves the other exactly as it was", arguments: [true, false])
    func advancingOneLeavesTheOtherUntouched(advanceFirst: Bool) throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))

        let advanced = advanceFirst ? first : second
        let untouched = advanceFirst ? second : first
        try service.markArrivedAtPickup(advanced, at: at(900))

        #expect(advanced.state == .arrivedAtPickup)
        #expect(advanced.arrivedAtPickupAt == at(900))
        #expect(untouched.state == .accepted, "An event belongs to one delivery and reaches no other")
        #expect(untouched.arrivedAtPickupAt == nil)
        #expect(untouched.acceptedAt == (advanceFirst ? at(600) : at(300)), "Its acceptance is untouched too")
    }

    @Test("Concurrent deliveries can sit at different states at the same time")
    func deliveriesHoldDifferentStatesAtOnce() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        let third = try service.startDelivery(at: at(900))

        try service.markArrivedAtPickup(second, at: at(1_200))
        try service.markArrivedAtPickup(third, at: at(1_500))
        try service.markPickedUp(third, at: at(1_800))

        #expect(first.state == .accepted)
        #expect(second.state == .arrivedAtPickup)
        #expect(third.state == .pickedUp)
        #expect(shift.deliverySummary.inProgress == 3)
        #expect(
            shift.activeDeliveries.map(\.state.nextAction) == [.arriveAtPickup, .pickUp, .complete],
            "Each delivery offers its own next step"
        )
    }

    @Test("Delivering one leaves the other running")
    func deliveringOneLeavesTheOtherActive() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(first, at: at(900))
        try service.markPickedUp(first, at: at(1_200))

        try service.markDelivered(first, at: at(1_800))

        #expect(first.state == .delivered)
        #expect(second.state == .accepted)
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [second.id])
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 0, inProgress: 1))
    }

    @Test("Cancelling one leaves the other running")
    func cancellingOneLeavesTheOtherActive() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(second, at: at(900))

        try service.cancelDelivery(first, at: at(1_200))

        #expect(first.state == .cancelled)
        #expect(second.state == .arrivedAtPickup, "The delivery still in the car is untouched")
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [second.id])
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2, "Cancelling is not deleting")
    }

    @Test("A refused transition on one delivery changes neither delivery")
    func refusalsNeverCrossDeliveries() throws {
        let (context, _) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(second, at: at(900))

        // Skipping a step on the first must not be absorbed by the second,
        // which *is* ready for this event.
        #expect(throws: DeliveryLifecycleError.invalidTransition(.outOfOrder(missing: .arrivedAtPickup))) {
            try service.markPickedUp(first, at: at(1_200))
        }

        #expect(first.state == .accepted)
        #expect(second.state == .arrivedAtPickup, "The refusal did not land on the other delivery")
        #expect(second.pickedUpAt == nil)
    }

    // MARK: Ordering and numbering

    @Test("Active deliveries are returned in the order they were accepted")
    func activeDeliveriesAreOrderedByAcceptance() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        // Started out of order on purpose: the fetch must not be trusted to
        // return them in insertion order.
        let late = try service.startDelivery(at: at(2_400))
        let early = try service.startDelivery(at: at(300))
        let middle = try service.startDelivery(at: at(1_200))

        #expect(try service.activeDeliveries().map(\.id) == [early.id, middle.id, late.id])
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [early.id, middle.id, late.id])
        #expect(shift.deliveriesInOrder.map(\.id) == [early.id, middle.id, late.id])
    }

    @Test("Two deliveries accepted in the same instant keep a stable order")
    func orderingIsTotalForIdenticalAcceptanceTimes() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(300))

        let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id)

        #expect(try service.activeDeliveries().map(\.id) == expected)
        #expect(try service.activeDeliveries().map(\.id) == expected, "And the same order on a second read")
        #expect(shift.numberedDeliveries.map(\.delivery.id) == expected)
    }

    @Test("A delivery keeps its number when another one finishes")
    func numbersSurviveOtherDeliveriesFinishing() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        let third = try service.startDelivery(at: at(900))

        #expect(shift.numberedActiveDeliveries.map(\.number) == [1, 2, 3])
        #expect(shift.numberedActiveDeliveries.map(\.title) == ["Delivery 1", "Delivery 2", "Delivery 3"])

        try service.markArrivedAtPickup(first, at: at(1_200))
        try service.markPickedUp(first, at: at(1_500))
        try service.markDelivered(first, at: at(1_800))

        #expect(
            shift.numberedActiveDeliveries.map(\.number) == [2, 3],
            "The remaining deliveries keep the labels they already had"
        )
        #expect(shift.numberedActiveDeliveries.map(\.delivery.id) == [second.id, third.id])
        #expect(shift.numberedDeliveries.map(\.number) == [1, 2, 3], "The finished one keeps its number in history")
    }

    @Test("A shift's active deliveries exclude another shift's")
    func activeDeliveriesAreScopedToTheirShift() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)

        let first = try shifts.startShift(at: start)
        let stranded = try service.startDelivery(at: at(300))
        // Ended at the model level, which the service would have refused: this
        // is a store holding data the app cannot produce.
        try first.end(at: at(3_600))
        try context.save()

        let second = try shifts.startShift(at: at(7_200))
        let current = try service.startDelivery(at: at(7_500))

        #expect(try service.activeDeliveries(for: second).map(\.id) == [current.id])
        #expect(try service.activeDeliveries(for: first).map(\.id) == [stranded.id])
        #expect(
            try service.activeDeliveries().map(\.id) == [stranded.id, current.id],
            "The store-wide read still reports the stranded row rather than hiding it"
        )
    }

    // MARK: Cancellation

    @Test("A cancelled delivery is kept in its shift's history")
    func keepsCancelledDeliveries() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))

        let cancelled = try service.cancelDelivery(delivery, at: at(1_200))

        #expect(cancelled.state == .cancelled)
        #expect(cancelled.arrivedAtPickupAt == at(600), "The arrival that happened is preserved")
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1, "Cancelling is not deleting")
        #expect(shift.deliverySummary == DeliverySummary(completed: 0, cancelled: 1))
        #expect(try service.activeDeliveries(for: shift).isEmpty)
    }

    // MARK: Shift interaction

    @Test("One shift can hold several completed deliveries")
    func holdsSeveralDeliveries() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)

        for index in 0..<3 {
            let base = TimeInterval(index) * 1_800
            let delivery = try service.startDelivery(at: at(base + 300))
            try service.markArrivedAtPickup(delivery, at: at(base + 600))
            try service.markPickedUp(delivery, at: at(base + 900))
            try service.markDelivered(delivery, at: at(base + 1_500))
        }

        #expect(shift.deliveries.count == 3)
        #expect(shift.deliverySummary == DeliverySummary(completed: 3, cancelled: 0))
        #expect(shift.deliveriesInOrder.map(\.acceptedAt) == [at(300), at(2_100), at(3_900)])
    }

    @Test("Overlapping deliveries each keep their own durations")
    func overlappingDeliveriesKeepSeparateDurations() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(0))
        let second = try service.startDelivery(at: at(600))
        try service.markArrivedAtPickup(first, at: at(300))
        try service.markPickedUp(first, at: at(900))
        try service.markArrivedAtPickup(second, at: at(1_200))
        try service.markPickedUp(second, at: at(1_500))
        try service.markDelivered(first, at: at(1_800))
        try service.markDelivered(second, at: at(2_100))

        // 30 minutes and 25 minutes that overlap by 20. Each delivery reports
        // its own span, and nothing anywhere adds them up: a sum would claim 55
        // minutes of work out of 35 minutes of shift.
        #expect(first.completedDuration == 1_800)
        #expect(second.completedDuration == 1_500)
        #expect(first.pickupWait == 600)
        #expect(second.pickupWait == 300)
        #expect(shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 0))
    }

    @Test("A delivery belongs to the shift that was running, and never to another")
    func deliveriesNeverCrossShifts() throws {
        let (context, first) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        let delivery = try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(delivery, at: at(600))
        try deliveries.markPickedUp(delivery, at: at(900))
        try deliveries.markDelivered(delivery, at: at(1_200))
        try shifts.endActiveShift(at: at(3_600))

        let second = try shifts.startShift(at: at(7_200))
        try deliveries.startDelivery(at: at(7_500))

        #expect(first.deliveries.count == 1)
        #expect(second.deliveries.count == 1)
        #expect(first.deliveries.first?.id != second.deliveries.first?.id)
        #expect(second.deliveries.allSatisfy { $0.shift?.id == second.id })
    }

    @Test("A delivery attached to a shift that has ended cannot be advanced")
    func refusesTransitionsOnAStrandedDelivery() throws {
        let (context, shift) = try makeRunningShift()
        let service = DeliveryService(context: context)
        let delivery = try service.startDelivery(at: at(300))
        // Ended at the model level, bypassing the refusal the service would
        // have raised: only a damaged store can be in this state.
        try shift.end(at: at(3_600))
        try context.save()

        #expect(throws: DeliveryLifecycleError.deliveryNotOnARunningShift) {
            try service.markArrivedAtPickup(delivery, at: at(3_700))
        }
        #expect(throws: DeliveryLifecycleError.deliveryNotOnARunningShift) {
            try service.cancelDelivery(delivery, at: at(3_700))
        }
        #expect(delivery.state == .accepted, "Nothing is repaired, closed or reparented")
        #expect(delivery.shift?.id == shift.id)
    }

    // MARK: Shift end

    @Test("A shift cannot end while one of its deliveries is in progress")
    func refusesToEndWithAnActiveDelivery() throws {
        let (context, shift) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        try DeliveryService(context: context).startDelivery(at: at(300))

        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 1)) {
            try shifts.endActiveShift(at: at(3_600))
        }
        #expect(shift.isActive, "The shift is still running")
        #expect(shift.endedAt == nil)
        #expect(
            shift.activeDeliveries.map(\.state) == [.accepted],
            "The delivery is neither silently delivered nor silently discarded"
        )
    }

    @Test("A shift is blocked until every one of several deliveries is resolved")
    func refusesToEndUntilEveryDeliveryIsResolved() throws {
        let (context, shift) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        let first = try service.startDelivery(at: at(300))
        let second = try service.startDelivery(at: at(600))
        let third = try service.startDelivery(at: at(900))

        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 3)) {
            try shifts.endActiveShift(at: at(3_600))
        }

        try service.markArrivedAtPickup(first, at: at(1_200))
        try service.markPickedUp(first, at: at(1_500))
        try service.markDelivered(first, at: at(1_800))

        #expect(
            throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 2),
            "Finishing one of three still leaves two that happened"
        ) {
            try shifts.endActiveShift(at: at(3_600))
        }

        try service.cancelDelivery(second, at: at(2_100))

        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 1)) {
            try shifts.endActiveShift(at: at(3_600))
        }

        try service.markArrivedAtPickup(third, at: at(2_400))
        try service.markPickedUp(third, at: at(2_700))
        try service.markDelivered(third, at: at(3_000))
        try shifts.endActiveShift(at: at(3_600))

        #expect(shift.endedAt == at(3_600))
        #expect(shift.deliveries.count == 3, "Every delivery stays in the shift")
        #expect(shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 1))
    }

    @Test("The refusal names how many deliveries are still running")
    func theRefusalIsPluralised() {
        #expect(
            ShiftLifecycleError.activeDeliveriesInProgress(count: 1).errorDescription
                == "A delivery is still in progress. Mark it delivered or cancel it before ending the shift."
        )
        let several = ShiftLifecycleError.activeDeliveriesInProgress(count: 3).errorDescription
        #expect(several?.hasPrefix("3 deliveries are still in progress.") == true, "Got: \(several ?? "nil")")
    }

    @Test("The shift ends once the delivery is resolved", arguments: [true, false])
    func endsOnceTheDeliveryIsResolved(byDelivering: Bool) throws {
        let (context, shift) = try makeRunningShift()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(delivery, at: at(600))

        if byDelivering {
            try deliveries.markPickedUp(delivery, at: at(900))
            try deliveries.markDelivered(delivery, at: at(1_200))
        } else {
            try deliveries.cancelDelivery(delivery, at: at(1_200))
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
        let cancelled = try deliveries.startDelivery(at: at(300))
        try deliveries.markArrivedAtPickup(cancelled, at: at(600))
        try deliveries.cancelDelivery(cancelled, at: at(900))
        try shifts.endActiveShift(at: at(3_600))

        try shifts.startShift(at: at(7_200))
        let kept = try deliveries.startDelivery(at: at(7_500))
        try deliveries.markArrivedAtPickup(kept, at: at(7_800))
        try deliveries.markPickedUp(kept, at: at(8_100))
        try deliveries.markDelivered(kept, at: at(8_400))
        let keptDeliveryID = kept.id
        try shifts.endActiveShift(at: at(10_800))

        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)

        try shifts.deleteCompletedShift(removed)

        let remaining = try context.fetch(FetchDescriptor<Delivery>())
        #expect(remaining.count == 1, "The deleted shift's deliveries go with it rather than being orphaned")
        #expect(remaining.first?.id == keptDeliveryID)
        #expect(remaining.allSatisfy { $0.shift != nil }, "No delivery is left without a shift")
    }

    // MARK: Data the service did not create

    @Test("Several unfinished deliveries written straight into the store are ordinary, not an anomaly")
    func severalActiveDeliveriesAreOrdinary() throws {
        let (context, shift) = try makeRunningShift()
        // Written straight into the store rather than through the service, so
        // the rules hold for data the service did not create.
        let older = Delivery(shift: shift, acceptedAt: at(300))
        let newer = Delivery(shift: shift, acceptedAt: at(900))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let service = DeliveryService(context: context)

        #expect(try service.activeDeliveries(for: shift).map(\.id) == [older.id, newer.id])
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [older.id, newer.id], "Repeatable")

        // Both can be advanced, independently, and a third can still start.
        try service.markArrivedAtPickup(newer, at: at(1_200))
        #expect(older.state == .accepted)
        let third = try service.startDelivery(at: at(1_500))
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [older.id, newer.id, third.id])
    }
}
