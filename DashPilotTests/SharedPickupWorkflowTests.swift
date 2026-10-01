import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Park and Resume Driving over deliveries the driver recorded as sharing a
/// pickup: which ones move together, which never do, that each shared event is
/// written whole or not at all, and that Undo takes back exactly one press.
///
/// Every refused-save case reads the store through a **fresh context**, the
/// convention every rollback suite here follows.
@MainActor
@Suite("Shared pickup workflow")
struct SharedPickupWorkflowTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private struct Refused: Error {}

    @MainActor
    private struct Store {
        let context: ModelContext
        let deliveries: DeliveryService
        let settings: SettingsService

        var parking: ParkVehicleService { ParkVehicleService(context: context) }

        func fresh() -> ModelContext { ModelContext(context.container) }

        func stored(_ delivery: Delivery) throws -> Delivery {
            let id = delivery.id
            return try #require(try fresh().fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id })).first)
        }
    }

    private func makeStore(workflow: Bool = true, stacked: Bool = true, at url: URL? = nil) throws -> Store {
        let container = try url.map(ModelContainerFactory.makeContainer(at:)) ?? ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        try ShiftService(context: context).startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(workflow)
        try settings.setHandlesStackedOrdersInOrder(stacked)
        return Store(context: context, deliveries: DeliveryService(context: context), settings: settings)
    }

    /// An offer of `count` accepted at `minute`, its deliveries in number order.
    private func offer(
        in store: Store,
        of count: Int = 2,
        sharing: Set<SharedStopKind>,
        at minute: Double
    ) throws -> [Delivery] {
        try store.deliveries.startOffer(deliveryCount: count, sharing: sharing, at: at(minute)).deliveriesInOrder
    }

    // MARK: Which deliveries move

    @Test("Deliveries marked Same pickup are both marked Arrived at Park and both Picked Up at Resume")
    func sharedPickupMovesTogether() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup, .dropOff], at: 1)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [1, 2], alreadyArrived: [])))
        #expect(pair.allSatisfy { $0.arrivedAtPickupAt == at(10) }, "One press, one instant")
        let stretch = try #require(parked.shift.openRouteSuspension)
        #expect(stretch.pickupWorkflowDeliveryIDs == pair.map(\.id), "Both, lowest number first")
        #expect(parked.automatedSteps.map(\.deliveryID) == pair.map(\.id))
        #expect(parked.pickup.notice?.title == "Deliveries 1 and 2 marked Arrived at Pickup")
        #expect(parked.pickup.notice?.detail.contains("you marked Same pickup") == true)

        let resumed = try store.parking.resumeDriving(at: at(17))
        #expect(
            resumed.pickup == .sharedPickupPickedUp(
                SharedPickupResume(recorded: [1, 2], alreadyPickedUp: [], notAtPickup: [], noLongerInProgress: [])
            )
        )
        #expect(pair.allSatisfy { $0.pickedUpAt == at(17) && $0.pickupProvenance == .resumeAutomation })
        #expect(resumed.pickup.notice?.title == "Deliveries 1 and 2 marked Picked Up")
        #expect(resumed.automatedSteps.count == 2)
    }

    @Test("A shared drop-off alone is not a shared pickup: Park marks only the lowest number")
    func sameDropOffDifferentPickup() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.dropOff], at: 1)

        let parked = try store.parking.park(at: at(10))

        #expect(parked.pickup == .markedArrived(deliveryNumber: 1))
        #expect(pair[0].state == .arrivedAtPickup)
        #expect(pair[1].state == .accepted, "Parking at one restaurant records nothing for the other")
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryIDs == [pair[0].id])

        _ = try store.parking.resumeDriving(at: at(15))
        #expect(pair[1].pickedUpAt == nil)
    }

    @Test("Unrelated stacked deliveries keep the lowest-number rule, one per Park")
    func unrelatedKeepTheRule() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [], at: 1)

        #expect(try store.parking.park(at: at(10)).pickup == .markedArrived(deliveryNumber: 1))
        #expect(pair[1].state == .accepted)
        #expect(try store.parking.resumeDriving(at: at(15)).pickup == .markedPickedUp(deliveryNumber: 1))
        #expect(try store.parking.park(at: at(20)).pickup == .markedArrived(deliveryNumber: 2))
    }

    @Test("An unrelated lower-numbered delivery is chosen first, alone, and the shared pair waits")
    func lowerUnrelatedFirst() throws {
        let store = try makeStore()
        let alone = try store.deliveries.startDelivery(at: at(1))
        let pair = try offer(in: store, sharing: [.pickup], at: 2)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .markedArrived(deliveryNumber: 1))
        #expect(alone.state == .arrivedAtPickup)
        #expect(pair.allSatisfy { $0.state == .accepted })

        _ = try store.parking.resumeDriving(at: at(15))
        let second = try store.parking.park(at: at(20))
        #expect(second.pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [2, 3], alreadyArrived: [])))
    }

    @Test("Mixed states: only the one still at Accepted is recorded, and both are picked up at Resume")
    func mixedStates() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        try store.deliveries.markArrivedAtPickup(pair[0], at: at(5))

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [2], alreadyArrived: [1])))
        #expect(pair[0].arrivedAtPickupAt == at(5), "No second arrival")
        #expect(pair[1].arrivedAtPickupAt == at(10))
        #expect(parked.automatedSteps.map(\.deliveryID) == [pair[1].id], "Undo would take back only what this press wrote")
        #expect(parked.pickup.notice?.detail.contains("Delivery 1 already had it") == true)

        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup.notice?.title == "Deliveries 1 and 2 marked Picked Up")
        #expect(pair.allSatisfy { $0.state == .pickedUp })
    }

    @Test("A member already picked up by hand is left alone, and the rest is recorded as one delivery")
    func memberAlreadyInTheCar() throws {
        let store = try makeStore(stacked: false)
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        try store.deliveries.markArrivedAtPickup(pair[0], at: at(3))
        try store.deliveries.markPickedUp(pair[0], at: at(4))

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .markedArrived(deliveryNumber: 2), "One delivery was still waiting, so it reads as one")
        #expect(pair[0].pickedUpAt == at(4))
    }

    // MARK: The stacked-orders switch

    @Test("Stacked orders off: deliveries that all share one pickup are one stop, and the workflow acts")
    func stackedOffSharedPickupIsOneStop() throws {
        let store = try makeStore(stacked: false)
        let pair = try offer(in: store, sharing: [.pickup], at: 1)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [1, 2], alreadyArrived: [])))
        #expect(pair.allSatisfy { $0.state == .arrivedAtPickup })
    }

    @Test("Stacked orders off: an unrelated order beside a shared pickup is still a choice, and nothing moves")
    func stackedOffWithAnUnrelatedOrder() throws {
        let store = try makeStore(stacked: false)
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        let other = try store.deliveries.startDelivery(at: at(2))

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .stackedNotHandled(inProgress: 3))
        #expect((pair + [other]).allSatisfy { $0.state == .accepted })
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryIDs.isEmpty == true)
    }

    @Test("Stacked orders off: a shared drop-off does not make two deliveries one stop")
    func stackedOffSharedDropOffIsNotOneStop() throws {
        let store = try makeStore(stacked: false)
        let pair = try offer(in: store, sharing: [.dropOff], at: 1)

        #expect(try store.parking.park(at: at(10)).pickup == .stackedNotHandled(inProgress: 2))
        #expect(pair.allSatisfy { $0.state == .accepted })
    }

    @Test("With the workflow off, a shared pickup moves nothing at all")
    func workflowOff() throws {
        let store = try makeStore(workflow: false)
        let pair = try offer(in: store, sharing: [.pickup, .dropOff], at: 1)

        #expect(try store.parking.park(at: at(10)).pickup == .notEnabled)
        #expect(try store.parking.resumeDriving(at: at(15)).pickup == .notEnabled)
        #expect(pair.allSatisfy { $0.state == .accepted })
    }

    // MARK: Resume acts on what Park chose

    @Test("A delivery cancelled inside is left alone, and the other is still picked up")
    func cancelledInside() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        _ = try store.parking.park(at: at(10))
        try store.deliveries.cancelDelivery(pair[0], at: at(12))

        let resumed = try store.parking.resumeDriving(at: at(15))

        #expect(
            resumed.pickup == .sharedPickupPickedUp(
                SharedPickupResume(recorded: [2], alreadyPickedUp: [], notAtPickup: [], noLongerInProgress: [1])
            )
        )
        #expect(resumed.pickup.notice?.title == "Delivery 2 marked Picked Up")
        #expect(resumed.pickup.notice?.detail.contains("Delivery 1 is no longer in progress") == true)
        #expect(pair[0].state == .cancelled)
        #expect(pair[1].state == .pickedUp)
        #expect(resumed.automatedSteps.map(\.deliveryID) == [pair[1].id])
    }

    @Test("Regrouping while parked changes the next Park, never what this Resume picks up")
    func resumeUsesTheStoredSet() throws {
        let store = try makeStore()
        let offer = try store.deliveries.startOffer(deliveryCount: 3, at: at(1))
        let ordered = offer.deliveriesInOrder
        let corrections = OfferCorrectionService(context: store.context)
        try corrections.recordSharedStops(pickup: [ordered[0], ordered[1]], dropOff: [], in: offer)

        _ = try store.parking.park(at: at(10))
        #expect(ordered[2].state == .accepted)

        // Inside, the driver changes their mind about which two share a pickup,
        // and records the third's arrival by hand.
        try corrections.recordSharedStops(pickup: [ordered[1], ordered[2]], dropOff: [], in: offer)
        try store.deliveries.markArrivedAtPickup(ordered[2], at: at(12))

        let resumed = try store.parking.resumeDriving(at: at(15))

        #expect(ordered[0].state == .pickedUp, "Park chose it, so Resume picks it up")
        #expect(ordered[1].state == .pickedUp)
        #expect(ordered[2].state == .arrivedAtPickup, "Park never chose it, whatever it is grouped with now")
        #expect(resumed.automatedSteps.count == 2)
    }

    @Test("The stored set survives a relaunch, and Resume in the new process picks up both")
    func survivesTermination() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotSharedPickupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "DashPilot.store")

        var ids: [UUID] = []
        do {
            let store = try makeStore(at: url)
            ids = try offer(in: store, sharing: [.pickup], at: 1).map(\.id)
            _ = try store.parking.park(at: at(10))
        }

        // A new container stands in for the process the Lock Screen wakes.
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.openRouteSuspension?.pickupWorkflowDeliveryIDs == ids)

        let resumed = try ParkVehicleService(context: context).resumeDriving(at: at(15))
        #expect(resumed.pickup.notice?.title == "Deliveries 1 and 2 marked Picked Up")
        let stored = try context.fetch(FetchDescriptor<Delivery>())
        #expect(stored.allSatisfy { $0.pickedUpAt == at(15) })
    }

    // MARK: All or nothing

    @Test("A refused save at Park records neither arrival, and the vehicle stays parked with both stored")
    func parkSaveFailureRecordsNeither() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        let failing = ParkVehicleService(context: store.context, deliveryCommit: { _ in throw Refused() })

        let parked = try failing.park(at: at(10))

        #expect(parked.pickup == .sharedPickupArrivalNotRecorded(deliveryNumbers: [1, 2]))
        #expect(parked.pickup.notice?.title == "No arrival recorded for Deliveries 1 and 2")
        #expect(parked.automatedSteps.isEmpty)
        #expect(try store.stored(pair[0]).arrivedAtPickupAt == nil)
        #expect(try store.stored(pair[1]).arrivedAtPickupAt == nil, "Never half-recorded")
        let fresh = store.fresh()
        let stretch = try #require(try fresh.fetch(FetchDescriptor<RouteSuspension>()).first)
        #expect(stretch.isOpen, "Parking was saved first and stands")
        #expect(stretch.pickupWorkflowDeliveryIDs == pair.map(\.id))
    }

    @Test("A refused save at Resume records neither pickup, and the vehicle is driving")
    func resumeSaveFailureRecordsNeither() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        _ = try store.parking.park(at: at(10))
        let failing = ParkVehicleService(context: store.context, deliveryCommit: { _ in throw Refused() })

        let resumed = try failing.resumeDriving(at: at(15))

        #expect(resumed.pickup == .sharedPickupNotRecorded(deliveryNumbers: [1, 2]))
        #expect(try store.stored(pair[0]).pickedUpAt == nil)
        #expect(try store.stored(pair[1]).pickedUpAt == nil)
        let stretch = try #require(try store.fresh().fetch(FetchDescriptor<RouteSuspension>()).first)
        #expect(!stretch.isOpen, "Driving was saved first and stands")
    }

    @Test("A shared advance is judged whole before anything is written")
    func judgedBeforeWritten() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        try store.deliveries.markArrivedAtPickup(pair[1], at: at(3))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.alreadyRecorded(.arrivedAtPickup))) {
            try store.deliveries.markArrivedAtPickup(together: pair, at: at(10))
        }
        #expect(pair[0].arrivedAtPickupAt == nil, "The valid one was not written in memory either")
        #expect(try store.stored(pair[0]).arrivedAtPickupAt == nil)
    }

    // MARK: Undo

    @Test("One Undo after a shared Park takes back both arrivals and leaves the vehicle parked")
    func undoSharedArrival() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        let parked = try store.parking.park(at: at(10))
        let action = try #require(AutomatedPickupAction(parked.automatedSteps))
        #expect(action.spokenUndoLabel.contains("Undo Arrived at Pickup for Deliveries 1 and 2"))
        #expect(action.spokenUndoLabel.contains("The vehicle is still parked"))

        let restored = try store.deliveries.undoAutomatedSteps(action.steps)

        #expect(restored == .accepted)
        #expect(pair.allSatisfy { $0.arrivedAtPickupAt == nil })
        #expect(action.undoneNotice.title == "Undid Arrived at Pickup for Deliveries 1 and 2")
        let shift = try #require(pair[0].shift)
        #expect(shift.isRouteSuspended, "The vehicle is still parked")
    }

    @Test("One Undo after a shared Resume takes back both pickups and leaves the vehicle driving")
    func undoSharedPickup() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        _ = try store.parking.park(at: at(10))
        let resumed = try store.parking.resumeDriving(at: at(15))

        try store.deliveries.undoAutomatedSteps(resumed.automatedSteps)

        #expect(pair.allSatisfy { $0.state == .arrivedAtPickup && $0.pickupProvenance == nil })
        #expect(pair.allSatisfy { $0.arrivedAtPickupAt == at(10) }, "The arrival Park recorded stays")
        #expect(resumed.shift.isRouteSuspended == false, "The vehicle is still driving")
    }

    @Test("Undo never cascades into a delivery the press did not write to")
    func undoNeverCascades() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        try store.deliveries.markArrivedAtPickup(pair[0], at: at(5))
        let parked = try store.parking.park(at: at(10))

        try store.deliveries.undoAutomatedSteps(parked.automatedSteps)

        #expect(pair[0].arrivedAtPickupAt == at(5), "The driver's own arrival stays")
        #expect(pair[1].arrivedAtPickupAt == nil)
    }

    @Test("Later evidence on one refuses the whole Undo, and nothing moves on either")
    func undoRefusedWhole() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        let parked = try store.parking.park(at: at(10))
        try store.deliveries.markPickedUp(pair[0], at: at(12))

        #expect(throws: DeliveryLifecycleError.invalidAutomatedUndo(.laterEventRecorded)) {
            try store.deliveries.undoAutomatedSteps(parked.automatedSteps)
        }
        #expect(pair[0].state == .pickedUp)
        #expect(pair[1].arrivedAtPickupAt == at(10), "Not half taken back")
        #expect(try store.stored(pair[1]).arrivedAtPickupAt == at(10))
    }

    @Test("A refused save during Undo leaves both events recorded")
    func undoSaveFailure() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        let parked = try store.parking.park(at: at(10))
        let failing = DeliveryService(context: store.context, commit: { _ in throw Refused() })

        #expect(throws: DeliveryLifecycleError.self) {
            try failing.undoAutomatedSteps(parked.automatedSteps)
        }
        #expect(try store.stored(pair[0]).arrivedAtPickupAt == at(10))
        #expect(try store.stored(pair[1]).arrivedAtPickupAt == at(10))
    }

    @Test("One step reads exactly as it always did")
    func oneStepWordingUnchanged() throws {
        let store = try makeStore()
        _ = try store.deliveries.startDelivery(at: at(1))
        let parked = try store.parking.park(at: at(10))
        let step = try #require(parked.automatedSteps.first)
        let action = try #require(AutomatedPickupAction(parked.automatedSteps))

        #expect(action.spokenUndoLabel == step.spokenUndoLabel)
        #expect(action.undoneNotice == step.undoneNotice)
    }

    // MARK: Words

    @Test("No shared-pickup sentence claims DashPilot saw a restaurant, a customer or a handover")
    func sentencesClaimNothing() {
        let outcomes: [PickupWorkflowNotice?] = [
            ParkPickupOutcome.sharedPickupArrived(SharedPickupArrival(recorded: [3, 4], alreadyArrived: [])).notice,
            ParkPickupOutcome.sharedPickupArrived(SharedPickupArrival(recorded: [], alreadyArrived: [3, 4])).notice,
            ParkPickupOutcome.sharedPickupArrivalNotRecorded(deliveryNumbers: [3, 4]).notice,
            ResumePickupOutcome.sharedPickupPickedUp(
                SharedPickupResume(recorded: [4], alreadyPickedUp: [3], notAtPickup: [], noLongerInProgress: [])
            ).notice,
            ResumePickupOutcome.sharedPickupPickedUp(
                SharedPickupResume(recorded: [], alreadyPickedUp: [], notAtPickup: [3], noLongerInProgress: [4])
            ).notice,
            ResumePickupOutcome.sharedPickupNotRecorded(deliveryNumbers: [3, 4]).notice
        ]
        for notice in outcomes {
            let words = [notice?.title, notice?.detail, notice?.spokenLabel].compactMap { $0 }.joined(separator: " ")
            #expect(!words.isEmpty)
            for claim in ["detected", "restaurant", "customer", "handed", "same address", "arrived at the store"] {
                #expect(!words.lowercased().contains(claim), "Said \(claim): \(words)")
            }
        }
    }

    @Test("Delivery numbers are listed in order however they are given")
    func names() {
        #expect(PickupWorkflowNotice.names([4]) == "Delivery 4")
        #expect(PickupWorkflowNotice.names([4, 3]) == "Deliveries 3 and 4")
        #expect(PickupWorkflowNotice.names([5, 3, 4]) == "Deliveries 3, 4 and 5")
    }
}
