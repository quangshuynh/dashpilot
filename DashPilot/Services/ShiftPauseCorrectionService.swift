import Foundation
import OSLog
import SwiftData

/// Failures raised when a correction to a recorded pause cannot be applied.
///
/// A thin layer over ``ShiftPauseCorrectionRefusal``: the domain owns which
/// corrections are truthful, and this adds only the three things a store can go
/// wrong with.
nonisolated enum ShiftPauseCorrectionError: Error {
    /// The domain refused the proposed stretch.
    case invalidCorrection(ShiftPauseCorrectionRefusal)
    /// The pause is not, or is no longer, a row the store holds.
    case pauseNoLongerExists
    /// The pause records no shift, which is a store the app cannot produce.
    case pauseNotOnAShift
    /// The local store could not be written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension ShiftPauseCorrectionError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidCorrection(lhsError), .invalidCorrection(rhsError)): lhsError == rhsError
        case (.pauseNoLongerExists, .pauseNoLongerExists): true
        case (.pauseNotOnAShift, .pauseNotOnAShift): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension ShiftPauseCorrectionError: LocalizedError {
    /// Every sentence says **why** the stretch was refused and what would make
    /// it acceptable, rather than only that something was wrong. A driver who is
    /// told "invalid times" has been given the same information twice.
    var errorDescription: String? {
        switch self {
        case .invalidCorrection(.shiftNotCompleted):
            "Pauses can be corrected once the shift has ended."
        case .invalidCorrection(.pauseIsOpen):
            """
            This pause has not ended yet, so it cannot be corrected here. Resume the shift, or end \
            it, and the pause can be corrected afterwards.
            """
        case .invalidCorrection(.notPositiveDuration):
            "A pause has to end after it started. Choose an end time later than the start time."
        case .invalidCorrection(.startsBeforeShift):
            "A pause cannot begin before the shift did. Choose a start time inside the shift."
        case .invalidCorrection(.endsAfterShift):
            "A pause cannot end after the shift did. Choose an end time inside the shift."
        case .invalidCorrection(.overlapsAnotherPause):
            """
            This shift already records a pause covering some of that time. Two pauses cannot overlap: \
            change these times, or delete the other pause first.
            """
        case .invalidCorrection(.overlapsDeliveryWork):
            """
            A delivery was in progress during that time, so the shift cannot also record it as \
            paused. Choose times that do not overlap a delivery.
            """
        case .pauseNoLongerExists:
            "That pause is no longer in DashPilot, so nothing was changed."
        case .pauseNotOnAShift:
            "That pause is not recorded against a shift, so it cannot be corrected."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the pause was not changed."
        }
    }
}

/// Correcting the pauses a driver recorded during a shift that has since ended.
///
/// ## Why this exists
///
/// A pause is two taps made while doing something else, and until this service
/// they were the last recorded facts in the app with no remedy but deleting the
/// whole shift. Everything else a driver records can be corrected: a shift's
/// earnings, a delivery's earnings, an expected amount, a pickup place's name
/// and identity, an expense, which deliveries arrived together, and how a
/// delivery ended. A pause recorded ten minutes late, left running for an hour
/// after the driver got going again, or forgotten entirely, changed the shift's
/// working duration and every hourly figure over it, and the only way out threw
/// away the route, the deliveries and the amounts as well.
///
/// ## What a correction is, and what it is emphatically not
///
/// **It moves two timestamps on one pause row, or removes that row, or adds
/// one.** Nothing else in the store is read for writing. The shift's own start
/// and end do not move, no delivery's lifecycle timestamp moves, no amount
/// moves, and **no route sample is created, deleted, retimed, re-coordinated or
/// moved between capture sessions**. A correction that could not be represented
/// without doing one of those is refused instead; see
/// ``ShiftPauseCorrectionRefusal``.
///
/// **It performs no lifecycle transition.** It never pauses, resumes, starts or
/// stops anything. Core Location is not touched, no capture session is minted or
/// ended, and no Live Activity is requested, updated or ended: the shift it acts
/// on has already finished, so there is no running shift for any of that to be
/// about.
///
/// **Nothing is detected or suggested.** Every timestamp here was typed by the
/// driver. DashPilot observes nothing about why a vehicle stopped moving, so it
/// proposes no pause, completes no interval and fills nothing in.
///
/// ## What moves afterwards, and what does not
///
/// Nothing derived is stored anywhere in this app, so a corrected pause is
/// reflected the next time each figure is read rather than by any invalidation
/// this service performs:
///
/// | Moves | Does not move |
/// | --- | --- |
/// | The shift's paused time and pause count | Its elapsed duration |
/// | Its working duration | Its delivery active time and non-delivery time |
/// | Its gross per working hour | Its gross per delivery active hour and per recorded mile |
/// | Period working hours and the rates over them | Its recorded mileage, route segments and gaps |
/// | The exported `pausedSeconds`, `workingSeconds` and `pauseCount` | Its recorded gross earnings |
///
/// The export contract does not move at all: those three fields already carry
/// exactly this, so a corrected pause exports through them with no field added,
/// removed or redefined and no version change.
///
/// ## One save per correction
///
/// Each operation mutates and commits exactly once, and a refused save rolls the
/// context back, so the store holds precisely the pause set it held before. The
/// caller must re-read from the store rather than trusting a live object
/// afterwards, which is the SwiftData rollback caveat `AGENTS.md` records and
/// what every refused-save test in this project asserts through a fresh context.
///
/// ## Finished shifts only
///
/// Enforced here **and** by ``ShiftPauseCorrection``, rather than by which
/// screen presents a control. Two reasons, and both are rules rather than
/// conveniences. The live pause of a paused shift is Resume's and End's alone,
/// because those reconcile route capture and the Live Activity as they close it
/// and this does neither; and choosing two timestamps from two pickers is the
/// sustained-attention typing this app deliberately keeps away from a driver who
/// may be at a wheel.
///
/// `@MainActor` isolated like every other service here: operations run to
/// completion without suspending, so no caller interleaves a read with the write
/// that follows it.
@MainActor
struct ShiftPauseCorrectionService {
    private let context: ModelContext

    /// How a change is handed to the store. Injectable for the reason
    /// ``OfferCorrectionService``'s is: every claim here about what a refused
    /// save leaves behind is untestable while the save can only succeed.
    private let commit: (ModelContext) throws -> Void

    init(context: ModelContext, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.commit = commit
    }

    // MARK: Correcting one pause

    /// Rewrites when `pause` started and ended.
    ///
    /// The one operation behind all three of "the start was wrong", "the end was
    /// wrong" and "both were wrong": the driver always supplies both timestamps,
    /// and an end left where it was is simply passed back unchanged. A single
    /// path means a correction to one end is checked against exactly the same
    /// rules as a correction to both.
    ///
    /// - Throws: ``ShiftPauseCorrectionError``.
    func correct(_ pause: ShiftPause, from startedAt: Date, to endedAt: Date) throws {
        let shift = try shift(of: pause)

        let correction = try proposed(on: shift, from: startedAt, to: endedAt, replacing: pause)
        do {
            try pause.apply(correction)
        } catch let error as ShiftPauseCorrectionRefusal {
            // Nothing has been mutated: the model checks before it assigns.
            AppLog.shift.notice(
                "Refused a pause correction: \(String(describing: error), privacy: .public)"
            )
            throw ShiftPauseCorrectionError.invalidCorrection(error)
        }

        try save(describing: "correct a recorded pause")

        // Structural only, and deliberately without the durations. A pause is a
        // statement about a driver's day — when they eat, how long their breaks
        // run — which is why `AppLog.shift` has never recorded when one
        // happened, and correcting one is not the moment to start.
        AppLog.shift.info("A recorded pause was corrected")
    }

    // MARK: Deleting a pause

    /// Removes a pause the driver recorded by mistake.
    ///
    /// The claim it records is "I was never paused then", which is why the row
    /// is deleted rather than shortened to nothing: a zero-length pause is still
    /// a pause the shift counts, and a shift that reports `1 pause` of no length
    /// says something the driver did not mean.
    ///
    /// **The shift's own timestamps do not move**, and neither does its route.
    /// A pause recorded live left a real gap in the route, and that gap stays:
    /// nothing was recorded across it, so nothing may be measured across it, and
    /// reconnecting the capture sessions would invent distance the app never
    /// observed. The shift's working duration grows by the deleted pause's
    /// contribution, because that stretch is no longer subtracted.
    ///
    /// One transaction: the row is marked deleted and a single save follows, so
    /// a store that refuses the write leaves the pause exactly where it was.
    ///
    /// - Throws: ``ShiftPauseCorrectionError``.
    func delete(_ pause: ShiftPause) throws {
        try requireRecorded(pause)

        // The live pause is not deletable either. Deleting the row a paused
        // shift is currently in would leave `lifecycleState` reporting a shift
        // as running while capture is stopped and the Live Activity still says
        // `Shift Paused`, which is precisely the state Resume exists to leave
        // properly.
        guard !pause.isOpen else {
            AppLog.shift.notice("Refused to delete a pause: it has not ended")
            throw ShiftPauseCorrectionError.invalidCorrection(.pauseIsOpen)
        }
        guard try shift(of: pause).isActive == false else {
            AppLog.shift.notice("Refused to delete a pause: its shift has not ended")
            throw ShiftPauseCorrectionError.invalidCorrection(.shiftNotCompleted)
        }

        context.delete(pause)
        try save(describing: "delete a recorded pause")

        AppLog.shift.info("A recorded pause was deleted")
    }

    // MARK: Adding a pause that was not recorded

    /// Records a pause the driver took and did not record at the time.
    ///
    /// Both timestamps are the driver's, and the stretch is checked against the
    /// shift exactly as a correction to an existing pause is: inside the shift,
    /// positive, not overlapping another pause, and not overlapping a stretch a
    /// delivery was open for.
    ///
    /// ## Why this is truthful, and what it leaves inconsistent
    ///
    /// A ``ShiftPause`` records **when the driver says they were paused**, and
    /// that is the whole of its claim: the type has never asserted that anything
    /// was observed during one, because nothing is. A pause the driver enters
    /// afterwards makes the same claim about the same kind of fact, and the
    /// shift's working duration — elapsed less the union of its pauses — stays
    /// exactly as true as it was.
    ///
    /// What it does **not** do is make the route look as though the shift had
    /// been paused at the time. Capture was running, so positions recorded
    /// during that stretch are still there and still counted in the shift's
    /// recorded mileage. That is deliberate and is the alternative to the two
    /// dishonest repairs: deleting real positions, or claiming a gap that never
    /// happened. A shift can therefore record mileage inside a stretch it also
    /// records as paused, which the completed shift's route footer states
    /// plainly rather than smoothing over.
    ///
    /// - Returns: the pause now recorded.
    /// - Throws: ``ShiftPauseCorrectionError``.
    @discardableResult
    func addMissedPause(on shift: Shift, from startedAt: Date, to endedAt: Date) throws -> ShiftPause {
        let correction = try proposed(on: shift, from: startedAt, to: endedAt, replacing: nil)

        let pause = shift.addMissedPause(correction)
        // Inserted explicitly rather than left to the inverse relationship, for
        // the reason `ShiftService` inserts a live pause explicitly: a failed
        // save must roll back exactly what this call put in.
        context.insert(pause)
        try save(describing: "record a pause that was not recorded at the time")

        AppLog.shift.info("A pause the driver did not record at the time was added")
        return pause
    }

    // MARK: Asking without writing

    /// What the driver's proposed stretch would be refused for, or `nil` if it
    /// would be accepted.
    ///
    /// The editor asks this while the pickers move, so the sentence on screen is
    /// written by the same rule the write will consult rather than by a second
    /// opinion about it. It mutates nothing and saves nothing.
    func refusal(
        correcting pause: ShiftPause?,
        on shift: Shift,
        from startedAt: Date,
        to endedAt: Date
    ) -> ShiftPauseCorrectionRefusal? {
        if let pause, pause.isOpen { return .pauseIsOpen }
        do {
            _ = try shift.pauseCorrection(from: startedAt, to: endedAt, replacing: pause)
            return nil
        } catch let refusal as ShiftPauseCorrectionRefusal {
            return refusal
        } catch {
            return .shiftNotCompleted
        }
    }

    // MARK: Writing

    private func proposed(
        on shift: Shift,
        from startedAt: Date,
        to endedAt: Date,
        replacing pause: ShiftPause?
    ) throws -> ShiftPauseCorrection {
        do {
            return try shift.pauseCorrection(from: startedAt, to: endedAt, replacing: pause)
        } catch let error as ShiftPauseCorrectionRefusal {
            AppLog.shift.notice(
                "Refused a pause correction: \(String(describing: error), privacy: .public)"
            )
            throw ShiftPauseCorrectionError.invalidCorrection(error)
        }
    }

    /// Saves a correction, and rolls back if the store refuses.
    ///
    /// `operation` is a fixed word naming what was attempted, typed as a
    /// `StaticString` so nothing a driver recorded can become the value.
    private func save(describing operation: StaticString) throws {
        do {
            try commit(context)
        } catch {
            // The whole correction is discarded: the interface must not show a
            // pause the store does not hold, and a working duration derived from
            // one must never outlive the call that attempted it.
            context.rollback()
            AppLog.shift.error("Failed to \(operation, privacy: .public): \(error)")
            throw ShiftPauseCorrectionError.storeUnavailable(underlying: error)
        }
    }

    /// The shift this pause belongs to, once it is established that the row is
    /// one the store still holds.
    private func shift(of pause: ShiftPause) throws -> Shift {
        try requireRecorded(pause)
        guard let shift = pause.shift else {
            // A pause attached to no shift is a store the app cannot produce,
            // which is why this is a fault rather than an ordinary refusal.
            AppLog.shift.fault("Refused a pause correction: the pause is attached to no shift")
            throw ShiftPauseCorrectionError.pauseNotOnAShift
        }
        return shift
    }

    /// Whether this row is still one the store holds.
    ///
    /// A view can hold a pause across a sheet dismissal, another screen's
    /// deletion or its own correction, so an object arriving here is not proof
    /// of a row. Checked before anything is mutated, for the reason
    /// ``OfferCorrectionService`` checks: a half-applied correction is worse than
    /// a refused one.
    private func requireRecorded(_ pause: ShiftPause) throws {
        guard pause.modelContext != nil, !pause.isDeleted else {
            AppLog.shift.notice("Refused a pause correction: the pause is not in the store")
            throw ShiftPauseCorrectionError.pauseNoLongerExists
        }
    }
}
