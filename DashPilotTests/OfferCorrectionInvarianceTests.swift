import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a grouping correction must leave exactly where it found it.
///
/// These are the negative claims the feature rests on. An offer is a grouping
/// and nothing else: no figure the app derives reads which offer a delivery came
/// in, so regrouping must move no money, no duration, no distance, no count and
/// no recorded fact. The only thing in the whole app that may change is the
/// grouping key, and the export's `offerNumber` is asserted to follow it.
///
/// Every timestamp, amount and name here is invented.
@MainActor
@Suite("Offer correction invariance")
struct OfferCorrectionInvarianceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A shift holding two offers, one grouped, with a pickup place, an expected
    /// amount and a recorded gross spread across them, and one delivery already
    /// terminal.
    private func workedShift() throws -> (context: ModelContext, shift: Shift, offers: [Offer]) {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let places = PickupPlaceService(context: context)

        let grouped = try deliveries.startOffer(deliveryCount: 2, at: at(300))
        let ordered = grouped.deliveriesInOrder
        try places.assignPlace(named: "Nowhere Noodles", to: ordered[0], at: at(360))
        try deliveries.setExpectedEarnings(try #require(Money(exact: "8.50")), on: ordered[1])
        try deliveries.markArrivedAtPickup(ordered[0], at: at(600))
        try deliveries.markPickedUp(ordered[0], at: at(1_200))
        try deliveries.markDelivered(ordered[0], at: at(2_100))
        try deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: ordered[0])
        try deliveries.markArrivedAtPickup(ordered[1], at: at(900))

        let addOn = try deliveries.startOffer(deliveryCount: 1, at: at(1_800))
        try deliveries.markArrivedAtPickup(try #require(addOn.deliveriesInOrder.first), at: at(2_400))

        return (context, shift, [grouped, addOn])
    }

    /// Every fact a delivery records, as values, so a comparison survives the
    /// object being mutated in between.
    private struct DeliveryFacts: Equatable {
        let id: UUID
        let shiftID: UUID?
        let state: DeliveryState
        let acceptedAt: Date
        let arrivedAtPickupAt: Date?
        let pickedUpAt: Date?
        let deliveredAt: Date?
        let cancelledAt: Date?
        let pickupPlaceID: UUID?
        let grossEarnings: Money?
        let expectedEarnings: Money?
        let pickupWait: TimeInterval?

        init(_ delivery: Delivery) {
            id = delivery.id
            shiftID = delivery.shift?.id
            state = delivery.state
            acceptedAt = delivery.acceptedAt
            arrivedAtPickupAt = delivery.arrivedAtPickupAt
            pickedUpAt = delivery.pickedUpAt
            deliveredAt = delivery.deliveredAt
            cancelledAt = delivery.cancelledAt
            pickupPlaceID = delivery.pickupPlace?.id
            grossEarnings = delivery.grossEarnings
            expectedEarnings = delivery.expectedEarnings
            pickupWait = delivery.pickupWait
        }
    }

    private func facts(of shift: Shift) -> [DeliveryFacts] {
        shift.deliveries.map(DeliveryFacts.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: Nothing a delivery records moves

    @Test("Every lifecycle timestamp, place and amount survives a move, on an active and a terminal delivery")
    func deliveryFactsSurviveAMove() throws {
        let (context, shift, offers) = try workedShift()
        let before = facts(of: shift)
        let moving = try #require(offers[1].deliveriesInOrder.first)

        try OfferCorrectionService(context: context).move(moving, into: offers[0])

        #expect(facts(of: shift) == before, "A correction moved something other than membership")
        #expect(moving.offer?.id == offers[0].id, "And it did move the membership")
    }

    @Test("Every delivery fact survives a split, a merge and a separation")
    func deliveryFactsSurviveEveryCorrection() throws {
        let (context, shift, offers) = try workedShift()
        let before = facts(of: shift)
        let corrections = OfferCorrectionService(context: context)

        let split = try corrections.split([try #require(offers[0].deliveriesInOrder.last)])
        #expect(facts(of: shift) == before, "A split moved something other than membership")

        try corrections.merge(split, into: offers[0])
        #expect(facts(of: shift) == before, "A merge moved something other than membership")

        try corrections.separate(offers[0])
        #expect(facts(of: shift) == before, "A separation moved something other than membership")
        #expect(shift.numberedOffers.allSatisfy { $0.isGrouped == false })
    }

    // MARK: No figure moves

    @Test("Shift gross, delivery gross, expected pay and every derived rate are unmoved by regrouping")
    func figuresAreUnmoved() throws {
        let (context, shift, offers) = try workedShift()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        // Finished, because a shift's own gross may only be recorded against a
        // completed shift. Every delivery here is therefore terminal, which is
        // the half of the claim about correcting history rather than a running
        // shift.
        for delivery in shift.deliveries where delivery.isActive {
            if delivery.pickedUpAt == nil { try deliveries.markPickedUp(delivery, at: at(2_700)) }
            try deliveries.markDelivered(delivery, at: at(3_000))
        }
        try shifts.endActiveShift(at: at(3_600))
        try shifts.setGrossEarnings(try #require(Money(exact: "100.00")), on: shift)

        let distance = RouteDistance.none
        let before = shift.metrics(for: distance)
        let beforeActive = shift.deliveryActiveTime()
        let beforeSummary = shift.deliverySummary
        let beforeGross = shift.grossEarnings
        let beforeDeliveryGross = shift.deliveries.compactMap(\.grossEarnings).reduce(Money.zero, +)

        try OfferCorrectionService(context: context)
            .move(try #require(offers[1].deliveriesInOrder.first), into: offers[0])

        let after = shift.metrics(for: distance)
        #expect(shift.grossEarnings == beforeGross)
        #expect(shift.deliveries.compactMap(\.grossEarnings).reduce(Money.zero, +) == beforeDeliveryGross)
        #expect(shift.deliveryActiveTime().duration == beforeActive.duration, "The union is over deliveries, not offers")
        #expect(shift.deliveryActiveTime().isAvailable == beforeActive.isAvailable)
        #expect(shift.deliverySummary == beforeSummary)
        #expect(after.grossPerWorkingHour.amount == before.grossPerWorkingHour.amount)
        #expect(after.grossPerDeliveryActiveHour.amount == before.grossPerDeliveryActiveHour.amount)
        #expect(after.grossPerRecordedMile.amount == before.grossPerRecordedMile.amount)
        #expect(after.recordedDistance == before.recordedDistance, "No route was recorded, and none was invented")
    }

    @Test("The Live Activity's active-delivery count is unmoved by regrouping")
    func activeCountIsUnmoved() throws {
        let (context, shift, offers) = try workedShift()
        let before = shift.activityContentState(for: .none, asOf: at(3_000), locale: Locale(identifier: "en_US"))

        try OfferCorrectionService(context: context)
            .merge(offers[1], into: offers[0])

        let after = shift.activityContentState(for: .none, asOf: at(3_000), locale: Locale(identifier: "en_US"))
        #expect(after.activeDeliveryCount == before.activeDeliveryCount)
        #expect(after.activeDeliveryCount == 2, "Two deliveries are still running, in one offer now rather than two")
        #expect(after.completedDeliveryCount == before.completedDeliveryCount)
        #expect(after.controls == before.controls, "And the step is still withheld for the same reason")
    }

    @Test("Pickup waits and their per-place samples are unmoved by regrouping")
    func pickupWaitsAreUnmoved() throws {
        let (context, shift, offers) = try workedShift()
        let place = try #require(shift.deliveries.compactMap(\.pickupPlace).first)
        let before = place.deliveries.compactMap(\.pickupWait).sorted()

        try OfferCorrectionService(context: context)
            .split([try #require(offers[0].deliveriesInOrder.first)])

        #expect(place.deliveries.compactMap(\.pickupWait).sorted() == before)
        #expect(place.deliveries.count == 1, "The delivery is still recorded against the place it named")
    }

    @Test("Period aggregates over a corrected shift report exactly what they reported before")
    func periodAggregatesAreUnmoved() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let offer = try deliveries.startOffer(deliveryCount: 2, at: at(300))
        for delivery in offer.deliveriesInOrder {
            try deliveries.markArrivedAtPickup(delivery, at: at(600))
            try deliveries.markPickedUp(delivery, at: at(1_200))
            try deliveries.markDelivered(delivery, at: at(2_100))
        }
        try shifts.endActiveShift(at: at(3_600))
        try shifts.setGrossEarnings(try #require(Money(exact: "80.00")), on: shift)

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: .current))
        let calculator = PeriodMetricsCalculator()
        let before = calculator.metrics(of: [shift.periodRecord(for: .none)], in: period)

        try OfferCorrectionService(context: context).separate(offer)

        let after = calculator.metrics(of: [shift.periodRecord(for: .none)], in: period)
        #expect(after == before, "A period figure read which deliveries arrived together")
    }

    // MARK: The one thing that does move

    @Test("The export's offer number follows the corrected grouping, under the same version")
    func exportFollowsTheCorrection() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.deliveredOffer(in: shift, deliveryCount: 2, acceptedAfter: 300, earnings: ["14.75", nil])
        try fixture.delivered(in: shift, acceptedAfter: 5_400, earnings: "6.25")

        let before = try fixture.exportRecord(of: shift)
        #expect(before.deliveries.map(\.offerNumber) == [1, 1, 2])

        // The third delivery was really part of the first acceptance.
        let third = try #require(shift.numberedDeliveries.last)
        let first = try #require(shift.numberedOffers.first)
        try OfferCorrectionService(context: fixture.context).move(third.delivery, into: first.offer)

        let after = try fixture.exportRecord(of: shift)
        #expect(after.deliveries.map(\.offerNumber) == [1, 1, 1], "All three are now recorded as one acceptance")
        #expect(after.deliveries.map(\.number) == before.deliveries.map(\.number), "Delivery numbers are unmoved")
        #expect(after.deliveries.map(\.grossEarnings) == before.deliveries.map(\.grossEarnings))
        #expect(after.deliveries.map(\.acceptedAt) == before.deliveries.map(\.acceptedAt))
        #expect(after.grossEarnings == before.grossEarnings)
        #expect(after.deliveryActiveSeconds == before.deliveryActiveSeconds)
        #expect(ExportFormat.version == 4, "Correcting a grouping moves values, never the contract")
    }

    @Test("Removing an offer renumbers the offers that outlive it, with nothing stored to go stale")
    func exportRenumbersAfterAMerge() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.delivered(in: shift, acceptedAfter: 300)
        try fixture.delivered(in: shift, acceptedAfter: 3_600)
        try fixture.delivered(in: shift, acceptedAfter: 7_200)

        #expect(try fixture.exportRecord(of: shift).deliveries.map(\.offerNumber) == [1, 2, 3])

        let offers = shift.numberedOffers
        try OfferCorrectionService(context: fixture.context).merge(offers[1].offer, into: offers[0].offer)

        #expect(
            try fixture.exportRecord(of: shift).deliveries.map(\.offerNumber) == [1, 1, 2],
            "The third offer became the second, because the numbering is counted rather than stored"
        )
    }

    // MARK: Paths the correction must leave alone

    @Test("Start Delivery still records one delivery in an offer of one after a correction elsewhere")
    func theOneTapPathIsUnchanged() throws {
        let (context, shift, offers) = try workedShift()
        try OfferCorrectionService(context: context).separate(offers[0])

        let delivery = try DeliveryService(context: context).startDelivery(at: at(3_000))

        #expect(delivery.offer?.deliveryCount == 1)
        #expect(delivery.offer?.acceptedAt == delivery.acceptedAt)
        #expect(shift.numberedOffers.last?.deliveryCount == 1)
    }

    @Test("A historical one-delivery offer is a valid correction subject and a valid destination")
    func migratedOffersRemainValid() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)

        // Exactly what the v11 to v12 migration writes: a delivery with no offer,
        // given its own one-delivery offer taking its own acceptance.
        let first = Delivery(shift: shift, acceptedAt: at(300))
        let second = Delivery(shift: shift, acceptedAt: at(900))
        context.insert(first)
        context.insert(second)
        for delivery in [first, second] {
            let offer = try #require(delivery.makeHistoricalOffer())
            context.insert(offer)
        }
        try context.save()

        let corrections = OfferCorrectionService(context: context)
        let destinations = corrections.moveDestinations(for: second)
        #expect(destinations.count == 1)
        try corrections.move(second, into: try #require(destinations.first))

        #expect(shift.offers.count == 1, "The migrated offer left holding nothing was removed")
        #expect(shift.offers.first?.deliveryCount == 2)
        #expect(first.acceptedAt == at(300))
        #expect(second.acceptedAt == at(900), "Neither migrated acceptance was rewritten")
    }

    @Test("A store holding an offer with no deliveries is read, and corrected around, without crashing")
    func malformedEmptyOfferIsSurvivable() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let real = try DeliveryService(context: context).startOffer(deliveryCount: 2, at: at(300))

        // A row the app cannot produce. It is inserted directly, which is the
        // only way to reach one.
        let empty = Offer(shift: shift, acceptedAt: at(120))
        context.insert(empty)
        try context.save()

        #expect(empty.state == .empty)
        #expect(empty.isTerminal == false)
        #expect(shift.numberedOffers.count == 2, "Both offers are numbered, the empty one included")
        #expect(shift.numberedOffers.map(\.deliveryCount) == [0, 2])

        let corrections = OfferCorrectionService(context: context)
        #expect(
            corrections.moveDestinations(for: try #require(real.deliveriesInOrder.first)).map(\.id) == [empty.id],
            "It is a destination like any other: accepted earlier, and able to hold the work"
        )
        #expect(corrections.mergeDestinations(for: empty).map(\.id) == [real.id])

        // Merging the empty one away is how it is removed, and it takes nothing
        // with it.
        try corrections.merge(empty, into: real)
        #expect(shift.offers.count == 1)
        #expect(real.deliveryCount == 2)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 2)
    }
}
