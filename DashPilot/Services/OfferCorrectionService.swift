import Foundation
import OSLog
import SwiftData

/// Failures raised when a grouping correction cannot be applied.
///
/// A thin layer over ``OfferMembershipError``: the model owns which corrections
/// are truthful, and this adds only the two things a store can go wrong with.
nonisolated enum OfferCorrectionError: Error {
    /// The model refused the correction.
    case invalidMembership(OfferMembershipError)
    /// An offer in the operation is not, or is no longer, a row the store holds.
    case offerNoLongerExists
    /// A delivery in the operation is not, or is no longer, a row the store
    /// holds.
    case deliveryNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension OfferCorrectionError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidMembership(lhsError), .invalidMembership(rhsError)): lhsError == rhsError
        case (.offerNoLongerExists, .offerNoLongerExists): true
        case (.deliveryNoLongerExists, .deliveryNoLongerExists): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension OfferCorrectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidMembership(.differentShift):
            "Deliveries can only be regrouped within the shift they were recorded in."
        case .invalidMembership(.alreadyInThatOffer):
            "That delivery is already in that offer, so nothing was changed."
        case .invalidMembership(.deliveryPrecedesOfferAcceptance):
            """
            That delivery was accepted before the offer you chose, so it cannot have arrived in it. \
            Choose an offer accepted earlier, or put the delivery in a new offer of its own.
            """
        case .invalidMembership(.noDeliveriesToGroup):
            "Choose at least one delivery to put in a new offer."
        case .invalidMembership(.deliveriesFromDifferentOffers):
            "Deliveries from different offers are moved one offer at a time."
        case .invalidMembership(.wouldRegroupEveryDelivery):
            """
            Every delivery in that offer was chosen, which would record the same grouping again. \
            Leave at least one delivery where it is.
            """
        case .invalidMembership(.offerIsNotGrouped):
            "That offer holds a single delivery already, so there is nothing to separate."
        case .invalidMembership(.cannotMergeIntoItself):
            "An offer cannot be combined with itself. Choose a different offer."
        case .offerNoLongerExists:
            "That offer is no longer in DashPilot, so nothing was changed."
        case .deliveryNoLongerExists:
            "That delivery is no longer in DashPilot, so nothing was changed."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the grouping was not changed."
        }
    }
}

/// Correcting which deliveries a driver recorded as having arrived together.
///
/// ## Why this exists
///
/// An offer is a grouping the driver recorded by hand, at a kerb, in a hurry. A
/// driver who pressed `Start Delivery` twice for what was really one stacked
/// offer, or who said two and was handed three, has a store that says something
/// about their work that is not true. Nothing detects that, because DashPilot
/// reads no delivery platform and infers no relationship between deliveries, so
/// the correction is theirs to make explicitly.
///
/// ## What a correction is, and what it is emphatically not
///
/// **It moves membership.** A correction changes which offer owns a delivery and
/// nothing else. No lifecycle timestamp, pickup place, expected amount, recorded
/// gross or terminal state moves with it, on the delivery being corrected or on
/// any of its old or new siblings, and no figure the app derives from those
/// facts can move either: shift gross, delivery gross, delivery active time,
/// recorded mileage, pickup waits, period aggregates and the Live Activity's
/// active count are all read from deliveries, and none of them asks which offer
/// a delivery came in.
///
/// **Neither acceptance timestamp is rewritten.** ``Delivery/acceptedAt`` is what
/// the driver recorded and stays that; an existing ``Offer/acceptedAt`` is the
/// acceptance that offer records and stays that. The two are not required to be
/// equal after a correction, because the commonest mistake being corrected is
/// two taps a minute apart, and requiring equality would refuse to fix it. The
/// one ordering rule is ``Offer/couldHaveContained(_:)``, enforced by
/// ``Delivery/move(into:)``: an offer may not come to hold a delivery accepted
/// before the offer itself was.
///
/// **Nothing is invented.** A new offer built by a split takes the earliest
/// acceptance among the deliveries moving into it, which is a moment the driver
/// really recorded. Nobody is asked to type an acceptance time, because a time
/// typed from memory is platform history the driver does not have.
///
/// ## Four operations, one primitive
///
/// ``move(_:into:)``, ``split(_:)``, ``merge(_:into:)`` and ``separate(_:)`` are
/// all built from ``Delivery/move(into:)`` plus one rule about the offer left
/// behind, rather than from four write paths that can drift apart. A merge is
/// exactly moving every delivery of one offer into another and then removing the
/// offer left holding nothing; it has no logic of its own.
///
/// ## An offer left holding nothing is removed
///
/// In the same write. An offer records an acceptance, and an acceptance with no
/// work under it is not something a driver witnessed; letting empty shells
/// accumulate through ordinary correction would put rows in a driver's history
/// that no screen can explain and that every offer count would have to exclude.
/// ``OfferState/empty`` stays in the domain for the store it was written for:
/// rows the app cannot produce, which the interface must still read without
/// crashing.
///
/// Deletion is guarded rather than assumed. `Offer.deliveries` cascades, so an
/// offer is deleted only once that relationship is genuinely empty; an offer
/// that still lists a delivery is left standing and the anomaly is logged.
///
/// ## One save
///
/// Every operation mutates and commits exactly once. A merge that saved between
/// each delivery could leave the worst outcome available, a half-moved offer
/// beside a source still standing, and a driver whose history is now wrong in a
/// new way. A refused save rolls the context back instead, and the store holds
/// exactly the grouping it held before.
///
/// ## Available on finished shifts
///
/// Deliberately, and it bypasses no lifecycle rule because it performs no
/// lifecycle transition. History is where a driver reviews what they recorded
/// and where a grouping mistake is actually noticed, and a terminal delivery is
/// not a reason to refuse: the correction says which deliveries arrived
/// together, not what happened to them. Correction never crosses shifts.
///
/// `@MainActor` isolated like every other service here: operations run to
/// completion without suspending, so no caller interleaves a read with the write
/// that follows it.
@MainActor
struct OfferCorrectionService {
    private let context: ModelContext

