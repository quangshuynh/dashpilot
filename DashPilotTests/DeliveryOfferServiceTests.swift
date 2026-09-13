import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedSave: Error {}

/// Recording an offer through the service: what one tap records, what a grouped
/// offer records, how add-on offers stay apart, and what a refused save leaves
/// behind.
///
/// Every operation is given its timestamp, so nothing here depends on how long
/// the test took to run.
@MainActor
@Suite("Delivery offer service")
struct DeliveryOfferServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeRunningShift(
        commit: ((ModelContext) throws -> Void)? = nil
    ) throws -> (context: ModelContext, shift: Shift, deliveries: DeliveryService) {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let service = commit.map { DeliveryService(context: context, commit: $0) }
            ?? DeliveryService(context: context)
        return (context, shift, service)
    }

    // MARK: The one-tap path

    @Test("Start Delivery records exactly one delivery, through an offer of one")
    func startDeliveryRecordsOneOfOne() throws {
        let (context, shift, service) = try makeRunningShift()

        let delivery = try service.startDelivery(at: at(300))

        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)

        let offer = try #require(delivery.offer)
        #expect(offer.deliveryCount == 1)
        #expect(offer.isGrouped == false)
        #expect(offer.acceptedAt == delivery.acceptedAt, "One acceptance, recorded once")
        #expect(offer.shift?.id == shift.id)
        #expect(shift.offers.count == 1)
    }

    @Test("A start that precedes its shift is clamped, and the offer is clamped with it")
    func clampsToTheShiftStart() throws {
        let (_, shift, service) = try makeRunningShift()

        let delivery = try service.startDelivery(at: at(-600))

        #expect(delivery.acceptedAt == shift.startedAt)
        #expect(delivery.offer?.acceptedAt == shift.startedAt, "The offer cannot predate its shift either")
    }

    @Test("No offer is recorded where no delivery would have been")
    func refusalsRecordNoOffer() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let service = DeliveryService(context: context)

        #expect(throws: DeliveryLifecycleError.noActiveShift) {
            try service.startOffer(deliveryCount: 2, at: start)
        }
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty)

        let shifts = ShiftService(context: context)
        try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(60))

        #expect(throws: DeliveryLifecycleError.shiftPaused) {
            try service.startOffer(deliveryCount: 2, at: at(120))
        }
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
    }

    @Test("An offer of no deliveries is refused and writes nothing")
    func refusesAnEmptyOffer() throws {
        let (context, _, service) = try makeRunningShift()

        #expect(throws: DeliveryLifecycleError.invalidOffer(.deliveryCountNotPositive)) {
            try service.startOffer(deliveryCount: 0, at: at(300))
        }
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        #expect(!context.hasChanges, "A refusal leaves nothing pending")
    }

    // MARK: Grouped creation

    @Test("An offer of two records one offer and two deliveries, both active")
    func recordsAGroupedOffer() throws {
        let (context, shift, service) = try makeRunningShift()

        let offer = try service.startOffer(deliveryCount: 2, at: at(300))

        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)
        #expect(offer.deliveryCount == 2)
        #expect(shift.activeDeliveries.count == 2)
        #expect(shift.deliverySummary.inProgress == 2)
        #expect(offer.deliveries.allSatisfy { $0.state == .accepted })
    }

    @Test("Nothing about a grouped offer asks for a place, a name or an amount")
    func groupedCreationAsksForNothingElse() throws {
        let (_, _, service) = try makeRunningShift()

        let offer = try service.startOffer(deliveryCount: 3, at: at(300))

        for delivery in offer.deliveries {
            #expect(delivery.pickupPlace == nil)
            #expect(delivery.expectedEarnings == nil)
            #expect(delivery.grossEarnings == nil)
        }
    }

    // MARK: Add-on offers

    @Test("An offer accepted while another is running is a second offer, not an addition")
    func addOnOfferIsItsOwn() throws {
        let (context, shift, service) = try makeRunningShift()

        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(1_500))

        #expect(first.id != second.id)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 2)
        #expect(first.deliveryCount == 2, "The earlier offer did not grow")
        #expect(second.deliveryCount == 1)
        #expect(shift.activeDeliveries.count == 3)
        #expect(shift.offersInOrder.map(\.acceptedAt) == [at(300), at(1_500)])
    }

    @Test("Two offers overlapping in time are still two offers")
    func overlappingOffersDoNotMerge() throws {
        let (_, shift, service) = try makeRunningShift()

        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(420))

        // The first offer's delivery is still running when the second arrives,
        // and is still running after it.
        #expect(first.state == .inProgress)
        #expect(second.state == .inProgress)
        #expect(shift.numberedOffers.count == 2)
        #expect(first.deliveries.count == 1)
    }

    @Test("Deliveries in one offer can sit at different points of their lifecycles")
    func siblingsAtDifferentStates() throws {
        let (_, _, service) = try makeRunningShift()

        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder
        try service.markArrivedAtPickup(ordered[0], at: at(600))
        try service.markPickedUp(ordered[0], at: at(900))

        #expect(ordered[0].state == .pickedUp)
        #expect(ordered[1].state == .accepted)
        #expect(offer.activeDeliveries.count == 2)
    }

    @Test("Completing one delivery leaves its siblings running and its offer open")
    func completingOneLeavesTheRest() throws {
        let (context, shift, service) = try makeRunningShift()

        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder
        try service.markArrivedAtPickup(ordered[0], at: at(600))
        try service.markPickedUp(ordered[0], at: at(900))
        try service.markDelivered(ordered[0], at: at(1_500))

        #expect(offer.state == .inProgress)
        #expect(try service.activeDeliveries(for: shift).map(\.id) == [ordered[1].id])
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1, "No second offer appeared")

        try service.markArrivedAtPickup(ordered[1], at: at(1_600))
        try service.markPickedUp(ordered[1], at: at(1_800))
        try service.markDelivered(ordered[1], at: at(2_400))

        #expect(offer.state == .completed)
        #expect(offer.isTerminal)
    }

    @Test("Earnings stay on the delivery they were recorded against")
    func earningsStayWithTheirDelivery() throws {
        let (_, _, service) = try makeRunningShift()

        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder

        try service.setExpectedEarnings(try #require(Money(exact: "8.50")), on: ordered[0])
        #expect(ordered[0].expectedEarnings == Money(exact: "8.50"))
        #expect(ordered[1].expectedEarnings == nil, "A sibling gains nothing from it")

        for delivery in ordered {
            try service.markArrivedAtPickup(delivery, at: at(600))
            try service.markPickedUp(delivery, at: at(900))
            try service.markDelivered(delivery, at: at(1_500))
        }
        try service.setGrossEarnings(try #require(Money(exact: "6.25")), on: ordered[1])

        #expect(ordered[0].grossEarnings == nil, "Recording one delivery's gross records nothing on the other")
        #expect(ordered[1].grossEarnings == Money(exact: "6.25"))
        #expect(ordered[0].expectedEarnings == Money(exact: "8.50"), "And the expectation survived the completion")
        #expect(ordered[1].expectedEarnings == nil)
    }

    // MARK: A refused save

    @Test("A refused save leaves neither the offer nor any of its deliveries")
    func refusedSaveLeavesNothing() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        try ShiftService(context: context).startShift(at: start)
        let refusing = DeliveryService(context: context, commit: { _ in throw RefusedSave() })

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try refusing.startOffer(deliveryCount: 3, at: at(300))
        }

        #expect(!context.hasChanges, "The rollback left nothing pending")
        #expect(try context.fetch(FetchDescriptor<Offer>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
    }

    @Test("A refused save leaves an offer already recorded exactly as it was")
    func refusedSaveKeepsTheEarlierOffer() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        try ShiftService(context: context).startShift(at: start)
        let writing = DeliveryService(context: context)
        let first = try writing.startOffer(deliveryCount: 2, at: at(300))

        let refusing = DeliveryService(context: context, commit: { _ in throw RefusedSave() })
        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try refusing.startOffer(deliveryCount: 2, at: at(900))
        }

        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)
        #expect(first.deliveryCount == 2, "The surviving offer still holds exactly its own deliveries")
        #expect(first.deliveries.allSatisfy { $0.offer?.id == first.id })
    }
}
