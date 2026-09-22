import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// A presenter that records what it was asked to draw.
///
/// It answers the way ActivityKit answers: a list of live activities, a handle
/// per request, nothing left behind once ended. So the reconciliation under test
/// is the shipping one rather than a version written for a test. What it
/// does not do is draw, which is the only part of the feature a unit test could
/// not reach anyway.
@MainActor
final class RecordingShiftActivityPresenter: ShiftActivityPresenting {
    /// What the coordinator asked for, in order.
    enum Event: Equatable {
        case started(UUID)
        case updated(String)
        case ended(String)
    }

    var isAvailable = true

    /// Set to refuse the next request, the way a system that has run out of
    /// activity slots would.
    var refusesToStart = false

    private(set) var events: [Event] = []
    private(set) var live: [ShiftActivityHandle] = []
    private(set) var contents: [String: ShiftActivityAttributes.ContentState] = [:]
    private var nextID = 0

    /// The snapshot currently on the one live activity, or `nil` when there is
    /// not exactly one.
    var onlyContent: ShiftActivityAttributes.ContentState? {
        guard live.count == 1, let handle = live.first else { return nil }
        return contents[handle.id]
    }

    var startCount: Int { events.filter { if case .started = $0 { true } else { false } }.count }
    var updateCount: Int { events.filter { if case .updated = $0 { true } else { false } }.count }
    var endCount: Int { events.filter { if case .ended = $0 { true } else { false } }.count }

    /// Puts an activity in place that this process did not request, which is
    /// what a relaunch during a shift finds.
    @discardableResult
    func seed(shiftID: UUID) -> ShiftActivityHandle {
        nextID += 1
        let handle = ShiftActivityHandle(id: "seeded-\(nextID)", shiftID: shiftID)
        live.append(handle)
        return handle
    }

    func activities() -> [ShiftActivityHandle] { live }

    func start(
        shiftID: UUID,
        content: ShiftActivityAttributes.ContentState
    ) -> ShiftActivityHandle? {
        guard !refusesToStart else { return nil }
        nextID += 1
        let handle = ShiftActivityHandle(id: "activity-\(nextID)", shiftID: shiftID)
        live.append(handle)
        contents[handle.id] = content
        events.append(.started(shiftID))
        return handle
    }

    func update(_ handle: ShiftActivityHandle, content: ShiftActivityAttributes.ContentState) {
        guard live.contains(handle) else { return }
        contents[handle.id] = content
        events.append(.updated(handle.id))
    }

    func end(_ handle: ShiftActivityHandle) {
        live.removeAll { $0 == handle }
        contents[handle.id] = nil
        events.append(.ended(handle.id))
    }
}

