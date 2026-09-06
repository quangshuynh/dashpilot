import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a shift survives: being interrupted, being backgrounded, being
/// terminated, being changed by a voice action while the screen is open, and
/// running long enough to cross a midnight.
///
/// Every other suite here tests one layer against synthetic input. This one
/// tests the joins between them, because that is where a phone in a cradle
/// actually breaks things: the store, route capture, the lifecycle services and
/// the App Intents all touch the same shift, and each of them is reached by a
/// different interruption.
///
/// Nothing here simulates a screen. What a view does on a scene-phase change is
/// a single call into ``LocationTrackingService`` (`enterBackground()`,
/// `enterForeground()`, `synchronize()`), so the sequences below are the
/// sequences ``RootView`` produces, without a UI test's ability to hide a
/// missing call behind a redraw.
@MainActor
@Suite("Real-world recovery")
struct RealWorldRecoveryTests {
    private let shiftStart = Date(timeIntervalSince1970: 1_756_000_000)

    // MARK: Harness

    /// A settable clock, so staleness is decided by the test rather than by how
    /// long the test took to run.
    @MainActor
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    /// The app's wiring with Core Location replaced: one container, one main
    /// context, and every service the process builds over it.
    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let provider: StubLocationTrackingProvider
        let tracking: LocationTrackingService
        let clock: Clock

        var shifts: ShiftService { ShiftService(context: context) }
        var deliveries: DeliveryService { DeliveryService(context: context) }
        var intents: IntentLifecycleService { IntentLifecycleService(context: context) }

