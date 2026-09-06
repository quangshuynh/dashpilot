import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What DashPilot will and will not record when the request arrives without a
/// screen.
///
/// The lifecycle rules themselves are proved in `ShiftServiceTests` and
/// `DeliveryServiceTests` and are not repeated here. What is proved here is
/// that the intent layer reaches those same rules, carries their refusals
/// through, and adds the one rule that only exists off-screen: a spoken step
/// identifies a delivery only while exactly one is running.
///
/// Every operation is given its timestamp, so nothing depends on how long the
/// test took to run.
@MainActor
@Suite("Intent lifecycle service")
struct IntentLifecycleServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeService() throws -> (context: ModelContext, service: IntentLifecycleService) {
        let context = try makeContext()
        return (context, IntentLifecycleService(context: context))
    }

    // MARK: Shift

    @Test("Starting a shift records it and reports the stored start time")
    func startsAShift() throws {
        let (context, service) = try makeService()

        let outcome = try service.startShift(at: start)

        #expect(outcome == .shiftStarted(at: start))
        let shifts = try context.fetch(FetchDescriptor<Shift>())
        #expect(shifts.count == 1)
        #expect(shifts.first?.startedAt == start)
        #expect(shifts.first?.isActive == true)
    }

    @Test("A second shift is refused with the service's own sentence")
    func refusesASecondShift() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)

        #expect(throws: IntentLifecycleError.shift(.shiftAlreadyActive(startedAt: start))) {
            try service.startShift(at: at(60))
        }
        #expect(try context.fetch(FetchDescriptor<Shift>()).count == 1, "A refused start must record nothing")
    }

    @Test("Ending a shift reports how long it ran")
    func endsAShift() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)

        let outcome = try service.endShift(at: at(5_400))

        #expect(outcome == .shiftEnded(duration: 5_400))
        let shift = try context.fetch(FetchDescriptor<Shift>()).first
        #expect(shift?.endedAt == at(5_400))
        #expect(shift?.isActive == false)
    }

    @Test("Ending with no shift running is refused")
    func refusesToEndNothing() throws {
        let (_, service) = try makeService()

        #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
            try service.endShift(at: start)
        }
    }

    @Test("A shift with a delivery still running is not ended by voice either")
    func refusesToEndOverARunningDelivery() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))

        #expect(throws: IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 1))) {
            try service.endShift(at: at(3_600))
        }
        #expect(
            try context.fetch(FetchDescriptor<Shift>()).first?.isActive == true,
            "A refused end must leave the shift running"
        )
    }

    // MARK: Starting a delivery

    @Test("A delivery starts on the running shift and is named and counted")
    func startsADelivery() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)

        let outcome = try service.startDelivery(at: at(300))

        #expect(outcome == .deliveryStarted(number: 1, inProgress: 1))
        let deliveries = try context.fetch(FetchDescriptor<Delivery>())
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.acceptedAt == at(300))
        #expect(deliveries.first?.state == .accepted)
    }

    @Test("A second delivery is started without touching the first")
    func startsASecondDelivery() throws {
        let (_, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))
        try service.recordDeliveryProgress(at: at(400))

        let outcome = try service.startDelivery(at: at(900))

        #expect(outcome == .deliveryStarted(number: 2, inProgress: 2))
    }

    @Test("A delivery cannot start with no shift running")
    func refusesADeliveryWithoutAShift() throws {
        let (context, service) = try makeService()

        #expect(throws: IntentLifecycleError.delivery(.noActiveShift)) {
            try service.startDelivery(at: start)
        }
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
    }

    // MARK: Recording the next step

    @Test("The one delivery in progress advances one step at a time, in order")
    func advancesTheOnlyDelivery() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))

        #expect(try service.recordDeliveryProgress(at: at(600)) == .deliveryEventRecorded(number: 1, state: .arrivedAtPickup))
        #expect(try service.recordDeliveryProgress(at: at(900)) == .deliveryEventRecorded(number: 1, state: .pickedUp))
        #expect(try service.recordDeliveryProgress(at: at(1_500)) == .deliveryEventRecorded(number: 1, state: .delivered))

        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(delivery.pickedUpAt == at(900))
        #expect(delivery.deliveredAt == at(1_500))
        #expect(delivery.state == .delivered)
    }

    @Test("A finished delivery leaves nothing to record")
    func refusesOnceTheDeliveryIsFinished() throws {
        let (_, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))
        try service.recordDeliveryProgress(at: at(600))
        try service.recordDeliveryProgress(at: at(900))
        try service.recordDeliveryProgress(at: at(1_200))

        #expect(throws: IntentLifecycleError.noDeliveryInProgress) {
            try service.recordDeliveryProgress(at: at(1_500))
        }
    }

    @Test("A step asked for with no delivery running is refused")
    func refusesWithNothingRunning() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)

        #expect(throws: IntentLifecycleError.noDeliveryInProgress) {
            try service.recordDeliveryProgress(at: at(300))
        }
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
    }

    @Test("A step asked for with no shift running is refused as the app refuses it")
    func refusesWithNoShift() throws {
        let (_, service) = try makeService()

        #expect(throws: IntentLifecycleError.delivery(.noActiveShift)) {
            try service.recordDeliveryProgress(at: start)
        }
    }

    // MARK: The ambiguity rule

    @Test("Two deliveries in progress refuse the step and neither one moves")
    func refusesWhileTwoDeliveriesRun() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))
        try service.recordDeliveryProgress(at: at(400))
        try service.startDelivery(at: at(900))

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
            try service.recordDeliveryProgress(at: at(1_000))
        }

        let deliveries = try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)
        #expect(deliveries.map(\.state) == [.arrivedAtPickup, .accepted], "A refusal must move neither delivery")
        #expect(deliveries.first?.pickedUpAt == nil)
    }

    @Test("Three in progress name the count they refused over")
    func namesHowManyAreRunning() throws {
        let (_, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))
        try service.startDelivery(at: at(600))
        try service.startDelivery(at: at(900))

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 3)) {
            try service.recordDeliveryProgress(at: at(1_000))
        }
    }

    @Test("The refusal lifts as soon as one delivery is left running")
    func recordsAgainOnceOneRemains() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        let first = try DeliveryService(context: context).startDelivery(at: at(300))
        try service.startDelivery(at: at(600))

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
            try service.recordDeliveryProgress(at: at(700))
        }

        // Resolved in the app, on the delivery the driver actually meant.
        try DeliveryService(context: context).markArrivedAtPickup(first, at: at(800))
        try DeliveryService(context: context).markPickedUp(first, at: at(900))
        try DeliveryService(context: context).markDelivered(first, at: at(1_000))

        #expect(try service.recordDeliveryProgress(at: at(1_100)) == .deliveryEventRecorded(number: 2, state: .arrivedAtPickup))
    }

    @Test("A cancelled delivery is not one the voice step can reach or count")
    func ignoresACancelledDelivery() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        let first = try DeliveryService(context: context).startDelivery(at: at(300))
        try service.startDelivery(at: at(600))
        try DeliveryService(context: context).cancelDelivery(first, at: at(700))

        let outcome = try service.recordDeliveryProgress(at: at(800))

        #expect(outcome == .deliveryEventRecorded(number: 2, state: .arrivedAtPickup))
        #expect(first.state == .cancelled, "A cancelled delivery stays cancelled")
        #expect(first.arrivedAtPickupAt == nil)
    }

    // MARK: What the intents keep out of reach

    @Test("Nothing here records an amount, a place or a cancellation")
    func recordsNoValues() throws {
        let (context, service) = try makeService()
        try service.startShift(at: start)
        try service.startDelivery(at: at(300))
        try service.recordDeliveryProgress(at: at(600))
        try service.recordDeliveryProgress(at: at(900))
        try service.recordDeliveryProgress(at: at(1_200))
        try service.endShift(at: at(1_800))

        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
        #expect(shift.grossEarnings == nil)
        #expect(delivery.grossEarnings == nil)
        #expect(delivery.pickupPlace == nil)
        #expect(delivery.cancelledAt == nil)
        #expect(try context.fetch(FetchDescriptor<PickupPlace>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RouteSample>()).isEmpty)
    }
}
