import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedPickupSave: Error {}

/// How a delivery's pickup was recorded: written with the event, by the one
/// control that wrote it, and never moved by anything that keeps the event.
///
/// The invariant every test here holds is the same: **a provenance exists
/// exactly when a pickup the app recorded exists.** Nothing clears a pickup, so
/// nothing clears its provenance; a correction moves the instant and leaves the
/// provenance where it was.
///
/// Rollback is read through a **fresh context**, because an already-held model
/// and the store can disagree after one.
@MainActor
@Suite("Pickup provenance")
struct PickupProvenanceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private struct Store {
        let container: ModelContainer
        let context: ModelContext
        let shifts: ShiftService
        let deliveries: DeliveryService
    }

    private func makeStore() throws -> Store {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = Store(
            container: container,
            context: context,
            shifts: ShiftService(context: context),
            deliveries: DeliveryService(context: context)
        )
        try store.shifts.startShift(at: start)
        return store
    }

    /// A delivery accepted at minute 10 and arrived at minute 15.
    private func deliveryAtPickup(in store: Store) throws -> Delivery {
        let delivery = try store.deliveries.startDelivery(at: at(10))
        try store.deliveries.markArrivedAtPickup(delivery, at: at(15))
        return delivery
    }

    /// The same delivery recorded picked up by Park at minute 16.
    private func parkedPickup(in store: Store) throws -> Delivery {
        let delivery = try deliveryAtPickup(in: store)
        try SettingsService(context: store.context).setRecordsPickupWhenParking(true)
        let result = try ParkVehicleService(context: store.context).park(at: at(16))
        #expect(result.pickup.recordedPickup)
        try store.shifts.resumeDrivingOnActiveShift(at: at(20))
        return delivery
    }

    // MARK: The model

    @Test("A delivery with no pickup has no provenance")
    func noPickupNoProvenance() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.pickupProvenance == nil)
    }

    @Test("A refused pickup writes no provenance")
    func refusedPickupWritesNone() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(10))

        #expect(throws: DeliveryError.outOfOrder(missing: .arrivedAtPickup)) {
            try delivery.markPickedUp(at: at(12), recordedBy: .parkAutomation)
        }
        #expect(delivery.pickupProvenance == nil)
    }

    @Test("A pickup already recorded keeps its provenance when a second one is refused")
    func secondPickupDoesNotOverwrite() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        try store.deliveries.markPickedUp(delivery, at: at(20))

        #expect(throws: DeliveryError.alreadyRecorded(.pickedUp)) {
            try delivery.markPickedUp(at: at(21), recordedBy: .parkAutomation)
        }
        #expect(delivery.pickupProvenance == .manual)
    }

    // MARK: Each writer

    @Test("The card's Picked Up step records a manual pickup")
    func manualPickup() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        try store.deliveries.markPickedUp(delivery, at: at(22), recordedBy: .manual)

        #expect(delivery.pickupProvenance == .manual)
        #expect(delivery.pickupWait == 420)
    }

    @Test("Park in the app records the pickup as Park's, at the instant of parking")
    func parkPickup() throws {
        let store = try makeStore()
        let delivery = try parkedPickup(in: store)

        #expect(delivery.pickedUpAt == at(16))
        #expect(delivery.pickupProvenance == .parkAutomation)
    }

    @Test("With the setting off, Park records no pickup and so no provenance")
    func parkWithTheSettingOff() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        try ParkVehicleService(context: store.context).park(at: at(16))

        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.pickupProvenance == nil)
    }

    @Test("A pickup Park could not save leaves neither the instant nor the provenance in the store")
    func refusedParkPickupSave() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        let id = delivery.id
        try SettingsService(context: store.context).setRecordsPickupWhenParking(true)

        let result = try ParkVehicleService(
            context: store.context,
            deliveryCommit: { _ in throw RefusedPickupSave() }
        ).park(at: at(16))
        #expect(result.pickup == .notRecorded(deliveryNumber: 1))

        let fresh = ModelContext(store.container)
        let stored = try #require(
            try fresh.fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id })).first
        )
        #expect(stored.pickedUpAt == nil)
        #expect(stored.pickupProvenance == nil)
    }

    // MARK: What keeps the event keeps the provenance

    @Test("Delivering, cancelling after pickup and reopening keep the provenance")
    func lifecycleKeepsIt() throws {
        let store = try makeStore()
        let delivered = try parkedPickup(in: store)
        try store.deliveries.markDelivered(delivered, at: at(30))
        #expect(delivered.pickupProvenance == .parkAutomation)

        try store.deliveries.reopenDelivered(delivered)
        #expect(delivered.state == .pickedUp)
        #expect(delivered.pickupProvenance == .parkAutomation, "Reopening keeps the pickup, so it keeps how")

        try store.deliveries.cancelDelivery(delivered, at: at(35))
        #expect(delivered.state == .cancelled)
        #expect(delivered.pickupProvenance == .parkAutomation)
    }

    @Test("Correcting a completion to a cancellation keeps the provenance")
    func historicalCancellationKeepsIt() throws {
        let store = try makeStore()
        let delivery = try parkedPickup(in: store)
        try store.deliveries.markDelivered(delivery, at: at(30))
        try store.shifts.endActiveShift(at: at(60))

        try store.deliveries.correctCompletionToCancellation(delivery)
        #expect(delivery.state == .cancelled)
        #expect(delivery.pickupProvenance == .parkAutomation)
    }

    @Test("Correcting the pickup's time moves the instant and leaves the provenance")
    func timeCorrectionKeepsIt() throws {
        let store = try makeStore()
        let delivery = try parkedPickup(in: store)
        try store.deliveries.markDelivered(delivery, at: at(30))
        try store.shifts.endActiveShift(at: at(60))

        let proposed = DeliveryLifecycleRecord(delivery).replacing(.pickedUp, with: at(24))
        try store.deliveries.correctRecordedTimes(delivery, to: proposed)

        #expect(delivery.pickedUpAt == at(24))
        #expect(delivery.pickupWait == 540, "The wait follows the corrected instant at once")
        #expect(delivery.pickupProvenance == .parkAutomation, "A correction is not a second recording")
    }

    @Test("A manual pickup stays manual through a correction")
    func manualSurvivesCorrection() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        try store.deliveries.markPickedUp(delivery, at: at(22))
        try store.deliveries.markDelivered(delivery, at: at(30))
        try store.shifts.endActiveShift(at: at(60))

        let proposed = DeliveryLifecycleRecord(delivery).replacing(.pickedUp, with: at(18))
        try store.deliveries.correctRecordedTimes(delivery, to: proposed)
        #expect(delivery.pickupProvenance == .manual)
    }

    // MARK: Recovering from a pickup Park recorded too early

    /// The recovery path an accidental or early Park pickup already has, with
    /// nothing new built for it: the delivery keeps every next step, its wait
    /// stays out of every typical figure, and once the shift ends the instant
    /// can be moved to the real handover by the existing correction.
    @Test("A pickup Park recorded too early leaves the driver every next step, and the time correctable afterwards")
    func earlyParkPickupIsRecoverable() throws {
        let store = try makeStore()
        let delivery = try parkedPickup(in: store)

        #expect(delivery.state.nextAction == .complete, "Delivered is still the next step on the card")
        #expect(PickupWaitSample(delivery)?.countsTowardTypicalWait == false, "Its wait is already left out")

        try store.deliveries.markDelivered(delivery, at: at(40))
        try store.shifts.endActiveShift(at: at(60))
        let proposed = DeliveryLifecycleRecord(delivery).replacing(.pickedUp, with: at(27))
        #expect(store.deliveries.timeCorrectionRefusal(on: delivery, to: proposed) == nil)
        try store.deliveries.correctRecordedTimes(delivery, to: proposed)
        #expect(delivery.pickupWait == 720, "The handover the driver remembers, recorded honestly")
        #expect(delivery.recordedEvents.count == 4, "No event created, none removed")
    }

    @Test("A pickup Park recorded for an order that never came can still end as a cancellation")
    func earlyParkPickupThenCancelled() throws {
        let store = try makeStore()
        let delivery = try parkedPickup(in: store)

        try store.deliveries.cancelDelivery(delivery, at: at(25))
        #expect(delivery.state == .cancelled)
        #expect(delivery.pickupProvenance == .parkAutomation, "Who recorded the pickup is still on the record")
        #expect(PickupWaitSample(delivery)?.countsTowardTypicalWait == false)
    }

    // MARK: Logging

    @Test("The log line names the kind of recording and nothing else")
    func logDescriptionIsStructural() {
        #expect(PickupProvenance.manual.logDescription == "pickup recorded manually")
        #expect(PickupProvenance.parkAutomation.logDescription == "pickup recorded by configured park automation")
    }

    @Test("A stored value this build does not know reads as unknown")
    func unknownRawValue() {
        #expect(PickupProvenance.stored("manual") == .manual)
        #expect(PickupProvenance.stored("parkAutomation") == .parkAutomation)
        #expect(PickupProvenance.stored("geofence") == nil)
        #expect(PickupProvenance.stored(nil) == nil)
    }
}
