import Foundation

/// What one proposed grouping correction will do, in the words a driver is asked
/// to confirm.
///
/// ## Why the sentences live here
///
/// A confirmation that says "Merge?" is a confirmation of nothing. Every
/// correction moves named deliveries between named offers, sometimes removes an
/// offer, and must say so before it is applied, because none of it is undoable
/// and all of it is about work the driver actually did. Building those sentences
/// in a view body would put the one thing the driver reads somewhere it cannot
/// be tested, and would let two screens describe the same operation differently.
///
/// ## What every one of them says
///
/// The **subject by name** (`Delivery 2`, `Offer 1`), the **direction**, what
/// happens to an offer left holding nothing, and the fact the whole feature
/// rests on: nothing else about the deliveries changes. Local display names
/// only. No identifier, no timestamp and no amount appears in any of it.
nonisolated struct OfferCorrectionPlan: Equatable {
    /// The question, naming both ends of the correction.
    let title: String

    /// What will happen, in the order it happens.
    let detail: String

    /// The confirming button, which repeats the correction rather than saying
    /// "OK": with two offers on screen, a button labelled only `Move` is asking
    /// the driver to remember which row they tapped.
    let confirmTitle: String

    /// The one thing every correction promises, said the same way each time.
    ///
    /// Deliberately concrete rather than "nothing else changes": the facts a
    /// driver worries about losing are the times they recorded, the place they
    /// named and the money they entered, so those are the ones named.
    static let unchangedStatement =
        "Recorded times, pickup places and amounts do not change."

    /// Moving one delivery into an offer the shift already holds.
    static func move(
        _ delivery: NumberedDelivery,
        from source: NumberedOffer?,
        to destination: NumberedOffer
    ) -> Self {
        Self(
            title: "Move \(delivery.title) to \(destination.title)?",
            detail: [
                "\(delivery.title) moves \(leaving(source))to \(destination.title).",
                emptiedStatement(source),
                unchangedStatement
            ]
            .compactMap { $0 }
            .joined(separator: " "),
            confirmTitle: "Move to \(destination.title)"
        )
    }

    /// Taking one delivery out of the offer it shares and recording it on its
    /// own.
    ///
    /// The acceptance the new offer takes is stated, because it is the one value
    /// the driver did not choose. It is said as *the time already recorded for
    /// that delivery* rather than as a timestamp: the point is that nothing was
    /// invented, not what the clock read.
    static func split(_ delivery: NumberedDelivery, from source: NumberedOffer?) -> Self {
        Self(
            title: "Put \(delivery.title) in a new offer?",
            detail: [
                """
                \(delivery.title) moves \(leaving(source))into a new offer of its own, accepted at \
                the time already recorded for it.
                """,
                unchangedStatement
            ]
            .joined(separator: " "),
            confirmTitle: "Put \(delivery.title) in a New Offer"
        )
    }

    /// Moving every delivery of one offer into another, and removing the offer
    /// left behind.
    ///
    /// The deliveries are **named**, not counted, so the driver can check the
    /// direction against the cards they are looking at.
    static func merge(_ source: NumberedOffer, into destination: NumberedOffer) -> Self {
        let moving = source.deliveries.map(\.title)
        return Self(
            title: "Combine \(source.title) into \(destination.title)?",
            detail: [
                movedStatement(moving, destination: destination),
                "\(source.title) is then removed.",
                unchangedStatement
            ]
            .joined(separator: " "),
            confirmTitle: "Combine into \(destination.title)"
        )
    }

    /// Breaking a grouped offer back into one offer per delivery.
    static func separate(_ offer: NumberedOffer) -> Self {
        let separated = offer.deliveries.dropFirst().map(\.title)
        let kept = offer.deliveries.first?.title
        return Self(
            title: "Separate \(offer.title)?",
            detail: [
                "\(list(separated)) \(Self.separatedVerb(count: separated.count)).",
                kept.map { "\($0) stays in \(offer.title)." },
                unchangedStatement
            ]
            .compactMap { $0 }
            .joined(separator: " "),
            confirmTitle: "Separate \(offer.title)"
        )
    }

    /// An offer of two separates one delivery, which does not "each move".
    private static func separatedVerb(count: Int) -> String {
        count == 1 ? "moves into a new offer of its own" : "each move into a new offer of their own"
    }

    /// "out of Offer 1 " where there is an offer to leave, and nothing at all
    /// where the delivery records none.
    private static func leaving(_ source: NumberedOffer?) -> String {
        source.map { "out of \($0.title) " } ?? ""
    }

    /// Said only where this correction empties the source, because that is the
    /// one part of a correction that removes a row.
    private static func emptiedStatement(_ source: NumberedOffer?) -> String? {
        guard let source, source.deliveryCount == 1 else { return nil }
        return "\(source.title) is left with no deliveries and is removed."
    }

    private static func movedStatement(_ moving: [String], destination: NumberedOffer) -> String {
        guard !moving.isEmpty else { return "Nothing moves: \(destination.title) is unchanged." }
        let verb = moving.count == 1 ? "moves" : "move"
        return "\(list(moving)) \(verb) to \(destination.title)."
    }

    /// "Delivery 2", "Delivery 2 and Delivery 3", "Delivery 2, Delivery 3 and
    /// Delivery 4", for the reason ``NumberedOffer`` spells its own list out:
    /// VoiceOver does not read a comma as a conjunction.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and \(last)"
    }
}
