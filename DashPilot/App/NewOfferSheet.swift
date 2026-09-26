import SwiftData
import SwiftUI

/// Records an offer the driver accepted that contains more than one delivery.
///
/// ## Why a second control rather than a changed one
///
/// Most offers are one delivery, and that path is one tap. Putting a count in
/// front of it would charge every driver an extra decision for the ordinary
/// case, on the screen this project is most careful about. So `Start Delivery`
/// is untouched and means exactly what it always meant, and this sheet is
/// reached from a small secondary control beside it, in the same shape the
/// pickup-place and expected-pay controls already have.
///
/// ## What it asks for, and what it refuses to ask for
///
/// **A count, and nothing else.** No pickup place, no expected amount, no
/// customer and no name: every one of those is optional on a delivery, can be
/// added later from the delivery's own card, and asking for any of them at a
/// kerb is the interaction this project designs away. The deliveries are
/// numbered by the shift, which is the only label DashPilot has for them and the
/// only one it will invent.
///
/// The stepper's range is a **control's bounds, not a domain rule**: the store
/// refuses an offer below one delivery and caps nothing above it, because how
/// much work a driver accepted is a fact about their work. The upper bound here
/// is what a stepper can be tapped to without becoming a way to mis-record a
/// shift, and the lower bound is two because an offer of one is the button this
/// sheet sits under.
///
/// Nothing is written until the confirm button is pressed. Dismissing the sheet
/// records no offer and no delivery.
struct NewOfferSheet: View {
    /// Called with the count the driver confirmed. The write lives with the
    /// panel's other lifecycle writes, so a refusal is reported in the one place
    /// this screen reports them.
    let start: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Two, because this sheet exists for offers that hold more than one
    /// delivery, and a driver who opens it has already said theirs does.
    @State private var deliveryCount = 2

    /// The most a stepper is a sensible way to say a number. See the note above:
    /// this is the control's range and not the model's.
    private static let range = 2...10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $deliveryCount, in: Self.range) {
                        LabeledContent("Deliveries") {
                            Text(deliveryCount, format: .number)
                                .monospacedDigit()
                                .dashFont(.metric)
                        }
                    }
                    .accessibilityIdentifier("offerDeliveryCountStepper")
                    .accessibilityLabel("Deliveries in this offer")
                    .accessibilityValue("\(deliveryCount)")
                } header: {
                    Text("Deliveries in This Offer")
                } footer: {
                    Text(
                        """
                        How many deliveries you accepted together. Each one is recorded separately and \
                        takes its own steps, so you can pick one up while another is still waiting. \
                        You can add a pickup place or expected pay to any of them afterwards.
                        """
                    )
                }

                Section {
                    Button(action: confirm) {
                        Text(confirmTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("confirmStartOfferButton")
                    .accessibilityLabel("Start an offer of \(deliveryCount) deliveries")
                }
            }
            .navigationTitle("Offer With Several Deliveries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelStartOfferButton")
                }
            }
        }
    }

    /// The button says what it will record, including the number, so the count
    /// is confirmed twice on a screen that may be read in a hurry.
    private var confirmTitle: String { "Start \(deliveryCount) Deliveries" }

    private func confirm() {
        start(deliveryCount)
        dismiss()
    }
}

#if DEBUG
#Preview("An offer of several deliveries") {
    NewOfferSheet(start: { _ in })
}
#endif
