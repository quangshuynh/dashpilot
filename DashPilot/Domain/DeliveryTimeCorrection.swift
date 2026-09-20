import Foundation

/// Why a proposed correction to a completed delivery's recorded times cannot be
/// written.
///
/// Each case is a refusal rather than something to repair on the driver's
/// behalf, for the reason ``ShiftEndCorrectionRefusal``'s are: every instant a
/// correction collides with is an instant the driver recorded, and an editor
/// that quietly slid a pickup back to make a completion fit would replace a fact
/// they recorded with one the app invented.
///
/// Three of them carry **which** recorded fact was collided with, because that
/// is the whole of what a driver needs in order to correct it themselves. A
/// refusal that says only "those times do not work" leaves them to find the
/// collision by moving pickers until one stops being refused.
nonisolated enum DeliveryTimeCorrectionRefusal: Error, Equatable, Sendable {
    /// The delivery belongs to a shift that has not ended.
    ///
    /// Correcting recorded times is a **review** action on history. A delivery
    /// on a running shift is still being worked: a mis-tapped completion is
    /// taken back by ``DeliveryRecovery`` and the delivery is then finished
    /// properly, which records the real instant rather than typing one. It is
    /// also the rule that gives this correction an upper bound at all, since the
    /// shift's own end is what no recorded event may fall after.
    case shiftNotCompleted

    /// The delivery has not finished, so there is no recorded history to
    /// correct.
    ///
    /// Unreachable on a well-formed completed shift, which cannot end while any
    /// of its deliveries is active, and refused rather than allowed for the
    /// anomalous row that reaches it: a delivery with no terminal event is one
    /// the driver never finished recording, and the repair for that is to record
    /// what happened rather than to move what did not.
    case deliveryNotFinished

    /// The correction proposes a time for a lifecycle stage this delivery never
    /// recorded.
    ///
    /// **A correction edits an existing recorded fact and creates none.** A
    /// delivery cancelled before the driver reached the pickup records no
    /// arrival, and writing one here would put an event into a driver's history
    /// on the app's authority rather than theirs, which is the same distinction the app
    /// keeps everywhere between a missing value and a zero.
    case eventNotRecorded(DeliveryState)

    /// The correction drops a lifecycle event this delivery does record.
    ///
    /// The mirror of ``eventNotRecorded(_:)``, and its own case because the two
    /// are different mistakes. Removing a recorded event is deleting history
    /// rather than correcting it, and the two corrections that genuinely remove
    /// one, ``DeliveryRecovery`` and ``HistoricalDeliveryCancellation``, each
    /// say so in their own name and have their own confirmation.
    case recordedEventRemoved(DeliveryState)

    /// The correction would put one recorded event before another the lifecycle
    /// records ahead of it.
    ///
    /// Carries **both** halves of the collision: the event whose proposed time
    /// is too early, and the recorded event it would then precede. Refused
    /// rather than resolved, exactly as a shift's end is refused rather than a
    /// delivery shortened to fit it: nothing here moves a second timestamp to
    /// accommodate the first, so a driver who meant to move both moves both.
    case outOfOrder(event: DeliveryState, mustNotPrecede: DeliveryState)

    /// The correction would put a recorded event before the shift that holds it
    /// began.
    ///
    /// A delivery is work done **during** a shift, and
    /// ``DeliveryActiveInterval`` clips to the shift's own window, so an event
    /// outside it would quietly stop counting minutes that really were worked.
    case precedesShiftStart(DeliveryState)

    /// The correction would put a recorded event after the shift that holds it
    /// ended.
    ///
    /// The mirror of ``precedesShiftStart(_:)`` and refused for the same reason.
    /// A driver whose shift end is itself wrong corrects the shift's end in its
    /// own editor; nothing here moves a shift boundary to make a delivery fit.
    case followsShiftEnd(DeliveryState)

    /// The delivery no longer records the times the correction was judged
    /// against.
    ///
    /// Raised at the moment of writing rather than of judging, and it is what
    /// keeps a correction atomic against a record that moved underneath it: a
    /// sheet held open across another screen's write, or a second tap on Save,
    /// meets this rather than having a stale proposal applied over the newer
    /// times. The same guard ``Shift/apply(_:)`` makes with a shift's recorded
    /// end.
    case recordedTimesChanged
}

