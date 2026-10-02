import SwiftData
import SwiftUI

/// Recording an order the driver has just accepted, pinned to the bottom of the
/// running shift's screen.
///
/// ## Why it stays put
///
/// A driver may open DashPilot for nothing but this, with an offer accepted a
/// moment ago, and may already be scrolled down to a card's step or the shift's
/// controls. So the control does not live in the list: it is a bar in the
/// screen's bottom safe area, reachable from wherever the list has been
/// scrolled to. Being in the safe area rather than drawn over the list is what
/// lets the list's last row scroll fully above it, so nothing is left hidden
/// underneath.
///
/// ## Its two controls, and which one leads
///
/// One delivery is the ordinary offer, so it is the wide control and an offer
/// of several is the narrow one beside it. With nothing in progress, `Start
/// Delivery` is the screen's prominent control. With deliveries in progress the
/// prominent controls are their next steps, so it says `Add Delivery` and is
/// bordered: never a second prominent control beside a step. While the vehicle
/// is recorded as parked, `Resume Driving` is the prominent control, so it is
/// bordered there too.
///
/// Not drawn while the shift is paused: a delivery cannot be started then, and
/// the deliveries section already says why.
struct DeliveryEntryBar: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(ShiftLiveActivityService.self) private var liveActivity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Every unfinished delivery, so the bar follows a delivery starting or
    /// finishing anywhere, including from the Lock Screen.
    @Query(filter: #Predicate<Delivery> { $0.deliveredAt == nil && $0.cancelledAt == nil })
    private var unfinishedDeliveries: [Delivery]

    @State private var isStartingGroupedOffer = false
    @State private var lifecycleError: DeliveryLifecycleError?

    private var hasDeliveryInProgress: Bool {
        unfinishedDeliveries.contains { $0.shift?.id == shift.id }
    }

    private var isProminent: Bool { !hasDeliveryInProgress && !shift.isRouteSuspended }

    var body: some View {
        HStack(alignment: .center, spacing: DashSpacing.md) {
            startButton
            severalButton
        }
        .padding(.horizontal, DashSpacing.xl)
        .padding(.vertical, DashSpacing.md)
        // Clamped at the first accessibility size, as the Live Activity card
        // is at its own limit: past it `Start Delivery` broke inside its word
        // in the width the row leaves it, and stacking the two controls would
        // take a third of the screen on every scroll position.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Opaque, with a rule above it: a row scrolling beneath the bar is
        // hidden by it rather than read through it, and the list is inset by
        // the bar's height so every row can still be scrolled clear of it.
        .background {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: $isStartingGroupedOffer) {
            NewOfferSheet { count, sharing in
                perform { _ = try DeliveryService(context: modelContext).startOffer(deliveryCount: count, sharing: sharing) }
            }
        }
        .alert(
            "Delivery Not Updated",
            isPresented: isShowingLifecycleError,
            presenting: lifecycleError
        ) { _ in
            Button("OK", role: .cancel) { lifecycleError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The delivery could not be started.")
        }
    }

    /// One delivery: the wide control, worded for whether this is the first
    /// order in hand or one more.
    @ViewBuilder
    private var startButton: some View {
        let button = Button {
            perform { _ = try DeliveryService(context: modelContext).startDelivery() }
        } label: {
            Text(hasDeliveryInProgress ? "Add Delivery" : DeliveryAction.start.title)
                .dashFont(.control)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityLabel(hasDeliveryInProgress ? "Add another delivery" : DeliveryAction.start.spokenLabel)
        .accessibilityIdentifier("startDeliveryButton")

        if isProminent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// An offer of several: narrow, bordered, and never prominent. At
    /// accessibility sizes it keeps its glyph and gives up its word, so the bar
    /// stays one row and the wide control keeps room for its title.
    private var severalButton: some View {
        Button {
            isStartingGroupedOffer = true
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "square.stack.3d.up")
                    .dashFont(.control)
                    .frame(minWidth: 44)
            } else {
                Label("Several", systemImage: "square.stack.3d.up")
                    .labelStyle(DashCompactLabelStyle())
                    .dashFont(.control)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
        .accessibilityLabel("Start an offer containing several deliveries")
        .accessibilityIdentifier("startOfferButton")
    }

    /// A refused start is said in an alert, the way the panel above says every
    /// other refused lifecycle step. The Lock Screen card is reconciled either
    /// way, because it reads the store rather than this tap.
    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch let error as DeliveryLifecycleError {
            lifecycleError = error
        } catch {
            lifecycleError = .storeUnavailable(underlying: error)
        }
        liveActivity.reconcile()
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }
}
