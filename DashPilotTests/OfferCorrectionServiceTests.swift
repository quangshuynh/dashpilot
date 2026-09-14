import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedSave: Error {}

/// The four corrections as the store applies them: what moves, what is left
/// holding nothing, what a refused save leaves behind, and which destinations a
/// screen is allowed to offer.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held relationship cache and the authoritative store
/// can disagree after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp and amount here is invented.
@MainActor
@Suite("Offer correction service")
struct OfferCorrectionServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotOfferCorrectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func runningShift() throws -> (context: ModelContext, shift: Shift, deliveries: DeliveryService) {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        return (context, shift, DeliveryService(context: context))
    }

    private func corrections(_ context: ModelContext) -> OfferCorrectionService {
        OfferCorrectionService(context: context)
    }

    private func refusing(_ context: ModelContext) -> OfferCorrectionService {
        OfferCorrectionService(context: context, commit: { _ in throw RefusedSave() })
    }

    // MARK: Moving one delivery

    @Test("A delivery moves from one offer to another, and both offers survive")
    func movesBetweenTwoOffers() throws {
        let (context, shift, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 2, at: at(900))
        let moving = try #require(second.deliveriesInOrder.first)

        try corrections(context).move(moving, into: first)

        #expect(moving.offer?.id == first.id)
        #expect(first.deliveryCount == 3)
        #expect(second.deliveryCount == 1)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 2, "Neither offer was removed")
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 4, "And no delivery was")
        #expect(shift.deliveries.count == 4)
    }

    @Test("Moving out of a two-delivery offer leaves the other delivery where it was")
    func leavesTheSiblingBehind() throws {
        let (context, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 2, at: at(900))
        let ordered = second.deliveriesInOrder
        let staying = ordered[1]

        try corrections(context).move(ordered[0], into: first)

        #expect(second.deliveriesInOrder.map(\.id) == [staying.id])
        #expect(staying.offer?.id == second.id)
        #expect(staying.acceptedAt == at(900))
        #expect(second.acceptedAt == at(900), "The offer left behind keeps its own acceptance")
    }

    @Test("Moving the last delivery out of an offer removes the offer in the same write")
    func removesTheEmptiedOffer() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let service = DeliveryService(context: context)
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(900))
        let secondID = second.id
        let moving = try #require(second.deliveriesInOrder.first)
        let movingID = moving.id

        try corrections(context).move(moving, into: first)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())
        let deliveries = try reopened.fetch(FetchDescriptor<Delivery>())

        #expect(offers.count == 1, "No empty shell is left in ordinary history")
        #expect(offers.first?.id == first.id)
        #expect(offers.contains { $0.id == secondID } == false)
        #expect(deliveries.count == 2, "And the delivery that moved was not taken with it")
        #expect(deliveries.first { $0.id == movingID }?.offer?.id == first.id)
    }

    @Test("A refused destination changes nothing and leaves nothing pending")
    func refusedMoveWritesNothing() throws {
        let (context, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(900))
        let earlier = try #require(first.deliveriesInOrder.first)

        #expect(throws: OfferCorrectionError.invalidMembership(.deliveryPrecedesOfferAcceptance)) {
            try corrections(context).move(earlier, into: second)
        }

        #expect(earlier.offer?.id == first.id)
        #expect(second.deliveryCount == 1)
        #expect(!context.hasChanges, "A refusal leaves nothing for a later save to commit")
    }

    @Test("A refused save leaves the grouping exactly as the store had it")
    func rollbackDuringAMove() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let service = DeliveryService(context: context)
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(900))
        let firstID = first.id
        let secondID = second.id
        let moving = try #require(second.deliveriesInOrder.first)
        let movingID = moving.id

        #expect(throws: OfferCorrectionError.storeUnavailable(underlying: RefusedSave())) {
            try refusing(context).move(moving, into: first)
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())
        let deliveries = try reopened.fetch(FetchDescriptor<Delivery>())

        #expect(offers.count == 2, "The offer that would have been emptied is still there")
        #expect(Set(offers.map(\.id)) == [firstID, secondID])
        #expect(deliveries.count == 3)
        #expect(deliveries.first { $0.id == movingID }?.offer?.id == secondID, "It never moved")
        #expect(offers.first { $0.id == firstID }?.deliveryCount == 2)
        #expect(offers.first { $0.id == secondID }?.deliveryCount == 1)
    }

    // MARK: Splitting

    @Test("One delivery splits into a new offer taking its own acceptance")
    func splitsOneDelivery() throws {
        let (context, shift, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let moving = try #require(offer.deliveriesInOrder.last)

        let created = try corrections(context).split([moving])

        #expect(created.deliveryCount == 1)
        #expect(created.acceptedAt == at(300), "Its own recorded acceptance, and nothing invented")
        #expect(moving.offer?.id == created.id)
        #expect(offer.deliveryCount == 1)
        #expect(shift.offers.count == 2)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 2)
    }

    @Test("Several deliveries split into one new offer together")
    func splitsSeveralDeliveries() throws {
        let (context, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 4, at: at(300))
        let ordered = offer.deliveriesInOrder

        let created = try corrections(context).split([ordered[1], ordered[2]])

        #expect(created.deliveryCount == 2)
        #expect(Set(created.deliveriesInOrder.map(\.id)) == [ordered[1].id, ordered[2].id])
        #expect(offer.deliveryCount == 2)
        #expect(Set(offer.deliveriesInOrder.map(\.id)) == [ordered[0].id, ordered[3].id])
    }

    @Test("Splitting every delivery of an offer is refused as the no-op it is")
    func refusesSplittingEverything() throws {
        let (context, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))

        #expect(throws: OfferCorrectionError.invalidMembership(.wouldRegroupEveryDelivery)) {
            try corrections(context).split(offer.deliveriesInOrder)
        }
        #expect(offer.deliveryCount == 2)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
    }

    @Test("Deliveries from two different offers cannot be split in one operation")
    func refusesMixedSources() throws {
        let (context, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 2, at: at(900))

        #expect(throws: OfferCorrectionError.invalidMembership(.deliveriesFromDifferentOffers)) {
            try corrections(context).split([
                try #require(first.deliveriesInOrder.first),
                try #require(second.deliveriesInOrder.first)
            ])
        }
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 2)
    }

    @Test("A refused save leaves no new offer and no moved delivery")
    func rollbackDuringASplit() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 3, at: at(300))
        let offerID = offer.id
        let moving = try #require(offer.deliveriesInOrder.last)

        #expect(throws: OfferCorrectionError.storeUnavailable(underlying: RefusedSave())) {
            try refusing(context).split([moving])
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())

        #expect(offers.count == 1, "The offer the split would have created is not in the store")
        #expect(offers.first?.id == offerID)
        #expect(offers.first?.deliveryCount == 3)
        #expect(try reopened.fetch(FetchDescriptor<Delivery>()).allSatisfy { $0.offer?.id == offerID })
    }

    // MARK: Merging

    @Test("Merging moves every delivery and removes the offer left holding nothing")
    func mergesTwoOffers() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let service = DeliveryService(context: context)
        let destination = try service.startOffer(deliveryCount: 1, at: at(300))
        let source = try service.startOffer(deliveryCount: 2, at: at(900))
        let sourceID = source.id
        let movingIDs = Set(source.deliveriesInOrder.map(\.id))

        try corrections(context).merge(source, into: destination)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())
        let deliveries = try reopened.fetch(FetchDescriptor<Delivery>())

        #expect(offers.count == 1)
        #expect(offers.first?.id == destination.id)
        #expect(offers.first?.acceptedAt == at(300), "The destination keeps its own acceptance")
        #expect(offers.first?.deliveryCount == 3)
        #expect(deliveries.count == 3, "Removing the source took no delivery with it")
        #expect(deliveries.filter { movingIDs.contains($0.id) }.allSatisfy { $0.offer?.id == destination.id })
        #expect(deliveries.contains { $0.offer?.id == sourceID } == false)
    }

    @Test("Merging into an offer accepted after the source's deliveries is refused before anything moves")
    func refusesTheWrongMergeDirection() throws {
        let (context, _, service) = try runningShift()
        let earlier = try service.startOffer(deliveryCount: 2, at: at(300))
        let later = try service.startOffer(deliveryCount: 1, at: at(900))

        #expect(throws: OfferCorrectionError.invalidMembership(.deliveryPrecedesOfferAcceptance)) {
            try corrections(context).merge(earlier, into: later)
        }
        #expect(earlier.deliveryCount == 2, "Neither offer moved")
        #expect(later.deliveryCount == 1)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 2)

        // And the direction that is truthful is always available: the earlier
        // offer could have contained everything the later one holds.
        try corrections(context).merge(later, into: earlier)
        #expect(earlier.deliveryCount == 3)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
    }

    @Test("An offer cannot be merged into itself")
    func refusesMergingIntoItself() throws {
        let (context, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))

        #expect(throws: OfferCorrectionError.invalidMembership(.cannotMergeIntoItself)) {
            try corrections(context).merge(offer, into: offer)
        }
        #expect(offer.deliveryCount == 2)
    }

    @Test("A refused save leaves no partly merged grouping in the store")
    func rollbackDuringAMerge() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        try ShiftService(context: context).startShift(at: start)
        let service = DeliveryService(context: context)
        let destination = try service.startOffer(deliveryCount: 1, at: at(300))
        let source = try service.startOffer(deliveryCount: 3, at: at(900))
        let destinationID = destination.id
        let sourceID = source.id
        let sourceDeliveryIDs = Set(source.deliveriesInOrder.map(\.id))

        #expect(throws: OfferCorrectionError.storeUnavailable(underlying: RefusedSave())) {
            try refusing(context).merge(source, into: destination)
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let offers = try reopened.fetch(FetchDescriptor<Offer>())
        let deliveries = try reopened.fetch(FetchDescriptor<Delivery>())

        #expect(offers.count == 2, "The source is still standing")
        #expect(Set(offers.map(\.id)) == [destinationID, sourceID])
        #expect(offers.first { $0.id == sourceID }?.deliveryCount == 3, "With all three of its deliveries")
        #expect(offers.first { $0.id == destinationID }?.deliveryCount == 1)
        #expect(deliveries.count == 4)
        #expect(deliveries.filter { sourceDeliveryIDs.contains($0.id) }.allSatisfy { $0.offer?.id == sourceID })
    }

    // MARK: Separating

    @Test("Separating a grouped offer leaves one delivery in it and gives every other its own")
    func separatesAGroupedOffer() throws {
        let (context, shift, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 3, at: at(300))
        let ordered = offer.deliveriesInOrder

        let created = try corrections(context).separate(offer)

        #expect(created.count == 2)
        #expect(offer.deliveryCount == 1)
        #expect(offer.deliveriesInOrder.map(\.id) == [ordered[0].id], "The first stays where it was")
        #expect(created.allSatisfy { $0.deliveryCount == 1 })
        #expect(created.allSatisfy { $0.acceptedAt == at(300) }, "Each takes its own delivery's acceptance")
        #expect(shift.offers.count == 3)
        #expect(shift.numberedOffers.allSatisfy { $0.isGrouped == false })
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 3, "No delivery was created or removed")
    }

    @Test("An offer of one has nothing to separate")
    func refusesSeparatingAnOfferOfOne() throws {
        let (context, _, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 1, at: at(300))

        #expect(throws: OfferCorrectionError.invalidMembership(.offerIsNotGrouped)) {
            try corrections(context).separate(offer)
        }
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
    }

    // MARK: Destinations a screen may offer

    @Test("A delivery's destinations exclude its own offer and every offer accepted after it")
    func moveDestinationsFollowTheRule() throws {
        let (context, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(900))
        let third = try service.startOffer(deliveryCount: 1, at: at(1_500))
        let middle = try #require(second.deliveriesInOrder.first)

        let destinations = corrections(context).moveDestinations(for: middle)

        #expect(destinations.map(\.id) == [first.id], "Its own offer, and the later one, are both out")
        #expect(destinations.contains { $0.id == third.id } == false)
    }

    @Test("Every destination a screen may offer is one the model accepts")
    func everyOfferedDestinationIsAccepted() throws {
        let (context, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 2, at: at(300))
        try service.startOffer(deliveryCount: 1, at: at(900))
        try service.startOffer(deliveryCount: 3, at: at(1_500))

        let correcting = corrections(context)
        for delivery in shift.deliveries {
            for destination in correcting.moveDestinations(for: delivery) {
                #expect(destination.couldHaveContained(delivery.acceptedAt))
                #expect(destination.id != delivery.offer?.id)
                #expect(destination.shift?.id == shift.id)
            }
        }
    }

    @Test("An offer's merge destinations accept every delivery that would move")
    func mergeDestinationsFollowTheRule() throws {
        let (context, _, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 2, at: at(900))

        #expect(corrections(context).mergeDestinations(for: second).map(\.id) == [first.id])
        #expect(
            corrections(context).mergeDestinations(for: first).isEmpty,
            "The earlier offer has nowhere truthful to go, and the screen offers it nothing"
        )
    }
}
