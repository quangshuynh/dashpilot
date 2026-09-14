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
    var title: String { Self.title(number: number) }

    /// The same name built from a number alone, for a caller that has the
    /// number but not the record — a spoken confirmation, for instance. One
    /// definition, so the voice surface and the screen cannot drift into
    /// calling the same delivery two things.
    static func title(number: Int) -> String { "Delivery \(number)" }

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

    /// What the pickup-place control prints, which depends only on whether one
    /// is already recorded.
    ///
    /// Short, because it sits under a delivery that has already named itself and
    /// beside a lifecycle button that must stay the prominent thing on the card.
    func pickupPlaceActionTitle(hasPlace: Bool) -> String {
        hasPlace ? "Change Pickup Place" : "Add Pickup Place"
    }

    /// What VoiceOver hears for that control.
    ///
    /// The delivery is named, exactly as it is for every other control on a card
    /// — with three cards on screen, "Add pickup place" alone identifies its
    /// target by nothing but where it happens to sit.
    func spokenPickupPlaceLabel(hasPlace: Bool) -> String {
        hasPlace ? "Change pickup place for \(title)" : "Add pickup place for \(title)"
    }

    /// What the control that takes back an accidental `Delivered` prints.
    ///
    /// Named after what it does to **this delivery**, and deliberately not
    /// `Edit`: nothing here edits a timestamp, and a control that says so would
    /// promise a lifecycle editor the app does not have. It says `Reopen`
    /// because that is what happens to the delivery, and it names which one for
    /// the reason every other control on a list of deliveries does.
    var reopenActionTitle: String { "Reopen \(title)" }

    /// What VoiceOver hears for that control.
    ///
    /// It says the consequence rather than the action alone. A listener choosing
    /// between rows has to know that this puts the delivery back among the ones
    /// they are still working, and which state it goes back to, before they
    /// press anything.
    func spokenReopenLabel(restoredTo state: DeliveryState) -> String {
        "Reopen \(title). It becomes active again, \(state.statusDescription.lowercased())."
    }

    /// What the short-lived undo offered right after the tap says on screen.
    ///
    /// Two words and a name, because it appears while the driver may be putting
    /// the phone down.
    var deliveredStatement: String { "\(title) marked delivered" }

    /// What VoiceOver hears for that undo.
    ///
    /// The delivery is named and the consequence is stated, exactly as it is on
    /// the deliberate control above: a listener who hears only "Undo" has been
    /// told neither which delivery it belongs to nor what pressing it does.
    func spokenUndoDeliveredLabel(restoredTo state: DeliveryState) -> String {
        "Undo marking \(title) delivered. It becomes active again, \(state.statusDescription.lowercased())."
    }

    /// What the earnings control prints, which depends only on whether an amount
    /// is already recorded.
    func earningsActionTitle(hasEarnings: Bool) -> String {
        hasEarnings ? "Edit Earnings" : "Add Earnings"
    }

    /// What VoiceOver hears for that control, named for its delivery like every
    /// other one.
    ///
    /// A log of finished deliveries puts several of these on one screen, and
    /// "Add Earnings" alone would identify its target by nothing but where it
    /// happens to sit — which is exactly the mistake that puts an amount against
    /// the wrong order.
    func spokenEarningsLabel(hasEarnings: Bool) -> String {
        hasEarnings ? "Edit gross earnings for \(title)" : "Add gross earnings for \(title)"
    }

    /// What VoiceOver hears for the control that deletes the amount. `from`
    /// rather than `for`, because it takes something away.
    var spokenRemoveEarningsLabel: String { "Remove gross earnings from \(title)" }

    /// What the expected-pay control prints, which depends only on whether an
    /// expectation is already recorded.
    ///
    /// **"Expected pay", never "earnings".** The word the app uses for a
    /// recorded amount is reserved for recorded amounts, on every surface, so
    /// that two controls one tap apart on the same card cannot be read as two
    /// ways of doing the same thing.
    func expectedEarningsActionTitle(hasExpected: Bool) -> String {
        hasExpected ? "Change Expected Pay" : "Add Expected Pay"
    }

    /// What VoiceOver hears for that control, named for its delivery like every
    /// other one, because a driver carrying three orders hears three of these.
    func spokenExpectedEarningsLabel(hasExpected: Bool) -> String {
        hasExpected ? "Change expected pay for \(title)" : "Add expected pay for \(title)"
    }

    /// What VoiceOver hears for the control that deletes the expectation.
    var spokenRemoveExpectedEarningsLabel: String { "Remove expected pay from \(title)" }

    /// An expected amount spoken with the delivery it belongs to **and with
    /// what it is not**.
    ///
    /// The trailing sentence is the whole point. A figure read out as "Delivery
    /// 2, $8.50" is indistinguishable by ear from the recorded amount spoken by
    /// ``spokenEarnings(_:)``, and a listener has no column headings to fall
    /// back on. Saying that nothing is recorded yet is what keeps the two facts
    /// apart for someone who cannot see them side by side.
    func spokenExpectedEarnings(_ formattedAmount: String) -> String {
        "Expected pay for \(title), \(formattedAmount). No gross earnings recorded yet."
    }

    /// The same figure spoken for a delivery that **does** have a recorded
    /// amount beside it, where the absence sentence would be untrue.
    func spokenExpectedEarningsBesideRecorded(_ formattedAmount: String) -> String {
        "Expected pay for \(title), \(formattedAmount). This is what was expected, not what was recorded."
    }

    /// A recorded amount spoken with the delivery it belongs to.
    ///
    /// A bare `$14.75` in a list of deliveries says which figure but not whose,
    /// and the whole risk this project designs against is a monetary figure read
    /// against the wrong record.
    func spokenEarnings(_ formattedAmount: String) -> String {
        "Gross earnings for \(title), \(formattedAmount)"
    }

    /// The delivery's own hourly figure, spoken with the delivery it belongs to
    /// and with the denominator named in full.
    ///
    /// "Per hour" alone would be heard as a wage. The phrase says *recorded
    /// delivery hour* everywhere, printed and spoken, because the denominator is
    /// one delivery's own elapsed lifecycle and nothing else.
    func spokenDeliveryHourRate(_ formattedAmount: String) -> String {
        "\(formattedAmount) gross earnings per recorded delivery hour, for \(title)"
    }
}
