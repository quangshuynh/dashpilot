import Foundation

/// Immutable rows cross the period loader's isolation boundary. Identity is kept
/// only to resolve an explicit edit in the UI's own model context.
nonisolated struct ExpensePresentation: Equatable, Sendable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let amount: Money
    let category: ExpenseCategory
    let note: String?

    var record: ExpenseRecord {
        ExpenseRecord(occurredAt: occurredAt, amount: amount, category: category)
    }
}

nonisolated struct MoneyPeriodSummary: Equatable, Sendable {
    let metrics: PeriodMetrics
    let rows: [ExpensePresentation]
    let hasAnyExpense: Bool
    let includesFuelEstimates: Bool

    func rows(in category: ExpenseCategory?) -> [ExpensePresentation] {
        guard let category else { return rows }
        return rows.filter { $0.category == category }
    }

    /// Uses the authoritative calculator's already-derived category subtotal.
    /// Filtering never changes the overall expense total or net.
    func subtotal(in category: ExpenseCategory?) -> Money? {
        guard let category else { return metrics.expenses.recordedTotal }
        return metrics.expenses.categoryTotals.first { $0.category == category }?.total
    }
}

extension Expense {
    var presentation: ExpensePresentation {
        ExpensePresentation(id: id, occurredAt: occurredAt, amount: amount, category: category, note: note)
    }
}
