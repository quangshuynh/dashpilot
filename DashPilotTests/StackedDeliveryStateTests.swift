import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a shift holding several deliveries at once says about each of them:
/// which delivery, what it is doing, and what it is waiting for.
///
/// Nothing here is a new rule. `DeliveryState` already decides what comes next,
/// `NumberedDelivery` already decides what a delivery is called and
/// `DeliveryGroup` already decides which cards belong together; these are the
/// combinations a driver actually meets, asserted together, because the failure
/// this area has is not a wrong rule but two deliveries reading as one.
///
/// Every date is an explicit offset from one fixed instant.
@MainActor
@Suite("Stacked delivery state")
struct StackedDeliveryStateTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func runningShift() throws -> (shift: Shift, deliveries: DeliveryService) {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        return (shift, DeliveryService(context: context))
    }

    /// What each active card exposes: its number, its state and its next step.
    private func cards(of shift: Shift) -> [(title: String, state: String, next: String?)] {
        shift.numberedActiveDeliveries.map { numbered in
            (
                numbered.title,
                numbered.delivery.state.statusDescription,
                numbered.delivery.state.nextAction?.nextStepStatement
            )
        }
    }

    // MARK: The combinations a stacked driver meets

    @Test("Accepted beside arrived: two states, two steps")
    func acceptedBesideArrived() throws {
        let (shift, deliveries) = try runningShift()
        let waiting = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(waiting, at: at(120))
        _ = try deliveries.startDelivery(at: at(180))

        #expect(cards(of: shift).map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(cards(of: shift).map(\.state) == ["Waiting at the pickup", "Heading to the pickup"])
        #expect(cards(of: shift).map(\.next) == ["Next: Picked Up", "Next: Arrived at Pickup"])
    }

    @Test("Arrived beside picked up: the later delivery can be the further along")
    func arrivedBesidePickedUp() throws {
        let (shift, deliveries) = try runningShift()
        let waiting = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(waiting, at: at(120))

        let carrying = try deliveries.startDelivery(at: at(180))
        try deliveries.markArrivedAtPickup(carrying, at: at(240))
        try deliveries.markPickedUp(carrying, at: at(300))

        #expect(cards(of: shift).map(\.state) == ["Waiting at the pickup", "Heading to the customer"])
        #expect(cards(of: shift).map(\.next) == ["Next: Picked Up", "Next: Delivered"])
    }

    @Test("Two accepted deliveries are two cards saying the same thing about two orders")
    func twoAccepted() throws {
        let (shift, deliveries) = try runningShift()
        _ = try deliveries.startDelivery(at: at(60))
        _ = try deliveries.startDelivery(at: at(120))

        #expect(cards(of: shift).map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(cards(of: shift).map(\.state) == ["Heading to the pickup", "Heading to the pickup"])
        #expect(cards(of: shift).map(\.next) == ["Next: Arrived at Pickup", "Next: Arrived at Pickup"])
        // Identical words, different records. The number is the only thing
        // telling them apart, which is why every control carries it.
        #expect(Set(shift.numberedActiveDeliveries.map(\.id)).count == 2)
    }

    @Test("Two picked-up deliveries are both offered the completion, each for itself")
    func twoPickedUp() throws {
        let (shift, deliveries) = try runningShift()
        for offset in [60.0, 180.0] {
            let delivery = try deliveries.startDelivery(at: at(offset))
            try deliveries.markArrivedAtPickup(delivery, at: at(offset + 20))
            try deliveries.markPickedUp(delivery, at: at(offset + 40))
        }

        #expect(cards(of: shift).map(\.next) == ["Next: Delivered", "Next: Delivered"])

        let spoken = shift.numberedActiveDeliveries.map { $0.spokenLabel(for: .complete) }
        #expect(spoken == ["Delivery 1. Mark delivery completed", "Delivery 2. Mark delivery completed"])
    }

    @Test("A delivery that finishes leaves the active set and its siblings do not move")
    func terminalDeliveryLeavesTheActiveSet() throws {
        let (shift, deliveries) = try runningShift()
        let finishing = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(finishing, at: at(120))
        try deliveries.markPickedUp(finishing, at: at(180))
        let waiting = try deliveries.startDelivery(at: at(240))
        try deliveries.markArrivedAtPickup(waiting, at: at(300))

        #expect(cards(of: shift).count == 2)

        try deliveries.markDelivered(finishing, at: at(360))

        #expect(cards(of: shift).map(\.title) == ["Delivery 2"])
        #expect(cards(of: shift).map(\.next) == ["Next: Picked Up"])
        // The numbering runs over the shift rather than over what is on screen,
        // so the survivor keeps the name it already had.
        #expect(shift.numberedDeliveries.map(\.title) == ["Delivery 1", "Delivery 2"])
    }

    @Test("A cancellation leaves the active set the same way a completion does")
    func cancelledDeliveryLeavesTheActiveSet() throws {
        let (shift, deliveries) = try runningShift()
        let cancelling = try deliveries.startDelivery(at: at(60))
        _ = try deliveries.startDelivery(at: at(120))

        try deliveries.cancelDelivery(cancelling, at: at(180))

        #expect(cards(of: shift).map(\.title) == ["Delivery 2"])
        #expect(shift.numberedDeliveries.count == 2, "It is still one of the shift's deliveries")
    }

    // MARK: Numbering and grouping

    @Test("Numbers are stable as the deliveries around them advance and finish")
    func numberingIsStable() throws {
        let (shift, deliveries) = try runningShift()
        let first = try deliveries.startDelivery(at: at(60))
        let second = try deliveries.startDelivery(at: at(120))
        let third = try deliveries.startDelivery(at: at(180))

        let before = shift.numberedDeliveries.map { ($0.id, $0.number) }

        try deliveries.markArrivedAtPickup(second, at: at(240))
        try deliveries.markArrivedAtPickup(third, at: at(300))
        try deliveries.markPickedUp(third, at: at(360))
        try deliveries.cancelDelivery(first, at: at(420))

        let after = shift.numberedDeliveries.map { ($0.id, $0.number) }
        #expect(before.map(\.0) == after.map(\.0))
        #expect(before.map(\.1) == after.map(\.1))
        #expect(after.map(\.1) == [1, 2, 3])
    }

    @Test("Grouping survives one delivery of an offer advancing past its sibling")
    func groupMembershipIsPreserved() throws {
        let (shift, deliveries) = try runningShift()
        let pair = try deliveries.startOffer(deliveryCount: 2, at: at(60)).deliveriesInOrder
        #expect(pair.count == 2)
        try deliveries.markArrivedAtPickup(pair[0], at: at(120))

        let groups = DeliveryGroup.grouping(shift.numberedActiveDeliveries, within: shift.numberedOffers)

        #expect(groups.count == 1, "Both cards still belong to the one offer they arrived in")
        #expect(groups[0].isGrouped)
        #expect(groups[0].deliveries.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(
            groups[0].deliveries.map { $0.delivery.state.nextAction?.nextStepStatement }
                == ["Next: Picked Up", "Next: Arrived at Pickup"],
            "A group is a heading and a sequence: each delivery keeps its own next step"
        )

        // Finishing one leaves the other in its group rather than promoting it
        // out of one.
        try deliveries.markPickedUp(pair[0], at: at(180))
        try deliveries.markDelivered(pair[0], at: at(240))

        let remaining = DeliveryGroup.grouping(shift.numberedActiveDeliveries, within: shift.numberedOffers)
        #expect(remaining.count == 1)
        #expect(remaining[0].deliveries.map(\.title) == ["Delivery 2"])
        #expect(remaining[0].offer?.number == 1)
        #expect(
            remaining[0].offer?.remainingStatement != nil,
            "The heading says how much of the offer is still running"
        )
    }

    @Test("Two offers keep their own membership while both are running")
    func twoOffersKeepTheirOwnMembership() throws {
        let (shift, deliveries) = try runningShift()
        let pair = try deliveries.startOffer(deliveryCount: 2, at: at(60)).deliveriesInOrder
        _ = try deliveries.startDelivery(at: at(120))
        try deliveries.markArrivedAtPickup(pair[1], at: at(180))

        let groups = DeliveryGroup.grouping(shift.numberedActiveDeliveries, within: shift.numberedOffers)

        #expect(groups.count == 2)
        #expect(groups[0].deliveries.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(groups[0].isGrouped)
        #expect(groups[1].deliveries.map(\.title) == ["Delivery 3"])
        #expect(groups[1].isGrouped == false, "An offer of one is the ordinary case and gets no heading")
    }

    // MARK: Every card exposes a valid next action

    @Test("Every active delivery exposes exactly the step its state allows")
    func everyCardExposesItsOwnValidStep() throws {
        let (shift, deliveries) = try runningShift()

        let heading = try deliveries.startDelivery(at: at(60))
        let waiting = try deliveries.startDelivery(at: at(120))
        try deliveries.markArrivedAtPickup(waiting, at: at(180))
        let carrying = try deliveries.startDelivery(at: at(240))
        try deliveries.markArrivedAtPickup(carrying, at: at(300))
        try deliveries.markPickedUp(carrying, at: at(360))

        for numbered in shift.numberedActiveDeliveries {
            let action = try #require(numbered.delivery.state.nextAction)
            #expect(action == numbered.delivery.state.nextAction)
            #expect(action.nextStepStatement == "Next: \(action.title)")
            #expect(numbered.spokenLabel(for: action).hasPrefix(numbered.title))
            #expect(action.spokenNextStep.lowercased().contains(action.spokenLabel.lowercased()))
        }

        #expect(
            shift.numberedActiveDeliveries.map { $0.delivery.state.nextAction } == [
                .arriveAtPickup, .pickUp, .complete
            ]
        )
        #expect([heading, waiting, carrying].map(\.state) == [.accepted, .arrivedAtPickup, .pickedUp])
    }

    @Test("The compact state says the same thing as the long one, shorter")
    func theCompactStateIsTheSameClaim() {
        #expect(DeliveryState.accepted.compactStatusDescription == "To pickup")
        #expect(DeliveryState.arrivedAtPickup.compactStatusDescription == "At pickup")
        #expect(DeliveryState.pickedUp.compactStatusDescription == "To customer")

        for state in DeliveryState.allCases {
            let compact = state.compactStatusDescription
            #expect(!compact.isEmpty)
            #expect(
                compact.count <= state.statusDescription.count,
                "The compact form exists to be shorter: \(compact) vs \(state.statusDescription)"
            )
        }
        #expect(
            Set(DeliveryState.allCases.map(\.compactStatusDescription)).count == DeliveryState.allCases.count,
            "Two states must never share a word, or a card would say nothing"
        )
    }
}
