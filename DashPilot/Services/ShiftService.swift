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
        case .invalidTransition:
            "That change could not be applied to the shift."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the shift was not changed."
        }
    }
}

/// Start and end transitions for the driver's shift.
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

    /// Ends the shift currently in progress.
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

        // A driver must always be able to end a shift. If the device clock has
        // moved behind the recorded start, ending at the start records a zero
        // length shift, which keeps the ordering truthful and is preferable to
        // leaving the shift open until the clock catches up.
        let endDate = max(date, shift.startedAt)
        if endDate != date {
            AppLog.shift.warning("End timestamp preceded the shift start; clamped to the start time")
        }

        do {
            try shift.end(at: endDate)
        } catch let error as ShiftError {
            AppLog.shift.error("Shift rejected the end transition: \(String(describing: error), privacy: .public)")
            throw ShiftLifecycleError.invalidTransition(error)
        }

        do {
            try context.save()
        } catch {
            // Discards the pending end timestamp: the model must not claim the
            // shift finished when the store does not record it.
            context.rollback()
            AppLog.shift.error("Failed to persist a shift end: \(error)")
            throw ShiftLifecycleError.storeUnavailable(underlying: error)
        }

        AppLog.shift.info("Shift ended")
        return shift
    }
}