nonisolated extension DeliveryTimeCorrectionRefusal {
    /// Every case, with a representative event where one is carried, for the
    /// suites that assert each has a sentence.
    ///
    /// Written out rather than synthesised, for the reason
    /// ``ShiftEndCorrectionRefusal/allCases`` is: three of these carry values,
    /// so `CaseIterable` is not available and a hand-written list is what the
    /// wording suites walk.
    static let allCases: [Self] = [
        .shiftNotCompleted,
        .deliveryNotFinished,
        .eventNotRecorded(.arrivedAtPickup),
        .recordedEventRemoved(.pickedUp),
        .outOfOrder(event: .delivered, mustNotPrecede: .pickedUp),
        .precedesShiftStart(.accepted),
        .followsShiftEnd(.delivered),
        .recordedTimesChanged
    ]

    /// A fixed structural name for the log, carrying no instant and no event.
    ///
    /// `String(describing:)` would print the associated `DeliveryState`, which
    /// is harmless, and would print any instant a future case carried, which is
    /// not. One accessor means a refusal can never leak a recorded time into
    /// `AppLog` by the ordinary act of being logged.
    var logDescription: String {
        switch self {
        case .shiftNotCompleted: "shiftNotCompleted"
        case .deliveryNotFinished: "deliveryNotFinished"
        case .eventNotRecorded: "eventNotRecorded"
        case .recordedEventRemoved: "recordedEventRemoved"
        case .outOfOrder: "outOfOrder"
        case .precedesShiftStart: "precedesShiftStart"
        case .followsShiftEnd: "followsShiftEnd"
        case .recordedTimesChanged: "recordedTimesChanged"
        }
    }
}

