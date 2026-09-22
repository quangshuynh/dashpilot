import Foundation
import OSLog
import SwiftData

/// Failures raised when a shift lifecycle operation cannot be applied.
///
/// These are the states the UI has to be able to explain, so each case carries
/// enough information to write a sentence about it rather than only a code.
nonisolated enum ShiftLifecycleError: Error {
    /// A shift was already running when a start was requested.
    case shiftAlreadyActive(startedAt: Date)
    /// An end was requested while no shift was running.
    case noActiveShift
    /// Deletion was requested for a shift that has not finished.
    case cannotDeleteActiveShift
    /// An end was requested while deliveries on that shift were still in
    /// progress. Carries how many, because the refusal has to name them.
    case activeDeliveriesInProgress(count: Int)
    /// A pause was requested while deliveries on that shift were still in
    /// progress.
    ///
    /// Kept apart from ``activeDeliveriesInProgress(count:)`` rather than
    /// reused, because the sentence has to name what was refused: a driver told
    /// to finish their deliveries "before ending the shift" when they asked to
    /// pause it has been answered about something they did not ask for.
    case activeDeliveriesBlockPause(count: Int)
    /// A pause was requested on a shift that is already paused. Carries when it
    /// was paused, as ``shiftAlreadyActive(startedAt:)`` carries its start.
    case shiftAlreadyPaused(pausedAt: Date)
    /// A resume was requested on a shift that is not paused.
    case shiftNotPaused
    /// Parking was requested on a shift that already records the vehicle as
    /// parked.
    case shiftAlreadyParked(parkedAt: Date)
    /// Resuming driving was requested on a shift that does not record the
    /// vehicle as parked.
    case shiftNotParked
    /// The shift model rejected the transition.
    case invalidTransition(ShiftError)
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension ShiftLifecycleError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.shiftAlreadyActive(lhsDate), .shiftAlreadyActive(rhsDate)): lhsDate == rhsDate
        case (.noActiveShift, .noActiveShift): true
        case (.cannotDeleteActiveShift, .cannotDeleteActiveShift): true
        case let (.activeDeliveriesInProgress(lhsCount), .activeDeliveriesInProgress(rhsCount)):
            lhsCount == rhsCount
        case let (.activeDeliveriesBlockPause(lhsCount), .activeDeliveriesBlockPause(rhsCount)):
            lhsCount == rhsCount
        case let (.shiftAlreadyPaused(lhsDate), .shiftAlreadyPaused(rhsDate)): lhsDate == rhsDate
        case (.shiftNotPaused, .shiftNotPaused): true
        case let (.shiftAlreadyParked(lhsDate), .shiftAlreadyParked(rhsDate)): lhsDate == rhsDate
        case (.shiftNotParked, .shiftNotParked): true
        case let (.invalidTransition(lhsError), .invalidTransition(rhsError)): lhsError == rhsError
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension ShiftLifecycleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .shiftAlreadyActive:
            "A shift is already in progress. End it before starting another one."
        case .noActiveShift:
            // Names no particular action. This one refusal is reached by ending,
            // pausing, resuming, parking and driving again, and a driver who
            // said they had parked should not be answered about ending.
            "There is no shift in progress."
        case .cannotDeleteActiveShift:
            "A shift that is still in progress cannot be deleted. End it first."
        case let .activeDeliveriesInProgress(count):
            count == 1
                ? "A delivery is still in progress. Mark it delivered or cancel it before ending the shift."
                : """
                \(count) deliveries are still in progress. Mark each one delivered or cancel it before \
                ending the shift.
                """
        case let .activeDeliveriesBlockPause(count):
            count == 1
                ? "A delivery is still in progress. Mark it delivered or cancel it before pausing the shift."
                : """
                \(count) deliveries are still in progress. Mark each one delivered or cancel it before \
                pausing the shift.
                """
        case .shiftAlreadyPaused:
            "This shift is already paused. Resume it before pausing it again."
        case .shiftNotPaused:
            "This shift is not paused, so there is nothing to resume."
        case .shiftAlreadyParked:
            "DashPilot already has this shift recorded as parked. Resume driving before parking again."
        case .shiftNotParked:
            "This shift is not recorded as parked, so there is nothing to resume."
        case .invalidTransition(.alreadyParked):
            "DashPilot already has this shift recorded as parked. Resume driving before parking again."
        case .invalidTransition(.notParked):
            "This shift is not recorded as parked, so there is nothing to resume."
        case .invalidTransition(.alreadyPaused):
            "This shift is already paused. Resume it before pausing it again."
        case .invalidTransition(.notPaused):
            "This shift is not paused, so there is nothing to resume."
        case .invalidTransition(.shiftAlreadyEnded):
            "This shift has already ended, so it cannot be paused or resumed."
        case .invalidTransition(.shiftNotCompleted):
            "Earnings can be recorded once the shift has ended."
        case .invalidTransition(.negativeEarnings):
            "Gross earnings cannot be negative."
        case .invalidTransition(.invalidFuelEconomy):
            "Miles per gallon has to be more than zero. It is what DashPilot divides the recorded miles by."
        case .invalidTransition(.negativeGasPrice):
            "A gas price cannot be a negative amount. Enter what a gallon cost."
        case .invalidTransition:
            "That change could not be applied to the shift."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the shift was not changed."
        }
    }
}

