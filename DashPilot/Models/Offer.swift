import Foundation
import SwiftData

/// Errors raised when recording an offer would violate the model's invariants.
nonisolated enum OfferError: Error, Equatable {
    /// An offer was recorded with fewer than one delivery in it.
    ///
    /// An offer with no deliveries records an acceptance with no work attached
    /// to it, which is not a thing the driver can have witnessed.
    case deliveryCountNotPositive
    /// An offer was recorded against a shift that has already ended.
    case shiftAlreadyEnded
    /// The acceptance timestamp precedes the shift's own start.
    case acceptedBeforeShiftStart
}

/// One accepted offer, and the deliveries the driver said it contained.
///
/// ## What an offer is, and how it differs from a delivery
///
/// An **offer** is one acceptance event: the driver was shown work, they took
/// it, and this row records that moment. A **delivery** is one customer
/// dropoff, with its own pickup, its own terminal event and its own lifecycle.
/// The two are not the same fact, because real work does not make them the
/// same fact: an accepted offer routinely contains two dropoffs, occasionally
/// more, sometimes from two different pickups.
///
/// Before this type existed the app recorded only the second half. Two
/// deliveries the driver accepted in one tap were indistinguishable from two
/// they accepted ten minutes apart, and nothing in the store said they arrived
/// together.
///
/// ## Nothing here is a platform's
///
/// DashPilot reads no delivery platform, sees no offer screen and receives no
/// notification. This row exists because the driver said how many deliveries
/// they had just accepted, and it holds nothing beyond that: no offer
/// identifier, no platform name, no pay figure, no distance estimate and no
/// customer. An offer here is a **grouping the driver recorded**, not a message
/// anything sent.
///
/// ## An add-on offer is a different offer
///
/// Accepting more work while deliveries are already running records a new
/// offer, always. Two offers whose deliveries overlap in time are still two
/// acceptances, and nothing merges them: overlapping lifetimes are what stacked
/// delivery work looks like, and treating them as one acceptance would erase
/// the fact that the driver decided twice.
///
/// ## It carries one timestamp, and the deliveries keep their own
///
/// ``acceptedAt`` is when the offer was accepted. Every delivery keeps its own
/// ``Delivery/acceptedAt`` and every one of its lifecycle timestamps, which is
/// what lets the deliveries of one offer advance independently: one can be
/// picked up while another is still waiting at a counter. Nothing here is a
/// second copy of a delivery's lifecycle, and no figure anywhere is derived
/// from this timestamp in place of a delivery's own.
///
/// ## No money
///
/// An offer holds no amount. Expected pay and recorded gross earnings stay on
/// the delivery, and nothing sums them into an offer total: a sum over
/// deliveries with no amount recorded would read each one as having paid
/// nothing, which is the allocation the project refuses everywhere else.
@Model
nonisolated final class Offer {
    /// Stable identifier, for the reason ``Shift`` has one. Local to this
    /// device, and not an identifier any delivery platform would recognise.
    @Attribute(.unique) private(set) var id: UUID

    /// When the driver recorded accepting this offer.
    ///
    /// Acceptance is the offer's creation rather than a separate optional
    /// timestamp, for the reason it is a delivery's: an offer that has not been
    /// accepted is an offer that does not exist.
    private(set) var acceptedAt: Date

    /// The shift this offer was accepted during.
    ///
    /// Optional because SwiftData models the inverse of a to-many relationship
    /// that way, not because an offer without a shift is meaningful: the
    /// initializer requires one, ``DeliveryService`` records one only on a
    /// running shift, and `Shift.offers` cascades on delete.
    private(set) var shift: Shift?

    /// The deliveries this offer contained, in no guaranteed order.
    ///
    /// The delete rule is `.cascade`, for the reason a shift's deliveries
    /// cascade: a delivery recorded inside an offer means nothing apart from
    /// it. Nothing in the app deletes an offer on its own, so in practice this
    /// runs only when the whole shift is deleted, where the deliveries are
    /// going anyway.
    @Relationship(deleteRule: .cascade, inverse: \Delivery.offer)
    private(set) var deliveries: [Delivery] = []

    init(id: UUID = UUID(), shift: Shift, acceptedAt: Date) {
        self.id = id
        self.acceptedAt = acceptedAt
        self.shift = shift
    }

    /// This offer's deliveries in the order they are numbered.
    var deliveriesInOrder: [Delivery] { deliveries.sorted(by: Delivery.acceptedBefore) }

    /// How many deliveries the driver said this offer contained.
    var deliveryCount: Int { deliveries.count }

    /// Whether this offer contains more than one delivery.
    ///
    /// The question the interface actually asks: a one-delivery offer is the
    /// ordinary case and needs no grouping shown, and anything above one does.
    var isGrouped: Bool { deliveryCount > 1 }

    /// The deliveries of this offer that are still running.
    var activeDeliveries: [Delivery] { deliveriesInOrder.filter(\.isActive) }

    /// Where this offer has reached, derived from its deliveries.
    var state: OfferState { OfferState(deliveryStates: deliveries.map(\.state)) }

    /// Whether every delivery in this offer has finished.
    var isTerminal: Bool { state.isTerminal }

    /// How the deliveries of this offer ended.
    var deliverySummary: DeliverySummary { DeliverySummary(states: deliveries.map(\.state)) }
}

extension Offer {
    /// Deterministic order for a shift's offers: earliest acceptance first,
    /// with identity breaking a tie.
    ///
    /// The same rule, for the same reason, as ``Delivery/acceptedBefore(_:_:)``:
    /// the order decides which offer is called `Offer 1`, so it has to be total
    /// and repeatable rather than whatever a fetch happened to return.
    static func acceptedBefore(_ lhs: Offer, _ rhs: Offer) -> Bool {
        if lhs.acceptedAt != rhs.acceptedAt { return lhs.acceptedAt < rhs.acceptedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
