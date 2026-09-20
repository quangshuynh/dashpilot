import Foundation

/// Why a proposed correction to a completed shift's end time cannot be written.
///
/// Each case is a refusal rather than something to repair on the driver's
/// behalf, for the reason ``ShiftPauseCorrectionRefusal``'s are: the facts a
/// corrected end would collide with are facts the driver recorded, and an
/// editor that quietly shortened a delivery, moved a pause or rewrote a second
/// shift to make an instant fit would replace a record they made with one the
/// app invented.
///
/// Every case is a sentence the interface has to be able to write.
nonisolated enum ShiftEndCorrectionRefusal: Error, Equatable, Sendable {
    /// The shift has not ended, so there is no recorded end to correct.
    ///
    /// Correcting an end is a **review** action on a finished shift. A running
    /// shift is ended by End, which stops route capture and reconciles the Live
    /// Activity as it goes, and this does neither.
    case shiftNotCompleted

    /// The proposed end is at or before the shift's own start.
    ///
    /// Zero is refused as well as negative. A shift of no length is not a
    /// correction anybody means to record: it reports no working time, no rate
    /// and no route coverage, and a driver who wants a shift gone is asking to
    /// delete it, which is a different action with its own confirmation.
    case notAfterShiftStart

    /// The shift records a pause the driver never ended.
    ///
    /// A store the app cannot write: ending a shift closes its open pause at the
    /// same instant. Such a pause has no recorded end, so every figure derived
    /// from it is measured to the shift's own end, and moving that end would
    /// silently lengthen or shorten a stretch the driver never touched. Refused
    /// rather than resolved, exactly as the pause editor refuses the same row.
    case pauseIsOpen

    /// The proposed end would leave a recorded pause outside the shift.
    ///
    /// A pause is a stretch **of** the shift, and ``ShiftPauseCorrection``
    /// refuses one reaching past the end for that reason. Moving the end back
    /// through one would create from the other direction exactly the row that
    /// editor will not write. It is refused rather than trimmed: shortening a
    /// pause the driver recorded is rewriting a second fact to accommodate the
    /// first, and the pause editor is where a pause is corrected.
    case cutsThroughRecordedPause

    /// The proposed end precedes a lifecycle event one of the shift's deliveries
    /// records.
    ///
    /// Acceptance, arrival, pickup, completion and cancellation are all
    /// instants the driver recorded, and every one of them happened **during**
    /// the shift that holds the delivery. An end before one of them would put
    /// recorded work outside the shift it belongs to, and the shift's delivery
    /// active time — which clips to the shift's own window — would quietly stop
    /// counting minutes that really were worked.
    ///
    /// Refused rather than resolved, for the reason a pause is refused over a
    /// delivery rather than shortened: nothing here moves a delivery's
    /// timestamps to make a shift boundary fit.
    case precedesRecordedDeliveryWork

    /// The proposed end would reach into a shift recorded after this one.
    ///
    /// A driver cannot work two shifts at once, and two overlapping shifts would
    /// each contribute their whole working duration to the same period, so the
    /// hours a week reports would exceed the hours it held.
    ///
    /// This is a rule about what the editor may **create**, not a claim that no
    /// store holds an overlap, exactly as ``ShiftPauseCorrectionRefusal/overlapsAnotherPause``
    /// is. Nothing here repairs a pair that already overlaps.
    case overlapsAnotherShift
}

nonisolated extension ShiftEndCorrectionRefusal {
    /// Every case, for the suites that assert each one has a sentence.
    ///
    /// Written out rather than synthesised by `CaseIterable`, which this enum
    /// could adopt today and could not keep if a case ever carried a value.
    static let allCases: [Self] = [
        .shiftNotCompleted,
        .notAfterShiftStart,
        .pauseIsOpen,
        .cutsThroughRecordedPause,
        .precedesRecordedDeliveryWork,
        .overlapsAnotherShift
    ]
}