    /// How a change is handed to the store. Injectable for the reason
    /// ``DeliveryService``'s is: every claim here about what a refused save
    /// leaves behind is untestable while the save can only succeed.
    private let commit: (ModelContext) throws -> Void

    init(context: ModelContext, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.commit = commit
    }

    // MARK: Moving one delivery

    /// Records `delivery` under `destination` instead of the offer it is under
    /// now, removing that offer if the move leaves it holding nothing.
    ///
    /// The delivery keeps every one of its own recorded facts. A delivery that
    /// records no offer at all, which only a store the app cannot produce holds,
    /// is moved in exactly the same way and leaves nothing behind.
    ///
    /// - Throws: ``OfferCorrectionError/invalidMembership(_:)``,
    ///   ``OfferCorrectionError/deliveryNoLongerExists``,
    ///   ``OfferCorrectionError/offerNoLongerExists`` or
    ///   ``OfferCorrectionError/storeUnavailable(underlying:)``.
    func move(_ delivery: Delivery, into destination: Offer) throws {
        try requireRecorded(delivery)
        try requireRecorded(destination)

        let emptied: Offer?
        do {
            emptied = try delivery.move(into: destination)
        } catch let error as OfferMembershipError {
            // Nothing has been mutated: the model checks before it assigns.
            AppLog.delivery.notice(
                "Refused a grouping correction: \(String(describing: error), privacy: .public)"
            )
            throw OfferCorrectionError.invalidMembership(error)
        }

        removeIfEmptied(emptied)
        try save(describing: "move a delivery between offers")

        // Structural only: that a delivery changed offers. Never which delivery,
        // which offers, when any of it happened, how many deliveries either
        // offer now holds, or anything the delivery records.
        AppLog.delivery.info("Delivery moved between offers")
    }

    // MARK: Splitting into a new offer

