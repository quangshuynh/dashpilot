import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Deliveries the driver recorded as sharing a pickup or a drop-off: only when
/// they said so, only within one offer, and never moving anything else.
///
/// Every refused-save case reads the store through a **fresh context**, the
/// convention every rollback suite here follows.
@MainActor
@Suite("Shared stops")
struct SharedStopTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private struct Refused: Error {}

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        try ShiftService(context: context).startShift(at: start)
        return context
    }

    // MARK: Recorded with the offer

    @Test("An offer of several deliveries is independent unless the driver says otherwise")
    func independentByDefault() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(1))

        for delivery in offer.deliveries {
            #expect(delivery.sharedPickupID == nil, "Accepted together is not evidence of one pickup")
            #expect(delivery.sharedDropOffID == nil, "Nor of one customer")
        }
    }

    @Test("Choosing both on the sheet gives every delivery of the offer one identity per kind")
    func sharedOnCreation() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(
            deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1)
        )

        let pickups = Set(offer.deliveries.compactMap(\.sharedPickupID))
        let dropOffs = Set(offer.deliveries.compactMap(\.sharedDropOffID))
        #expect(pickups.count == 1)
        #expect(dropOffs.count == 1)
        #expect(pickups != dropOffs, "Two facts, two identities")
        #expect(offer.deliveries.allSatisfy { $0.sharedPickupID != nil && $0.sharedDropOffID != nil })
    }

    @Test("A shared drop-off alone says nothing about the pickup")
    func dropOffAlone() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(1))

        #expect(offer.deliveries.allSatisfy { $0.sharedPickupID == nil })
        #expect(Set(offer.deliveries.compactMap(\.sharedDropOffID)).count == 1)
    }

    @Test("A shared stop on an offer of one is refused and records nothing")
    func oneDeliveryCannotShare() throws {
        let context = try makeContext()
        #expect(throws: DeliveryLifecycleError.invalidOffer(.sharedStopNeedsSeveralDeliveries)) {
            try DeliveryService(context: context).startOffer(deliveryCount: 1, sharing: [.pickup], at: at(1))
        }
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty)
    }

    @Test("Two separate offers never share an identity, however close they were accepted")
    func separateOffersStayApart() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let first = try service.startOffer(deliveryCount: 2, sharing: [.pickup], at: at(1))
        let second = try service.startOffer(deliveryCount: 2, sharing: [.pickup], at: at(1))

        #expect(
            Set(first.deliveries.compactMap(\.sharedPickupID)).isDisjoint(with: second.deliveries.compactMap(\.sharedPickupID))
        )
    }

    // MARK: Recording a subset

    @Test("Two of three can share a pickup, and the third stays independent")
    func aSubset() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 3, at: at(1))
        let ordered = offer.deliveriesInOrder

        try OfferCorrectionService(context: context).recordSharedStops(
            pickup: [ordered[0], ordered[2]], dropOff: [], in: offer
        )

        #expect(ordered[0].sharedPickupID != nil)
        #expect(ordered[0].sharedPickupID == ordered[2].sharedPickupID)
        #expect(ordered[1].sharedPickupID == nil)
        #expect(ordered.allSatisfy { $0.sharedDropOffID == nil })
    }

    @Test("Recording again replaces the old answer with a fresh identity, and an empty list takes it back")
    func replaceAndClear() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 3, sharing: [.pickup], at: at(1))
        let ordered = offer.deliveriesInOrder
        let old = try #require(ordered[0].sharedPickupID)
        let corrections = OfferCorrectionService(context: context)

        try corrections.recordSharedStops(pickup: [ordered[1], ordered[2]], dropOff: [], in: offer)
        #expect(ordered[0].sharedPickupID == nil, "Left out, so no longer shared")
        let new = try #require(ordered[1].sharedPickupID)
        #expect(new != old, "A delivery taken out of a group can never still match it")
        #expect(ordered[2].sharedPickupID == new)

        try corrections.recordSharedStops(pickup: [], dropOff: [], in: offer)
        #expect(ordered.allSatisfy { $0.sharedPickupID == nil && $0.sharedDropOffID == nil })
    }

    @Test("One delivery cannot share a stop with nobody, and a refusal leaves both kinds as they were")
    func oneIsRefused() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, sharing: [.pickup], at: at(1))
        let ordered = offer.deliveriesInOrder
        let before = ordered.map(\.sharedPickupID)

        #expect(throws: OfferCorrectionError.invalidSharedStop(.onlyOneDelivery)) {
            // The pickup half is valid and would be written first.
            try OfferCorrectionService(context: context).recordSharedStops(
                pickup: [], dropOff: [ordered[0]], in: offer
            )
        }
        #expect(ordered.map(\.sharedPickupID) == before, "Nothing is half-recorded")

        let fresh = ModelContext(context.container)
        let stored = try fresh.fetch(FetchDescriptor<Delivery>())
        #expect(Set(stored.map(\.sharedPickupID)) == Set(before))
    }

    @Test("A delivery from another offer cannot join a shared stop")
    func outsideTheOffer() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let offer = try service.startOffer(deliveryCount: 2, at: at(1))
        let other = try service.startDelivery(at: at(2))

        #expect(throws: OfferCorrectionError.invalidSharedStop(.deliveryOutsideOffer)) {
            try OfferCorrectionService(context: context).recordSharedStops(
                pickup: [offer.deliveriesInOrder[0], other], dropOff: [], in: offer
            )
        }
        #expect(other.sharedPickupID == nil)
    }

    @Test("Recording shared stops moves no lifecycle instant, place, amount or offer")
    func movesNothingElse() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let offer = try service.startOffer(deliveryCount: 2, at: at(1))
        let ordered = offer.deliveriesInOrder
        try service.markArrivedAtPickup(ordered[0], at: at(5))
        try service.setExpectedEarnings(Money(minorUnits: 850), on: ordered[1])
        let before = ordered.map { [$0.acceptedAt, $0.arrivedAtPickupAt, $0.pickedUpAt] }

        try OfferCorrectionService(context: context).recordSharedStops(pickup: ordered, dropOff: ordered, in: offer)

        #expect(ordered.map { [$0.acceptedAt, $0.arrivedAtPickupAt, $0.pickedUpAt] } == before)
        #expect(ordered[1].expectedEarnings == Money(minorUnits: 850))
        #expect(ordered.allSatisfy { $0.offer?.id == offer.id })
    }

    @Test("Allowed on a finished shift, because it records no event")
    func onAFinishedShift() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let offer = try service.startOffer(deliveryCount: 2, at: at(1))
        for delivery in offer.deliveriesInOrder { try service.cancelDelivery(delivery, at: at(2)) }
        try ShiftService(context: context).endActiveShift(at: at(3))

        try OfferCorrectionService(context: context).recordSharedStops(
            pickup: [], dropOff: offer.deliveriesInOrder, in: offer
        )
        #expect(Set(offer.deliveries.compactMap(\.sharedDropOffID)).count == 1)
    }

    @Test("A refused save leaves the store holding the old answer")
    func refusedSave() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(1))
        let failing = OfferCorrectionService(context: context, commit: { _ in throw Refused() })

        #expect(throws: OfferCorrectionError.self) {
            try failing.recordSharedStops(pickup: offer.deliveriesInOrder, dropOff: [], in: offer)
        }

        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<Delivery>()).allSatisfy { $0.sharedPickupID == nil })
    }

    // MARK: Membership corrections keep the invariant

    @Test("Moving a delivery out leaves its shared stops behind, and a pair left with one member dissolves")
    func movingOutDissolves() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        // Accepted first, so it could truthfully have contained the one moving.
        let earlier = try service.startOffer(deliveryCount: 1, at: at(1))
        let offer = try service.startOffer(deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(2))
        let moving = offer.deliveriesInOrder[1]
        let staying = offer.deliveriesInOrder[0]

        try OfferCorrectionService(context: context).move(moving, into: earlier)

        #expect(moving.sharedPickupID == nil && moving.sharedDropOffID == nil, "No claim is carried into another offer")
        #expect(staying.sharedPickupID == nil && staying.sharedDropOffID == nil, "One delivery shares with nobody")
    }

    @Test("Splitting two of a group of three together keeps them sharing, and the one left behind dissolves")
    func splittingKeepsWholeGroups() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 3, sharing: [.pickup], at: at(1))
        let ordered = offer.deliveriesInOrder

        try OfferCorrectionService(context: context).split([ordered[1], ordered[2]])

        #expect(ordered[1].sharedPickupID != nil)
        #expect(ordered[1].sharedPickupID == ordered[2].sharedPickupID)
        #expect(ordered[0].sharedPickupID == nil)
    }

    @Test("Separating an offer clears every shared stop in it")
    func separatingClears() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, sharing: [.pickup], at: at(1))

        try OfferCorrectionService(context: context).separate(offer)

        #expect(try context.fetch(FetchDescriptor<Delivery>()).allSatisfy { $0.sharedPickupID == nil })
    }

    @Test("Merging two offers keeps each group whole")
    func mergingKeepsGroups() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let first = try service.startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(1))
        let second = try service.startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(2))
        let firstIdentity = first.deliveriesInOrder[0].sharedDropOffID
        let secondIdentity = second.deliveriesInOrder[0].sharedDropOffID

        try OfferCorrectionService(context: context).merge(second, into: first)

        let merged = first.deliveriesInOrder
        #expect(merged.count == 4)
        #expect(merged.filter { $0.sharedDropOffID == firstIdentity }.count == 2)
        #expect(merged.filter { $0.sharedDropOffID == secondIdentity }.count == 2, "Two groups, still two")
    }

    // MARK: Words

    @Test("The caption names the siblings and says each kind only when it was recorded")
    func captions() throws {
        let context = try makeContext()
        let service = DeliveryService(context: context)
        let offer = try service.startOffer(deliveryCount: 3, at: at(1))
        let ordered = offer.deliveriesInOrder
        let corrections = OfferCorrectionService(context: context)
        let shift = try #require(ordered[0].shift)

        func caption(of delivery: Delivery) -> SharedStopDescription {
            let numbered = shift.numberedDeliveries
            let subject = try! #require(numbered.first { $0.id == delivery.id })
            return SharedStopDescription(of: subject, among: numbered.filter { $0.delivery.offer?.id == offer.id })
        }

        #expect(caption(of: ordered[0]).caption == nil, "Nothing shared: nothing said")

        try corrections.recordSharedStops(pickup: [ordered[0], ordered[1]], dropOff: [ordered[0], ordered[1]], in: offer)
        #expect(caption(of: ordered[0]).caption == "Same pickup and drop-off as Delivery 2")
        #expect(caption(of: ordered[0]).spokenCaption == "You recorded it as the same pickup and drop-off as Delivery 2")
        #expect(caption(of: ordered[2]).caption == nil)

        try corrections.recordSharedStops(pickup: [], dropOff: ordered, in: offer)
        #expect(caption(of: ordered[1]).caption == "Same drop-off as Delivery 1 and Delivery 3")

        try corrections.recordSharedStops(pickup: [ordered[0], ordered[1]], dropOff: ordered, in: offer)
        #expect(
            caption(of: ordered[0]).caption == "Same pickup as Delivery 2 · Same drop-off as Delivery 2 and Delivery 3"
        )
        #expect(
            caption(of: ordered[0]).spokenCaption
                == "You recorded it as the same pickup as Delivery 2, and the same drop-off as Delivery 2 and Delivery 3"
        )
    }

    @Test("No caption names a customer, an address or a restaurant")
    func captionsClaimNothing() throws {
        let context = try makeContext()
        let offer = try DeliveryService(context: context).startOffer(
            deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1)
        )
        let shift = try #require(offer.shift)
        let numbered = shift.numberedDeliveries
        let description = SharedStopDescription(of: numbered[0], among: numbered)
        let words = [description.caption, description.spokenCaption].compactMap { $0 }.joined(separator: " ").lowercased()

        for claim in ["customer", "address", "restaurant", "store", "same place", "same person"] {
            #expect(!words.contains(claim), "Said \(claim)")
        }
    }
}