/// Keeping the shift's Live Activity in step with the store.
///
/// Every case here is about the same claim: **the store is what is true, and the
/// surface follows it**. A shift that starts gets one activity; pausing and
/// resuming change what it says without replacing it; ending removes it; a new
/// process adopts the one it finds rather than adding a second; and a card left
/// behind by a shift that is gone is cleaned up rather than left claiming work.
@MainActor
@Suite("Shift Live Activity synchronisation")
struct ShiftLiveActivityServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A coordinator whose clock the test drives.
    private func makeService(
        context: ModelContext,
        presenter: RecordingShiftActivityPresenter,
        clock: Clock
    ) -> ShiftLiveActivityService {
        ShiftLiveActivityService(
            context: context,
            presenter: presenter,
            now: { clock.now },
            locale: { Locale(identifier: "en_US") }
        )
    }

    /// A settable clock, so a cadence can be tested without waiting for one.
    @MainActor
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    @discardableResult
    private func record(
        _ count: Int,
        from index: Int,
        for shift: Shift,
        in session: UUID,
        context: ModelContext
    ) throws -> [RouteSample] {
        let samples = (index..<(index + count)).map { step in
            RouteSample(
                shift: shift,
                sample: SyntheticRoute.sample(at: at(Double(step)), northMetres: Double(step) * 40),
                captureSessionID: session
            )
        }
        for sample in samples { context.insert(sample) }
        try context.save()
        return samples
    }

    // MARK: Running, paused, resumed, ended

    @Test("A shift that starts gets exactly one activity")
    func startingAShiftStartsOneActivity() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        service.reconcile()
        #expect(presenter.startCount == 0, "Nothing is running, so there is nothing to show")

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()

        #expect(presenter.startCount == 1)
        #expect(presenter.live.count == 1)
        #expect(presenter.onlyContent?.isPaused == false)
    }

    @Test("Reconciling again with nothing changed hands over nothing")
    func reconcilingWithNothingChangedHandsOverNothing() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()

        clock.now = at(120)
        service.reconcile()
        clock.now = at(600)
        service.reconcile()

        #expect(presenter.startCount == 1)
        #expect(
            presenter.updateCount == 0,
            "The working clock counts itself, so time passing is not a reason to redraw"
        )
    }

    @Test("Running to paused to resumed to ended is one activity, then none")
    func followsTheShiftThroughItsWholeLife() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shifts = ShiftService(context: context)

        try shifts.startShift(at: start)
        service.reconcile()
        let started = presenter.live.first
        #expect(presenter.onlyContent?.controls == [.startDelivery, .park, .pause, .end])

        clock.now = at(600)
        try shifts.pauseActiveShift(at: at(600))
        service.reconcile()
        #expect(presenter.onlyContent?.isPaused == true)
        #expect(presenter.onlyContent?.controls == [.resume, .end])
        #expect(presenter.onlyContent?.workingDuration == 600)

        clock.now = at(1_200)
        try shifts.resumeActiveShift(at: at(1_200))
        service.reconcile()
        #expect(presenter.onlyContent?.isPaused == false)
        #expect(presenter.onlyContent?.controls == [.startDelivery, .park, .pause, .end])

        clock.now = at(1_800)
        try shifts.endActiveShift(at: at(1_800))
        service.reconcile()

        #expect(presenter.live.isEmpty, "A finished shift leaves no card behind")
        #expect(presenter.startCount == 1, "One activity for one shift, never replaced")
        #expect(presenter.updateCount == 2, "Pausing and resuming, and nothing else")
        #expect(presenter.endCount == 1)
        #expect(presenter.live.first(where: { $0 == started }) == nil)
    }

    @Test("A paused shift's working figure stops moving on the surface too")
    func holdsTheWorkingFigureStillWhilePaused() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shifts = ShiftService(context: context)

        try shifts.startShift(at: start)
        service.reconcile()
        clock.now = at(600)
        try shifts.pauseActiveShift(at: at(600))
        service.reconcile()
        let atPause = presenter.onlyContent

        clock.now = at(4_200)
        service.reconcile()

        #expect(presenter.onlyContent?.workingDuration == atPause?.workingDuration)
        #expect(presenter.updateCount == 1, "An hour on a break is not an hour of redraws")
    }

    @Test("Parking swaps the card's control and says so, without pausing anything")
    func swapsTheParkedControlOnTheCard() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shifts = ShiftService(context: context)

        try shifts.startShift(at: start)
        service.reconcile()
        #expect(presenter.onlyContent?.controls.contains(.park) == true)
        #expect(presenter.onlyContent?.routeSuspendedNotice == nil)

        clock.now = at(600)
        try shifts.parkActiveShift(at: at(600))
        service.reconcile()
        #expect(presenter.onlyContent?.controls.first == .resumeDriving)
        #expect(presenter.onlyContent?.controls.contains(.park) == false)
        #expect(presenter.onlyContent?.routeSuspendedNotice != nil)
        #expect(presenter.onlyContent?.isPaused == false, "The card must not read as paused")
        #expect(presenter.onlyContent?.workingDuration == 600)

        clock.now = at(1_200)
        service.reconcile()
        // Working time keeps counting through a parked stretch, and the system
        // draws it from the shift's own start: parking pushes nothing and holds
        // nothing still, unlike a pause.
        #expect(presenter.onlyContent?.workingTimerAnchor == start)
        #expect(presenter.updateCount == 1, "Ten quiet minutes parked is not ten minutes of redraws")

        clock.now = at(1_800)
        try shifts.resumeDrivingOnActiveShift(at: at(1_800))
        service.reconcile()
        #expect(presenter.onlyContent?.controls.contains(.park) == true)
        #expect(presenter.onlyContent?.routeSuspendedNotice == nil)
        #expect(presenter.startCount == 1, "One card throughout")
        #expect(presenter.endCount == 0)
    }

    // MARK: Deliveries

    @Test("A delivery starting and advancing changes what the surface offers")
    func followsTheDeliveryLifecycle() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let deliveries = DeliveryService(context: context)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()

        clock.now = at(60)
        let delivery = try deliveries.startDelivery(at: at(60))
        service.reconcile()
        #expect(presenter.onlyContent?.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(presenter.onlyContent?.activeDeliveryCount == 1)

        clock.now = at(120)
        try deliveries.markArrivedAtPickup(delivery, at: at(120))
        service.reconcile()
        #expect(presenter.onlyContent?.controls == [.deliveryStep(.pickUp), .startDelivery, .park])
        #expect(presenter.onlyContent?.deliveryStatus == "Waiting at the pickup")

        clock.now = at(180)
        try deliveries.markPickedUp(delivery, at: at(180))
        try deliveries.markDelivered(delivery, at: at(240))
        service.reconcile()
        #expect(presenter.onlyContent?.controls == [.startDelivery, .park, .pause, .end])
        #expect(presenter.onlyContent?.completedDeliveryCount == 1)
    }

    @Test("A second delivery removes the step control rather than choosing one")
    func withdrawsTheStepControlWhenDeliveriesStack() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let deliveries = DeliveryService(context: context)

        try ShiftService(context: context).startShift(at: start)
        _ = try deliveries.startDelivery(at: at(60))
        service.reconcile()
        #expect(presenter.onlyContent?.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])

        clock.now = at(120)
        _ = try deliveries.startDelivery(at: at(120))
        service.reconcile()

        // Start Delivery survives, because it names no existing order and
        // therefore cannot be aimed at the wrong one.
        #expect(presenter.onlyContent?.controls == [.startDelivery, .park])
        #expect(presenter.onlyContent?.deliveryStatus == nil)
        #expect(presenter.onlyContent?.controlNotice != nil)
    }

    @Test("A delivery started from the card moves the count on the card at once")
    func startingADeliveryMovesTheCountImmediately() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let deliveries = DeliveryService(context: context)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()
        #expect(presenter.onlyContent?.activeDeliveryCount == 0)
        let afterStart = presenter.updateCount

        clock.now = at(60)
        _ = try deliveries.startDelivery(at: at(60))
        service.reconcile()
        #expect(presenter.onlyContent?.activeDeliveryCount == 1)
        #expect(presenter.updateCount == afterStart + 1, "A count that moved is material, so it does not wait")

        clock.now = at(90)
        _ = try deliveries.startDelivery(at: at(90))
        service.reconcile()
        #expect(presenter.onlyContent?.activeDeliveryCount == 2, "Stacked, and the card says two")
        #expect(presenter.updateCount == afterStart + 2)
    }

    @Test("Reconciling never starts a delivery of its own")
    func reconcilingStartsNoDelivery() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        try ShiftService(context: context).startShift(at: start)
        _ = try DeliveryService(context: context).startDelivery(at: at(60))

        // The card is reconciled on every lifecycle transition, on returning to
        // the foreground and on relaunch. A surface that wrote a record while
        // catching up would turn one press into several deliveries.
        for offset in stride(from: 120, through: 600, by: 60) {
            clock.now = at(Double(offset))
            service.reconcile()
        }

        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
        #expect(presenter.onlyContent?.activeDeliveryCount == 1)
    }

    // MARK: Mileage cadence

    @Test("A route figure that moved waits for the cadence rather than redrawing at once")
    func throttlesRouteOnlyUpdates() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shift = try ShiftService(context: context).startShift(at: start)
        let session = UUID()

        service.reconcile()
        #expect(presenter.onlyContent?.mileageStatement == "No route recorded")

        // Far enough to move the figure, but only a few seconds later.
        clock.now = at(20)
        try record(20, from: 0, for: shift, in: session, context: context)
        service.reconcile()
        #expect(presenter.updateCount == 0, "A tenth of a mile is not worth a redraw on a locked screen")

        clock.now = start.addingTimeInterval(ShiftActivityUpdatePolicy.routeInterval)
        try record(20, from: 20, for: shift, in: session, context: context)
        service.reconcile()
        #expect(presenter.updateCount == 1)
        #expect(presenter.onlyContent?.mileageStatement.contains("recorded") == true)
    }

    @Test("A material change is handed over at once, whatever the route cadence says")
    func doesNotThrottleMaterialChanges() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()

        // One second later, which is well inside the route cadence.
        clock.now = at(1)
        try ShiftService(context: context).pauseActiveShift(at: at(1))
        service.reconcile()

        #expect(presenter.updateCount == 1)
        #expect(presenter.onlyContent?.isPaused == true)
    }

    @Test("The route is extended rather than measured again, and matches the whole-route figure")
    func extendsTheRouteIncrementally() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shift = try ShiftService(context: context).startShift(at: start)
        let session = UUID()

        try record(30, from: 0, for: shift, in: session, context: context)
        service.reconcile()

        clock.now = at(120)
        try record(30, from: 30, for: shift, in: session, context: context)
        service.reconcile()

        let whole = RouteQuality(shift.recordedDistance()).mileageStatement(locale: Locale(identifier: "en_US"))
        #expect(presenter.onlyContent?.mileageStatement == whole)
    }

    @Test("A pause shows on the surface as a partial route, because that is what it makes")
    func reportsThePartialRouteAPauseProduces() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)

        try record(20, from: 0, for: shift, in: UUID(), context: context)
        service.reconcile()
        #expect(presenter.onlyContent?.partialRouteMarker == nil)

        clock.now = at(600)
        try shifts.pauseActiveShift(at: at(600))
        try shifts.resumeActiveShift(at: at(900))
        // Resuming mints a new capture session, so nothing is measured across
        // the break.
        try record(20, from: 900, for: shift, in: UUID(), context: context)
        clock.now = at(920)
        service.reconcile()

        #expect(presenter.onlyContent?.partialRouteMarker == "partial route")
    }

    // MARK: Relaunch, adoption and stale cleanup

    @Test("A new process adopts the activity its shift already has")
    func adoptsAnExistingActivityOnRelaunch() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let shift = try ShiftService(context: context).startShift(at: start)

        // What a relaunch mid-shift finds: an activity nobody in this process
        // requested, describing the shift the store still holds.
        let seeded = presenter.seed(shiftID: shift.id)

        let service = makeService(context: context, presenter: presenter, clock: clock)
        service.reconcile()

        #expect(presenter.startCount == 0, "A second card for one shift is the failure this prevents")
        #expect(presenter.live == [seeded])
        #expect(presenter.updateCount == 1, "The adopted card is brought up to date at once")
    }

    @Test("An activity left behind by a shift that has ended is cleaned up on relaunch")
    func endsAStaleActivityWhenNoShiftIsRunning() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        presenter.seed(shiftID: UUID())

        let service = makeService(context: context, presenter: presenter, clock: clock)
        service.reconcile()

        #expect(presenter.live.isEmpty)
        #expect(presenter.endCount == 1)
        #expect(presenter.startCount == 0)
    }

    @Test("An activity describing another shift is ended and replaced, not updated")
    func replacesAnActivityForADifferentShift() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        presenter.seed(shiftID: UUID())
        let shift = try ShiftService(context: context).startShift(at: start)

        let service = makeService(context: context, presenter: presenter, clock: clock)
        service.reconcile()

        #expect(presenter.endCount == 1)
        #expect(presenter.startCount == 1)
        #expect(presenter.live.count == 1)
        #expect(presenter.live.first?.shiftID == shift.id)
    }

    @Test("An activity the driver dismissed is started again rather than updated into nothing")
    func startsAgainAfterTheCardIsDismissed() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()
        let first = try #require(presenter.live.first)

        // The driver swiped it away. ActivityKit stops listing it, and nothing
        // tells the app.
        presenter.end(first)
        clock.now = at(60)
        service.reconcile()

        #expect(presenter.startCount == 2)
        #expect(presenter.live.count == 1)
    }

    // MARK: Refusals and failures

    @Test("Live Activities turned off leaves the app recording exactly as it did")
    func doesNothingWhenActivitiesAreUnavailable() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        presenter.isAvailable = false
        let service = makeService(context: context, presenter: presenter, clock: Clock(start))

        let shift = try ShiftService(context: context).startShift(at: start)
        service.reconcile()

        #expect(presenter.events.isEmpty)
        #expect(shift.isActive, "The shift is recorded whether or not anything can draw it")
    }

    @Test("A system that refuses the request leaves nothing half-started")
    func survivesARefusedRequest() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        presenter.refusesToStart = true
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)

        try ShiftService(context: context).startShift(at: start)
        service.reconcile()
        #expect(presenter.live.isEmpty)

        // The next pass tries again, which is the whole recovery story.
        presenter.refusesToStart = false
        clock.now = at(60)
        service.reconcile()
        #expect(presenter.live.count == 1)
    }

    @Test("Deleting the shift the activity described ends it")
    func endsTheActivityWhenTheShiftIsDeleted() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let clock = Clock(start)
        let service = makeService(context: context, presenter: presenter, clock: clock)
        let shifts = ShiftService(context: context)

        let shift = try shifts.startShift(at: start)
        service.reconcile()
        #expect(presenter.live.count == 1)

        try shifts.endActiveShift(at: at(600))
        try shifts.deleteCompletedShift(shift)
        clock.now = at(601)
        service.reconcile()

        #expect(presenter.live.isEmpty)
    }
}

