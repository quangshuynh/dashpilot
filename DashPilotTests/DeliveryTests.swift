import Foundation
import Testing
@testable import DashPilot

/// The delivery model's own rules: which transitions it accepts, which it
/// refuses, and what it derives from the timestamps it holds.
///
/// Every date here is an explicit offset from one fixed instant, so nothing in
/// this suite depends on when it runs.
@MainActor
@Suite("Delivery lifecycle")
struct DeliveryTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// A delivery attached to a running shift, without a store: the model's
    /// rules do not need one.
    private func makeDelivery(acceptedAfter seconds: TimeInterval = 0) -> Delivery {
        Delivery(shift: Shift(startedAt: start), acceptedAt: start.addingTimeInterval(seconds))
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    // MARK: State

    @Test("A new delivery is accepted, and active")
    func startsAccepted() {
        let delivery = makeDelivery()

        #expect(delivery.state == .accepted)
        #expect(delivery.isActive)
        #expect(delivery.acceptedAt == start)
        #expect(delivery.arrivedAtPickupAt == nil)
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.cancelledAt == nil)
    }

    @Test("The state is read from the timestamps at every step")
    func derivesStateFromTimestamps() throws {
        let delivery = makeDelivery()

        try delivery.markArrivedAtPickup(at: at(300))
        #expect(delivery.state == .arrivedAtPickup)

        try delivery.markPickedUp(at: at(600))
        #expect(delivery.state == .pickedUp)

        try delivery.markDelivered(at: at(1_200))
        #expect(delivery.state == .delivered)
        #expect(!delivery.isActive)
    }

    @Test("Each event stores the exact timestamp it was given")
    func storesEachTimestamp() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(660))
        try delivery.markDelivered(at: at(1_500))

        #expect(delivery.acceptedAt == start)
        #expect(delivery.arrivedAtPickupAt == at(300))
        #expect(delivery.pickedUpAt == at(660))
        #expect(delivery.deliveredAt == at(1_500))
    }

    @Test("A cancellation is the state, whatever happened before it")
    func cancellationWins() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(600))
        try delivery.cancel(at: at(900))

        #expect(delivery.state == .cancelled)
        #expect(!delivery.isActive)
        // The events that genuinely happened are still there. A cancellation
        // records an ending; it does not rewrite the history behind it.
        #expect(delivery.arrivedAtPickupAt == at(300))
        #expect(delivery.pickedUpAt == at(600))
        #expect(delivery.cancelledAt == at(900))
    }

    // MARK: Order

    @Test("Picking up before arriving is refused")
    func refusesPickupBeforeArrival() {
        let delivery = makeDelivery()

        #expect(throws: DeliveryError.outOfOrder(missing: .arrivedAtPickup)) {
            try delivery.markPickedUp(at: at(300))
        }
        #expect(delivery.state == .accepted)
        #expect(delivery.pickedUpAt == nil)
    }

    @Test("Delivering before picking up is refused, from either earlier state", arguments: [true, false])
    func refusesDeliveryBeforePickup(afterArriving: Bool) throws {
        let delivery = makeDelivery()
        if afterArriving {
            try delivery.markArrivedAtPickup(at: at(300))
        }

        #expect(throws: DeliveryError.outOfOrder(missing: .pickedUp)) {
            try delivery.markDelivered(at: at(600))
        }
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.state == (afterArriving ? .arrivedAtPickup : .accepted))
    }

    @Test("Recording arrival twice is refused")
    func refusesRepeatedArrival() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))

        #expect(throws: DeliveryError.alreadyRecorded(.arrivedAtPickup)) {
            try delivery.markArrivedAtPickup(at: at(400))
        }
        #expect(delivery.arrivedAtPickupAt == at(300), "The first recorded time is the one that happened")
    }

    @Test("Recording pickup twice is refused")
    func refusesRepeatedPickup() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(600))

        #expect(throws: DeliveryError.alreadyRecorded(.pickedUp)) {
            try delivery.markPickedUp(at: at(700))
        }
        #expect(delivery.pickedUpAt == at(600))
    }

    @Test("Going back a step on a delivery already further along is refused")
    func refusesArrivalAfterPickup() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(600))

        #expect(throws: DeliveryError.alreadyRecorded(.arrivedAtPickup)) {
            try delivery.markArrivedAtPickup(at: at(700))
        }
        #expect(delivery.state == .pickedUp)
    }

    // MARK: Terminal states

    @Test("A delivered delivery cannot transition again")
    func deliveredIsTerminal() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(600))
        try delivery.markDelivered(at: at(1_200))

        #expect(throws: DeliveryError.alreadyFinished(.delivered)) {
            try delivery.markDelivered(at: at(1_500))
        }
        #expect(throws: DeliveryError.alreadyFinished(.delivered)) {
            try delivery.markPickedUp(at: at(1_500))
        }
        #expect(throws: DeliveryError.alreadyFinished(.delivered)) {
            try delivery.cancel(at: at(1_500))
        }
        #expect(delivery.deliveredAt == at(1_200))
        #expect(delivery.cancelledAt == nil)
    }

    @Test("A cancelled delivery cannot be continued or completed")
    func cancelledIsTerminal() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.cancel(at: at(600))

        #expect(throws: DeliveryError.alreadyFinished(.cancelled)) {
            try delivery.markPickedUp(at: at(900))
        }
        #expect(throws: DeliveryError.alreadyFinished(.cancelled)) {
            try delivery.markDelivered(at: at(900))
        }
        #expect(throws: DeliveryError.alreadyFinished(.cancelled)) {
            try delivery.cancel(at: at(900))
        }
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.deliveredAt == nil, "A cancelled delivery must never become a completed one")
    }

    @Test("Cancelling is allowed from every active state", arguments: [DeliveryState.accepted, .arrivedAtPickup, .pickedUp])
    func cancelsFromAnyActiveState(state: DeliveryState) throws {
        let delivery = makeDelivery()
        if state != .accepted {
            try delivery.markArrivedAtPickup(at: at(300))
        }
        if state == .pickedUp {
            try delivery.markPickedUp(at: at(600))
        }
        #expect(delivery.state == state)

        try delivery.cancel(at: at(900))

        #expect(delivery.state == .cancelled)
    }

    // MARK: Backwards clocks

    @Test("An event before the last recorded one is refused")
    func refusesBackwardsTimestamp() throws {
        let delivery = makeDelivery(acceptedAfter: 600)

        #expect(throws: DeliveryError.timestampPrecedesLastEvent) {
            try delivery.markArrivedAtPickup(at: at(300))
        }

        try delivery.markArrivedAtPickup(at: at(900))
        #expect(throws: DeliveryError.timestampPrecedesLastEvent) {
            try delivery.markPickedUp(at: at(800))
        }
        #expect(throws: DeliveryError.timestampPrecedesLastEvent) {
            try delivery.cancel(at: at(800))
        }
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.cancelledAt == nil)
    }

    @Test("An event at exactly the previous instant is allowed")
    func allowsSimultaneousEvents() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: start)
        try delivery.markPickedUp(at: start)
        try delivery.markDelivered(at: start)

        #expect(delivery.state == .delivered)
        #expect(delivery.pickupWait == 0)
        #expect(delivery.completedDuration == 0)
    }

    @Test("The last event is whichever one happened most recently")
    func tracksTheLastEvent() throws {
        let delivery = makeDelivery()
        #expect(delivery.lastEventAt == start)

        try delivery.markArrivedAtPickup(at: at(300))
        #expect(delivery.lastEventAt == at(300))

        try delivery.markPickedUp(at: at(600))
        #expect(delivery.lastEventAt == at(600))

        try delivery.markDelivered(at: at(1_200))
        #expect(delivery.lastEventAt == at(1_200))
    }

    // MARK: Derived intervals

    @Test("The pickup wait is the time between arriving and collecting")
    func derivesPickupWait() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(1_020))

        #expect(delivery.pickupWait == 720)
    }

    @Test("A delivery missing either end of the wait reports none")
    func withholdsAnIncompletePickupWait() throws {
        let waiting = makeDelivery()
        try waiting.markArrivedAtPickup(at: at(300))
        #expect(waiting.pickupWait == nil, "A driver still waiting has no completed wait")

        let cancelledEarly = makeDelivery()
        try cancelledEarly.cancel(at: at(300))
        #expect(cancelledEarly.pickupWait == nil, "A delivery cancelled before arriving never waited")
    }

    @Test("The delivery duration runs from acceptance to completion")
    func derivesCompletedDuration() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: at(300))
        try delivery.markPickedUp(at: at(600))
        try delivery.markDelivered(at: at(1_800))

        #expect(delivery.completedDuration == 1_800)
    }

    @Test("Only a delivered delivery has a delivery duration")
    func withholdsDurationUnlessDelivered() throws {
        let running = makeDelivery()
        try running.markArrivedAtPickup(at: at(300))
        #expect(running.completedDuration == nil)

        let cancelled = makeDelivery()
        try cancelled.markArrivedAtPickup(at: at(300))
        try cancelled.markPickedUp(at: at(600))
        try cancelled.cancel(at: at(900))
        #expect(
            cancelled.completedDuration == nil,
            "A cancelled delivery has an elapsed time, but it is not a delivery duration"
        )
    }
}
