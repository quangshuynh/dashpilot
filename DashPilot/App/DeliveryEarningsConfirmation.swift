import SwiftData
import SwiftUI

/// Offers the amount a delivery was expected to pay back to the driver, so they
/// can record what it actually paid in one tap or correct it in two.
///
/// ## The rule this sheet implements
///
/// Marking a delivery delivered **never** records a gross amount by itself, and
/// never turns the expected amount into one. The delivery is already written as
/// delivered before this appears; everything here is additive, and dismissing it
/// leaves the delivery exactly as the lifecycle left it: terminal, with an
/// expectation recorded and no gross earnings. That is a coherent state the app
/// shows plainly rather than a half-finished one, and the completed shift's
/// history offers the same confirmation again whenever the driver is ready.
///
/// So there is exactly one thing that writes a recorded gross amount, here as
/// everywhere else in DashPilot: a driver pressing a control that says it will.
///
/// ## Why it appears at all
///
/// Because the alternative to asking is guessing. Without it there are only two
/// designs left: finalize the expectation silently, which puts a figure nothing
/// confirmed into a driver's earnings history, or say nothing and leave every
/// delivery to be reconciled that evening from an amount the driver can no
/// longer see. Asking once, at the moment the delivery ends, is the only version
/// where the app writes nothing the driver did not agree to and they still do
/// not have to remember anything.
///
/// ## Why it is not in the way
///
/// It appears **only** for a delivery that carries an expectation, so a driver
/// who does not use the feature never sees it and the existing flow is
/// unchanged to the tap. It has a large dismissal control and no field focused
/// on appearance, so confirming or leaving is one deliberate tap and neither
/// raises a keyboard. Editing is available and is never required; a driver who
/// wants to correct the figure is by definition a driver who has stopped, since
/// they have just handed an order over.
struct DeliveryEarningsConfirmation: View {
    let numbered: NumberedDelivery

    /// The expectation this sheet was raised for.
    ///
    /// Passed in rather than re-read from the delivery, so that the figure being
    /// offered is the one the sheet opened with even if the store changes
    /// underneath it, and so the sheet cannot appear with nothing to offer.
    let expected: Money

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The draft gross amount. Seeded from the expectation, and the only thing
    /// ``record()`` reads: what is recorded is whatever this field says when the
    /// driver presses the button, never the stored expectation.
    @State private var text = ""
    @State private var message: String?
    @FocusState private var isAmountFocused: Bool

    private var delivery: Delivery { numbered.delivery }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Stated, not editable, and above the field rather than
                    // inside it. The whole risk this sheet carries is a driver
                    // reading one figure as the other, and a value that cannot
                    // be typed into is the clearest way to say which one is the
                    // reference and which one is being recorded.
                    LabeledContent("Expected pay") {
                        Text(expected.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(numbered.spokenExpectedEarnings(expected.formatted(locale: locale)))
                    .accessibilityIdentifier("confirmEarningsExpectedAmount")
                } header: {
                    Text("What You Expected")
                } footer: {
                    Text(
                        """
                        This is what you recorded expecting \(numbered.title) to pay. Nothing has been \
                        recorded as earnings yet.
                        """
                    )
                }

                Section {
                    // Deliberately not focused on appearance. The keyboard
                    // arriving unasked is what would make this sheet something
                    // to dismiss rather than something to answer.
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .font(.title2)
                        .monospacedDigit()
                        .accessibilityIdentifier("confirmEarningsAmountField")
                        .accessibilityLabel("Gross earnings for \(numbered.title)")
                        .onChange(of: text) { _, _ in
                            message = nil
                        }

                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("confirmEarningsValidationMessage")
                    }

                    Button(action: record) {
                        Text("Record as Gross Earnings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("Record gross earnings for \(numbered.title)")
                    .accessibilityIdentifier("confirmEarningsRecordButton")
                } header: {
                    Text("Gross Earnings")
                } footer: {
                    Text(
                        """
                        What \(numbered.title) actually paid. Change it if it differs from what you \
                        expected. This is the amount DashPilot records, and the only one its totals \
                        and rates are worked out from.
                        """
                    )
                }

                Section {
                    Button("Not Now", role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                        .accessibilityLabel("Record no earnings for \(numbered.title) now")
                        .accessibilityIdentifier("confirmEarningsDismissButton")
                } footer: {
                    Text(
                        """
                        Leaves \(numbered.title) with no gross earnings recorded. What you expected is \
                        kept, and this shift's history will offer it again.
                        """
                    )
                }
            }
            .navigationTitle("\(numbered.title) Delivered")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            text = MoneyInput(locale: locale).text(for: expected)
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func record() {
        do {
            let earnings = try MoneyInput(locale: locale).amount(from: text)
            try DeliveryService(context: modelContext).setGrossEarnings(earnings, on: delivery)
            dismiss()
        } catch {
            // The sheet stays open holding what the driver typed, like every
            // other amount editor here.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That amount could not be saved."
            isAmountFocused = true
        }
    }
}

#if DEBUG
#Preview("Confirm what a delivery paid") {
    PreviewSupport.deliveryEarningsConfirmation()
}
#endif
