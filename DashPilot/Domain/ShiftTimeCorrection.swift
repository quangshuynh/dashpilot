import Foundation

/// Why a proposed start time cannot be recorded for a shift.
///
/// Refusals rather than repairs, for the reason ``ShiftEndCorrectionRefusal``'s
/// are: every fact a corrected start would collide with is one the driver
/// recorded, and an editor that moved a delivery, a pause or another shift to
/// make an instant fit would replace their record with one the app invented.
nonisolated enum ShiftStartCorrectionRefusal: Error, Equatable, Sendable {
    /// The proposed start moves the start later, to an instant that has not
    /// happened yet.
    ///
    /// A running shift's working time is measured from its start to now, so a
    /// start in the future would report negative work clamped to zero and stop
    /// the timer. A finished shift cannot have started after the present either.
    /// A start already recorded in the future, which a wrong device clock can
    /// leave behind, may still move earlier, for the reason
    /// ``ShiftEndCorrectionRefusal/inFuture`` gives.
    case inFuture

    /// The proposed start is at or after the end this shift records.
    ///
    /// Raised only when the end is not being corrected in the same edit. When it
    /// is, the end side judges the pair and names the end, which is the field a
    /// driver would move to resolve it.
    case notBeforeShiftEnd

    /// A recorded pause began before the proposed start.
    ///
    /// A pause is a stretch **of** the shift, so a start after one would leave
    /// recorded paused time outside the shift it belongs to.
    case followsRecordedPause

    /// A recorded stretch parked began before the proposed start.
    ///
    /// A suspension explains a gap in the shift's route, so it has to stay
    /// inside the shift for the same reason a pause does.
    case followsRecordedRouteSuspension

    /// The proposed start is after a lifecycle event one of the shift's
    /// deliveries records.
    ///
    /// Carries the **earliest** blocking event: it is the one that has to move
    /// first, and a start acceptable to it is acceptable to every later one.
    case followsRecordedDeliveryWork(RecordedDeliveryEvent)

    /// The proposed start is after the moment one of the shift's offers was
    /// accepted.
    ///
    /// An offer is normally accepted at the same instant as its first delivery,
    /// so this is reached only by a store where the two differ. It is checked
    /// on its own because ``Offer`` refuses an acceptance before its shift's
    /// start, and a correction must not create the row that rule forbids.
    case followsRecordedOfferAcceptance

    /// The proposed start would put this shift over another one.
    ///
    /// Either the previous shift had not ended by then, or a whole shift was
    /// recorded between the proposed start and the one this shift records. Two
    /// shifts cannot overlap: each would contribute its working time to the same
    /// period, so a week would report more hours than it held.
    case overlapsAnotherShift
}

nonisolated extension ShiftStartCorrectionRefusal {
    /// Every case, for the suites that assert each one has a sentence.
    static let allCases: [Self] = [
        .inFuture,
        .notBeforeShiftEnd,
        .followsRecordedPause,
        .followsRecordedRouteSuspension,
        .followsRecordedDeliveryWork(
            RecordedDeliveryEvent(deliveryNumber: 1, event: .accepted, occurredAt: .distantPast)
        ),
        .followsRecordedOfferAcceptance,
        .overlapsAnotherShift
    ]

    /// A fixed structural name for the log, carrying no instant and no delivery.
    var logDescription: String {
        switch self {
        case .inFuture: "inFuture"
        case .notBeforeShiftEnd: "notBeforeShiftEnd"
        case .followsRecordedPause: "followsRecordedPause"
        case .followsRecordedRouteSuspension: "followsRecordedRouteSuspension"
        case .followsRecordedDeliveryWork: "followsRecordedDeliveryWork"
        case .followsRecordedOfferAcceptance: "followsRecordedOfferAcceptance"
        case .overlapsAnotherShift: "overlapsAnotherShift"
        }
    }
}

