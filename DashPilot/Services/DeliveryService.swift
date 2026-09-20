import Foundation
import OSLog
import SwiftData

/// Failures raised when a delivery lifecycle operation cannot be applied.
///
/// Each case carries enough to write a sentence about it, because every one of
/// them is something a driver may see on a running shift.
nonisolated enum DeliveryLifecycleError: Error {
    /// A delivery was requested while no shift was running.
    case noActiveShift
    /// A delivery was requested while the shift was paused.
    ///
    /// Pausing says the driver stopped working; accepting a delivery says they
    /// had not. Recording both would produce a shift whose delivery active time
    /// runs through time the app is also reporting as not worked, so the start
    /// is refused and the driver is told to resume first. The converse rule,
    /// that a shift with a delivery open cannot be paused, lives in
    /// ``ShiftService``.
    case shiftPaused
    /// A transition was requested for a delivery that is not attached to a
    /// shift that is still running.
    ///
    /// Unreachable through the ordinary API — a delivery is created on the
    /// running shift, never moved to another, and a shift cannot end while one
    /// of its deliveries is active — so this reports a store holding data the
    /// app cannot produce rather than an ordinary refusal.
    case deliveryNotOnARunningShift
    /// A delivery recorded as delivered was asked to be reopened on a shift that
    /// has already ended.
    ///
    /// Its own case rather than ``deliveryNotOnARunningShift``, which reports a
    /// store the app cannot produce. This one is an ordinary refusal a driver can
    /// genuinely reach: a shift cannot end while a delivery is active, so
    /// reopening one on a finished shift would leave an active delivery under an
    /// ended shift that nothing could then advance. Reopening the shift is a
    /// separate decision this version does not make.
    case cannotReopenOnEndedShift
    /// A delivery was asked to be reopened while its shift was paused.
    ///
    /// The mirror of ``shiftPaused``, and kept apart from it so the sentence
    /// names what was refused. Pausing is refused while any delivery is open, so
    /// reopening one during a pause would produce exactly the pairing
    /// ``ShiftService`` forbids: delivery active time running through hours the
    /// app also reports as not worked.
    case cannotReopenWhilePaused
    /// A historical completion was asked to be corrected to a cancellation on a
    /// shift that has **not** ended.
    ///
    /// The mirror of ``cannotReopenOnEndedShift``, and its own case for the same
    /// reason: a refusal sentence has to name what was refused, and this one has
    /// somewhere better to send the driver. While the shift is still running, a
    /// delivery marked delivered by mistake is **reopened** and finished
    /// properly; rewriting it into a cancellation would throw away work the
    /// driver can still record. The correction exists for the shift that is
    /// already over, where there is nothing left to finish.
    case cannotCorrectOnRunningShift
    /// A correction was asked for a delivery attached to no shift at all.
    ///
    /// A store the app cannot produce, so this reports a fault rather than an
    /// ordinary refusal. Distinct from ``deliveryNotOnARunningShift``, whose
    /// sentence says the delivery's shift has ended, which is the required
    /// state for this correction rather than an obstacle to it.
    case deliveryNotOnAShift
    /// The delivery model refused to reopen the delivery.
    case invalidRecovery(DeliveryRecoveryRefusal)
    /// A historical correction was refused by the delivery's own timestamps.
    case invalidCancellation(HistoricalCancellationRefusal)
    /// The domain refused a correction to a completed delivery's recorded
    /// lifecycle times.
    ///
    /// Its own case rather than ``invalidTransition(_:)``, for the reason
    /// ``invalidCancellation(_:)`` is: this rewrites instants on a delivery that
    /// has already finished, and a driver reading a refusal has to be told which
    /// recorded time it collided with rather than that a lifecycle step was out
    /// of order.
    case invalidTimeCorrection(DeliveryTimeCorrectionRefusal)
    /// An additional tip was refused by the delivery or by the amount itself.
    ///
    /// Its own case rather than ``invalidTransition(_:)``, for the reason
    /// ``invalidOffer(_:)`` is one: a tip is not a lifecycle event, and the
    /// sentences it needs are about money that arrived outside the platform's
    /// figure rather than about a delivery advancing.
    case invalidTip(DeliveryTipError)
    /// The delivery model rejected the transition.
    case invalidTransition(DeliveryError)
    /// The shift refused to record the offer as described.
    case invalidOffer(OfferError)
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension DeliveryLifecycleError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.noActiveShift, .noActiveShift): true
        case (.shiftPaused, .shiftPaused): true
        case (.deliveryNotOnARunningShift, .deliveryNotOnARunningShift): true
        case (.cannotReopenOnEndedShift, .cannotReopenOnEndedShift): true
        case (.cannotReopenWhilePaused, .cannotReopenWhilePaused): true
        case (.cannotCorrectOnRunningShift, .cannotCorrectOnRunningShift): true
        case (.deliveryNotOnAShift, .deliveryNotOnAShift): true
        case let (.invalidRecovery(lhsError), .invalidRecovery(rhsError)): lhsError == rhsError
        case let (.invalidCancellation(lhsError), .invalidCancellation(rhsError)): lhsError == rhsError
        case let (.invalidTimeCorrection(lhsError), .invalidTimeCorrection(rhsError)): lhsError == rhsError
        case let (.invalidTip(lhsError), .invalidTip(rhsError)): lhsError == rhsError
        case let (.invalidTransition(lhsError), .invalidTransition(rhsError)): lhsError == rhsError
        case let (.invalidOffer(lhsError), .invalidOffer(rhsError)): lhsError == rhsError
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension DeliveryLifecycleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveShift:
            "Start a shift before recording a delivery."
        case .shiftPaused:
            "This shift is paused. Resume it before recording a delivery."
        case .deliveryNotOnARunningShift:
            "That delivery belongs to a shift that has already ended, so it cannot be changed."
        case .cannotReopenOnEndedShift:
            """
            That shift has already ended. A delivery can only be reopened while the shift it was \
            recorded in is still running.
            """
        case .cannotReopenWhilePaused:
            "This shift is paused. Resume it before reopening a delivery."
        case .cannotCorrectOnRunningShift:
            """
            That shift has not ended yet. While a shift is still running, a delivery marked \
            delivered by mistake is reopened and finished properly instead.
            """
        case .deliveryNotOnAShift:
            "That delivery is not recorded against a shift, so it cannot be changed."
        case .invalidTimeCorrection(.shiftNotCompleted):
            """
            That delivery belongs to a shift that has not ended yet. Recorded times are corrected \
            once the shift is over.
            """
        case .invalidTimeCorrection(.deliveryNotFinished):
            """
            That delivery has not finished, so there are no recorded times to correct. Record what \
            happened to it first.
            """
        case let .invalidTimeCorrection(.eventNotRecorded(stage)):
            """
            This delivery never recorded \(Self.eventName(stage)), so there is no time for it to \
            correct. DashPilot does not add an event that was not recorded.
            """
        case let .invalidTimeCorrection(.recordedEventRemoved(stage)):
            """
            \(stage.historyDescription) was recorded for this delivery, and \
            correcting its times cannot remove it.
            """
        case let .invalidTimeCorrection(.outOfOrder(event, mustNotPrecede)):
            """
            \(event.historyDescription) cannot be earlier than \
            \(Self.eventName(mustNotPrecede)). Choose a later time, or correct \
            \(Self.eventName(mustNotPrecede)) as well.
            """
        case let .invalidTimeCorrection(.precedesShiftStart(stage)):
            """
            \(stage.historyDescription) would be before this shift started, and a \
            delivery happens during the shift that recorded it. Choose a time after the shift began.
            """
        case let .invalidTimeCorrection(.followsShiftEnd(stage)):
            """
            \(stage.historyDescription) would be after this shift ended, and a \
            delivery happens during the shift that recorded it. Choose an earlier time, or correct \
            the shift's end time first.
            """
        case .invalidTimeCorrection(.recordedTimesChanged):
            "This delivery's recorded times changed while this was open, so nothing was written."
        case .invalidCancellation(.notDelivered):
            "That delivery is not recorded as delivered, so there is no completion to correct."
        case .invalidCancellation(.alreadyCancelled):
            "That delivery is already recorded as cancelled, so nothing was changed."
        case .invalidCancellation(.pickedUpWithoutArrival):
            """
            That delivery records being picked up with no arrival at the pickup before it, so \
            DashPilot will not rewrite how it ended. Nothing was changed.
            """
        case .invalidCancellation(.timestampsOutOfOrder):
            """
            That delivery's recorded times run backwards, so DashPilot will not rewrite how it \
            ended. Nothing was changed.
            """
        case .invalidRecovery(.notDelivered):
            "That delivery is not recorded as delivered, so there is nothing to reopen."
        case .invalidRecovery(.cancelled):
            "That delivery was cancelled. Only a delivery recorded as delivered can be reopened."
        case .invalidRecovery(.pickedUpWithoutArrival):
            """
            That delivery records being picked up with no arrival at the pickup before it, so \
            DashPilot cannot tell which state to return it to. Nothing was changed.
            """
        case .invalidRecovery(.timestampsOutOfOrder):
            """
            That delivery's recorded times run backwards, so DashPilot cannot tell which state to \
            return it to. Nothing was changed.
            """
        case .invalidTransition(.alreadyFinished(.delivered)):
            "That delivery is already recorded as delivered."
        case .invalidTransition(.alreadyFinished(.cancelled)):
            "That delivery was cancelled and cannot be continued."
        case .invalidTransition(.alreadyFinished):
            "That delivery has finished and cannot be changed."
        case let .invalidTransition(.alreadyRecorded(state)):
            "\(state.historyDescription) is already recorded for this delivery."
        case let .invalidTransition(.outOfOrder(missing)):
            "Record \(missing.historyDescription.lowercased()) first."
        case .invalidTransition(.timestampPrecedesLastEvent):
            "That would record a delivery event before one that already happened."
        case .invalidTransition(.deliveryNotFinished):
            "Earnings can be recorded once the delivery has been delivered or cancelled."
        case .invalidTransition(.deliveryNotActive):
            "An expected amount can only be recorded while the delivery is still in progress."
        case .invalidTransition(.negativeEarnings):
            "Gross earnings cannot be negative."
        case .invalidTransition(.negativeExpectedEarnings):
            "An expected amount cannot be negative."
        case .invalidTip(.amountNotPositive):
            """
            An additional tip has to be more than nothing. A delivery that received no tip simply has \
            none recorded.
            """
        case .invalidTip(.deliveryNotFinished):
            "An additional tip can be recorded once the delivery has been delivered or cancelled."
        case .invalidTip(.tipNotOnADelivery):
            "That tip is not recorded against a delivery, so it cannot be changed."
        case .invalidOffer(.deliveryCountNotPositive):
            "An offer has to contain at least one delivery."
        case .invalidOffer(.shiftAlreadyEnded):
            "That shift has already ended, so no offer can be recorded against it."
        case .invalidOffer(.acceptedBeforeShiftStart):
            "That would record an offer accepted before its shift began."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the delivery was not changed."
        }
    }

    /// What a refusal calls one lifecycle stage in the middle of a sentence.
    ///
    /// ``DeliveryState/historyDescription`` is written for the start of one, so
    /// it is used as it stands where a sentence begins with the stage and
    /// lowercased here where it does not. One accessor rather than five literals,
    /// so the stage a refusal names is the stage the delivery's own record names.
    private static func eventName(_ stage: DeliveryState) -> String {
        stage.historyDescription.lowercased()
    }
}