/// One instant a driver is proposing to record as the moment a finished shift
/// ended, checked against everything else that shift already records.
///
/// ## What this corrects
///
/// A shift's end is recorded by tapping End, and it is the one lifecycle
/// timestamp a driver can be prevented from recording at the right moment by
/// the app itself. If DashPilot is killed under memory pressure, crashes, or is
/// simply not reachable in the last minutes of a shift, the end is recorded
/// whenever the driver next gets to it — which may be long after they actually
/// stopped working. Every hourly figure the app derives divides by a duration
/// that boundary defines, so a shift ending twenty minutes late reports twenty
/// minutes of work that did not happen and an hourly rate that is too low.
///
/// ## What a correction changes, and what it must not
///
/// It writes **`Shift.endedAt`**, and, when the end moves **earlier**, it
/// removes the route evidence that then lies outside the shift. Nothing else in
/// the store is written:
///
/// | Unchanged by every correction here |
/// | --- |
/// | `Shift.startedAt`, so the period, week and day the shift belongs to do not move |
/// | The shift's recorded gross earnings |
/// | Every delivery's lifecycle timestamps, amounts, tips and terminal state |
/// | Every recorded pause's two timestamps |
/// | Every retained route sample at or before the corrected end: its coordinate, its timestamp and its capture session |
///
/// Everything derived from the boundary moves, because everything derived from
/// it is recomputed rather than stored: the shift's elapsed duration, its
/// working duration, its paused time where a pause is clipped by the window, its
/// three rates, its recorded mileage and route coverage, and the period
/// aggregates that sum those.
///
/// ## Mileage is re-measured, never scaled
///
/// **No distance is ever derived from a duration here.** A shift shortened by a
/// fifth does not lose a fifth of its miles: the route is measured again, by
/// ``RouteMileageCalculator``, from the positions that remain and against the
/// corrected window, exactly as it is measured for any other shift. What the
/// correction does is decide which positions are still this shift's, and it
/// decides that by their timestamps alone.
///
/// No endpoint is invented either. A shift corrected to end at 9:20 PM whose
/// last retained position was fixed at 9:07 PM keeps that position as its last
/// one; nothing is interpolated to the boundary, and the thirteen minutes
/// between them are counted as the uncovered stretch they are.
///
/// ## Moving the end later adds no route and no miles
///
/// Nothing is fabricated for the added stretch. The existing route model already
/// has the vocabulary for it: a route that stops well before its shift ends
/// counts that as a gap, which makes the distance partial, and the detail
/// screen already says a partial distance is a floor. So a shift extended past
/// its recorded route reports the same metres it always did, with one more
/// uncovered stretch and the partial wording that follows from it. The
/// limitation is expressed rather than papered over.
///
/// ## What it is not
///
/// Not detection. Nothing here infers when a driver stopped from a stationary
/// stretch, the last recorded position, or the last delivery they completed:
/// DashPilot observes nothing about why a vehicle stopped, and an end it guessed
/// at would rewrite the shift the driver recorded. The instant this type accepts
/// was typed by the driver on purpose.
///
/// Not a general timestamp correction either. The shift's **start** is not
/// editable here, and neither is any delivery event: those are different facts
/// with different collisions, and one editor that moved any of them would be
/// four corrections wearing one name.
nonisolated struct ShiftEndCorrection: Equatable, Sendable {
    /// The end the shift records now.
    let recordedEnd: Date

    /// The end the driver is correcting it to.
    let correctedEnd: Date

    /// Whether the correction moves the end back in time, which is the only
    /// direction that takes route evidence out of the shift.
    var movesEarlier: Bool { correctedEnd < recordedEnd }

    /// Whether the correction moves the end forward in time.
    var movesLater: Bool { correctedEnd > recordedEnd }

    /// How far the end moves, always positive. Zero for a correction that
    /// re-records the end it already had, which is accepted and writes the same
    /// facts back.
    var movement: TimeInterval { abs(correctedEnd.timeIntervalSince(recordedEnd)) }

    /// The instant route evidence must not lie after once this is applied, or
    /// `nil` when the correction takes nothing out of the shift.
    ///
    /// `nil` for a correction that moves the end later or leaves it where it is.
    /// Capture is judged against the shift's end as positions arrive, so a shift
    /// holds nothing after the end it recorded and a later end can have nothing
    /// to remove.
    var routeTrimBoundary: Date? { movesEarlier ? correctedEnd : nil }

    /// Checks a proposed end against a shift's own recorded facts.
    ///
    /// The parameters are plain values rather than a `Shift`, so every rule
    /// below is testable without a store, a container or a rendered view.
    /// ``Shift/endCorrection(to:nextShiftStartedAt:)`` is the adapter that reads
    /// the model into it, and it is the only thing that knows how to gather
    /// these.
    ///
    /// - Parameters:
    ///   - correctedEnd: the instant the driver proposes.
    ///   - startedAt: the shift's own start, which does not move.
    ///   - recordedEnd: the end the shift records, or `nil` for a shift that has
    ///     not ended, which is refused.
    ///   - pauses: every pause the shift records. A pause is judged by the
    ///     stretch it states rather than by the stretch it contributes, so a
    ///     malformed row whose end precedes its start is judged by the later of
    ///     the two: that is the instant a corrected window would have to reach
    ///     to still contain it.
    ///   - deliveryEvents: every lifecycle instant the shift's deliveries
    ///     record, in any order. Acceptance is always among them; the rest are
    ///     there when they happened.
    ///   - nextShiftStartedAt: when the next shift recorded after this one
    ///     began, or `nil` if this is the most recent. Running or finished: a
    ///     shift that has started is a shift whose minutes are spoken for.
    /// - Throws: ``ShiftEndCorrectionRefusal``.
    init(
        to correctedEnd: Date,
        startedAt: Date,
        recordedEnd: Date?,
        pauses: [ShiftPauseInterval],
        deliveryEvents: [Date],
        nextShiftStartedAt: Date?
    ) throws {
        guard let recordedEnd else { throw ShiftEndCorrectionRefusal.shiftNotCompleted }
        guard correctedEnd > startedAt else { throw ShiftEndCorrectionRefusal.notAfterShiftStart }

        if let nextShiftStartedAt, correctedEnd > nextShiftStartedAt {
            throw ShiftEndCorrectionRefusal.overlapsAnotherShift
        }

        // Checked before the stretch each pause covers, because an open pause is
        // not a stretch this can reason about at all: its end *is* the shift's
        // end, so every reading of it would move with the correction.
        guard !pauses.contains(where: \.isOpen) else { throw ShiftEndCorrectionRefusal.pauseIsOpen }
        let lastPausedInstant = pauses.compactMap { pause in pause.end.map { max(pause.start, $0) } }.max()
        if let lastPausedInstant, lastPausedInstant > correctedEnd {
            throw ShiftEndCorrectionRefusal.cutsThroughRecordedPause
        }

        if let lastDeliveryEvent = deliveryEvents.max(), lastDeliveryEvent > correctedEnd {
            throw ShiftEndCorrectionRefusal.precedesRecordedDeliveryWork
        }

        self.recordedEnd = recordedEnd
        self.correctedEnd = correctedEnd
    }
}