/// Why a proposed correction to a shift's start and end cannot be recorded,
/// naming which of the two times the driver has to move.
///
/// The editor shows each refusal under the picker it belongs to, so a driver is
/// never told "these times are invalid" without being told which one.
nonisolated enum ShiftTimeCorrectionRefusal: Error, Equatable, Sendable {
    /// The start time is refused.
    case start(ShiftStartCorrectionRefusal)
    /// The end time is refused, by the rules ``ShiftEndCorrection`` keeps.
    case end(ShiftEndCorrectionRefusal)

    /// A fixed structural name for the log.
    var logDescription: String {
        switch self {
        case let .start(refusal): "start.\(refusal.logDescription)"
        case let .end(refusal): "end.\(refusal.logDescription)"
        }
    }
}

/// When one other shift started and ended, as the overlap rule needs it.
nonisolated struct RecordedShiftSpan: Equatable, Sendable {
    let startedAt: Date
    /// `nil` for a shift that is still running.
    let endedAt: Date?
}

/// The shifts recorded either side of a proposed start, read from the store by
/// the caller.
///
/// Two neighbours are enough for a store holding shifts that do not overlap,
/// which is the invariant every writer in the app keeps: an overlap with any
/// shift implies an overlap with one of these.
nonisolated struct ShiftTimeNeighbours: Equatable, Sendable {
    /// The latest other shift that started **before** the proposed start.
    let previous: RecordedShiftSpan?
    /// When the earliest other shift that started **at or after** the proposed
    /// start began.
    let nextStartedAt: Date?
    /// When the earliest other shift that started at or after this shift's
    /// **recorded** start began. The end side's neighbour, exactly as
    /// ``ShiftEndCorrection`` has always been given it.
    let nextAfterRecordedStartStartedAt: Date?

    static let none = ShiftTimeNeighbours(previous: nil, nextStartedAt: nil, nextAfterRecordedStartStartedAt: nil)
}

