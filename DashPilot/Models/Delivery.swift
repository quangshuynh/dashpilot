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
    /// A negative amount was recorded as gross earnings.
    case negativeEarnings
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

    init(id: UUID = UUID(), shift: Shift, acceptedAt: Date) {
        self.id = id
        self.acceptedAt = acceptedAt
        self.shift = shift
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
