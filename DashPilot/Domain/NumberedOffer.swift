import Foundation

/// One of a shift's offers together with the number the interface calls it and
/// the deliveries it contains.
///
/// ## The number is presentation, and it is local
///
/// Exactly what ``NumberedDelivery``'s number is, and for the same reason:
/// DashPilot collects no platform order number, no merchant and no customer, so
/// what is left to tell two accepted offers apart is a count taken from the
/// order they were accepted in. `Offer 2` is not an identifier anything outside
/// this app would recognise, and nothing is persisted.
///
/// ## The deliveries keep the numbers the shift gave them
///
/// The deliveries carried here are numbered **across the shift**, not restarted
/// within the offer. A driver carrying two offers of two would otherwise be
/// looking at two cards both called `Delivery 1`, which is the one thing the
/// numbering exists to prevent: every lifecycle control on screen names the
/// delivery it acts on, and that name has to be unique on the screen it appears
/// on. The grouping is said in its own words instead.
nonisolated struct NumberedOffer: Identifiable {
    let number: Int
    let offer: Offer

    /// Every delivery this offer contains, under its shift-wide number, in the
    /// order the shift numbers them.
    let deliveries: [NumberedDelivery]

    var id: UUID { offer.id }

    /// Numbers offers in the order they were accepted, attaching each one's
    /// deliveries from the shift's own numbering.
    ///
    /// - Parameters:
    ///   - offers: the shift's offers, already in accepted order.
    ///   - deliveries: the shift's deliveries under their shift-wide numbers.
    static func numbering(
        _ offers: [Offer],
        deliveries: [NumberedDelivery]
    ) -> [NumberedOffer] {
        offers.enumerated().map { position, offer in
            let members = Set(offer.deliveries.map(\.id))
            return NumberedOffer(
                number: position + 1,
                offer: offer,
                deliveries: deliveries.filter { members.contains($0.id) }
            )
        }
    }

    /// What this offer is called on screen.
    var title: String { "Offer \(number)" }

    /// Whether this offer contains more than one delivery, which is the only
    /// case where grouping is worth showing at all.
    var isGrouped: Bool { offer.isGrouped }

    /// How many deliveries this offer contains.
    var deliveryCount: Int { offer.deliveryCount }

    /// The printed caption for a group of deliveries accepted together.
    ///
    /// Says what the driver did, not what a platform sent: they accepted two
    /// deliveries in one go. The word "offer" is the neutral one for that, and
    /// nothing here names a platform, a program or a tier.
    var groupStatement: String {
        let noun = deliveryCount == 1 ? "delivery" : "deliveries"
        return "\(deliveryCount) \(noun) accepted together"
    }

    /// The same fact spoken, with the offer named first so a listener knows
    /// which group is being described before hearing its size.
    var spokenGroupStatement: String {
        "\(title). \(groupStatement)."
    }

    /// How many deliveries this offer holds, said for an offer of one and for an
    /// offer of none as well.
    ///
    /// ``groupStatement`` says *accepted together*, which is true of two or more
    /// and is nonsense about one: a single delivery arrived with nothing. The
    /// grouping correction screen names **every** offer a shift holds, including
    /// the ordinary offer of one and an anomalous offer holding none, so it needs
    /// a phrase that claims only what the offer actually is.
    var membershipStatement: String {
        switch deliveryCount {
        case 0: "No deliveries recorded"
        case 1: "1 delivery"
        default: groupStatement
        }
    }

    /// The same fact spoken, named first for the reason
    /// ``spokenGroupStatement`` is.
    var spokenMembershipStatement: String {
        "\(title). \(membershipStatement)."
    }

    /// How many of this offer's deliveries are still running, stated only where
    /// some have already finished.
    ///
    /// `nil` for an offer whose deliveries are all still in progress, where the
    /// count would repeat ``groupStatement``, and for one that is wholly
    /// finished, where there is no progress left to report.
    var remainingStatement: String? {
        let active = deliveries.filter(\.delivery.isActive).count
        guard active > 0, active < deliveryCount else { return nil }
        return "\(active) of \(deliveryCount) still in progress"
    }

    /// What VoiceOver hears about which deliveries one of these was accepted
    /// with, or `nil` when it was accepted on its own.
    ///
    /// The siblings are named rather than counted, because the names are what a
    /// listener can act on: every control on screen is labelled with a delivery
    /// number, so "accepted together with Delivery 3" tells them which other
    /// card belongs to this one. Their own number is left out of the list.
    func spokenGrouping(of numbered: NumberedDelivery) -> String? {
        guard isGrouped else { return nil }
        let siblings = deliveries
            .filter { $0.id != numbered.id }
            .map(\.title)
        guard !siblings.isEmpty else { return nil }
        return "Part of \(title), accepted together with \(Self.list(siblings))"
    }

    /// The printed caption on a delivery that arrived with others, or `nil` when
    /// it arrived alone.
    ///
    /// Short, because it sits on a card whose prominent thing must stay the
    /// lifecycle button.
    func groupingCaption(of numbered: NumberedDelivery) -> String? {
        guard isGrouped else { return nil }
        return "\(title) · \(groupStatement)"
    }

    /// "Delivery 2", "Delivery 2 and Delivery 3", "Delivery 2, Delivery 3 and
    /// Delivery 4". Spoken punctuation, since VoiceOver does not read a comma
    /// as a conjunction.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and \(last)"
    }
}
