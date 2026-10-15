import SwiftData
import SwiftUI

/// Full ledger remains available for records outside the selected Money week.
struct ExpenseListView: View {
    @Query(sort: [SortDescriptor(\Expense.occurredAt, order: .reverse), SortDescriptor(\Expense.id)])
    private var expenses: [Expense]
    @State private var actions = ExpenseActions()

    var body: some View {
        List {
            Section {
                Button { actions.editing = .new } label: {
                    Label("Add Expense", systemImage: "plus").frame(minHeight: 44)
                }
                .accessibilityIdentifier("addExpenseButton")
            }
            if _expenses.fetchError != nil {
                Section { DashNotice(title: "Couldn't load expenses", message: "Reopen Expenses to try again.", symbol: "exclamationmark.triangle") }
            } else if expenses.isEmpty {
                Section {
                    DashNotice(title: "No expenses recorded yet", message: "A cost you add appears here, newest first.", symbol: "creditcard")
                        .accessibilityIdentifier("expensesEmptyState")
                }
            } else {
                Section("All recorded expenses · Newest first") {
                    ForEach(expenses) { expense in
                        ExpenseRecordButton(row: expense.presentation, actions: actions)
                    }
                }
            }
        }
        .dashCanvas()
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ExpenseActionPresentation(actions: actions))
    }
}

/// One recorded expense in the list.
///
/// Read as one accessibility element, because the amount, the category and the
/// date are one record rather than three fragments, and because the date and
/// the note are what tell two amounts apart.
struct ExpenseRow: View {
    let expense: ExpensePresentation

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            heading
            Text(expense.occurredAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                .dashFont(.body)
                .foregroundStyle(.secondary)
            if let note = expense.note {
                Text(note)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DashSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The category and the amount share a line, until the text is large enough
    /// that one of them would be truncated. A shortened amount is worse than a
    /// second line. The complete amount then fits on its own line.
    @ViewBuilder
    private var heading: some View {
        let category = Label(expense.category.title, systemImage: expense.category.systemImage)
            .dashFont(.emphasis)
            .fixedSize(horizontal: false, vertical: true)
        let amount = Text(expense.amount.formatted(locale: locale))
            .dashFont(.emphasis)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)

        if dynamicTypeSize.isAccessibilitySize {
            category
            amount
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    category
                    Spacer(minLength: DashSpacing.md)
                    amount.fixedSize(horizontal: true, vertical: true)
                }
                VStack(alignment: .leading, spacing: DashSpacing.sm) {
                    category
                    amount
                }
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