/// The cadence rule on its own.
@MainActor
@Suite("Shift Live Activity update policy")
struct ShiftActivityUpdatePolicyTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func state(
        isPaused: Bool = false,
        parkedNotice: String? = nil,
        workingDuration: TimeInterval = 600,
        asOf: TimeInterval = 600,
        mileage: String = "1.0 mi recorded",
        partial: String? = nil,
        active: Int = 0,
        completed: Int = 0,
        status: String? = nil,
        timers: [ShiftActivityDeliveryTimer] = [],
        controls: [ShiftActivityControl] = [.pause, .end]
    ) -> ShiftActivityAttributes.ContentState {
        ShiftActivityAttributes.ContentState(
            isPaused: isPaused,
            routeSuspendedNotice: parkedNotice,
            workingDuration: workingDuration,
            asOf: start.addingTimeInterval(asOf),
            mileageStatement: mileage,
            partialRouteMarker: partial,
            activeDeliveryCount: active,
            completedDeliveryCount: completed,
            deliveryStatus: status,
            activeDeliveryTimers: timers,
            controls: controls
        )
    }

    @Test("The first snapshot is always handed over")
    func firstSnapshotIsMaterial() {
        #expect(ShiftActivityUpdatePolicy.change(from: nil, to: state()) == .material)
    }

    @Test("Time passing is not a change")
    func timePassingIsNotAChange() {
        let earlier = state(workingDuration: 600, asOf: 600)
        let later = state(workingDuration: 3_600, asOf: 3_600)

        #expect(
            ShiftActivityUpdatePolicy.change(from: earlier, to: later) == .none,
            "The anchor has not moved, so the system is already drawing the right clock"
        )
    }

    @Test("Pausing, a delivery and a control change are all material")
    func materialChanges() {
        let base = state()

        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(isPaused: true)) == .material)
        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(active: 1)) == .material)
        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(completed: 1)) == .material)
        #expect(
            ShiftActivityUpdatePolicy.change(from: base, to: state(status: "Waiting at the pickup")) == .material
        )
        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(controls: [])) == .material)
    }

    /// The state whose whole job is to be seen while the driver is away from the
    /// vehicle. It reaches the card at once rather than on the route's throttle,
    /// and so does the control that leaves it.
    @Test("Parking and driving again are material, both in the notice and in the control")
    func parkingIsMaterial() {
        let driving = state(controls: [.startDelivery, .park, .pause, .end])
        let parked = state(
            parkedNotice: "Parked, route not recording",
            controls: [.resumeDriving, .startDelivery, .pause, .end]
        )

        #expect(ShiftActivityUpdatePolicy.change(from: driving, to: parked) == .material)
        #expect(ShiftActivityUpdatePolicy.change(from: parked, to: driving) == .material)
        #expect(
            ShiftActivityUpdatePolicy.change(
                from: driving,
                to: state(parkedNotice: "Parked, route not recording", controls: driving.controls)
            ) == .material,
            "The notice alone is enough, without any control moving"
        )
        #expect(
            ShiftActivityUpdatePolicy.change(from: parked, to: parked) == .none,
            "A parked card that has not moved is not redrawn"
        )
    }

    /// The one case every count on the card hides: an order finishing at the
    /// moment another is accepted. Nothing else moves, and without the timers
    /// in the comparison the surface would keep counting a delivery that had
    /// already been delivered.
    @Test("One delivery replacing another is material even though every count is unchanged")
    func swappingTheCountedDeliveryIsMaterial() {
        let first = ShiftActivityDeliveryTimer(title: "Delivery 1", startedAt: start)
        let second = ShiftActivityDeliveryTimer(title: "Delivery 2", startedAt: start.addingTimeInterval(900))

        let before = state(active: 1, status: "Heading to the pickup", timers: [first])
        let after = state(active: 1, status: "Heading to the pickup", timers: [second])

        #expect(before.activeDeliveryCount == after.activeDeliveryCount)
        #expect(before.completedDeliveryCount == after.completedDeliveryCount)
        #expect(before.deliveryStatus == after.deliveryStatus)
        #expect(before.controls == after.controls)
        #expect(ShiftActivityUpdatePolicy.change(from: before, to: after) == .material)
    }

    @Test("A delivery timer that has not moved is not a change, however late the snapshot is")
    func anUnchangedDeliveryTimerIsNotAChange() {
        let timer = ShiftActivityDeliveryTimer(title: "Delivery 1", startedAt: start)

        let earlier = state(workingDuration: 600, asOf: 600, active: 1, timers: [timer])
        let later = state(workingDuration: 7_200, asOf: 7_200, active: 1, timers: [timer])

        #expect(
            ShiftActivityUpdatePolicy.change(from: earlier, to: later) == .none,
            "The anchor is the whole of what the system needs, so an hour later is still the same card"
        )
    }

    @Test("Only the route moving is a route change")
    func routeChanges() {
        let base = state()

        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(mileage: "1.1 mi recorded")) == .route)
        #expect(ShiftActivityUpdatePolicy.change(from: base, to: state(partial: "partial route")) == .route)
    }

    @Test("A route change waits for the cadence, and a material one never does")
    func pushingFollowsTheCadence() {
        let lastPush = start

        #expect(ShiftActivityUpdatePolicy.shouldPush(.none, lastPushedAt: nil, now: start) == false)
        #expect(ShiftActivityUpdatePolicy.shouldPush(.material, lastPushedAt: lastPush, now: start) == true)
        #expect(ShiftActivityUpdatePolicy.shouldPush(.route, lastPushedAt: nil, now: start) == true)
        #expect(
            ShiftActivityUpdatePolicy.shouldPush(
                .route,
                lastPushedAt: lastPush,
                now: start.addingTimeInterval(ShiftActivityUpdatePolicy.routeInterval - 1)
            ) == false
        )
        #expect(
            ShiftActivityUpdatePolicy.shouldPush(
                .route,
                lastPushedAt: lastPush,
                now: start.addingTimeInterval(ShiftActivityUpdatePolicy.routeInterval)
            ) == true
        )
    }

    @Test("A clock that moved backwards cannot hold the figure still")
    func aBackwardsClockDoesNotLatch() {
        #expect(
            ShiftActivityUpdatePolicy.shouldPush(
                .route,
                lastPushedAt: start,
                now: start.addingTimeInterval(-3_600)
            ) == true
        )
    }
}