/// The delivery lifecycle: starting one, moving it through the events a driver
/// can truthfully record, and ending it either delivered or cancelled.
///
/// ## Several deliveries at once
///
/// A driver can be working more than one order at a time, so **any number of
/// deliveries may be active**, and each one advances on its own. That is the
/// whole reason every mutation here takes the delivery it applies to as a
/// parameter: with two active, "the active delivery" is not a thing the service
/// could resolve, and resolving one anyway — the newest, the oldest, the first
/// row a fetch returned — would attach a driver's tap to a record they did not
/// mean. There is no API here that guesses.
///
/// ## What it enforces
///
/// - A delivery belongs to exactly one shift, and can only begin while that
///   shift is running.
/// - A delivery is recorded **inside an accepted offer**, always, and an offer
///   holds at least one delivery. One tap records an offer of one; a driver who
///   says an offer held two records one offer holding two. Accepting more work
///   later records a **new** offer, never an addition to an existing one. See
///   ``startOffer(deliveryCount:at:)``.
/// - A lifecycle event is applied to **exactly one delivery, named by the
///   caller**, and never to another. Nothing is shared between concurrent
///   deliveries: starting, advancing, finishing or cancelling one leaves every
///   other one exactly as it was.
/// - A delivery can only be advanced while the shift it belongs to is still
///   running.
/// - Transitions happen in lifecycle order, once each, and never after the
///   delivery has finished. Those rules live on ``Delivery`` itself, so they
///   hold for every caller.
/// - A **gross** amount may only be recorded against a **finished** delivery,
///   and only ever the amount the driver typed for that one delivery. Nothing
///   here reads the shift's own recorded amount, and no total is ever divided
///   among deliveries. See ``setGrossEarnings(_:on:)``.
/// - An **expected** amount may only be recorded against an **active**
///   delivery, is stored in its own column, and never becomes a gross amount
///   here or anywhere else. See ``setExpectedEarnings(_:on:)``. Finishing a
///   delivery leaves its expectation exactly as it was and records no gross.
///
/// ## Timestamps
///
/// Every operation takes its date, so tests are deterministic and nothing in
/// the model reaches for `Date()`. A date behind the last recorded event is
/// clamped forward rather than refused, which is the rule ``ShiftService``
/// already applies when the device clock moves behind a shift's start: a driver
/// must always be able to record what just happened, and a clamped event
/// records a zero-length interval instead of a negative one.
///
/// SwiftData is the only source of truth. Nothing here caches which deliveries
/// are running, so deliveries left active when the app was terminated are
/// simply still active — all of them, with their own timestamps — when a new
/// service reads the store.
///
/// `@MainActor` isolated, like ``ShiftService``: every operation runs to
/// completion without suspending, so two callers cannot interleave a read with
/// the write that follows it.
@MainActor
struct DeliveryService {
    private let context: ModelContext

