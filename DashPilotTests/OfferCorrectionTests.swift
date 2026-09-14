import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The rules membership correction keeps, at the level the model owns them, and
/// the sentences a driver is asked to confirm.
///
/// The claim under test is narrow and is the whole feature: a correction changes
/// **which offer owns a delivery** and changes nothing else, including neither
/// acceptance timestamp. Everything the model refuses, it refuses because
/// applying it would make the store say something the driver cannot have
/// witnessed.
///
/// Every timestamp and name here is invented.
@MainActor
@Suite("Offer correction")
struct OfferCorrectionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func runningShift() throws -> (context: ModelContext, shift: Shift, deliveries: DeliveryService) {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        return (context, shift, DeliveryService(context: context))
    }

    // MARK: The ordering rule

    @Test("An offer could have contained a delivery accepted at or after its own acceptance")
    func couldHaveContained() throws {
        let (_, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 1, at: at(300))

        #expect(offer.couldHaveContained(at(300)), "The instant it was accepted")
        #expect(offer.couldHaveContained(at(900)), "And anything after it")
        #expect(offer.couldHaveContained(at(299)) == false, "But not a delivery accepted before it existed")
    }

    @Test("A delivery moves into an offer accepted before it, keeping both timestamps")
    func moveKeepsBothTimestamps() throws {
        let (_, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(360))
        let moving = try #require(second.deliveriesInOrder.first)

        try moving.move(into: first)

        #expect(moving.offer?.id == first.id)
        #expect(moving.acceptedAt == at(360), "The delivery's own acceptance is what the driver recorded")
        #expect(first.acceptedAt == at(300), "And the offer's is the acceptance it records")
        #expect(
            first.acceptedAt != moving.acceptedAt,
            "A correction does not require the two to agree, which is the mistake it exists to fix"
        )
    }

    @Test("A delivery cannot move into an offer accepted after it")
    func refusesAnOfferAcceptedLater() throws {
        let (_, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(360))
        let earlier = try #require(first.deliveriesInOrder.first)

        #expect(throws: OfferMembershipError.deliveryPrecedesOfferAcceptance) {
            try earlier.move(into: second)
        }
        #expect(earlier.offer?.id == first.id, "A refusal changes nothing")
        #expect(second.deliveryCount == 1)
    }

    @Test("A delivery cannot move into an offer from another shift")
    func refusesAnotherShift() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        let first = try shifts.startShift(at: start)
        let theirs = try deliveries.startOffer(deliveryCount: 1, at: at(300))
        try deliveries.cancelDelivery(try #require(theirs.deliveriesInOrder.first), at: at(420))
        try shifts.endActiveShift(at: at(600))

        try shifts.startShift(at: at(900))
        let mine = try deliveries.startOffer(deliveryCount: 1, at: at(1_200))
        let moving = try #require(mine.deliveriesInOrder.first)

        #expect(throws: OfferMembershipError.differentShift) {
            try moving.move(into: theirs)
        }
        #expect(moving.offer?.id == mine.id)
        #expect(moving.shift?.id != first.id, "And the shift reference nothing else touches is untouched")
    }

    @Test("Moving a delivery into the offer it is already in is refused rather than treated as a move")
    func refusesTheOfferItIsAlreadyIn() throws {
        let (_, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let delivery = try #require(offer.deliveriesInOrder.first)

        #expect(throws: OfferMembershipError.alreadyInThatOffer) {
            try delivery.move(into: offer)
        }
    }

    @Test("A move returns the offer it left, so the caller can decide what happens to it")
    func moveReturnsTheOfferLeftBehind() throws {
        let (_, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(600))
        let moving = try #require(second.deliveriesInOrder.first)

        let emptied = try moving.move(into: first)

        #expect(emptied?.id == second.id)
        #expect(second.deliveryCount == 0, "The model empties it; removing it is the service's decision")
        #expect(first.deliveryCount == 3)
    }

    // MARK: A new offer's acceptance

    @Test("A regrouped offer takes the earliest acceptance among its deliveries")
    func newOfferTakesTheEarliestAcceptance() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 1, at: at(300))
        let later = try service.startOffer(deliveryCount: 1, at: at(900))
        let first = try #require(shift.deliveries.first { $0.acceptedAt == at(300) })
        let second = try #require(later.deliveriesInOrder.first)

        let regrouped = try shift.makeOffer(regrouping: [second, first])

        #expect(regrouped.acceptedAt == at(300), "A moment the driver really recorded, and the earliest of them")
        #expect(regrouped.deliveryCount == 2)
        #expect(first.acceptedAt == at(300), "Neither delivery's own acceptance moved")
        #expect(second.acceptedAt == at(900))
    }

    @Test("A regrouped offer is refused with no deliveries to put in it")
    func refusesAnEmptyRegrouping() throws {
        let (_, shift, _) = try runningShift()

        #expect(throws: OfferMembershipError.noDeliveriesToGroup) {
            try shift.makeOffer(regrouping: [])
        }
    }

    @Test("A regrouped offer is allowed on a shift that has already ended")
    func regroupingIsAllowedOnAFinishedShift() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder
        for delivery in ordered {
            try delivery.markArrivedAtPickup(at: at(600))
            try delivery.markPickedUp(at: at(900))
            try delivery.markDelivered(at: at(1_200))
        }
        try shifts.endActiveShift(at: at(1_800))

        let regrouped = try shift.makeOffer(regrouping: [ordered[1]])

        #expect(regrouped.deliveryCount == 1)
        #expect(offer.deliveryCount == 1)
        #expect(
            throws: OfferError.shiftAlreadyEnded,
            "Recording new work on a finished shift is still refused; restating a grouping is not new work"
        ) {
            try shift.beginOffer(deliveryCount: 1, at: at(1_500))
        }
    }

    // MARK: Numbering

    @Test("Offer numbers are derived, so a correction renumbers what is left with no stored value to go stale")
    func numbersFollowTheCorrection() throws {
        let (_, shift, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(600))
        let third = try service.startOffer(deliveryCount: 1, at: at(900))

        #expect(shift.numberedOffers.map(\.number) == [1, 2, 3])
        #expect(shift.numberedOffer(containing: try #require(third.deliveriesInOrder.first))?.number == 3)

        // The middle offer's delivery joins the first, which leaves the middle
        // holding nothing. The third is then the shift's second offer.
        try #require(second.deliveriesInOrder.first).move(into: first)

        #expect(second.deliveryCount == 0)
        #expect(first.deliveryCount == 2)
        #expect(
            shift.numberedOffers.filter { $0.deliveryCount > 0 }.map(\.number) == [1, 3],
            "Numbering is positional, so removing the emptied row is what renumbers the rest"
        )
    }

    // MARK: What a driver is asked to confirm

    @Test("A move is confirmed by a sentence naming the delivery, both offers and what does not change")
    func moveWording() throws {
        let (_, shift, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 2, at: at(600))
        let numbered = shift.numberedOffers
        let moving = try #require(numbered[1].deliveries.first)

        let plan = OfferCorrectionPlan.move(moving, from: numbered[1], to: numbered[0])

        #expect(plan.title == "Move \(moving.title) to Offer 1?")
        #expect(plan.detail.contains("\(moving.title) moves out of Offer 2 to Offer 1."))
        #expect(plan.detail.contains(OfferCorrectionPlan.unchangedStatement))
        #expect(plan.detail.contains("removed") == false, "Offer 2 still holds a delivery, so nothing is removed")
        #expect(plan.confirmTitle == "Move to Offer 1")
        #expect(first.deliveryCount == 2, "Describing a correction applies nothing")
        #expect(second.deliveryCount == 2)
    }

    @Test("A move that empties its offer says the offer is removed")
    func moveWordingStatesTheRemoval() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 1, at: at(300))
        try service.startOffer(deliveryCount: 1, at: at(600))
        let numbered = shift.numberedOffers
        let moving = try #require(numbered[1].deliveries.first)

        let plan = OfferCorrectionPlan.move(moving, from: numbered[1], to: numbered[0])

        #expect(plan.detail.contains("Offer 2 is left with no deliveries and is removed."))
    }

    @Test("A split says where the new offer's acceptance comes from, without stating a time")
    func splitWording() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 2, at: at(300))
        let offer = try #require(shift.numberedOffers.first)
        let moving = try #require(offer.deliveries.last)

        let plan = OfferCorrectionPlan.split(moving, from: offer)

        #expect(plan.title == "Put \(moving.title) in a new offer?")
        #expect(plan.detail.contains("out of Offer 1 into a new offer of its own"))
        #expect(plan.detail.contains("accepted at the time already recorded for it"))
        #expect(plan.detail.contains(OfferCorrectionPlan.unchangedStatement))
        #expect(plan.confirmTitle == "Put \(moving.title) in a New Offer")
    }

    @Test("A merge names the deliveries that move rather than counting them")
    func mergeWording() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 1, at: at(300))
        try service.startOffer(deliveryCount: 2, at: at(600))
        let numbered = shift.numberedOffers

        let plan = OfferCorrectionPlan.merge(numbered[1], into: numbered[0])

        #expect(plan.title == "Combine Offer 2 into Offer 1?")
        #expect(plan.detail.contains("Delivery 2 and Delivery 3 move to Offer 1."))
        #expect(plan.detail.contains("Offer 2 is then removed."))
        #expect(plan.detail.contains(OfferCorrectionPlan.unchangedStatement))
        #expect(plan.confirmTitle == "Combine into Offer 1")
    }

    @Test("Separating says which deliveries leave and which one stays")
    func separateWording() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 3, at: at(300))
        let offer = try #require(shift.numberedOffers.first)

        let plan = OfferCorrectionPlan.separate(offer)

        #expect(plan.title == "Separate Offer 1?")
        #expect(plan.detail.contains("Delivery 2 and Delivery 3 each move into a new offer of their own."))
        #expect(plan.detail.contains("Delivery 1 stays in Offer 1."))
        #expect(plan.confirmTitle == "Separate Offer 1")
    }

    @Test("No confirmation anywhere exposes an identifier")
    func wordingCarriesNoIdentifiers() throws {
        let (_, shift, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(600))
        let numbered = shift.numberedOffers
        let moving = try #require(numbered[0].deliveries.first)

        let plans = [
            OfferCorrectionPlan.move(moving, from: numbered[0], to: numbered[1]),
            OfferCorrectionPlan.split(moving, from: numbered[0]),
            OfferCorrectionPlan.merge(numbered[0], into: numbered[1]),
            OfferCorrectionPlan.separate(numbered[0])
        ]
        let identifiers = [
            first.id.uuidString,
            second.id.uuidString,
            moving.delivery.id.uuidString,
            shift.id.uuidString
        ]

        for plan in plans {
            let text = [plan.title, plan.detail, plan.confirmTitle].joined(separator: " ")
            for identifier in identifiers {
                #expect(text.contains(identifier) == false, "An identifier reached the driver: \(text)")
                #expect(text.contains(identifier.prefix(8)) == false)
            }
        }
    }
}
