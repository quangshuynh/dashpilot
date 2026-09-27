import Foundation
import Testing
@testable import DashPilot

/// Which delivery Park works on under the pickup workflow, as a pure rule over
/// numbers and states.
///
/// The rule reads nothing but each delivery's number and state, so every case
/// here is two lists of plain values and the answer.
@Suite("Park pickup selection")
struct ParkPickupSelectionTests {
    /// A delivery as the rule sees it.
    private struct Candidate: Equatable {
        let number: Int
        let state: DeliveryState
    }

    private func select(_ candidates: [Candidate], stacked: Bool) -> ParkPickupSelection<Candidate> {
        ParkPickupSelection.select(
            among: candidates,
            handlesStackedOrdersInOrder: stacked,
            number: \.number,
            state: \.state
        )
    }

    private func target(_ candidates: [Candidate], stacked: Bool) -> Int? {
        guard case let .target(chosen) = select(candidates, stacked: stacked) else { return nil }
        return chosen.number
    }

    // MARK: One delivery

    @Test("One delivery waiting for its pickup is chosen, whether it is heading there or already there")
    func oneDeliveryAwaitingPickup() {
        for stacked in [false, true] {
            #expect(target([Candidate(number: 1, state: .accepted)], stacked: stacked) == 1)
            #expect(target([Candidate(number: 1, state: .arrivedAtPickup)], stacked: stacked) == 1)
        }
    }

    @Test("A delivery already in the car, or finished, is never chosen")
    func noneAwaitingPickup() {
        for state in [DeliveryState.pickedUp, .delivered, .cancelled] {
            for stacked in [false, true] {
                guard case .noneAwaitingPickup = select([Candidate(number: 1, state: state)], stacked: stacked) else {
                    Issue.record("\(state) must never be chosen")
                    continue
                }
            }
        }
        guard case .noneAwaitingPickup = select([], stacked: true) else {
            Issue.record("Nothing in progress, nothing chosen")
            return
        }
    }

    // MARK: The brief's cases, with stacked orders handled

    @Test("D3 Accepted, D4 Accepted: D3")
    func bothAccepted() {
        #expect(target([Candidate(number: 3, state: .accepted), Candidate(number: 4, state: .accepted)], stacked: true) == 3)
    }

    @Test("D3 Arrived, D4 Accepted: D3, so Resume continues it")
    func firstArrived() {
        #expect(
            target([Candidate(number: 3, state: .arrivedAtPickup), Candidate(number: 4, state: .accepted)], stacked: true)
                == 3
        )
    }

    @Test("D3 Picked Up, D4 Accepted: D4")
    func firstInTheCar() {
        #expect(target([Candidate(number: 3, state: .pickedUp), Candidate(number: 4, state: .accepted)], stacked: true) == 4)
    }

    @Test("D3 finished, D4 Accepted: D4")
    func firstFinished() {
        for finished in [DeliveryState.delivered, .cancelled] {
            #expect(target([Candidate(number: 3, state: finished), Candidate(number: 4, state: .accepted)], stacked: true) == 4)
        }
    }

    /// The honest deterministic answer: the rule orders by number and nothing
    /// else, so the lower number is chosen and the other waits for the next
    /// Park.
    @Test("D3 Arrived, D4 Arrived: D3")
    func bothArrived() {
        #expect(
            target(
                [Candidate(number: 3, state: .arrivedAtPickup), Candidate(number: 4, state: .arrivedAtPickup)],
                stacked: true
            ) == 3
        )
    }

    @Test("Three orders: the lowest number still waiting for its pickup, whatever state the others are in")
    func threeOrders() {
        let candidates = [
            Candidate(number: 1, state: .pickedUp),
            Candidate(number: 2, state: .accepted),
            Candidate(number: 3, state: .arrivedAtPickup)
        ]
        #expect(target(candidates, stacked: true) == 2)
    }

    /// The rule sorts by number itself, so neither a store's fetch order nor a
    /// screen's can move the answer.
    @Test("The order the deliveries are handed over in does not matter")
    func orderIndependent() {
        let candidates = [
            Candidate(number: 5, state: .accepted),
            Candidate(number: 2, state: .pickedUp),
            Candidate(number: 4, state: .accepted),
            Candidate(number: 3, state: .accepted)
        ]
        let expected = target(candidates, stacked: true)
        #expect(expected == 3)
        for permutation in [candidates.reversed(), candidates.shuffled(), candidates.shuffled()] {
            #expect(target(Array(permutation), stacked: true) == expected)
        }
    }

    // MARK: Stacked orders not handled

    @Test("Without stacked orders, two in progress choose nothing and say how many")
    func stackedOff() {
        for pair in [
            [Candidate(number: 3, state: .accepted), Candidate(number: 4, state: .accepted)],
            [Candidate(number: 3, state: .pickedUp), Candidate(number: 4, state: .accepted)],
            [Candidate(number: 3, state: .arrivedAtPickup), Candidate(number: 4, state: .arrivedAtPickup)]
        ] {
            guard case .stackedNotHandled(inProgress: 2) = select(pair, stacked: false) else {
                Issue.record("Two in progress with stacked orders off must choose nothing: \(pair)")
                continue
            }
        }
    }

    @Test("Without stacked orders, a finished delivery beside the one in progress does not count")
    func stackedOffCountsOnlyInProgress() {
        let candidates = [Candidate(number: 3, state: .delivered), Candidate(number: 4, state: .accepted)]
        #expect(target(candidates, stacked: false) == 4)
    }

    @Test("Without stacked orders, orders all in the car are a stop at a customer, and nothing is said")
    func stackedOffAtACustomer() {
        let candidates = [Candidate(number: 3, state: .pickedUp), Candidate(number: 4, state: .pickedUp)]
        guard case .noneAwaitingPickup = select(candidates, stacked: false) else {
            Issue.record("Nothing is waiting for a pickup, so there is nothing to explain")
            return
        }
    }
}