/// A new set of lifecycle times for a delivery that has already finished,
/// checked against the delivery's own record and the shift that holds it.
///
/// ## Why this exists
///
/// DashPilot can be unreachable at the moment work actually happens. Evicted
/// under memory pressure, crashed, or replaced by a new build mid-shift: the
/// driver keeps delivering, and the events land in the app whenever it comes
/// back. The delivery then records a completion long after the food reached the
/// door, and everything measured from that instant is wrong with it: how long
/// the delivery took, what it paid per hour, how much of the shift was delivery
/// active, and, downstream, whether the shift's own end can be corrected at all.
///
/// That last one is why this correction comes first in a recovery.
/// ``ShiftEndCorrection`` refuses to move a shift's end back past anything a
/// delivery recorded, so a delivery holding a late completion pins the shift's
/// end to it. The delivery is corrected here, and the shift's end is then
/// corrected in its own editor.
///
/// ## What a correction changes
///
/// The lifecycle instants the delivery **already records**, and nothing else:
///
/// | Correctable | Only when already recorded |
/// | --- | --- |
/// | `acceptedAt` | Always present: a delivery that was not accepted does not exist |
/// | `arrivedAtPickupAt` | Present when the driver recorded reaching the pickup |
/// | `pickedUpAt` | Present when the driver recorded collecting the order |
/// | `deliveredAt` | Present on a delivery recorded as delivered |
/// | `cancelledAt` | Present on a delivery recorded as cancelled |
///
/// | Unchanged by every correction here |
/// | --- |
/// | Which terminal event the delivery records, so a delivered delivery stays delivered and a cancelled one stays cancelled |
/// | Which lifecycle stages exist at all: none is created and none is removed |
/// | The offer the delivery arrived in, and therefore every grouping built from it |
/// | The pickup place it names |
/// | Its recorded platform pay, its expected pay, every additional tip, and every note or expense anywhere |
/// | Every `RouteSample`: its coordinate, its timestamp and its capture session |
/// | The shift's own start and end |
///
/// ## Nothing is fabricated, and nothing cascades
///
/// A stage the delivery never recorded stays unrecorded: this is not a way to
/// add an arrival to a delivery that was cancelled on the way to one. And no
/// timestamp moves except the ones the driver moved. A completion dragged back
/// behind its own pickup is **refused, naming the pickup**, rather than dragging
/// the pickup back with it. The driver corrects that fact explicitly, in the
/// same editor, and the whole proposal is judged again.
///
/// ## Nothing derived is written
///
/// The delivery's completed duration, its recorded pickup wait, its effective
/// earnings per recorded delivery hour, the shift's union of delivery intervals
/// and every period figure over them are all derived on demand from exactly
/// these instants. Correcting one therefore moves all of them with no
/// invalidation, no recomputation step and no second stored answer, which is the
/// same property ``ShiftEndCorrection`` relies on for mileage.
///
/// ## What it is not
///
/// Not detection. Nothing here infers when a delivery really finished from the
/// route, a stationary stretch or the next delivery's acceptance. Every instant
/// it accepts was typed by the driver on purpose.
///
/// Not a lifecycle editor either. It records no event, removes no event and
/// changes no terminal outcome: a delivery that never completed is corrected by
/// ``HistoricalDeliveryCancellation``, and one still being worked by
/// ``DeliveryRecovery``.
nonisolated struct DeliveryTimeCorrection: Equatable, Sendable {
    /// The times the delivery records now, as the correction was built against
    /// them.
    ///
    /// Carried so that applying a correction can check it is still being applied
    /// to the record it was judged against, which is the guard
    /// ``Shift/apply(_:)`` makes with a shift's recorded end.
    let recorded: DeliveryLifecycleRecord

    /// The times it will record instead.
    let corrected: DeliveryLifecycleRecord

    /// Which lifecycle stages actually move, in lifecycle order.
    ///
    /// Empty for a correction that re-records the times the delivery already
    /// had, which is accepted and writes the same facts back, exactly as an
    /// end-time correction to the recorded end is.
    var movedEvents: [DeliveryState] {
        let before = Dictionary(uniqueKeysWithValues: recorded.recordedEvents.map { ($0.event, $0.occurredAt) })
        return corrected.recordedEvents
            .filter { before[$0.event] != $0.occurredAt }
            .map(\.event)
    }

    /// Whether this correction would write the record back unchanged.
    var changesNothing: Bool { movedEvents.isEmpty }

    /// Checks a proposed set of times against what the delivery records and the
    /// shift that holds it.
    ///
    /// The parameters are plain values rather than a `Delivery`, so every rule
    /// below is testable without a store, a container or a rendered view.
    /// ``Delivery/timeCorrection(to:)`` is the adapter that reads the model into
    /// it.
    ///
    /// - Parameters:
    ///   - recorded: the times the delivery records now.
    ///   - proposed: the times the driver is proposing instead. It must record
    ///     exactly the same lifecycle stages: one that adds a stage is refused
    ///     by ``DeliveryTimeCorrectionRefusal/eventNotRecorded(_:)`` and one
    ///     that drops a stage by
    ///     ``DeliveryTimeCorrectionRefusal/recordedEventRemoved(_:)``.
    ///   - shiftWindow: the containing completed shift's own start-to-end range,
    ///     or `nil` for a shift that has not ended, which is refused. Touching
    ///     either bound is allowed, which is the same reading of touching
    ///     instants ``ShiftPauseCorrection`` and ``ShiftEndCorrection`` take.
    /// - Throws: ``DeliveryTimeCorrectionRefusal``.
    init(
        correcting recorded: DeliveryLifecycleRecord,
        to proposed: DeliveryLifecycleRecord,
        within shiftWindow: ClosedRange<Date>?
    ) throws {
        guard let shiftWindow else { throw DeliveryTimeCorrectionRefusal.shiftNotCompleted }
        guard recorded.isFinished else { throw DeliveryTimeCorrectionRefusal.deliveryNotFinished }

        // Checked before anything about the instants, because a proposal that
        // describes a different lifecycle is not a correction of this one at
        // all, and reporting an ordering problem inside it would be answering a
        // question nobody asked.
        try Self.requireSameStages(recorded: recorded, proposed: proposed)

        let events = proposed.recordedEvents
        for event in events {
            guard event.occurredAt >= shiftWindow.lowerBound else {
                throw DeliveryTimeCorrectionRefusal.precedesShiftStart(event.event)
            }
            guard event.occurredAt <= shiftWindow.upperBound else {
                throw DeliveryTimeCorrectionRefusal.followsShiftEnd(event.event)
            }
        }

        // Adjacent pairs only: `recordedEvents` is already in lifecycle order,
        // so a chain in which every step is at or after the one before it is
        // ordered throughout. The pair reported is the first that runs
        // backwards, which is the one nearest the start of the lifecycle and the
        // one a driver correcting from the top meets first.
        for (earlier, later) in zip(events, events.dropFirst()) where later.occurredAt < earlier.occurredAt {
            throw DeliveryTimeCorrectionRefusal.outOfOrder(
                event: later.event,
                mustNotPrecede: earlier.event
            )
        }

        self.recorded = recorded
        corrected = proposed
    }

    /// Refuses a proposal that records a different set of lifecycle stages from
    /// the one being corrected.
    ///
    /// Walked in lifecycle order so that the stage named is the earliest one
    /// that differs, and the addition is reported before the removal at the same
    /// stage, which cannot both happen to one stage anyway.
    private static func requireSameStages(
        recorded: DeliveryLifecycleRecord,
        proposed: DeliveryLifecycleRecord
    ) throws {
        for stage in DeliveryLifecycleRecord.lifecycleStages {
            switch (recorded.instant(of: stage), proposed.instant(of: stage)) {
            case (nil, .some): throw DeliveryTimeCorrectionRefusal.eventNotRecorded(stage)
            case (.some, nil): throw DeliveryTimeCorrectionRefusal.recordedEventRemoved(stage)
            default: continue
            }
        }
    }
}

