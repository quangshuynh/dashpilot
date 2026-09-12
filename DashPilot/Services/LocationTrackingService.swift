import Foundation
import OSLog
import SwiftData

/// Captures a running shift's route.
///
/// The service coordinates three things that are deliberately kept apart
/// elsewhere: ``LocationAuthorizationService`` decides what the app is allowed
/// to do, ``LocationTrackingProviding`` produces candidate positions, and
/// ``RouteSampleFilter`` judges them. This type decides *when* capture runs and
/// writes what survives.
///
/// ## The invariant
///
/// **A retained sample always belongs to exactly one running shift.** SwiftData
/// is the only authority on whether a shift is running; the service never keeps
/// its own "a shift is active" flag that could disagree with the store. It holds
/// the shift object itself, reads `endedAt` from it on every candidate, and
/// stops when that object says the shift has finished. A completed shift cannot
/// grow: the filter rejects every candidate for a shift with an end timestamp,
/// and ``prepareForShiftEnd()`` stops updates before the end is recorded.
///
/// ## Continuity
///
/// Each stretch of capture is stamped with a capture session identifier, minted
/// when updates start and cleared when they stop. It is the only record the
/// stored route keeps of its own gaps, and the mileage calculation refuses to
/// measure across a change of it. Every way capture can stop, including a lost
/// permission, a failed save and a new process, therefore ends a session, and
/// nothing resumes one.
///
/// The corollary matters as much: a transition that does **not** stop capture
/// must not end a session either, or the route would carry a gap where nothing
/// was actually missed. Leaving the foreground with a session running is that
/// case.
///
/// ## A paused shift
///
/// Pausing stops capture at once, and resuming starts a **new** session. That
/// is not an implementation detail to work around: nothing was recorded between
/// the two, so nothing may be measured across them either, and the session
/// change is exactly what stops the mileage calculation from drawing a line from
/// where the driver paused to wherever they resumed. The route carries the break
/// because the break is real.
///
/// ## Where capture may run
///
/// A session can only be **started** while the app is in the foreground, and
/// once started it **continues** when the driver switches to another app or
/// locks the phone. That is exactly what When In Use authorization plus the
/// `location` background mode permits, and it is why the app asks for nothing
/// more: Always authorization buys the ability to begin a session from the
/// background and to be relaunched into one, neither of which is implemented.
///
/// The consequences are deliberate and are stated rather than smoothed over:
///
/// - Leaving the foreground with capture running is **not** a gap. One capture
///   session spans the transition, nothing is stopped and nothing is restarted,
///   so the route across it is a route that was genuinely recorded.
/// - Leaving the foreground with capture *not* running leaves it not running.
///   A shift started by voice while the app is behind another one records
///   nothing until the driver opens DashPilot, and ``RouteCaptureState`` says
///   `pausedInBackground` for exactly that.
/// - iOS may still suspend or terminate the process, and nothing here relaunches
///   it. That ends the capture session like any other interruption, so the route
///   carries the gap and the mileage calculation refuses to measure across it.
///
/// iOS guarantees no background execution, and nothing here pretends otherwise.
///
/// `@MainActor` because it drives visible state and shares the main context with
/// ``ShiftService``. Every operation runs to completion without suspending, so a
/// candidate cannot arrive part-way through starting or stopping a shift.
@MainActor
@Observable
final class LocationTrackingService {
    /// What capture is doing. Read by the interface; never set from it.
    private(set) var state: RouteCaptureState = .idle

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let authorization: LocationAuthorizationService
    @ObservationIgnored private let provider: any LocationTrackingProviding
    @ObservationIgnored private let filter: RouteSampleFilter
    @ObservationIgnored private let now: () -> Date

    /// How many accepted samples may be held in memory before a save.
    ///
    /// Saving on every callback would mean a store write roughly once a second
    /// for the length of a shift; batching without measurement would be building
    /// a subsystem for a problem nobody has demonstrated. Ten is the smallest
    /// step that removes the per-callback write while bounding what an abrupt
    /// termination costs to a few seconds of route. Every deliberate stop —
    /// backgrounding, ending a shift, losing permission — flushes first, so the
    /// exposure is only to a crash or a kill.
    @ObservationIgnored private let saveBatchSize: Int

    /// The shift being recorded, as the store's own object rather than a copy.
    @ObservationIgnored private var recordingShift: Shift?

    /// The last sample retained for ``recordingShift``, which the filter judges
    /// the next candidate against.
    @ObservationIgnored private var lastAccepted: LocationSample?