    /// Records `deliveries` as a new offer of their own, taking them out of the
    /// offer they share now.
    ///
    /// The new offer's acceptance is derived by ``Shift/makeOffer(regrouping:)``
    /// from the deliveries themselves. Creating it is explicit: this is the only
    /// way a correction adds an offer, and it is never done on the driver's
    /// behalf as a side effect of some other operation.
    ///
    /// Splitting **every** delivery of an offer is refused. It would record the
    /// same grouping under a new row while quietly moving the acceptance forward
    /// to the earliest delivery's own timestamp, which is the silent rewrite this
    /// service exists to avoid.
    ///
    /// - Returns: the offer that now holds them.
    /// - Throws: ``OfferCorrectionError/invalidMembership(_:)``,
    ///   ``OfferCorrectionError/deliveryNoLongerExists`` or
    ///   ``OfferCorrectionError/storeUnavailable(underlying:)``.
    @discardableResult
    func split(_ deliveries: [Delivery]) throws -> Offer {
        for delivery in deliveries { try requireRecorded(delivery) }

        guard let first = deliveries.first else {
            throw OfferCorrectionError.invalidMembership(.noDeliveriesToGroup)
        }
        guard let shift = first.shift else {
            throw OfferCorrectionError.invalidMembership(.differentShift)
        }

        // One source offer, so the confirmation a driver saw can describe what
        // moved. `nil` on every delivery is the ungrouped store, and is allowed.
        let source = first.offer
        guard deliveries.allSatisfy({ $0.offer?.id == source?.id }) else {
            throw OfferCorrectionError.invalidMembership(.deliveriesFromDifferentOffers)
        }
        if let source, source.deliveryCount == deliveries.count {
            throw OfferCorrectionError.invalidMembership(.wouldRegroupEveryDelivery)
        }

        let offer: Offer
        do {
            offer = try shift.makeOffer(regrouping: deliveries)
        } catch let error as OfferMembershipError {
            // A delivery may already have moved before a later one was refused,
            // so the context is returned to what the store holds.
            context.rollback()
            AppLog.delivery.notice(
                "Refused a grouping correction: \(String(describing: error), privacy: .public)"
            )
            throw OfferCorrectionError.invalidMembership(error)
        }

        // Explicitly, rather than letting a relationship carry it in: a failed
        // save must roll back exactly what this call put in.
        context.insert(offer)
        try save(describing: "split deliveries into a new offer")

        AppLog.delivery.info("Deliveries split into a new offer")
        return offer
    }

    // MARK: Merging two offers

    /// Moves every delivery of `source` into `destination`, then removes
    /// `source`.
    ///
    /// **No merge logic of its own.** It is the move above, applied to each
    /// delivery, in one write; `source` is removed only once every one of them
    /// has actually moved, and a refusal anywhere leaves the store holding both
    /// offers exactly as they were.
    ///
    /// `destination` keeps its own identity and its own acceptance. Nothing is
    /// combined, averaged or recorded about the merge: the source contributes
    /// its deliveries and nothing else, and each of those keeps every fact it
    /// already carried.
    ///
    /// - Throws: ``OfferCorrectionError/invalidMembership(_:)``,
    ///   ``OfferCorrectionError/offerNoLongerExists`` or
    ///   ``OfferCorrectionError/storeUnavailable(underlying:)``.
    func merge(_ source: Offer, into destination: Offer) throws {
        try requireRecorded(source)
        try requireRecorded(destination)

        guard source.id != destination.id else {
            throw OfferCorrectionError.invalidMembership(.cannotMergeIntoItself)
        }

        let moving = source.deliveriesInOrder
        do {
            for delivery in moving {
                try delivery.move(into: destination)
            }
        } catch let error as OfferMembershipError {
            // Half the deliveries may have moved already. The context is rolled
            // back so no partly merged grouping can reach the store or the
            // screen that asked for it.
            context.rollback()
            AppLog.delivery.notice(
                "Refused a grouping correction: \(String(describing: error), privacy: .public)"
            )
            throw OfferCorrectionError.invalidMembership(error)
        }

        removeIfEmptied(source)
        try save(describing: "combine two offers")

        AppLog.delivery.info("Two offers combined")
    }

    // MARK: Separating a grouped offer

    /// Records each delivery of `offer` as an offer of its own, for a driver who
    /// grouped deliveries that did not arrive together.
    ///
    /// The first delivery in the shift's own order stays where it is, so the
    /// acceptance the driver recorded survives on the row that already held it
    /// rather than being replaced by a copy. Every other delivery becomes a
    /// one-delivery offer taking its own acceptance, which is the shape
    /// `Start Delivery` records and the shape a migrated store is full of.
    ///
    /// - Returns: the offers created, in the order their deliveries are numbered.
    /// - Throws: ``OfferCorrectionError/invalidMembership(_:)``,
    ///   ``OfferCorrectionError/offerNoLongerExists`` or
    ///   ``OfferCorrectionError/storeUnavailable(underlying:)``.
    @discardableResult
    func separate(_ offer: Offer) throws -> [Offer] {
        try requireRecorded(offer)

        guard offer.isGrouped else {
            throw OfferCorrectionError.invalidMembership(.offerIsNotGrouped)
        }
        guard let shift = offer.shift else {
            throw OfferCorrectionError.invalidMembership(.differentShift)
        }

        let separated = offer.deliveriesInOrder.dropFirst()
        var created: [Offer] = []
        do {
            for delivery in separated {
                created.append(try shift.makeOffer(regrouping: [delivery]))
            }
        } catch let error as OfferMembershipError {
            context.rollback()
            AppLog.delivery.notice(
                "Refused a grouping correction: \(String(describing: error), privacy: .public)"
            )
            throw OfferCorrectionError.invalidMembership(error)
        }

        for new in created { context.insert(new) }
        try save(describing: "separate an offer into one-delivery offers")

        AppLog.delivery.info("An offer was separated into one-delivery offers")
        return created
    }

