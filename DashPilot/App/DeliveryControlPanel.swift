import SwiftData
import SwiftUI

/// The running shift's delivery controls: one card per delivery being worked,
/// each offering only its own next step.
///
/// ## Why a list rather than one button
///
/// A driver can be carrying two or three orders at once, so there is no single
/// "the delivery" for one control to advance. The panel shows each active
/// delivery separately and gives each one a single primary button — whatever
/// ``DeliveryState/nextAction`` says comes next for *that* delivery — so the
/// driver never picks a lifecycle event out of a menu, and never picks which
/// delivery a tap belongs to out of an implicit rule. Two active deliveries
/// means two buttons, each already saying the right thing.
///
/// `Start Delivery` stays available underneath at all times while the shift
/// runs, because accepting another order is normal work rather than an
/// exception.
///
/// Every button acts on the persisted delivery its card was built from, so the
/// numbering is a label and nothing more: it could change and a tap would still
/// reach the same record.
///
/// Nothing here is detected. Every tap records an event the driver witnessed;
/// DashPilot does not know that an order was accepted, handed over or received.
///
/// The active deliveries are read from the store rather than held in view
/// state, which is what makes relaunch recovery ordinary: deliveries left active
/// when the app was terminated are all still active on the next launch, each
/// with its own next step.
struct DeliveryControlPanel: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    /// Write-only from here, like ``RootView``'s: a delivery starting or
    /// advancing changes what the shift's Live Activity should say, including
    /// whether it may offer a step control at all.
    @Environment(ShiftLiveActivityService.self) private var liveActivity

    /// Every unfinished delivery in the store.
    ///
    /// A `@Query` rather than the shift's relationship alone, because it is what
    /// rebuilds the panel when a delivery is inserted or advanced. It says
    /// *which* deliveries are running; the shift supplies the order they were
    /// accepted in, which is where each card's number comes from.
    @Query(
        filter: #Predicate<Delivery> { $0.deliveredAt == nil && $0.cancelledAt == nil },
        sort: \Delivery.acceptedAt
    )
    private var unfinishedDeliveries: [Delivery]

    @State private var lifecycleError: DeliveryLifecycleError?

    /// The delivery a cancellation is being confirmed for. Held as the numbered
    /// delivery itself rather than as a flag, so the confirmation can name which
    /// one it is about and act on that record.
    @State private var pendingCancellation: NumberedDelivery?

    /// The delivery just marked delivered, and the amount it was expected to
    /// pay, when it had one recorded.
    ///
    /// Captured **before** the transition and held here, rather than re-read
    /// from the delivery afterwards, for two reasons. The delivered delivery
    /// leaves ``activeDeliveries`` the moment the write lands, so its card is
    /// gone and there is nothing left on screen to hang the sheet off; and the
    /// figure being offered has to be the one the driver entered, not whatever
    /// the store happens to say a moment later.
    @State private var pendingEarningsConfirmation: PendingEarningsConfirmation?

    private var activeDeliveries: [NumberedDelivery] {
        let running = Set(unfinishedDeliveries.lazy.filter { $0.shift?.id == shift.id }.map(\.id))
        return shift.numberedDeliveries.filter { running.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            status

            ForEach(activeDeliveries) { numbered in
                ActiveDeliveryCard(
                    numbered: numbered,
                    advance: { perform(.advance(numbered)) },
                    cancel: { pendingCancellation = numbered }
                )
            }

            startControl
        }
        .padding(.vertical, 8)
        .alert(
            pendingCancellation.map { "Cancel \($0.title)?" } ?? "Cancel this delivery?",
            isPresented: isConfirmingCancellation,
            presenting: pendingCancellation
        ) { numbered in
            // The destructive button repeats which delivery it will cancel.
            // With several in progress, "Cancel Delivery" alone would be asking
            // the driver to remember which card they tapped.
            Button("Cancel \(numbered.title)", role: .destructive) { perform(.cancel(numbered)) }
                .accessibilityIdentifier("confirmCancelDeliveryButton")
            Button("Keep Delivering", role: .cancel) { pendingCancellation = nil }
        } message: { numbered in
            Text(
                """
                \(numbered.title) is kept in this shift's history as cancelled, with the times you \
                already recorded. Nothing is deleted, and your other deliveries are not affected.
                """
            )
        }
        .alert(
            "Delivery Not Updated",
            isPresented: isShowingLifecycleError,
            presenting: lifecycleError
        ) { _ in
            Button("OK", role: .cancel) { lifecycleError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The delivery could not be updated.")
        }
        // Raised only by a delivery that carried an expectation, and only after
        // the delivered event is already in the store. A driver who records no
        // expected amounts never meets it.
        .sheet(item: $pendingEarningsConfirmation) { pending in
            DeliveryEarningsConfirmation(numbered: pending.numbered, expected: pending.expected)
        }
    }

    /// How many deliveries are being worked, and what the shift has recorded so
    /// far. Both are glanceable and neither is a number that moves.
    @ViewBuilder
    private var status: some View {
        let summary = shift.deliverySummary

        VStack(alignment: .leading, spacing: 4) {
            // A symbol and a phrase, never colour alone: the state has to be
            // readable in bright sun and to someone who does not see the tint.
            Label(summary.inProgressStatement, systemImage: activeDeliveries.isEmpty ? "pause.circle" : "shippingbox.fill")
                .font(.headline)

            if !summary.isEmpty {
                Text(summary.statement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([summary.inProgressStatement, summary.spokenStatement].joined(separator: ". "))
        .accessibilityIdentifier("deliveryStatus")
    }

    /// Starting another delivery, available whenever the shift is running.
    ///
    /// Prominent only when nothing is in progress. While deliveries are running,
    /// the buttons the driver reaches for are the ones advancing them, and two
    /// competing prominent controls beside a kerb is how the wrong one gets
    /// tapped.
    @ViewBuilder
    private var startControl: some View {
        let button = Button { perform(.start) } label: {
            Text(DeliveryAction.start.title)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityLabel(DeliveryAction.start.spokenLabel)
        .accessibilityIdentifier("startDeliveryButton")

        if activeDeliveries.isEmpty {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    // MARK: Actions

    /// What a control asked for, and which delivery it asked for it on.
    ///
    /// Cancelling is kept apart from the ordered lifecycle steps because it is
    /// not one of them: it is available from every active state rather than
    /// following one.
    private enum Operation {
        case start
        case advance(NumberedDelivery)
        case cancel(NumberedDelivery)
    }

    private func perform(_ operation: Operation) {
        let service = DeliveryService(context: modelContext)
        do {
            switch operation {
            case .start:
                try service.startDelivery()
            case let .advance(numbered):
                // The step is read from the delivery's own state and applied to
                // that same delivery, so a card can only ever advance itself.
                switch numbered.delivery.state.nextAction {
                case .arriveAtPickup: try service.markArrivedAtPickup(numbered.delivery)
                case .pickUp: try service.markPickedUp(numbered.delivery)
                case .complete:
                    // Read before the write, because the card disappears with
                    // it. Nothing is offered unless an expectation is the only
                    // amount this delivery carries: one that already has a
                    // recorded gross has been answered, and asking again would
                    // invite overwriting it by reflex.
                    let expected = numbered.delivery.hasUnconfirmedExpectedEarnings
                        ? numbered.delivery.expectedEarnings
                        : nil
                    try service.markDelivered(numbered.delivery)
                    // Only after the transition actually succeeded. A refused
                    // write leaves a delivery still in progress, and offering to
                    // record what it paid would be the screen disagreeing with
                    // the store about whether it is over.
                    if let expected {
                        pendingEarningsConfirmation = PendingEarningsConfirmation(
                            numbered: numbered,
                            expected: expected
                        )
                    }
                case .start, nil: break
                }
            case let .cancel(numbered):
                pendingCancellation = nil
                try service.cancelDelivery(numbered.delivery)
            }
        } catch let error as DeliveryLifecycleError {
            lifecycleError = error
        } catch {
            lifecycleError = .storeUnavailable(underlying: error)
        }

        // After every outcome, refused or not. Reconciling reads the store, so a
        // refusal costs one pass that finds nothing changed, and the alternative
        // — reconciling only on success — would be this screen deciding what the
        // store now holds.
        liveActivity.reconcile()
    }

    /// A delivery that has just been recorded as delivered, together with the
    /// amount it was expected to pay.
    ///
    /// The expectation is carried rather than looked up so the sheet is
    /// unpresentable without one: there is no state in which the confirmation
    /// appears offering nothing, and no path by which it could show a figure
    /// read back out of the recorded gross column.
    private struct PendingEarningsConfirmation: Identifiable {
        let numbered: NumberedDelivery
        let expected: Money

        var id: UUID { numbered.id }
    }

    private var isConfirmingCancellation: Binding<Bool> {
        Binding(
            get: { pendingCancellation != nil },
            set: { isShowing in if !isShowing { pendingCancellation = nil } }
        )
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }
}

/// One delivery in progress: which one it is, what it is doing, and the single
/// step available next.
///
/// The card names itself in print and aloud. With two on screen, a control
/// identified only by its position is unusable without sight and easy to
/// mis-tap with it.
private struct ActiveDeliveryCard: View {
    let numbered: NumberedDelivery
    let advance: () -> Void
    let cancel: () -> Void

    @Environment(\.locale) private var locale

    /// Presented from the card's secondary pickup control. Sheet state rather
    /// than a navigation push, because naming a pickup is a short aside from the
    /// running shift rather than somewhere to be.
    @State private var isEditingPickupPlace = false

    /// Presented from the card's secondary expected-pay control, for the same
    /// reason and in the same shape.
    @State private var isEditingExpectedEarnings = false

    private var delivery: Delivery { numbered.delivery }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(numbered.statusTitle, systemImage: delivery.state.symbolName)
                    .font(.headline)

                if let place = delivery.pickupPlace {
                    Label(place.displayName, systemImage: "bag")
                        .font(.subheadline)
                        .lineLimit(1)
                }

                LabeledContent("Accepted") {
                    Text(delivery.acceptedAt, format: .dateTime.hour().minute())
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                // Named "Expected pay" wherever it is printed, so it is never
                // one word away from the "Gross earnings" row a finished
                // delivery shows. Absent when none was recorded, like the
                // pickup place above it.
                if let expected = delivery.expectedEarnings {
                    LabeledContent("Expected pay") {
                        Text(expected.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenStatus)
            .accessibilityIdentifier("activeDeliveryStatus")

            // Secondary in every way that matters: small, plain, and above the
            // lifecycle button rather than in its place. Naming a pickup is
            // optional and this delivery advances identically without it.
            pickupPlaceControl

            // The same shape, for the same reason, and deliberately beside it
            // rather than anywhere nearer the lifecycle button: an amount is
            // optional, is skippable on every delivery, and the one moment it
            // is easy to enter is while the driver is standing still waiting
            // for a bag.
            expectedEarningsControl

            // Only the one step this delivery can actually take. A card for a
            // finished delivery does not exist, so the absence is defensive.
            if let action = delivery.state.nextAction {
                Button(action: advance) {
                    Text(action.title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(numbered.spokenLabel(for: action))
                .accessibilityIdentifier("deliveryActionButton")
            }

            Button("Cancel \(numbered.title)", role: .destructive, action: cancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(numbered.spokenCancelLabel)
                .accessibilityIdentifier("cancelDeliveryButton")
        }
        .sheet(isPresented: $isEditingPickupPlace) {
            PickupPlaceEditor(numbered: numbered)
        }
        .sheet(isPresented: $isEditingExpectedEarnings) {
            DeliveryExpectedEarningsEditor(numbered: numbered)
        }
    }

    /// The one control for what this delivery is expected to pay.
    ///
    /// A sheet rather than a field on the card, for exactly the reason
    /// ``pickupPlaceControl`` opens one: a keyboard that appears beside the
    /// lifecycle buttons is the interaction this project refuses to design. The
    /// sheet can be dismissed and ignored entirely, and the delivery advances
    /// identically with no amount on it.
    private var expectedEarningsControl: some View {
        Button {
            isEditingExpectedEarnings = true
        } label: {
            Label(
                numbered.expectedEarningsActionTitle(hasExpected: delivery.expectedEarnings != nil),
                systemImage: delivery.expectedEarnings == nil ? "plus.circle" : "pencil"
            )
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            numbered.spokenExpectedEarningsLabel(hasExpected: delivery.expectedEarnings != nil)
        )
        .accessibilityIdentifier("expectedEarningsButton")
    }

    /// The one control for pickup identity: add it, or change what is recorded.
    ///
    /// Deliberately not a text field on the card. A running shift is the one
    /// screen a driver may look at with the engine on, and a keyboard that
    /// appears beside the lifecycle buttons is exactly the interaction this
    /// project refuses to design. The sheet it opens can be answered in one tap
    /// from a recent place, or dismissed and ignored entirely.
    private var pickupPlaceControl: some View {
        Button {
            isEditingPickupPlace = true
        } label: {
            Label(
                numbered.pickupPlaceActionTitle(hasPlace: delivery.pickupPlace != nil),
                systemImage: delivery.pickupPlace == nil ? "plus.circle" : "pencil"
            )
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(numbered.spokenPickupPlaceLabel(hasPlace: delivery.pickupPlace != nil))
        .accessibilityIdentifier("pickupPlaceButton")
    }

    /// "Delivery 2, waiting at the pickup, from Nowhere Noodles, accepted at
    /// 5:12 PM" — the identity first, because that is what tells the listener
    /// which card they are on, and the place only when one was recorded.
    ///
    /// An expected amount is appended as its own **sentence** rather than as
    /// another comma-separated clause, because it is the one part of this label
    /// that has to say what it is not: a figure heard in a run-on list beside a
    /// time and a place is heard as this delivery's earnings.
    private var spokenStatus: String {
        let accepted = delivery.acceptedAt.formatted(date: .omitted, time: .shortened)
        var parts = [numbered.spokenStatus]
        if let place = delivery.pickupPlace {
            parts.append("from \(place.displayName)")
        }
        parts.append("accepted at \(accepted)")

        var spoken = parts.joined(separator: ", ")
        if let expected = delivery.expectedEarnings {
            spoken += ". \(numbered.spokenExpectedEarnings(expected.formatted(locale: locale)))"
        }
        return spoken
    }
}

#if DEBUG
#Preview("No delivery in progress") {
    PreviewSupport.rootView(container: PreviewSupport.populatedContainer())
}

#Preview("Two deliveries in progress") {
    PreviewSupport.rootView(container: PreviewSupport.activeDeliveryContainer())
}
#endif
