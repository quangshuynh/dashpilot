import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// A store, a running shift and the services every correction test drives.
///
/// Built through the real services rather than by inserting rows, so the
/// relationships a merge walks are the ones SwiftData actually maintains.
///
/// Every name below is invented. The repository names no real business.
@MainActor
private struct CorrectionFixture {
    let container: ModelContainer
    let context: ModelContext
    let places: PickupPlaceService
    let deliveries: DeliveryService
    let shift: Shift
    let start: Date

    /// `commit` substitutes for `ModelContext.save()`, which is the only way to
    /// exercise what a refused save leaves behind — see the atomicity tests.
    init(
        start: Date = Date(timeIntervalSince1970: 1_756_000_000),
        commit: ((ModelContext) throws -> Void)? = nil
    ) throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        self.context = context
        self.start = start
        places = commit.map { PickupPlaceService(context: context, commit: $0) }
            ?? PickupPlaceService(context: context)
        deliveries = DeliveryService(context: context)
        shift = try ShiftService(context: context).startShift(at: start)
    }

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// One delivery accepted five minutes before `arrival`, picked up `wait`
    /// minutes after arriving, and delivered ten minutes after that.
    ///
    /// A `nil` wait records an arrival and then a cancellation, which is the
    /// lifecycle that contributes no pickup wait.
    @discardableResult
    func recordDelivery(
        arrivingAt arrival: Double,
        waiting wait: Double?,
        at place: PickupPlace? = nil
    ) throws -> Delivery {
        let delivery = try deliveries.startDelivery(at: at(arrival - 5))
        try deliveries.markArrivedAtPickup(delivery, at: at(arrival))
        if let wait {
            try deliveries.markPickedUp(delivery, at: at(arrival + wait))
            try deliveries.markDelivered(delivery, at: at(arrival + wait + 10))
        } else {
            try deliveries.cancelDelivery(delivery, at: at(arrival + 30))
        }
        if let place { try places.assign(place, to: delivery) }
        return delivery
    }

    /// A delivery left running, so an active-delivery case can be covered.
    @discardableResult
    func recordActiveDelivery(acceptedAt accepted: Double, at place: PickupPlace? = nil) throws -> Delivery {
        let delivery = try deliveries.startDelivery(at: at(accepted))
        if let place { try places.assign(place, to: delivery) }
        return delivery
    }

    func storedPlaces() throws -> [PickupPlace] {
        try context.fetch(FetchDescriptor<PickupPlace>()).sorted(by: PickupPlace.namedBefore)
    }

    /// A second context over the same store, which is the only way to read what
    /// the store actually holds after a rollback.
    ///
    /// `ModelContext.rollback()` restores the store, and the reopen tests in
    /// `PickupPlacePersistenceTests` confirm the same across a real file. What it
    /// does **not** reliably restore is the relationship arrays cached on model
    /// objects a test is still holding — after a refused merge, one of
    /// `source.deliveries` and `delivery.pickupPlace` can still describe the
    /// mutation the store rejected. So an assertion about a rollback reads the
    /// store fresh rather than the objects that were mutated.
    func reopened() throws -> ModelContext {
        ModelContext(container)
    }

    func storedDeliveries() throws -> [Delivery] {
        try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)
    }

    /// The lifecycle timestamps of every stored delivery, in a form two
    /// snapshots either side of an operation can be compared by.
    func lifecycleSnapshot() throws -> [LifecycleSnapshot] {
        try storedDeliveries().map(LifecycleSnapshot.init)
    }
}

/// Every timestamp on one delivery, which a rename or a merge must leave alone.
private struct LifecycleSnapshot: Equatable {
    let id: UUID
    let acceptedAt: Date
    let arrivedAtPickupAt: Date?
    let pickedUpAt: Date?
    let deliveredAt: Date?
    let cancelledAt: Date?

    init(_ delivery: Delivery) {
        id = delivery.id
        acceptedAt = delivery.acceptedAt
        arrivedAtPickupAt = delivery.arrivedAtPickupAt
        pickedUpAt = delivery.pickedUpAt
        deliveredAt = delivery.deliveredAt
        cancelledAt = delivery.cancelledAt
    }
}

/// A commit that always refuses, so the rollback a merge promises can be
/// asserted rather than described.
private struct RefusedSave: Error {}

// MARK: - Rename

