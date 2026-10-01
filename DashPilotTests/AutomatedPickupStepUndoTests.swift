import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Taking back the one delivery event the Park and Resume workflow just
/// recorded, and never the vehicle state beside it.
///
/// The invariant every test here holds: **Undo reverses the automated delivery
/// event and nothing else.** A parked vehicle stays parked, a driving one stays
/// driving, no other delivery moves, and a delivery that has moved on since is
/// refused rather than rewound.
@MainActor
@Suite("Automated pickup step undo")
struct AutomatedPickupStepUndoTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @MainActor
    private struct Store {
        let context: ModelContext
        let shifts: ShiftService
        let deliveries: DeliveryService

        var parking: ParkVehicleService { ParkVehicleService(context: context) }

        func fresh() -> ModelContext { ModelContext(context.container) }
    }

    private func makeStore(stacked: Bool = false) throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let store = Store(context: context, shifts: ShiftService(context: context), deliveries: DeliveryService(context: context))
        try store.shifts.startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(true)
        try settings.setHandlesStackedOrdersInOrder(stacked)
        return store
    }

    private func openSuspensions(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<RouteSuspension>()).count { $0.isOpen }
    }

    // MARK: The two undos

    @Test("Undo after Park: the delivery goes back to Accepted and the vehicle stays parked")
    func undoArrivalKeepsParked() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let parked = try store.parking.park(at: at(10))
        let step = try #require(parked.automatedSteps.first)

        let restored = try store.deliveries.undoAutomatedStep(step)

        #expect(restored == .accepted)
        #expect(delivery.state == .accepted)
        #expect(delivery.arrivedAtPickupAt == nil)
        #expect(delivery.acceptedAt == at(1), "Nothing before it moves")
        let shift = try #require(try store.fresh().fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.isRouteSuspended, "The vehicle is still parked")
        #expect(shift.openRouteSuspension?.startedAt == at(10), "The same stretch, untouched")
        #expect(try openSuspensions(in: store.fresh()) == 1)
        let stored = try #require(try DeliveryService(context: store.fresh()).delivery(withID: delivery.id))
        #expect(stored.arrivedAtPickupAt == nil, "Saved, not only held")
    }

    @Test("Undo after Resume: the delivery goes back to Arrived at Pickup and the vehicle stays driving")
    func undoPickupKeepsDriving() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        _ = try store.parking.park(at: at(10))
        let resumed = try store.parking.resumeDriving(at: at(16))
        let step = try #require(resumed.automatedSteps.first)

        let restored = try store.deliveries.undoAutomatedStep(step)

        #expect(restored == .arrivedAtPickup)
        #expect(delivery.state == .arrivedAtPickup)
        #expect(delivery.pickedUpAt == nil)
        #expect(delivery.pickupProvenance == nil, "The provenance goes with the pickup it described")
        #expect(delivery.arrivedAtPickupAt == at(10), "Park's arrival stays: only the latest step comes back")
        let fresh = store.fresh()
        let shift = try #require(try fresh.fetch(FetchDescriptor<Shift>()).first)
        #expect(!shift.isRouteSuspended, "The vehicle is still driving")
        #expect(try openSuspensions(in: fresh) == 0, "No stretch is reopened")
        #expect(shift.routeSuspensions.first?.endedAt == at(16))
    }

    @Test("After undoing the pickup the delivery takes its next step as usual, recorded as the driver's")
    func afterUndoTheCardStillWorks() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        _ = try store.parking.park(at: at(10))
        let step = try #require(try store.parking.resumeDriving(at: at(16)).automatedSteps.first)
        try store.deliveries.undoAutomatedStep(step)

        try store.deliveries.markPickedUp(delivery, at: at(18), recordedBy: .manual)
        #expect(delivery.pickedUpAt == at(18))
        #expect(delivery.pickupProvenance == .manual)
    }

    @Test("Undo moves no other delivery")
    func otherDeliveriesUntouched() throws {
        let store = try makeStore(stacked: true)
        let third = try store.deliveries.startDelivery(at: at(1))
        let fourth = try store.deliveries.startDelivery(at: at(2))
        try store.deliveries.markArrivedAtPickup(fourth, at: at(3))
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)
        #expect(step.deliveryID == third.id)

        try store.deliveries.undoAutomatedStep(step)

        #expect(third.state == .accepted)
        #expect(fourth.arrivedAtPickupAt == at(3), "The manually recorded arrival on the other order stays")
    }

    // MARK: Refusals

    @Test("An arrival with a pickup recorded after it cannot be undone, and nothing cascades")
    func refusesAfterALaterEvent() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)
        try store.deliveries.markPickedUp(delivery, at: at(13), recordedBy: .manual)

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.laterEventRecorded)) {
            try store.deliveries.undoAutomatedStep(step)
        }
        #expect(delivery.arrivedAtPickupAt == at(10))
        #expect(delivery.pickedUpAt == at(13), "The driver's own pickup is never removed")
    }

    @Test("A pickup with a delivery or cancellation after it cannot be undone")
    func refusesAfterTerminal() throws {
        for finish in ["delivered", "cancelled"] {
            let store = try makeStore()
            let delivery = try store.deliveries.startDelivery(at: at(1))
            _ = try store.parking.park(at: at(10))
            let step = try #require(try store.parking.resumeDriving(at: at(16)).automatedSteps.first)
            if finish == "delivered" {
                try store.deliveries.markDelivered(delivery, at: at(30))
            } else {
                try store.deliveries.cancelDelivery(delivery, at: at(30))
            }

            #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.laterEventRecorded)) {
                try store.deliveries.undoAutomatedStep(step)
            }
            #expect(delivery.pickedUpAt == at(16), "\(finish): nothing moved")
            #expect(delivery.pickupProvenance == .resumeAutomation)
        }
    }

    @Test("Undoing twice is refused the second time, and writes nothing")
    func refusesTwice() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)
        try store.deliveries.undoAutomatedStep(step)

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.stepNoLongerRecorded)) {
            try store.deliveries.undoAutomatedStep(step)
        }
        #expect(delivery.state == .accepted)
    }

    @Test("An arrival recorded again by hand at a different instant is not the step, and is kept")
    func refusesARerecordedEvent() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)
        try store.deliveries.undoAutomatedStep(step)
        try store.deliveries.markArrivedAtPickup(delivery, at: at(11))

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.stepNoLongerRecorded)) {
            try store.deliveries.undoAutomatedStep(step)
        }
        #expect(delivery.arrivedAtPickupAt == at(11))
    }

    @Test("A pickup at the recorded instant that the workflow did not record is refused")
    func refusesAManualPickup() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try store.deliveries.markArrivedAtPickup(delivery, at: at(2))
        try store.deliveries.markPickedUp(delivery, at: at(9), recordedBy: .manual)
        let forged = AutomatedPickupStep(kind: .pickedUpWhenResumed, deliveryID: delivery.id, deliveryNumber: 1, recordedAt: at(9))

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.notRecordedAutomatically)) {
            try store.deliveries.undoAutomatedStep(forged)
        }
        #expect(delivery.pickedUpAt == at(9))
        #expect(delivery.pickupProvenance == .manual)
    }

    @Test("A step naming a delivery the store no longer holds is refused")
    func refusesAMissingDelivery() throws {
        let store = try makeStore()
        let step = AutomatedPickupStep(kind: .arrivedWhenParked, deliveryID: UUID(), deliveryNumber: 1, recordedAt: at(10))

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.stepNoLongerRecorded)) {
            try store.deliveries.undoAutomatedStep(step)
        }
    }

    @Test("The model refuses a step that names a different delivery")
    func modelRefusesADifferentDelivery() throws {
        let record = DeliveryLifecycleRecord(acceptedAt: at(1), arrivedAtPickupAt: at(10))
        let step = AutomatedPickupStep(kind: .arrivedWhenParked, deliveryID: UUID(), deliveryNumber: 1, recordedAt: at(10))

        #expect(throws: AutomatedStepUndoRefusal.differentDelivery) {
            try AutomatedPickupStepUndo(undoing: step, deliveryID: UUID(), record: record, pickupProvenance: nil)
        }
    }

    @Test("An undo whose save fails leaves the store holding the event")
    func refusedSave() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let id = delivery.id
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)

        struct Refused: Error {}
        #expect(throws: DeliveryLifecycleError.self) {
            try DeliveryService(context: store.context, commit: { _ in throw Refused() }).undoAutomatedStep(step)
        }
        #expect(!store.context.hasChanges)
        let stored = try #require(try DeliveryService(context: store.fresh()).delivery(withID: id))
        #expect(stored.arrivedAtPickupAt == at(10))
        #expect(stored.state == .arrivedAtPickup)
    }

    // MARK: Lifetime

    /// The offer to undo is held by the screen that showed it and is gone with
    /// it. What makes a held step safe is the store, not the step: after a
    /// relaunch a step value still undoes only what the store still records.
    @Test("A step is a plain value: nothing about it is stored, and it is judged against the store every time")
    func stepIsEphemeral() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let step = try #require(try store.parking.park(at: at(10)).automatedSteps.first)

        // Nothing in the schema holds a step or an offer to undo one.
        for entity in ModelContainerFactory.currentSchema.entities {
            #expect(!entity.properties.map(\.name).contains { $0.lowercased().contains("undo") }, "\(entity.name)")
        }

        // Read back through another context, standing in for a later process:
        // the store still records exactly this arrival, so the rule allows it.
        let later = DeliveryService(context: store.fresh())
        #expect(try later.undoAutomatedStep(step) == .accepted)
        #expect(try #require(try DeliveryService(context: store.fresh()).delivery(withID: delivery.id)).state == .accepted)
    }

    // MARK: Wording

    @Test("The Undo control says which delivery, which step, what it goes back to, and that the vehicle stays")
    func spokenLabel() {
        let arrival = AutomatedPickupStep(kind: .arrivedWhenParked, deliveryID: UUID(), deliveryNumber: 3, recordedAt: at(10))
        #expect(
            arrival.spokenUndoLabel
                == "Undo Arrived at Pickup for Delivery 3. It goes back to Accepted. The vehicle is still parked."
        )
        #expect(arrival.undoneNotice.title == "Undid Arrived at Pickup for Delivery 3")

        let pickup = AutomatedPickupStep(kind: .pickedUpWhenResumed, deliveryID: UUID(), deliveryNumber: 4, recordedAt: at(16))
        #expect(pickup.spokenUndoLabel.contains("Undo Picked Up for Delivery 4"))
        #expect(pickup.spokenUndoLabel.contains("The vehicle is still recorded as driving."))
        #expect(pickup.undoneNotice.detail.contains("Arrived at the pickup"))
    }
}
