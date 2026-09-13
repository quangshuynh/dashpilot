import Foundation

/// The deliveries on one screen, arranged by the offer they were accepted in.
///
/// ## Why the interface needs this and the store does not
///
/// The store already says which offer each delivery came in. What a screen
/// needs on top of that is an **order**: which cards sit together, in what
/// sequence, and which of them have a grouping worth stating at all. Working
/// that out in a view body would put the rule somewhere it cannot be tested and
/// would let two surfaces disagree about it, so it lives here.
///
/// ## What it preserves
///
/// - **The order deliveries already had.** Groups appear where their first
///   delivery appears, and within a group the deliveries keep the sequence they
///   were given. A shift of one-delivery offers therefore shows exactly the
///   list it showed before offers existed.
/// - **Each delivery's own identity.** A group is a heading and a sequence,
///   never a merged row. Every delivery carried here is the same
///   ``NumberedDelivery`` the rest of the app uses, with its own state and its
///   own next step, and nothing acts on a group as a unit.
/// - **A delivery that records no offer.** It becomes a group of its own with
///   no offer attached, shown exactly as an ungrouped delivery has always been
///   shown. Unreachable through the app, which records an offer with every
///   delivery, so this is about not misrepresenting a store rather than about
///   an ordinary case.
nonisolated struct DeliveryGroup: Identifiable {
    /// The offer these deliveries were accepted in, or `nil` for a delivery
    /// that records none.
    ///
    /// It carries **all** of the offer's deliveries, not only the ones in
    /// ``deliveries``, so a heading can say `1 of 2 still in progress` on a
    /// screen that is showing one of them.
    let offer: NumberedOffer?

    /// The deliveries this group shows, in the order they were given. Never
    /// empty.
    let deliveries: [NumberedDelivery]

    /// The offer's identity where there is one, and the single delivery's
    /// otherwise. Stable across a redraw either way, which is what a `ForEach`
    /// needs to keep a card's state attached to its own delivery.
    var id: UUID { offer?.id ?? deliveries[0].id }

    /// Whether this group is worth showing a heading for.
    ///
    /// Only an offer that contains more than one delivery is: a one-delivery
    /// offer is the ordinary case, and a heading over every single card would
    /// be the interface repeating itself in words most drivers never need.
    var isGrouped: Bool { offer?.isGrouped == true }

    /// Arranges `deliveries` into the groups their offers describe.
    ///
    /// - Parameters:
    ///   - deliveries: the deliveries to show, in the order they should appear.
    ///   - offers: the shift's numbered offers, which supply each group's
    ///     heading and its full membership.
    static func grouping(
        _ deliveries: [NumberedDelivery],
        within offers: [NumberedOffer]
    ) -> [DeliveryGroup] {
        let offersByID = Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) })

        var order: [UUID] = []
        var members: [UUID: [NumberedDelivery]] = [:]
        var offerForKey: [UUID: NumberedOffer] = [:]

        for numbered in deliveries {
            // The delivery's own identity is the key for one that records no
            // offer, which keeps it in a group of its own rather than pooling
            // every such row into one heap.
            let offer = numbered.delivery.offer.flatMap { offersByID[$0.id] }
            let key = offer?.id ?? numbered.id
            if members[key] == nil {
                order.append(key)
                offerForKey[key] = offer
            }
            members[key, default: []].append(numbered)
        }

        return order.map { key in
            DeliveryGroup(offer: offerForKey[key], deliveries: members[key] ?? [])
        }
    }
}
