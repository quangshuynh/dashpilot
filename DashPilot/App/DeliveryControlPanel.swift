import SwiftData
import SwiftUI

/// The running shift's delivery control: one primary action, and a way out.
///
/// This is the part of DashPilot most likely to be used beside a running
/// engine, so it is deliberately the smallest thing that can record a delivery.
/// There is one large primary button, and what it says is decided by
/// ``DeliveryState/nextAction`` rather than by this view — no form, no fields,
/// no picker, nothing to type, and no second decision to make while stopped at
/// a kerb.
///
/// Nothing here is detected. Every tap records an event the driver witnessed;
/// DashPilot does not know that an order was accepted, handed over or received.
///
/// The active delivery is read from the store with a query rather than held in
/// view state, which is what makes relaunch recovery ordinary: a delivery left
/// active when the app was terminated is still active on the next launch, and
/// the button that appears is the next step of the delivery that was already
/// running.
struct DeliveryControlPanel: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext

    /// Deliveries that are neither delivered nor cancelled, newest first.
    ///
    /// Not limited to one row on purpose: if the store ever holds more than one,
    /// the newest is shown and ``DeliveryService`` reports the anomaly rather
    /// than this screen hiding it.
    @Query(
        filter: #Predicate<Delivery> { $0.deliveredAt == nil && $0.cancelledAt == nil },
        sort: \Delivery.acceptedAt,
        order: .reverse
    )
    private var activeDeliveries: [Delivery]

    @State private var lifecycleError: DeliveryLifecycleError?
    @State private var isConfirmingCancellation = false

    private var activeDelivery: Delivery? { activeDeliveries.first }

    /// The state the controls are built from, or `nil` when nothing is running.
    private var state: DeliveryState? { activeDelivery?.state }

    /// The one action offered. Starting a delivery when none is running;
    /// otherwise whatever the current state's next step is.
    private var action: DeliveryAction { state?.nextAction ?? .start }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            status

            Button(action: perform) {
                Text(action.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(action.spokenLabel)
            .accessibilityIdentifier("deliveryLifecycleButton")

            if activeDelivery != nil {
                Button("Cancel Delivery", role: .destructive) {
                    isConfirmingCancellation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Cancel this delivery")
                .accessibilityIdentifier("cancelDeliveryButton")
            }
        }
        .padding(.vertical, 8)
        .alert("Cancel this delivery?", isPresented: $isConfirmingCancellation) {
            Button("Cancel Delivery", role: .destructive) { perform(.cancel) }
                .accessibilityIdentifier("confirmCancelDeliveryButton")
            Button("Keep Delivering", role: .cancel) {}
        } message: {
            Text(
                """
                The delivery is kept in this shift's history as cancelled, with the times you \
                already recorded. Nothing is deleted.
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
    }

    /// One line: what the delivery is doing, and what the shift has recorded so
    /// far. Both are glanceable and neither is a number that moves.
    @ViewBuilder
    private var status: some View {
        let summary = shift.deliverySummary

        VStack(alignment: .leading, spacing: 4) {
            if let state {
                // A symbol and a phrase, never colour alone: the state has to be
                // readable in bright sun and to someone who does not see the tint.
                Label(state.statusDescription, systemImage: state.symbolName)
                    .font(.headline)
            } else {
                Label("No delivery in progress", systemImage: "pause.circle")
                    .font(.headline)
            }

            if !summary.isEmpty {
                Text(summary.statement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [state?.statusDescription ?? "No delivery in progress", summary.spokenStatement]
                .joined(separator: ". ")
        )
        .accessibilityIdentifier("deliveryStatus")
    }

    // MARK: Actions

    /// What the delivery service call for an action is. Kept as a small local
    /// enum rather than folded into ``DeliveryAction`` because cancelling is not
    /// one of the ordered lifecycle steps a state offers next.
    private enum Operation {
        case lifecycle(DeliveryAction)
        case cancel
    }

    private func perform() {
        perform(.lifecycle(action))
    }

    private func perform(_ operation: Operation) {
        let service = DeliveryService(context: modelContext)
        do {
            switch operation {
            case .lifecycle(.start): try service.startDelivery()
            case .lifecycle(.arriveAtPickup): try service.markArrivedAtPickup()
            case .lifecycle(.pickUp): try service.markPickedUp()
            case .lifecycle(.complete): try service.markDelivered()
            case .cancel: try service.cancelActiveDelivery()
            }
        } catch let error as DeliveryLifecycleError {
            lifecycleError = error
        } catch {
            lifecycleError = .storeUnavailable(underlying: error)
        }
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }
}

#if DEBUG
#Preview("No delivery in progress") {
    PreviewSupport.rootView(container: PreviewSupport.populatedContainer())
}

#Preview("Delivery in progress") {
    PreviewSupport.rootView(container: PreviewSupport.activeDeliveryContainer())
}
#endif
