import Foundation

/// One recorded expense, reduced to the facts an aggregate needs.
///
/// A plain value rather than an ``Expense``, for the reason
/// ``PeriodShiftRecord`` is a plain value: every totalling rule, every coverage
/// rule and every calendar boundary can then be tested without a store, a
/// container or a rendered view.
nonisolated struct ExpenseRecord: Equatable, Sendable {
    /// What decides which period the expense belongs to, by exactly the rule
    /// ``ReportingPeriod/contains(_:)`` applies to a shift's start.
    let occurredAt: Date

    /// What the driver recorded it cost. Never negative — the model refuses one
    /// — and `$0.00` is a recorded amount like any other.
    let amount: Money

    let category: ExpenseCategory

    init(occurredAt: Date, amount: Money, category: ExpenseCategory) {
        self.occurredAt = occurredAt
        self.amount = amount
        self.category = category
    }
}

/// One category's share of a period's recorded expenses.
///
/// A subtotal and the number of records behind it, and nothing else. There is no
/// percentage, no rank and no comparison with another period: a category holding
/// three of a driver's five recorded costs says something about their
/// bookkeeping, not about where their money goes.
nonisolated struct ExpenseCategoryTotal: Equatable, Sendable, Identifiable {
    let category: ExpenseCategory

    /// The recorded amounts in this category, added up.
    let total: Money

    /// How many records that was.
    let recordCount: Int

    var id: String { category.rawValue }
}

/// What the expenses a driver recorded in a period add up to.
///
/// ## The one thing this type must never be read as
///
/// **A period's recorded expenses are not its costs.** DashPilot sees no
/// purchase: it holds the rows the driver typed and nothing else, so a total
/// here is a floor on what the period cost, in the same way recorded mileage is
/// a floor on the miles driven. A period with no expense recorded is not a
/// period that cost nothing, and every figure derived from these totals has to
/// carry that with it.
///
/// That is why there is **no coverage pair** here as there is on an earnings
/// subtotal. A ``MetricCoverage`` needs a denominator — the records that *could*
/// have contributed — and expenses have none: nothing in the app or on the
/// device knows how many costs a driver incurred and did not enter. Publishing
/// "3 of 3 expenses" would state completeness the app cannot observe. The record
/// count is reported as what it is, a count of what was entered, and the
/// interface says the rest in words.
nonisolated struct PeriodExpenseTotals: Equatable, Sendable {
    /// The amounts recorded in the period, added up, or `nil` when nothing was
    /// recorded in it.
    ///
    /// Absent rather than zero, for the reason a missing earnings amount is
    /// absent rather than zero: `$0.00` would be a claim that the period cost
    /// nothing, which is exactly the claim the app cannot make.
    let recordedTotal: Money?

    /// How many expense records the total came from.
    let recordCount: Int

    /// The same total split by what the driver said each amount was for, in
    /// ``ExpenseCategory/allCases`` order, holding only the categories that have
    /// a record in this period.
    ///
    /// A category with nothing recorded is left out rather than listed at
    /// `$0.00`: a driver who has never entered a maintenance cost has not
    /// recorded that maintenance was free.
    let categoryTotals: [ExpenseCategoryTotal]

    /// A period in which no expense was recorded.
    static let none = PeriodExpenseTotals(recordedTotal: nil, recordCount: 0, categoryTotals: [])

    /// Whether the driver recorded any expense at all in the period.
    var hasRecords: Bool { recordCount > 0 }
}

/// A period's recorded gross earnings, less its recorded expenses.
///
/// ## What it is called, and why it is never called profit
///
/// **Net after recorded expenses**, in full, everywhere it appears. It is the
/// difference between two subtotals of things the driver typed:
///
/// - gross earnings recorded on the period's completed shifts, over the shifts
///   that carry an amount, and
/// - the expenses recorded in the period, over the records that exist.
///
/// It is not profit, not take-home pay, not earnings after costs and not a
/// taxable figure. Calling it any of those would assert that every cost of doing
/// the work is represented, and DashPilot cannot know that: it observes no
/// purchase, models no vehicle wear, and has no idea what the driver paid for
/// and never entered. Both halves are floors, so the difference between them is
/// an **upper bound** on what the period actually netted, and the wording that
/// travels with it says so.
///
/// ## When there is no figure
///
/// The amount is absent unless **both** halves were actually recorded, and each
/// refusal is deliberate:
///
/// - With no recorded earnings there is nothing to net. A "net" of nothing minus
///   recorded costs is a negative number, and a negative number presented beside
///   a period's earnings reads as a loss the records do not establish.
/// - With no recorded expense the difference would equal the gross exactly, and
///   showing it as a *net* figure would assert that the period cost nothing —
///   the one statement this whole type exists to avoid making. A driver who
///   genuinely spent nothing can record `$0.00`, which is a recorded expense and
///   produces a net.
///
/// The counts travel with the figure for the reason every other aggregate's do:
/// a net over three of four shifts and the same net over all four are different
/// statements.
nonisolated struct PeriodNetAfterExpenses: Equatable, Sendable {
    /// Recorded gross earnings less recorded expenses, or `nil` when either half
    /// was not recorded. May be negative: a period whose recorded costs exceed
    /// its recorded earnings is a fact, not an error.
    let amount: Money?

    /// The shifts behind the earnings half, out of the completed shifts in the
    /// period.
    let earningsCoverage: MetricCoverage

    /// How many expense records were subtracted.
    let expenseRecordCount: Int

    var isAvailable: Bool { amount != nil }

    /// A net figure the period's records cannot support.
    static func unavailable(earningsCoverage: MetricCoverage, expenseRecordCount: Int) -> PeriodNetAfterExpenses {
        PeriodNetAfterExpenses(
            amount: nil,
            earningsCoverage: earningsCoverage,
            expenseRecordCount: expenseRecordCount
        )
    }

    static let none = PeriodNetAfterExpenses.unavailable(earningsCoverage: .none, expenseRecordCount: 0)
}
