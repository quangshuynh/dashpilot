import Foundation
import Testing
@testable import DashPilot

/// Taking back an accidental `Delivered`: which state the timestamps that stay
/// describe, which stores are refused, and what the model leaves untouched.
///
/// The derivation is exercised as plain values, because most of the rows it has
/// to judge are ones the lifecycle refuses to produce. What the model can
/// actually be driven into is exercised on a real `Delivery` below.
///
/// Every date is an explicit offset from one fixed instant, so nothing here
/// depends on when it runs.
@MainActor
@Suite("Delivery recovery")
struct DeliveryRecoveryTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A delivery driven through the lifecycle to delivered, without a store.
    private func makeDeliveredDelivery() throws -> Delivery {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))
        return delivery
    }

    // MARK: The state that is restored

    @Test("A delivery delivered after a pickup goes back to heading to the customer")
    func restoresThePickedUpState() throws {
        let recovery = try DeliveryRecovery(
            reopening: DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(900),
                deliveredAt: at(1500)
            )
        )

        #expect(recovery.restoredState == .pickedUp)
        #expect(recovery.restoredState.statusDescription == "Heading to the customer")
    }

    @Test("An arrival with no pickup goes back to waiting at the pickup")
    func restoresTheArrivedState() throws {
        // Unreachable through the app, which refuses a completion before a
        // pickup. It is restored rather than refused because the state it lands
        // in is one the lifecycle supports and a driver can be looking at.
        let recovery = try DeliveryRecovery(
            reopening: DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                deliveredAt: at(1500)
            )
        )

        #expect(recovery.restoredState == .arrivedAtPickup)
    }

    @Test("An acceptance alone goes back to heading to the pickup")
    func restoresTheAcceptedState() throws {
        let recovery = try DeliveryRecovery(
            reopening: DeliveryLifecycleRecord(acceptedAt: at(300), deliveredAt: at(1500))
        )

        #expect(recovery.restoredState == .accepted)
    }

    @Test("Every restored state is one the driver can still act on")
    func restoresOnlyActiveStates() throws {
        let records = [
            DeliveryLifecycleRecord(acceptedAt: at(300), deliveredAt: at(1500)),
            DeliveryLifecycleRecord(acceptedAt: at(300), arrivedAtPickupAt: at(600), deliveredAt: at(1500)),
            DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(900),
                deliveredAt: at(1500)
            )
        ]

        for record in records {
            let recovery = try DeliveryRecovery(reopening: record)
            #expect(recovery.restoredState.isActive)
            #expect(recovery.restoredState.nextAction != nil, "A reopened delivery has a step to take")
        }
    }

    // MARK: What is refused

    @Test("A delivery that was never delivered has nothing to take back")
    func refusesADeliveryThatIsNotDelivered() {
        #expect(throws: DeliveryRecoveryRefusal.notDelivered) {
            try DeliveryRecovery(
                reopening: DeliveryLifecycleRecord(
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(900)
                )
            )
        }
    }

    @Test("A cancelled delivery is refused, and is not treated as an accidental completion")
    func refusesACancelledDelivery() {
        #expect(throws: DeliveryRecoveryRefusal.cancelled) {
            try DeliveryRecovery(
                reopening: DeliveryLifecycleRecord(acceptedAt: at(300), cancelledAt: at(700))
            )
        }

        // Cancellation wins even where a completion is also recorded, which is a
        // row the transitions refuse to produce: the delivery is terminal for a
        // reason this version has not decided how to undo.
        #expect(throws: DeliveryRecoveryRefusal.cancelled) {
            try DeliveryRecovery(
                reopening: DeliveryLifecycleRecord(
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    pickedUpAt: at(900),
                    deliveredAt: at(1500),
                    cancelledAt: at(1600)
                )
            )
        }
    }

    @Test("A pickup with no arrival before it is refused rather than restored")
    func refusesAPickupWithNoArrival() {
        #expect(throws: DeliveryRecoveryRefusal.pickedUpWithoutArrival) {
            try DeliveryRecovery(
                reopening: DeliveryLifecycleRecord(
                    acceptedAt: at(300),
                    pickedUpAt: at(900),
                    deliveredAt: at(1500)
                )
            )
        }
    }

    @Test("Timestamps that run backwards are refused rather than guessed at")
    func refusesContradictoryTimestamps() {
        let contradictory = [
            // The arrival precedes the acceptance.
            DeliveryLifecycleRecord(acceptedAt: at(900), arrivedAtPickupAt: at(600), deliveredAt: at(1500)),
            // The pickup precedes the arrival.
            DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(900),
                pickedUpAt: at(600),
                deliveredAt: at(1500)
            ),
            // The completion precedes the pickup it followed. The row says two
            // contradictory things and does not say which is the mistake.
            DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(1500),
                deliveredAt: at(900)
            ),
            // The completion precedes the acceptance.
            DeliveryLifecycleRecord(acceptedAt: at(900), deliveredAt: at(300))
        ]

        for record in contradictory {
            #expect(throws: DeliveryRecoveryRefusal.timestampsOutOfOrder) {
                try DeliveryRecovery(reopening: record)
            }
        }
    }

    @Test("Equal timestamps are not backwards")
    func allowsSimultaneousEvents() throws {
        // A clamped event records a zero-length interval, which the lifecycle
        // produces on a backwards device clock. It is a real row and stays
        // recoverable.
        let recovery = try DeliveryRecovery(
            reopening: DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(300),
                pickedUpAt: at(300),
                deliveredAt: at(300)
            )
        )

        #expect(recovery.restoredState == .pickedUp)
    }

    // MARK: The model's own operation

    @Test("Reopening removes the delivered timestamp and no other")
    func clearsOnlyTheDeliveredTimestamp() throws {
        let delivery = try makeDeliveredDelivery()

        let restored = try delivery.reopenFromDelivered()

        #expect(restored == .pickedUp)
        #expect(delivery.state == .pickedUp)
        #expect(delivery.isActive)
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.cancelledAt == nil)
        // Byte for byte, not merely present: a recovery that rewrote an event
        // the driver recorded would be correcting more than the mistake.
        #expect(delivery.acceptedAt == at(300))
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(delivery.pickedUpAt == at(900))
    }

    @Test("The derived readings follow the state back")
    func derivedReadingsFollowTheRestoredState() throws {
        let delivery = try makeDeliveredDelivery()

        #expect(delivery.completedDuration == 1200)
        #expect(DeliveryActiveInterval(delivery).end == at(1500))
        #expect(delivery.lastEventAt == at(1500))

        try delivery.reopenFromDelivered()

        #expect(delivery.completedDuration == nil, "A delivery that is not delivered has no duration to state")
        #expect(DeliveryActiveInterval(delivery).isUnfinished, "It is open again, exactly as any unfinished delivery is")
        #expect(delivery.lastEventAt == at(900), "The next event orders against the pickup again")
        // The wait is between two events neither of which moved.
        #expect(delivery.pickupWait == 300)
    }

    @Test("A recorded amount is kept, and the expectation beside it")
    func keepsBothAmounts() throws {
        let delivery = try makeDeliveredDelivery()
        try delivery.setGrossEarnings(Money(minorUnits: 925))

        try delivery.reopenFromDelivered()

        #expect(delivery.grossEarnings == Money(minorUnits: 925), "Money the driver recorded is not deleted by a lifecycle correction")
        // Recording a *new* amount is still refused while it is active, which is
        // a rule about writing rather than about holding.
        #expect(throws: DeliveryError.deliveryNotFinished) {
            try delivery.setGrossEarnings(Money(minorUnits: 1000))
        }
        // A rate needs a completion, so the delivery states none while reopened.
        #expect(delivery.grossPerDeliveryHour == .unavailable(.deliveryNotCompleted))
    }

    @Test("An expectation survives, and can be corrected again while the delivery is open")
    func keepsTheExpectation() throws {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.setExpectedEarnings(Money(minorUnits: 850))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))

        try delivery.reopenFromDelivered()

        #expect(delivery.expectedEarnings == Money(minorUnits: 850))
        #expect(delivery.hasUnconfirmedExpectedEarnings)
        try delivery.setExpectedEarnings(Money(minorUnits: 900))
        #expect(delivery.expectedEarnings == Money(minorUnits: 900))
    }

    @Test("The pickup place is untouched")
    func keepsThePickupPlace() throws {
        let delivery = try makeDeliveredDelivery()
        let place = try PickupPlace(name: PickupPlaceName("Nowhere Noodles"), createdAt: at(0))
        delivery.setPickupPlace(place)

        try delivery.reopenFromDelivered()

        #expect(delivery.pickupPlace?.id == place.id)
    }

    @Test("A reopened delivery advances from where it was left")
    func advancesAgainFromTheRestoredState() throws {
        let delivery = try makeDeliveredDelivery()
        try delivery.reopenFromDelivered()

        #expect(delivery.state.nextAction == .complete)
        // The step before it is already recorded and is not repeated.
        #expect(throws: DeliveryError.alreadyRecorded(.pickedUp)) {
            try delivery.markPickedUp(at: at(1800))
        }

        try delivery.markDelivered(at: at(1800))

        #expect(delivery.state == .delivered)
        #expect(delivery.deliveredAt == at(1800), "The new completion is the one the driver recorded")
        #expect(delivery.pickedUpAt == at(900), "and the events before it never moved")
    }

    @Test("Reopening twice is refused the second time and changes nothing")
    func refusesASecondReopen() throws {
        let delivery = try makeDeliveredDelivery()
        try delivery.reopenFromDelivered()

        #expect(throws: DeliveryRecoveryRefusal.notDelivered) {
            try delivery.reopenFromDelivered()
        }
        #expect(delivery.state == .pickedUp)
        #expect(delivery.pickedUpAt == at(900))
    }

    @Test("A cancelled delivery refuses the model's operation too")
    func refusesReopeningACancelledDelivery() throws {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.cancel(at: at(700))

        #expect(throws: DeliveryRecoveryRefusal.cancelled) {
            try delivery.reopenFromDelivered()
        }
        #expect(delivery.state == .cancelled)
        #expect(delivery.cancelledAt == at(700), "Nothing about a cancellation moves")
    }

    @Test("The record read from a delivery is the delivery's own timestamps")
    func readsTheRecordFromTheDelivery() throws {
        let delivery = try makeDeliveredDelivery()

        #expect(
            DeliveryLifecycleRecord(delivery) == DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(900),
                deliveredAt: at(1500)
            )
        )
    }
}
