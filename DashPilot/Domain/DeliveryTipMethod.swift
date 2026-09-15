import Foundation

/// How an additional tip reached the driver.
///
/// ## Two, and deliberately no more
///
/// The distinction a driver actually needs is whether the money is already in
/// their pocket or is still coming to them in a payout. Cash was handed over at
/// the door; a platform tip was added to the order afterwards and arrives with
/// everything else the platform pays. Nothing else about a tip is recorded: no
/// payer, no order reference, no payout batch, and no claim that DashPilot saw
/// any of it. A tip is here because the driver typed it.
///
/// The set is closed for the reason ``ExpenseCategory``'s is, and with one
/// difference worth stating: there is no neutral third case. ``ExpenseCategory``
/// has ``ExpenseCategory/other``, which claims nothing and is therefore a safe
/// home for a stored word this build cannot name. A tip method has no such
/// case — `cash` and `platform` are both substantive claims — so a stored word
/// this build cannot name reads as **no method**, which is what ``stored(_:)``
/// returns. See ``DeliveryTip/method``.
nonisolated enum DeliveryTipMethod: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
    /// Handed over in cash, so the driver already has it.
    case cash
    /// Added through the delivery platform, so it arrives with the platform's
    /// own payment rather than separately.
    case platform

    var id: String { rawValue }

    /// The label a control shows.
    var title: String {
        switch self {
        case .cash: "Cash"
        case .platform: "Platform"
        }
    }

    /// The same word inside a spoken sentence, where a leading capital reads as
    /// the start of a new phrase.
    var spokenTitle: String {
        switch self {
        case .cash: "cash"
        case .platform: "platform"
        }
    }

    /// One sentence saying what choosing this method asserts, shown under the
    /// control that chooses it.
    ///
    /// The platform sentence is the one that matters, and it is the whole of
    /// this feature's guard against double counting: a tip the platform already
    /// included in what it paid for the delivery is **part of that amount** and
    /// must not be recorded again here.
    var explanation: String {
        switch self {
        case .cash:
            "Handed to you in cash, so it is not part of what the platform recorded paying for this delivery."
        case .platform:
            """
            Added through the platform after it recorded what this delivery paid. Only record it here \
            if it is not already inside that amount.
            """
        }
    }

    /// The icon beside the label. Decoration only: every surface states the
    /// method in words as well, because an icon is not a label to VoiceOver.
    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .platform: "iphone"
        }
    }

    /// Reads a method back out of the store.
    ///
    /// `nil` for a word this build cannot name, which is the honest answer
    /// rather than a guess: both cases say something definite about where the
    /// money came from, and picking either one for an unrecognised value would
    /// invent that. The amount is still a recorded fact and still counts, so a
    /// tip whose method cannot be named is presented as a tip with no method
    /// rather than dropped. See ``DeliveryTip/method``.
    static func stored(_ rawValue: String) -> DeliveryTipMethod? {
        DeliveryTipMethod(rawValue: rawValue)
    }
}
