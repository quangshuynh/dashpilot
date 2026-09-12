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
///
/// ## Where the expected amount fits
///
/// A delivery may also carry what the driver expected it to pay, entered while
/// it was still in progress. This editor is the one place both amounts are on
/// screen together, and it keeps them apart in three ways: the expectation is
/// **stated** in its own section and cannot be typed into, the field below is
/// labelled and explained as the recorded gross, and the expectation is never
/// written by saving this sheet. Seeding the field from it is a convenience and
/// is said out loud in the footer; what gets recorded is whatever the field
/// holds when Save is pressed.
///
/// Removing the expectation lives here too, because this is where a terminal
/// delivery's money is edited and ``DeliveryExpectedEarningsEditor`` is
/// deliberately unreachable once the delivery has finished.
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
                // Above the field, stated and not editable, exactly as
                // ``DeliveryEarningsConfirmation`` states it: the driver has to
                // be able to see which figure is the reference and which one
                // they are recording, and a value that cannot be typed into
                // says so without a caption.
                if let expected = delivery.expectedEarnings {
                    Section {
                        LabeledContent("Expected pay") {
                            Text(expected.formatted(locale: locale))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(spokenExpectedLabel(expected))
                        .accessibilityIdentifier("deliveryEarningsExpectedAmount")

                        Button("Remove Expected Pay", role: .destructive, action: removeExpected)
                            .accessibilityIdentifier("removeDeliveryExpectedEarningsButton")
                            .accessibilityLabel(numbered.spokenRemoveExpectedEarningsLabel)
                    } header: {
                        Text("What You Expected")
                    } footer: {
                        Text(
                            """
                            What you recorded expecting \(numbered.title) to pay while it was in \
                            progress. It is not earnings and no total includes it. Removing it leaves \
                            whatever you record below untouched.
                            """
                        )
                    }
                }

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
                    Text(grossEarningsExplanation)
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
            // A recorded amount wins: it is what this editor is for. Failing
            // that, the field is **seeded** from the expectation, which saves a
            // driver retyping a figure the app is already holding.
            //
            // Seeding is not recording. Nothing is written until Save is
            // pressed, the expected figure is stated above the field so the
            // number in it is not mistaken for something already stored, and
            // what gets recorded is whatever the field says at that moment
            // rather than the expectation it started from.
            if let earnings = delivery.grossEarnings {
                text = MoneyInput(locale: locale).text(for: earnings)
            } else if let expected = delivery.expectedEarnings {
                text = MoneyInput(locale: locale).text(for: expected)
            }
            isAmountFocused = true
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    /// What the amount being typed is, said in the terms of what the delivery
    /// already carries.
    ///
    /// The seeded case gets its own sentence because a field that is already
    /// full is the one arrangement a driver could mistake for something the app
    /// has recorded. Saying that nothing is recorded until Save is pressed is
    /// the whole distinction this screen exists to keep.
    private var grossEarningsExplanation: String {
        let shared = """
            It is separate from the amount recorded for the shift: DashPilot never splits a shift \
            total between deliveries, never adds one up from them, and does not mind if they differ.
            """

        if !hasRecordedEarnings, delivery.expectedEarnings != nil {
            return """
                What this delivery actually paid. The field starts from what you expected, so change \
                it if it differs. Nothing is recorded until you save. \(shared)
                """
        }
        return "What this delivery paid, as you choose to record it. \(shared)"
    }

    /// The expected figure spoken with what it is not, in the phrasing that
    /// matches whether a recorded amount exists beside it.
    private func spokenExpectedLabel(_ expected: Money) -> String {
        let amount = expected.formatted(locale: locale)
        return hasRecordedEarnings
            ? numbered.spokenExpectedEarningsBesideRecorded(amount)
            : numbered.spokenExpectedEarnings(amount)
    }

    private func removeExpected() {
        do {
            try DeliveryService(context: modelContext).clearExpectedEarnings(on: delivery)
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "The expected amount could not be removed."
        }
    }

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
