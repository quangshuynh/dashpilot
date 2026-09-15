import Foundation
import SwiftData

/// Errors raised when recording or correcting an additional tip would violate
/// the model's invariants.
nonisolated enum DeliveryTipError: Error, Equatable {
    /// The amount was zero or negative.
    ///
    /// A tip is money that arrived. Zero is not a tip that paid nothing, it is
    /// the absence of one, and the way to record that a delivery received no
    /// additional tip is to record none. Negative is not a tip at all: money the
    /// work cost the driver is an expense, which lives in its own record with no
    /// relationship to a delivery.
    ///
    /// Deliberately stricter than ``DeliveryError/negativeEarnings``, which
    /// allows a recorded `$0.00` because "this delivery paid nothing" is a real
    /// thing to record about the delivery as a whole.
    case amountNotPositive
    /// A tip was recorded against a delivery that has not finished.
    ///
    /// The same rule ``Delivery/setGrossEarnings(_:)`` keeps, for the same
    /// reason: entering an amount is a review action performed after the
    /// driving, and a monetary field on a card the driver may be looking at from
    /// a moving car is the interaction this project designs away.
    ///
    /// It is a rule about **writing**, not about holding. A delivery reopened
    /// from a mistaken completion keeps every tip already recorded against it,
    /// exactly as it keeps its recorded gross.
    case deliveryNotFinished
    /// A tip was corrected or deleted while attached to no delivery.
    ///
    /// A store the app cannot produce: a tip is created against a delivery and
    /// cascades away with it. It reports a fault rather than an ordinary
    /// refusal.
    case tipNotOnADelivery
}