    /// Identifies the stretch of capture in progress, or `nil` when capture is
    /// not running.
    ///
    /// A new identifier is minted every time updates start and cleared every
    /// time they stop, so samples sharing one were retained with no interruption
    /// between them. That is the only thing the stored route says about its own
    /// continuity, and the mileage calculation depends on it: without it a
    /// twenty second backgrounding and a twenty second wait at a light are the
    /// same twenty seconds of missing samples.
    @ObservationIgnored private var captureSessionID: UUID?

    /// Accepted samples inserted but not yet saved.
    @ObservationIgnored private var unsavedSampleCount = 0

    /// Samples retained since capture last started, for logging only.
    @ObservationIgnored private var retainedSampleCount = 0

    /// Set while the app is not in the foreground.
    @ObservationIgnored private var isBackgrounded = false

    /// Called after accepted samples reach the store.
    ///
    /// The one place that knows a shift's recorded mileage has actually moved,
    /// and the only place that knows it **while the app is off screen**, which
    /// is where most of a shift is recorded. The shift's Live Activity is driven
    /// from here for that reason: a cadence owned by a view would stop at the
    /// moment the driver locks the phone, which is the moment the surface starts
    /// being the only thing they can see.
    ///
    /// It is a notification and never an instruction: what the callback does
    /// with it is the caller's, capture does not wait on it, and a callback that
    /// raised would be a bug in the caller rather than a reason to stop
    /// recording.
    @ObservationIgnored var onRoutePersisted: (() -> Void)?

    /// The shipping configuration, backed by Core Location.
    convenience init(context: ModelContext, authorization: LocationAuthorizationService) {
        self.init(
            context: context,
            authorization: authorization,
            provider: CoreLocationTrackingProvider()
        )
    }

    init(
        context: ModelContext,
        authorization: LocationAuthorizationService,
        provider: any LocationTrackingProviding,
        filter: RouteSampleFilter = RouteSampleFilter(),
        saveBatchSize: Int = 10,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.authorization = authorization
        self.provider = provider
        self.filter = filter
        self.saveBatchSize = saveBatchSize
        self.now = now

        provider.onSample = { [weak self] candidate in
            self?.receive(candidate)
        }
        provider.onFailure = { [weak self] failure in
            self?.receive(failure)
        }
        // Permission can be revoked while the app is behind another one, which
        // is where a driver changing it in Settings necessarily does it. Capture
        // now runs there, so it reconciles on the platform's report rather than
        // waiting for a screen to notice.
        authorization.onAuthorizationChange = { [weak self] _ in
            self?.synchronize()
        }
    }

    // MARK: Reconciling with the shift

    /// Brings capture into line with the store and the current permission.
    ///
    /// This is the only way capture starts or stops. It is safe to call at any
    /// time and as often as the app likes: it derives what should be happening
    /// from the store rather than from what happened last, so a missed call
    /// costs a delay and never a wrong state.
    ///
    /// Call it when a shift starts or ends, when the app becomes active, when
    /// permission changes, and once when the interface appears — the last of
    /// which is how a shift that was still running when the app was terminated
    /// resumes capture without a replacement shift being created.
    func synchronize() {
        let activeShift: Shift?
        do {
            activeShift = try ShiftService(context: context).activeShift()
        } catch {
            AppLog.routeCapture.error("Could not read the active shift; capture stopped: \(error)")
            stopCapturing()
            recordingShift = nil
            lastAccepted = nil
            transition(to: .unavailable(.storeUnavailable))
            return
        }

        guard let shift = activeShift else {
            stopCapturing()
            recordingShift = nil
            lastAccepted = nil
            transition(to: .idle)
            return
        }

        adopt(shift)

        // The driver's own decision outranks everything below it. A paused shift
        // is not recording because they said so, and reporting a permission
        // problem or a background pause instead would explain a stop they
        // already know the reason for, and would imply that fixing it would
        // resume recording, which it would not.
        guard !shift.isPaused else {
            stopCapturing()
            transition(to: .shiftPaused)
            return
        }

        // Permission is judged before the app's own position, because it
        // outranks it: a shift that cannot be recorded at all should say why,
        // not report a pause it would not come back from anyway.
        if let reason = RouteCaptureUnavailableReason(authorization.authorization) {
            stopCapturing()
            transition(to: .unavailable(reason))
            return
        }

        if !provider.isUpdating {
            // A session may only *begin* in the foreground. When In Use lets a
            // running stream continue into the background; it does not deliver
            // one that was not already running, so starting here would leave the
            // app claiming to record a route no position will arrive for.
            guard !isBackgrounded else {
                transition(to: .pausedInBackground)
                return
            }
            retainedSampleCount = 0
            captureSessionID = UUID()
            provider.startUpdates()
            AppLog.routeCapture.info("Route capture started")
        }
        transition(to: .tracking)
    }