/// Giving a place a new spelling: the policy it reuses, the collision it
/// refuses, and everything it is required to leave untouched.
@MainActor
@Suite("Pickup place rename")
struct PickupPlaceRenameTests {
    @Test("A renamed place shows the new spelling and is found by the new key")
    func renamesAPlace() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(place.displayName == "Nowhere Noodles")
        #expect(place.normalizedName == PickupPlaceName.comparisonKey(of: "Nowhere Noodles"))
        #expect(try fixture.storedPlaces().count == 1, "Renaming corrects a row rather than adding one")

        // The point of writing both forms: the new spelling now finds this place.
        let resolved = try fixture.places.resolvePlace(named: "nowhere noodles", at: fixture.at(60))
        #expect(resolved.id == place.id)
        #expect(try fixture.storedPlaces().count == 1)
    }

    @Test("The old spelling no longer finds the renamed place")
    func theOldKeyStopsMatching() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))

        try fixture.places.rename(place, to: "Nowhere Noodles")
        let resurrected = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(60))

        #expect(resurrected.id != place.id, "A rename moves the key; it leaves no alias behind")
        #expect(try fixture.storedPlaces().count == 2)
    }

    @Test("A rename keeps the place's identity and the date it was named")
    func renameKeepsIdentity() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        let id = place.id
        let createdAt = place.createdAt

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(place.id == id)
        #expect(place.createdAt == createdAt, "Renaming is not re-naming for the first time")
    }

    @Test("The typed name is trimmed and collapsed exactly as a new name is")
    func renameReusesTheNormalisationPolicy() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))

        try fixture.places.rename(place, to: "  Nowhere   Noodles \n ")

        #expect(place.displayName == "Nowhere Noodles")
        #expect(place.normalizedName == PickupPlaceName.comparisonKey(of: "Nowhere Noodles"))
    }

    @Test("A rename that changes only capitalisation is applied as a display change")
    func caseOnlyRename() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "nowhere noodles", at: fixture.at(0))
        let key = place.normalizedName

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(place.displayName == "Nowhere Noodles", "The driver asked for this spelling")
        #expect(place.normalizedName == key, "And the key it is matched by did not need to move")
        #expect(try fixture.storedPlaces().count == 1, "Its own key is not a collision with itself")
    }

    @Test("Renaming to exactly what is stored changes nothing and refuses nothing")
    func renameToTheSameNameIsANoOp() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(place.displayName == "Nowhere Noodles")
        #expect(try fixture.storedPlaces().count == 1)
    }

    @Test("A rename may introduce or keep characters outside ASCII", arguments: [
        "Café Nowhere",
        "Nowhere Nudeln Straße",
        "どこにもない麺",
        "Nowhere Noodles 🍜"
    ])
    func unicodeRename(_ newName: String) throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))

        try fixture.places.rename(place, to: newName)

        #expect(place.displayName == newName)
        #expect(try fixture.places.resolvePlace(named: newName, at: fixture.at(60)).id == place.id)
    }

    @Test("Punctuation a driver types is preserved, exactly as it is when naming a place")
    func punctuationIsPreserved() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "AB Grill", at: fixture.at(0))

        try fixture.places.rename(place, to: "A&B Grill")

        #expect(place.displayName == "A&B Grill")
        // The old, punctuation-free name is a different place, not the same one.
        #expect(try fixture.places.resolvePlace(named: "AB Grill", at: fixture.at(60)).id != place.id)
    }

    @Test("An empty rename is refused and changes nothing", arguments: ["", "   ", "\n\t"])
    func refusesAnEmptyRename(_ rawName: String) throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))

        #expect(throws: PickupPlaceError.invalidName(.empty)) {
            try fixture.places.rename(place, to: rawName)
        }
        #expect(place.displayName == "Nowhere Noodles")
        #expect(try fixture.storedPlaces().count == 1)
    }

    @Test("An oversized rename is refused and changes nothing")
    func refusesAnOversizedRename() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let tooLong = String(repeating: "N", count: PickupPlaceName.maximumLength + 1)

        #expect(throws: PickupPlaceError.invalidName(.tooLong(maximum: PickupPlaceName.maximumLength))) {
            try fixture.places.rename(place, to: tooLong)
        }
        #expect(place.displayName == "Nowhere Noodles")
    }

    @Test("Renaming onto another place's key is refused, and names the place it collided with")
    func refusesACollision() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))

        let expected = PickupPlaceError.placeAlreadyExists(
            existingPlace: PickupPlaceIdentity(id: noodles.id, displayName: "Nowhere Noodles")
        )
        #expect(throws: expected) {
            try fixture.places.rename(diner, to: "  nowhere   NOODLES ")
        }

        #expect(diner.displayName == "Example Diner", "Nothing was written")
        #expect(noodles.displayName == "Nowhere Noodles", "And the other place was not touched either")
        #expect(try fixture.storedPlaces().count == 2, "A refused rename is never a quiet merge")
    }

    @Test("A refused rename leaves both places' deliveries exactly where they were")
    func aRefusedRenameMovesNoDelivery() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 20, at: diner)

        #expect(throws: (any Error).self) {
            try fixture.places.rename(diner, to: "Nowhere Noodles")
        }

        #expect(noodles.deliveries.count == 1)
        #expect(diner.deliveries.count == 1)
    }

    @Test("Every delivery stays attached to the place it was recorded at")
    func deliveriesFollowTheRenamedPlace() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: place)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 11, at: place)
        let before = try fixture.lifecycleSnapshot()

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(place.deliveries.count == 2)
        #expect(try fixture.storedDeliveries().allSatisfy { $0.pickupPlace?.id == place.id })
        #expect(try fixture.lifecycleSnapshot() == before, "A rename records no event and moves no timestamp")
    }

    @Test("A rename changes no recorded wait, no count and no median")
    func renameLeavesTheHistoryAlone() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: place)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 11, at: place)
        try fixture.recordDelivery(arrivingAt: 80, waiting: 41, at: place)
        let before = place.pickupWaitMetrics()

        try fixture.places.rename(place, to: "Nowhere Noodles")
        let after = place.pickupWaitMetrics()

        #expect(after.sampleCount == before.sampleCount)
        #expect(after.medianDuration == before.medianDuration)
        #expect(after.shortestDuration == before.shortestDuration)
        #expect(after.longestDuration == before.longestDuration)
        #expect(after.mostRecentSampleAt == before.mostRecentSampleAt)
    }

    @Test("Recent-place ordering is unchanged by a rename")
    func renameLeavesRecencyAlone() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 60, waiting: 20, at: diner)

        try fixture.places.rename(noodles, to: "Nowhere Noodles")

        #expect(try fixture.places.recentPlaces().map(\.id) == [diner.id, noodles.id])
    }

    @Test("A place attached to a delivery still running can be renamed")
    func renamesAPlaceOnAnActiveDelivery() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        let active = try fixture.recordActiveDelivery(acceptedAt: 10, at: place)

        try fixture.places.rename(place, to: "Nowhere Noodles")

        #expect(active.isActive, "Renaming a place is not a lifecycle event")
        #expect(active.pickupPlace?.displayName == "Nowhere Noodles")
        #expect(active.deliveredAt == nil && active.cancelledAt == nil)
    }

    @Test("Renaming a place the store no longer holds is refused")
    func refusesToRenameADeletedPlace() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        fixture.context.delete(place)
        try fixture.context.save()

        #expect(throws: PickupPlaceError.placeNoLongerExists) {
            try fixture.places.rename(place, to: "Nowhere Noodle")
        }
    }

    @Test("A rename the store refuses is rolled back, leaving the old spelling")
    func aRefusedSaveKeepsTheOldName() throws {
        let fixture = try CorrectionFixture(commit: { _ in throw RefusedSave() })
        // The place has to exist before the failing commit is in play, so it is
        // created through a service that can save.
        let writing = PickupPlaceService(context: fixture.context)
        let place = try writing.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))

        #expect(throws: PickupPlaceError.storeUnavailable(underlying: RefusedSave())) {
            try fixture.places.rename(place, to: "Nowhere Noodles")
        }

        #expect(!fixture.context.hasChanges, "The rollback left nothing pending")

        let stored = try fixture.reopened().fetch(FetchDescriptor<PickupPlace>())
        #expect(stored.count == 1)
        #expect(stored.first?.displayName == "Nowhere Noodle", "The store still holds the old spelling")
        #expect(stored.first?.normalizedName == PickupPlaceName.comparisonKey(of: "Nowhere Noodle"))
    }
}

