import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Park records Arrived at Pickup and Resume Driving records Picked Up, for one
/// delivery, under the driver's two settings: which delivery moves, which never
/// do, the order the saves happen in, and that the vehicle always stands.
///
/// Every refused-save case reads the store through a **fresh context**, the
/// convention every rollback suite here follows: a model held across a
/// rollback can still report the value the rollback discarded.
@MainActor
@Suite("Park and Resume pickup workflow")
struct ParkResumePickupWorkflowTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @MainActor
    private struct Store {
        let context: ModelContext
        let shifts: ShiftService
        let deliveries: DeliveryService
        let settings: SettingsService

        var parking: ParkVehicleService { ParkVehicleService(context: context) }

        func fresh() -> ModelContext { ModelContext(context.container) }
    }

    /// A running shift started at `start`, with the two answers set as asked,
    /// or no settings row at all when `workflow` is `nil`.
    private func makeStore(workflow: Bool?, stacked: Bool = false) throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let store = Store(
            context: context,
            shifts: ShiftService(context: context),
            deliveries: DeliveryService(context: context),
            settings: SettingsService(context: context)
        )
        try store.shifts.startShift(at: start)
        if let workflow {
            try store.settings.setUsesParkAndResumeForPickups(workflow)
            try store.settings.setHandlesStackedOrdersInOrder(stacked)
        }
        return store
    }

    /// A delivery accepted at `minute` and advanced to `state`, one minute per
    /// step.
    @discardableResult
    private func delivery(in store: Store, acceptedAt minute: Double, advancedTo state: DeliveryState) throws -> Delivery {
        let delivery = try store.deliveries.startDelivery(at: at(minute))
        let steps: [DeliveryState] = switch state {
        case .accepted: []
        case .arrivedAtPickup: [.arrivedAtPickup]
        case .pickedUp: [.arrivedAtPickup, .pickedUp]
        case .delivered: [.arrivedAtPickup, .pickedUp, .delivered]
        case .cancelled: [.cancelled]
        }
        for (index, step) in steps.enumerated() {
            let date = at(minute + Double(index + 1))
            switch step {
            case .arrivedAtPickup: try store.deliveries.markArrivedAtPickup(delivery, at: date)
            case .pickedUp: try store.deliveries.markPickedUp(delivery, at: date)
            case .delivered: try store.deliveries.markDelivered(delivery, at: date)
            case .cancelled: try store.deliveries.cancelDelivery(delivery, at: date)
            case .accepted: break
            }
        }
        #expect(delivery.state == state)
        return delivery
    }

    private func suspension(in context: ModelContext) throws -> RouteSuspension? {
        try context.fetch(FetchDescriptor<RouteSuspension>()).max { $0.startedAt < $1.startedAt }
    }

    // MARK: Off

    @Test("With no settings row the workflow is off, Park and Resume move only the vehicle, and no row is created")
    func defaultsOff() throws {
        let store = try makeStore(workflow: nil)
        let heading = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .notEnabled)
        #expect(parked.pickup.notice == nil, "Nothing is added to what the driver is told")
        #expect(parked.automatedStep == nil)
        #expect(parked.shift.isRouteSuspended)
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryID == nil)

        let resumed = try store.parking.resumeDriving(at: at(20))
        #expect(resumed.pickup == .notEnabled)
        #expect(!resumed.shift.isRouteSuspended)
        #expect(heading.state == .accepted)
        #expect(heading.arrivedAtPickupAt == nil)
        #expect(try store.context.fetch(FetchDescriptor<DriverSettings>()).isEmpty)
    }

    @Test("The stacked-order answer on its own causes nothing")
    func stackedAloneCausesNothing() throws {
        let store = try makeStore(workflow: false, stacked: true)
        let first = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let second = try delivery(in: store, acceptedAt: 2, advancedTo: .arrivedAtPickup)

        #expect(try store.parking.park(at: at(10)).pickup == .notEnabled)
        #expect(try store.parking.resumeDriving(at: at(20)).pickup == .notEnabled)
        #expect(first.state == .accepted)
        #expect(second.state == .arrivedAtPickup)
        #expect(second.pickedUpAt == nil)
    }

    // MARK: One delivery

    @Test("Park marks the one delivery Arrived at Pickup at the instant of parking, and Resume marks it Picked Up")
    func oneDeliveryParkThenResume() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .markedArrived(deliveryNumber: 1))
        #expect(parked.shift.isRouteSuspended, "The vehicle is parked")
        #expect(delivery.state == .arrivedAtPickup)
        #expect(delivery.arrivedAtPickupAt == at(10), "The recorded parking instant, as the card's button would record it")
        #expect(delivery.pickedUpAt == nil, "Park never records Picked Up")
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryID == delivery.id)
        #expect(
            parked.automatedStep
                == AutomatedPickupStep(kind: .arrivedWhenParked, deliveryID: delivery.id, deliveryNumber: 1, recordedAt: at(10))
        )

        let resumed = try store.parking.resumeDriving(at: at(17))
        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: 1))
        #expect(!resumed.shift.isRouteSuspended, "The vehicle is driving")
        #expect(delivery.state == .pickedUp)
        #expect(delivery.pickedUpAt == at(17))
        #expect(delivery.pickupProvenance == .resumeAutomation)
        #expect(delivery.arrivedAtPickupAt == at(10), "The arrival is untouched")
        #expect(delivery.pickupWait == 420, "Parked to driving, exactly as recorded")
        #expect(
            resumed.automatedStep
                == AutomatedPickupStep(kind: .pickedUpWhenResumed, deliveryID: delivery.id, deliveryNumber: 1, recordedAt: at(17))
        )
    }

    @Test("A delivery already at Arrived at Pickup gets no second arrival, and Resume still picks it up")
    func alreadyArrived() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .arrivedAtPickup)
        let arrivedAt = delivery.arrivedAtPickupAt

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .alreadyArrived(deliveryNumber: 1))
        #expect(parked.automatedStep == nil, "Nothing was recorded, so there is nothing to undo")
        #expect(delivery.arrivedAtPickupAt == arrivedAt, "No duplicate event")
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryID == delivery.id)

        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: 1))
        #expect(delivery.pickedUpAt == at(15))
    }

    @Test("A delivery already in the car is a stop at the customer: nothing is recorded and nothing is said")
    func deliveryInTheCar() throws {
        let store = try makeStore(workflow: true)
        let carrying = try delivery(in: store, acceptedAt: 1, advancedTo: .pickedUp)
        let pickedUpAt = carrying.pickedUpAt

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .noneAwaitingPickup)
        #expect(parked.pickup.notice == nil)
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryID == nil)

        let resumed = try store.parking.resumeDriving(at: at(12))
        #expect(resumed.pickup == .noParkedPickup)
        #expect(carrying.pickedUpAt == pickedUpAt)
        #expect(carrying.deliveredAt == nil)
    }

    @Test("The arrival instant follows the card's clamping rather than inventing an earlier one")
    func arrivalClampsLikeTheCard() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 10, advancedTo: .accepted)

        // A device clock that has moved behind the recorded acceptance.
        _ = try store.parking.park(at: at(5))

        #expect(delivery.arrivedAtPickupAt == at(10), "Clamped to the delivery's own last event, never before it")
    }

    // MARK: Stacked orders

    @Test("Stacked orders off: two in progress park the vehicle and move neither")
    func stackedOffMovesNeither() throws {
        let store = try makeStore(workflow: true, stacked: false)
        let first = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let second = try delivery(in: store, acceptedAt: 2, advancedTo: .accepted)

        let parked = try store.parking.park(at: at(10))
        #expect(parked.pickup == .stackedNotHandled(inProgress: 2))
        #expect(parked.shift.isRouteSuspended, "Parking stands whatever the workflow decided")
        #expect(parked.shift.openRouteSuspension?.pickupWorkflowDeliveryID == nil)
        #expect(first.state == .accepted && second.state == .accepted)
        #expect(try store.parking.resumeDriving(at: at(15)).pickup == .noParkedPickup)
    }

    /// The real-shift sequence the workflow was built for, from the driver's
    /// observation: Delivery 3 and Delivery 4 in progress, each picked up by its
    /// own Park and Resume Driving, in order.
    @Test("D3 then D4: each Park and Resume works on the next order in turn")
    func stackedSequence() throws {
        let store = try makeStore(workflow: true, stacked: true)
        try delivery(in: store, acceptedAt: 1, advancedTo: .delivered)
        try delivery(in: store, acceptedAt: 5, advancedTo: .delivered)
        let third = try delivery(in: store, acceptedAt: 10, advancedTo: .accepted)
        let fourth = try delivery(in: store, acceptedAt: 11, advancedTo: .accepted)

        #expect(try store.parking.park(at: at(20)).pickup == .markedArrived(deliveryNumber: 3))
        #expect(third.state == .arrivedAtPickup)
        #expect(fourth.state == .accepted, "Delivery 4 waits for its own stop")

        #expect(try store.parking.resumeDriving(at: at(26)).pickup == .markedPickedUp(deliveryNumber: 3))
        #expect(third.state == .pickedUp)
        #expect(fourth.state == .accepted)

        #expect(try store.parking.park(at: at(35)).pickup == .markedArrived(deliveryNumber: 4))
        #expect(fourth.arrivedAtPickupAt == at(35))
        #expect(third.pickedUpAt == at(26), "Delivery 3 is not touched again")

        #expect(try store.parking.resumeDriving(at: at(41)).pickup == .markedPickedUp(deliveryNumber: 4))
        #expect(fourth.pickedUpAt == at(41))
        #expect(fourth.pickupProvenance == .resumeAutomation)
        #expect(third.pickupWait == 360)
        #expect(fourth.pickupWait == 360)
    }

    @Test("Three orders: the lowest-numbered still waiting for its pickup, and never the one in the car")
    func threeOrders() throws {
        let store = try makeStore(workflow: true, stacked: true)
        let carrying = try delivery(in: store, acceptedAt: 1, advancedTo: .pickedUp)
        let heading = try delivery(in: store, acceptedAt: 5, advancedTo: .accepted)
        let waiting = try delivery(in: store, acceptedAt: 6, advancedTo: .arrivedAtPickup)

        #expect(try store.parking.park(at: at(20)).pickup == .markedArrived(deliveryNumber: 2))
        #expect(heading.state == .arrivedAtPickup)
        #expect(waiting.pickedUpAt == nil)
        #expect(carrying.state == .pickedUp)
    }

    @Test("D3 and D4 both at their pickup: D3 is picked up and D4 waits for its own stop")
    func bothArrived() throws {
        let store = try makeStore(workflow: true, stacked: true)
        let third = try delivery(in: store, acceptedAt: 1, advancedTo: .arrivedAtPickup)
        let fourth = try delivery(in: store, acceptedAt: 2, advancedTo: .arrivedAtPickup)

        #expect(try store.parking.park(at: at(10)).pickup == .alreadyArrived(deliveryNumber: 1))
        #expect(try store.parking.resumeDriving(at: at(14)).pickup == .markedPickedUp(deliveryNumber: 1))
        #expect(third.state == .pickedUp)
        #expect(fourth.state == .arrivedAtPickup)
    }

    // MARK: Resume acts on the delivery Park chose, and only while it is still at its pickup

    /// The sixth case: Resume must not pick up a different stacked order
    /// because the first one changed while the driver was inside.
    @Test("A delivery cancelled between Park and Resume is not replaced by the next one")
    func cancelledBetweenParkAndResume() throws {
        let store = try makeStore(workflow: true, stacked: true)
        let third = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let fourth = try delivery(in: store, acceptedAt: 2, advancedTo: .arrivedAtPickup)

        #expect(try store.parking.park(at: at(10)).pickup == .markedArrived(deliveryNumber: 1))
        try store.deliveries.cancelDelivery(third, at: at(12))

        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup == .noLongerInProgress(deliveryNumber: 1))
        #expect(resumed.automatedStep == nil)
        #expect(!resumed.shift.isRouteSuspended, "Driving is recorded regardless")
        #expect(fourth.state == .arrivedAtPickup, "The other order is never picked up in its place")
        #expect(fourth.pickedUpAt == nil)
    }

    @Test("A pickup the driver recorded by hand while parked is left alone")
    func pickedUpByHandWhileParked() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        _ = try store.parking.park(at: at(10))
        try store.deliveries.markPickedUp(delivery, at: at(13), recordedBy: .manual)

        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup == .alreadyPickedUp(deliveryNumber: 1))
        #expect(resumed.pickup.notice == nil)
        #expect(delivery.pickedUpAt == at(13))
        #expect(delivery.pickupProvenance == .manual)
    }

    @Test("A delivery no longer at its pickup when Resume is pressed is not picked up")
    func notAtPickupAtResume() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let parked = try store.parking.park(at: at(10))
        let step = try #require(parked.automatedStep)
        try store.deliveries.undoAutomatedStep(step)

        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup == .notAtPickup(deliveryNumber: 1))
        #expect(delivery.state == .accepted)
        #expect(delivery.pickedUpAt == nil)
    }

    @Test("Turning the workflow off while parked leaves Resume recording only the vehicle")
    func turnedOffWhileParked() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        _ = try store.parking.park(at: at(10))

        try store.settings.setUsesParkAndResumeForPickups(false)
        let resumed = try store.parking.resumeDriving(at: at(15))

        #expect(resumed.pickup == .notEnabled)
        #expect(delivery.state == .arrivedAtPickup, "What Park recorded stays; nothing is rewritten")
    }

    // MARK: Refusals and failures

    @Test("A refused Park records no arrival")
    func parkRefusedRecordsNothing() throws {
        let store = try makeStore(workflow: true)
        try store.shifts.parkActiveShift(at: at(5))
        let delivery = try delivery(in: store, acceptedAt: 6, advancedTo: .accepted)

        #expect(throws: ShiftLifecycleError.shiftAlreadyParked(parkedAt: at(5))) {
            try store.parking.park(at: at(10))
        }
        #expect(delivery.state == .accepted)
        #expect(try store.fresh().fetch(FetchDescriptor<RouteSuspension>()).count == 1)
    }

    @Test("With no shift running, Park is refused and nothing is written")
    func noShift() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        try SettingsService(context: context).setUsesParkAndResumeForPickups(true)

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try ParkVehicleService(context: context).park(at: at(10))
        }
        #expect(try context.fetch(FetchDescriptor<RouteSuspension>()).isEmpty)
    }

    @Test("An arrival whose save fails leaves the vehicle parked and the delivery where it was")
    func arrivalFailureDoesNotUndoParking() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let id = delivery.id

        struct Refused: Error {}
        let parked = try ParkVehicleService(context: store.context, deliveryCommit: { _ in throw Refused() }).park(at: at(10))

        #expect(parked.pickup == .arrivalNotRecorded(deliveryNumber: 1))
        #expect(parked.automatedStep == nil)
        #expect(parked.pickup.notice?.title == "Delivery 1's arrival was not recorded")
        #expect(!store.context.hasChanges, "The rollback left nothing pending")

        let fresh = store.fresh()
        let stretch = try #require(try suspension(in: fresh))
        #expect(stretch.isOpen, "Parking was saved first and stands")
        #expect(stretch.pickupWorkflowDeliveryID == id, "It was saved with the stretch, in the one write")
        let stored = try #require(try DeliveryService(context: fresh).delivery(withID: id))
        #expect(stored.state == .accepted)
        #expect(stored.arrivedAtPickupAt == nil)

        // With no arrival, Resume has nothing to pick up, and says so.
        let resumed = try store.parking.resumeDriving(at: at(15))
        #expect(resumed.pickup == .notAtPickup(deliveryNumber: 1))
        #expect(try #require(try DeliveryService(context: store.fresh()).delivery(withID: id)).pickedUpAt == nil)
    }

    @Test("A refused Resume records no pickup")
    func resumeRefusedRecordsNothing() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .arrivedAtPickup)

        #expect(throws: ShiftLifecycleError.shiftNotParked) {
            try store.parking.resumeDriving(at: at(10))
        }
        #expect(delivery.pickedUpAt == nil)
    }

    @Test("A pickup whose save fails leaves the vehicle driving and the delivery at its pickup")
    func pickupFailureDoesNotUndoDriving() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let id = delivery.id
        _ = try store.parking.park(at: at(10))

        struct Refused: Error {}
        let resumed = try ParkVehicleService(context: store.context, deliveryCommit: { _ in throw Refused() })
            .resumeDriving(at: at(15))

        #expect(resumed.pickup == .pickupNotRecorded(deliveryNumber: 1))
        #expect(resumed.automatedStep == nil)
        let fresh = store.fresh()
        let stretch = try #require(try suspension(in: fresh))
        #expect(!stretch.isOpen, "Driving was saved first and stands")
        #expect(stretch.endedAt == at(15))
        let stored = try #require(try DeliveryService(context: fresh).delivery(withID: id))
        #expect(stored.state == .arrivedAtPickup)
        #expect(stored.pickedUpAt == nil)
        #expect(stored.pickupProvenance == nil)
    }

    // MARK: Save order

    /// The ordering, observed rather than read off the source: when the
    /// delivery step's save runs, the store already holds the vehicle state it
    /// follows.
    @Test("The vehicle is saved before the delivery step, on Park and on Resume")
    func vehicleIsSavedFirst() throws {
        let store = try makeStore(workflow: true)
        let delivery = try delivery(in: store, acceptedAt: 1, advancedTo: .accepted)
        let container = store.context.container
        var observed: [(open: Bool?, association: UUID?)] = []

        let spying = ParkVehicleService(context: store.context, deliveryCommit: { context in
            let stored = try? ModelContext(container).fetch(FetchDescriptor<RouteSuspension>()).first
            observed.append((stored?.isOpen, stored?.pickupWorkflowDeliveryID))
            try context.save()
        })

        _ = try spying.park(at: at(10))
        _ = try spying.resumeDriving(at: at(15))

        #expect(observed.count == 2, "One delivery save for each half")
        #expect(observed.first?.open == true, "Parked, and saved, before the arrival's save")
        #expect(observed.first?.association == delivery.id, "With the delivery it is for")
        #expect(observed.last?.open == false, "Driving, and saved, before the pickup's save")
        #expect(delivery.state == .pickedUp)
    }

    // MARK: Wording

    @Test("No sentence claims DashPilot detected a restaurant, an order or a handover")
    func wordingClaimsNoDetection() {
        let park: [ParkPickupOutcome] = [
            .notEnabled, .markedArrived(deliveryNumber: 3), .markedArrived(deliveryNumber: nil),
            .alreadyArrived(deliveryNumber: 3), .noneAwaitingPickup, .stackedNotHandled(inProgress: 2),
            .arrivalNotRecorded(deliveryNumber: 3), .deliveriesUnreadable
        ]
        let resume: [ResumePickupOutcome] = [
            .notEnabled, .noParkedPickup, .markedPickedUp(deliveryNumber: 3), .alreadyPickedUp(deliveryNumber: 3),
            .notAtPickup(deliveryNumber: 3), .noLongerInProgress(deliveryNumber: 3),
            .noLongerInProgress(deliveryNumber: nil), .pickupNotRecorded(deliveryNumber: 3)
        ]
        let notices = park.compactMap(\.notice) + resume.compactMap(\.notice)
        #expect(notices.count == 11)
        for notice in notices {
            for sentence in [notice.title, notice.detail, notice.spokenLabel, notice.sentence] {
                let lowered = sentence.lowercased()
                #expect(!lowered.contains("detect"), "\(sentence)")
                #expect(!lowered.contains("confirmed"), "\(sentence)")
                #expect(!lowered.contains("restaurant"), "\(sentence)")
                #expect(!lowered.contains("top delivery"), "\(sentence)")
            }
        }
    }

    @Test("The recorded lines name the delivery and say the step was recorded automatically")
    func recordedWording() throws {
        let arrived = try #require(ParkPickupOutcome.markedArrived(deliveryNumber: 3).notice)
        #expect(arrived.title == "Delivery 3 marked Arrived at Pickup")
        #expect(arrived.detail == "Recorded automatically when you parked.")
        #expect(arrived.spokenLabel.contains("Pick up orders with Park & Resume"), "A listener is told it was their setting")
        #expect(arrived.recordedAnEvent)

        let pickedUp = try #require(ResumePickupOutcome.markedPickedUp(deliveryNumber: 4).notice)
        #expect(pickedUp.title == "Delivery 4 marked Picked Up")
        #expect(pickedUp.detail == "Recorded automatically when you resumed driving.")
    }

    @Test("A recorded step and a declined one differ by symbol, not only by tint")
    func resultIsNotColourAlone() throws {
        let recorded = try #require(ParkPickupOutcome.markedArrived(deliveryNumber: 1).notice)
        let declined = try #require(ParkPickupOutcome.stackedNotHandled(inProgress: 2).notice)
        let pickedUp = try #require(ResumePickupOutcome.markedPickedUp(deliveryNumber: 1).notice)
        #expect(recorded.symbolName != declined.symbolName)
        #expect(pickedUp.symbolName != declined.symbolName)
        #expect(recorded.symbolName != pickedUp.symbolName, "Arrived and Picked Up are told apart too")
    }
}
