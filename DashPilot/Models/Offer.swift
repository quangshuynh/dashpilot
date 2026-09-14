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

/// Errors raised when correcting which offer a delivery is recorded under would
/// violate the model's invariants.
///
/// Apart from ``OfferError`` deliberately. That one is about **recording** an
/// acceptance, and is raised before any row exists; these are about
/// **regrouping** rows that already exist, and every one of them is a refusal
/// to make the store say something the driver cannot have witnessed.
nonisolated enum OfferMembershipError: Error, Equatable {
    /// The delivery and the offer belong to different shifts, or one of them
    /// belongs to no shift at all.
    ///
    /// ``Delivery/shift`` stays the authority on which shift a delivery belongs
    /// to, and correction never touches it: every fetch, aggregate, export
    /// figure and delete rule in the app is built on that reference, and moving
    /// a delivery across shifts through an offer would rewrite a driver's
    /// history to express a grouping mistake.
    case differentShift
    /// The delivery is already recorded under that offer, so there is nothing
    /// to move.
    case alreadyInThatOffer
    /// The delivery was accepted before the offer it would move into.
    ///
    /// An offer is an acceptance, and a delivery it contained cannot have been
    /// accepted before it happened. Refused rather than fixed by moving either
    /// timestamp: the two are recorded facts, and a correction that silently
    /// rewrote one to make the other fit would be inventing the acceptance
    /// history this app exists to record honestly. Splitting the delivery into a
    /// new offer is always available instead, and takes a timestamp the driver
    /// really recorded.
    case deliveryPrecedesOfferAcceptance
    /// A new offer was asked for with no deliveries to put in it.
    case noDeliveriesToGroup
    /// Deliveries from more than one offer were regrouped in a single
    /// operation.
    ///
    /// Each one is its own correction, with its own confirmation. A screen that
    /// moved deliveries out of several offers at once would be describing
    /// something no confirmation sentence can state plainly.
    case deliveriesFromDifferentOffers
    /// Every delivery of an offer was asked to move into a new one.
    ///
    /// That records the same grouping under a different row, and it would move
    /// the acceptance timestamp to the earliest delivery's own, which is a
    /// silent rewrite of when the driver accepted. Refused as the no-op it is.
    case wouldRegroupEveryDelivery
    /// An offer holding one delivery was asked to be separated into several.
    case offerIsNotGrouped
    /// An offer was named as both the source and the destination of a merge.
    case cannotMergeIntoItself
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
    /// it. In practice it runs when the whole shift is deleted, where the
    /// deliveries are going anyway.
    ///
    /// One other path deletes an offer, and it is written so that this rule
    /// never reaches a delivery. ``OfferCorrectionService`` removes an offer
    /// left holding nothing once its deliveries have moved elsewhere, and it
    /// deletes only an offer whose ``deliveries`` is already empty. An offer is
    /// never deleted to remove the deliveries under it.
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

    /// Whether a delivery accepted at `date` could have arrived in this offer.
    ///
    /// The one ordering rule membership correction keeps: an offer is an
    /// acceptance, so a delivery it contained was accepted at that moment or
    /// afterwards. It is asked here rather than restated at each call site, so
    /// the list of offers a screen presents and the refusal the model raises are
    /// the same rule.
    ///
    /// Nothing about the two timestamps is required to be **equal**. Two taps a
    /// minute apart that were really one acceptance are exactly the mistake this
    /// correction exists for, and requiring equality would refuse to fix it.
    func couldHaveContained(_ date: Date) -> Bool { acceptedAt <= date }

    /// The earliest acceptance recorded by a delivery in this offer, or `nil`
    /// for an offer holding none.
    var earliestDeliveryAcceptance: Date? { deliveries.map(\.acceptedAt).min() }

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