    // MARK: Destinations

    /// The offers `delivery` could truthfully be moved into, in the order its
    /// shift accepted them.
    ///
    /// Its own offer is excluded, because moving a delivery where it already is
    /// changes nothing, and so is any offer accepted after the delivery was: an
    /// offer cannot come to contain work accepted before it happened. The list a
    /// screen shows and the refusal the model raises are therefore the same rule,
    /// and a screen cannot offer a destination that would be refused.
    ///
    /// Nothing is suggested, scored or ordered by similarity. DashPilot does not
    /// know which two of a driver's offers were really one, and a list that
    /// pretended otherwise would make the wrong correction the easy tap.
    func moveDestinations(for delivery: Delivery) -> [Offer] {
        guard let shift = delivery.shift else { return [] }
        return shift.offersInOrder.filter { candidate in
            candidate.id != delivery.offer?.id && candidate.couldHaveContained(delivery.acceptedAt)
        }
    }

    /// The offers `offer`'s deliveries could truthfully be moved into, in the
    /// order its shift accepted them.
    ///
    /// The same rule applied to every delivery that would move, so a destination
    /// on this list accepts all of them or is not on it. An offer holding
    /// nothing has nothing to move and offers every other offer of its shift,
    /// which is how a merge repairs an anomalous empty row rather than tripping
    /// over it.
    func mergeDestinations(for offer: Offer) -> [Offer] {
        guard let shift = offer.shift else { return [] }
        let earliest = offer.earliestDeliveryAcceptance
        return shift.offersInOrder.filter { candidate in
            guard candidate.id != offer.id else { return false }
            guard let earliest else { return true }
            return candidate.couldHaveContained(earliest)
        }
    }

    // MARK: Writing

    /// Removes an offer that a correction left holding nothing.
    ///
    /// Guarded twice, because `Offer.deliveries` cascades and a wrong delete here
    /// would take a driver's recorded work with it. The authoritative reading is
    /// the deliveries' own ``Delivery/offer`` references; the relationship array
    /// must agree that it is empty before anything is deleted. An offer whose
    /// array still lists a delivery is left standing, which costs one row that
    /// the interface already knows how to render, and the disagreement is logged
    /// as the structural fault it is.
    private func removeIfEmptied(_ offer: Offer?) {
        guard let offer, offer.modelContext != nil, !offer.isDeleted else { return }
        guard offer.deliveries.allSatisfy({ $0.offer?.id != offer.id }) else { return }
        guard offer.deliveries.isEmpty else {
            AppLog.delivery.fault(
                "An emptied offer still lists deliveries; it was kept rather than deleted"
            )
            return
        }

        context.delete(offer)
        AppLog.delivery.info("An offer left holding no deliveries was removed")
    }

    /// Saves a correction, and rolls back if the store refuses.
    ///
    /// `operation` is a fixed word naming what was attempted, typed as a
    /// `StaticString` so nothing a driver recorded can become the value.
    private func save(describing operation: StaticString) throws {
        do {
            try commit(context)
        } catch {
            // The whole correction is discarded: the interface must not show a
            // grouping the store does not hold, and a half-applied merge must
            // never outlive the call that attempted it.
            context.rollback()
            AppLog.delivery.error("Failed to \(operation, privacy: .public): \(error)")
            throw OfferCorrectionError.storeUnavailable(underlying: error)
        }
    }

    /// Whether this row is still one the store holds.
    ///
    /// A view can hold an offer or a delivery across a sheet dismissal, another
    /// screen's deletion or its own correction, so an object arriving here is not
    /// proof of a row. Checked before anything is mutated, for the reason
    /// ``PickupPlaceService`` checks: a half-applied correction is worse than a
    /// refused one.
    private func requireRecorded(_ offer: Offer) throws {
        guard offer.modelContext != nil, !offer.isDeleted else {
            AppLog.delivery.notice("Refused a grouping correction: an offer is not in the store")
            throw OfferCorrectionError.offerNoLongerExists
        }
    }

    private func requireRecorded(_ delivery: Delivery) throws {
        guard delivery.modelContext != nil, !delivery.isDeleted else {
            AppLog.delivery.notice("Refused a grouping correction: a delivery is not in the store")
            throw OfferCorrectionError.deliveryNoLongerExists
        }
    }
}