    /// How a change is handed to the store.
    ///
    /// `ModelContext.save()` everywhere in the app, and injectable for the one
    /// reason ``PickupPlaceService``'s is: every write here claims that a
    /// refused save leaves the model exactly as the store has it, and a claim
    /// about a refused save is untestable while the save can only succeed. A
    /// test substitutes a commit that throws; the rollback it triggers is the
    /// real ``ModelContext/rollback()``, so what the test asserts is the store's
    /// own behaviour rather than a stand-in for it.
    ///
    /// Deliberately a closure and not a protocol: one function, one call site
    /// per operation, no second conformance to write and nothing for the app to
    /// configure.
    private let commit: (ModelContext) throws -> Void

    init(context: ModelContext, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.commit = commit
    }

    /// Every delivery in the store that is neither delivered nor cancelled, in
    /// deterministic order.
    ///
    /// Active is read from the timestamps themselves rather than from a stored
    /// flag. More than one is expected: it is what stacked delivery work looks
    /// like, and it is no longer treated as a damaged store.
    ///
    /// The result is ordered by ``Delivery/acceptedBefore(_:_:)`` rather than by
    /// whatever order the fetch produced, so presentation and recovery see the
    /// same sequence every time.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeDeliveries() throws -> [Delivery] {
        let descriptor = FetchDescriptor<Delivery>(
            predicate: #Predicate { $0.deliveredAt == nil && $0.cancelledAt == nil },
            sortBy: [SortDescriptor(\.acceptedAt)]
        )

        let unfinished: [Delivery]
        do {
            unfinished = try context.fetch(descriptor)
        } catch {
            AppLog.delivery.error("Failed to read active deliveries: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        let ordered = unfinished.sorted(by: Delivery.acceptedBefore)

        // What *cannot* legitimately exist is an active delivery attached to a
        // shift that has already ended, or to no shift at all: a delivery is
        // created on the running shift, never reparented, and a shift cannot end
        // while any of its deliveries are active. Such a row is reported and
        // left alone — nothing is closed, cancelled, deleted or reparented to
        // tidy it up, because every one of those would invent a fact about work
        // the driver did.
        let stranded = ordered.filter { $0.shift?.isActive != true }
        if !stranded.isEmpty {
            AppLog.delivery.fault(
                "Store holds \(stranded.count, privacy: .public) active deliveries not attached to a running shift"
            )
        }

        return ordered
    }

    /// The deliveries `shift` still has running, in the same deterministic order.
    ///
    /// This is the query the running-shift interface and relaunch recovery are
    /// built from. It is a query, not a mutation seam: nothing is advanced,
    /// finished or repaired by reading it.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeDeliveries(for shift: Shift) throws -> [Delivery] {
        let shiftID = shift.id
        return try activeDeliveries().filter { $0.shift?.id == shiftID }
    }

