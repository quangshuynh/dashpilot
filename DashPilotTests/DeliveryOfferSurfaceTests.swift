import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What grouping deliveries into offers deliberately does **not** change: the
/// figures a shift reports, the count the Live Activity states, and what a
/// surface with no card to tap is allowed to act on.
///
/// Every claim here is a negative one, which is why they are gathered rather
/// than scattered through the suites that own each surface. An offer holds no
/// money and no time, so a figure that moved because two deliveries now share
/// one would be a defect in whichever calculation read it.
///
/// Every timestamp and amount is invented.
@MainActor
@Suite("Delivery offer surfaces")
struct DeliveryOfferSurfaceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func runningShift() throws -> (context: ModelContext, shift: Shift, deliveries: DeliveryService) {
        let context = try makeContext()
        let shift = try ShiftService(context: context).startShift(at: start)
        return (context, shift, DeliveryService(context: context))
    }

    // MARK: Active time

    @Test("Two deliveries of one offer are unioned, exactly as two of separate offers are")
    func activeTimeIsUnionedWithinAnOffer() throws {
        let (groupedContext, grouped, groupedService) = try runningShift()
        let offer = try groupedService.startOffer(deliveryCount: 2, at: at(300))
        for delivery in offer.deliveriesInOrder {
            try groupedService.markArrivedAtPickup(delivery, at: at(600))
            try groupedService.markPickedUp(delivery, at: at(900))
            try groupedService.markDelivered(delivery, at: at(1_800))
        }
        try ShiftService(context: groupedContext).endActiveShift(at: at(7_200))

        // The same two intervals, recorded as two separate offers.
        let (separateContext, _, separateService) = try runningShift()
        for _ in 0..<2 {
            let delivery = try separateService.startDelivery(at: at(300))
            try separateService.markArrivedAtPickup(delivery, at: at(600))
            try separateService.markPickedUp(delivery, at: at(900))
            try separateService.markDelivered(delivery, at: at(1_800))
        }
        try ShiftService(context: separateContext).endActiveShift(at: at(7_200))

        let groupedTime = grouped.deliveryActiveTime()
        let separate = try #require(try separateContext.fetch(FetchDescriptor<Shift>()).first)
        let separateTime = separate.deliveryActiveTime()

        // 300 to 1,800 counted once, not twice, in both arrangements.
        #expect(groupedTime.duration == 1_500)
        #expect(groupedTime.duration == separateTime.duration, "Sharing an offer changes no duration")
        #expect(groupedTime.countedIntervalCount == 2)
        #expect(groupedTime.mergedIntervalCount == 1, "The two overlapping deliveries merge into one stretch")
        #expect(groupedTime.hasOverlappingDeliveries)
    }

    @Test("Deliveries from several offers still union once where they overlap")
    func activeTimeUnionsAcrossOffers() throws {
        let (context, shift, service) = try runningShift()

        // Offer 1 holds two deliveries running 300 to 2,400. Offer 2, accepted
        // later, holds one running 1,800 to 3,000, overlapping the first.
        let first = try service.startOffer(deliveryCount: 2, at: at(300))
        for delivery in first.deliveriesInOrder {
            try service.markArrivedAtPickup(delivery, at: at(600))
            try service.markPickedUp(delivery, at: at(900))
            try service.markDelivered(delivery, at: at(2_400))
        }
        let addOn = try service.startDelivery(at: at(1_800))
        try service.markArrivedAtPickup(addOn, at: at(2_000))
        try service.markPickedUp(addOn, at: at(2_200))
        try service.markDelivered(addOn, at: at(3_000))
        try ShiftService(context: context).endActiveShift(at: at(7_200))

        let activeTime = shift.deliveryActiveTime()
        #expect(activeTime.duration == 2_700, "300 to 3,000 counted once, not 2,100 + 2,100 + 1,200")
        #expect(activeTime.countedIntervalCount == 3)
        #expect(activeTime.mergedIntervalCount == 1)
    }

    @Test("A shift's counts and rates are unmoved by two deliveries sharing an offer")
    func shiftFiguresAreUnmoved() throws {
        let (context, shift, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        for delivery in offer.deliveriesInOrder {
            try service.markArrivedAtPickup(delivery, at: at(600))
            try service.markPickedUp(delivery, at: at(900))
            try service.markDelivered(delivery, at: at(1_800))
        }
        let shifts = ShiftService(context: context)
        try shifts.endActiveShift(at: at(7_200))
        try shifts.setGrossEarnings(try #require(Money(exact: "100.00")), on: shift)
        try service.setGrossEarnings(try #require(Money(exact: "14.75")), on: offer.deliveriesInOrder[0])

        #expect(shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 0))
        #expect(shift.metrics(for: .none).grossPerWorkingHour.amount == Money(exact: "50.00"))

        // The period record still counts one recorded delivery amount out of
        // two terminal deliveries. An offer is not a unit anything counts.
        let record = shift.periodRecord(for: .none)
        #expect(record.recordedDeliveryEarnings == [try #require(Money(exact: "14.75"))])
        #expect(record.terminalDeliveryCount == 2, "Two terminal deliveries, one of which recorded an amount")
        #expect(record.deliverySummary.completed == 2)
    }

    // MARK: The Live Activity

    @Test("The card's active-delivery count is the delivery count, whatever the offers are")
    func activityCountsDeliveriesRatherThanOffers() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 2, at: at(300))
        _ = try service.startDelivery(at: at(900))

        let state = shift.activityContentState(for: .none, asOf: at(1_200), locale: locale)

        #expect(state.activeDeliveryCount == 3, "Three deliveries in progress, from two offers")
        #expect(state.completedDeliveryCount == 0)
        #expect(shift.offers.count == 2, "And the store really does hold two offers")
    }

    @Test("A single offer of one still offers its delivery's next step")
    func activityStillOffersAStepForOneDelivery() throws {
        let (_, shift, service) = try runningShift()
        _ = try service.startDelivery(at: at(300))

        let state = shift.activityContentState(for: .none, asOf: at(600), locale: locale)

        #expect(state.activeDeliveryCount == 1)
        #expect(state.controls == [.deliveryStep(.arriveAtPickup), .startDelivery])
    }

    @Test("Two deliveries of one offer withhold the step exactly as two offers do")
    func activityWithholdsTheStepWithinAnOffer() throws {
        let (_, grouped, groupedService) = try runningShift()
        try groupedService.startOffer(deliveryCount: 2, at: at(300))

        let (_, separate, separateService) = try runningShift()
        _ = try separateService.startDelivery(at: at(300))
        _ = try separateService.startDelivery(at: at(400))

        let groupedState = grouped.activityContentState(for: .none, asOf: at(600), locale: locale)
        let separateState = separate.activityContentState(for: .none, asOf: at(600), locale: locale)

        #expect(groupedState.controls == [.startDelivery], "No step, because there is no one delivery to mean")
        #expect(groupedState.controls == separateState.controls)
        #expect(groupedState.deliveryStatus == nil)
        #expect(groupedState.activeDeliveryCount == separateState.activeDeliveryCount)
    }

    @Test("The card still carries nothing about an offer")
    func activityCarriesNoOfferWording() throws {
        let (_, shift, service) = try runningShift()
        try service.startOffer(deliveryCount: 2, at: at(300))

        let state = shift.activityContentState(for: .none, asOf: at(600), locale: locale)
        let printed = [state.mileageStatement, state.partialRouteMarker, state.deliveryStatus]
            .compactMap { $0 }
            .joined(separator: " ")

        #expect(!printed.lowercased().contains("offer"), "Showed: \(printed)")
    }

    // MARK: Off-screen surfaces

    @Test("Start Delivery from an intent records one delivery, in an offer of one")
    func intentStartsOneDeliveryInOneOffer() throws {
        let context = try makeContext()
        let service = IntentLifecycleService(context: context)
        _ = try service.startShift(at: start)

        let outcome = try service.startDelivery(at: at(300))

        #expect(outcome == .deliveryStarted(number: 1, inProgress: 1))
        let deliveries = try context.fetch(FetchDescriptor<Delivery>())
        let offers = try context.fetch(FetchDescriptor<Offer>())
        #expect(deliveries.count == 1)
        #expect(offers.count == 1)
        #expect(offers.first?.deliveryCount == 1)
        #expect(deliveries.first?.offer?.id == offers.first?.id)
    }

    @Test("A spoken step is refused over two deliveries of one offer, and records nothing")
    func intentRefusesWithinAnOffer() throws {
        let context = try makeContext()
        let service = IntentLifecycleService(context: context)
        _ = try service.startShift(at: start)
        let offer = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(300))

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
            try service.recordDeliveryProgress(at: at(600))
        }

        // The refusal is the whole point: neither delivery moved, so nothing
        // guessed which one the driver meant.
        #expect(offer.deliveries.allSatisfy { $0.state == .accepted })
        #expect(offer.state == .inProgress)
    }

    @Test("A spoken step works again once one delivery of the offer has finished")
    func intentResolvesOnceOneIsTerminal() throws {
        let context = try makeContext()
        let service = IntentLifecycleService(context: context)
        _ = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let offer = try deliveries.startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder
        try deliveries.cancelDelivery(ordered[0], at: at(600))

        let outcome = try service.recordDeliveryProgress(at: at(900))

        #expect(outcome == .deliveryEventRecorded(number: 2, state: .arrivedAtPickup))
        #expect(ordered[0].state == .cancelled, "The cancelled sibling is untouched")
        #expect(ordered[1].state == .arrivedAtPickup)
    }
}
