import Foundation
import SwiftData

/// Errors raised when an expense would violate the model's invariants.
nonisolated enum ExpenseError: Error, Equatable {
    /// A negative amount. An expense is what the work cost; money coming back
    /// is not an expense, and DashPilot records no refunds or reimbursements.
    case negativeAmount
    /// The note broke ``ExpenseNote``'s length rule.
    case invalidNote(ExpenseNoteError)
}

nonisolated extension ExpenseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .negativeAmount:
            "An expense cannot be a negative amount. Enter what it cost, for example 42.10."
        case let .invalidNote(error):
            error.errorDescription
        }
    }
}

/// One operating cost the driver recorded.
///
/// ## Every one of these was typed
///
/// DashPilot observes no purchase. It reads no card, no bank, no receipt, no
/// email and no delivery platform, and it estimates nothing: there is no fuel
/// consumption model, no per-mile vehicle cost and no depreciation anywhere in
/// the app. An expense exists because the driver entered an amount, a date, a
/// category and — if they wanted one — a short note. Nothing else is inferred
/// from it.
///
/// ## It belongs to a date, not to a shift
///
/// There is **no relationship to ``Shift`` and none to ``Delivery``**, and that
/// is the substantive decision in this model rather than an omission.
///
/// A tank of fuel is burned across several shifts and several days. A set of
/// tyres is spread over thousands of miles and hundreds of deliveries. A parking
/// charge might belong to one delivery, but the driver did not say which and the
/// app cannot know. Attaching a cost to whichever shift happened to be running
/// when it was typed would record an attribution the driver never made, and no
/// later screen, figure or export could tell it apart from one they did — the
/// same failure the app refuses when it declines to divide a shift's earnings
/// among its deliveries.
///
/// So an expense carries the moment it happened, and a period contains it if
/// that moment falls inside the period, by exactly the rule that puts a shift in
/// a period. The consequence is deliberate and is stated wherever a figure
/// depends on it: DashPilot reports costs *per period*, never *per shift*, never
/// *per delivery*, and never *per mile*.
///
/// ## The amount is required; the coverage is not a claim
///
/// Unlike gross earnings, an amount is not optional here: an expense record with
/// no amount is not a record of anything. A recorded `$0.00` is still allowed and
/// still means what it says — the driver recorded that this cost nothing.
///
/// What stays absent is everything they did **not** record. A period holding no
/// expense is not a period that cost nothing, and no total derived from these
/// rows may be presented as though it were complete. See
/// ``PeriodExpenseTotals``.
@Model
nonisolated final class Expense {
    /// Stable identifier, used for cross-store references and export.
    @Attribute(.unique) private(set) var id: UUID

    /// When the cost was incurred, as the driver recorded it.
    ///
    /// Not when the row was created: a driver typing Sunday's fuel on Monday
    /// says when it happened, and a period summary that used the typing time
    /// would put the cost in the wrong week. This is the timestamp period
    /// membership is decided by.
    private(set) var occurredAt: Date

    /// The amount, stored as a `Decimal` for the reason
    /// ``Shift/grossEarningsAmount`` is: SwiftData persists a `Decimal` as a
    /// decimal attribute, so the exact amount survives a round trip with no
    /// binary floating point anywhere in the store. The conversion is
    /// centralised in ``amount``; nothing else reads this property.
    private var amountValue: Decimal

    /// ``ExpenseCategory``'s raw value.
    ///
    /// A string rather than the enum itself, for the reason ``PickupPlace``
    /// stores plain strings: the store describes storage, and a stored value an
    /// older build cannot name must read as a category rather than fail a fetch.
    /// See ``ExpenseCategory/stored(_:)``.
    private var categoryRawValue: String

    /// The driver's own short reminder, or `nil` when they wrote none.
    ///
    /// Free text they typed, treated as sensitive: never logged, and out of the
    /// app only through an export they started. See ``ExpenseNote``.
    private(set) var note: String?

    /// - Throws: ``ExpenseError`` if the amount is negative or the note is too
    ///   long. The refusals live on the model rather than in a view, so no
    ///   screen, test or later caller can create a row the app would refuse to
    ///   display.
    init(
        id: UUID = UUID(),
        occurredAt: Date,
        amount: Money,
        category: ExpenseCategory,
        noteText: String = ""
    ) throws {
        guard !amount.isNegative else { throw ExpenseError.negativeAmount }
        let note: String?
        do {
            note = try ExpenseNote.note(from: noteText)
        } catch let error as ExpenseNoteError {
            throw ExpenseError.invalidNote(error)
        }

        self.id = id
        self.occurredAt = occurredAt
        amountValue = amount.amount
        categoryRawValue = category.rawValue
        self.note = note
    }

    /// What this expense cost, exactly as entered.
    var amount: Money { Money(amount: amountValue) }

    /// What the driver said it was for.
    var category: ExpenseCategory { ExpenseCategory.stored(categoryRawValue) }

    /// Replaces every recorded fact about this expense with the ones given.
    ///
    /// One method rather than four setters: the editor is a draft that the
    /// driver saves once, and a row half-updated by a failure part-way through
    /// would be a record they never typed. Every value is validated before any
    /// of them is written.
    ///
    /// - Throws: ``ExpenseError``.
    func update(
        occurredAt: Date,
        amount: Money,
        category: ExpenseCategory,
        noteText: String
    ) throws {
        guard !amount.isNegative else { throw ExpenseError.negativeAmount }
        let note: String?
        do {
            note = try ExpenseNote.note(from: noteText)
        } catch let error as ExpenseNoteError {
            throw ExpenseError.invalidNote(error)
        }

        self.occurredAt = occurredAt
        amountValue = amount.amount
        categoryRawValue = category.rawValue
        self.note = note
    }
}

extension Expense {
    /// This expense, reduced to the facts an aggregate needs.
    ///
    /// The adapter between the model and ``ExpenseTotalsCalculator``, holding no
    /// rule of its own — the same shape ``Shift/periodRecord(for:)`` takes, and
    /// for the same reason: the arithmetic is then testable without a store.
    ///
    /// The note is deliberately absent from the value. Nothing aggregated is
    /// derived from it, and a total has no business carrying a driver's free
    /// text around.
    var expenseRecord: ExpenseRecord {
        ExpenseRecord(occurredAt: occurredAt, amount: amount, category: category)
    }

    /// Deterministic order for a list a driver reads: most recent first, with
    /// identity breaking a tie.
    ///
    /// Total and repeatable for the reason ``PickupPlace/namedBefore(_:_:)`` is:
    /// two rows recorded for the same instant must not be free to swap places
    /// between two reads.
    static func recordedBefore(_ lhs: Expense, _ rhs: Expense) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
