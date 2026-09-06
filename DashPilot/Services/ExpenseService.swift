import Foundation
import OSLog
import SwiftData

/// Failures raised when a recorded expense cannot be written.
nonisolated enum ExpenseRecordingError: Error {
    /// The model refused the values: a negative amount, or a note that is too
    /// long.
    case invalidExpense(ExpenseError)
    /// The expense being edited or deleted is no longer a row the store holds.
    case expenseNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension ExpenseRecordingError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidExpense(lhsError), .invalidExpense(rhsError)): lhsError == rhsError
        case (.expenseNoLongerExists, .expenseNoLongerExists): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension ExpenseRecordingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidExpense(error):
            error.errorDescription
        case .expenseNoLongerExists:
            "That expense is no longer in DashPilot, so nothing was changed."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the expense was not changed."
        }
    }
}

/// Recording, correcting and removing the operating costs a driver enters.
///
/// ## What it owns
///
/// The writes, and nothing else. There is no cached list, no running total and
/// no aggregate held here: what a period cost is derived from these rows by
/// ``ExpenseTotalsCalculator`` every time it is asked for, exactly as mileage is
/// derived from route samples.
///
/// ## What it deliberately does not do
///
/// - **It never attaches an expense to a shift.** Not to the shift that is
///   running when the driver types, not to the nearest one by time, not to any
///   shift. An expense is dated; see ``Expense``.
/// - **It creates nothing on its own.** No recurring cost, no estimate, no
///   suggestion from mileage, and nothing written when a shift ends.
/// - **It refuses no expense for being unusual.** A large amount, a duplicate,
///   an amount on a day with no shift: all are things that happen, and the app
///   is not in a position to second-guess a driver's own record.
///
/// The type is `@MainActor` isolated like every other service: each operation
/// runs to completion without suspending, over the same context the views read.
@MainActor
struct ExpenseService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Records a new expense.
    ///
    /// - Throws: ``ExpenseRecordingError``.
    @discardableResult
    func record(
        amount: Money,
        category: ExpenseCategory,
        occurredAt: Date,
        noteText: String = ""
    ) throws -> Expense {
        let expense: Expense
        do {
            expense = try Expense(
                occurredAt: occurredAt,
                amount: amount,
                category: category,
                noteText: noteText
            )
        } catch let error as ExpenseError {
            AppLog.expenses.notice("Refused an expense: \(String(describing: error), privacy: .public)")
            throw ExpenseRecordingError.invalidExpense(error)
        }

        context.insert(expense)
        try save(afterFailing: "record an expense")

        // The category, and that a note exists at all. Never the amount, never
        // the date the money was spent, and never a word of the note itself.
        AppLog.expenses.info(
            """
            Expense recorded (category: \(category.rawValue, privacy: .public), \
            note: \(expense.note != nil, privacy: .public))
            """
        )
        return expense
    }

    /// Replaces every recorded fact about an existing expense.
    ///
    /// - Throws: ``ExpenseRecordingError``.
    func update(
        _ expense: Expense,
        amount: Money,
        category: ExpenseCategory,
        occurredAt: Date,
        noteText: String
    ) throws {
        try requireStored(expense)

        do {
            try expense.update(
                occurredAt: occurredAt,
                amount: amount,
                category: category,
                noteText: noteText
            )
        } catch let error as ExpenseError {
            AppLog.expenses.notice("Refused an expense edit: \(String(describing: error), privacy: .public)")
            throw ExpenseRecordingError.invalidExpense(error)
        }

        try save(afterFailing: "update an expense")
        AppLog.expenses.info("Expense updated (category: \(category.rawValue, privacy: .public))")
    }

    /// Removes an expense.
    ///
    /// Deletion is the only way an expense leaves the store. Nothing else in the
    /// app removes one — not ending a shift, not deleting a shift, not a
    /// migration — because an expense belongs to no shift and so has nothing to
    /// be cascaded from.
    ///
    /// - Throws: ``ExpenseRecordingError``.
    func delete(_ expense: Expense) throws {
        try requireStored(expense)

        context.delete(expense)
        try save(afterFailing: "delete an expense")
        AppLog.expenses.info("Expense deleted")
    }

    /// Every recorded expense, most recent first.
    ///
    /// - Throws: ``ExpenseRecordingError/storeUnavailable(underlying:)``.
    func allExpenses() throws -> [Expense] {
        do {
            return try context.fetch(
                FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
            )
        } catch {
            AppLog.expenses.error("Failed to read expenses: \(error)")
            throw ExpenseRecordingError.storeUnavailable(underlying: error)
        }
    }

    /// The expenses belonging to a reporting period, most recent first.
    ///
    /// Selected by the expense's **own** timestamp, with the same half-open
    /// `[start, end)` bounds a shift is selected by, so a cost recorded at
    /// exactly midnight falls in the day that is beginning and in that day only.
    ///
    /// - Throws: ``ExpenseRecordingError/storeUnavailable(underlying:)``.
    func expenses(in period: ReportingPeriod) throws -> [Expense] {
        let start = period.start
        let end = period.end
        do {
            return try context.fetch(
                FetchDescriptor<Expense>(
                    predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end },
                    sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
                )
            )
        } catch {
            AppLog.expenses.error("Failed to read expenses for a period: \(error)")
            throw ExpenseRecordingError.storeUnavailable(underlying: error)
        }
    }

    // MARK: Writing

    /// Refuses to operate on an object the store no longer holds.
    ///
    /// A screen can hold a row that was deleted underneath it, and SwiftData
    /// will happily let a caller mutate one. Writing through it would either
    /// resurrect a deleted record or throw somewhere far from the cause.
    private func requireStored(_ expense: Expense) throws {
        // The same rule ``PickupPlaceService`` applies: a deleted row keeps its
        // values but loses its context, and an object that was never inserted
        // never had one.
        guard expense.modelContext != nil, !expense.isDeleted else {
            AppLog.expenses.notice("Refused to change an expense the store no longer holds")
            throw ExpenseRecordingError.expenseNoLongerExists
        }
    }

    private func save(afterFailing operation: String) throws {
        do {
            try context.save()
        } catch {
            // Leave nothing in memory that the store does not hold: the list is
            // read straight from the context, so a kept-but-unsaved change would
            // show the driver a record that is not there.
            context.rollback()
            AppLog.expenses.error("Failed to \(operation, privacy: .public): \(error)")
            throw ExpenseRecordingError.storeUnavailable(underlying: error)
        }
    }
}
