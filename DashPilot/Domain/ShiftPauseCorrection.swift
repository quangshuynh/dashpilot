import Foundation

/// Why a proposed correction to a recorded pause cannot be written.
///
/// Each case is a refusal rather than something to repair on the driver's
/// behalf, for the reason ``HistoricalCancellationRefusal``'s are: a pause is
/// the driver's own statement about their day, and an editor that quietly moved
/// a timestamp, merged two rows or shortened a delivery to make an interval fit
/// would replace a fact they recorded with one the app invented.
///
/// Every case is a sentence the interface has to be able to write, which is why
/// two of them carry what they collided with.
nonisolated enum ShiftPauseCorrectionRefusal: Error, Equatable, Sendable {
    /// The shift has not ended.
    ///
    /// Pause correction is a **review** action and is offered from a finished
    /// shift's own record, never from the screen a driver reads while they may
    /// be driving. It also keeps ``pauseIsOpen`` from being the only thing
    /// standing between this editor and the live pause: a finished shift has no
    /// open pause at all, because ending one closes it.
    case shiftNotCompleted

    /// The pause has no recorded end, so it is the live one.
    ///
    /// The open pause of a paused shift belongs to Resume and End alone. See
    /// ``ShiftPauseCorrection`` for why that is a rule rather than an omission.
    case pauseIsOpen

    /// The proposed end is at or before the proposed start.
    ///
    /// Zero is refused as well as negative. A pause of no length is not a
    /// correction anybody means to record, and a driver who wants a recorded
    /// pause gone is asking to delete it, which is a different action with its
    /// own confirmation.
    case notPositiveDuration

    /// The proposed start is before the shift began.
    case startsBeforeShift

    /// The proposed end is after the shift ended.
    case endsAfterShift

    /// The proposed stretch overlaps another pause this shift records.
    ///
    /// Refused rather than merged. Two pauses covering the same minutes are one
    /// pause recorded twice, and combining them here would delete a row the
    /// driver can still see without ever asking them. Touching is not
    /// overlapping: a pause that begins exactly where another ended is allowed,
    /// because those are two adjacent breaks rather than two claims about the
    /// same minute.
    case overlapsAnotherPause

    /// The proposed stretch overlaps a stretch a delivery was open for.
    ///
    /// The same fact the live lifecycle already keeps from either direction:
    /// pausing is refused while a delivery is in progress, and starting a
    /// delivery is refused while paused. Without it a shift could report
    /// delivery active time inside hours it also reports as not worked, and
    /// every figure derived from the pair would be arguing with itself.
    ///
    /// It is refused rather than resolved. Moving a delivery's timestamps to fit
    /// a pause would rewrite a second recorded fact to accommodate the first.
    case overlapsDeliveryWork
}

nonisolated extension ShiftPauseCorrectionRefusal {
    /// Every case, for the suites that assert each one has a sentence.
    ///
    /// Written out rather than synthesised by `CaseIterable`, which this enum
    /// could adopt today and could not keep if a case ever carried a value.
    static let allCases: [Self] = [
        .shiftNotCompleted,
        .pauseIsOpen,
        .notPositiveDuration,
        .startsBeforeShift,
        .endsAfterShift,
        .overlapsAnotherPause,
        .overlapsDeliveryWork
    ]
}

