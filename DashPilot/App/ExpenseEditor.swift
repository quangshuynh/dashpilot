import SwiftData
import SwiftUI

/// Records a new operating cost, or corrects one already recorded.
///
/// ## A draft, saved once
///
/// Everything on this sheet is view state until the driver taps Save. Cancelling
/// — or dismissing the sheet — writes nothing, and nothing is written per
/// keystroke, which is the same rule the earnings editors follow.
///
/// ## Not a driving surface
///
/// Typing an amount and a note is a stopped-vehicle task, and this sheet is
/// reached from the expense list rather than from the shift controls. It is
/// never presented during a delivery flow and never interrupts one.
///
/// ## What it does not ask for
///
/// Which shift the cost belongs to. There is no such field because there is no
/// such fact: an expense carries the date it happened, and DashPilot does not
/// attach one to a shift or divide it across work. See ``Expense``.
struct ExpenseEditor: View {
    /// The expense being corrected, or `nil` when recording a new one.
    let expense: Expense?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var amountText = ""
    @State private var category: ExpenseCategory = .fuel
    @State private var occurredAt = Date.now
    @State private var noteText = ""
    @State private var message: String?

    /// Fixed when the sheet appears rather than read continuously, so the latest
    /// selectable moment cannot move under the driver while they are choosing.
    @State private var now = Date.now

    @FocusState private var isAmountFocused: Bool

    private var isEditing: Bool { expense != nil }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                detailSection
                noteSection
                if isEditing { deleteSection }
            }
            .navigationTitle(isEditing ? "Edit Expense" : "Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelExpenseButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveExpenseButton")
                }
            }
        }
        .onAppear(perform: seed)
    }

    // MARK: Sections

    private var amountSection: some View {
        Section {
            // A decimal pad: the field holds an amount, and a full keyboard
            // offers a driver in a parked car a lot of keys that can only
            // produce a validation message.
            TextField(placeholder, text: $amountText)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .font(.title2)
                .monospacedDigit()
                .accessibilityIdentifier("expenseAmountField")
                .accessibilityLabel("Expense amount")
                .onChange(of: amountText) { _, _ in message = nil }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("expenseValidationMessage")
            }
        } header: {
            Text("Amount")
        } footer: {
            Text(
                """
                What this cost, as you choose to record it. DashPilot sees no purchase of its own: \
                nothing is read from a card, a receipt or an app, and no cost is estimated from your \
                mileage.
                """
            )
        }
    }

    private var detailSection: some View {
        Section {
            Picker("Category", selection: $category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage).tag(category)
                }
            }
            .accessibilityIdentifier("expenseCategoryPicker")

            // Date and time: two costs on one day are told apart by the time,
            // and the time is what puts a cost recorded around midnight in the
            // day the driver means.
            //
            // Bounded at the present. An expense is something that already
            // happened, and a mistyped year would silently drop the record out
            // of every period the driver looks at.
            DatePicker(
                "Date",
                selection: $occurredAt,
                in: ...latestSelectableMoment,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("expenseDatePicker")
        } header: {
            Text("Details")
        } footer: {
            Text(
                """
                An expense belongs to the date you give it, not to a shift. DashPilot does not attach \
                costs to shifts or deliveries, and never divides one across your work.
                """
            )
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Optional", text: $noteText, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("expenseNoteField")
                .accessibilityLabel("Expense note, optional")
                .onChange(of: noteText) { _, _ in message = nil }
        } header: {
            Text("Note")
        } footer: {
            Text(
                """
                A short reminder of which purchase this was, up to \(ExpenseNote.maximumLength) \
                characters. It stays on this device and is never logged, and it is included in an \
                export you choose to share.
                """
            )
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Expense", role: .destructive, action: delete)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("deleteExpenseButton")
        } footer: {
            Text("Removes this record entirely. Nothing else in DashPilot changes.")
        }
    }

    // MARK: Behaviour

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    /// Today is selectable in full; tomorrow is not. The same rule the custom
    /// range picker applies, for the same reason: DashPilot records what has
    /// already happened.
    private var latestSelectableMoment: Date { max(now, occurredAt) }

    private func seed() {
        guard let expense else {
            isAmountFocused = true
            return
        }
        amountText = MoneyInput(locale: locale).text(for: expense.amount)
        category = expense.category
        occurredAt = expense.occurredAt
        noteText = expense.note ?? ""
    }

    private func save() {
        do {
            let amount = try MoneyInput(locale: locale).amount(from: amountText)
            let service = ExpenseService(context: modelContext)
            if let expense {
                try service.update(
                    expense,
                    amount: amount,
                    category: category,
                    occurredAt: occurredAt,
                    noteText: noteText
                )
            } else {
                try service.record(
                    amount: amount,
                    category: category,
                    occurredAt: occurredAt,
                    noteText: noteText
                )
            }
            dismiss()
        } catch let error as MoneyInputError {
            // The sheet stays open with what the driver typed: an amount that
            // could not be saved is not a reason to make them type it again.
            message = error.message(for: .expense)
            isAmountFocused = true
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That expense could not be saved."
        }
    }

    private func delete() {
        guard let expense else { return }
        do {
            try ExpenseService(context: modelContext).delete(expense)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That expense could not be deleted."
        }
    }
}

#if DEBUG
#Preview("Add expense") {
    PreviewSupport.expenseEditor(editingExisting: false)
}

#Preview("Edit expense") {
    PreviewSupport.expenseEditor(editingExisting: true)
}
#endif
