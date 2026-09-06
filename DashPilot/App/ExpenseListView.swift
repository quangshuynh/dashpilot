import SwiftData
import SwiftUI

/// Every operating cost the driver has recorded, newest first.
///
/// ## Why it is a list of its own
///
/// Because an expense is a record of its own. It is not part of a shift, so
/// there is no shift screen it could live inside, and putting it on one would
/// suggest an attachment the model deliberately does not have. What a period
/// cost, and what its earnings come to after those costs, is on the period
/// summary — which is where a figure can carry the counts behind it.
///
/// ## No totals here
///
/// A running total over every expense ever recorded would be a number with no
/// span attached, and the first thing anyone would do is compare it with a
/// week's earnings. Totals belong to a period; this screen is the record.
struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext

    /// Most recent first, matching the order history is read in.
    @Query(sort: \Expense.occurredAt, order: .reverse)
    private var expenses: [Expense]

    /// The expense being edited, or a marker for a new one.
    @State private var editing: EditorSubject?

    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Button {
                    editing = .new
                } label: {
                    Label("Add Expense", systemImage: "plus")
                }
                .accessibilityLabel("Add an expense")
                .accessibilityIdentifier("addExpenseButton")
            } footer: {
                Text(
                    """
                    Fuel, parking, tolls, maintenance and supplies you paid for, as you choose to \
                    record them. DashPilot records no purchase on its own and estimates none, so \
                    this is only what you enter.
                    """
                )
            }

            if expenses.isEmpty {
                Section {
                    Text("No expenses recorded yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("expensesEmptyState")
                }
            } else {
                Section {
                    ForEach(expenses) { expense in
                        Button {
                            editing = .existing(expense)
                        } label: {
                            ExpenseRow(expense: expense)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("expenseRow")
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { delete(expense) }
                                .accessibilityLabel("Delete this expense")
                        }
                    }
                } header: {
                    Text(recordCountStatement)
                } footer: {
                    Text(
                        """
                        What these come to over a day, week, month or range, and what your recorded \
                        earnings are after them, is on the period summary.
                        """
                    )
                }
            }
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { subject in
            ExpenseEditor(expense: subject.expense)
        }
        .alert(
            "Expense Not Changed",
            isPresented: isShowingFailure,
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) { failure = nil }
        } message: { message in
            Text(message)
        }
    }

    private var recordCountStatement: String {
        expenses.count == 1 ? "1 recorded expense" : "\(expenses.count) recorded expenses"
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { isShowing in if !isShowing { failure = nil } }
        )
    }

    private func delete(_ expense: Expense) {
        do {
            try ExpenseService(context: modelContext).delete(expense)
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? "That expense could not be deleted."
        }
    }

    /// What the sheet is editing. A separate value rather than an optional
    /// `Expense`, so "add" is a state the sheet can be in rather than the
    /// absence of one.
    private enum EditorSubject: Identifiable {
        case new
        case existing(Expense)

        var id: String {
            switch self {
            case .new: "new"
            case let .existing(expense): expense.id.uuidString
            }
        }

        var expense: Expense? {
            switch self {
            case .new: nil
            case let .existing(expense): expense
            }
        }
    }
}

/// One recorded expense in the list.
///
/// Read as one accessibility element, because the amount, the category and the
/// date are one record rather than three fragments — and because the date and
/// the note are what tell two amounts apart.
private struct ExpenseRow: View {
    let expense: Expense

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading
            Text(expense.occurredAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = expense.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The category and the amount share a line, until the text is large enough
    /// that one of them would be truncated. A shortened amount is worse than a
    /// second line.
    @ViewBuilder
    private var heading: some View {
        let category = Label(expense.category.title, systemImage: expense.category.systemImage)
            .font(.headline)
        let amount = Text(expense.amount.formatted(locale: locale))
            .font(.headline)
            .monospacedDigit()

        if dynamicTypeSize.isAccessibilitySize {
            category
            amount
        } else {
            HStack(alignment: .firstTextBaseline) {
                category
                Spacer(minLength: 8)
                amount
            }
        }
    }

    private var accessibilityLabel: String {
        var sentences = [
            "\(expense.category.title), \(expense.amount.formatted(locale: locale))",
            expense.occurredAt.formatted(date: .complete, time: .shortened)
        ]
        if let note = expense.note {
            sentences.append(note)
        }
        return sentences.joined(separator: ". ")
    }
}

#if DEBUG
#Preview("Recorded expenses") {
    NavigationStack {
        ExpenseListView()
    }
    .modelContainer(PreviewSupport.periodSummaryContainer())
}

#Preview("No expenses") {
    NavigationStack {
        ExpenseListView()
    }
    .modelContainer(PreviewSupport.emptyContainer())
}
#endif
