import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedPickupSave: Error {}

/// How a delivery's pickup was recorded: written with the event, by the one
/// control that wrote it, and never moved by anything that keeps the event.
///
/// The invariant every test here holds is the same: **a provenance exists
/// exactly when a pickup the app recorded exists.** The one thing that clears a
/// pickup, taking back one Resume Driving just recorded, clears its provenance
/// in the same statement (`AutomatedPickupStepUndoTests`); a correction moves
/// the instant and leaves the provenance where it was.
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

    /// The same delivery, parked for at minute 15 under the pickup workflow
    /// and recorded picked up by Resume Driving at minute 16.
    private func resumedPickup(in store: Store) throws -> Delivery {
        let delivery = try deliveryAtPickup(in: store)
        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(true)
        let parked = try ParkVehicleService(context: store.context).park(at: at(15))
        #expect(parked.pickup == .alreadyArrived(deliveryNumber: 1))
        let resumed = try ParkVehicleService(context: store.context).resumeDriving(at: at(16))
        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: 1))
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

    @Test("Resume Driving in the app records the pickup as Resume's, at the instant of driving")
    func resumePickup() throws {
        let store = try makeStore()
        let delivery = try resumedPickup(in: store)

        #expect(delivery.pickedUpAt == at(16))
        #expect(delivery.pickupProvenance == .resumeAutomation)
    }

    @Test("With the workflow off, Park and Resume record no pickup and so no provenance")
    func parkWithTheSettingOff() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        try ParkVehicleService(context: store.context).park(at: at(16))
        try ParkVehicleService(context: store.context).resumeDriving(at: at(20))

        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.pickupProvenance == nil)
    }

    @Test("Nothing records a pickup as Park's any more: Park records the arrival")
    func parkRecordsNoPickup() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(10))
        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(true)
        try ParkVehicleService(context: store.context).park(at: at(15))

        #expect(delivery.state == .arrivedAtPickup)
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.pickupProvenance == nil)
    }

    @Test("A pickup Resume could not save leaves neither the instant nor the provenance in the store")
    func refusedResumePickupSave() throws {
        let store = try makeStore()
        let delivery = try deliveryAtPickup(in: store)
        let id = delivery.id
        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(true)
        try ParkVehicleService(context: store.context).park(at: at(15))

        let result = try ParkVehicleService(
            context: store.context,
            deliveryCommit: { _ in throw RefusedPickupSave() }
        ).resumeDriving(at: at(16))
        #expect(result.pickup == .pickupNotRecorded(deliveryNumber: 1))

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
        let delivered = try resumedPickup(in: store)
        try store.deliveries.markDelivered(delivered, at: at(30))
        #expect(delivered.pickupProvenance == .resumeAutomation)

        try store.deliveries.reopenDelivered(delivered)
        #expect(delivered.state == .pickedUp)
        #expect(delivered.pickupProvenance == .resumeAutomation, "Reopening keeps the pickup, so it keeps how")

        try store.deliveries.cancelDelivery(delivered, at: at(35))
        #expect(delivered.state == .cancelled)
        #expect(delivered.pickupProvenance == .resumeAutomation)
    }

    @Test("Correcting a completion to a cancellation keeps the provenance")
    func historicalCancellationKeepsIt() throws {
        let store = try makeStore()
        let delivery = try resumedPickup(in: store)
        try store.deliveries.markDelivered(delivery, at: at(30))
        try store.shifts.endActiveShift(at: at(60))

        try store.deliveries.correctCompletionToCancellation(delivery)
        #expect(delivery.state == .cancelled)
        #expect(delivery.pickupProvenance == .resumeAutomation)
    }

    @Test("Correcting the pickup's time moves the instant and leaves the provenance")
    func timeCorrectionKeepsIt() throws {
        let store = try makeStore()
        let delivery = try resumedPickup(in: store)
        try store.deliveries.markDelivered(delivery, at: at(30))
        try store.shifts.endActiveShift(at: at(60))

        let proposed = DeliveryLifecycleRecord(delivery).replacing(.pickedUp, with: at(24))
        try store.deliveries.correctRecordedTimes(delivery, to: proposed)

        #expect(delivery.pickedUpAt == at(24))
        #expect(delivery.pickupWait == 540, "The wait follows the corrected instant at once")
        #expect(delivery.pickupProvenance == .resumeAutomation, "A correction is not a second recording")
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

    // MARK: Recovering from an automated pickup once Undo has gone

    /// The recovery path an automated pickup has once its short Undo has gone,
    /// with nothing new built for it: the delivery keeps every next step, its
    /// wait stays out of every typical figure, and once the shift ends the
    /// instant can be moved to the real handover by the existing correction.
    @Test("A pickup Resume recorded leaves the driver every next step, and the time correctable afterwards")
    func automatedPickupIsRecoverable() throws {
        let store = try makeStore()
        let delivery = try resumedPickup(in: store)

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

    @Test("A pickup Resume recorded for an order that never came can still end as a cancellation")
    func automatedPickupThenCancelled() throws {
        let store = try makeStore()
        let delivery = try resumedPickup(in: store)

        try store.deliveries.cancelDelivery(delivery, at: at(25))
        #expect(delivery.state == .cancelled)
        #expect(delivery.pickupProvenance == .resumeAutomation, "Who recorded the pickup is still on the record")
        #expect(PickupWaitSample(delivery)?.countsTowardTypicalWait == false)
    }

    // MARK: Logging

    @Test("The log line names the kind of recording and nothing else")
    func logDescriptionIsStructural() {
        #expect(PickupProvenance.manual.logDescription == "pickup recorded manually")
        #expect(PickupProvenance.parkAutomation.logDescription == "pickup recorded by configured park automation")
        #expect(PickupProvenance.resumeAutomation.logDescription == "pickup recorded by configured resume automation")
    }

    @Test("A stored value this build does not know reads as unknown")
    func unknownRawValue() {
        #expect(PickupProvenance.stored("manual") == .manual)
        #expect(PickupProvenance.stored("parkAutomation") == .parkAutomation)
        #expect(PickupProvenance.stored("resumeAutomation") == .resumeAutomation)
        #expect(PickupProvenance.stored("geofence") == nil)
        #expect(PickupProvenance.stored(nil) == nil)
    }
}
