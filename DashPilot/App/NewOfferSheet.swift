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
/// **A count, and two optional switches.** No pickup place, no expected
/// amount, no customer and no name: every one of those is optional on a
/// delivery, can be added later from the delivery's own card, and asking for
/// any of them at a kerb is the interaction this project designs away. The
/// deliveries are numbered by the shift, which is the only label DashPilot has
/// for them and the only one it will invent.
///
/// The switches say whether the deliveries share a **pickup** and whether they
/// share a **drop-off**, each off unless the driver turns it on. They are two
/// because they are two facts: one customer can order from two restaurants.
/// Both off is the ordinary case and records the deliveries as independent,
/// exactly as before, and nothing ever turns one on because the deliveries
/// arrived in one offer. They apply to every delivery of the offer; a driver
/// whose offer of three shares a stop between two says so afterwards, in
/// `Correct Grouping`. No customer, address or place is asked for or stored.
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
    /// Called with the count and the shared stops the driver confirmed. The
    /// write lives with the panel's other lifecycle writes, so a refusal is
    /// reported in the one place this screen reports them.
    let start: (Int, Set<SharedStopKind>) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Two, because this sheet exists for offers that hold more than one
    /// delivery, and a driver who opens it has already said theirs does.
    @State private var deliveryCount = 2

    /// Both off: deliveries accepted together are independent unless the driver
    /// says otherwise.
    @State private var sharesPickup = false
    @State private var sharesDropOff = false

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
                        How many deliveries you accepted together. Each takes its own steps, so you \
                        can pick one up while another waits. Add a pickup place or expected pay to any \
                        of them later.
                        """
                    )
                }

                Section {
                    Toggle(isOn: $sharesPickup) {
                        Text(SharedStopKind.pickup.title)
                            .dashFont(.body)
                    }
                    .accessibilityHint("Turn on only if every delivery in this offer is collected at the same pickup.")
                    .accessibilityIdentifier("offerSamePickupToggle")

                    Toggle(isOn: $sharesDropOff) {
                        Text(SharedStopKind.dropOff.title)
                            .dashFont(.body)
                    }
                    .accessibilityHint("Turn on only if every delivery in this offer goes to the same drop-off.")
                    .accessibilityIdentifier("offerSameDropOffToggle")
                } header: {
                    Text("Together")
                } footer: {
                    Text(
                        """
                        Leave these off unless the orders really share it. With Pick up orders with Park & \
                        Resume on, orders marked Same pickup are marked arrived and picked up together. Same \
                        drop-off only shows they belong together. DashPilot stores no customer or address.
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
                    .accessibilityLabel(confirmSpokenLabel)
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

    /// The chosen stops are part of what is confirmed, so a listener hears them
    /// before pressing, and hears nothing extra when neither is on.
    private var confirmSpokenLabel: String {
        let base = "Start an offer of \(deliveryCount) deliveries"
        let shared = sharing.sorted { $0.rawValue > $1.rawValue }.map { $0.title.lowercased() }
        guard !shared.isEmpty else { return base }
        return "\(base), \(shared.joined(separator: " and "))"
    }

    private var sharing: Set<SharedStopKind> {
        var kinds: Set<SharedStopKind> = []
        if sharesPickup { kinds.insert(.pickup) }
        if sharesDropOff { kinds.insert(.dropOff) }
        return kinds
    }

    private func confirm() {
        start(deliveryCount, sharing)
        dismiss()
    }
}

#if DEBUG
#Preview("An offer of several deliveries") {
    NewOfferSheet(start: { _, _ in })
}
#endif