    /// Starts a delivery on the running shift, alongside any already in progress.
    ///
    /// **One offer containing one delivery**, which is what a single tap, a
    /// spoken shortcut and a Lock Screen button all mean. It is the whole of
    /// this method: it names a count of one and hands the work to
    /// ``startOffer(deliveryCount:at:)``, so there is one write path and one
    /// place the invariants live. The one-tap path is unchanged from the
    /// caller's side, and every existing caller keeps the delivery it was
    /// returned.
    ///
    /// Nothing already recorded is touched. There is deliberately no maximum on
    /// how many deliveries may be running: how many orders a driver is carrying
    /// is a fact about their work, not a number this app is in a position to
    /// cap.
    ///
    /// - Throws: ``DeliveryLifecycleError/noActiveShift`` if no shift is
    ///   running, ``DeliveryLifecycleError/shiftPaused`` if it is paused, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func startDelivery(at date: Date = .now) throws -> Delivery {
        let offer = try startOffer(deliveryCount: 1, at: date)
        guard let delivery = offer.deliveriesInOrder.first else {
            // Unreachable: an offer is refused below the count of one, so one
            // that was recorded holds at least one delivery. Reported rather
            // than forced, because the alternative is a crash on a driver's
            // device over a store anomaly.
            AppLog.delivery.fault("An offer was recorded holding no delivery")
            throw DeliveryLifecycleError.invalidOffer(.deliveryCountNotPositive)
        }
        return delivery
    }

    /// Records an accepted offer on the running shift, containing
    /// `deliveryCount` deliveries.
    ///
    /// ## What one call records
    ///
    /// One acceptance and the deliveries it contained, in **one write**. The
    /// deliveries share the offer's acceptance timestamp, because the driver
    /// accepted them in one act; from that instant each advances entirely on its
    /// own, and completing one leaves its siblings exactly as they were.
    ///
    /// ## An add-on offer is a separate call and a separate offer
    ///
    /// Recording an offer while deliveries from an earlier one are still running
    /// is ordinary work and is allowed. The new offer is its own row and is
    /// never merged into an existing one: two acceptances whose deliveries
    /// overlap in time are still two acceptances, and nothing here reads the
    /// clock to decide otherwise.
    ///
    /// ## What it does not ask for
    ///
    /// A count, and nothing else. No pickup place, no expected amount, no
    /// customer and no name: every one of those is optional on a delivery and
    /// can be added later from a card, and asking for any of them at the kerb
    /// is the interaction this project designs away.
    ///
    /// - Throws: ``DeliveryLifecycleError/noActiveShift``,
    ///   ``DeliveryLifecycleError/shiftPaused``,
    ///   ``DeliveryLifecycleError/invalidOffer(_:)`` for a count below one, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func startOffer(deliveryCount: Int, at date: Date = .now) throws -> Offer {
        guard let shift = try activeShift() else {
            AppLog.delivery.notice("Refused to start a delivery: no shift is running")
            throw DeliveryLifecycleError.noActiveShift
        }

        guard !shift.isPaused else {
            AppLog.delivery.notice("Refused to start a delivery: the shift is paused")
            throw DeliveryLifecycleError.shiftPaused
        }

        // An offer cannot have been accepted before the shift it belongs to
        // began. Clamping rather than refusing keeps the driver able to record
        // the work, and records deliveries that start with their shift.
        let acceptedAt = max(date, shift.startedAt)
        if acceptedAt != date {
            AppLog.delivery.warning("Delivery start preceded the shift start; clamped to the shift start")
        }

        let recorded: (offer: Offer, deliveries: [Delivery])
        do {
            recorded = try shift.beginOffer(deliveryCount: deliveryCount, at: acceptedAt)
        } catch let error as OfferError {
            AppLog.delivery.notice("Shift rejected an offer: \(String(describing: error), privacy: .public)")
            throw DeliveryLifecycleError.invalidOffer(error)
        }

        // Both halves, explicitly, rather than relying on a relationship to
        // carry one in behind the other: a failed save must roll back exactly
        // what this call put in.
        context.insert(recorded.offer)
        for delivery in recorded.deliveries { context.insert(delivery) }

        do {
            try commit(context)
        } catch {
            // Leave nothing half-started in memory that the store does not hold.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery start: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Counts, which are structural. Not when it started, and not which one.
        AppLog.delivery.info(
            """
            Offer started with \(recorded.deliveries.count, privacy: .public) deliveries; \
            \(shift.activeDeliveries.count, privacy: .public) now active on this shift
            """
        )
        return recorded.offer
    }

    /// Records that the driver reached `delivery`'s pickup.
    @discardableResult
    func markArrivedAtPickup(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .arrivedAtPickup, at: date) { delivery, eventDate in
            try delivery.markArrivedAtPickup(at: eventDate)
        }
    }

    /// Records that `delivery`'s order is in the car.
    @discardableResult
    func markPickedUp(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .pickedUp, at: date) { delivery, eventDate in
            try delivery.markPickedUp(at: eventDate)
        }
    }

    /// Records that `delivery` was completed.
    @discardableResult
    func markDelivered(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .delivered, at: date) { delivery, eventDate in
            try delivery.markDelivered(at: eventDate)
        }
    }

    /// Records that `delivery` ended without being completed.
    ///
    /// One named delivery, never "the delivery in progress". With two orders in
    /// the car, a cancel control that picked its own target would be the most
    /// destructive guess in the app, and the mistake is not undoable.
    ///
    /// The delivery is kept. A cancelled delivery is history — the driver drove
    /// to a pickup and waited there — and deleting it would remove work that
    /// happened from the shift it happened in.
    @discardableResult
    func cancelDelivery(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .cancelled, at: date) { delivery, eventDate in
            try delivery.cancel(at: eventDate)
        }
    }

    // MARK: Correcting an accidental completion

    /// Takes back a `Delivered` the driver did not mean, returning one named
    /// delivery to the state its remaining timestamps describe.
    ///
    /// ## What it corrects, and what it refuses to become
    ///
    /// One mistake: a delivery recorded as delivered that is not delivered yet.
    /// It removes **the delivered timestamp and nothing else**, and the state
    /// that results is derived by ``DeliveryRecovery`` from the timestamps that
    /// stay, so nothing is chosen, typed or invented. It is deliberately not a
    /// lifecycle editor: no timestamp can be moved through here, no state can be
    /// named, and a delivery cannot be put into a state the lifecycle could not
    /// have produced on its own.
    ///
    /// A cancelled delivery is refused rather than treated as the same
    /// correction, because taking back a cancellation is a different statement
    /// with different consequences and this version has not decided them.
    ///
    /// ## Only while the shift is running
    ///
    /// Both refusals are about the shift rather than the delivery, and both keep
    /// invariants that already exist:
    ///
    /// - **A shift that has ended** cannot hold a reopened delivery. ``ShiftService``
    ///   refuses to end a shift while any delivery is active, so reopening one
    ///   afterwards would create the very row this service treats as a
    ///   structural fault, and ``validateShift(of:)`` would then refuse every
    ///   step that could finish it. The delivery would be stuck active in
    ///   history forever. Reopening the shift itself would be a separate,
    ///   explicit decision; nothing here makes it silently.
    /// - **A paused shift** cannot either, for the reason a delivery cannot be
    ///   started during one: delivery active time would run through hours the
    ///   app reports as not worked.
    ///
    /// ## One write, and the money is left alone
    ///
    /// One save, with the same rollback rule every other mutation here uses: a
    /// refused save leaves the **store** holding the delivery exactly as
    /// delivered as it already had it. A gross amount already recorded against
    /// the delivery stays
    /// recorded, because it is a separate fact the driver entered and a
    /// lifecycle correction is not an instruction to delete money. An expected
    /// amount stays too, and becomes editable again with the delivery.
    ///
    /// - Returns: the state the delivery is now in.
    /// - Throws: ``DeliveryLifecycleError/cannotReopenOnEndedShift``,
    ///   ``DeliveryLifecycleError/cannotReopenWhilePaused``,
    ///   ``DeliveryLifecycleError/invalidRecovery(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func reopenDelivered(_ delivery: Delivery) throws -> DeliveryState {
        guard let shift = delivery.shift else {
            // A delivery attached to no shift is a store the app cannot produce,
            // which is why this is a fault rather than one of the two refusals
            // below. The row is left exactly as it is.
            AppLog.delivery.fault("Refused to reopen a delivery: it is attached to no shift")
            throw DeliveryLifecycleError.deliveryNotOnARunningShift
        }
        guard shift.isActive else {
            AppLog.delivery.notice("Refused to reopen a delivery: its shift has ended")
            throw DeliveryLifecycleError.cannotReopenOnEndedShift
        }
        guard !shift.isPaused else {
            AppLog.delivery.notice("Refused to reopen a delivery: the shift is paused")
            throw DeliveryLifecycleError.cannotReopenWhilePaused
        }

        let restored: DeliveryState
        do {
            restored = try delivery.reopenFromDelivered()
        } catch let error as DeliveryRecoveryRefusal {
            // Nothing has been mutated: the model derives before it clears.
            AppLog.delivery.notice(
                "Delivery refused to reopen: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidRecovery(error)
        }

        do {
            try commit(context)
        } catch {
            // The store keeps the delivery exactly as delivered as it already
            // had it, and nothing is left pending. The live object can still
            // read as reopened until the context is re-read, which is the
            // SwiftData rollback caveat `AGENTS.md` records and is why every
            // claim about a refused save here is verified through a fresh
            // context.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery reopening: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only: which state it went back to, and how many deliveries
        // are now running. Never which delivery, never a timestamp, and never
        // the amount it still carries.
        AppLog.delivery.info(
            """
            A delivery recorded as delivered was reopened to \(restored.rawValue, privacy: .public); \
            \(shift.activeDeliveries.count, privacy: .public) now active on this shift
            """
        )
        return restored
    }

    // MARK: Correcting a historical completion

    /// Corrects one delivery that a **finished** shift records as delivered, and
    /// that never actually completed, into the cancellation it was.
    ///
    /// ## What it corrects, and what it refuses to become
    ///
    /// One mistake, noticed too late: a delivery marked delivered that fell
    /// through, on a shift that is already over. The delivery **stays
    /// terminal**. Its `deliveredAt` is removed, its `cancelledAt` is written
    /// with the instant that completion recorded, and nothing else on the row
    /// moves. It is deliberately not a lifecycle editor and not a second
    /// ``cancelDelivery(_:at:)``: no timestamp can be supplied through here, no
    /// state can be named, and a delivery that is not recorded as delivered is
    /// refused rather than cancelled.
    ///
    /// **Nothing about the shift changes.** It stays ended, no delivery becomes
    /// active inside it, no route capture session is started, no Live Activity
    /// is requested and no lifecycle control appears anywhere: the correction
    /// writes two attributes of one delivery, and every one of those surfaces
    /// reads the shift's own end timestamp, which this does not touch.
    ///
    /// ## Only once the shift has ended
    ///
    /// The mirror of ``reopenDelivered(_:)``'s rule, and the two together cover
    /// the whole of the mistake. While the shift is **running** there is still
    /// work to do, so the correction is to reopen the delivery and finish it
    /// properly; rewriting it into a cancellation there would discard a
    /// completion the driver is about to record for real. Once the shift has
    /// **ended** nothing can finish it, and recording the ending that actually
    /// happened is the only truthful repair left. A **paused** shift has not
    /// ended, so it is refused by the same guard and sent to the same place.
    ///
    /// ## One write, and the money is left alone
    ///
    /// One save, with the same rollback rule every other mutation here uses: a
    /// refused save leaves the **store** holding the delivery exactly as
    /// delivered as it already had it. A gross amount already recorded stays
    /// recorded, because a cancelled delivery may truthfully carry one (see
    /// ``Delivery/setGrossEarnings(_:)``) and a lifecycle correction is not an
    /// instruction to delete money; an expected amount stays for the same
    /// reason. Neither is converted into the other and no adjustment, refund or
    /// clawback is invented.
    ///
    /// A second invocation meets
    /// ``HistoricalCancellationRefusal/alreadyCancelled`` and writes nothing,
    /// which is what makes a double tap safe.
    ///
    /// - Throws: ``DeliveryLifecycleError/deliveryNotOnAShift``,
    ///   ``DeliveryLifecycleError/cannotCorrectOnRunningShift``,
    ///   ``DeliveryLifecycleError/invalidCancellation(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    func correctCompletionToCancellation(_ delivery: Delivery) throws {
        guard let shift = delivery.shift else {
            // A delivery attached to no shift is a store the app cannot produce,
            // which is why this is a fault rather than the refusal below. The
            // row is left exactly as it is.
            AppLog.delivery.fault("Refused to correct a delivery: it is attached to no shift")
            throw DeliveryLifecycleError.deliveryNotOnAShift
        }
        guard !shift.isActive else {
            AppLog.delivery.notice("Refused to correct a delivery: its shift has not ended")
            throw DeliveryLifecycleError.cannotCorrectOnRunningShift
        }

        do {
            try delivery.correctCompletionToCancellation()
        } catch let error as HistoricalCancellationRefusal {
            // Nothing has been mutated: the model derives before it writes.
            AppLog.delivery.notice(
                "Delivery refused a historical correction: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidCancellation(error)
        }

        do {
            try commit(context)
        } catch {
            // The store keeps the delivery exactly as delivered as it already
            // had it, and nothing is left pending. The live object can still
            // read as cancelled until the context is re-read, which is the
            // SwiftData rollback caveat `AGENTS.md` records and is why every
            // claim about a refused save here is verified through a fresh
            // context.
            context.rollback()
            AppLog.delivery.error("Failed to persist a historical delivery correction: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only: that one recorded completion became a cancellation,
        // and how the shift's deliveries now divide. Never which delivery, never
        // a timestamp, never a place and never the amount it still carries.
        let summary = shift.deliverySummary
        AppLog.delivery.info(
            """
            A recorded completion was corrected to a cancellation; this shift now records \
            \(summary.completed, privacy: .public) completed and \(summary.cancelled, privacy: .public) cancelled
            """
        )
    }

    // MARK: Correcting recorded times

    /// Rewrites the lifecycle instants a **finished** delivery on a **finished**
    /// shift recorded.
    ///
    /// ## What it corrects
    ///
    /// Work that happened while DashPilot could not record it. The app is
    /// evicted, crashes or is replaced by a new build mid-shift, the driver keeps
    /// delivering, and the events land whenever it comes back — so a delivery
    /// records a completion long after the food reached the door. Every figure
    /// measured from that instant is wrong with it, and, because
    /// ``ShiftEndCorrectionService`` refuses to move a shift's end back past
    /// anything a delivery recorded, one late completion also pins the shift's
    /// own end. Correcting the delivery is what unblocks correcting the shift.
    ///
    /// ## What it writes, and what it will not
    ///
    /// The instants the delivery **already records**, and nothing else. No
    /// lifecycle stage is created and none is removed, so the delivery is
    /// terminal in exactly the same way afterwards; its offer, pickup place,
    /// recorded platform pay, expected pay and tips are not read here at all;
    /// and no route sample, capture session or shift timestamp is touched. This
    /// corrects what the driver recorded about the delivery, not where the phone
    /// recorded being.
    ///
    /// **Nothing cascades.** A proposal that would put one recorded event before
    /// another is refused naming both, rather than dragging the second along
    /// with the first. That is the same rule the shift's end meets against a
    /// pause and against a delivery: the colliding fact is corrected explicitly,
    /// by the driver.
    ///
    /// ## Nothing derived is written
    ///
    /// The delivery's completed duration, its recorded pickup wait, its
    /// effective earnings per recorded delivery hour, the shift's union of
    /// delivery intervals and every period figure over them are derived on
    /// demand from exactly these instants, so all of them move with the save and
    /// none of them is recomputed or invalidated here.
    ///
    /// ## Validated whole, written whole
    ///
    /// ``DeliveryTimeCorrection`` judges the **complete** proposal before
    /// anything is assigned, ``Delivery/apply(_:)`` checks it is still a
    /// correction of the record it was judged against, and one save follows. A
    /// refused save rolls back, so the store keeps every original instant and
    /// there is no ordering in which one moved and another did not.
    ///
    /// The caller must re-read from the store rather than trusting a live object
    /// after a refused save, which is the SwiftData rollback caveat `AGENTS.md`
    /// records.
    ///
    /// - Parameters:
    ///   - delivery: the finished delivery whose recorded times are moving.
    ///   - proposed: the times it should record instead. It must record exactly
    ///     the stages the delivery already records.
    /// - Returns: what was applied, so a caller can say what moved without
    ///   re-deriving it from a model that already has.
    /// - Throws: ``DeliveryLifecycleError/deliveryNotOnAShift``,
    ///   ``DeliveryLifecycleError/invalidTimeCorrection(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func correctRecordedTimes(
        _ delivery: Delivery,
        to proposed: DeliveryLifecycleRecord
    ) throws -> DeliveryTimeCorrection {
        guard delivery.shift != nil else {
            // A delivery attached to no shift is a store the app cannot produce,
            // which is why this is a fault rather than a refusal. The row is left
            // exactly as it is.
            AppLog.delivery.fault("Refused to correct a delivery's times: it is attached to no shift")
            throw DeliveryLifecycleError.deliveryNotOnAShift
        }

        let correction = try proposedCorrection(on: delivery, to: proposed)

        do {
            try delivery.apply(correction)
        } catch let error as DeliveryTimeCorrectionRefusal {
            // Nothing has been assigned: the model checks before it writes.
            AppLog.delivery.notice(
                "Refused a delivery time correction: \(error.logDescription, privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTimeCorrection(error)
        }

        do {
            try commit(context)
        } catch {
            // Every original instant survives, together: the rollback discards
            // the whole proposal rather than the part that failed.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery time correction: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only, and deliberately without an instant, a direction, a
        // stage or a delivery — and without a count of how many stages moved,
        // which is the same line `OfferCorrectionService` already declines to
        // write about how many deliveries it moved. When a driver accepted,
        // collected or delivered an order is exactly the class of fact
        // `AppLog.delivery` has never recorded, and correcting one is not the
        // moment to start.
        AppLog.delivery.info("A completed delivery's recorded times were corrected")
        return correction
    }

    /// Why the proposed times would be refused, or `nil` if they would be
    /// accepted.
    ///
    /// The editor asks this while its pickers move, so the sentence on screen is
    /// written by the same rule the write will consult rather than by a second
    /// opinion about it. It mutates nothing and saves nothing.
    ///
    /// A delivery attached to no shift reports
    /// ``DeliveryTimeCorrectionRefusal/shiftNotCompleted``, which withholds the
    /// save: there is no window to judge against, and offering a save that is
    /// about to fail would be the worse answer.
    func timeCorrectionRefusal(
        on delivery: Delivery,
        to proposed: DeliveryLifecycleRecord
    ) -> DeliveryTimeCorrectionRefusal? {
        do {
            _ = try proposedCorrection(on: delivery, to: proposed)
            return nil
        } catch DeliveryLifecycleError.invalidTimeCorrection(let refusal) {
            return refusal
        } catch {
            return .shiftNotCompleted
        }
    }

    /// The proposed correction, with the domain's refusal wrapped for this
    /// layer.
    private func proposedCorrection(
        on delivery: Delivery,
        to proposed: DeliveryLifecycleRecord
    ) throws -> DeliveryTimeCorrection {
        do {
            return try delivery.timeCorrection(to: proposed)
        } catch let error as DeliveryTimeCorrectionRefusal {
            AppLog.delivery.notice(
                "Refused a delivery time correction: \(error.logDescription, privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTimeCorrection(error)
        }
    }

    /// Applies one lifecycle event to one named delivery.
    ///
    /// - Throws: ``DeliveryLifecycleError/deliveryNotOnARunningShift``,
    ///   ``DeliveryLifecycleError/invalidTransition(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    private func advance(
        _ delivery: Delivery,
        to recorded: DeliveryState,
        at date: Date,
        applying transition: (Delivery, Date) throws -> Void
    ) throws -> Delivery {
        try validateShift(of: delivery)

        // The same rule `ShiftService` applies to a shift end: a clock that has
        // moved backwards must not stop a driver recording what just happened,
        // and a clamped event produces a zero-length interval rather than a
        // negative one. It is read from *this* delivery's own last event, so a
        // second delivery's timeline has no influence on it.
        let eventDate = max(date, delivery.lastEventAt)
        if eventDate != date {
            AppLog.delivery.warning("Delivery event preceded the previous one; clamped to the previous event")
        }

        do {
            try transition(delivery, eventDate)
        } catch let error as DeliveryError {
            AppLog.delivery.notice("Delivery rejected a transition: \(String(describing: error), privacy: .public)")
            throw DeliveryLifecycleError.invalidTransition(error)
        }

        do {
            try commit(context)
        } catch {
            // Discards the pending timestamp: the model must not claim an event
            // the store does not record.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery transition: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only: which event, never which delivery, when it happened,
        // where it happened or what it paid.
        AppLog.delivery.info("Delivery advanced to \(recorded.rawValue, privacy: .public)")
        return delivery
    }

    // MARK: Earnings

    /// Records what one finished delivery paid, replacing any amount already
    /// stored against it.
    ///
    /// The model enforces the invariants (finished only, never negative); this
    /// adds the store write and the same rollback rule the lifecycle transitions
    /// use, so an amount can never be showing in the interface while the store
    /// holds something else.
    ///
    /// **This is the one delivery mutation that does not require a running
    /// shift**, and the exception is deliberate rather than an oversight.
    /// Recording an amount is a review action performed afterwards, from a
    /// completed shift's history, precisely so that nobody is asked to type a
    /// figure while they may be driving. A lifecycle event on a finished shift
    /// would be rewriting what happened; an amount on a finished delivery is the
    /// driver telling the app something it never had.
    ///
    /// Nothing here reads or writes the shift's own recorded amount. The two are
    /// independent facts, and no total is checked, reconciled or adjusted — see
    /// ``Delivery/setGrossEarnings(_:)``.
    ///
    /// - Throws: ``DeliveryLifecycleError/invalidTransition(_:)`` if the delivery
    ///   or the amount is not one earnings can be recorded against, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the write
    ///   fails.
    func setGrossEarnings(_ earnings: Money, on delivery: Delivery) throws {
        // Read before the write, so the log can say what happened without ever
        // holding the amount that happened to it.
        let isFirstAmount = delivery.grossEarnings == nil

        do {
            try delivery.setGrossEarnings(earnings)
        } catch let error as DeliveryError {
            AppLog.earnings.notice(
                "Delivery rejected recorded earnings: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTransition(error)
        }

        try saveEarnings(describing: isFirstAmount ? "add" : "update")
        AppLog.earnings.info("Delivery earnings \(isFirstAmount ? "recorded" : "updated", privacy: .public)")
    }

    /// Removes a delivery's recorded earnings, returning it to having none.
    ///
    /// Distinct from recording zero: afterwards the delivery is one with no
    /// amount entered, which is what it was before the driver typed one.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    func clearGrossEarnings(on delivery: Delivery) throws {
        delivery.clearGrossEarnings()
        try saveEarnings(describing: "remove")
        AppLog.earnings.info("Delivery earnings removed")
    }

    // MARK: Expected earnings

    /// Records what the driver expects one delivery in progress to pay,
    /// replacing any expectation already stored against it.
    ///
    /// **This writes nothing a total will ever count.** The expected amount is
    /// its own column; ``Delivery/grossEarningsAmount`` is untouched here, on
    /// this delivery and on every other, so no shift figure, period figure,
    /// rate or export summary moves because a driver said what they think an
    /// order will pay. What it buys them is the figure being on the delivery
    /// while they remember it, rather than being reconstructed from memory that
    /// evening.
    ///
    /// It is the mirror of ``setGrossEarnings(_:on:)`` in both directions.
    /// That one is the review action, allowed only on a finished delivery and
    /// deliberately allowed after the shift has ended; this one is the
    /// in-the-moment action, allowed only while the delivery is active, which
    /// means only while its shift is still running. The model enforces both
    /// rules, so a screen is never the only thing keeping them.
    ///
    /// - Throws: ``DeliveryLifecycleError/invalidTransition(_:)`` if the
    ///   delivery has already finished or the amount is negative, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the write
    ///   fails.
    func setExpectedEarnings(_ expected: Money, on delivery: Delivery) throws {
        // Read before the write, for the reason `setGrossEarnings` reads before
        // its own: the log says what happened without ever holding the amount.
        let isFirstAmount = delivery.expectedEarnings == nil

        do {
            try delivery.setExpectedEarnings(expected)
        } catch let error as DeliveryError {
            AppLog.earnings.notice(
                "Delivery rejected an expected amount: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTransition(error)
        }

        try saveEarnings(describing: isFirstAmount ? "add expected" : "update expected")
        AppLog.earnings.info("Delivery expected amount \(isFirstAmount ? "recorded" : "updated", privacy: .public)")
    }

    /// Removes a delivery's expected amount, returning it to having none.
    ///
    /// Available after the delivery has finished as well as during it, matching
    /// ``Delivery/clearExpectedEarnings()``: removing a figure claims nothing,
    /// and an expectation that turned out to be wrong must be removable from a
    /// delivery whose gross the driver has already recorded.
    ///
    /// Distinct from recording zero, and it never touches the recorded gross
    /// amount.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the write fails.
    func clearExpectedEarnings(on delivery: Delivery) throws {
        delivery.clearExpectedEarnings()
        try saveEarnings(describing: "remove expected")
        AppLog.earnings.info("Delivery expected amount removed")
    }

    // MARK: Additional tips

    /// Records a tip one finished delivery received **outside** what the
    /// platform recorded paying for it, and returns the row.
    ///
    /// The model enforces the invariants, a finished delivery and an amount above
    /// zero, and ``Delivery/recordAdditionalTip(_:method:at:)`` is the only
    /// thing that builds the row, so a screen is never the only thing keeping
    /// either rule. This adds the insert, the save and the same rollback rule
    /// every other write here uses, so a tip can never be showing in the
    /// interface while the store holds nothing.
    ///
    /// **Nothing here reads or writes ``Delivery/grossEarnings``**, on this
    /// delivery or on any other. The platform figure stays exactly as the driver
    /// recorded it, including whatever the platform already folded into it; this
    /// records money that arrived beside it. The two are added only on demand,
    /// by ``EffectiveDeliveryEarnings``, and no total is stored anywhere.
    ///
    /// It requires no running shift, for the reason
    /// ``setGrossEarnings(_:on:)`` does not: recording an amount is a review
    /// action performed afterwards, from a completed shift's history, precisely
    /// so that nobody is asked to type a figure while they may be driving.
    ///
    /// The row is inserted explicitly rather than left to the inverse
    /// relationship, for the reason ``ShiftPauseCorrectionService`` inserts a
    /// pause explicitly: a failed save must roll back exactly what this call put
    /// in.
    ///
    /// - Parameter date: when the tip is being recorded. Defaulted to now, and
    ///   injectable so a test can pin it; it is never a claim about when the
    ///   money changed hands.
    /// - Throws: ``DeliveryLifecycleError/invalidTip(_:)`` if the delivery or the
    ///   amount is not one a tip can be recorded against, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the write
    ///   fails.
    @discardableResult
    func addAdditionalTip(
        _ amount: Money,
        method: DeliveryTipMethod,
        on delivery: Delivery,
        at date: Date = .now
    ) throws -> DeliveryTip {
        let tip: DeliveryTip
        do {
            tip = try delivery.recordAdditionalTip(amount, method: method, at: date)
        } catch let error as DeliveryTipError {
            AppLog.earnings.notice(
                "Delivery rejected an additional tip: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTip(error)
        }

        context.insert(tip)
        try saveEarnings(describing: "add an additional tip")

        // Structural only: which operation, and which method it was recorded
        // under. Never the amount, never the delivery, never when.
        AppLog.earnings.info("Additional tip recorded (\(method.rawValue, privacy: .public))")
        return tip
    }

    /// Corrects what one recorded tip was and how it arrived.
    ///
    /// Replaces both values together, through ``DeliveryTip/update(amount:method:)``,
    /// so a row is never momentarily half corrected. The row keeps its identity
    /// and its ``DeliveryTip/recordedAt``: correcting a tip is not deleting one
    /// and recording another, and rewriting a historical timestamp is a decision
    /// this version deliberately does not make.
    ///
    /// The delivery's own state is **not** re-checked. The rule that a tip may
    /// only be recorded against a finished delivery is about creating one; a tip
    /// that already exists describes money that already arrived, and a delivery
    /// reopened from a mistaken completion must not make the driver unable to
    /// fix a typo in it. That is the same reading ``Delivery/setGrossEarnings(_:)``
    /// takes of an amount it already holds.
    ///
    /// - Throws: ``DeliveryLifecycleError/invalidTip(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    func updateAdditionalTip(_ tip: DeliveryTip, amount: Money, method: DeliveryTipMethod) throws {
        try requireOnADelivery(tip)

        do {
            try tip.update(amount: amount, method: method)
        } catch let error as DeliveryTipError {
            // Nothing has been mutated: the model validates before it assigns.
            AppLog.earnings.notice(
                "Delivery tip rejected a correction: \(String(describing: error), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidTip(error)
        }

        try saveEarnings(describing: "correct an additional tip")
        AppLog.earnings.info("Additional tip corrected (\(method.rawValue, privacy: .public))")
    }

    /// Removes a tip the driver recorded by mistake.
    ///
    /// The claim it records is "this tip never arrived", which is why the row is
    /// deleted rather than reduced to nothing: a tip of `$0.00` is refused
    /// everywhere else in this feature precisely because it says nothing.
    ///
    /// One transaction: the row is marked deleted and a single save follows, so
    /// a store that refuses the write leaves the tip exactly where it was. The
    /// delivery's recorded gross is untouched either way.
    ///
    /// - Throws: ``DeliveryLifecycleError/invalidTip(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    func deleteAdditionalTip(_ tip: DeliveryTip) throws {
        try requireOnADelivery(tip)

        context.delete(tip)
        try saveEarnings(describing: "delete an additional tip")

        AppLog.earnings.info("Additional tip removed")
    }

    /// Refuses to change a tip that is attached to no delivery.
    ///
    /// Through the ordinary API this cannot happen: a tip is created against a
    /// delivery and cascades away with it. It is checked anyway, for the reason
    /// ``validateShift(of:)`` is checked: a store holding one is a structural
    /// fault, and the row is left exactly as it is rather than repaired,
    /// reparented or deleted.
    private func requireOnADelivery(_ tip: DeliveryTip) throws {
        guard tip.delivery != nil else {
            AppLog.earnings.fault("Refused a tip change: the tip is attached to no delivery")
            throw DeliveryLifecycleError.invalidTip(.tipNotOnADelivery)
        }
    }

    /// Saves an earnings change, and rolls back if the store refuses.
    ///
    /// `operation` is a fixed word naming what was attempted, typed as a
    /// `StaticString` so an amount cannot become the value. It is written to the
    /// log; the amount never is.
    private func saveEarnings(describing operation: StaticString) throws {
        do {
            try commit(context)
        } catch {
            // The pending amount is discarded: the interface must not show a
            // figure the store does not hold.
            context.rollback()
            AppLog.earnings.error("Failed to \(operation, privacy: .public) delivery earnings: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }
    }

    /// Refuses to change a delivery that is not attached to a running shift.
    ///
    /// Through the ordinary API this cannot happen. It is checked anyway,
    /// because a store that somehow holds an active delivery on a finished shift
    /// — or on no shift at all — holds data the app cannot produce, and writing
    /// further lifecycle events into it would turn a structural fault into a
    /// longer and more confusing history. The row is left exactly as it is and
    /// the fault is logged; nothing is reparented, closed or deleted.
    private func validateShift(of delivery: Delivery) throws {
        guard let shift = delivery.shift else {
            AppLog.delivery.fault("Refused a transition: the delivery is attached to no shift")
            throw DeliveryLifecycleError.deliveryNotOnARunningShift
        }
        guard shift.isActive else {
            AppLog.delivery.fault("Refused a transition: the delivery's shift has already ended")
            throw DeliveryLifecycleError.deliveryNotOnARunningShift
        }
    }

    /// The running shift, read through ``ShiftService`` so there is one
    /// definition of "the active shift" — including how an anomalous store with
    /// more than one unfinished shift is handled.
    private func activeShift() throws -> Shift? {
        do {
            return try ShiftService(context: context).activeShift()
        } catch let ShiftLifecycleError.storeUnavailable(underlying) {
            throw DeliveryLifecycleError.storeUnavailable(underlying: underlying)
        }
    }
}
