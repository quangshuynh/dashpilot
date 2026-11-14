import Foundation
import OSLog
import SwiftData

/// Failures raised when a correction to a completed shift's end cannot be
/// applied.
///
/// A thin layer over ``ShiftEndCorrectionRefusal``: the domain owns which
/// corrections are truthful, and this adds only what a store can go wrong with.
nonisolated enum ShiftEndCorrectionError: Error {
    /// The domain refused the proposed end.
    case invalidCorrection(ShiftEndCorrectionRefusal)
    /// The shift is not, or is no longer, a row the store holds.
    case shiftNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension ShiftEndCorrectionError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidCorrection(lhsError), .invalidCorrection(rhsError)): lhsError == rhsError
        case (.shiftNoLongerExists, .shiftNoLongerExists): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension ShiftEndCorrectionError: LocalizedError {
    /// Every sentence says **why** the instant was refused and what would make
    /// it acceptable, rather than only that something was wrong. A driver who is
    /// told "invalid time" has been given the same information twice.
    var errorDescription: String? {
        switch self {
        case .invalidCorrection(.shiftNotCompleted):
            "A shift's end time can be corrected once the shift has ended."
        case .invalidCorrection(.notAfterShiftStart):
            "A shift has to end after it started. Choose a time later than the time this shift began."
        case .invalidCorrection(.inFuture):
            "That time has not happened yet. Choose an end time no later than now."
        case .invalidCorrection(.pauseIsOpen):
            """
            This shift records a pause that was never ended, so moving its end time would change how \
            long it was paused for. That pause has to be sorted out first.
            """
        case .invalidCorrection(.cutsThroughRecordedPause):
            """
            This shift records a pause that ends after that time, and a pause has to be inside the \
            shift. Correct or delete that pause first, or choose a later end time.
            """
        case .invalidCorrection(.routeSuspensionIsOpen):
            """
            This shift records a stretch parked that was never ended, so moving its end time would \
            change how much of its route is accounted for. That has to be sorted out first.
            """
        case .invalidCorrection(.cutsThroughRecordedRouteSuspension):
            """
            This shift records a stretch parked that ends after that time, and it explains a gap in \
            the shift's route. Choose a later end time.
            """
        case let .invalidCorrection(.precedesRecordedDeliveryWork(event)):
            """
            \(event.deliveryTitle) has \(event.eventTitle) recorded at \
            \(event.occurredAt.formatted(date: .omitted, time: .shortened)), after the proposed \
            shift end. Open that delivery and correct its times, or choose a later end time.
            """
        case .invalidCorrection(.overlapsAnotherShift):
            """
            Another shift had already started by then, and two shifts cannot overlap. Choose an end \
            time before that shift began.
            """
        case .shiftNoLongerExists:
            "That shift is no longer in DashPilot, so nothing was changed."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the shift was not changed."
        }
    }
}

