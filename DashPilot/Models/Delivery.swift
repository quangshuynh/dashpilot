import Foundation
import SwiftData

/// Errors raised when a delivery transition would violate the model's invariants.
nonisolated enum DeliveryError: Error, Equatable {
    /// The delivery has already been delivered or cancelled, so it cannot
    /// transition again. Carries the terminal state it is in.
    case alreadyFinished(DeliveryState)
    /// The event being recorded is already recorded on this delivery.
    case alreadyRecorded(DeliveryState)
    /// A lifecycle step was skipped: the named event has not happened yet.
    case outOfOrder(missing: DeliveryState)
    /// The event's timestamp is earlier than the last event already recorded,
    /// which would make the lifecycle run backwards.
    case timestampPrecedesLastEvent
    /// Earnings were recorded against a delivery that is still in progress.
    case deliveryNotFinished
    /// An expected amount was recorded against a delivery that has already
    /// finished.
    ///
    /// The mirror of ``deliveryNotFinished``, and deliberately its own case: an
    /// expectation is a statement about work that has not been paid for yet, so
    /// once the delivery is delivered or cancelled the fact worth recording is
    /// what it actually paid. Clearing an expected amount is still allowed from
    /// any state, because removing one claims nothing.
    case deliveryNotActive
    /// A negative amount was recorded as gross earnings.
    case negativeEarnings
    /// A negative amount was recorded as expected earnings.
    ///
    /// Apart from ``negativeEarnings`` so the refusal can name which of the two
    /// amounts was refused. A driver who typed a minus sign into the expected
    /// field must not be told that recorded gross earnings cannot be negative,
    /// because they were not recording any.
    case negativeExpectedEarnings
}

