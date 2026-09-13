import Foundation
import Testing
@testable import DashPilot

/// One offer can contain several deliveries, and this is what that does and does
/// not change.
///
/// The domain half: how an offer is built, what state it derives from the
/// deliveries it holds, and how a screen arranges them. The store half is in
/// `DeliveryOfferPersistenceTests`, and the service half in
/// `DeliveryOfferServiceTests`.
///
/// Every timestamp is invented.
@MainActor
@Suite("Delivery grouping")
struct DeliveryGroupingTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func runningShift() -> Shift { Shift(startedAt: start) }

    // MARK: Building an offer

    @Test("An offer of one holds one delivery, which is what a single tap records")
    func offerOfOne() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))

        #expect(recorded.deliveries.count == 1)
        #expect(recorded.offer.deliveryCount == 1)
        #expect(recorded.offer.isGrouped == false, "One delivery is not a group")
        #expect(recorded.offer.acceptedAt == at(300))
        #expect(recorded.offer.shift?.id == shift.id)
        #expect(shift.offersInOrder.map(\.id) == [recorded.offer.id])
    }

    @Test("An offer of two holds two deliveries, each with its own lifecycle")
    func offerOfTwo() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))

        #expect(recorded.deliveries.count == 2)
        #expect(recorded.offer.isGrouped)
        #expect(Set(recorded.deliveries.map(\.id)).count == 2, "Two deliveries, not one recorded twice")

        for delivery in recorded.deliveries {
            #expect(delivery.offer?.id == recorded.offer.id)
            #expect(delivery.shift?.id == shift.id, "The shift is still the delivery's own")
            #expect(delivery.acceptedAt == at(300), "They were accepted in one act")
            #expect(delivery.state == .accepted)
        }
    }

    @Test("An offer is refused below one delivery")
    func refusesEmptyOffer() {
        let shift = runningShift()
        #expect(throws: OfferError.deliveryCountNotPositive) {
            _ = try shift.beginOffer(deliveryCount: 0, at: at(300))
        }
        #expect(throws: OfferError.deliveryCountNotPositive) {
            _ = try shift.beginOffer(deliveryCount: -2, at: at(300))
        }
        #expect(shift.offers.isEmpty, "A refused offer records nothing")
        #expect(shift.deliveries.isEmpty)
    }

    @Test("An offer is refused on a shift that has ended, and before its shift began")
    func refusesImpossibleOffers() throws {
        let ended = runningShift()
        try ended.end(at: at(7_200))
        #expect(throws: OfferError.shiftAlreadyEnded) {
            _ = try ended.beginOffer(deliveryCount: 1, at: at(300))
        }

        let running = runningShift()
        #expect(throws: OfferError.acceptedBeforeShiftStart) {
            _ = try running.beginOffer(deliveryCount: 1, at: at(-60))
        }
    }

    @Test("There is no maximum: how much work was accepted is the driver's fact")
    func noMaximum() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 12, at: at(300))
        #expect(recorded.deliveries.count == 12)
        #expect(recorded.offer.deliveryCount == 12)
    }

    // MARK: Independent lifecycles within one offer

    @Test("One delivery of an offer advances while its sibling waits at the pickup")
    func siblingsAdvanceIndependently() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))
        let first = recorded.deliveries[0]
        let second = recorded.deliveries[1]

        try first.markArrivedAtPickup(at: at(600))
        try first.markPickedUp(at: at(900))
        try second.markArrivedAtPickup(at: at(700))

        #expect(first.state == .pickedUp)
        #expect(second.state == .arrivedAtPickup, "The sibling advanced on its own and not with it")
        #expect(recorded.offer.state == .inProgress)
        #expect(recorded.offer.isTerminal == false)
    }

    @Test("Completing one delivery leaves its siblings active and its offer in progress")
    func completingOneLeavesSiblingsActive() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 3, at: at(300))
        let finished = recorded.deliveries[0]

        try finished.markArrivedAtPickup(at: at(600))
        try finished.markPickedUp(at: at(900))
        try finished.markDelivered(at: at(1_500))

        #expect(finished.state == .delivered)
        #expect(recorded.deliveries[1].state == .accepted)
        #expect(recorded.deliveries[2].state == .accepted)
        #expect(recorded.offer.activeDeliveries.count == 2)
        #expect(recorded.offer.state == .inProgress, "An offer is not complete because one delivery is")
    }

    @Test("An offer becomes terminal only once every delivery is terminal")
    func offerTerminalOnlyWhenAllAre() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))

        for (index, delivery) in recorded.deliveries.enumerated() {
            try delivery.markArrivedAtPickup(at: at(600))
            try delivery.markPickedUp(at: at(900))
            try delivery.markDelivered(at: at(1_200))
            let expected = index == 0 ? OfferState.inProgress : .completed
            #expect(recorded.offer.state == expected)
        }

        #expect(recorded.offer.isTerminal)
        #expect(recorded.offer.deliverySummary == DeliverySummary(completed: 2, cancelled: 0))
    }

    // MARK: Cancellation semantics

    @Test("Cancelling one delivery cancels only that delivery")
    func cancellingOneIsNotCancellingTheOffer() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))

        try recorded.deliveries[0].cancel(at: at(600))

        #expect(recorded.deliveries[0].state == .cancelled)
        #expect(recorded.deliveries[1].state == .accepted, "The sibling is untouched")
        #expect(recorded.offer.state == .inProgress)
    }

    @Test("An offer whose deliveries all ended cancelled is cancelled")
    func whollyCancelledOffer() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))
        for delivery in recorded.deliveries { try delivery.cancel(at: at(600)) }

        #expect(recorded.offer.state == .cancelled)
        #expect(recorded.offer.isTerminal)
        #expect(recorded.offer.state.historyDescription == "All deliveries cancelled")
    }

    @Test("An offer with one delivered and one cancelled is neither completed nor cancelled")
    func partiallyCompletedOffer() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))

        try recorded.deliveries[0].markArrivedAtPickup(at: at(600))
        try recorded.deliveries[0].markPickedUp(at: at(900))
        try recorded.deliveries[0].markDelivered(at: at(1_200))
        try recorded.deliveries[1].cancel(at: at(1_300))

        #expect(recorded.offer.state == .partiallyCompleted)
        #expect(recorded.offer.isTerminal)
        #expect(recorded.offer.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
    }

    @Test("An offer holding no deliveries is not reported as complete")
    func emptyOfferIsNotComplete() {
        let shift = runningShift()
        let offer = Offer(shift: shift, acceptedAt: at(300))

        #expect(offer.state == .empty)
        #expect(offer.isTerminal == false, "Nothing finished, because nothing was recorded")
    }

    // MARK: Numbering

    @Test("Deliveries keep one number across the shift, and offers are numbered beside them")
    func numberingRunsAcrossTheShift() throws {
        let shift = runningShift()
        let first = try shift.beginOffer(deliveryCount: 2, at: at(300))
        let second = try shift.beginOffer(deliveryCount: 1, at: at(1_800))

        let offers = shift.numberedOffers
        #expect(offers.map(\.number) == [1, 2])
        #expect(offers[0].id == first.offer.id)
        #expect(offers[1].id == second.offer.id)

        // Numbers run over the shift, not restarted per offer: two cards both
        // called "Delivery 1" is the thing the numbering exists to prevent.
        #expect(offers[0].deliveries.map(\.number) == [1, 2])
        #expect(offers[1].deliveries.map(\.number) == [3])
        #expect(offers[0].deliveries.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(offers[1].title == "Offer 2")
    }

    @Test("An offer of two is stated as two deliveries accepted together")
    func groupWording() throws {
        let shift = runningShift()
        _ = try shift.beginOffer(deliveryCount: 2, at: at(300))
        let offer = try #require(shift.numberedOffers.first)

        #expect(offer.groupStatement == "2 deliveries accepted together")
        #expect(offer.spokenGroupStatement == "Offer 1. 2 deliveries accepted together.")
        #expect(offer.remainingStatement == nil, "Nothing has finished, so there is no progress to report")
    }

    @Test("Once one of two has finished, the heading says how many are left")
    func remainingWording() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))
        try recorded.deliveries[0].cancel(at: at(600))

        let offer = try #require(shift.numberedOffers.first)
        #expect(offer.remainingStatement == "1 of 2 still in progress")
    }

    @Test("A delivery accepted with others says so aloud, naming them")
    func spokenGrouping() throws {
        let shift = runningShift()
        _ = try shift.beginOffer(deliveryCount: 3, at: at(300))
        let offer = try #require(shift.numberedOffers.first)

        #expect(
            offer.spokenGrouping(of: offer.deliveries[0])
                == "Part of Offer 1, accepted together with Delivery 2 and Delivery 3"
        )
        #expect(
            offer.spokenGrouping(of: offer.deliveries[1])
                == "Part of Offer 1, accepted together with Delivery 1 and Delivery 3"
        )
        #expect(offer.groupingCaption(of: offer.deliveries[0]) == "Offer 1 · 3 deliveries accepted together")
    }

    @Test("A delivery accepted on its own says nothing about grouping")
    func lonelyDeliverySaysNothing() throws {
        let shift = runningShift()
        _ = try shift.beginOffer(deliveryCount: 1, at: at(300))
        let offer = try #require(shift.numberedOffers.first)

        #expect(offer.isGrouped == false)
        #expect(offer.spokenGrouping(of: offer.deliveries[0]) == nil)
        #expect(offer.groupingCaption(of: offer.deliveries[0]) == nil)
    }

    // MARK: Arranging a screen

    @Test("Deliveries are grouped by their offer, in the order they were accepted")
    func groupingPreservesOrder() throws {
        let shift = runningShift()
        _ = try shift.beginOffer(deliveryCount: 2, at: at(300))
        _ = try shift.beginOffer(deliveryCount: 1, at: at(1_800))

        let groups = DeliveryGroup.grouping(shift.numberedDeliveries, within: shift.numberedOffers)

        #expect(groups.count == 2)
        #expect(groups[0].deliveries.map(\.number) == [1, 2])
        #expect(groups[0].isGrouped)
        #expect(groups[1].deliveries.map(\.number) == [3])
        #expect(groups[1].isGrouped == false, "A one-delivery offer shows no heading")
    }

    @Test("A group still names its offer while only one of its deliveries is on screen")
    func groupKnowsTheWholeOffer() throws {
        let shift = runningShift()
        let recorded = try shift.beginOffer(deliveryCount: 2, at: at(300))
        try recorded.deliveries[0].markArrivedAtPickup(at: at(600))
        try recorded.deliveries[0].markPickedUp(at: at(900))
        try recorded.deliveries[0].markDelivered(at: at(1_200))

        let groups = DeliveryGroup.grouping(shift.numberedActiveDeliveries, within: shift.numberedOffers)

        #expect(groups.count == 1)
        #expect(groups[0].deliveries.count == 1, "Only the delivery still running is shown")
        #expect(groups[0].isGrouped, "And it is still shown as part of the offer it arrived in")
        #expect(groups[0].offer?.remainingStatement == "1 of 2 still in progress")
    }

    @Test("A delivery recording no offer is its own group rather than pooled with others")
    func ungroupedDeliveriesStayApart() {
        let shift = runningShift()
        let first = Delivery(shift: shift, acceptedAt: at(300))
        let second = Delivery(shift: shift, acceptedAt: at(900))

        let groups = DeliveryGroup.grouping(
            NumberedDelivery.numbering([first, second]),
            within: shift.numberedOffers
        )

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.offer == nil })
        #expect(groups.allSatisfy { $0.isGrouped == false })
        #expect(groups.map(\.id) == [first.id, second.id], "Each identifies itself by its own delivery")
    }

    @Test("Two offers accepted at once are two groups, never one")
    func twoOffersNeverMerge() throws {
        let shift = runningShift()
        let first = try shift.beginOffer(deliveryCount: 1, at: at(300))
        let second = try shift.beginOffer(deliveryCount: 1, at: at(300))

        #expect(first.offer.id != second.offer.id)
        let groups = DeliveryGroup.grouping(shift.numberedDeliveries, within: shift.numberedOffers)
        #expect(groups.count == 2, "Sharing an instant is not sharing an acceptance")
    }

    // MARK: The states an offer can be in

    @Test("Offer state is read from the deliveries and nothing else", arguments: [
        ([DeliveryState.accepted, .delivered], OfferState.inProgress),
        ([.delivered, .delivered], .completed),
        ([.cancelled, .cancelled], .cancelled),
        ([.delivered, .cancelled], .partiallyCompleted),
        ([.pickedUp], .inProgress),
        ([.delivered], .completed),
        ([], .empty)
    ])
    func offerStates(states: [DeliveryState], expected: OfferState) {
        #expect(OfferState(deliveryStates: states) == expected)
    }
}