        /// Reads through a context the services never used, so only saved rows
        /// are visible, which is what a relaunch would see.
        func storedSamples() throws -> [RouteSample] {
            try ModelContext(container).fetch(
                FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)])
            )
        }
    }

    private func makeHarness(
        container: ModelContainer? = nil,
        saveBatchSize: Int = 1,
        at date: Date? = nil
    ) throws -> Harness {
        let container = try container ?? ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(
                servicesEnabled: true,
                status: .authorizedWhenInUse,
                accuracy: .full
            )
        )
        let clock = Clock(date ?? shiftStart)

        return Harness(
            container: container,
            context: context,
            provider: provider,
            tracking: LocationTrackingService(
                context: context,
                authorization: authorization,
                provider: provider,
                saveBatchSize: saveBatchSize,
                now: { clock.date }
            ),
            clock: clock
        )
    }

    /// Emits one position as Core Location would, with the clock moved to it so
    /// the staleness rule sees a fresh fix.
    private func emit(
        _ harness: Harness,
        secondsAfterStart: TimeInterval,
        northMetres: Double
    ) {
        harness.clock.date = shiftStart.addingTimeInterval(secondsAfterStart)
        harness.provider.emit(
            SyntheticRoute.sample(
                at: shiftStart.addingTimeInterval(secondsAfterStart),
                northMetres: northMetres
            )
        )
    }

    /// A store location on disk, deleted when the test finishes. The only way to
    /// demonstrate what survives termination: an in-memory store goes with the
    /// container that owns it.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotRecoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Relaunch with work still in progress

    @Test("A running shift with two deliveries on it reopens exactly as it was left")
    func stackedWorkSurvivesTermination() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let firstAccepted = shiftStart.addingTimeInterval(300)
        let secondAccepted = shiftStart.addingTimeInterval(600)

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try ShiftService(context: context).startShift(at: shiftStart)
            let deliveries = DeliveryService(context: context)
            let first = try deliveries.startDelivery(at: firstAccepted)
            try deliveries.markArrivedAtPickup(first, at: firstAccepted.addingTimeInterval(120))
            try deliveries.startDelivery(at: secondAccepted)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try ShiftService(context: context).activeShift())
        #expect(shift.startedAt == shiftStart)

        // Both are still running, in the order they were accepted, each holding
        // its own state. Nothing was closed, cancelled or merged to tidy up.
        let running = try DeliveryService(context: context).activeDeliveries(for: shift)
        #expect(running.count == 2)
        #expect(running.map(\.acceptedAt) == [firstAccepted, secondAccepted])
        #expect(running.map(\.state) == [.arrivedAtPickup, .accepted])

        // And the rule that protects them is a store rule, so it survives too.
        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 2)) {
            try ShiftService(context: context).endActiveShift(at: shiftStart.addingTimeInterval(900))
        }
    }

    @Test("Capture resumed after a relaunch continues the route without measuring across the break")
    func relaunchedCaptureDoesNotBridgeTheGap() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let firstRun = try makeHarness(container: try ModelContainerFactory.makeContainer(at: storeURL))
        try firstRun.shifts.startShift(at: shiftStart)
        firstRun.tracking.synchronize()
        emit(firstRun, secondsAfterStart: 10, northMetres: 0)
        emit(firstRun, secondsAfterStart: 20, northMetres: 100)

        // Terminated here: no `enterBackground`, no shift end, nothing tidied.
        let firstSession = try #require(try firstRun.storedSamples().first?.captureSessionID)

        let secondRun = try makeHarness(
            container: try ModelContainerFactory.makeContainer(at: storeURL),
            at: shiftStart.addingTimeInterval(1800)
        )
        // The one call `RootView.task` makes. The shift is still unfinished, so
        // capture resumes on it rather than a replacement being created.
        secondRun.tracking.synchronize()
        #expect(secondRun.tracking.state == .tracking)
        #expect(try secondRun.shifts.activeShift()?.startedAt == shiftStart)

        emit(secondRun, secondsAfterStart: 1810, northMetres: 5100)
        emit(secondRun, secondsAfterStart: 1820, northMetres: 5200)

        let stored = try secondRun.storedSamples()
        #expect(stored.count == 4)
        let sessions = stored.map(\.captureSessionID)
        #expect(sessions[0] == firstSession && sessions[1] == firstSession)
        #expect(sessions[2] == sessions[3])
        #expect(
            sessions[2] != firstSession,
            "A new process is a new stretch of capture; nothing may resume the old one"
        )

        // The five kilometres the driver covered while the app was not running
        // are left out rather than drawn as a straight line.
        let distance = RouteMileageCalculator().distance(of: stored.map(\.routePoint))
        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount == 1)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 200))
        #expect(distance.isPartial)
    }

    // MARK: Leaving and returning to the foreground

    @Test("Backgrounding writes what capture was holding before iOS can suspend the app")
    func backgroundingFlushesPendingSamples() throws {
        let harness = try makeHarness(saveBatchSize: 10)
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 1...3 {
            emit(harness, secondsAfterStart: TimeInterval(step * 5), northMetres: Double(step) * 50)
        }
        #expect(try harness.storedSamples().isEmpty, "Below the batch size, nothing has been written yet")

        harness.tracking.enterBackground()

        #expect(try harness.storedSamples().count == 3)
        #expect(harness.tracking.state == .pausedInBackground)
        #expect(!harness.provider.isUpdating)
    }

    @Test("A trip to another app and back leaves a gap rather than a straight line")
    func returningFromBackgroundStartsANewStretch() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        emit(harness, secondsAfterStart: 10, northMetres: 0)
        emit(harness, secondsAfterStart: 20, northMetres: 100)

        harness.tracking.enterBackground()
        harness.tracking.enterForeground()
        #expect(harness.tracking.state == .tracking)

        emit(harness, secondsAfterStart: 620, northMetres: 4100)
        emit(harness, secondsAfterStart: 630, northMetres: 4200)

        let stored = try harness.storedSamples()
        #expect(Set(stored.map(\.captureSessionID)).count == 2)

        let distance = RouteMileageCalculator().distance(of: stored.map(\.routePoint))
        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount == 1)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 200))
    }

    @Test("An interruption the driver never left the app for does not fragment the route")
    func reconcilingWhileTrackingKeepsOneStretch() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        emit(harness, secondsAfterStart: 10, northMetres: 0)

        // A call banner, the notification shade, an alert: the scene goes
        // inactive and comes back without ever reaching `.background`, and the
        // screen reconciles rather than pausing. Doing so must not restart
        // capture, because a restart is a recorded break in the route.
        harness.tracking.synchronize()
        harness.tracking.synchronize()

        emit(harness, secondsAfterStart: 20, northMetres: 100)
        emit(harness, secondsAfterStart: 30, northMetres: 200)

        #expect(harness.provider.startCount == 1)
        #expect(harness.provider.stopCount == 0)

        let stored = try harness.storedSamples()
        #expect(Set(stored.map(\.captureSessionID)).count == 1)

        let distance = RouteMileageCalculator().distance(of: stored.map(\.routePoint))
        #expect(distance.segmentCount == 1)
        #expect(distance.gapCount == 0)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 200))
    }

    @Test("Capture that stopped because location failed resumes on the next return to the foreground")
    func captureRecoversFromALocationFailure() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        emit(harness, secondsAfterStart: 10, northMetres: 0)

        harness.provider.fail(.unavailable)
        #expect(harness.tracking.state == .unavailable(.locationFailed))
        #expect(!harness.provider.isUpdating)

        harness.tracking.enterBackground()
        harness.tracking.enterForeground()

        #expect(harness.tracking.state == .tracking)
        emit(harness, secondsAfterStart: 60, northMetres: 100)
        #expect(try harness.storedSamples().count == 2)
    }

    // MARK: A voice action and the screen, over one store

    @Test("A shift ended by an intent stops the capture the screen started")
    func anIntentEndingTheShiftStopsCapture() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        emit(harness, secondsAfterStart: 10, northMetres: 0)
        emit(harness, secondsAfterStart: 20, northMetres: 100)

        // Said at the kerb, with the app still on screen. The intent performs no
        // capture bookkeeping of its own.
        _ = try harness.intents.endShift(at: shiftStart.addingTimeInterval(30))

        // A fix already in flight when the shift closed. The store is the
        // authority, so it is refused rather than attached to a finished shift.
        emit(harness, secondsAfterStart: 40, northMetres: 200)

        #expect(try harness.storedSamples().count == 2)
        #expect(harness.tracking.state == .idle)
        #expect(!harness.provider.isUpdating)

        // And the screen's own reconcile, which arrives a moment later, agrees.
        harness.tracking.synchronize()
        #expect(harness.tracking.state == .idle)
    }

    @Test("A shift started by voice is captured from the moment the app is opened")
    func anIntentStartedShiftIsPickedUpOnReturn() throws {
        let harness = try makeHarness()

        // The phone is in a cradle with DashPilot not on screen.
        harness.tracking.enterBackground()
        _ = try harness.intents.startShift(at: shiftStart)
        #expect(harness.tracking.state == .idle, "Nothing may claim to be recording while backgrounded")

        harness.tracking.enterForeground()
        #expect(harness.tracking.state == .tracking)

        emit(harness, secondsAfterStart: 10, northMetres: 0)
        emit(harness, secondsAfterStart: 20, northMetres: 100)

        let stored = try harness.storedSamples()
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.shift?.startedAt == shiftStart })
    }

    @Test("A delivery started by voice is one the screen advances, and the other way round")
    func aVoiceStartedDeliveryIsTheSameRecordTheScreenAdvances() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)

        _ = try harness.intents.startDelivery(at: shiftStart.addingTimeInterval(60))

        let shift = try #require(try harness.shifts.activeShift())
        let started = try #require(shift.activeDeliveries.first)
        try harness.deliveries.markArrivedAtPickup(started, at: shiftStart.addingTimeInterval(300))

        // Back to the voice surface: still one delivery running, so the next
        // step is unambiguous and lands on the same record.
        let outcome = try harness.intents.recordDeliveryProgress(at: shiftStart.addingTimeInterval(420))

        #expect(shift.deliveries.count == 1)
        #expect(started.state == .pickedUp)
        #expect(outcome == .deliveryEventRecorded(number: 1, state: .pickedUp))
    }

    @Test("A second delivery makes the spoken step ambiguous, and the shift refuses to end")
    func stackedWorkRefusesBothTheSpokenStepAndTheShiftEnd() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        _ = try harness.intents.startDelivery(at: shiftStart.addingTimeInterval(60))
        _ = try harness.intents.startDelivery(at: shiftStart.addingTimeInterval(120))

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
            try harness.intents.recordDeliveryProgress(at: shiftStart.addingTimeInterval(180))
        }
        #expect(throws: IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 2))) {
            try harness.intents.endShift(at: shiftStart.addingTimeInterval(240))
        }

        // Nothing was written by either refusal.
        let shift = try #require(try harness.shifts.activeShift())
        #expect(shift.activeDeliveries.map(\.state) == [.accepted, .accepted])
    }

    // MARK: Long shifts

    @Test("A shift long enough to cross a midnight reports its whole length")
    func aShiftLongerThanADayIsNotWrappedToOne() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: shiftStart)
        let length: TimeInterval = 26 * 3600 + 300
        let ended = shiftStart.addingTimeInterval(length)
        try shifts.endActiveShift(at: ended)

        let recorded = try #require(shift.completedDuration)
        #expect(recorded == length)
        #expect(recorded > 24 * 3600, "Nothing wraps a shift into a single day")
        #expect(shift.elapsed(asOf: ended) == length)
        #expect(shift.completedWindow == shiftStart...ended)
    }

    @Test("A long shift keeps writing, so a termination costs less than one batch")
    func aLongShiftFlushesAsItGoes() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let harness = try makeHarness(
            container: try ModelContainerFactory.makeContainer(at: storeURL),
            saveBatchSize: 10
        )
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 1...25 {
            emit(harness, secondsAfterStart: TimeInterval(step * 5), northMetres: Double(step) * 50)
        }

        // Twenty written in two batches; five still in memory. Terminated here.
        #expect(try harness.storedSamples().count == 20)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let survived = try reopened.fetch(
            FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)])
        )
        #expect(survived.count == 20)
        #expect(survived.first?.timestamp == shiftStart.addingTimeInterval(5))
        #expect(survived.last?.timestamp == shiftStart.addingTimeInterval(100))
    }

    // MARK: Date rollover

    @Test("A day stops being today the moment the clock passes midnight")
    func aDayStopsBeingCurrentAfterMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        let lateEvening = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 23, minute: 30))
        )
        let afterMidnight = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 0, minute: 30))
        )
        let day = try #require(ReportingPeriod(unit: .day, containing: lateEvening, calendar: calendar))

        // The three facts a summary screen holding a stale "now" would get
        // wrong: what the period is called, whether it is the one the driver is
        // living in, and whether there is a later period to step to.
        #expect(day.title(asOf: lateEvening, calendar: calendar) == "Today")
        #expect(day.isCurrent(asOf: lateEvening))

        #expect(day.title(asOf: afterMidnight, calendar: calendar) == "Yesterday")
        #expect(!day.isCurrent(asOf: afterMidnight))

        let today = try #require(day.next(using: calendar))
        #expect(today.isCurrent(asOf: afterMidnight))
        #expect(today.title(asOf: afterMidnight, calendar: calendar) == "Today")
    }

    // MARK: The location manager the app actually ships

    @Test("The location manager never lets the system pause updates out from under a shift")
    func theLocationManagerDoesNotAllowAutomaticPausing() {
        // The platform default is `true` on a fresh process, which is what this
        // configuration exists to override. It is deliberately not asserted: the
        // value a newly created manager reports is not stable once anything else
        // in the process has touched Core Location, so an expectation on it fails
        // by test ordering rather than by anything about DashPilot.
        let manager = CLLocationManager()
        CoreLocationTrackingProvider.configure(manager)

        // The one that matters on a real shift. iOS pauses updates when it
        // decides a device has stopped moving, which on a shift is a driver
        // parked at a pickup, and it does not resume them by itself. DashPilot
        // has no background location mode to be woken by, so a pause would end
        // the route for the rest of the shift while the screen still said
        // tracking.
        #expect(!manager.pausesLocationUpdatesAutomatically)

        // The rest of the policy, asserted here because it is invisible from
        // outside the provider and each choice has a reason recorded on it.
        #expect(manager.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(manager.activityType == .automotiveNavigation)
        #expect(manager.distanceFilter == kCLDistanceFilterNone)
    }
}