// MARK: - Merge

/// Putting one place's deliveries under another, and removing the one left
/// empty.
@MainActor
@Suite("Pickup place merge")
struct PickupPlaceMergeTests {
    @Test("Every delivery moves to the destination and the source is removed")
    func mergesOnePlaceIntoAnother() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let noodle = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(1))
        let moving = try [
            fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodle),
            fixture.recordDelivery(arrivingAt: 40, waiting: 11, at: noodle)
        ]
        let staying = try fixture.recordDelivery(arrivingAt: 80, waiting: 41, at: noodles)

        try fixture.places.merge(noodle, into: noodles)

        #expect(try fixture.storedPlaces().map(\.id) == [noodles.id], "Only the destination is left")
        #expect(moving.allSatisfy { $0.pickupPlace?.id == noodles.id })
        #expect(staying.pickupPlace?.id == noodles.id, "The destination's own delivery did not move")
        #expect(noodles.deliveries.count == 3)
    }

    @Test("The destination keeps its identity, its spelling and the date it was named")
    func theDestinationIsUnchanged() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(30))
        let id = noodles.id
        let key = noodles.normalizedName
        let createdAt = noodles.createdAt
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: diner)

        try fixture.places.merge(diner, into: noodles)

        #expect(noodles.id == id)
        #expect(noodles.displayName == "Nowhere Noodles", "Names are never combined")
        #expect(noodles.normalizedName == key)
        #expect(noodles.createdAt == createdAt, "The destination was not re-created")
    }

    @Test("No delivery record is deleted, and no lifecycle timestamp moves")
    func deliveriesSurviveIntact() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: diner)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 20, at: noodles)
        try fixture.recordDelivery(arrivingAt: 80, waiting: nil, at: diner)
        let before = try fixture.lifecycleSnapshot()

        try fixture.places.merge(diner, into: noodles)

        #expect(try fixture.storedDeliveries().count == 3)
        #expect(try fixture.lifecycleSnapshot() == before)
    }

    @Test("A source no delivery references merges, and simply disappears")
    func mergesAnEmptySource() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let stray = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)

        try fixture.places.merge(stray, into: noodles)

        #expect(try fixture.storedPlaces().map(\.id) == [noodles.id])
        #expect(noodles.deliveries.count == 1, "The destination gained nothing, and lost nothing")
    }

    @Test("A source whose deliveries include cancelled ones merges them all")
    func mergesCancelledDeliveries() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        let delivered = try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: diner)
        let cancelled = try fixture.recordDelivery(arrivingAt: 40, waiting: nil, at: diner)

        try fixture.places.merge(diner, into: noodles)

        #expect(delivered.state == .delivered)
        #expect(cancelled.state == .cancelled, "A cancellation is history, and a merge does not rewrite it")
        #expect(noodles.deliveries.count == 2)
    }

    @Test("A place attached to a delivery still running can be merged away")
    func mergesAPlaceOnAnActiveDelivery() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let noodle = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(1))
        let active = try fixture.recordActiveDelivery(acceptedAt: 10, at: noodle)

        try fixture.places.merge(noodle, into: noodles)

        #expect(active.isActive, "Correcting a place is not a lifecycle event")
        #expect(active.pickupPlace?.id == noodles.id)
        #expect(active.arrivedAtPickupAt == nil && active.deliveredAt == nil)
        #expect(try fixture.deliveries.activeDeliveries().map(\.id) == [active.id])
    }

    @Test("Merging a place into itself is refused")
    func refusesASelfMerge() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: place)

        #expect(throws: PickupPlaceError.cannotMergeIntoItself) {
            try fixture.places.merge(place, into: place)
        }

        #expect(try fixture.storedPlaces().map(\.id) == [place.id], "And it certainly did not delete itself")
        #expect(place.deliveries.count == 1)
    }

    @Test("Merging a place the store no longer holds is refused, either side")
    func refusesAStaleModel() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        fixture.context.delete(diner)
        try fixture.context.save()

        #expect(throws: PickupPlaceError.placeNoLongerExists) {
            try fixture.places.merge(diner, into: noodles)
        }
        #expect(throws: PickupPlaceError.placeNoLongerExists) {
            try fixture.places.merge(noodles, into: diner)
        }

        #expect(noodles.deliveries.count == 1, "Neither refusal moved anything")
        #expect(try fixture.storedPlaces().map(\.id) == [noodles.id])
    }

    @Test("A merge the store refuses leaves both places and every delivery where they were")
    func aRefusedSaveRollsTheWholeMergeBack() throws {
        let fixture = try CorrectionFixture(commit: { _ in throw RefusedSave() })
        // Both places and their deliveries are written through a service that
        // can save; only the merge meets the refusing commit.
        let writing = PickupPlaceService(context: fixture.context)
        let noodles = try writing.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try writing.resolvePlace(named: "Example Diner", at: fixture.at(1))
        let delivery = try fixture.deliveries.startDelivery(at: fixture.at(5))
        try fixture.deliveries.markArrivedAtPickup(delivery, at: fixture.at(10))
        try fixture.deliveries.markPickedUp(delivery, at: fixture.at(16))
        try writing.assign(diner, to: delivery)

        #expect(throws: PickupPlaceError.storeUnavailable(underlying: RefusedSave())) {
            try fixture.places.merge(diner, into: noodles)
        }

        #expect(!fixture.context.hasChanges, "The rollback left nothing pending")

        // Read fresh, because a rollback restores the store rather than the
        // relationship arrays cached on the objects that were mutated.
        let reopened = try fixture.reopened()
        let places = try reopened.fetch(FetchDescriptor<PickupPlace>())
        #expect(places.count == 2, "The source was not deleted")
        #expect(places.contains { $0.id == diner.id })
        #expect(places.contains { $0.id == noodles.id })

        let stored = try reopened.fetch(FetchDescriptor<Delivery>())
        #expect(stored.count == 1)
        #expect(stored.first?.id == delivery.id)
        #expect(stored.first?.pickupPlace?.id == diner.id, "And the delivery did not move to the destination")

        let storedNoodles = try #require(places.first { $0.id == noodles.id })
        let storedDiner = try #require(places.first { $0.id == diner.id })
        #expect(storedNoodles.deliveries.isEmpty)
        #expect(storedDiner.deliveries.count == 1)
        #expect(storedDiner.pickupWaitMetrics().sampleCount == 1, "Its history is where it was")
    }

    // MARK: Destinations offered

    @Test("Every other place is offered as a destination, alphabetically")
    func destinationsAreAlphabetical() throws {
        let fixture = try CorrectionFixture()
        // Created deliberately out of alphabetical order.
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        let grill = try fixture.places.resolvePlace(named: "a&b grill", at: fixture.at(2))
        let subject = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(3))

        let destinations = try fixture.places.mergeDestinations(for: subject)

        #expect(destinations.map(\.id) == [grill.id, diner.id, noodles.id])
        #expect(!destinations.contains { $0.id == subject.id }, "A place is never its own destination")
    }

    @Test("The only place in the catalogue has nothing to merge into")
    func aSolePlaceHasNoDestinations() throws {
        let fixture = try CorrectionFixture()
        let place = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))

        #expect(try fixture.places.mergeDestinations(for: place).isEmpty)
    }

    @Test("A place nothing references is still offered, because it still exists")
    func unreferencedPlacesAreStillDestinations() throws {
        let fixture = try CorrectionFixture()
        let subject = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(0))
        let unused = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))

        #expect(try fixture.places.mergeDestinations(for: subject).map(\.id) == [unused.id])
    }
}

