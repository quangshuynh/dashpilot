import SwiftData
import SwiftUI

/// Records or changes what one finished delivery paid.
///
/// Presented only from a finished delivery in a completed shift's history.
/// Typing an amount is the kind of task that must happen while stopped, so
/// nothing on the running-shift screen offers earnings entry for a delivery in
/// progress — and ``Delivery/setGrossEarnings(_:)`` refuses it as well, because
/// a screen that is merely never presented is not a rule.
///
/// Deliberately a second small editor rather than a generalisation of
/// ``ShiftEarningsEditor``. The two share the parser, the money type and the
/// service rules — everything where a difference would be a bug — and differ in
/// what they say, which delivery or shift they name, and what removing an amount
/// means. Folding them into one configurable editor would trade a page of
/// shared sentences for a page of parameters, and make the shift's flow harder
/// to read in order to describe both.
///
/// Editing is a **draft**. The typed text is view state; the store is written
/// once, when the driver taps Save or Remove. Cancelling — or dismissing the
/// sheet — leaves the recorded amount exactly as it was, and nothing is written
/// per keystroke.
struct DeliveryEarningsEditor: View {
    let numbered: NumberedDelivery

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The draft. Seeded from the stored amount, and never read by anything
    /// but ``save()``.
    @State private var text = ""
    @State private var message: String?
    @FocusState private var isAmountFocused: Bool

    private var delivery: Delivery { numbered.delivery }

    private var hasRecordedEarnings: Bool { delivery.grossEarnings != nil }

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
                        .accessibilityIdentifier("deliveryEarningsAmountField")
                        .accessibilityLabel("Gross earnings for \(numbered.title)")
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
                            .accessibilityIdentifier("deliveryEarningsValidationMessage")
                    }
                } header: {
                    Text("Gross Earnings")
                } footer: {
                    Text(
                        """
                        What this delivery paid, as you choose to record it. It is separate from the \
                        amount recorded for the shift: DashPilot never splits a shift total between \
                        deliveries, never adds one up from them, and does not mind if they differ.
                        """
                    )
                }

                if hasRecordedEarnings {
                    Section {
                        Button("Remove Earnings", role: .destructive, action: remove)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeDeliveryEarningsButton")
                            .accessibilityLabel(numbered.spokenRemoveEarningsLabel)
                    } footer: {
                        Text(
                            """
                            Removes the amount entirely. A delivery with no amount recorded is not the \
                            same as one that paid \(Money.zero.formatted(locale: locale)).
                            """
                        )
                    }
                }
            }
            .navigationTitle(numbered.earningsActionTitle(hasEarnings: hasRecordedEarnings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelDeliveryEarningsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveDeliveryEarningsButton")
                }
            }
        }
        .onAppear {
            if let earnings = delivery.grossEarnings {
                text = MoneyInput(locale: locale).text(for: earnings)
            }
            isAmountFocused = true
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func save() {
        do {
            let earnings = try MoneyInput(locale: locale).amount(from: text)
            try DeliveryService(context: modelContext).setGrossEarnings(earnings, on: delivery)
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
            try DeliveryService(context: modelContext).clearGrossEarnings(on: delivery)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "The amount could not be removed."
        }
    }
}

#if DEBUG
#Preview("Add delivery earnings") {
    PreviewSupport.deliveryEarningsEditor(withRecordedEarnings: false)
}

#Preview("Edit delivery earnings") {
    PreviewSupport.deliveryEarningsEditor(withRecordedEarnings: true)
}
#endif
