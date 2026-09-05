import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Resolving a typed name to a place, attaching it to a delivery, and the
/// reuse rule that is the whole reason a place is an entity.
///
/// Every name below is invented. The repository names no real business.
@MainActor
@Suite("Pickup place service")
struct PickupPlaceServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A running shift with `count` deliveries on it, accepted five minutes
    /// apart, through the real services.
    @discardableResult
    private func makeDeliveries(_ count: Int, in context: ModelContext) throws -> [Delivery] {
        try ShiftService(context: context).startShift(at: start)
        let deliveries = DeliveryService(context: context)
        return try (0..<count).map { index in
            try deliveries.startDelivery(at: at(Double(index) * 300))
        }
    }

    private func storedPlaces(in context: ModelContext) throws -> [PickupPlace] {
        try context.fetch(FetchDescriptor<PickupPlace>()).sorted(by: PickupPlace.namedBefore)
    }

    // MARK: Resolution

    @Test("A name not seen before creates exactly one place")
    func createsOnePlaceForANewName() throws {
        let context = try makeContext()
        let service = PickupPlaceService(context: context)

        let place = try service.resolvePlace(named: "Nowhere Noodles", at: start)

        #expect(place.displayName == "Nowhere Noodles")
        #expect(try storedPlaces(in: context).count == 1)
        #expect(place.createdAt == start)
    }

    @Test("An equivalent name later reuses the same place", arguments: [
        "Nowhere Noodles",
        "nowhere noodles",
        "NOWHERE NOODLES",
        "  Nowhere   Noodles  "
    ])
    func reusesAPlaceForAnEquivalentName(_ laterSpelling: String) throws {
        let context = try makeContext()
        let service = PickupPlaceService(context: context)

        let first = try service.resolvePlace(named: "Nowhere Noodles", at: start)
        let second = try service.resolvePlace(named: laterSpelling, at: at(86_400))

        #expect(first.id == second.id, "\(laterSpelling) is the same place")
        #expect(try storedPlaces(in: context).count == 1, "And no second row was created for it")
    }

    @Test("A genuinely different name creates a separate place")
    func createsSeparatePlacesForDifferentNames() throws {
        let context = try makeContext()
        let service = PickupPlaceService(context: context)

        let noodles = try service.resolvePlace(named: "Nowhere Noodles", at: start)
        let diner = try service.resolvePlace(named: "Example Diner", at: at(60))

        #expect(noodles.id != diner.id)
        #expect(try storedPlaces(in: context).count == 2)
    }

    @Test("Names distinguished only by punctuation stay separate places")
    func punctuationSeparatesPlaces() throws {
        let context = try makeContext()
        let service = PickupPlaceService(context: context)

        try service.resolvePlace(named: "A&B Grill", at: start)
        try service.resolvePlace(named: "AB Grill", at: at(60))

        #expect(
            try storedPlaces(in: context).count == 2,
            "Conservative normalisation keeps names the driver may mean to distinguish apart"
        )
    }

    @Test("The first accepted spelling is never rewritten by a later one")
    func firstSpellingWins() throws {
        let context = try makeContext()
        let service = PickupPlaceService(context: context)

        let original = try service.resolvePlace(named: "Nowhere Noodles", at: start)
        try service.resolvePlace(named: "NOWHERE NOODLES", at: at(3_600))
        try service.resolvePlace(named: "nowhere noodles", at: at(7_200))

        #expect(
            original.displayName == "Nowhere Noodles",
            "A place a driver has been reading all week is not restyled behind them"
        )
        #expect(try storedPlaces(in: context).count == 1)
    }

    @Test("An unusable name is refused and creates nothing", arguments: ["", "   ", "\n\t"])
    func refusesAnEmptyName(_ text: String) throws {
        let context = try makeContext()

        #expect(throws: PickupPlaceError.invalidName(.empty)) {
            try PickupPlaceService(context: context).resolvePlace(named: text, at: start)
        }
        #expect(try storedPlaces(in: context).isEmpty)
    }

    @Test("An oversized name is refused and creates nothing")
    func refusesAnOversizedName() throws {
        let context = try makeContext()
        let text = String(repeating: "a", count: PickupPlaceName.maximumLength + 1)

        #expect(throws: PickupPlaceError.invalidName(.tooLong(maximum: PickupPlaceName.maximumLength))) {
            try PickupPlaceService(context: context).resolvePlace(named: text, at: start)
        }
        #expect(try storedPlaces(in: context).isEmpty)
    }

    // MARK: Assignment

    @Test("A place is recorded against the delivery it was assigned to")
    func assignsAPlaceToADelivery() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(2, in: context)

        let place = try PickupPlaceService(context: context)
            .assignPlace(named: "Nowhere Noodles", to: deliveries[0], at: start)

        #expect(deliveries[0].pickupPlace?.id == place.id)
        #expect(deliveries[1].pickupPlace == nil, "And to no other delivery")
    }

    @Test("Assigning a place changes no lifecycle timestamp")
    func assignmentIsNotALifecycleEvent() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let deliveries = DeliveryService(context: context)
        try deliveries.markArrivedAtPickup(delivery, at: at(300))
        try deliveries.markPickedUp(delivery, at: at(600))

        try PickupPlaceService(context: context).assignPlace(named: "Nowhere Noodles", to: delivery, at: at(700))

        #expect(delivery.acceptedAt == start)
        #expect(delivery.arrivedAtPickupAt == at(300))
        #expect(delivery.pickedUpAt == at(600))
        #expect(delivery.state == .pickedUp, "Naming a pickup does not advance anything")
        #expect(delivery.pickupWait == 300)
    }

    @Test("A delivery's place can be changed to another one")
    func changesAPlace() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let service = PickupPlaceService(context: context)

        try service.assignPlace(named: "Nowhere Noodles", to: delivery, at: start)
        let corrected = try service.assignPlace(named: "Example Diner", to: delivery, at: at(60))

        #expect(delivery.pickupPlace?.id == corrected.id)
        #expect(delivery.pickupPlace?.displayName == "Example Diner")
        #expect(try storedPlaces(in: context).count == 2, "The place tapped by mistake stays in the catalogue")
    }

    @Test("A delivery's place can be removed, leaving the delivery intact")
    func removesAPlace() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let service = PickupPlaceService(context: context)
        try service.assignPlace(named: "Nowhere Noodles", to: delivery, at: start)

        try service.removePlace(from: delivery)

        #expect(delivery.pickupPlace == nil)
        #expect(delivery.acceptedAt == start, "The delivery itself is untouched")
        #expect(try storedPlaces(in: context).count == 1, "The place remains available to other deliveries")
    }

    @Test("Removing a place from a delivery that has none does nothing")
    func removingNothingIsNotAFailure() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)

        try PickupPlaceService(context: context).removePlace(from: delivery)

        #expect(delivery.pickupPlace == nil)
    }

    @Test("Repeated assignment of the same name creates no duplicate")
    func repeatedAssignmentCreatesNoDuplicate() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(4, in: context)
        let service = PickupPlaceService(context: context)

        for (index, delivery) in deliveries.enumerated() {
            // The same place, spelled a different way each time.
            let spellings = ["Nowhere Noodles", "nowhere noodles", "NOWHERE  NOODLES", " Nowhere Noodles "]
            try service.assignPlace(named: spellings[index], to: delivery, at: at(Double(index) * 60))
        }

        let places = try storedPlaces(in: context)
        #expect(places.count == 1, "Four assignments, one place")
        #expect(Set(deliveries.compactMap(\.pickupPlace?.id)).count == 1, "All four point at it")
    }

    @Test("One place belongs to several deliveries, and each delivery to one place")
    func onePlaceManyDeliveries() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(3, in: context)
        let service = PickupPlaceService(context: context)

        try service.assignPlace(named: "Nowhere Noodles", to: deliveries[0], at: start)
        try service.assignPlace(named: "Example Diner", to: deliveries[1], at: at(60))
        try service.assignPlace(named: "nowhere noodles", to: deliveries[2], at: at(120))

        let noodles = try #require(deliveries[0].pickupPlace)
        #expect(deliveries[2].pickupPlace?.id == noodles.id)
        #expect(Set(noodles.deliveries.map(\.id)) == [deliveries[0].id, deliveries[2].id])
        #expect(deliveries[1].pickupPlace?.deliveries.count == 1)
    }

    @Test("A delivery on a completed shift can still be corrected")
    func editsACompletedDelivery() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let deliveries = DeliveryService(context: context)
        try deliveries.markArrivedAtPickup(delivery, at: at(300))
        try deliveries.markPickedUp(delivery, at: at(600))
        try deliveries.markDelivered(delivery, at: at(900))
        try ShiftService(context: context).endActiveShift(at: at(3_600))

        // The lifecycle refuses to move, and pickup identity is deliberately not
        // governed by it: a driver reviewing history must be able to fix a name
        // without deleting the shift.
        #expect(throws: DeliveryLifecycleError.deliveryNotOnARunningShift) {
            try deliveries.markDelivered(delivery, at: at(1_200))
        }

        let service = PickupPlaceService(context: context)
        try service.assignPlace(named: "Nowhere Noodles", to: delivery, at: at(4_000))
        #expect(delivery.pickupPlace?.displayName == "Nowhere Noodles")

        try service.assignPlace(named: "Example Diner", to: delivery, at: at(4_100))
        #expect(delivery.pickupPlace?.displayName == "Example Diner")

        try service.removePlace(from: delivery)
        #expect(delivery.pickupPlace == nil)
        #expect(delivery.deliveredAt == at(900), "None of it touched the lifecycle")
    }

    @Test("A cancelled delivery can still name where it was going to pick up")
    func editsACancelledDelivery() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let deliveries = DeliveryService(context: context)
        try deliveries.markArrivedAtPickup(delivery, at: at(300))
        try deliveries.cancelDelivery(delivery, at: at(1_500))

        try PickupPlaceService(context: context).assignPlace(named: "Nowhere Noodles", to: delivery, at: at(1_600))

        #expect(delivery.pickupPlace?.displayName == "Nowhere Noodles")
        #expect(delivery.state == .cancelled, "A waited-then-cancelled delivery is exactly the one worth naming")
    }

    // MARK: Recent places

    @Test("Recent places are ordered by the latest delivery that used them")
    func ordersRecentPlacesByUse() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(3, in: context)
        let service = PickupPlaceService(context: context)

        // Created oldest first, used in the opposite order.
        try service.assignPlace(named: "Nowhere Noodles", to: deliveries[0], at: start)
        try service.assignPlace(named: "Example Diner", to: deliveries[1], at: at(60))
        try service.assignPlace(named: "Sample Sandwiches", to: deliveries[2], at: at(120))

        #expect(
            try service.recentPlaces().map(\.displayName) == [
                "Sample Sandwiches",
                "Example Diner",
                "Nowhere Noodles"
            ],
            "Most recently used first, taken from the deliveries rather than a stored date"
        )
    }

    @Test("Reusing a place moves it back to the front")
    func reuseUpdatesRecency() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(3, in: context)
        let service = PickupPlaceService(context: context)

        try service.assignPlace(named: "Nowhere Noodles", to: deliveries[0], at: start)
        try service.assignPlace(named: "Example Diner", to: deliveries[1], at: at(60))
        // deliveries[2] was accepted last, so naming the older place with it is
        // what makes that place the most recently used.
        try service.assignPlace(named: "nowhere noodles", to: deliveries[2], at: at(120))

        #expect(try service.recentPlaces().map(\.displayName) == ["Nowhere Noodles", "Example Diner"])
    }

    @Test("A place no delivery references is not recent, and is not deleted either")
    func unreferencedPlacesAreNotRecent() throws {
        let context = try makeContext()
        let delivery = try #require(try makeDeliveries(1, in: context).first)
        let service = PickupPlaceService(context: context)
        try service.assignPlace(named: "Nowhere Noodles", to: delivery, at: start)

        try service.removePlace(from: delivery)

        #expect(try service.recentPlaces().isEmpty, "Recency comes from deliveries, and there are none")
        #expect(
            try service.allPlaces().map(\.displayName) == ["Nowhere Noodles"],
            "The catalogue keeps it: typing the name again finds it rather than making a second one"
        )
    }

    @Test("The recent list is capped, and asking for none returns none")
    func capsTheRecentList() throws {
        let context = try makeContext()
        let deliveries = try makeDeliveries(7, in: context)
        let service = PickupPlaceService(context: context)
        for (index, delivery) in deliveries.enumerated() {
            try service.assignPlace(named: "Nowhere Kitchen \(index)", to: delivery, at: at(Double(index)))
        }

        #expect(try service.recentPlaces().count == PickupPlaceService.recentPlaceLimit)
        #expect(try service.recentPlaces(limit: 2).count == 2)
        #expect(try service.recentPlaces(limit: 0).isEmpty)
    }

    @Test("The recent order is repeatable when two places have equal claim")
    func recentOrderIsDeterministic() throws {
        let context = try makeContext()
        try ShiftService(context: context).startShift(at: start)
        let deliveries = DeliveryService(context: context)
        // Two deliveries accepted in the same instant, so recency alone cannot
        // separate the places they name.
        let first = try deliveries.startDelivery(at: at(300))
        let second = try deliveries.startDelivery(at: at(300))
        let service = PickupPlaceService(context: context)

        try service.assignPlace(named: "Nowhere Noodles", to: first, at: start)
        try service.assignPlace(named: "Example Diner", to: second, at: at(60))

        let ordered = try service.recentPlaces().map(\.displayName)
        #expect(ordered.count == 2)
        #expect(
            ordered == ["Example Diner", "Nowhere Noodles"],
            "The tie falls to the place named later, and it falls the same way every read"
        )
        #expect(try service.recentPlaces().map(\.displayName) == ordered)
    }

    // MARK: Deletion

    @Test("Deleting a shift deletes its deliveries and spares a shared place")
    func shiftDeletionSparesASharedPlace() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        let places = PickupPlaceService(context: context)

        // Two shifts, both picking up from the same place.
        try shifts.startShift(at: start)
        let first = try deliveries.startDelivery(at: at(60))
        try places.assignPlace(named: "Nowhere Noodles", to: first, at: at(60))
        try deliveries.markArrivedAtPickup(first, at: at(120))
        try deliveries.markPickedUp(first, at: at(180))
        try deliveries.markDelivered(first, at: at(240))
        let doomedShift = try #require(try shifts.activeShift())
        try shifts.endActiveShift(at: at(3_600))

        try shifts.startShift(at: at(7_200))
        let second = try deliveries.startDelivery(at: at(7_260))
        try places.assignPlace(named: "nowhere noodles", to: second, at: at(7_260))
        try deliveries.markArrivedAtPickup(second, at: at(7_320))
        try deliveries.markPickedUp(second, at: at(7_380))
        try deliveries.markDelivered(second, at: at(7_440))
        try shifts.endActiveShift(at: at(10_800))

        #expect(try storedPlaces(in: context).count == 1, "One place, shared by both shifts")

        try shifts.deleteCompletedShift(doomedShift)

        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1, "The deleted shift took its delivery")
        let surviving = try storedPlaces(in: context)
        #expect(surviving.count == 1, "But not the place another shift still names")
        #expect(surviving.first?.deliveries.count == 1, "Which now knows about one delivery, not two")
        #expect(second.pickupPlace?.id == surviving.first?.id, "And the surviving delivery still names it")
    }

    @Test("Deleting the only shift that used a place leaves the place behind")
    func placeSurvivesItsLastDelivery() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)

        try shifts.startShift(at: start)
        let delivery = try deliveries.startDelivery(at: at(60))
        try PickupPlaceService(context: context).assignPlace(named: "Nowhere Noodles", to: delivery, at: at(60))
        try deliveries.markArrivedAtPickup(delivery, at: at(120))
        try deliveries.markPickedUp(delivery, at: at(180))
        try deliveries.markDelivered(delivery, at: at(240))
        let shift = try #require(try shifts.activeShift())
        try shifts.endActiveShift(at: at(3_600))

        try shifts.deleteCompletedShift(shift)

        #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        #expect(
            try storedPlaces(in: context).count == 1,
            "Deleting a shift must not delete vocabulary as a side effect; it is not garbage collected"
        )
        #expect(try PickupPlaceService(context: context).recentPlaces().isEmpty, "It is simply no longer recent")
    }
}