/// The driver's shift lifecycle, start through pause, resume and end, and the
/// recorded amounts that hang from a finished one.
///
/// The service owns one invariant: **at most one shift may be unfinished at a
/// time**. It is enforced here, against the store, rather than by whether a
/// button happens to be disabled — a disabled control is a presentation detail
/// and cannot protect the data.
///
/// SwiftData is the only source of truth. The service keeps no cached "is a
/// shift running" flag; the answer is always a fetch for a shift without an end
/// timestamp. That is what makes relaunch recovery fall out for free: a shift
/// left unfinished when the app was terminated is simply still unfinished when
/// a new service reads the store.
///
/// **Pausing keeps that property rather than weakening it.** A pause is a row
/// on the shift, so `endedAt == nil` still selects the unfinished shift and a
/// paused shift is recovered by exactly the same fetch as a running one; which
/// of the two it is comes from ``Shift/lifecycleState``, derived from the rows
/// each time. There is no paused flag anywhere in the app to fall out of step
/// with the store.
///
/// The type is `@MainActor` isolated. Every operation runs to completion without
/// suspending, so two concurrent callers cannot interleave a check with the
/// insert that follows it, and no further locking is needed in a single-user
/// on-device app.
@MainActor
struct ShiftService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The shift currently in progress, or `nil` if none is.
    ///
    /// - Throws: ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeShift() throws -> Shift? {
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        // One more than the invariant permits, so a broken store is noticed
        // instead of silently reduced to its first row.
        descriptor.fetchLimit = 2

        let unfinished: [Shift]
        do {
            unfinished = try context.fetch(descriptor)
        } catch {
            AppLog.shift.error("Failed to read the active shift: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        if unfinished.count > 1 {
            AppLog.shift.fault("Store holds more than one unfinished shift; treating the most recent as active")
        }
        return unfinished.first
    }

    /// Starts a shift.
    ///
    /// - Throws: ``ShiftLifecycleError/shiftAlreadyActive(startedAt:)`` if one is
    ///   already running, or ``ShiftLifecycleError/storeUnavailable(underlying:)``
    ///   if the store cannot be read or written.
    @discardableResult
    func startShift(at date: Date = .now) throws -> Shift {
        if let running = try activeShift() {
            AppLog.shift.notice("Refused to start a shift: one is already running")
            throw ShiftLifecycleError.shiftAlreadyActive(startedAt: running.startedAt)
        }

        let shift = Shift(startedAt: date)
        context.insert(shift)
        let recordedDefaults = recordStartingFuelDefaults(on: shift)
        do {
            try context.save()
        } catch {
            // Leave nothing half-started in memory that the store does not hold.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift start: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift started, fuel defaults recorded: \(recordedDefaults, privacy: .public)")
        return shift
    }

    /// Copies the driver's current fuel defaults onto a shift that has just been
    /// created, and reports whether there was anything to copy.
    ///
    /// **Why the start and not the end.** The assumptions a shift is estimated
    /// under are the ones that were true while it was being worked. Reading them
    /// when the shift *ends* would let a driver who changed vehicle or updated
    /// the gas price at lunchtime silently restate what the whole shift had
    /// already been worked under, which is the dependence on a current global
    /// figure the snapshot exists to prevent. Taking it at the start is the
    /// earliest moment the facts are true and the last moment they cannot have
    /// moved.
    ///
    /// **A start is never refused over a default.** A driver going out to work
    /// must be able to start a shift, so a refusal here is logged structurally
    /// and swallowed: the shift then records no assumptions, which is exactly
    /// what every shift recorded before this existed carries, and the driver can
    /// enter a pair on the completed shift as they always could. There is no
    /// state in which the shift is half-started.
    ///
    /// No write happens in the same context save unless the shift itself is
    /// saved, because the caller saves once.
    private func recordStartingFuelDefaults(on shift: Shift) -> Bool {
        let defaults = SettingsService(context: context).currentFuelDefaults()
        guard defaults.hasAny else { return false }

        do {
            try shift.recordStartingFuelDefaults(defaults)
            return true
        } catch {
            AppLog.fuel.error(
                "Could not record the starting fuel defaults: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// Ends the shift currently in progress, paused or not.
    ///
    /// ## Ending a paused shift is allowed, and closes the pause
    ///
    /// Refusing would be the wrong answer to the only question that matters
    /// here: a driver who has finished for the day has finished, and making them
    /// resume a shift they are not working in order to end it would record a
    /// stretch of work that did not happen. So the open pause is closed **at the
    /// same instant the shift ends**, which is the truthful reading of what
    /// happened: they were paused right up to the moment they stopped.
    ///
    /// Two consequences, both asserted rather than assumed: the pause
    /// contributes its full length to the shift's paused time, and the shift's
    /// working duration therefore excludes every second between pausing and
    /// ending. A shift paused and then ended without being resumed can have a
    /// working duration well short of its elapsed one, and that is the figure
    /// every rate is derived from.
    ///
    /// - Throws: ``ShiftLifecycleError/noActiveShift`` if none is running, or
    ///   ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the store cannot
    ///   be read or written.
    @discardableResult
    func endActiveShift(at date: Date = .now) throws -> Shift {
        guard let shift = try activeShift() else {
            AppLog.shift.notice("Refused to end a shift: none is running")
            throw ShiftLifecycleError.noActiveShift
        }

        // A shift cannot close over work that is still happening. The
        // alternatives were both dishonest: marking the deliveries delivered
        // would record completions the driver never made, and discarding them
        // would erase deliveries they did make. So the end is refused, and the
        // driver resolves each one — delivered or cancelled — first. The rule is
        // checked against the shift's own persisted deliveries rather than
        // against whichever buttons a screen happens to show.
        //
        // Every unfinished delivery blocks, not just the first: with stacked
        // orders, finishing one of three leaves two that still happened.
        let unfinished = shift.activeDeliveries
        if !unfinished.isEmpty {
            AppLog.shift.notice(
                "Refused to end a shift: \(unfinished.count, privacy: .public) deliveries still in progress"
            )
            throw ShiftLifecycleError.activeDeliveriesInProgress(count: unfinished.count)
        }

        // A driver must always be able to end a shift. If the device clock has
        // moved behind the recorded start, ending at the start records a zero
        // length shift, which keeps the ordering truthful and is preferable to
        // leaving the shift open until the clock catches up.
        //
        // An open pause is a second floor for the same reason: a clock that has
        // moved back since the driver paused must not close that pause before it
        // began, which the model would refuse and which would leave a driver
        // unable to end a paused shift at all.
        let earliest = max(
            shift.startedAt,
            max(
                shift.openPause?.startedAt ?? shift.startedAt,
                shift.openRouteSuspension?.startedAt ?? shift.startedAt
            )
        )
        let endDate = max(date, earliest)
        if endDate != date {
            AppLog.shift.warning(
                "End timestamp preceded the shift start, its open pause or its open suspension; clamped forward"
            )
        }

        do {
            // Before the end, and at the same instant: a pause left open on a
            // finished shift would describe a state the app cannot produce, and
            // `lifecycleState` would have to decide which of two stored facts to
            // believe. Closing it here means there is only ever one.
            if shift.openPause != nil {
                try shift.endOpenPause(at: endDate)
                AppLog.shift.info("Ending a paused shift; the pause was closed at the end time")
            }
            // And for the same reason: a suspension left open on a finished
            // shift would describe a state the app cannot produce, and
            // `isRouteSuspended` would have to decide which of two stored facts
            // to believe. A driver who ends a shift from inside a shop is
            // recorded as parked right up to the end, which is what happened.
            if shift.openRouteSuspension != nil {
                try shift.endOpenRouteSuspension(at: endDate)
                AppLog.shift.info("Ending a parked shift; the suspension was closed at the end time")
            }
            try shift.end(at: endDate)
        } catch let error as ShiftError {
            // The end is two mutations now, so a refusal between them would
            // otherwise leave a closed pause in memory that the store does not
            // hold, and the shift reading as resumed rather than paused. Both
            // steps are unreachable through this path, which is exactly why the
            // rollback is cheap insurance rather than a cost.
            context.rollback()
            AppLog.shift.error("Shift rejected the end transition: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }

        do {
            try context.save()
        } catch {
            // Discards the pending end timestamp, and with it the pause
            // closure above: the model must not claim the shift finished when
            // the store does not record it, and must not claim the driver
            // resumed either.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift end: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift ended")
        return shift
    }

    // MARK: Pausing

    /// Pauses the shift in progress.
    ///
    /// ## What pausing is, here
    ///
    /// One row opened on the shift, and nothing else. The shift's `endedAt`
    /// stays `nil`, so it is still the unfinished shift every other part of the
    /// app reads; its earnings, deliveries and route are untouched; and the only
    /// consequence is that the stretch from now until the driver resumes is not
    /// counted as working time and is not recorded as route.
    ///
    /// ## Why deliveries in progress refuse it
    ///
    /// Pausing says the driver stopped working. A delivery that has not reached
    /// a terminal state says they had not. Recording both at once would produce
    /// a shift whose delivery active time overlaps time the app is also claiming
    /// nobody worked, and every figure derived from the pair would be arguing
    /// with itself. The driver resolves each delivery first, delivered or
    /// cancelled, exactly as they do before ending a shift, and the refusal
    /// names how many are open.
    ///
    /// The check is against the shift's own persisted deliveries rather than
    /// against whichever buttons a screen happens to show.
    ///
    /// - Throws: ``ShiftLifecycleError/noActiveShift`` if none is running,
    ///   ``ShiftLifecycleError/shiftAlreadyPaused(pausedAt:)`` if it is already
    ///   paused, ``ShiftLifecycleError/activeDeliveriesBlockPause(count:)`` if
    ///   any delivery is open, or
    ///   ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    @discardableResult
    func pauseActiveShift(at date: Date = .now) throws -> Shift {
        guard let shift = try activeShift() else {
            AppLog.shift.notice("Refused to pause a shift: none is running")
            throw ShiftLifecycleError.noActiveShift
        }

        if let open = shift.openPause {
            AppLog.shift.notice("Refused to pause a shift: it is already paused")
            throw ShiftLifecycleError.shiftAlreadyPaused(pausedAt: open.startedAt)
        }

        let unfinished = shift.activeDeliveries
        if !unfinished.isEmpty {
            AppLog.shift.notice(
                "Refused to pause a shift: \(unfinished.count, privacy: .public) deliveries still in progress"
            )
            throw ShiftLifecycleError.activeDeliveriesBlockPause(count: unfinished.count)
        }

        // A driver must always be able to pause. A device clock behind the
        // recorded start would otherwise refuse the transition; clamping records
        // a pause that begins with the shift, which keeps the ordering truthful.
        let pauseDate = max(date, shift.startedAt)
        if pauseDate != date {
            AppLog.shift.warning("Pause timestamp preceded the shift start; clamped to the start time")
        }

        let pause: ShiftPause
        do {
            // A driver who pauses from inside a shop has stopped working, which
            // outranks being parked: the suspension closes at the same instant,
            // so the shift is paused rather than both. Route capture is already
            // stopped by either state, so nothing about the route moves.
            if shift.openRouteSuspension != nil {
                try shift.endOpenRouteSuspension(at: pauseDate)
                AppLog.shift.info("Pausing a parked shift; the suspension was closed at the pause time")
            }
            pause = try shift.beginPause(at: pauseDate)
        } catch let error as ShiftError {
            context.rollback()
            AppLog.shift.error("Shift rejected the pause transition: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }
        context.insert(pause)

        do {
            try context.save()
        } catch {
            // Discards the pending pause: the shift must not read as paused
            // while the store still holds it running. The caller reconciles
            // route capture afterwards either way, so capture comes back to
            // whatever the store actually says.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift pause: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift paused")
        return shift
    }

    /// Resumes the paused shift.
    ///
    /// Closes the open pause. Route capture is the caller's to reconcile
    /// afterwards, and it necessarily starts a **new capture session**: nothing
    /// was recorded across the pause, so nothing may be measured across it
    /// either.
    ///
    /// - Throws: ``ShiftLifecycleError/noActiveShift`` if none is running,
    ///   ``ShiftLifecycleError/shiftNotPaused`` if it is not paused, or
    ///   ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    @discardableResult
    func resumeActiveShift(at date: Date = .now) throws -> Shift {
        guard let shift = try activeShift() else {
            AppLog.shift.notice("Refused to resume a shift: none is running")
            throw ShiftLifecycleError.noActiveShift
        }

        guard let pause = shift.openPause else {
            AppLog.shift.notice("Refused to resume a shift: it is not paused")
            throw ShiftLifecycleError.shiftNotPaused
        }

        // Same rule as ending: a driver must always be able to resume, so a
        // clock that has moved behind the pause records a pause of zero length
        // rather than leaving the shift stuck paused until it catches up.
        let resumeDate = max(date, pause.startedAt)
        if resumeDate != date {
            AppLog.shift.warning("Resume timestamp preceded the pause start; clamped to the pause start")
        }

        do {
            try shift.endOpenPause(at: resumeDate)
        } catch let error as ShiftError {
            context.rollback()
            AppLog.shift.error("Shift rejected the resume transition: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }

        do {
            try context.save()
        } catch {
            // Discards the pending resume: the shift must not read as running
            // while the store still holds it paused, which would leave capture
            // recording against a shift the driver has not resumed.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift resume: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift resumed")
        return shift
    }

    // MARK: Parked for a pickup

    /// Records that the driver has parked and is walking away from the vehicle.
    ///
    /// ## What this is, and what it deliberately is not
    ///
    /// One row opened on the shift, and nothing else. The shift keeps running:
    /// `endedAt` stays `nil`, its working duration keeps growing, every rate it
    /// will produce keeps the denominator it had, its deliveries keep their own
    /// lifecycles and their timers keep counting. **Shopping is working**, and a
    /// driver inside a shop collecting an order is doing the job.
    ///
    /// The one consequence is to the **route**: the caller reconciles capture
    /// afterwards, which stops it, and resuming necessarily starts a **new
    /// capture session**. Nothing is recorded across the stretch, so nothing may
    /// be measured across it either, and ``RouteMileageCalculator`` counts it as
    /// the gap it is rather than drawing a line from the parking space to
    /// wherever the driver pulls away. **No sample is deleted and no distance is
    /// invented.**
    ///
    /// ## Why a paused shift refuses it
    ///
    /// Pausing says the driver stopped working; parking says they are working on
    /// foot. Recording both would be the app claiming two things about the same
    /// minutes. The driver resumes the shift first, which is one tap and which
    /// they have to make anyway before any delivery can move.
    ///
    /// ## Stacked deliveries do not enter into it
    ///
    /// There is no check against how many deliveries are open, in either
    /// direction, and that is the design rather than an omission. Whether the
    /// vehicle is moving is a fact about the driver and their vehicle: a driver
    /// shopping for one order while carrying another has one vehicle and it is
    /// parked. So there is at most one suspension at a time, it belongs to the
    /// shift, and no delivery starts, ends or owns one.
    ///
    /// - Throws: ``ShiftLifecycleError/noActiveShift`` if none is running,
    ///   ``ShiftLifecycleError/shiftAlreadyParked(parkedAt:)`` if the vehicle is
    ///   already recorded as parked,
    ///   ``ShiftLifecycleError/shiftAlreadyPaused(pausedAt:)`` if the shift is
    ///   paused, or ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the
    ///   write fails.
    @discardableResult
    func parkActiveShift(at date: Date = .now) throws -> Shift {
        guard let shift = try activeShift() else {
            AppLog.shift.notice("Refused to record parking: no shift is running")
            throw ShiftLifecycleError.noActiveShift
        }

        if let paused = shift.openPause {
            AppLog.shift.notice("Refused to record parking: the shift is paused")
            throw ShiftLifecycleError.shiftAlreadyPaused(pausedAt: paused.startedAt)
        }

        if let open = shift.openRouteSuspension {
            AppLog.shift.notice("Refused to record parking: the shift is already parked")
            throw ShiftLifecycleError.shiftAlreadyParked(parkedAt: open.startedAt)
        }

        // A driver must always be able to say they have parked, for the reason
        // they must always be able to pause: a device clock behind the recorded
        // start would otherwise refuse the transition.
        let parkDate = max(date, shift.startedAt)
        if parkDate != date {
            AppLog.shift.warning("Parked timestamp preceded the shift start; clamped to the start time")
        }

        let suspension: RouteSuspension
        do {
            suspension = try shift.beginRouteSuspension(at: parkDate)
        } catch let error as ShiftError {
            context.rollback()
            AppLog.shift.error(
                "Shift rejected the parked transition: \(String(describing: error), privacy: .public)"
            )
            throw ShiftLifecycleError.invalidTransition(error)
        }
        context.insert(suspension)

        do {
            try context.save()
        } catch {
            // Discards the pending row: the shift must not read as parked while
            // the store still holds it recording. The caller reconciles capture
            // afterwards either way, so capture comes back to whatever the store
            // actually says.
            context.rollback()
            AppLog.shift.error("Failed to persist a route suspension: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift recorded as parked; route capture stops")
        return shift
    }

    /// Records that the driver is driving again.
    ///
    /// Closes the open suspension. Route capture is the caller's to reconcile
    /// afterwards, and it necessarily starts a **new capture session**: nothing
    /// was recorded across the stretch, so nothing may be measured across it.
    ///
    /// **Only a driver ever calls this.** Nothing in DashPilot resumes a
    /// suspension because a speed changed, because a position moved or because a
    /// delivery advanced. A rule that guessed would be the app deciding a driver
    /// had returned to their car, and the cost of guessing wrong is a walk
    /// recorded as vehicle mileage.
    ///
    /// - Throws: ``ShiftLifecycleError/noActiveShift`` if none is running,
    ///   ``ShiftLifecycleError/shiftNotParked`` if the vehicle is not recorded as
    ///   parked, or ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the
    ///   write fails.
    @discardableResult
    func resumeDrivingOnActiveShift(at date: Date = .now) throws -> Shift {
        guard let shift = try activeShift() else {
            AppLog.shift.notice("Refused to resume driving: no shift is running")
            throw ShiftLifecycleError.noActiveShift
        }

        guard let suspension = shift.openRouteSuspension else {
            AppLog.shift.notice("Refused to resume driving: the shift is not parked")
            throw ShiftLifecycleError.shiftNotParked
        }

        // Clamped forward for the reason the pause resume is: a clock that moved
        // back since the driver parked must not close the row before it began,
        // which would leave a driver unable to resume at all.
        let resumeDate = max(date, suspension.startedAt)
        if resumeDate != date {
            AppLog.shift.warning("Driving timestamp preceded the recorded parking; clamped to it")
        }

        do {
            try shift.endOpenRouteSuspension(at: resumeDate)
        } catch let error as ShiftError {
            context.rollback()
            AppLog.shift.error(
                "Shift rejected the driving transition: \(String(describing: error), privacy: .public)"
            )
            throw ShiftLifecycleError.invalidTransition(error)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.shift.error("Failed to persist the end of a route suspension: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift recording again after parking; a new capture session opens")
        return shift
    }

    // MARK: Deletion

    /// Deletes a completed shift and everything recorded against it.
    ///
    /// Deletion lives here, beside the transitions, because the rule it has to
    /// keep is a lifecycle rule: **a shift that is still running cannot be
    /// deleted.** Deleting one would leave capture recording against a shift the
    /// store no longer holds, and would take the driver's current work with it.
    /// The rule is enforced against the model rather than by which button a
    /// screen happens to show, so a wrong navigation state cannot destroy a
    /// running shift.
    ///
    /// The shift's deliveries and pauses go with it through their `.cascade`
    /// delete rules. **Its route samples are deleted here, explicitly**, and
    /// that is the substantive part of this method rather than an
    /// implementation detail: `Shift` holds no collection of its route, so
    /// there is no cascade to carry the positions away, and nothing else in the
    /// app would. The orphans would be exactly the sensitive rows the app
    /// promises to keep accountable to a shift, so leaving them is the one
    /// outcome this method exists to prevent. ``DashPilotSchemaV10`` says why
    /// the collection is gone.
    ///
    /// **It is one transaction.** The route rows are marked deleted, then the
    /// shift, then a single save. A store that refuses the write leaves the
    /// shift *and* its whole route, and there is no ordering in which a shift
    /// disappears while its positions survive or the reverse. Deleting the rows
    /// in their own save first would create exactly that window.
    ///
    /// The rows are fetched and deleted rather than removed with a batch
    /// delete. A batch delete runs in the store beneath the context, so it
    /// cannot be rolled back and cannot be part of the same transaction as
    /// removing the shift, which is the whole guarantee above.
    ///
    /// - Throws: ``ShiftLifecycleError/cannotDeleteActiveShift`` if the shift has
    ///   not finished, or ``ShiftLifecycleError/storeUnavailable(underlying:)``
    ///   if the delete cannot be written.
    func deleteCompletedShift(_ shift: Shift) throws {
        guard !shift.isActive else {
            AppLog.shift.notice("Refused to delete a shift: it is still running")
            throw ShiftLifecycleError.cannotDeleteActiveShift
        }

        let shiftID = shift.id
        do {
            let route = try context.fetch(
                FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == shiftID })
            )
            for sample in route { context.delete(sample) }
        } catch {
            // Nothing has been marked deleted yet, so there is nothing to roll
            // back. Refusing is the only safe answer: deleting the shift now
            // would leave its positions behind with no shift to account for
            // them.
            AppLog.shift.error("Failed to read a completed shift's route before deleting it: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        context.delete(shift)
        do {
            try context.save()
        } catch {
            // Puts the shift and its route back: a delete the store refused must
            // not leave the interface showing a history the store still holds.
            context.rollback()
            AppLog.shift.error("Failed to delete a completed shift: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only. Not when the shift ran, not what it earned, not how
        // far it went — a deletion is the last moment to start writing a
        // driver's history into the log.
        AppLog.shift.info("Completed shift deleted with its route samples and deliveries")
    }

    // MARK: Earnings

    /// Records what a completed shift paid, replacing any amount already stored.
    ///
    /// The model enforces the invariants (completed only, never negative); this
    /// adds the store write and the same rollback rule the lifecycle
    /// transitions use, so an amount can never be showing in the interface
    /// while the store holds something else.
    ///
    /// - Throws: ``ShiftLifecycleError/invalidTransition(_:)`` if the shift or
    ///   the amount is not one earnings can be recorded against, or
    ///   ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    func setGrossEarnings(_ earnings: Money, on shift: Shift) throws {
        // Read before the write, so the log can say what happened without ever
        // holding the amount that happened to it.
        let isFirstAmount = shift.grossEarnings == nil

        do {
            try shift.setGrossEarnings(earnings)
        } catch let error as ShiftError {
            AppLog.earnings.error("Shift rejected recorded earnings: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }

        try save(describing: isFirstAmount ? "add" : "update")
        AppLog.earnings.info("Shift earnings \(isFirstAmount ? "recorded" : "updated", privacy: .public)")
    }

    /// Removes a shift's recorded earnings, returning it to having none.
    ///
    /// Distinct from recording zero: afterwards the shift is a shift with no
    /// amount entered, which is what it was before the driver typed one.
    ///
    /// - Throws: ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    func clearGrossEarnings(on shift: Shift) throws {
        shift.clearGrossEarnings()
        try save(describing: "remove")
        AppLog.earnings.info("Shift earnings removed")
    }

    // MARK: Fuel assumptions

    /// Records the fuel economy and gas price this shift's fuel estimate is
    /// worked out under, replacing whatever it recorded before.
    ///
    /// **The whole edit is one write.** ``Shift/setFuelAssumptions(milesPerGallon:gasPricePerGallon:vehicleName:)``
    /// checks both halves before it touches either, and this saves once, so a
    /// refused pair and a refused save both leave the shift with exactly the
    /// assumptions it already had. There is no state in which a driver's fuel
    /// economy moved and their gas price did not.
    ///
    /// Nothing derived is written. The estimated gallons and the estimated cost
    /// are read from the route and this pair whenever they are shown, so they
    /// cannot be left describing assumptions the shift no longer holds.
    ///
    /// **This creates no expense.** An estimate is not a cost the driver
    /// recorded paying, and nothing here inserts, reads or changes an
    /// ``Expense``.
    ///
    /// - Throws: ``ShiftLifecycleError/invalidTransition(_:)`` when the model
    ///   refuses the pair, or
    ///   ``ShiftLifecycleError/storeUnavailable(underlying:)`` when the write
    ///   fails.
    func setFuelAssumptions(
        milesPerGallon: Decimal?,
        gasPricePerGallon: Money?,
        vehicleName: String? = nil,
        on shift: Shift
    ) throws {
        // Read before the write, so the log can say what happened without ever
        // holding the figures it happened to.
        let isFirstRecording = !shift.fuelAssumptions.hasAny

        do {
            try shift.setFuelAssumptions(
                milesPerGallon: milesPerGallon,
                gasPricePerGallon: gasPricePerGallon,
                vehicleName: vehicleName
            )
        } catch let error as ShiftError {
            AppLog.fuel.error("Shift rejected fuel assumptions: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }

        try saveFuel(describing: isFirstRecording ? "add" : "update")
        AppLog.fuel.info("Shift fuel assumptions \(isFirstRecording ? "recorded" : "updated", privacy: .public)")
    }

    /// Removes a shift's fuel assumptions, returning it to having none.
    ///
    /// Distinct from recording zero: afterwards the shift has no estimate at
    /// all, which is what it had before the driver typed anything, rather than
    /// an estimate of `$0.00`.
    ///
    /// - Throws: ``ShiftLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    func clearFuelAssumptions(on shift: Shift) throws {
        shift.clearFuelAssumptions()
        try saveFuel(describing: "remove")
        AppLog.fuel.info("Shift fuel assumptions removed")
    }

    /// The assumptions the driver most recently recorded, for seeding an editor.
    ///
    /// **This is the whole of what "a current default" means in DashPilot, and
    /// it is deliberately not a stored setting.** The app has no preferences
    /// layer, and adding one for this would put a second, mutable source of
    /// truth beside a store whose rule is that history is derived from recorded
    /// facts. The most recent shift that recorded assumptions is already that
    /// fact, so the default *is* the last pair the driver typed.
    ///
    /// The consequence is the property that matters: **an older shift's estimate
    /// cannot move when a newer one records something different**, because there
    /// is no global figure for it to follow. Seeding a text field is the only
    /// thing this value is ever used for, and a seeded field the driver does not
    /// save writes nothing.
    ///
    /// The most recent shift by ``Shift/startedAt``, which is the ordering every
    /// period, week and history list in the app assigns a shift by. Completed
    /// shifts only, because a running one cannot carry assumptions.
    ///
    /// Returns ``FuelAssumptions/none`` when nothing has been recorded yet, and
    /// on a read failure: a field that could not be seeded is an empty field,
    /// which is the ordinary state of an editor, and is not worth refusing an
    /// edit over.
    func mostRecentFuelAssumptions() -> FuelAssumptions {
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate {
                $0.endedAt != nil
                    && ($0.fuelMilesPerGallonValue != nil || $0.fuelGasPricePerGallonAmount != nil)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first?.fuelAssumptions ?? .none
        } catch {
            AppLog.fuel.error("Failed to read the most recent fuel assumptions: \(error)")
            return .none
        }
    }

    /// Saves a fuel-assumption change, and rolls back if the store refuses.
    ///
    /// Its own saver rather than ``save(describing:)`` so the failure is logged
    /// under the category that describes it. `operation` is a fixed word naming
    /// what was attempted; the figures never are.
    private func saveFuel(describing operation: StaticString) throws {
        do {
            try context.save()
        } catch {
            // The pending pair is discarded: the interface must not show an
            // estimate derived from assumptions the store does not hold.
            context.rollback()
            AppLog.fuel.error("Failed to \(operation, privacy: .public) shift fuel assumptions: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }
    }

    /// Saves, and rolls back if the store refuses.
    ///
    /// `operation` is a fixed word naming what was attempted. It is written to
    /// the log; the amount never is.
    private func save(describing operation: StaticString) throws {
        do {
            try context.save()
        } catch {
            // The pending amount is discarded: the interface must not show a
            // figure the store does not hold.
            context.rollback()
            AppLog.earnings.error("Failed to \(operation, privacy: .public) shift earnings: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }
    }
}