    /// Stops capture ahead of ending a shift.
    ///
    /// Ordering matters: updates are stopped and pending samples are written
    /// *before* the end timestamp is recorded, so there is no window in which a
    /// candidate could be judged against a shift the store has already closed.
    /// If ending then fails, ``synchronize()`` restarts capture — this leaves
    /// nothing latched, it only closes the window.
    func prepareForShiftEnd() {
        stopCapturing()
    }

    /// Stops capture ahead of pausing a shift.
    ///
    /// The same ordering rule ``prepareForShiftEnd()`` keeps, for the same
    /// reason: updates are stopped and pending samples are written *before* the
    /// pause is recorded, so no candidate can be judged against a shift the
    /// store has already paused, and no position recorded after the driver
    /// tapped Pause is retained. If the pause then fails to save,
    /// ``synchronize()`` restarts capture in a new session. Nothing is latched,
    /// and the few seconds of route that stop cost are honestly reported as a
    /// break rather than measured across.
    func prepareForShiftPause() {
        stopCapturing()
    }

    /// Records that the app has left the foreground.
    ///
    /// What happens next is decided by whether a session is already running and
    /// whether this build may keep one running outside the foreground. A running
    /// session is left **untouched**: stopping and restarting it around the
    /// transition would mint a second capture session and put a gap in a route
    /// that was never interrupted.
    ///
    /// Pending samples are written either way. Once the app is off screen iOS
    /// may suspend or terminate it at any moment and promises no later chance,
    /// so what is only in memory is written while there is still a process to
    /// write it.
    func enterBackground() {
        guard !isBackgrounded else { return }
        isBackgrounded = true

        flush()

        if provider.isUpdating, provider.supportsBackgroundUpdates {
            AppLog.routeCapture.info("Left the foreground; route capture continues")
            return
        }

        // Read after the flush, which can itself have stopped capture and said
        // why. A store that cannot be written to is a better answer than a
        // pause, so the reason already on the state is not overwritten here.
        let wasTracking = state == .tracking
        stopCapturing()
        if wasTracking {
            transition(to: .pausedInBackground)
            AppLog.routeCapture.info("Left the foreground; route capture paused")
        }
    }

    /// Records that the app is in the foreground again.
    ///
    /// Reconciling is all that is needed in either direction: a session that
    /// continued through the background is still running and is left alone, and
    /// one that stopped starts again as a new capture session.
    func enterForeground() {
        isBackgrounded = false
        synchronize()
    }

    // MARK: Receiving candidates

    /// Judges one candidate and retains it if the policy accepts it.
    ///
    /// A rejection is only ever a rejection: it never stops capture, so one bad
    /// fix cannot cost a driver the rest of the route.
    private func receive(_ candidate: LocationSample) {
        guard state.isCapturing else { return }

        // Permission is re-read here, not just when the interface notices it
        // changed. Revocation while a shift runs must stop samples being kept at
        // the moment they arrive, not at the next reconcile.
        if let reason = RouteCaptureUnavailableReason(authorization.authorization) {
            AppLog.routeCapture.notice("Location became unusable during a shift; capture stopped")
            stopCapturing()
            transition(to: .unavailable(reason))
            return
        }

        // The shift object comes from the store and is read again for every
        // candidate. A shift that has ended, or that has been deleted, stops
        // capture rather than being written to.
        guard let shift = recordingShift, !shift.isDeleted else {
            stopCapturing()
            transition(to: .idle)
            return
        }

        let decision = filter.evaluate(
            candidate,
            in: RouteSampleFilter.Context(
                shiftStart: shift.startedAt,
                shiftEnd: shift.endedAt,
                isPaused: shift.isPaused,
                lastAccepted: lastAccepted,
                now: now()
            )
        )

        switch decision {
        case .reject(let reason):
            // The reason names the rule, never the sample, so this cannot leak
            // a position.
            AppLog.routeCapture.debug("Rejected a location sample: \(reason.rawValue, privacy: .public)")
            // Both of these say the shift stopped accepting route while a fix
            // was in flight. Reconciling settles which state that is, and the
            // stop is what guarantees the next accepted sample opens a new
            // capture session.
            if reason == .shiftEnded || reason == .shiftPaused {
                stopCapturing()
                synchronize()
            }
        case .accept:
            retain(candidate, for: shift, in: currentCaptureSession())
        }
    }

