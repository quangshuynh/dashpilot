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

    /// Set by the first press of the start button, so a second press that
    /// lands before the sheet has gone records nothing. Two offers from one
    /// double tap would be a mistake the driver has to find and cancel.
    @State private var hasStarted = false

    /// The most a stepper is a sensible way to say a number. See the note above:
    /// this is the control's range and not the model's.
    private static let range = 2...10

    /// Action first, because this sheet is opened at a kerb with an offer just
    /// accepted: the count and the two switches lead, the button that records
    /// them stays at the bottom of the screen however far the form is
    /// scrolled, and what the switches mean in full is said last. VoiceOver
    /// reads the count, the switches and the button, and hears the explanation
    /// as the button's hint.
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
                }

                Section {
                    DashSettingToggle(
                        isOn: $sharesPickup,
                        title: SharedStopKind.pickup.title,
                        detail: "One pickup stop. Park & Resume, if on, marks them arrived and picked up together.",
                        hint: "Turn on only if every delivery in this offer is collected at the same pickup.",
                        identifier: "offerSamePickupToggle"
                    )
                    DashSettingToggle(
                        isOn: $sharesDropOff,
                        title: SharedStopKind.dropOff.title,
                        detail: "One drop-off stop. Each is still marked delivered on its own.",
                        hint: "Turn on only if every delivery in this offer goes to the same drop-off.",
                        identifier: "offerSameDropOffToggle"
                    )
                } header: {
                    Text("Together")
                }

                Section {
                    Text(Self.explanation)
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                        // Heard as the button's hint instead, so a listener
                        // meets Start before the explanation rather than after.
                        .accessibilityHidden(true)
                }
            }
            // The action is pinned below the form in its safe area, so it is
            // reachable at every text size while the form scrolls, and the
            // form is inset by its height so the explanation scrolls fully
            // above it rather than under it.
            .safeAreaBar(edge: .bottom) {
                Button(action: confirm) {
                    Text(confirmTitle)
                        .dashFont(.control)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(hasStarted)
                .accessibilityIdentifier("confirmStartOfferButton")
                .accessibilityLabel(confirmSpokenLabel)
                .accessibilityHint(Self.explanation)
                .padding(.horizontal, DashSpacing.xl)
                .padding(.vertical, DashSpacing.md)
                .background {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .top) { Divider() }
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

    /// What the switches mean in full, said after the controls: printed under
    /// the form, and spoken as the button's hint.
    private static let explanation = """
        Leave both off unless the orders really share the stop: DashPilot never infers either, and \
        stores no customer or address. Each delivery takes its own steps, and a pickup place or \
        expected pay can be added to any of them later.
        """

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
        guard !hasStarted else { return }
        hasStarted = true
        start(deliveryCount, sharing)
        dismiss()
    }
}

#if DEBUG
#Preview("An offer of several deliveries") {
    NewOfferSheet(start: { _, _ in })
}
#endif
