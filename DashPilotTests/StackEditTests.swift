import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Correcting which deliveries in progress share a stop, across the offers they
/// were recorded in, without cancelling or recreating anything.
///
/// From a real shift on October 3 2026: two deliveries started separately
/// turned out, once the driver had parked, to share a pickup, and the only
/// correction was to cancel both and record them again as one offer. These
/// pin the edit that replaces that: identities only, one save, nothing else.
///
/// The combinations live in the planner's pure tests; the store, the
/// lifecycle boundaries, Park and the captions are exercised through the
/// service. Refused saves read the store through a **fresh context**.
@MainActor
@Suite("Stack edits")
struct StackEditTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
    private struct Refused: Error {}

    // MARK: The planner

    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let old = UUID(), other = UUID(), fresh = UUID()
    private var members: Set<UUID> { [a, b, c, d] }

    @Test("Joining two independent deliveries gives both one fresh identity")
    func joinTwo() throws {
        let plan = try SharedStopRegrouping(.join, selecting: [a, b], current: [:], members: members, fresh: fresh)
        #expect(plan.identities == [a: fresh, b: fresh])
    }

    @Test("Joining is additive: a delivery's existing group comes with it")
    func joinMergesGroups() throws {
        let current = [a: old, b: old]
        let plan = try SharedStopRegrouping(.join, selecting: [b, c], current: current, members: members, fresh: fresh)
        #expect(plan.identities == [a: fresh, b: fresh, c: fresh], "One stop is one place")
    }

    @Test("Joining two groups makes one, and leaves unrelated groups alone")
    func joinTwoGroups() throws {
        let current = [a: old, b: old, c: other, d: other]
        let plan = try SharedStopRegrouping(.join, selecting: [a, c], current: current, members: members, fresh: fresh)
        #expect(plan.identities == [a: fresh, b: fresh, c: fresh, d: fresh])

        let partial = try SharedStopRegrouping(.join, selecting: [a, b], current: [c: other, d: other], members: members, fresh: fresh)
        #expect(partial.identities == [a: fresh, b: fresh, c: other, d: other], "Two pickups in one stack")
    }

    @Test("Separating one of a pair dissolves the pair")
    func separateFromPair() throws {
        let plan = try SharedStopRegrouping(.separate, selecting: [a], current: [a: old, b: old], members: members)
        #expect(plan.identities.isEmpty, "One delivery sharing with nobody states nothing")
    }

    @Test("Separating one of three leaves the other two sharing")
    func separateFromThree() throws {
        let plan = try SharedStopRegrouping(.separate, selecting: [c], current: [a: old, b: old, c: old], members: members)
        #expect(plan.identities == [a: old, b: old])
    }

    @Test("Separating a delivery that shares nothing changes nothing")
    func separateNothing() throws {
        let current = [a: old, b: old]
        let plan = try SharedStopRegrouping(.separate, selecting: [d], current: current, members: members)
        #expect(plan.identities == current)
        #expect(plan.changes(from: current, members: members).isEmpty)
    }

    @Test("A finished member of a group stays in it when the screen does not show it")
    func finishedMemberKept() throws {
        // a has finished; the stack editor lists only b, c and d.
        let plan = try SharedStopRegrouping(
            .join, selecting: [b, c], current: [a: old, b: old], members: members, eligible: [b, c, d], fresh: fresh
        )
        #expect(plan.identities == [a: fresh, b: fresh, c: fresh])
    }

    @Test("The planner refuses what is not a statement, and names why")
    func refusals() {
        #expect(throws: SharedStopError.noDeliveries) {
            try SharedStopRegrouping(.join, selecting: [], current: [:], members: members)
        }
        #expect(throws: SharedStopError.onlyOneDelivery) {
            try SharedStopRegrouping(.join, selecting: [a], current: [:], members: members)
        }
        #expect(throws: SharedStopError.deliveryOutsideShift) {
            try SharedStopRegrouping(.join, selecting: [a, UUID()], current: [:], members: members)
        }
        #expect(throws: SharedStopError.deliveryNotInProgress) {
            try SharedStopRegrouping(.join, selecting: [a, b], current: [:], members: members, eligible: [b, c])
        }
    }

    @Test("Restating one offer keeps the statements of deliveries outside it")
    func restatingAnOffer() throws {
        // c and d are another offer, sharing with a. The offer {a, b} now says
        // only b shares nothing and a shares nothing either.
        let current = [a: old, c: old, d: old]
        let plan = try SharedStopRegrouping(restating: [], within: [a, b], current: current, members: members)
        #expect(plan.identities == [c: old, d: old])
    }

    // MARK: Through the store

    @MainActor
    private struct Store {
        let context: ModelContext
        let deliveries: DeliveryService
        var corrections: OfferCorrectionService { OfferCorrectionService(context: context) }
        var shift: Shift { get throws { try #require(try ShiftService(context: context).activeShift()) } }
    }

    private func makeStore(workflow: Bool = false, at url: URL? = nil) throws -> Store {
        let container = try url.map(ModelContainerFactory.makeContainer(at:)) ?? ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        try ShiftService(context: context).startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(workflow)
        try settings.setHandlesStackedOrdersInOrder(workflow)
        return Store(context: context, deliveries: DeliveryService(context: context))
    }

    /// The real case: two deliveries started one at a time, two offers.
    private func twoSeparateDeliveries(in store: Store) throws -> (Delivery, Delivery) {
        (try store.deliveries.startDelivery(at: at(1)), try store.deliveries.startDelivery(at: at(3)))
    }

    @Test("Two deliveries of two offers can be marked Same pickup, and nothing else moves")
    func acrossOffers() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        try store.deliveries.markArrivedAtPickup(first, at: at(5))
        try store.deliveries.setExpectedEarnings(Money(minorUnits: 725), on: second)
        let offers = [first.offer?.id, second.offer?.id]
        let numbers = try store.shift.numberedDeliveries.map(\.number)
        let instants = [first, second].map { [$0.acceptedAt, $0.arrivedAtPickupAt, $0.pickedUpAt, $0.deliveredAt] }

        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)

        #expect(first.sharedPickupID != nil)
        #expect(first.sharedPickupID == second.sharedPickupID)
        #expect(first.sharedDropOffID == nil && second.sharedDropOffID == nil, "Not the other kind")
        #expect([first.offer?.id, second.offer?.id] == offers, "No offer is recreated or merged")
        #expect(offers[0] != offers[1])
        #expect(try store.shift.numberedDeliveries.map(\.number) == numbers, "Nothing renumbered")
        #expect([first, second].map { [$0.acceptedAt, $0.arrivedAtPickupAt, $0.pickedUpAt, $0.deliveredAt] } == instants)
        #expect(second.arrivedAtPickupAt == nil, "No arrival is manufactured for the other one")
        #expect(second.expectedEarnings == Money(minorUnits: 725))
    }

    @Test("A larger stack: two pickups, then one delivery moved from one to the other")
    func largerStack() throws {
        let store = try makeStore()
        let ds = try (1...4).map { try store.deliveries.startDelivery(at: at(Double($0))) }

        try store.corrections.editSharedStops(.join, .pickup, of: [ds[0], ds[1]], on: store.shift)
        try store.corrections.editSharedStops(.join, .pickup, of: [ds[2], ds[3]], on: store.shift)
        #expect(ds[0].sharedPickupID == ds[1].sharedPickupID)
        #expect(ds[2].sharedPickupID == ds[3].sharedPickupID)
        #expect(ds[0].sharedPickupID != ds[2].sharedPickupID, "Two stops")

        try store.corrections.editSharedStops(.separate, .pickup, of: [ds[1]], on: store.shift)
        try store.corrections.editSharedStops(.join, .pickup, of: [ds[1], ds[2]], on: store.shift)
        #expect(ds[0].sharedPickupID == nil, "Left alone, it shares with nobody")
        #expect(Set([ds[1], ds[2], ds[3]].map(\.sharedPickupID)).count == 1)
    }

    @Test("Same drop-off is its own fact and changes no pickup")
    func dropOffAlone() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        try store.corrections.editSharedStops(.join, .dropOff, of: [first, second], on: store.shift)
        #expect(first.sharedDropOffID == second.sharedDropOffID && first.sharedDropOffID != nil)
        #expect(first.sharedPickupID == nil)

        try store.corrections.editSharedStops(.separate, .dropOff, of: [second], on: store.shift)
        #expect(first.sharedDropOffID == nil && second.sharedDropOffID == nil)
    }

    @Test("A picked-up delivery can be joined, and no event is written for either")
    func pickedUpBoundary() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        try store.deliveries.markArrivedAtPickup(first, at: at(5))
        try store.deliveries.markPickedUp(first, at: at(8))

        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)

        #expect(first.sharedPickupID == second.sharedPickupID)
        #expect(first.pickedUpAt == at(8))
        #expect(second.state == .accepted, "Saying where it was collected collects nothing")
    }

    @Test("A delivered or cancelled delivery cannot be named, and the refusal writes nothing")
    func finishedBoundary() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        let third = try store.deliveries.startDelivery(at: at(4))
        try store.deliveries.markArrivedAtPickup(first, at: at(5))
        try store.deliveries.markPickedUp(first, at: at(6))
        try store.deliveries.markDelivered(first, at: at(9))
        try store.deliveries.cancelDelivery(third, at: at(10))

        for finished in [first, third] {
            #expect(throws: OfferCorrectionError.invalidSharedStop(.deliveryNotInProgress)) {
                try store.corrections.editSharedStops(.join, .pickup, of: [finished, second], on: store.shift)
            }
        }
        let stored = try ModelContext(store.context.container).fetch(FetchDescriptor<Delivery>())
        #expect(stored.allSatisfy { $0.sharedPickupID == nil })
    }

    @Test("A group holding a finished delivery stays whole when an active member is joined")
    func finishedMemberKeptThroughTheStore() throws {
        let store = try makeStore()
        let offer = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(1)).deliveriesInOrder
        let later = try store.deliveries.startDelivery(at: at(3))
        try store.deliveries.markArrivedAtPickup(offer[0], at: at(4))
        try store.deliveries.markPickedUp(offer[0], at: at(5))
        try store.deliveries.markDelivered(offer[0], at: at(6))

        try store.corrections.editSharedStops(.join, .dropOff, of: [offer[1], later], on: store.shift)

        #expect(Set((offer + [later]).map(\.sharedDropOffID)).count == 1, "All three, one door")
        #expect(offer[0].deliveredAt == at(6))
    }

    @Test("Joining, separating and relaunching: what was said is what is stored")
    func survivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "stack-edit-\(UUID().uuidString).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        var ids: [UUID] = []
        do {
            let store = try makeStore(at: url)
            let (first, second) = try twoSeparateDeliveries(in: store)
            ids = [first.id, second.id]
            try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)
            try store.corrections.editSharedStops(.join, .dropOff, of: [first, second], on: store.shift)
            try store.corrections.editSharedStops(.separate, .dropOff, of: [first], on: store.shift)
        }
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let stored = try reopened.fetch(FetchDescriptor<Delivery>())
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        let first = try #require(byID[ids[0]]), second = try #require(byID[ids[1]])
        #expect(first.sharedPickupID != nil && first.sharedPickupID == second.sharedPickupID)
        #expect(first.sharedDropOffID == nil && second.sharedDropOffID == nil)
        #expect(first.offer?.id != second.offer?.id)
    }

    @Test("A refused save leaves the store and the held models as they were")
    func refusedSave() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        let failing = OfferCorrectionService(context: store.context, commit: { _ in throw Refused() })

        #expect(throws: OfferCorrectionError.self) {
            try failing.editSharedStops(.join, .pickup, of: [first, second], on: try store.shift)
        }
        let stored = try ModelContext(store.context.container).fetch(FetchDescriptor<Delivery>())
        #expect(stored.allSatisfy { $0.sharedPickupID == nil })
    }

    // MARK: What reads it

    @Test("Park and Resume move a cross-offer Same pickup pair together, as they do an offer's")
    func parkReadsTheEdit() throws {
        let store = try makeStore(workflow: true)
        let (first, second) = try twoSeparateDeliveries(in: store)
        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)

        let parking = ParkVehicleService(context: store.context)
        let parked = try parking.park(at: at(10))
        #expect(parked.pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [1, 2], alreadyArrived: [])))
        let resumed = try parking.resumeDriving(at: at(15))
        #expect([first, second].allSatisfy { $0.pickedUpAt == at(15) })
        #expect(resumed.automatedSteps.count == 2)
    }

    @Test("An edit while parked changes the next Park, not the Resume of this one")
    func editWhileParked() throws {
        let store = try makeStore(workflow: true)
        let (first, second) = try twoSeparateDeliveries(in: store)
        let parking = ParkVehicleService(context: store.context)
        _ = try parking.park(at: at(10))
        #expect(first.state == .arrivedAtPickup && second.state == .accepted)

        // The driver realises, parked, that the second order is at this counter.
        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)
        _ = try parking.resumeDriving(at: at(15))

        #expect(first.pickedUpAt == at(15))
        #expect(second.pickedUpAt == nil, "Resume completes what Park stored, and nothing it did not")
        #expect(second.arrivedAtPickupAt == nil, "No arrival is written after the fact")
    }

    @Test("Each card names its cross-offer sibling, and the spoken caption says the driver recorded it")
    func captionAcrossOffers() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)

        let numbered = try store.shift.numberedDeliveries
        #expect(numbered[0].sharedStops.caption == "Same pickup as Delivery 2")
        #expect(numbered[1].sharedStops.caption == "Same pickup as Delivery 1")
        #expect(numbered[0].sharedStops.spokenCaption == "You recorded it as the same pickup as Delivery 2")
    }

    @Test("Export numbers a cross-offer group as one shift-local group")
    func exportAcrossOffers() throws {
        let store = try makeStore()
        let (first, second) = try twoSeparateDeliveries(in: store)
        _ = try store.deliveries.startDelivery(at: at(4))
        try store.corrections.editSharedStops(.join, .pickup, of: [first, second], on: store.shift)
        let shift = try store.shift
        for delivery in shift.deliveries where delivery.isActive {
            try store.deliveries.cancelDelivery(delivery, at: at(20))
        }
        try ShiftService(context: store.context).endActiveShift(at: at(30))

        let record = try shift.exportRecord(for: shift.recordedDistance())
        #expect(record.deliveries.map(\.sharedPickupGroup) == [1, 1, nil])
    }
}
