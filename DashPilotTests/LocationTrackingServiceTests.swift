import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Route capture")
struct LocationTrackingServiceTests {
    private let shiftStart = Date(timeIntervalSince1970: 1_756_000_000)

    /// A settable clock, so staleness and ordering are decided by the test
    /// rather than by how long the test took to run.
    @MainActor
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    /// One store, one main context, and both location layers stubbed — the same
    /// wiring the app builds, with Core Location replaced.
    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let provider: StubLocationTrackingProvider
        let authorizationProvider: StubLocationAuthorizationProvider
        let authorization: LocationAuthorizationService
        let tracking: LocationTrackingService
        let clock: Clock

        var shifts: ShiftService { ShiftService(context: context) }

        /// Reads the store through a context the service under test never used,
        /// so only saved rows are visible.
        func storedSamples() throws -> [RouteSample] {
            try ModelContext(container).fetch(
                FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)])
            )
        }

        /// Samples the service holds, saved or not.
        func pendingAndStoredSamples() throws -> [RouteSample] {
            try context.fetch(FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)]))
        }
    }

    private func makeHarness(
        status: LocationAuthorizationStatus = .authorizedWhenInUse,
        accuracy: LocationAccuracyAuthorization = .full,
        servicesEnabled: Bool = true,
        saveBatchSize: Int = 1,
        at date: Date? = nil
    ) throws -> Harness {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let provider = StubLocationTrackingProvider()
        let authorizationProvider = StubLocationAuthorizationProvider(
            servicesEnabled: servicesEnabled,
            status: status,
            accuracy: accuracy
        )
        let authorization = LocationAuthorizationService(provider: authorizationProvider)
        let clock = Clock(date ?? shiftStart.addingTimeInterval(60))

        return Harness(
            container: container,
            context: context,
            provider: provider,
            authorizationProvider: authorizationProvider,
            authorization: authorization,
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

    private func sample(_ harness: Harness, secondsAfterStart: TimeInterval, northMetres: Double = 0, accuracy: Double = 8) -> LocationSample {
        harness.clock.date = shiftStart.addingTimeInterval(secondsAfterStart)
        return SyntheticRoute.sample(
            at: shiftStart.addingTimeInterval(secondsAfterStart),
            northMetres: northMetres,
            horizontalAccuracy: accuracy
        )
    }

    // MARK: Capturing during a shift

    @Test("A valid sample during a running shift is retained and attached to that shift")
    func retainsAValidSample() throws {
        let harness = try makeHarness()
        let shift = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.isUpdating)

        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        let stored = try harness.storedSamples()
        #expect(stored.count == 1)
        #expect(stored.first?.shift?.id == shift.id)
        #expect(stored.first?.timestamp == shiftStart.addingTimeInterval(10))
        #expect(shift.routeSamples.count == 1)
    }

    @Test("A run of moving samples is retained in order")
    func retainsConsecutiveMovement() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 1...5 {
            harness.provider.emit(
                sample(harness, secondsAfterStart: TimeInterval(step), northMetres: Double(step) * 20)
            )
        }

        let stored = try harness.storedSamples()
        #expect(stored.count == 5)
        #expect(stored.map(\.timestamp) == (1...5).map { shiftStart.addingTimeInterval(TimeInterval($0)) })
    }

    @Test("Capture only reports itself as running when it really is")
    func stateIsIdleWithoutAShift() throws {
        let harness = try makeHarness()

        harness.tracking.synchronize()

        #expect(harness.tracking.state == .idle)
        #expect(!harness.provider.isUpdating)
        #expect(harness.provider.startCount == 0)
    }

    // MARK: The invariant

    @Test("Nothing is retained when no shift is running")
    func retainsNothingWithoutAShift() throws {
        let harness = try makeHarness()
        harness.tracking.synchronize()

        // Delivered as if the platform had produced a fix anyway.
        harness.provider.emitWhileStopped(sample(harness, secondsAfterStart: 10))

        #expect(try harness.pendingAndStoredSamples().isEmpty)
        #expect(harness.tracking.state == .idle)
    }

    @Test("Nothing is retained after the shift has been ended")
    func retainsNothingAfterTheShiftEnds() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(20))
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .idle)
        #expect(!harness.provider.isUpdating)

        harness.provider.emitWhileStopped(sample(harness, secondsAfterStart: 30, northMetres: 400))

        #expect(try harness.pendingAndStoredSamples().count == 1)
    }

    @Test("A sample arriving after the shift ended but before capture stopped is refused")
    func refusesSamplesAtTheEndBoundary() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        // The shift is ended without stopping capture first: the ordering the
        // app uses is deliberate, and this proves the pipeline does not depend
        // on it for correctness.
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(20))
        harness.provider.emit(sample(harness, secondsAfterStart: 30, northMetres: 400))

        #expect(try harness.pendingAndStoredSamples().isEmpty)
        #expect(harness.tracking.state == .idle)
        #expect(!harness.provider.isUpdating)
    }

    @Test("Samples are attached to the shift that was running when they arrived")
    func attachesSamplesToTheCorrectShift() throws {
        let harness = try makeHarness()

        let first = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(60))
        harness.tracking.synchronize()

        let second = try harness.shifts.startShift(at: shiftStart.addingTimeInterval(120))
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 130, northMetres: 900))
        harness.provider.emit(sample(harness, secondsAfterStart: 140, northMetres: 1_100))

        #expect(first.routeSamples.count == 1)
        #expect(second.routeSamples.count == 2)
        let stored = try harness.storedSamples()
        #expect(stored.count == 3)
        #expect(Set(stored.compactMap(\.shift?.id)) == [first.id, second.id])
    }

    // MARK: Filtering through the pipeline

    @Test("An unusable sample is dropped without ending capture")
    func rejectsBadSamplesWithoutStopping() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.clock.date = shiftStart.addingTimeInterval(10)
        harness.provider.emit(
            LocationSample(
                timestamp: shiftStart.addingTimeInterval(10),
                latitude: .nan,
                longitude: .nan,
                horizontalAccuracy: -1
            )
        )

        #expect(try harness.pendingAndStoredSamples().isEmpty)
        #expect(harness.tracking.state == .tracking, "One bad fix must not cost the rest of the route")

        harness.provider.emit(sample(harness, secondsAfterStart: 11))
        #expect(try harness.storedSamples().count == 1)
    }

    @Test("A repeated identical callback is not stored twice")
    func rejectsDuplicatesThroughThePipeline() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        let first = sample(harness, secondsAfterStart: 10)
        harness.provider.emit(first)
        harness.provider.emit(first)
        harness.clock.date = shiftStart.addingTimeInterval(11)
        var restamped = first
        restamped.timestamp = shiftStart.addingTimeInterval(11)
        harness.provider.emit(restamped)

        #expect(try harness.storedSamples().count == 1)
    }

    @Test("The cached fix Core Location delivers when updates start is not retained")
    func rejectsTheStaleFirstFix() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        // A position from two minutes ago, which is what a cold start hands back.
        harness.clock.date = shiftStart.addingTimeInterval(130)
        harness.provider.emit(SyntheticRoute.sample(at: shiftStart.addingTimeInterval(10)))

        #expect(try harness.pendingAndStoredSamples().isEmpty)
        #expect(harness.tracking.state == .tracking)
    }

    @Test("A jump no vehicle could make is not retained")
    func rejectsJumpsThroughThePipeline() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.provider.emit(sample(harness, secondsAfterStart: 12, northMetres: 20_000))
        harness.provider.emit(sample(harness, secondsAfterStart: 14, northMetres: 60))

        let stored = try harness.storedSamples()
        #expect(stored.count == 2)
        #expect(stored.map(\.timestamp) == [shiftStart.addingTimeInterval(10), shiftStart.addingTimeInterval(14)])
    }

    // MARK: Authorization

    @Test(
        "Capture does not start while location is unusable",
        arguments: [
            (LocationAuthorization(servicesEnabled: true, status: .notDetermined, accuracy: .full),
             RouteCaptureUnavailableReason.permissionRequired),
            (LocationAuthorization(servicesEnabled: true, status: .denied, accuracy: .full),
             .permissionDenied),
            (LocationAuthorization(servicesEnabled: true, status: .restricted, accuracy: .full),
             .permissionRestricted),
            (LocationAuthorization(servicesEnabled: false, status: .authorizedWhenInUse, accuracy: .full),
             .locationServicesOff),
            (LocationAuthorization(servicesEnabled: true, status: .unrecognised(rawValue: 99), accuracy: .full),
             .authorizationUnknown)
        ]
    )
    func refusesToStartWhileUnusable(
        authorization: LocationAuthorization,
        expected: RouteCaptureUnavailableReason
    ) throws {
        let harness = try makeHarness(
            status: authorization.status,
            accuracy: authorization.accuracy,
            servicesEnabled: authorization.servicesEnabled
        )
        try harness.shifts.startShift(at: shiftStart)

        harness.tracking.synchronize()

        #expect(harness.tracking.state == .unavailable(expected))
        #expect(!harness.provider.isUpdating)
        #expect(harness.provider.startCount == 0)
    }

    @Test("Reduced accuracy does not by itself prevent capture")
    func capturesUnderReducedAccuracy() throws {
        let harness = try makeHarness(accuracy: .reduced)
        try harness.shifts.startShift(at: shiftStart)

        harness.tracking.synchronize()

        // Whether a sample is kept is decided by the accuracy it reports, not by
        // the scope of the grant.
        #expect(harness.tracking.state == .tracking)
        harness.provider.emit(sample(harness, secondsAfterStart: 10, accuracy: 60))
        harness.provider.emit(sample(harness, secondsAfterStart: 20, northMetres: 300, accuracy: 4_000))

        #expect(try harness.storedSamples().count == 1)
    }

    @Test("Permission lost during a shift stops samples being kept immediately")
    func stopsAcceptingWhenAuthorizationIsRevoked() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        harness.authorizationProvider.update(status: .denied)
        harness.provider.emit(sample(harness, secondsAfterStart: 20, northMetres: 400))

        #expect(harness.tracking.state == .unavailable(.permissionDenied))
        #expect(!harness.provider.isUpdating)
        #expect(try harness.storedSamples().count == 1, "The route so far is kept; nothing is added")
    }

    @Test("Location Services being switched off during a shift stops capture")
    func stopsWhenLocationServicesAreSwitchedOff() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.authorizationProvider.update(servicesEnabled: false)
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .unavailable(.locationServicesOff))
        #expect(!harness.provider.isUpdating)
    }

    @Test("Losing location does not end the shift")
    func losingLocationLeavesTheShiftRunning() throws {
        let harness = try makeHarness()
        let shift = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.authorizationProvider.update(status: .denied)
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .unavailable(.permissionDenied))
        #expect(shift.isActive)
        #expect(try harness.shifts.activeShift()?.id == shift.id)
    }

    @Test("Capture resumes when permission is granted mid-shift")
    func resumesWhenPermissionIsGranted() throws {
        let harness = try makeHarness(status: .notDetermined)
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        #expect(harness.tracking.state == .unavailable(.permissionRequired))

        harness.authorizationProvider.update(status: .authorizedWhenInUse)
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.startCount == 1)
    }

    // MARK: Platform failures

    @Test("A position the device cannot determine right now does not stop capture")
    func toleratesTransientLocationFailures() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.provider.fail(.temporarilyUnavailable)

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.isUpdating)
    }

    @Test("A failure that will not resolve itself is surfaced")
    func surfacesPermanentLocationFailures() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.provider.fail(.unavailable)

        #expect(harness.tracking.state == .unavailable(.locationFailed))
        #expect(!harness.provider.isUpdating)
    }

    // MARK: Leaving and returning to the foreground

    @Test("A running capture session keeps running when the app leaves the foreground")
    func continuesCapturingInTheBackground() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.tracking.enterBackground()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.isUpdating)
        #expect(harness.provider.stopCount == 0, "Stopping and restarting would record a break that did not happen")
        #expect(harness.provider.allowsBackgroundUpdates)

        // And positions that arrive there are retained, against the same shift.
        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.provider.emit(sample(harness, secondsAfterStart: 20, northMetres: 200))
        #expect(try harness.storedSamples().count == 2)
    }

    @Test("A build without the location background mode pauses instead, and says so")
    func pausesInBackgroundWithoutTheCapability() throws {
        let harness = try makeHarness()
        harness.provider.supportsBackgroundUpdates = false
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.tracking.enterBackground()

        #expect(harness.tracking.state == .pausedInBackground)
        #expect(!harness.provider.isUpdating)
        #expect(harness.provider.stopCount == 1)
        #expect(!harness.provider.allowsBackgroundUpdates)
    }

    @Test("The background grant is held only while a session is running")
    func holdsTheBackgroundGrantOnlyWhileCapturing() throws {
        let harness = try makeHarness()
        #expect(!harness.provider.allowsBackgroundUpdates, "No shift, nothing to record")

        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        #expect(harness.provider.allowsBackgroundUpdates)

        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(60))
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .idle)
        #expect(!harness.provider.allowsBackgroundUpdates, "A finished shift must not leave the grant open")
    }

    @Test("Returning to the foreground does not restart a session that never stopped")
    func returningDoesNotRestartAContinuedSession() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.tracking.enterBackground()

        harness.tracking.enterForeground()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.startCount == 1)
        #expect(harness.provider.stopCount == 0)
    }

    @Test("Returning to the foreground resumes capture that had stopped")
    func resumesOnForegroundReturn() throws {
        let harness = try makeHarness()
        harness.provider.supportsBackgroundUpdates = false
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.tracking.enterBackground()

        harness.tracking.enterForeground()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.startCount == 2)

        harness.provider.emit(sample(harness, secondsAfterStart: 300, northMetres: 500))
        #expect(try harness.storedSamples().count == 2)
    }

    @Test("Returning to the foreground with no shift running does not start capture")
    func doesNotResumeWithoutAShift() throws {
        let harness = try makeHarness()
        harness.tracking.enterBackground()

        harness.tracking.enterForeground()

        #expect(harness.tracking.state == .idle)
        #expect(harness.provider.startCount == 0)
    }

    @Test("A shift that begins while the app is already behind another one records nothing yet")
    func doesNotStartASessionFromTheBackground() throws {
        let harness = try makeHarness()
        harness.tracking.enterBackground()

        // Started by voice, with DashPilot not on screen. When In Use continues
        // a stream that began in front; it does not deliver one that did not, so
        // starting here would be a claim no position would arrive for.
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .pausedInBackground)
        #expect(harness.provider.startCount == 0)
        #expect(!harness.provider.allowsBackgroundUpdates)

        harness.tracking.enterForeground()
        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.startCount == 1)
    }

    @Test("Permission revoked while the app is behind another one stops capture there")
    func stopsWhenPermissionIsRevokedInTheBackground() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.tracking.enterBackground()
        #expect(harness.tracking.state == .tracking)

        // Turned off in Settings, which is somewhere the driver necessarily is
        // while DashPilot is not on screen. Nothing may go on recording, and
        // nothing may go on saying it is.
        harness.authorizationProvider.update(status: .denied)

        #expect(harness.tracking.state == .unavailable(.permissionDenied))
        #expect(!harness.provider.isUpdating)
        #expect(!harness.provider.allowsBackgroundUpdates)

        harness.tracking.enterForeground()
        #expect(harness.tracking.state == .unavailable(.permissionDenied))
    }

    @Test("Pending samples are written before the app leaves the foreground")
    func flushesWhenLeavingTheForeground() throws {
        let harness = try makeHarness(saveBatchSize: 100)
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        #expect(try harness.storedSamples().isEmpty, "Below the batch size, nothing is written yet")

        harness.tracking.enterBackground()

        #expect(try harness.storedSamples().count == 1)
    }

    // MARK: Resuming a persisted shift

    @Test("A shift still running when the app was terminated resumes capture")
    func resumesAPersistedShift() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try ShiftService(context: context).startShift(at: shiftStart)

        // A service built as the app would build one on the next launch: no
        // memory of the previous run, only the store.
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(status: .authorizedWhenInUse)
        )
        let tracking = LocationTrackingService(
            context: context,
            authorization: authorization,
            provider: provider,
            saveBatchSize: 1,
            now: { self.shiftStart.addingTimeInterval(20) }
        )

        tracking.synchronize()

        #expect(tracking.state == .tracking)
        #expect(provider.isUpdating)
        // And it records into the shift that was already there, not a new one.
        provider.emit(SyntheticRoute.sample(at: shiftStart.addingTimeInterval(20)))
        let shifts = try context.fetch(FetchDescriptor<Shift>())
        #expect(shifts.count == 1)
        #expect(shifts.first?.routeSamples.count == 1)
    }

    @Test("A rebuilt service continues the stored route rather than restarting it")
    func restoresTheEndOfTheStoredRoute() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10, northMetres: 100))

        let rebuiltProvider = StubLocationTrackingProvider()
        let rebuilt = LocationTrackingService(
            context: harness.context,
            authorization: harness.authorization,
            provider: rebuiltProvider,
            saveBatchSize: 1,
            now: { harness.clock.date }
        )
        rebuilt.synchronize()

        // The same position again: only knowing where the route left off makes
        // this a duplicate rather than the first sample of a new run.
        harness.clock.date = shiftStart.addingTimeInterval(15)
        rebuiltProvider.emit(
            SyntheticRoute.sample(at: shiftStart.addingTimeInterval(15), northMetres: 100)
        )

        #expect(try harness.storedSamples().count == 1)
    }

    // MARK: Persistence

    @Test("Accepted samples are written in batches rather than one save per fix")
    func batchesWrites() throws {
        let harness = try makeHarness(saveBatchSize: 3)
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        harness.provider.emit(sample(harness, secondsAfterStart: 1, northMetres: 20))
        harness.provider.emit(sample(harness, secondsAfterStart: 2, northMetres: 40))
        #expect(try harness.storedSamples().isEmpty)
        #expect(try harness.pendingAndStoredSamples().count == 2, "Held, not lost")

        harness.provider.emit(sample(harness, secondsAfterStart: 3, northMetres: 60))
        #expect(try harness.storedSamples().count == 3)
    }

    @Test("Ending a shift writes the samples still held in memory")
    func flushesWhenTheShiftEnds() throws {
        let harness = try makeHarness(saveBatchSize: 100)
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 1, northMetres: 20))
        harness.provider.emit(sample(harness, secondsAfterStart: 2, northMetres: 40))

        harness.tracking.prepareForShiftEnd()

        #expect(try harness.storedSamples().count == 2)

        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(60))
        harness.tracking.synchronize()
        #expect(try harness.storedSamples().count == 2)
    }

    // MARK: Reconciling

    @Test("Reconciling repeatedly does not restart capture")
    func synchronizeIsIdempotent() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)

        for _ in 0..<5 { harness.tracking.synchronize() }

        #expect(harness.provider.startCount == 1)
        #expect(harness.provider.stopCount == 0)
        #expect(harness.tracking.state == .tracking)
    }

    @Test("A refused shift start leaves capture as it was")
    func aRefusedStartDoesNotStartCapture() throws {
        let harness = try makeHarness()

        #expect(throws: ShiftLifecycleError.self) {
            try harness.shifts.endActiveShift(at: shiftStart)
        }
        harness.tracking.synchronize()

        #expect(harness.tracking.state == .idle)
        #expect(harness.provider.startCount == 0)
    }

    @Test("Capture restarts if ending the shift did not go through")
    func restartsWhenAnEndFails() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        // The app stops capture first, then records the end. Here the end never
        // happens — the reconcile that follows it has to put capture back.
        harness.tracking.prepareForShiftEnd()
        #expect(!harness.provider.isUpdating)

        harness.tracking.synchronize()

        #expect(harness.tracking.state == .tracking)
        #expect(harness.provider.isUpdating)
    }

    // MARK: Capture continuity

    @Test("Retained samples record the stretch of capture they belong to")
    func stampsSamplesWithACaptureSession() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 1...3 {
            harness.provider.emit(
                sample(harness, secondsAfterStart: TimeInterval(step) * 10, northMetres: Double(step) * 100)
            )
        }

        let sessions = Set(try harness.storedSamples().map(\.captureSessionID))
        #expect(sessions.count == 1, "One uninterrupted stretch of capture is one session")
        #expect(sessions.first != nil, "A sample recorded now is not a legacy sample")
    }

    @Test("Capture that continued through a backgrounding stays in one session")
    func keepsOneSessionAcrossABackgrounding() throws {
        let harness = try makeHarness()
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        harness.tracking.enterBackground()
        harness.provider.emit(sample(harness, secondsAfterStart: 40, northMetres: 800))
        harness.tracking.enterForeground()
        harness.provider.emit(sample(harness, secondsAfterStart: 70, northMetres: 1_600))

        let stored = try harness.storedSamples()
        #expect(stored.count == 3)
        #expect(
            Set(stored.map(\.captureSessionID)).count == 1,
            "Nothing stopped, so the route must not claim a break"
        )
    }

    @Test("Capture that stopped at the foreground boundary starts a new session")
    func opensANewSessionAfterAPause() throws {
        let harness = try makeHarness()
        harness.provider.supportsBackgroundUpdates = false
        try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))

        harness.tracking.enterBackground()
        harness.tracking.enterForeground()
        harness.provider.emit(sample(harness, secondsAfterStart: 70, northMetres: 2_000))

        let stored = try harness.storedSamples()
        #expect(stored.count == 2)
        #expect(
            stored.first?.captureSessionID != stored.last?.captureSessionID,
            "Capture stopped in between, and the route has to say so"
        )
    }

    @Test("Distance driven while DashPilot was behind another app is counted, because it was recorded")
    func countsDistanceRecordedInTheBackground() throws {
        let harness = try makeHarness()
        let shift = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 0...2 {
            harness.provider.emit(
                sample(harness, secondsAfterStart: TimeInterval(step) * 10, northMetres: Double(step) * 100)
            )
        }

        // The driver opens the delivery app and keeps driving. Capture never
        // stopped, so this is not a gap and the distance is not invented.
        harness.tracking.enterBackground()
        for step in 3...5 {
            harness.provider.emit(
                sample(harness, secondsAfterStart: TimeInterval(step) * 10, northMetres: Double(step) * 100)
            )
        }
        harness.tracking.enterForeground()

        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(60))

        let distance = shift.recordedDistance()

        #expect(shift.routeSamples.count == 6)
        #expect(
            SyntheticRoute.isCloseEnough(distance.metres, to: 500),
            "measured \(distance.metres) m over five hundred metres of recorded movement"
        )
        #expect(distance.segmentCount == 1)
        #expect(distance.gapCount == 0)
    }

    @Test("The distance covered while capture was paused is not counted as driving")
    func doesNotCountDistanceAcrossAPause() throws {
        let harness = try makeHarness()
        harness.provider.supportsBackgroundUpdates = false
        let shift = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()

        for step in 0...2 {
            harness.provider.emit(
                sample(harness, secondsAfterStart: TimeInterval(step) * 10, northMetres: Double(step) * 100)
            )
        }

        // A minute with capture stopped, two kilometres of driving. The pause is
        // deliberately shorter than the mileage calculation's gap threshold, so
        // only the recorded break in capture can exclude it.
        harness.tracking.enterBackground()
        harness.tracking.enterForeground()

        for step in 0...2 {
            harness.provider.emit(
                sample(
                    harness,
                    secondsAfterStart: 80 + TimeInterval(step) * 10,
                    northMetres: 2_200 + Double(step) * 100
                )
            )
        }

        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(110))

        let distance = shift.recordedDistance()

        #expect(shift.routeSamples.count == 6)
        #expect(
            SyntheticRoute.isCloseEnough(distance.metres, to: 400),
            "measured \(distance.metres) m; the two kilometres driven while paused must not be counted"
        )
        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount == 1)
        #expect(distance.isPartial)
    }

    @Test("A new shift's route never continues the previous shift's capture session")
    func opensANewSessionForANewShift() throws {
        let harness = try makeHarness()

        let first = try harness.shifts.startShift(at: shiftStart)
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 10))
        harness.tracking.prepareForShiftEnd()
        try harness.shifts.endActiveShift(at: shiftStart.addingTimeInterval(60))
        harness.tracking.synchronize()

        let second = try harness.shifts.startShift(at: shiftStart.addingTimeInterval(120))
        harness.tracking.synchronize()
        harness.provider.emit(sample(harness, secondsAfterStart: 130, northMetres: 3_000))

        let firstSessions = Set(first.routeSamples.map(\.captureSessionID))
        let secondSessions = Set(second.routeSamples.map(\.captureSessionID))

        #expect(firstSessions.count == 1)
        #expect(secondSessions.count == 1)
        #expect(firstSessions.isDisjoint(with: secondSessions))
    }
}