/// One delivery recorded during a shift.
///
/// ## What this is, and what it is not
///
/// Every timestamp on a delivery was written because the driver tapped a
/// control. DashPilot does not observe another delivery application, query a
/// platform, read a screen or watch the network, so it cannot know that an
/// order was accepted, that a restaurant handed it over or that a customer
/// received it. It knows only what the driver told it, and this model holds
/// exactly that and nothing more: no customer, no address and no order
/// identifier. The two things it does hold beyond the timestamps — a pickup
/// place and a gross amount — are there because the driver typed them, not
/// because anything was read from a platform.
///
/// ## The amount is a second independent fact
///
/// ``grossEarnings`` is unrelated to the amount recorded on the delivery's
/// shift. Neither is derived from the other, neither is checked against the
/// other, and nothing anywhere divides a shift total among its deliveries —
/// see ``setGrossEarnings(_:)``.
///
/// ## Expected and recorded are two more separate facts
///
/// A delivery can also carry ``expectedEarnings``: what the driver said they
/// expect it to pay, entered while it was still in progress. It is a third
/// independent fact, and the app never reads it as a fourth spelling of the
/// first two. ``grossEarnings`` stays the finalized recorded gross of a terminal
/// delivery and is the only amount any total, rate, period figure or export
/// summary is built from; an expectation is what the driver believed before
/// anything was paid. Finishing a delivery does not turn one into the other,
/// matching numbers do not make them the same fact, and the only thing that ever
/// writes a gross amount is the driver recording one.
///
/// ## State lives in the timestamps
///
/// There is no persisted `state` column and no set of booleans. ``state`` is
/// derived from which timestamps exist, so there is one authoritative answer to
/// what a delivery is doing and it is the same data that forms the historical
/// record. A stored state could drift out of step with the events it claims to
/// summarise; a derived one cannot.
///
/// ## Cancellation
///
/// A delivery can end without being delivered. ``cancel(at:)`` is available
/// from any active state and preserves whatever genuinely happened first — a
/// delivery cancelled after the driver waited twenty minutes at the pickup
/// still records that they arrived. A cancelled delivery is never deleted: it
/// is what happened.
///
/// ## Several at once
///
/// A delivery is independent of every other delivery. It owns its own
/// timestamps and derives its own state from them, so two, three or more can be
/// running at the same time with overlapping lifecycles — which is what stacked
/// delivery work actually is. Nothing here knows how many others exist, and no
/// shared "current delivery" state sits above these records deciding which one
/// an event belongs to.
@Model
nonisolated final class Delivery {
    /// Stable identifier, used for cross-store references and future export.
    @Attribute(.unique) private(set) var id: UUID

    /// When the driver started recording this delivery.
    ///
    /// Acceptance is the delivery's creation rather than a separate optional
    /// timestamp: a delivery that has not been accepted is a delivery that does
    /// not exist, and an `acceptedAt: Date?` would introduce a state the app can
    /// never be in. Every other lifecycle event is optional because it may
    /// genuinely not have happened.
    private(set) var acceptedAt: Date

    private(set) var arrivedAtPickupAt: Date?

    private(set) var pickedUpAt: Date?

    /// Set once the delivery is completed. Terminal, and mutually exclusive with
    /// ``cancelledAt`` because the transitions refuse a second terminal event.
    private(set) var deliveredAt: Date?

    /// When the driver recorded that the delivery ended without completing.
    private(set) var cancelledAt: Date?

    /// The shift this delivery belongs to.
    ///
    /// Optional because SwiftData models the inverse of a to-many relationship
    /// that way, not because a delivery without a shift is meaningful: the
    /// initializer requires one, `DeliveryService` refuses to create one outside
    /// a running shift, and `Shift.deliveries` cascades on delete so a delivery
    /// cannot outlive its shift.
    private(set) var shift: Shift?

    /// The accepted offer this delivery came in.
    ///
    /// One offer may contain several deliveries, and this is the only thing
    /// that says which ones arrived together. Two deliveries pointing at the
    /// same ``Offer`` were accepted in one act; two pointing at different
    /// offers were two decisions, however much their lifetimes overlap.
    ///
    /// **It groups; it does not govern.** Every lifecycle timestamp on this
    /// delivery is still this delivery's own, and nothing here reads a sibling's
    /// state: one delivery of an offer can be picked up while another is still
    /// waiting at a counter, and completing one leaves the others exactly as
    /// they were. See ``Offer``.
    ///
    /// Optional for two reasons, both about stores rather than about intent.
    /// SwiftData models the inverse of a to-many relationship that way; and a
    /// delivery recorded before offers existed had none until the v11 to v12
    /// migration gave it its own one-delivery offer. The app's own creation path
    /// always records one, and a row that somehow holds none is shown ungrouped
    /// rather than attached to an offer it was never part of.
    ///
    /// The shift is **not** read through here. ``shift`` stays the authority on
    /// which shift this delivery belongs to, unchanged and untouched by this
    /// version, so no fetch, aggregate, export figure or delete rule depends on
    /// an offer existing.
    private(set) var offer: Offer?

    /// Where the driver said this order was collected from, or `nil` if they did
    /// not say.
    ///
    /// Optional, and expected to be `nil` often: naming a pickup is a
    /// convenience the driver may take at a kerb, never a step the lifecycle
    /// waits for. Nothing in ``DeliveryService`` reads it, so every transition
    /// works exactly the same on a delivery with no place named.
    ///
    /// A reference rather than a stored string, so two deliveries from the same
    /// place point at the same row — see ``PickupPlace``. The delete rule is the
    /// default `.nullify`: deleting this delivery, or the shift it belongs to,
    /// leaves the place for every other delivery naming it.
    private(set) var pickupPlace: PickupPlace?

    /// Gross earnings for this delivery, exactly as entered, or `nil` if none
    /// were.
    ///
    /// Stored as a `Decimal` for the reason ``Shift/grossEarningsAmount`` is:
    /// SwiftData persists a `Decimal` as a decimal attribute, so the exact
    /// amount survives a round trip with no binary floating point anywhere in
    /// the store and no second monetary type in the app. The conversion is
    /// centralised in ``grossEarnings`` and ``setGrossEarnings(_:)``; nothing
    /// else reads this property, so the rest of the app only ever handles a
    /// ``Money``.
    ///
    /// **`nil` and zero are different facts.** `nil` means the driver has not
    /// recorded what this delivery paid; `0` means they recorded that it paid
    /// nothing. Migration never fabricates the second from the first, and
    /// nothing sums a shift's deliveries by reading a missing amount as zero.
    private var grossEarningsAmount: Decimal?

    /// What the driver currently expects this delivery to pay, exactly as
    /// entered, or `nil` if they have not said.
    ///
    /// **This is not ``grossEarningsAmount`` and never becomes it by itself.**
    /// The two are separate columns holding separate facts, and the app is
    /// careful never to read one as the other:
    ///
    /// - An **expected** amount is what the driver believes an *active* delivery
    ///   will pay. It is entered while the work is still happening, usually
    ///   while waiting at a pickup, from whatever the driver saw when they
    ///   accepted the order. Nothing confirms it and nothing is paid on it.
    /// - A **gross** amount is what the driver recorded a *terminal* delivery as
    ///   having paid. It is the finalized figure, and it is the only one any
    ///   total, rate, period figure or export summary is ever built from.
    ///
    /// The distinction holds **even when the two numbers are identical**. A
    /// delivery that was expected to pay `8.50` and has no gross recorded has
    /// not earned `8.50`; it has earned an amount nobody has written down yet.
    /// Reading the expectation as the record would put a figure into a driver's
    /// earnings history on the app's authority rather than theirs, and no later
    /// screen could tell it from one they confirmed.
    ///
    /// Stored as a `Decimal` for the reason ``grossEarningsAmount`` is, and read
    /// only through ``expectedEarnings``, ``setExpectedEarnings(_:)`` and
    /// ``clearExpectedEarnings()``.
    ///
    /// **`nil` and zero are different facts** here too. `nil` means no
    /// expectation was recorded; `0` means the driver recorded that they expect
    /// this delivery to pay nothing. Migration fabricates neither.
    ///
    /// It survives the delivery finishing rather than being consumed by it. That
    /// is what lets the app offer the figure back for confirmation afterwards,
    /// and what lets a driver see later that a delivery they expected `8.50`
    /// from paid `6.25` instead. Confirming an amount records a gross beside
    /// this one; it does not overwrite or erase it.
    private var expectedEarningsAmount: Decimal?

    /// - Parameter offer: the accepted offer this delivery came in. Defaulted to
    ///   `nil` so that a fixture exercising the lifecycle alone does not have to
    ///   construct a grouping it is not testing; the app's own creation path
    ///   goes through ``Shift/beginOffer(deliveryCount:at:)``, which always
    ///   supplies one.
    init(id: UUID = UUID(), shift: Shift, offer: Offer? = nil, acceptedAt: Date) {
        self.id = id
        self.acceptedAt = acceptedAt
        self.shift = shift
        self.offer = offer
    }

    /// Where the delivery has reached, read from its timestamps.
    ///
    /// The terminal states are checked first: a delivery that was cancelled
    /// after being picked up is cancelled, not picked up.
    var state: DeliveryState {
        if cancelledAt != nil { return .cancelled }
        if deliveredAt != nil { return .delivered }
        if pickedUpAt != nil { return .pickedUp }
        if arrivedAtPickupAt != nil { return .arrivedAtPickup }
        return .accepted
    }

    var isActive: Bool { state.isActive }

    /// The most recent lifecycle event recorded, which the next one must not
    /// precede.
    var lastEventAt: Date {
        cancelledAt ?? deliveredAt ?? pickedUpAt ?? arrivedAtPickupAt ?? acceptedAt
    }

    // MARK: Transitions

    /// Records that the driver reached the pickup.
    ///
    /// - Throws: ``DeliveryError`` if the delivery has finished, the event is
    ///   already recorded, or `date` precedes the last recorded event.
    func markArrivedAtPickup(at date: Date) throws {
        try validateTransition(at: date)
        guard arrivedAtPickupAt == nil else { throw DeliveryError.alreadyRecorded(.arrivedAtPickup) }
        arrivedAtPickupAt = date
    }

    /// Records that the order is in the car.
    ///
    /// - Throws: ``DeliveryError`` if the delivery has finished, the event is
    ///   already recorded, the arrival was never recorded, or `date` precedes
    ///   the last recorded event.
    func markPickedUp(at date: Date) throws {
        try validateTransition(at: date)
        guard pickedUpAt == nil else { throw DeliveryError.alreadyRecorded(.pickedUp) }
        guard arrivedAtPickupAt != nil else { throw DeliveryError.outOfOrder(missing: .arrivedAtPickup) }
        pickedUpAt = date
    }

    /// Records that the delivery was completed.
    ///
    /// - Throws: ``DeliveryError`` if the delivery has finished, the pickup was
    ///   never recorded, or `date` precedes the last recorded event.
    func markDelivered(at date: Date) throws {
        try validateTransition(at: date)
        guard pickedUpAt != nil else { throw DeliveryError.outOfOrder(missing: .pickedUp) }
        deliveredAt = date
    }

    /// Records that the delivery ended without being completed.
    ///
    /// Allowed from every active state, because an order can fall through at
    /// any point: before the driver arrives, while they wait, and after the
    /// food is in the car. Nothing already recorded is erased — a cancellation
    /// adds an ending, it does not rewrite the history that led to it.
    ///
    /// - Throws: ``DeliveryError`` if the delivery has already finished or
    ///   `date` precedes the last recorded event.
    func cancel(at date: Date) throws {
        try validateTransition(at: date)
        cancelledAt = date
    }

    // MARK: Correcting an accidental completion

    /// Removes the delivered timestamp, returning this delivery to the state its
    /// remaining timestamps describe.
    ///
    /// **The one place `deliveredAt` is ever cleared**, so the rules that decide
    /// whether there is anything truthful to restore cannot be bypassed by a
    /// screen, a test or a future caller. It lives here because that property's
    /// setter does, and it is written as one operation for the reason
    /// ``move(into:)`` is: a caller cannot clear the timestamp and then decide
    /// what the delivery became.
    ///
    /// ## It removes one timestamp and derives the rest
    ///
    /// ``acceptedAt``, ``arrivedAtPickupAt`` and ``pickedUpAt`` are left exactly
    /// as they are, and nothing is written in place of what is removed. The
    /// state that results is ``DeliveryRecovery``'s reading of the timestamps
    /// that stay, which is the same derivation ``state`` performs: there is no
    /// second opinion about what a delivery with these timestamps is doing.
    ///
    /// ## Nothing else on the delivery moves
    ///
    /// The pickup place, the expected amount and the recorded gross amount are
    /// untouched. A gross amount recorded against a delivery the driver has now
    /// reopened stays recorded: it is what they were told they were paid, the
    /// lifecycle correction says nothing about it, and removing money on the
    /// app's own authority is the one thing a recovery from a mis-tap must never
    /// do. ``setGrossEarnings(_:)`` still refuses to record a **new** amount
    /// while the delivery is active, which is unchanged and is a rule about
    /// writing rather than about holding.
    ///
    /// Reopening a delivery that is not recorded as delivered is refused rather
    /// than ignored, so invoking this twice writes nothing the second time.
    ///
    /// - Returns: the state the delivery is now in.
    /// - Throws: ``DeliveryRecoveryRefusal``.
    @discardableResult
    func reopenFromDelivered() throws -> DeliveryState {
        let recovery = try DeliveryRecovery(reopening: DeliveryLifecycleRecord(self))
        deliveredAt = nil
        return recovery.restoredState
    }

    // MARK: Pickup identity

    /// Names the place this order was collected from, or clears it with `nil`.
    ///
    /// Deliberately unconditional. Every other mutation on this model guards a
    /// lifecycle invariant, and this one has none to guard: a pickup place is not
    /// an event, it does not order against the timestamps, and correcting it a
    /// week later changes no interval, no duration and no rate. A delivery whose
    /// place was mistyped, or tapped on the wrong card, must be fixable without
    /// deleting the work it records.
    ///
    /// Resolving a typed name to a place — and reusing an existing one rather
    /// than creating a second — belongs to ``PickupPlaceService``, not here.
    func setPickupPlace(_ place: PickupPlace?) {
        pickupPlace = place
    }

    // MARK: Earnings

    /// Gross earnings recorded for this delivery, or `nil` if none were.
    ///
    /// "Gross" is the whole claim, exactly as it is on a shift. It is the figure
    /// the driver chose to associate with this delivery and nothing more:
    /// DashPilot does not know whether it includes a tip, a bonus or an
    /// adjustment, and it is not profit, take-home pay, a wage, a taxable amount
    /// or a payout any platform confirmed. Nothing is imported.
    var grossEarnings: Money? {
        grossEarningsAmount.map(Money.init(amount:))
    }

    /// Records what this delivery paid, replacing any amount already recorded.
    ///
    /// Two invariants, kept on the model rather than in a view so that no
    /// screen, test or future caller can set an amount the app would refuse to
    /// display:
    ///
    /// - Only a **finished** delivery can carry earnings. A delivery still in
    ///   progress has not been paid yet, and a monetary text field on a card the
    ///   driver may be looking at from a moving car is exactly the interaction
    ///   this project designs away. A cancelled delivery may carry an amount:
    ///   compensation for a cancelled order is real, and refusing to record it
    ///   would force the driver to attribute it somewhere it did not happen.
    ///   Nothing requires a cancelled delivery to be zero.
    /// - The amount may not be **negative**, for the reason a shift's may not:
    ///   a delivery that cost money is an expense, and expenses are not recorded
    ///   anywhere yet. Zero is allowed and meaningful.
    ///
    /// **Nothing here reads, writes or checks the shift's own amount.** The two
    /// are independent facts a driver entered separately, and they are free to
    /// differ: deliveries may go unrecorded, a stacked pair may be paid as one,
    /// and adjustments and incentives may post at shift level. DashPilot does
    /// not reconcile them, does not warn about the difference, and never
    /// allocates a shift total across deliveries.
    ///
    /// - Throws: ``DeliveryError/deliveryNotFinished`` or
    ///   ``DeliveryError/negativeEarnings``.
    func setGrossEarnings(_ earnings: Money) throws {
        guard state.isFinished else { throw DeliveryError.deliveryNotFinished }
        guard !earnings.isNegative else { throw DeliveryError.negativeEarnings }
        grossEarningsAmount = earnings.amount
    }

    /// Removes the recorded amount, returning the delivery to having none.
    ///
    /// Deliberately distinct from recording `0`, and deliberately unconditional
    /// for the reason ``setPickupPlace(_:)`` is: a delivery with no amount to
    /// remove is already in the state the caller asked for, and a driver
    /// deleting a figure they entered by mistake is saying "I have not recorded
    /// this", not "this delivery paid nothing".
    func clearGrossEarnings() {
        grossEarningsAmount = nil
    }

    // MARK: Expected earnings

    /// What the driver expects this delivery to pay, or `nil` if they have not
    /// said.
    ///
    /// **Never a substitute for ``grossEarnings``.** It is an expectation the
    /// driver typed, not a payment anything confirmed, and no caller in the app
    /// falls back to it when the gross amount is missing. Deliberately a
    /// different property name rather than a flag on one amount, so that reading
    /// the wrong fact requires writing the wrong word.
    var expectedEarnings: Money? {
        expectedEarningsAmount.map(Money.init(amount:))
    }

    /// Whether this delivery carries an expectation with no recorded gross
    /// beside it.
    ///
    /// The state the completion flow and the history screen both offer to
    /// resolve: something is expected, nothing is recorded. It is a question
    /// about which facts exist, never a suggestion that the expected figure
    /// should be treated as the recorded one.
    var hasUnconfirmedExpectedEarnings: Bool {
        expectedEarningsAmount != nil && grossEarningsAmount == nil
    }

    /// Records what the driver expects this delivery to pay, replacing any
    /// expectation already recorded.
    ///
    /// Two invariants, the mirror of ``setGrossEarnings(_:)``'s and kept on the
    /// model for the same reason:
    ///
    /// - Only an **active** delivery can carry an expectation. Once a delivery
    ///   is delivered or cancelled it is no longer something to have
    ///   expectations about, and the fact worth recording is what it paid.
    ///   Allowing an expectation to be written afterwards would invite exactly
    ///   the confusion this pair of columns exists to prevent: a figure that
    ///   looks like a late correction to earnings while being stored as
    ///   something no total will ever count.
    /// - The amount may not be **negative**, for the reason a gross amount may
    ///   not. Zero is allowed and means the driver expects this delivery to pay
    ///   nothing, which is a real thing to expect.
    ///
    /// **Nothing here touches ``grossEarningsAmount``**, on this delivery or on
    /// any other, and nothing reads the shift's own amount. Recording an
    /// expectation changes no total, no rate, no period figure and no export
    /// summary anywhere in the app.
    ///
    /// - Throws: ``DeliveryError/deliveryNotActive`` or
    ///   ``DeliveryError/negativeExpectedEarnings``.
    func setExpectedEarnings(_ expected: Money) throws {
        guard state.isActive else { throw DeliveryError.deliveryNotActive }
        guard !expected.isNegative else { throw DeliveryError.negativeExpectedEarnings }
        expectedEarningsAmount = expected.amount
    }

    /// Removes the recorded expectation, returning the delivery to having none.
    ///
    /// Unconditional, and available after the delivery has finished, unlike
    /// ``setExpectedEarnings(_:)``. Removing a figure claims nothing, and a
    /// driver whose expectation turned out to be wrong must be able to take it
    /// off a delivery whose gross they have already recorded. Distinct from
    /// recording `0`, for the reason ``clearGrossEarnings()`` is.
    func clearExpectedEarnings() {
        expectedEarningsAmount = nil
    }

    /// The two rules every transition shares: a finished delivery does not
    /// transition again, and the lifecycle does not run backwards.
    private func validateTransition(at date: Date) throws {
        let current = state
        guard current.isActive else { throw DeliveryError.alreadyFinished(current) }
        guard date >= lastEventAt else { throw DeliveryError.timestampPrecedesLastEvent }
    }

    // MARK: Derived intervals

    /// How long the driver waited at the pickup, once both ends of the wait
    /// exist.
    ///
    /// `nil` whenever either event is missing. A delivery cancelled before the
    /// driver arrived, or one still waiting, has no wait to report, and
    /// substituting "now" or zero would invent one.
    ///
    /// Also `nil` for a pickup recorded before the arrival it followed, which
    /// the transitions make unreachable. Unlike ``completedDuration`` this one
    /// is not clamped, because a pickup wait is an *observation*: it is counted
    /// into a place's history, and a zero standing in for an impossible interval
    /// would enter that history as a real wait of no length. Absence is the
    /// honest answer, and ``PickupWaitSample`` excludes the same rows.
    var pickupWait: TimeInterval? {
        guard let arrivedAtPickupAt, let pickedUpAt, pickedUpAt >= arrivedAtPickupAt else { return nil }
        return pickedUpAt.timeIntervalSince(arrivedAtPickupAt)
    }

    /// How long the whole delivery took, from acceptance to completion.
    ///
    /// `nil` unless the delivery was actually delivered. A cancelled delivery
    /// has a duration in the ordinary sense, but calling it a delivery duration
    /// would put it in the same column as deliveries that finished.
    var completedDuration: TimeInterval? {
        guard let deliveredAt else { return nil }
        return clamped(from: acceptedAt, to: deliveredAt)
    }

    /// The transitions refuse a backwards timestamp, so this cannot go negative
    /// through the domain API. It is clamped anyway, for the same reason
    /// ``Shift`` clamps: a store that somehow holds anomalous rows must not
    /// produce a negative duration on a driver's screen.
    private func clamped(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

extension Delivery {
    /// Builds the one-delivery offer a delivery recorded before offers existed
    /// belongs in, and attaches this delivery to it.
    ///
    /// **The v11 to v12 migration's only write.** It lives here because
    /// ``offer``'s setter does, and it is written as a single operation so that
    /// the migration cannot do anything but give an ungrouped delivery its own
    /// offer.
    ///
    /// It is not the only way a delivery's offer changes any more. ``move(into:)``
    /// corrects the grouping of deliveries that already exist, under invariants
    /// this method does not need: there is nothing to correct about a delivery
    /// that records no offer at all.
    ///
    /// Returns `nil`, changing nothing, in the two cases where there is no
    /// truthful offer to build:
    ///
    /// - the delivery already records one, so the caller would be overwriting a
    ///   grouping the driver's own work produced
    /// - the delivery is attached to no shift, which is a store the app cannot
    ///   produce. The row is left exactly as it is, for the reason nothing else
    ///   in the app repairs, reparents or deletes one.
    ///
    /// The offer takes this delivery's own acceptance timestamp, because that is
    /// the only acceptance the store records and it is a real one: the driver
    /// tapped it.
    func makeHistoricalOffer() -> Offer? {
        guard offer == nil, let shift else { return nil }
        let historical = Offer(shift: shift, acceptedAt: acceptedAt)
        offer = historical
        return historical
    }

    /// Records this delivery under `offer` instead of the one it is under now,
    /// and returns the offer it left.
    ///
    /// **The one place a delivery's grouping changes**, so the invariants that
    /// hold membership together cannot be bypassed by a screen, a test or a
    /// future caller. It lives here because ``offer``'s setter does.
    ///
    /// ## It moves membership and nothing else
    ///
    /// Every lifecycle timestamp, the pickup place, the expected amount, the
    /// recorded gross and the terminal state are left exactly as they are, on
    /// this delivery and on every delivery of either offer. A grouping mistake
    /// is a mistake about which deliveries arrived together; it is not a claim
    /// that anything else the driver recorded was wrong, and correcting it must
    /// not quietly rewrite work that happened.
    ///
    /// ``shift`` is untouched, and a move across shifts is refused rather than
    /// performed: that reference is what every fetch, aggregate, export figure
    /// and delete rule in the app is built on.
    ///
    /// ## Neither acceptance timestamp moves
    ///
    /// ``acceptedAt`` stays what the driver recorded, and so does the
    /// destination's ``Offer/acceptedAt``. The one relationship enforced between
    /// them is ``Offer/couldHaveContained(_:)``: an offer cannot come to contain
    /// a delivery accepted before it. They are not required to be equal, because
    /// the commonest grouping mistake is two taps a minute apart.
    ///
    /// The offer left behind is **returned rather than emptied here**. Whether a
    /// now-empty offer is removed is a decision about rows in a store, so it
    /// belongs to ``OfferCorrectionService`` and to the one save it makes.
    ///
    /// - Throws: ``OfferMembershipError/differentShift``,
    ///   ``OfferMembershipError/alreadyInThatOffer`` or
    ///   ``OfferMembershipError/deliveryPrecedesOfferAcceptance``.
    @discardableResult
    func move(into destination: Offer) throws -> Offer? {
        guard let shift, destination.shift?.id == shift.id else {
            throw OfferMembershipError.differentShift
        }
        guard offer?.id != destination.id else {
            throw OfferMembershipError.alreadyInThatOffer
        }
        guard destination.couldHaveContained(acceptedAt) else {
            throw OfferMembershipError.deliveryPrecedesOfferAcceptance
        }

        let previous = offer
        offer = destination
        return previous
    }
}

extension Delivery {
    /// Deterministic order for a shift's deliveries: earliest acceptance first,
    /// with identity breaking a tie.
    ///
    /// The order has to be total and repeatable, because it decides which
    /// concurrent delivery is labelled `Delivery 1` and which is `Delivery 2`.
    /// Acceptance time alone is not enough: two deliveries accepted in the same
    /// instant would be free to swap places between two reads, and the labels on
    /// screen would swap with them. Identity is an arbitrary tie-break, but an
    /// arbitrary *stable* one is exactly what is needed, and a tie is only
    /// reachable when two taps land on the same instant.
    ///
    /// SwiftData's own fetch order is not relied on anywhere, for the same
    /// reason: it is incidental, and reading a delivery's number out of it would
    /// be reading meaning into an implementation detail.
    static func acceptedBefore(_ lhs: Delivery, _ rhs: Delivery) -> Bool {
        if lhs.acceptedAt != rhs.acceptedAt { return lhs.acceptedAt < rhs.acceptedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