/// What one end-time correction will do, in the words the driver reads before
/// agreeing to it.
///
/// It lives beside the rule rather than in a view body for the reason
/// ``ShiftPauseDeletionPrompt`` does: the sentence a driver is asked to confirm
/// is the part of a destructive action that most needs testing.
///
/// Nothing here exposes an identifier, a coordinate or a stored row. The route
/// is described by how many positions leave the shift, which is a fact about the
/// shift and not a place.
nonisolated struct ShiftEndCorrectionPrompt: Equatable {
    /// The question.
    let title: String

    /// What will happen, in the order it happens.
    let detail: String

    /// The confirming button, which says what it does rather than "OK".
    let confirmTitle: String

    /// Moving a shift's end earlier, past route the shift recorded.
    ///
    /// Raised only when positions would actually leave the shift. A correction
    /// that removes nothing destroys nothing, and asking a driver to confirm a
    /// deletion that is not happening teaches them to confirm without reading.
    ///
    /// The sentence states the two consequences a driver is least likely to have
    /// in mind: the positions are **deleted**, not hidden, and the mileage is
    /// **measured again** from what is left rather than reduced by the same
    /// proportion as the time.
    ///
    /// - Parameters:
    ///   - positionCount: how many retained positions lie after the corrected
    ///     end. Always at least one.
    ///   - correctedEnd: the new end, already written the way the screen writes
    ///     a time.
    static func trimmingRoute(positionCount: Int, correctedEnd: String) -> Self {
        let positions = positionCount == 1
            ? "1 recorded position"
            : "\(positionCount) recorded positions"
        return Self(
            title: "Remove route recorded after \(correctedEnd)?",
            detail: """
            This shift recorded \(positions) after \(correctedEnd). Ending the shift then means \
            those positions are not part of it, so they are deleted from DashPilot and this shift's \
            recorded mileage is measured again from the positions that remain. The mileage is not \
            reduced by the same share as the time. Everything you recorded at or before \
            \(correctedEnd) is kept, and no amount, delivery or pause changes. This cannot be undone.
            """,
            confirmTitle: "Correct End and Remove"
        )
    }
}