/// Correcting the moment a shift the driver has already finished actually
/// ended.
///
/// ## Why this exists
///
/// Every other timestamp in a shift is recorded when the driver taps something,
/// and if they tap late they can correct it: a pause has its own editor, a
/// delivery's completion can be corrected to the cancellation it was, and an
/// amount can be retyped. A shift's **end** could not be corrected at all, and
/// it is the timestamp the app itself is most likely to have recorded wrongly.
/// DashPilot being unreachable in the last minutes of a shift — evicted under
/// memory pressure, crashed, or simply not something a driver will stop to open
/// — means the end lands whenever they next get to it. The shift then reports
/// working time nobody worked, an hourly rate that is too low, and, if capture
/// was still running, mileage from the drive home.
///
/// Until now the only remedy was deleting the whole shift, which threw away its
/// route, its deliveries and its amounts to fix one instant.
///
/// ## What a correction is
///
/// **It writes `Shift.endedAt`, and, when the end moves earlier, it deletes the
/// route samples that then lie outside the shift.** Nothing else in the store is
/// written. The shift's start does not move, so the day, week and period it
/// belongs to are the ones it was already in; no delivery timestamp, amount or
/// tip moves; no pause's timestamps move; and no position at or before the
/// corrected end is created, retimed, re-coordinated or moved between capture
/// sessions.
///
/// **Mileage is measured again, never scaled.** Nothing here multiplies a
/// distance by a ratio of durations. The retained positions are handed to the
/// same ``RouteMileageCalculator`` every other shift is measured by, against the
/// corrected window, and whatever that returns is the shift's recorded mileage.
/// Segments, gaps, the usable sample count and the partial-route wording all
/// follow from the same walk, so a trimmed route cannot report a coverage its
/// positions do not support.
///
/// **No endpoint is invented.** The last retained position is wherever the
/// driver was when it was fixed; nothing is interpolated forward to the corrected
/// end, and the stretch between them is counted as the uncovered stretch it is.
///
/// **A later end fabricates nothing.** No position and no metre is added for the
/// stretch gained. The route simply no longer reaches the shift's end, which the
/// existing walk already counts as a gap and already reports as a partial route.
///
/// **It performs no lifecycle transition.** It never starts, pauses, resumes or
/// ends anything. Core Location is not touched, no capture session is minted or
/// ended, and no Live Activity is requested, updated or ended: the shift it acts
/// on has already finished, so there is no running shift for any of that to be
/// about.
///
/// **Nothing is detected or suggested.** The instant comes from the driver.
/// DashPilot does not infer when they stopped from the last position it holds or
/// the last delivery they completed.
///
/// ## What moves afterwards, and what does not
///
/// Nothing derived is stored anywhere in this app, so a corrected end is
/// reflected the next time each figure is read rather than by any invalidation
/// this service performs:
///
/// | Moves | Does not move |
/// | --- | --- |
/// | The shift's elapsed and working duration | Its recorded gross earnings |
/// | Its three rates | Every delivery's timestamps, amounts and tips |
/// | Its recorded mileage, segments, gaps and usable sample count | Every recorded pause's timestamps |
/// | Its paused time, where a pause was clipped by the old window | Which day, week or period it belongs to |
/// | Period working hours, mileage and the rates over them | Its delivery active time, unless the old window clipped it |
/// | The exported `endedAt`, `elapsedSeconds`, `workingSeconds` and route figures | The export contract itself |
///
/// The export contract does not move at all: every field above already carries
/// exactly this, so a corrected shift exports through them with no field added,
/// removed or redefined and no version change.
///
/// ## One save per correction
///
/// The route rows are marked deleted, the end is written, and a **single** save
/// follows. A store that refuses the write leaves the shift's recorded end *and*
/// its whole route exactly as they were, and there is no ordering in which a
/// shift's end moves while its positions survive or the reverse. Deleting the
/// rows in their own save first would create exactly that window.
///
/// The rows are fetched and deleted rather than removed with a batch delete, for
/// the reason ``ShiftService/deleteCompletedShift(_:)`` fetches them: a batch
/// delete runs in the store beneath the context, so it cannot be rolled back and
/// cannot be part of the same transaction as the end.
///
/// The caller must re-read from the store rather than trusting a live object
/// after a refused save, which is the SwiftData rollback caveat `AGENTS.md`
/// records and what every refused-save test in this project asserts through a
/// fresh context.
///
/// ## Finished shifts only
///
/// Enforced here **and** by ``ShiftEndCorrection``, rather than by which screen
/// presents a control. A running shift is ended by End, which stops capture and
/// reconciles the Live Activity as it closes the shift, and this does neither;
/// and choosing an instant from a picker is the sustained attention this app
/// deliberately keeps away from a driver who may be at a wheel.
///
/// `@MainActor` isolated like every other service here: operations run to
/// completion without suspending, so no caller interleaves a read with the write
/// that follows it.
@MainActor
struct ShiftEndCorrectionService {
    private let context: ModelContext
    private let now: () -> Date

    /// How a change is handed to the store. Injectable for the reason
    /// ``ShiftPauseCorrectionService``'s is: every claim here about what a
    /// refused save leaves behind is untestable while the save can only succeed.
    private let commit: (ModelContext) throws -> Void

    init(
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.now = now
        self.commit = commit
    }

    // MARK: Correcting the end