/// What correcting a delivery's recorded times does, in the words the driver
/// reads before saving.
///
/// It lives beside the rule rather than in a view body for the reason
/// ``ShiftEndCorrectionPrompt`` does: what a driver is told a correction will do
/// is the part of it that most needs testing, and a sentence promising the route
/// is untouched has to be asserted somewhere.
///
/// There is no confirmation alert here, and that is a decision rather than an
/// omission. The two corrections in this app that raise one each **destroy**
/// something: an end moved earlier deletes recorded positions, and deleting a
/// pause removes a row. This deletes nothing, creates nothing and leaves the
/// delivery's terminal outcome, money and grouping exactly as they are, so it
/// follows ``ShiftPauseCorrection``'s shape instead: the consequences are
/// stated on the sheet, before Save, where they can be read rather than
/// dismissed. Raising an alert for a correction that destroys nothing is what
/// teaches a driver to confirm without reading.
///
/// Nothing here exposes an identifier, an amount or an instant: the sentences
/// are fixed, and the delivery is named only by what the screen calls it.
nonisolated enum DeliveryTimeCorrectionStatement {
    /// What moves once the times change. Every figure named is derived on
    /// demand, so all of them move together and none of them is rewritten.
    static let derivedFiguresMove = """
        Changing these times changes how long this delivery took, how long you waited at the pickup, \
        what it paid per recorded delivery hour, and how much of the shift was delivery active time.
        """

    /// The promise this correction makes about physical route evidence, which is
    /// the one thing a driver has no way to check from this screen.
    ///
    /// Stated positively and in full, because the natural fear is the opposite:
    /// a driver who has just moved a completion back by twenty minutes might
    /// reasonably expect the mileage to have fallen with it, and it has not.
    static let routeIsNotChanged = """
        Your recorded route and this shift's recorded mileage are not changed. This corrects what \
        you recorded about the delivery, not where the phone recorded being.
        """

    /// The promise it makes about everything else on the record.
    static let recordIsOtherwiseUnchanged = """
        Nothing else moves: the delivery stays finished as it is recorded now, and its pickup place, \
        the offer it arrived in, what it paid and any tips stay exactly as they are.
        """

    /// The rule the driver meets when one of these times collides with another,
    /// said once on the sheet so that a refusal below it reads as the rule
    /// rather than as a failure.
    static let eachTimeIsCorrectedExplicitly = """
        These times have to stay in the order they happened, and inside this shift. DashPilot never \
        moves one of them to make room for another, so correct each one you need to.
        """
}
