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
            "There is no shift in progress to end."
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
        do {
            try context.save()
        } catch {
            // Leave nothing half-started in memory that the store does not hold.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift start: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift started")
        return shift
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
        let earliest = max(shift.startedAt, shift.openPause?.startedAt ?? shift.startedAt)
        let endDate = max(date, earliest)
        if endDate != date {
            AppLog.shift.warning("End timestamp preceded the shift start or its open pause; clamped forward")
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
    /// The shift's route samples and its deliveries go with it. That is the
    /// relationships' `.cascade` delete rule doing its job rather than a loop
    /// here — a shift's positions and deliveries describe that shift and
    /// nothing else, and the orphans would be exactly the sensitive rows the
    /// app promises to keep accountable to a shift.
    ///
    /// - Throws: ``ShiftLifecycleError/cannotDeleteActiveShift`` if the shift has
    ///   not finished, or ``ShiftLifecycleError/storeUnavailable(underlying:)``
    ///   if the delete cannot be written.
    func deleteCompletedShift(_ shift: Shift) throws {
        guard !shift.isActive else {
            AppLog.shift.notice("Refused to delete a shift: it is still running")
            throw ShiftLifecycleError.cannotDeleteActiveShift
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