    /// Rewrites when `shift` ended, and removes the route evidence that a
    /// corrected-earlier end puts outside it.
    ///
    /// **The end-only entry point to ``ShiftTimeCorrectionService``**, which
    /// holds the one write path for a shift's times: the same deletion of the
    /// route beyond the end, the same single save and the same rollback. The
    /// start is passed through unchanged, so it is not judged at all, and every
    /// refusal is the ``ShiftEndCorrection`` rule this service has always
    /// raised.
    ///
    /// - Returns: what was applied, so a caller can say what it did without
    ///   re-deriving it from a model that has already moved.
    /// - Throws: ``ShiftEndCorrectionError``.
    @discardableResult
    func correct(_ shift: Shift, to correctedEnd: Date) throws -> ShiftEndCorrection {
        try requireRecorded(shift)
        let correction = try proposed(on: shift, to: correctedEnd)
        do {
            try ShiftTimeCorrectionService(context: context, now: now, commit: commit)
                .correct(shift, start: shift.startedAt, end: correctedEnd)
        } catch let error as ShiftTimeCorrectionError {
            throw Self.endError(from: error)
        }
        return correction
    }

    /// The end-only vocabulary for a failure the shared service raised.
    ///
    /// A start refusal cannot arise here, because the start does not move and
    /// an unmoved start is not judged; it is reported as the shift not being
    /// correctable rather than trapping.
    private static func endError(from error: ShiftTimeCorrectionError) -> ShiftEndCorrectionError {
        switch error {
        case let .invalidCorrection(.end(refusal)): .invalidCorrection(refusal)
        case .invalidCorrection(.start): .invalidCorrection(.shiftNotCompleted)
        case .shiftNoLongerExists: .shiftNoLongerExists
        case let .storeUnavailable(underlying): .storeUnavailable(underlying: underlying)
        }
    }

    // MARK: Asking without writing

    /// What the driver's proposed end would be refused for, or `nil` if it would
    /// be accepted.
    ///
    /// It mutates nothing and saves nothing. A store that cannot be read
    /// reports ``ShiftEndCorrectionRefusal/shiftNotCompleted``, which withholds
    /// the save.
    func refusal(on shift: Shift, to correctedEnd: Date) -> ShiftEndCorrectionRefusal? {
        do {
            _ = try proposed(on: shift, to: correctedEnd)
            return nil
        } catch ShiftEndCorrectionError.invalidCorrection(let refusal) {
            return refusal
        } catch {
            return .shiftNotCompleted
        }
    }

    /// How many of this shift's retained positions lie after `correctedEnd`, and
    /// would therefore be deleted. Zero for a correction that moves the end
    /// later or leaves it where it is.
    func routeEvidenceCount(on shift: Shift, after correctedEnd: Date) -> Int {
        guard let recordedEnd = shift.endedAt, correctedEnd < recordedEnd else { return 0 }
        return shift.routeSampleCount(after: correctedEnd)
    }

    // MARK: Reading

    /// The proposed correction, with the one fact that is not the shift's own
    /// read from the store.
    private func proposed(on shift: Shift, to correctedEnd: Date) throws -> ShiftEndCorrection {
        let nextStart = try nextShiftStart(after: shift)
        do {
            return try shift.endCorrection(to: correctedEnd, nextShiftStartedAt: nextStart, now: now())
        } catch let error as ShiftEndCorrectionRefusal {
            AppLog.shift.notice(
                "Refused a shift end correction: \(error.logDescription, privacy: .public)"
            )
            throw ShiftEndCorrectionError.invalidCorrection(error)
        }
    }

    /// When the next shift recorded after this one began, or `nil` if this is
    /// the most recent. Finished or running: a shift that has started is a
    /// shift whose minutes are spoken for.
    private func nextShiftStart(after shift: Shift) throws -> Date? {
        let startedAt = shift.startedAt
        let shiftID = shift.id
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.startedAt >= startedAt && $0.id != shiftID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first?.startedAt
        } catch {
            AppLog.shift.error("Failed to read the shift after the one being corrected: \(error)")
            throw ShiftEndCorrectionError.storeUnavailable(underlying: error)
        }
    }

    /// Whether this row is still one the store holds. A half-applied correction
    /// is worse than a refused one.
    private func requireRecorded(_ shift: Shift) throws {
        guard shift.modelContext != nil, !shift.isDeleted else {
            AppLog.shift.notice("Refused a shift end correction: the shift is not in the store")
            throw ShiftEndCorrectionError.shiftNoLongerExists
        }
    }
}
