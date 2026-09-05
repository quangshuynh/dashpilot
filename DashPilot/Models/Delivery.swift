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
/// exactly that and nothing more: no restaurant, no customer, no address, no
/// order identifier and no per-delivery amount.
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
    var pickupWait: TimeInterval? {
        guard let arrivedAtPickupAt, let pickedUpAt else { return nil }
        return clamped(from: arrivedAtPickupAt, to: pickedUpAt)
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
