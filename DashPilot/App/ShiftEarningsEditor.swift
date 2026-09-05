import SwiftData
import SwiftUI

/// Records or changes what a completed shift paid.
///
/// Presented only from a finished shift in history. Typing an amount is the
/// kind of task that must happen while stopped, so nothing anywhere in the app
/// offers earnings entry during a running shift — and the model refuses it as
/// well, because a screen that is merely never presented is not a rule.
///
/// Editing is a **draft**. The typed text is view state; the store is written
/// once, when the driver taps Save or Remove. Cancelling — or dismissing the
/// sheet — leaves the recorded amount exactly as it was, and nothing is written
/// per keystroke.
struct ShiftEarningsEditor: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The draft. Seeded from the stored amount, and never read by anything
    /// but ``save()``.
    @State private var text = ""
    @State private var message: String?
    @FocusState private var isAmountFocused: Bool

    private var hasRecordedEarnings: Bool { shift.grossEarnings != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A decimal pad: the field holds an amount, and a full
                    // keyboard would offer a driver in a parked car a lot of
                    // keys that can only produce a validation message.
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .font(.title2)
                        .monospacedDigit()
                        .accessibilityIdentifier("earningsAmountField")
                        .accessibilityLabel("Gross earnings")
                        .onChange(of: text) { _, _ in
                            // The message describes the text that produced it,
                            // so it goes as soon as the text does.
                            message = nil
                        }

                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("earningsValidationMessage")
                    }
                } header: {
                    Text("Gross Earnings")
                } footer: {
                    Text(
                        """
                        What this shift paid, as you choose to record it. \
                        DashPilot is not connected to any delivery platform, so nothing is imported \
                        and nothing is checked — this is your own figure, kept on this device.
                        """
                    )
                }

                if hasRecordedEarnings {
                    Section {
                        Button("Remove Earnings", role: .destructive, action: remove)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeEarningsButton")
                    } footer: {
                        Text("Removes the amount entirely. A shift with no amount recorded is not the same as one that paid $0.00.")
                    }
                }
            }
            .navigationTitle(hasRecordedEarnings ? "Edit Earnings" : "Add Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelEarningsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveEarningsButton")
                }
            }
        }
        .onAppear {
            if let earnings = shift.grossEarnings {
                text = MoneyInput(locale: locale).text(for: earnings)
            }
            isAmountFocused = true
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func save() {
        do {
            let earnings = try MoneyInput(locale: locale).amount(from: text)
            try ShiftService(context: modelContext).setGrossEarnings(earnings, on: shift)
            dismiss()
        } catch {
            // The sheet stays open with the text the driver typed: an amount
            // that could not be saved is not a reason to make them type it
            // again. Focus goes back to the field so the correction is one tap
            // closer.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That amount could not be saved."
            isAmountFocused = true
        }
    }

    private func remove() {
        do {
            try ShiftService(context: modelContext).clearGrossEarnings(on: shift)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "The amount could not be removed."
        }
    }
}

#if DEBUG
#Preview("Add earnings") {
    PreviewSupport.earningsEditor(withRecordedEarnings: false)
}

#Preview("Edit earnings") {
    PreviewSupport.earningsEditor(withRecordedEarnings: true)
}
#endif