// MARK: - Metrics and recency after a merge

/// What a merged place's history says, and that it says it because the figures
/// are derived rather than stored.
@MainActor
@Suite("Pickup wait history after a merge")
struct PickupWaitAfterMergeTests {
    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    @Test("Two separate histories become one, and the median recomputes")
    func historiesCombine() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 11, at: noodles)
        try fixture.recordDelivery(arrivingAt: 80, waiting: 41, at: noodles)
        try fixture.recordDelivery(arrivingAt: 140, waiting: 20, at: diner)

        // Before: two histories, neither of which is the other's.
        #expect(noodles.pickupWaitMetrics().sampleCount == 3)
        #expect(noodles.pickupWaitMetrics().medianDuration == minutes(11))
        #expect(diner.pickupWaitMetrics().sampleCount == 1)
        #expect(diner.pickupWaitMetrics().medianDuration == minutes(20))

        try fixture.places.merge(diner, into: noodles)

        // After: 6, 11, 20 and 41, whose median is the midpoint of 11 and 20.
        let combined = noodles.pickupWaitMetrics()
        #expect(combined.sampleCount == 4)
        #expect(combined.medianDuration == minutes(15.5))
        #expect(combined.shortestDuration == minutes(6))
        #expect(combined.longestDuration == minutes(41))
        #expect(combined.availability == .available)
    }

    @Test("The source's history cannot be read once the source is gone")
    func theSourceIsNoLongerQueryable() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 20, at: diner)
        let dinerID = diner.id

        try fixture.places.merge(diner, into: noodles)

        #expect(try !fixture.storedPlaces().contains { $0.id == dinerID })
        let byKey = FetchDescriptor<PickupPlace>(
            predicate: #Predicate { $0.normalizedName == "example diner" }
        )
        #expect(try fixture.context.fetch(byKey).isEmpty)
    }

    @Test("Two places' waits together produce no duplicate sample")
    func noSampleIsCountedTwice() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 12, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 12, at: diner)

        try fixture.places.merge(diner, into: noodles)

        let samples = noodles.pickupWaitSamples
        #expect(samples.count == 2, "Two identical waits are two observations, and never four")
        #expect(samples.allSatisfy { $0.duration == minutes(12) })
        #expect(Set(samples.map(\.pickedUpAt)).count == 2)
    }

    @Test("Deliveries that recorded no pickup are excluded after a merge exactly as before")
    func exclusionsSurviveTheMerge() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 20, at: diner)
        // Arrived, then cancelled without ever picking up: no wait, either side.
        try fixture.recordDelivery(arrivingAt: 80, waiting: nil, at: diner)
        try fixture.recordActiveDelivery(acceptedAt: 140, at: diner)

        try fixture.places.merge(diner, into: noodles)

        #expect(noodles.deliveries.count == 4, "Every delivery moved")
        #expect(noodles.pickupWaitMetrics().sampleCount == 2, "But only two of them recorded a wait")
        #expect(noodles.pickupWaitMetrics().medianDuration == minutes(13))
    }

    @Test("A merge writes no aggregate onto the destination")
    func nothingIsPersistedOntoTheDestination() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 20, at: diner)

        try fixture.places.merge(diner, into: noodles)

        // The store's shape is the assertion: a merge that had to record a
        // combined figure would need somewhere to put it.
        let entity = try #require(
            ModelContainerFactory.currentSchema.entities.first { $0.name == "PickupPlace" }
        )
        #expect(Set(entity.properties.map(\.name)) == ["id", "displayName", "normalizedName", "createdAt", "deliveries"])

        // And reading the history leaves nothing pending to be written.
        _ = noodles.pickupWaitMetrics()
        #expect(!fixture.context.hasChanges)
    }
}

