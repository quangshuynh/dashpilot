import Foundation

/// One of a shift's deliveries together with the number the interface calls it.
///
/// ## The number is presentation, and it is local
///
/// A driver working two orders at once has to be able to tell two controls on
/// screen apart. Every obvious way to label them — the restaurant, the address,
/// the platform's order number — is data DashPilot deliberately does not
/// collect, so what is left is a count: `Delivery 1`, `Delivery 2`, taken from
/// the order the shift accepted them in.
///
/// It is **not** an order identifier. It is not a platform's number, it does
/// not describe a stack, and nobody outside this app would recognise it.
///
/// ## Nothing about it is persisted
///
/// Storing a display number would create a second answer to a question the
/// acceptance timestamps already answer, and one free to drift away from them.
/// A delivery nevertheless keeps its number for the whole shift, because
/// deliveries are never deleted individually and an acceptance time never
/// changes.
///
/// ## Nothing mutates through it
///
/// Every control the interface builds from a numbered delivery acts on
/// ``delivery`` — the persisted model — so even a renumbering could not send a
/// lifecycle event to the wrong record.
nonisolated struct NumberedDelivery: Identifiable {
    let number: Int
    let delivery: Delivery

    var id: UUID { delivery.id }

    /// Numbers deliveries in the order they were accepted.
    ///
    /// The order comes from ``Delivery/acceptedBefore(_:_:)`` rather than from
    /// however a fetch or a relationship happened to return them, so the same
    /// deliveries always get the same numbers.
    static func numbering(_ deliveries: some Sequence<Delivery>) -> [NumberedDelivery] {
        deliveries
            .sorted(by: Delivery.acceptedBefore)
            .enumerated()
            .map { NumberedDelivery(number: $0.offset + 1, delivery: $0.element) }
    }

    /// What this delivery is called on screen.
    var title: String { "Delivery \(number)" }

    /// The card's heading: which delivery, and what it is doing.
    var statusTitle: String { "\(title) · \(delivery.state.statusDescription)" }

    /// The same two facts as a phrase, for VoiceOver, where a middle dot is not
    /// spoken.
    var spokenStatus: String { "\(title), \(delivery.state.statusDescription.lowercased())" }

    /// What VoiceOver hears for one of this delivery's controls.
    ///
    /// The delivery is named first. With several cards on screen, a button that
    /// says only "Mark order picked up" identifies its target by nothing but
    /// where it happens to sit, which is unusable without sight.
    func spokenLabel(for action: DeliveryAction) -> String {
        "\(title). \(action.spokenLabel)"
    }

    /// The spoken label for this delivery's cancel control, named for the same
    /// reason: cancelling the wrong delivery is not an error the driver can undo.
    var spokenCancelLabel: String { "\(title). Cancel this delivery" }
}