    private func receive(_ failure: LocationTrackingFailure) {
        switch failure {
        case .temporarilyUnavailable:
            // Core Location keeps trying. Reporting this as a failure would
            // turn a tunnel into a stopped recording.
            AppLog.routeCapture.debug("No position available; updates continue")
        case .unavailable:
            stopCapturing()
            if state.accompaniesActiveShift {
                transition(to: .unavailable(.locationFailed))
            }
        }
    }

    // MARK: Persistence

    private func retain(_ sample: LocationSample, for shift: Shift, in session: UUID) {
        context.insert(RouteSample(shift: shift, sample: sample, captureSessionID: session))
        lastAccepted = sample
        unsavedSampleCount += 1
        retainedSampleCount += 1

        if unsavedSampleCount >= saveBatchSize {
            flush()
        }
    }

    /// Writes accepted samples that are still only in memory.
    private func flush() {
        guard unsavedSampleCount > 0 else { return }
        let pending = unsavedSampleCount
        unsavedSampleCount = 0

        do {
            try context.save()
            AppLog.routeCapture.debug("Persisted \(pending, privacy: .public) route samples")
            onRoutePersisted?()
        } catch {
            // Same rule as the shift lifecycle: memory must not claim what the
            // store does not hold. `lastAccepted` is cleared with it, because
            // the sample it referred to no longer exists — the next candidate is
            // then judged as the first of the route, which is what it is.
            context.rollback()
            lastAccepted = nil
            AppLog.routeCapture.error("Failed to persist \(pending, privacy: .public) route samples: \(error)")
            stopCapturing()
            if state.accompaniesActiveShift {
                transition(to: .unavailable(.storeUnavailable))
            }
        }
    }

    // MARK: Internals

    /// Points capture at `shift`, restoring where the route left off if this is
    /// a shift the service has not been recording.
    private func adopt(_ shift: Shift) {
        guard recordingShift?.id != shift.id else {
            recordingShift = shift
            return
        }
        recordingShift = shift
        lastAccepted = lastRetainedSample(of: shift)
        unsavedSampleCount = 0
        // A different shift is a different route. Nothing recorded for the
        // previous one may share a capture session with what follows.
        captureSessionID = nil
    }

    /// The capture session samples are currently being recorded in.
    ///
    /// Capture starting is what normally opens one. If a candidate is somehow
    /// accepted without an open session, a fresh one is opened rather than the
    /// sample being stored with unknown continuity: an extra break under-reports
    /// distance, while a missing one would report a gap as driving.
    private func currentCaptureSession() -> UUID {
        if let captureSessionID { return captureSessionID }
        let session = UUID()
        captureSessionID = session
        return session
    }

    /// The newest sample already stored for a shift.
    ///
    /// Read back so that capture resumed after a relaunch, a backgrounding or a
    /// permission interruption continues to judge candidates against the route
    /// as it actually stands, instead of accepting a duplicate or a jump because
    /// the service was rebuilt with no history.
    ///
    /// Fetched with a limit rather than by walking `shift.routeSamples`, which
    /// would load an entire shift's route to look at one row.
    private func lastRetainedSample(of shift: Shift) -> LocationSample? {
        let shiftID = shift.id
        var descriptor = FetchDescriptor<RouteSample>(
            predicate: #Predicate { $0.shift?.id == shiftID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first?.locationSample
        } catch {
            AppLog.routeCapture.error("Could not read the end of the stored route: \(error)")
            return nil
        }
    }

    /// Stops updates and writes anything still pending.
    private func stopCapturing() {
        let wasUpdating = provider.isUpdating
        provider.stopUpdates()
        flush()
        // Whatever happens next was not recorded continuously with what came
        // before, including when a failed flush has just discarded rows.
        captureSessionID = nil
        if wasUpdating {
            AppLog.routeCapture.info(
                "Route capture stopped after \(self.retainedSampleCount, privacy: .public) retained samples"
            )
        }
    }

    private func transition(to newState: RouteCaptureState) {
        guard newState != state else { return }
        state = newState
        AppLog.routeCapture.info("Route capture state: \(String(describing: newState), privacy: .public)")
    }
}