/// A correction to when a shift started and, for a finished shift, when it
/// ended, checked against everything the shift records.
///
/// ## What it writes
///
/// **`Shift.startedAt` and `Shift.endedAt`, and nothing else on the shift.**
/// Removing the route evidence that a correction leaves outside the shift is
/// ``ShiftTimeCorrectionService``'s, because it is a change to other rows and
/// shares one save with this one. No delivery, offer, pause, suspension, amount,
/// tip, expense, fuel snapshot or hourly target moves.
///
/// Everything derived from the two boundaries is recomputed rather than stored:
/// elapsed, paused and working time, the rates over them, the route's coverage
/// and mileage, and every period aggregate. That is what makes the stored start
/// the **single authority**: no screen keeps its own copy to drift from it.
///
/// ## Reporting periods follow the start
///
/// A shift belongs to the day, week and month containing its `startedAt`, so a
/// start corrected across midnight or across Monday moves the whole shift into
/// the other period. Both periods are recomputed from the store, so the one it
/// left loses it and the one it joined gains it. ``reportingMove(calendar:)``
/// says which boundaries a correction crosses, for the sentence the driver reads
/// before saving.
///
/// ## Running shifts
///
/// A running shift may have its start corrected and nothing else: it has no
/// end, and it is ended by End, which stops capture and closes the Live
/// Activity. The correction does not pause, resume, end or restart anything, so
/// the timer simply continues from the corrected start because it is derived
/// from it.
///
/// ## Instants, not wall-clock times
///
/// Both times are instants. A correction across a daylight-saving change
/// measures the hours that really passed, because every duration here is a
/// `timeIntervalSince` and never a difference of clock readings.
nonisolated struct ShiftTimeCorrection: Equatable, Sendable {
    /// The start the shift records now.
    let recordedStart: Date
    /// The start the driver is correcting it to.
    let correctedStart: Date
    /// The end the shift records now, or `nil` for a running shift.
    let recordedEnd: Date?
    /// The end after the correction, or `nil` for a running shift.
    let correctedEnd: Date?

    /// Whether the start moves.
    var changesStart: Bool { correctedStart != recordedStart }
    /// Whether the end moves.
    var changesEnd: Bool { correctedEnd != recordedEnd }
    /// Whether anything moves at all. A correction that re-records both times
    /// is accepted and writes the same facts back.
    var changesAnything: Bool { changesStart || changesEnd }
    /// Whether this corrects a shift that is still running.
    var isRunningShift: Bool { recordedEnd == nil }

    /// Route evidence fixed **strictly before** this instant leaves the shift,
    /// or `nil` when the start does not move later.
    ///
    /// Strictly before, so a position fixed exactly at the corrected start is
    /// the first thing inside the shift rather than the last thing outside it.
    var routeTrimStartBoundary: Date? { correctedStart > recordedStart ? correctedStart : nil }

    /// Route evidence fixed **strictly after** this instant leaves the shift,
    /// or `nil` when the end does not move earlier. The rule
    /// ``ShiftEndCorrection/routeTrimBoundary`` states.
    var routeTrimEndBoundary: Date? {
        guard let recordedEnd, let correctedEnd, correctedEnd < recordedEnd else { return nil }
        return correctedEnd
    }

    /// Checks a proposed pair of times against a shift's own recorded facts.
    ///
    /// Plain values rather than a `Shift`, so every rule is testable without a
    /// store. ``Shift/timeCorrection(start:end:now:neighbours:)`` gathers them.
    ///
    /// Each side is judged only when it moves. A start that stays put is not
    /// re-judged against facts it was already recorded beside, so correcting an
    /// end alone is refused for exactly what ``ShiftEndCorrection`` has always
    /// refused it for, and nothing else.
    ///
    /// - Parameters:
    ///   - correctedStart: the start the driver proposes.
    ///   - correctedEnd: the end the driver proposes, or `nil` to keep the end
    ///     recorded now. A running shift must pass `nil`.
    ///   - recordedStart: the start the shift records.
    ///   - recordedEnd: the end the shift records, `nil` while running.
    ///   - now: the instant the correction is proposed at. Neither time may be
    ///     moved later than it.
    ///   - pauses: every pause the shift records.
    ///   - suspensions: every stretch the shift records the vehicle as parked.
    ///   - deliveryEvents: every lifecycle event its deliveries record.
    ///   - offerAcceptances: when each of its offers was accepted.
    ///   - neighbours: the shifts recorded either side of the proposed start.
    /// - Throws: ``ShiftTimeCorrectionRefusal``.
    init(
        start correctedStart: Date,
        end correctedEnd: Date?,
        recordedStart: Date,
        recordedEnd: Date?,
        now: Date,
        pauses: [ShiftPauseInterval],
        suspensions: [RouteSuspensionInterval],
        deliveryEvents: [RecordedDeliveryEvent],
        offerAcceptances: [Date],
        neighbours: ShiftTimeNeighbours
    ) throws {
        // A running shift has no end to correct, and a finished one keeps the
        // end it records unless the driver proposes another.
        if recordedEnd == nil, correctedEnd != nil {
            throw ShiftTimeCorrectionRefusal.end(.shiftNotCompleted)
        }
        let finalEnd = correctedEnd ?? recordedEnd
        let endMoves = finalEnd != recordedEnd

        if correctedStart != recordedStart {
            try Self.judgeStart(
                correctedStart,
                recordedStart: recordedStart,
                recordedEnd: recordedEnd,
                endMoves: endMoves,
                now: now,
                pauses: pauses,
                suspensions: suspensions,
                deliveryEvents: deliveryEvents,
                offerAcceptances: offerAcceptances,
                neighbours: neighbours
            )
        }

        if endMoves, let finalEnd {
            do {
                _ = try ShiftEndCorrection(
                    to: finalEnd,
                    startedAt: correctedStart,
                    recordedEnd: recordedEnd,
                    pauses: pauses,
                    suspensions: suspensions,
                    deliveryEvents: deliveryEvents,
                    nextShiftStartedAt: neighbours.nextAfterRecordedStartStartedAt,
                    now: now
                )
            } catch let refusal as ShiftEndCorrectionRefusal {
                throw ShiftTimeCorrectionRefusal.end(refusal)
            }
        }

        self.recordedStart = recordedStart
        self.correctedStart = correctedStart
        self.recordedEnd = recordedEnd
        self.correctedEnd = finalEnd
    }

    /// The start-side rules, in the order a driver would resolve them: the
    /// shift's own end, its recorded work, the shifts around it, then the
    /// clock. A proposed start that both follows recorded work and lies in the
    /// future names the work, which is the fact the driver can act on.
    private static func judgeStart(
        _ correctedStart: Date,
        recordedStart: Date,
        recordedEnd: Date?,
        endMoves: Bool,
        now: Date,
        pauses: [ShiftPauseInterval],
        suspensions: [RouteSuspensionInterval],
        deliveryEvents: [RecordedDeliveryEvent],
        offerAcceptances: [Date],
        neighbours: ShiftTimeNeighbours
    ) throws {
        // With the end moving too, the end side judges the pair and names the
        // end; here the recorded end is the one the start has to precede.
        if !endMoves, let recordedEnd, correctedStart >= recordedEnd {
            throw ShiftTimeCorrectionRefusal.start(.notBeforeShiftEnd)
        }

        // A malformed row whose end precedes its start is judged by the earlier
        // of its two instants: that is how far a window would have to reach back
        // to still contain it.
        let firstPaused = pauses.map { pause in pause.end.map { min(pause.start, $0) } ?? pause.start }.min()
        if let firstPaused, firstPaused < correctedStart {
            throw ShiftTimeCorrectionRefusal.start(.followsRecordedPause)
        }
        let firstParked = suspensions.map { parked in parked.end.map { min(parked.start, $0) } ?? parked.start }.min()
        if let firstParked, firstParked < correctedStart {
            throw ShiftTimeCorrectionRefusal.start(.followsRecordedRouteSuspension)
        }
        let firstEvent = deliveryEvents.min { $0.occurredAt < $1.occurredAt }
        if let firstEvent, firstEvent.occurredAt < correctedStart {
            throw ShiftTimeCorrectionRefusal.start(.followsRecordedDeliveryWork(firstEvent))
        }
        if let firstOffer = offerAcceptances.min(), firstOffer < correctedStart {
            throw ShiftTimeCorrectionRefusal.start(.followsRecordedOfferAcceptance)
        }

        if let previous = neighbours.previous {
            // A previous shift still running has every minute after its start.
            guard let previousEnd = previous.endedAt, previousEnd <= correctedStart else {
                throw ShiftTimeCorrectionRefusal.start(.overlapsAnotherShift)
            }
        }
        // Moving the start earlier past the whole of another shift.
        if correctedStart < recordedStart, let next = neighbours.nextStartedAt, next < recordedStart {
            throw ShiftTimeCorrectionRefusal.start(.overlapsAnotherShift)
        }
        if correctedStart > now, correctedStart > recordedStart {
            throw ShiftTimeCorrectionRefusal.start(.inFuture)
        }
    }
}

