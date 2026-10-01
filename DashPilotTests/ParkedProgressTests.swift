import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// `Resume driving after delivery progress`: a Picked Up or Delivered the
/// driver records while parked resumes driving only when that stop has nothing
/// left to record, through the one Resume Driving path, never recursively, and
/// with one Undo that takes back the step and the driving together.
///
/// Every refused-save case reads the store through a **fresh context**.
@MainActor
@Suite("Resume driving after delivery progress")
struct ParkedProgressTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private struct Refused: Error {}

    @MainActor
    private struct Store {
        let context: ModelContext
        let deliveries: DeliveryService

        var parking: ParkVehicleService { ParkVehicleService(context: context) }
        var progress: DeliveryProgressService { DeliveryProgressService(context: context) }
        var shift: Shift { get throws { try #require(try ShiftService(context: context).activeShift()) } }

        func fresh() -> ModelContext { ModelContext(context.container) }

        func stored(_ delivery: Delivery) throws -> Delivery {
            let id = delivery.id
            return try #require(try fresh().fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id })).first)
        }

        func storedSuspensions() throws -> [RouteSuspension] {
            try fresh().fetch(FetchDescriptor<RouteSuspension>(sortBy: [SortDescriptor(\.startedAt)]))
        }
    }

    private func makeStore(resumes: Bool = true, workflow: Bool = false, stacked: Bool = false) throws -> Store {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        try ShiftService(context: context).startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setResumesDrivingAfterDeliveryProgress(resumes)
        try settings.setUsesParkAndResumeForPickups(workflow)
        try settings.setHandlesStackedOrdersInOrder(stacked)
        return Store(context: context, deliveries: DeliveryService(context: context))
    }

    private func offer(in store: Store, of count: Int = 2, sharing: Set<SharedStopKind>, at minute: Double) throws -> [Delivery] {
        try store.deliveries.startOffer(deliveryCount: count, sharing: sharing, at: at(minute)).deliveriesInOrder
    }

    private func arrived(_ delivery: Delivery, in store: Store, at minute: Double) throws {
        try store.deliveries.markArrivedAtPickup(delivery, at: at(minute))
    }

    // MARK: The setting

    @Test("Off: a pickup recorded while parked leaves the vehicle parked and says nothing")
    func offStaysParked() throws {
        let store = try makeStore(resumes: false)
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))

        let result = try store.progress.record(.pickedUp, of: delivery, at: at(9))

        #expect(result.parked == .notApplicable)
        #expect(result.parked.notice == nil)
        #expect(result.undoableAction == nil)
        #expect(try store.shift.isRouteSuspended)
        #expect(delivery.pickupProvenance == .manual)
    }

    @Test("With no settings row at all the answer is off, and reading it creates none")
    func noRowIsOff() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        #expect(SettingsService(context: context).resumesDrivingAfterDeliveryProgress() == false)
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty)
    }

    @Test("The answer persists and changing it rewrites nothing recorded")
    func persistsAndRewritesNothing() throws {
        let store = try makeStore(resumes: false)
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        try store.parking.resumeDriving(at: at(8))
        try store.deliveries.markPickedUp(delivery, at: at(9))
        try store.deliveries.markDelivered(delivery, at: at(20))
        let before = (try store.storedSuspensions().map { [$0.startedAt, $0.endedAt] }, delivery.deliveredAt)

        try SettingsService(context: store.context).setResumesDrivingAfterDeliveryProgress(true)

        let reread = try #require(try store.fresh().fetch(FetchDescriptor<DriverSettings>()).first)
        #expect(reread.resumesDrivingAfterDeliveryProgress)
        #expect(try store.storedSuspensions().map { [$0.startedAt, $0.endedAt] } == before.0)
        #expect(try store.stored(delivery).deliveredAt == before.1)
    }

    // MARK: Picked Up

    @Test("On: one independent order picked up while parked resumes driving at the pickup's instant")
    func independentPickupResumes() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))

        let result = try store.progress.record(.pickedUp, of: delivery, at: at(11))

        #expect(result.parked == .resumed(step: .pickedUp, deliveryNumbers: [1]))
        let suspension = try #require(try store.storedSuspensions().first)
        #expect(suspension.endedAt == at(11), "Closed at the step's own instant")
        #expect(try store.shift.isRouteSuspended == false)
        #expect(try store.stored(delivery).pickupProvenance == .manual, "The driver's pickup, recorded once")
        #expect(result.parked.notice?.title == "Delivery 1 picked up · driving resumed")
        let notice = try #require(result.parked.notice)
        for claim in ["detected", "moving", "left the", "you left", "drove away"] {
            #expect(!notice.spokenLabel.lowercased().contains(claim), "Claims \(claim)")
            #expect(!notice.detail.lowercased().contains(claim))
        }
        #expect(notice.spokenLabel.contains("setting"), "Says it was the driver's setting")
        let action = try #require(result.undoableAction)
        #expect(action.recordedAt == at(11) && action.resumedAt == at(11) && action.suspensionID == suspension.id)
    }

    @Test("A paused shift is untouched: no step is recorded and nothing resumes")
    func pausedStaysPaused() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        // Pausing is refused while a delivery is open, so the step itself is
        // what a paused shift refuses.
        try store.deliveries.markPickedUp(delivery, at: at(6))
        try store.deliveries.markDelivered(delivery, at: at(7))
        try ShiftService(context: store.context).pauseActiveShift(at: at(8))
        let shift = try store.shift
        #expect(shift.isPaused)
        #expect(try store.storedSuspensions().isEmpty)
        #expect(throws: (any Error).self) { try store.deliveries.startDelivery(at: at(9)) }
        #expect(shift.isPaused, "A paused shift is never resumed by any of this")
    }

    @Test("A running shift that is not parked records the step and nothing else")
    func runningUnchanged() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)

        let result = try store.progress.record(.pickedUp, of: delivery, at: at(9))

        #expect(result.parked == .notApplicable)
        #expect(try store.storedSuspensions().isEmpty, "Nothing opened or closed")
        #expect(delivery.state == .pickedUp)
    }

    @Test("Same pickup with a member still to collect stays parked; the last one resumes")
    func groupedPickup() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        for delivery in pair { try arrived(delivery, in: store, at: 5) }
        try store.parking.park(at: at(6))

        let first = try store.progress.record(.pickedUp, of: pair[0], at: at(9))
        #expect(first.parked == .stillParkedForGroup(step: .pickedUp, remaining: [2]))
        #expect(first.parked.notice?.detail == "Delivery 2 still needs pickup at this stop.")
        #expect(try store.shift.isRouteSuspended)
        #expect(first.undoableAction == nil)

        let second = try store.progress.record(.pickedUp, of: pair[1], at: at(10))
        #expect(second.parked == .resumed(step: .pickedUp, deliveryNumbers: [1, 2]))
        #expect(second.parked.notice?.title == "Deliveries 1 and 2 picked up · driving resumed")
        #expect(try store.shift.isRouteSuspended == false)
    }

    @Test("Same drop-off alone does not make a pickup stop: the other order still to collect keeps it parked as an unrelated one")
    func sameDropOffDoesNotJoinThePickup() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.dropOff], at: 1)
        try arrived(pair[0], in: store, at: 5)
        try store.parking.park(at: at(6))

        let result = try store.progress.record(.pickedUp, of: pair[0], at: at(9))

        #expect(result.parked == .stillParkedForOtherOrders(step: .pickedUp, remaining: [2]))
        #expect(result.parked != .stillParkedForGroup(step: .pickedUp, remaining: [2]), "Not as a shared pickup")
        #expect(pair[1].state == .accepted, "And it is not touched")
    }

    @Test("Same drop-off with the other order already in the car: the pickup stop is done")
    func sameDropOffOtherInCar() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.dropOff], at: 1)
        try arrived(pair[1], in: store, at: 2)
        try store.deliveries.markPickedUp(pair[1], at: at(3))
        try arrived(pair[0], in: store, at: 5)
        try store.parking.park(at: at(6))

        let result = try store.progress.record(.pickedUp, of: pair[0], at: at(9))
        #expect(result.parked == .resumed(step: .pickedUp, deliveryNumbers: [1]))
    }

    @Test("An unrelated stacked order still to collect keeps the vehicle parked and is not modified")
    func unrelatedStackedPickup() throws {
        let store = try makeStore()
        let first = try store.deliveries.startDelivery(at: at(1))
        let other = try store.deliveries.startDelivery(at: at(2))
        try arrived(first, in: store, at: 5)
        try store.parking.park(at: at(6))
        let otherBefore = DeliveryLifecycleRecord(other)

        let result = try store.progress.record(.pickedUp, of: first, at: at(9))

        #expect(result.parked == .stillParkedForOtherOrders(step: .pickedUp, remaining: [2]))
        #expect(try store.shift.isRouteSuspended, "Completing one unrelated order is not leaving")
        #expect(DeliveryLifecycleRecord(try store.stored(other)) == otherBefore, "Untouched")
    }

    // MARK: Delivered

    @Test("An independent drop-off delivered while parked resumes driving")
    func independentDropOffResumes() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.deliveries.markPickedUp(delivery, at: at(6))
        try store.parking.park(at: at(20))

        let result = try store.progress.record(.delivered, of: delivery, at: at(22))

        #expect(result.parked == .resumed(step: .delivered, deliveryNumbers: [1]))
        #expect(result.parked.notice?.title == "Delivery 1 delivered · driving resumed")
        #expect(try store.storedSuspensions().first?.endedAt == at(22))
    }

    @Test("Same drop-off partly delivered stays parked; the last one resumes")
    func groupedDropOff() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.dropOff], at: 1)
        for delivery in pair {
            try arrived(delivery, in: store, at: 2)
            try store.deliveries.markPickedUp(delivery, at: at(3))
        }
        try store.parking.park(at: at(20))

        let first = try store.progress.record(.delivered, of: pair[0], at: at(21))
        #expect(first.parked == .stillParkedForGroup(step: .delivered, remaining: [2]))
        #expect(try store.shift.isRouteSuspended)

        let second = try store.progress.record(.delivered, of: pair[1], at: at(22))
        #expect(second.parked == .resumed(step: .delivered, deliveryNumbers: [1, 2]))
    }

    @Test("Same pickup alone does not make a drop-off stop: the other order in the car keeps it parked as an unrelated one")
    func samePickupDoesNotJoinTheDropOff() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        for delivery in pair {
            try arrived(delivery, in: store, at: 2)
            try store.deliveries.markPickedUp(delivery, at: at(3))
        }
        try store.parking.park(at: at(20))

        let result = try store.progress.record(.delivered, of: pair[0], at: at(21))
        #expect(result.parked == .stillParkedForOtherOrders(step: .delivered, remaining: [2]))
    }

    @Test("An unrelated order still to collect does not hold a drop-off open")
    func pendingPickupDoesNotHoldADropOff() throws {
        let store = try makeStore()
        let delivered = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivered, in: store, at: 2)
        try store.deliveries.markPickedUp(delivered, at: at(3))
        let later = try store.deliveries.startDelivery(at: at(4))
        try store.parking.park(at: at(20))

        let result = try store.progress.record(.delivered, of: delivered, at: at(21))
        #expect(result.parked == .resumed(step: .delivered, deliveryNumbers: [1]))
        #expect(later.state == .accepted, "Untouched")
    }

    // MARK: Orchestration

    @Test("Park's arrival then the driver's own pickup: Resume records no second pickup, and the step is recorded once")
    func noDuplicatePickupUnderTheWorkflow() throws {
        let store = try makeStore(workflow: true)
        let delivery = try store.deliveries.startDelivery(at: at(1))
        let parked = try store.parking.park(at: at(6))
        #expect(parked.pickup == .markedArrived(deliveryNumber: 1))

        let result = try store.progress.record(.pickedUp, of: delivery, at: at(9))

        #expect(result.parked == .resumed(step: .pickedUp, deliveryNumbers: [1]))
        let stored = try store.stored(delivery)
        #expect(stored.pickedUpAt == at(9))
        #expect(stored.pickupProvenance == .manual, "Not overwritten by Resume's automation")
        #expect(try store.storedSuspensions().count == 1, "One stretch, closed once")
    }

    @Test("Resume Driving's own pickup never resumes anything again: it does not go through this path")
    func resumePickupIsNotRecursive() throws {
        let store = try makeStore(workflow: true)
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try store.parking.park(at: at(6))

        let resumed = try store.parking.resumeDriving(at: at(9))

        #expect(resumed.pickup == .markedPickedUp(deliveryNumber: 1))
        #expect(delivery.pickupProvenance == .resumeAutomation)
        #expect(try store.storedSuspensions().map(\.endedAt) == [at(9)], "One transition, the button's")
        #expect(try store.shift.isRouteSuspended == false)
    }

    @Test("A stretch chosen for a pickup still at Arrived keeps it parked, so Resume never writes a pickup from here")
    func parkedPickupHoldsTheStop() throws {
        let store = try makeStore(workflow: true, stacked: true)
        // Delivery 1 in the car; Park (stacked on) marks Delivery 2 arrived even
        // though the driver is at Delivery 1's customer.
        let carried = try store.deliveries.startDelivery(at: at(1))
        try arrived(carried, in: store, at: 2)
        try store.deliveries.markPickedUp(carried, at: at(3))
        let waiting = try store.deliveries.startDelivery(at: at(4))
        #expect(try store.parking.park(at: at(20)).pickup == .markedArrived(deliveryNumber: 2))

        let result = try store.progress.record(.delivered, of: carried, at: at(22))

        #expect(result.parked == .stillParkedForParkedPickup(remaining: [2]))
        #expect(waiting.pickedUpAt == nil, "No pickup the driver did not record")
        #expect(try store.shift.isRouteSuspended)
    }

    @Test("A failed automatic resume leaves the step recorded and the vehicle parked")
    func failedResume() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))

        let result = try DeliveryProgressService(context: store.context, resumeDriving: { _, _ in throw Refused() })
            .record(.pickedUp, of: delivery, at: at(9))

        #expect(result.parked == .resumeNotRecorded(step: .pickedUp, deliveryNumbers: [1]))
        #expect(result.undoableAction == nil)
        #expect(try store.stored(delivery).pickedUpAt == at(9), "The driver's step stands")
        #expect(try store.storedSuspensions().first?.endedAt == nil, "Still parked")
        #expect(result.parked.notice?.detail.contains("Resume Driving") == true)
    }

    @Test("A failed step save records no driving")
    func failedStepInventsNoResume() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))

        #expect(throws: DeliveryLifecycleError.self) {
            try DeliveryProgressService(context: store.context, deliveryCommit: { _ in throw Refused() })
                .record(.pickedUp, of: delivery, at: at(9))
        }
        #expect(try store.stored(delivery).pickedUpAt == nil)
        #expect(try store.storedSuspensions().first?.endedAt == nil)
    }

    @Test("Working time is unchanged by parking and by an automatic resume")
    func workingTimeUnchanged() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        try store.progress.record(.pickedUp, of: delivery, at: at(16))

        #expect(try store.shift.workingDuration(asOf: at(30)) == 30 * 60)
    }

    @Test("Siri and the Lock Screen reach the same path, and say why driving resumed")
    func intentPath() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))

        let outcome = try IntentLifecycleService(context: store.context).recordDeliveryProgress(at: at(9))

        #expect(
            outcome == .deliveryEventRecorded(
                number: 1, state: .pickedUp, parked: .resumed(step: .pickedUp, deliveryNumbers: [1])
            )
        )
        #expect(outcome.confirmation.contains("Driving resumed by your Resume driving after delivery progress setting"))
        #expect(outcome.confirmation.contains("Open DashPilot"), "A capture session starts only in the foreground")
        #expect(try store.shift.isRouteSuspended == false)
        #expect(delivery.pickupProvenance == .manual)
    }

    // MARK: Undo

    @Test("Undo takes back the pickup and the driving, both, and reopens the same stretch")
    func undoBoth() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        let action = try #require(try store.progress.record(.pickedUp, of: delivery, at: at(9)).undoableAction)

        let restored = try store.progress.undo(action)

        #expect(restored == .arrivedAtPickup)
        let stored = try store.stored(delivery)
        #expect(stored.pickedUpAt == nil && stored.pickupProvenance == nil)
        #expect(stored.arrivedAtPickupAt == at(5), "Nothing earlier moves")
        let suspensions = try store.storedSuspensions()
        #expect(suspensions.count == 1 && suspensions[0].endedAt == nil && suspensions[0].startedAt == at(6))
        #expect(try store.shift.isRouteSuspended)
    }

    @Test("Undo after a Delivered reopens the delivery and parks again")
    func undoDelivered() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.deliveries.markPickedUp(delivery, at: at(6))
        try store.parking.park(at: at(20))
        let action = try #require(try store.progress.record(.delivered, of: delivery, at: at(22)).undoableAction)

        #expect(try store.progress.undo(action) == .pickedUp)
        #expect(try store.stored(delivery).deliveredAt == nil)
        #expect(try store.shift.isRouteSuspended)
    }

    @Test("A later event on the delivery refuses the whole Undo")
    func laterEventRefuses() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        let action = try #require(try store.progress.record(.pickedUp, of: delivery, at: at(9)).undoableAction)
        try store.deliveries.markDelivered(delivery, at: at(12))

        #expect(throws: DeliveryLifecycleError.invalidParkedProgressUndo(.laterEventRecorded)) {
            try store.progress.undo(action)
        }
        #expect(try store.stored(delivery).deliveredAt == at(12))
        #expect(try store.storedSuspensions().first?.endedAt == at(9), "The driving stays too")
    }

    @Test("Parking again since refuses the whole Undo")
    func parkedAgainRefuses() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        let action = try #require(try store.progress.record(.pickedUp, of: delivery, at: at(9)).undoableAction)
        try store.parking.park(at: at(10))

        #expect(throws: DeliveryLifecycleError.invalidParkedProgressUndo(.vehicleStateChanged)) {
            try store.progress.undo(action)
        }
        #expect(try store.stored(delivery).pickedUpAt == at(9), "The step stays")
        #expect(try store.storedSuspensions().count == 2)
    }

    @Test("Undo never touches another delivery's events")
    func undoLeavesOthersAlone() throws {
        let store = try makeStore()
        let pair = try offer(in: store, sharing: [.pickup], at: 1)
        for delivery in pair { try arrived(delivery, in: store, at: 5) }
        try store.parking.park(at: at(6))
        try store.progress.record(.pickedUp, of: pair[0], at: at(8))
        let action = try #require(try store.progress.record(.pickedUp, of: pair[1], at: at(9)).undoableAction)

        try store.progress.undo(action)

        #expect(try store.stored(pair[0]).pickedUpAt == at(8), "The earlier, separate step stays")
        #expect(try store.stored(pair[1]).pickedUpAt == nil)
    }

    @Test("A refused Undo save leaves the step, the driving and the route as stored")
    func undoSaveRefused() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try arrived(delivery, in: store, at: 5)
        try store.parking.park(at: at(6))
        let action = try #require(try store.progress.record(.pickedUp, of: delivery, at: at(9)).undoableAction)

        #expect(throws: DeliveryLifecycleError.self) {
            try DeliveryProgressService(context: store.context, deliveryCommit: { _ in throw Refused() }).undo(action)
        }
        #expect(try store.stored(delivery).pickedUpAt == at(9))
        #expect(try store.storedSuspensions().first?.endedAt == at(9))
    }

    // MARK: Route

    @Test("Automatic resume opens a new capture session, nothing is measured across the stretch, and Undo drops the positions since")
    func captureBoundary() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(servicesEnabled: true, status: .authorizedWhenInUse, accuracy: .full)
        )
        var clock = at(0)
        let tracking = LocationTrackingService(
            context: context, authorization: authorization, provider: provider, saveBatchSize: 1, now: { clock }
        )
        func emit(_ seconds: Double, north: Double) {
            clock = start.addingTimeInterval(seconds)
            provider.emit(SyntheticRoute.sample(at: clock, northMetres: north))
        }

        try ShiftService(context: context).startShift(at: start)
        try SettingsService(context: context).setResumesDrivingAfterDeliveryProgress(true)
        tracking.synchronize()
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(1))
        for step in 1...5 { emit(60 + Double(step) * 5, north: Double(step) * 100) }
        try deliveries.markArrivedAtPickup(delivery, at: at(2))

        tracking.prepareForRouteSuspension()
        try ParkVehicleService(context: context).park(at: at(3))
        tracking.synchronize()
        emit(200, north: 900) // a walk: refused while parked

        clock = at(10)
        let result = try DeliveryProgressService(context: context).record(.pickedUp, of: delivery, at: at(10))
        #expect(result.parked == .resumed(step: .pickedUp, deliveryNumbers: [1]))
        tracking.synchronize()
        for step in 1...5 { emit(600 + Double(step) * 5, north: 5_000 + Double(step) * 100) }

        let shift = try #require(try ShiftService(context: context).activeShift())
        let samples = shift.routeSamples()
        let sessions = Set(samples.map(\.captureSessionID))
        #expect(sessions.count == 2, "A new session after the automatic resume, as after the button")
        #expect(!samples.contains { $0.timestamp == start.addingTimeInterval(200) }, "Nothing while parked")
        let distance = shift.recordedDistance()
        #expect(distance.metres < 1_000, "No line from the parking space to where driving resumed: \(distance.metres)")
        #expect(distance.gapCount >= 1)

        tracking.prepareForRouteSuspension()
        try DeliveryProgressService(context: context).undo(try #require(result.undoableAction))
        tracking.synchronize()
        #expect(tracking.state == .routeSuspended)
        #expect(shift.routeSamples().allSatisfy { $0.timestamp < at(10) }, "The positions since the resume are gone")
        #expect(shift.routeSamples().count == 5, "And none before it")
    }

    // MARK: The rule, on plain values

    private struct Plain {
        let number: Int
        let state: DeliveryState
        var pickup: UUID?
        var dropOff: UUID?
        var parkedFor = false
    }

    private func evaluate(_ stepped: Plain, _ step: ParkedProgressStep, _ others: [Plain]) -> ParkedStopCompletion<Plain> {
        ParkedStopCompletion.evaluate(
            stepped: stepped,
            step: step,
            others: others,
            parkedFor: \.parkedFor,
            number: \.number,
            state: \.state,
            sharedStop: { $1 == .pickup ? $0.pickup : $0.dropOff }
        )
    }

    private func numbers(_ completion: ParkedStopCompletion<Plain>) -> [Int] {
        switch completion {
        case .complete: []
        case let .groupedDeliveriesRemain(items), let .otherDeliveriesRemain(items), let .parkedPickupRemains(items):
            items.map(\.number)
        }
    }

    @Test("Finished deliveries never hold a stop open, cancelled grouped members included")
    func finishedIgnored() {
        let group = UUID()
        let stepped = Plain(number: 1, state: .pickedUp, pickup: group)
        let others = [
            Plain(number: 2, state: .cancelled, pickup: group),
            Plain(number: 3, state: .delivered)
        ]
        if case .complete = evaluate(stepped, .pickedUp, others) {} else { Issue.record("Expected complete") }
    }

    @Test("Grouped members are reported lowest number first, ahead of unrelated orders")
    func groupedFirst() {
        let group = UUID()
        let stepped = Plain(number: 2, state: .delivered, dropOff: group)
        let others = [
            Plain(number: 5, state: .pickedUp, dropOff: group),
            Plain(number: 3, state: .accepted, dropOff: group),
            Plain(number: 4, state: .pickedUp)
        ]
        let result = evaluate(stepped, .delivered, others)
        guard case .groupedDeliveriesRemain = result else { Issue.record("Expected the group"); return }
        #expect(numbers(result) == [3, 5])
    }
}
