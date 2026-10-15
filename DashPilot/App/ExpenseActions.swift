import SwiftData
import SwiftUI

/// One presentation owner for a selected identity, outside recycled list rows.
@MainActor @Observable
final class ExpenseActions {
    enum Subject: Identifiable {
        case new
        case existing(Expense)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let expense): expense.id.uuidString
            }
        }
        var expense: Expense? {
            if case .existing(let expense) = self { return expense }
            return nil
        }
    }
    var editing: Subject?
    var pendingDelete: ExpensePresentation?
    var failure: String?

    func edit(_ row: ExpensePresentation, in context: ModelContext) {
        do { editing = .existing(try resolve(row.id, in: context)) }
        catch { failure = error.localizedDescription }
    }

    func confirmDelete(in context: ModelContext) {
        guard let row = pendingDelete else { return }
        pendingDelete = nil
        do { try ExpenseService(context: context).delete(resolve(row.id, in: context)) }
        catch { failure = error.localizedDescription }
    }

    private func resolve(_ id: UUID, in context: ModelContext) throws -> Expense {
        var query = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let expense = try context.fetch(query).first else {
            throw ExpenseRecordingError.expenseNoLongerExists
        }
        return expense
    }
}

struct ExpenseActionPresentation: ViewModifier {
    @Bindable var actions: ExpenseActions
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editing) { subject in ExpenseEditor(expense: subject.expense) }
            .confirmationDialog("Delete Expense?", isPresented: Binding(
                get: { actions.pendingDelete != nil },
                set: { if !$0 { actions.pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: actions.pendingDelete) { _ in
                Button("Delete Expense", role: .destructive) { actions.confirmDelete(in: context) }
                Button("Cancel", role: .cancel) { actions.pendingDelete = nil }
            } message: { row in
                Text("Delete \(row.category.title), \(row.amount.formatted(locale: locale)), \(row.occurredAt.formatted(date: .abbreviated, time: .shortened))? This cannot be undone.")
            }
            .alert("Expense Not Changed", isPresented: Binding(
                get: { actions.failure != nil }, set: { if !$0 { actions.failure = nil } }
            )) {
                Button("OK", role: .cancel) { actions.failure = nil }
            } message: { Text(actions.failure ?? "That expense could not be changed.") }
    }
}

struct ExpenseRecordButton: View {
    let row: ExpensePresentation
    let actions: ExpenseActions
    @Environment(\.modelContext) private var context

    var body: some View {
        Button { actions.edit(row, in: context) } label: {
            ExpenseRow(expense: row).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("expenseRow")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { actions.pendingDelete = row }
                .accessibilityLabel("Delete \(row.category.title) expense")
                .accessibilityIdentifier("deleteExpenseSwipeButton")
        }
    }
}