// MARK: - What the correction changes

nonisolated extension ShiftTimeCorrection {
    /// The shift's elapsed time after the correction: to its corrected end, or
    /// to `referenceDate` while it is running.
    func correctedElapsed(asOf referenceDate: Date) -> TimeInterval {
        max(0, (correctedEnd ?? referenceDate).timeIntervalSince(correctedStart))
    }

    /// The shift's elapsed time before it, measured the same way.
    func recordedElapsed(asOf referenceDate: Date) -> TimeInterval {
        max(0, (recordedEnd ?? referenceDate).timeIntervalSince(recordedStart))
    }

    /// The shift's working time after the correction: elapsed less the paused
    /// time that lies inside the corrected window.
    ///
    /// The same calculation ``Shift/workingDuration(asOf:)`` performs, over the
    /// proposed window instead of the recorded one, so the figure in the editor
    /// is the figure the shift will report.
    func correctedWorking(
        pauses: [ShiftPauseInterval],
        asOf referenceDate: Date,
        using calculator: ShiftPausedTimeCalculator = ShiftPausedTimeCalculator()
    ) -> TimeInterval {
        let elapsed = correctedElapsed(asOf: referenceDate)
        guard !pauses.isEmpty else { return elapsed }
        let window = correctedStart...max(correctedStart, correctedEnd ?? referenceDate)
        return max(0, elapsed - calculator.pausedTime(of: pauses, within: window).duration)
    }

    /// Which reporting boundaries the corrected start crosses, or `nil` when it
    /// stays on the same calendar day.
    func reportingMove(calendar: Calendar) -> ShiftReportingMove? {
        ShiftReportingMove(from: recordedStart, to: correctedStart, calendar: calendar)
    }
}