/// One tip a driver received for a delivery **outside** the amount the platform
/// recorded paying for it.
///
/// ## Why this is a row and not a column
///
/// A single mutable `additionalTipAmount` on ``Delivery`` would have been
/// cheaper and is the thing this version must not do. Tips arrive as separate
/// events: cash at the door, and then a platform tip added that evening. Each is
/// its own fact with its own method and its own moment, and folding them into
/// one number means a driver correcting the cash figure has to remember what the
/// platform one was and do the arithmetic themselves. It would also throw away
/// the method, which is the part a driver actually acts on: cash is already in
/// their pocket, and a platform tip is still coming.
///
/// Rows also keep the distinction the whole app is built on: several recorded
/// facts, never one derived summary. ``EffectiveDeliveryEarnings`` adds them up
/// on demand and nothing stores the total.
///
/// ## What it is not
///
/// **Not a correction to what the platform paid.** ``Delivery/grossEarnings``
/// stays exactly what the driver recorded, including any tip the platform
/// already folded into it, and recording a tip here never touches it. The two
/// are separate facts for the reason expected pay and recorded gross are, and
/// the screens say so in as many words: a tip already inside the platform amount
/// must not be recorded again here.
///
/// **Not cash-on-delivery accounting.** There is no order total, no cash
/// collected, no platform deduction, no reimbursement and no customer balance
/// anywhere in DashPilot. This row holds money that reached the driver, and
/// nothing about money that passed through them.
///
/// **Not read from anywhere.** DashPilot sees no delivery platform and no
/// payout. Every value here is one the driver typed.
@Model
nonisolated final class DeliveryTip {
    /// Stable identifier, used for cross-store references and export, for the
    /// reason ``Delivery`` has one.
    @Attribute(.unique) private(set) var id: UUID

    /// The amount, stored as a `Decimal` for the reason
    /// ``Shift/grossEarningsAmount`` is: SwiftData persists a `Decimal` as a
    /// decimal attribute, so the exact amount survives a round trip with no
    /// binary floating point anywhere in the store. The conversion is
    /// centralised in ``amount``; nothing else reads this property.
    ///
    /// Always positive: ``DeliveryTipError/amountNotPositive`` is refused on the
    /// way in, so there is no "missing versus zero" question to ask about it.
    private var amountValue: Decimal

    /// ``DeliveryTipMethod``'s raw value.
    ///
    /// A string rather than the enum itself, for the reason ``Expense`` stores
    /// one: the store describes storage, and a stored value an older build
    /// cannot name must read as something rather than fail a fetch. Unlike an
    /// expense category there is no neutral case to fall back on, so it reads as
    /// **no method**. See ``method``.
    private var methodRawValue: String

    /// When the driver recorded this tip.
    ///
    /// The moment the row was created, and it never moves. It is deliberately
    /// **not** an editable "when the tip arrived": correcting a historical
    /// timestamp is its own decision with its own rules, and a field that looked
    /// like the time the money changed hands while actually holding the time it
    /// was typed would be the worst of both. Nothing in the app derives a
    /// duration, a rate or a period from it; a tip belongs to the period its
    /// **delivery's shift** does, through the shift, exactly as every other
    /// delivery fact does.
    private(set) var recordedAt: Date

    /// The delivery this tip was received for.
    ///
    /// Optional because SwiftData models the inverse of a to-many relationship
    /// that way, not because a tip without a delivery is meaningful: the
    /// initializer requires one, ``DeliveryService`` records one only against a
    /// finished delivery, and `Delivery.additionalTips` cascades on delete so a
    /// tip cannot outlive the delivery it describes, or the shift that
    /// delivery belongs to, which cascades to the delivery first.
    private(set) var delivery: Delivery?

    /// - Throws: ``DeliveryTipError/amountNotPositive`` for an amount that is
    ///   not more than zero. The refusal lives on the model rather than in a
    ///   view so that no screen, test or later caller can create a row the app
    ///   would refuse to display.
    init(
        id: UUID = UUID(),
        delivery: Delivery,
        amount: Money,
        method: DeliveryTipMethod,
        recordedAt: Date
    ) throws {
        guard amount > .zero else { throw DeliveryTipError.amountNotPositive }

        self.id = id
        amountValue = amount.amount
        methodRawValue = method.rawValue
        self.recordedAt = recordedAt
        self.delivery = delivery
    }

    /// What the tip was, exactly as entered.
    var amount: Money { Money(amount: amountValue) }

    /// How it reached the driver, or `nil` for a stored word this build cannot
    /// name.
    ///
    /// The absence is presented rather than guessed at. Both methods say
    /// something definite about where the money came from, so choosing one for
    /// an unrecognised value would invent that; the amount is still a recorded
    /// fact and still counts toward the delivery's effective earnings, because
    /// what the money was is a separate question from how much of it there was.
    var method: DeliveryTipMethod? { DeliveryTipMethod.stored(methodRawValue) }

    /// Replaces the amount and the method with the ones given.
    ///
    /// One method rather than two setters, for the reason ``Expense/update`` is
    /// one: the editor is a draft the driver saves once, and a row half-updated
    /// by a failure part-way through would be a record they never typed. The
    /// amount is validated before either value is written.
    ///
    /// ``recordedAt`` is **not** a parameter and does not move. Correcting what
    /// a tip was is not a claim about when it was recorded, and rewriting a
    /// historical timestamp is a decision this version deliberately does not
    /// make.
    ///
    /// - Throws: ``DeliveryTipError/amountNotPositive``.
    func update(amount: Money, method: DeliveryTipMethod) throws {
        guard amount > .zero else { throw DeliveryTipError.amountNotPositive }
        amountValue = amount.amount
        methodRawValue = method.rawValue
    }
}

extension DeliveryTip {
    /// Deterministic order for a delivery's tips: earliest recorded first, with
    /// identity breaking a tie.
    ///
    /// The same rule, for the same reason, as ``Delivery/acceptedBefore(_:_:)``:
    /// the order decides which tip is called `Tip 1` on screen, so it has to be
    /// total and repeatable rather than whatever a relationship happened to
    /// return.
    static func recordedBefore(_ lhs: DeliveryTip, _ rhs: DeliveryTip) -> Bool {
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
