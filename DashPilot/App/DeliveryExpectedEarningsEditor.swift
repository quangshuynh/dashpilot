import SwiftData
import SwiftUI

/// Records or changes what the driver expects one delivery **in progress** to
/// pay.
///
/// ## Why this one is offered while the shift runs and the other is not
///
/// ``DeliveryEarningsEditor`` refuses to appear on a running delivery, because
/// typing what an order paid is a review task and a monetary keyboard beside
/// the lifecycle buttons is the interaction this project designs away. This
/// editor is the same keyboard on the same screen, so the difference has to be
/// earned rather than asserted.
///
/// It is earned by *when* the figure is available. The amount an offer showed is
/// on the phone at the kerb and gone by the evening; a driver who cannot write
/// it down while they are waiting for a bag either reconstructs it from memory
/// hours later or never records it at all. The interaction is entered from a
/// small secondary control, is skippable on every delivery, and the delivery
/// advances identically without it — exactly the shape ``PickupPlaceEditor``
/// already has for the same reason.
///
/// ## What it does not do
///
/// **It records nothing any total will count.** The amount goes into its own
/// column through ``DeliveryService/setExpectedEarnings(_:on:)``; no shift
/// figure, period figure, rate or export summary moves because of it, and the
/// delivery's recorded gross earnings are untouched. Saying so is the footer's
/// job, because a driver typing money into a field is entitled to know which
/// question they just answered.
///
/// Editing is a **draft**, like every other amount editor here: the typed text
/// is view state, the store is written once on Save or Remove, and dismissing
/// the sheet leaves the recorded expectation exactly as it was.
struct DeliveryExpectedEarningsEditor: View {
    let numbered: NumberedDelivery

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The draft. Seeded from the stored expectation, and never read by
    /// anything but ``save()``.
    @State private var text = ""
    @State private var message: String?
    @FocusState private var isAmountFocused: Bool

    private var delivery: Delivery { numbered.delivery }

    private var hasExpectedEarnings: Bool { delivery.expectedEarnings != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .font(.title2)
                        .monospacedDigit()
                        .accessibilityIdentifier("deliveryExpectedEarningsAmountField")
                        .accessibilityLabel("Expected pay for \(numbered.title)")
                        .onChange(of: text) { _, _ in
                            message = nil
                        }

                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("deliveryExpectedEarningsValidationMessage")
                    }
                } header: {
                    Text("Expected Pay")
                } footer: {
                    Text(
                        """
                        What you expect \(numbered.title) to pay, as you choose to record it. It is not \
                        gross earnings: nothing counts it, no total or rate includes it, and it does \
                        not appear in any summary. DashPilot will offer it back when you mark this \
                        delivery delivered, so you can record what it actually paid.
                        """
                    )
                }

                if hasExpectedEarnings {
                    Section {
                        Button("Remove Expected Pay", role: .destructive, action: remove)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeDeliveryExpectedEarningsButton")
                            .accessibilityLabel(numbered.spokenRemoveExpectedEarningsLabel)
                    } footer: {
                        Text(
                            """
                            Removes the expected amount entirely. A delivery with none recorded is not \
                            the same as one you expect to pay \(Money.zero.formatted(locale: locale)).
                            """
                        )
                    }
                }
            }
            .navigationTitle(numbered.expectedEarningsActionTitle(hasExpected: hasExpectedEarnings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelDeliveryExpectedEarningsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveDeliveryExpectedEarningsButton")
                }
            }
        }
        .onAppear {
            if let expected = delivery.expectedEarnings {
                text = MoneyInput(locale: locale).text(for: expected)
            }
            isAmountFocused = true
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func save() {
        do {
            let expected = try MoneyInput(locale: locale).amount(from: text)
            try DeliveryService(context: modelContext).setExpectedEarnings(expected, on: delivery)
            dismiss()
        } catch let error as MoneyInputError {
            // The expected subject, so an empty field and a minus sign are
            // refused in the words of what is being typed rather than in the
            // words of an amount the driver is not recording.
            message = error.message(for: .expectedEarnings)
            isAmountFocused = true
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That amount could not be saved."
            isAmountFocused = true
        }
    }

    private func remove() {
        do {
            try DeliveryService(context: modelContext).clearExpectedEarnings(on: delivery)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "The amount could not be removed."
        }
    }
}

#if DEBUG
#Preview("Add expected pay") {
    PreviewSupport.deliveryExpectedEarningsEditor(withExpectedEarnings: false)
}

#Preview("Change expected pay") {
    PreviewSupport.deliveryExpectedEarningsEditor(withExpectedEarnings: true)
}
#endif