/// Recency is derived from deliveries, so a merge moves it without being told
/// to.
@MainActor
@Suite("Recent places after a merge")
struct RecentPlacesAfterMergeTests {
    @Test("The destination inherits the most recent use among the deliveries it gained")
    func recencyFollowsTheDeliveries() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let diner = try fixture.places.resolvePlace(named: "Example Diner", at: fixture.at(1))
        let grill = try fixture.places.resolvePlace(named: "A&B Grill", at: fixture.at(2))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 60, waiting: 6, at: grill)
        // The most recent delivery of the three belongs to the source.
        try fixture.recordDelivery(arrivingAt: 120, waiting: 20, at: diner)

        #expect(try fixture.places.recentPlaces().map(\.id) == [diner.id, grill.id, noodles.id])

        try fixture.places.merge(diner, into: noodles)

        #expect(
            try fixture.places.recentPlaces().map(\.id) == [noodles.id, grill.id],
            "The destination is now the most recently used, through the delivery it gained"
        )
        #expect(noodles.lastUsedAt == fixture.at(115), "Which is the acceptance of that delivery")
    }

    @Test("A merged-away place disappears from the recent list")
    func theSourceDisappears() throws {
        let fixture = try CorrectionFixture()
        let noodles = try fixture.places.resolvePlace(named: "Nowhere Noodles", at: fixture.at(0))
        let noodle = try fixture.places.resolvePlace(named: "Nowhere Noodle", at: fixture.at(1))
        try fixture.recordDelivery(arrivingAt: 10, waiting: 6, at: noodles)
        try fixture.recordDelivery(arrivingAt: 40, waiting: 11, at: noodle)

        try fixture.places.merge(noodle, into: noodles)

        #expect(try fixture.places.recentPlaces().map(\.id) == [noodles.id])
        #expect(try fixture.places.allPlaces().map(\.id) == [noodles.id])
    }
}