/// One stretch a driver is proposing to record as a pause, checked against
/// everything else their shift already records.
///
/// ## What this corrects, and what it refuses to touch
///
/// A pause is two timestamps the driver produced by tapping Pause and Resume,
/// usually while doing something else. They are the easiest facts in the app to
/// record at the wrong moment: pausing on arriving at a restaurant rather than
/// on leaving it, forgetting to resume until the next offer arrives, or
/// forgetting to pause at all. Until now the only remedy was deleting the whole
/// shift, which threw away its route, its deliveries and its earnings to fix one
/// timestamp.
///
/// What a correction changes is **the two timestamps of one pause row**, and
/// nothing else:
///
/// | Unchanged by every correction here |
/// | --- |
/// | `Shift.startedAt` and `Shift.endedAt` |
/// | Every delivery's lifecycle timestamps, amounts and terminal state |
/// | Every `RouteSample`: its coordinate, its timestamp and its capture session |
/// | The shift's recorded gross earnings |
///
/// Everything derived from a pause moves, because everything derived from a
/// pause is recomputed rather than stored: the shift's paused time, its working
/// duration, its gross per working hour, and the period aggregates that sum
/// working durations. Its elapsed duration, its delivery active time, its
/// recorded mileage and its gross earnings do not move, because none of them
/// reads a pause.
///
/// ## Why the live pause is not editable here
///
/// A pause with no end is the state the driver is **in**. It is ended by
/// resuming or by ending the shift, both of which reconcile route capture and
/// the Live Activity as they go, and an editor that closed it would have to
/// repeat all of that or leave capture stopped on a shift the store now says is
/// running. So the editor refuses an open pause outright, and refuses a running
/// shift before it ever gets that far. A driver who mis-tapped a pause they are
/// still in resumes out of it; the row is then a completed pause like any other
/// and this corrects it once the shift has ended.
///
/// ## Why overlap is refused rather than merged
///
/// ``ShiftPausedTimeCalculator`` unions pauses rather than adding them, so a
/// store holding two overlapping rows is still measured correctly and always
/// will be: that defence is for data the app did not write, and this type does
/// not weaken it. What this refuses is **creating** an overlap through the
/// editor, because the union would then quietly report two recorded pauses as
/// one shorter total than their lengths suggest, and nothing on screen would say
/// why.
///
/// ## What it is not
///
/// Not detection. Nothing here infers a pause from a stationary stretch, a gap
/// in the route or a quiet hour: DashPilot observes nothing about why a vehicle
/// stopped, and a pause it guessed at would shorten a shift the driver recorded
/// as whole. Every timestamp this type accepts was typed by the driver on
/// purpose.
nonisolated struct ShiftPauseCorrection: Equatable, Sendable {
    /// The instant the corrected pause will record as its start.
    let startedAt: Date

    /// The instant it will record as its end. Never `nil`: a correction always
    /// produces a completed pause.
    let endedAt: Date

    /// How long the corrected pause will be. Always positive.
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// Checks a proposed stretch against a shift's own recorded facts.
    ///
    /// The parameters are plain values rather than a `Shift`, so every rule
    /// below is testable without a store, a container or a rendered view.
    /// ``Shift/pauseCorrection(from:to:replacing:)`` is the adapter that reads
    /// the model into it, and it is the only thing that knows how to gather
    /// these.
    ///
    /// - Parameters:
    ///   - startedAt: the proposed start.
    ///   - endedAt: the proposed end.
    ///   - shiftWindow: the completed shift's own start-to-end range, or `nil`
    ///     for a shift that has not ended, which is refused.
    ///   - otherPauses: every pause the shift records **apart from** the one
    ///     being corrected. The row being replaced is excluded by the caller, so
    ///     that a pause never collides with itself and an edit that leaves one
    ///     end where it was is not refused for touching it.
    ///   - deliveryIntervals: the stretch each of the shift's deliveries was
    ///     open for. An interval the data cannot measure contributes no refusal,
    ///     for the reason it contributes no active time: a malformed row is not
    ///     evidence that work happened at a particular moment.
    /// - Throws: ``ShiftPauseCorrectionRefusal``.
    init(
        startedAt: Date,
        endedAt: Date,
        within shiftWindow: ClosedRange<Date>?,
        avoiding otherPauses: [ShiftPauseInterval],
        and deliveryIntervals: [DeliveryActiveInterval]
    ) throws {
        guard let shiftWindow else { throw ShiftPauseCorrectionRefusal.shiftNotCompleted }
        guard endedAt > startedAt else { throw ShiftPauseCorrectionRefusal.notPositiveDuration }
        guard startedAt >= shiftWindow.lowerBound else { throw ShiftPauseCorrectionRefusal.startsBeforeShift }
        guard endedAt <= shiftWindow.upperBound else { throw ShiftPauseCorrectionRefusal.endsAfterShift }

        let proposed = startedAt...endedAt

        // An open pause among the others is measured to the shift's own end,
        // exactly as the working-duration calculation measures it, so a
        // correction cannot be slipped underneath one. On a completed shift
        // there is no open pause to meet; this is for a store holding the
        // anomalous row the app cannot write.
        let occupied = otherPauses.compactMap { $0.clipped(to: shiftWindow) }
        guard !occupied.contains(where: { Self.overlaps($0, proposed) }) else {
            throw ShiftPauseCorrectionRefusal.overlapsAnotherPause
        }

        let worked = deliveryIntervals.compactMap { $0.clipped(to: shiftWindow) }
        guard !worked.contains(where: { Self.overlaps($0, proposed) }) else {
            throw ShiftPauseCorrectionRefusal.overlapsDeliveryWork
        }

        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// Whether two stretches share more than an instant.
    ///
    /// Both are closed ranges, so ranges that merely touch share their common
    /// endpoint and are **not** overlapping here. That is the same reading
    /// ``DateRangeUnion`` takes of touching ranges, where one stretch ending as
    /// the next begins is one continuous stretch rather than a collision, and it
    /// is what lets a driver record a pause that begins the moment a delivery
    /// finished.
    private static func overlaps(_ lhs: ClosedRange<Date>, _ rhs: ClosedRange<Date>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }
}

/// What one pause correction will do, in the words the driver reads before
/// agreeing to it.
///
/// It lives beside the rule rather than in a view body for the reason
/// ``HistoricalCancellationPrompt`` does: the sentence a driver is asked to
/// confirm is the part of a destructive action that most needs testing.
///
/// Nothing here says `Edit`, exposes an identifier or names a stored row. A
/// pause is called what the screen calls it, which is its position in the shift.
nonisolated struct ShiftPauseDeletionPrompt: Equatable {
    /// The question, naming the pause.
    let title: String

    /// What will happen, in the order it happens.
    let detail: String

    /// The confirming button, which repeats the pause rather than saying "OK":
    /// a button labelled only `Delete` asks the driver to remember which row
    /// they tapped.
    let confirmTitle: String

    /// Deleting one pause a finished shift records.
    ///
    /// The sentence states the consequence a driver is least likely to have in
    /// mind: deleting a pause makes the shift's **working time longer**, because
    /// that stretch stops being subtracted. It also states what deletion does
    /// not do, since the two obvious guesses are both wrong — the shift's own
    /// start and end do not move, and the route recorded during the shift is
    /// untouched, gap and all.
    ///
    /// - Parameters:
    ///   - title: what the screen calls this pause, such as `Pause 2`.
    ///   - duration: how long the pause being deleted is, already written.
    static func delete(_ title: String, duration: String) -> Self {
        Self(
            title: "Delete \(title)?",
            detail: """
            \(title) was recorded as \(duration) of this shift. Deleting it records that you were \
            never paused then, so this shift's working time becomes \(duration) longer and the \
            hourly figures over it change. The shift's own start and end times do not move, and the \
            route recorded during it is not changed. This cannot be undone.
            """,
            confirmTitle: "Delete \(title)"
        )
    }
}
