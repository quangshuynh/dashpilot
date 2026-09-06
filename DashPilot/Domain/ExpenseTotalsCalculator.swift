import Foundation

/// Adds up the expenses a driver recorded in a period, and works out what the
/// period's recorded earnings come to after them.
///
/// ## Why it is separate from the period calculator
///
/// Expenses are not shift records. They select by their own timestamp, they have
/// no coverage denominator, and they answer a different question, so they get
/// their own pure type rather than another responsibility inside
/// ``PeriodMetricsCalculator`` — which calls it. There is one definition of a
/// recorded-expense total in the app, and this is it.
///
/// ## What it does not do
///
/// - **No allocation.** Nothing here divides an expense across the shifts,
///   deliveries, days or miles of the period it falls in. An expense sits in one
///   period, whole, exactly as a shift does.
/// - **No estimation.** No cost is inferred from mileage, from hours, from a
///   vehicle or from any other expense. If it was not typed it does not exist.
/// - **No rates.** There is no cost per hour, per mile or per delivery, and that
///   is a decision rather than an omission: the numerator would come from
///   records dated to a period and the denominator from work recorded on shifts,
///   which is precisely the numerator-from-one-population-denominator-from-
///   another figure this project refuses to publish. A tank of fuel bought on
///   Sunday and burned across the week has no honest denominator.
/// - **No tax anything.** No deduction, no depreciation, no mileage allowance
///   and no classification of a cost as claimable.
nonisolated struct ExpenseTotalsCalculator: Equatable, Sendable {
    init() {}

    /// The expenses of `period`, added up and split by category.
    ///
    /// - Parameters:
    ///   - records: candidate expenses, in any order. Records outside the period
    ///     are excluded here, by ``ReportingPeriod/contains(_:)`` — the same
    ///     half-open membership rule a shift is selected by, so an expense at
    ///     exactly midnight belongs to the day that is beginning and to that day
    ///     only.
    ///   - period: the span being summarised.
    func totals(of records: some Sequence<ExpenseRecord>, in period: ReportingPeriod) -> PeriodExpenseTotals {
        let expenses = records.filter { period.contains($0.occurredAt) }
        guard !expenses.isEmpty else { return .none }

        return PeriodExpenseTotals(
            recordedTotal: expenses.reduce(Money.zero) { $0 + $1.amount },
            recordCount: expenses.count,
            categoryTotals: categoryTotals(of: expenses)
        )
    }

    /// Recorded gross earnings less recorded expenses, when both were recorded.
    ///
    /// The subtraction is the whole of the arithmetic; the rules about when it
    /// may be performed at all, and about what the result may be called, are
    /// ``PeriodNetAfterExpenses``'.
    ///
    /// - Parameters:
    ///   - grossEarnings: the period's recorded shift earnings, or `nil` when no
    ///     shift in it recorded an amount.
    ///   - earningsCoverage: the shifts behind that subtotal, carried into the
    ///     result so the net cannot be read without them.
    ///   - totals: the period's recorded expenses.
    func net(
        of grossEarnings: Money?,
        coverage earningsCoverage: MetricCoverage,
        after totals: PeriodExpenseTotals
    ) -> PeriodNetAfterExpenses {
        guard let grossEarnings, let expenses = totals.recordedTotal else {
            return .unavailable(earningsCoverage: earningsCoverage, expenseRecordCount: totals.recordCount)
        }
        return PeriodNetAfterExpenses(
            amount: grossEarnings - expenses,
            earningsCoverage: earningsCoverage,
            expenseRecordCount: totals.recordCount
        )
    }

    /// The subtotals by category, in the enum's own order.
    ///
    /// Ordered by ``ExpenseCategory/allCases`` rather than by size: a list that
    /// reorders itself as amounts change is harder to read across two periods,
    /// and ranking categories by spend is a comparison this screen does not make.
    private func categoryTotals(of expenses: [ExpenseRecord]) -> [ExpenseCategoryTotal] {
        ExpenseCategory.allCases.compactMap { category in
            let matching = expenses.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }
            return ExpenseCategoryTotal(
                category: category,
                total: matching.reduce(Money.zero) { $0 + $1.amount },
                recordCount: matching.count
            )
        }
    }
}