/// A corrected start that moves a shift into a different day, week or month.
///
/// Historical summaries assign a whole shift to the period containing its
/// start. A driver correcting 12:10 AM Monday to 11:50 PM Sunday is moving the
/// shift into the previous week, and both weeks' totals change. That is a
/// consequence worth stating before saving, and it is stated rather than
/// confirmed: it is a correct result of an ordinary edit, not a loss.
nonisolated struct ShiftReportingMove: Equatable, Sendable {
    let fromDay: ReportingPeriod
    let toDay: ReportingPeriod
    let fromWeek: ReportingPeriod
    let toWeek: ReportingPeriod
    let fromMonth: ReportingPeriod
    let toMonth: ReportingPeriod

    var changesWeek: Bool { fromWeek != toWeek }
    var changesMonth: Bool { fromMonth != toMonth }

    /// `nil` when both instants fall on the same calendar day, or when the
    /// calendar cannot build a period for either.
    init?(from recorded: Date, to corrected: Date, calendar: Calendar) {
        guard
            let fromDay = ReportingPeriod(unit: .day, containing: recorded, calendar: calendar),
            let toDay = ReportingPeriod(unit: .day, containing: corrected, calendar: calendar),
            fromDay != toDay,
            let fromWeek = ReportingPeriod(unit: .week, containing: recorded, calendar: calendar),
            let toWeek = ReportingPeriod(unit: .week, containing: corrected, calendar: calendar),
            let fromMonth = ReportingPeriod(unit: .month, containing: recorded, calendar: calendar),
            let toMonth = ReportingPeriod(unit: .month, containing: corrected, calendar: calendar)
        else { return nil }
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromWeek = fromWeek
        self.toWeek = toWeek
        self.fromMonth = fromMonth
        self.toMonth = toMonth
    }

    /// The sentence the editor shows, naming the largest boundary crossed.
    ///
    /// Written with the calendar's own time zone, so the days named are the
    /// days the periods were built from.
    func statement(calendar: Calendar, locale: Locale) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let day = base.weekday(.wide).month(.abbreviated).day()
        var sentence = "This shift will count on \(toDay.start.formatted(day)) instead of \(fromDay.start.formatted(day))"
        var periods: [String] = []
        if changesWeek { periods.append("the week of \(toWeek.start.formatted(base.month(.abbreviated).day()))") }
        if changesMonth { periods.append(toMonth.start.formatted(base.month(.wide).year())) }
        if !periods.isEmpty { sentence += ", in " + periods.joined(separator: " and in ") }
        return sentence + ". Both periods' totals update."
    }
}

/// What one time correction will delete, in the words the driver confirms.
///
/// Raised only when recorded positions would actually leave the shift. A
/// correction that removes nothing destroys nothing, and asking a driver to
/// confirm a deletion that is not happening teaches them to confirm without
/// reading.
nonisolated struct ShiftTimeCorrectionPrompt: Equatable {
    let title: String
    let detail: String
    let confirmTitle: String

    /// - Parameters:
    ///   - beforeStart: positions fixed before the corrected start.
    ///   - afterEnd: positions fixed after the corrected end.
    ///   - correctedStart: the new start, written the way the screen writes it.
    ///   - correctedEnd: the new end, written the same way, when it moves.
    /// - Returns: `nil` when nothing would be deleted.
    static func trimmingRoute(
        beforeStart: Int,
        afterEnd: Int,
        correctedStart: String,
        correctedEnd: String?
    ) -> Self? {
        guard beforeStart + afterEnd > 0 else { return nil }
        var parts: [String] = []
        if beforeStart > 0 {
            parts.append("\(positions(beforeStart)) before \(correctedStart)")
        }
        if afterEnd > 0, let correctedEnd {
            parts.append("\(positions(afterEnd)) after \(correctedEnd)")
        }
        return Self(
            title: "Remove route outside the corrected times?",
            detail: """
            This shift recorded \(parts.joined(separator: " and ")). Those positions are no longer \
            part of the shift, so they are deleted from DashPilot and its recorded mileage is measured \
            again from the positions that remain. Mileage is not reduced by the same share as the time. \
            No amount, delivery, pause or expense changes. This cannot be undone.
            """,
            confirmTitle: "Correct Times and Remove"
        )
    }

    private static func positions(_ count: Int) -> String {
        count == 1 ? "1 recorded position" : "\(count) recorded positions"
    }
}
