import SwiftData
import SwiftUI

/// Correcting which of a shift's deliveries the driver recorded as having
/// arrived together.
///
/// ## Why it is a screen of its own
///
/// Grouping is recorded at a kerb and is occasionally wrong: two taps on
/// `Start Delivery` for one stacked offer, or an offer of three that was really
/// two and a separate one. Correcting it is a review action, so it is reached
/// from one small control rather than from a button on every card. The running
/// shift's cards stay what they are, each with one prominent lifecycle button
/// and nothing competing with it.
///
/// ## What it shows, and what it refuses to show
///
/// The shift's offers in the order they were accepted, each with the deliveries
/// under it named exactly as they are named everywhere else. No identifier
/// appears anywhere: `Offer 2` and `Delivery 3` are the only names DashPilot
/// has for these rows, and they are the names on the cards the driver is
/// correcting.
///
/// Each correction is confirmed by a sentence that says which deliveries move,
/// where they move to, and whether an offer is removed by it. None of it is
/// undoable, and all of it is about work that really happened.
///
/// ## Nothing is suggested
///
/// The destinations are the shift's other offers, in acceptance order, minus the
/// ones that could not truthfully have contained the delivery. There is no
/// "did you mean", no candidate highlighted by how close two timestamps are and
/// no ordering that hints at an answer: DashPilot does not know which two of a
/// driver's offers were really one.
struct OfferCorrectionView: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The destination screen being chosen on, if any.
    ///
    /// Held here so an applied correction can return to the list. The row a
    /// pushed screen was describing may not exist afterwards, and a screen left
    /// showing a destination for an offer that has just been removed is a screen
    /// describing nothing.
    @State private var path: [CorrectionTarget] = []

    /// The correction awaiting confirmation. Nothing is written until it is
    /// confirmed, and dismissing this sheet writes nothing at all.
    @State private var pending: PendingCorrection?

    @State private var message: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if offers.isEmpty {
                    emptySection
                } else {
                    ForEach(offers) { offer in
                        offerSection(offer)
                    }
                    explanationSection
                }
                if let message {
                    failureSection(message)
                }
            }
            .navigationTitle("Correct Grouping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("closeOfferCorrectionButton")
                }
            }
            .navigationDestination(for: CorrectionTarget.self) { target in
                destination(for: target)
            }
        }
        // An alert rather than a confirmation dialog, for the reason deleting a
        // shift uses one: a dialog is a popover in some layouts, where iOS drops
        // the explicit Cancel button, and a correction that removes an offer
        // must always show both choices.
        .alert(
            pending.map { Text($0.plan.title) } ?? Text("Correct Grouping"),
            isPresented: isConfirming,
            presenting: pending
        ) { correction in
            Button(correction.plan.confirmTitle) { apply(correction) }
                .accessibilityIdentifier("confirmOfferCorrectionButton")
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { correction in
            Text(correction.plan.detail)
        }
    }

    // MARK: The shift's grouping

    private var offers: [NumberedOffer] { shift.numberedOffers }

    /// One offer, its deliveries, and the two corrections that act on the offer
    /// as a whole.
    ///
    /// The heading says how many deliveries arrived together, in the same words
    /// the running shift's own heading uses, so a driver who opened this from
    /// that screen is reading the same sentence about the same group.
    @ViewBuilder
    private func offerSection(_ offer: NumberedOffer) -> some View {
        Section {
            ForEach(offer.deliveries) { numbered in
                NavigationLink(value: CorrectionTarget.delivery(numbered.id)) {
                    deliveryRow(numbered)
                }
                .accessibilityLabel("Move \(numbered.title) out of \(offer.title)")
                .accessibilityIdentifier("offerCorrectionDeliveryButton")
            }

            // An offer the app cannot produce, which a correction screen must
            // still read without falling over. It is shown rather than hidden:
            // a row a driver can see is a row they can merge something into.
            if offer.deliveryCount == 0 {
                Text("Nothing is recorded under this offer. Combining it into another offer removes it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("offerCorrectionEmptyOffer")
            }

            if offer.isGrouped {
                Button("Separate Into Single Deliveries") {
                    pending = PendingCorrection(operation: .separate(offer.id), plan: .separate(offer))
                }
                .accessibilityLabel("Separate \(offer.title) into one offer per delivery")
                .accessibilityIdentifier("offerCorrectionSeparateButton")
            }

            if !mergeDestinations(for: offer).isEmpty {
                NavigationLink(value: CorrectionTarget.offer(offer.id)) {
                    Text("Combine With Another Offer")
                }
                .accessibilityLabel("Combine \(offer.title) into another offer")
                .accessibilityIdentifier("offerCorrectionMergeButton")
            }
        } header: {
            Text(offerHeading(offer))
                .accessibilityLabel(offer.spokenMembershipStatement)
                .accessibilityIdentifier("offerCorrectionOfferHeader")
        }
    }

    /// `Offer 1 · 2 deliveries accepted together`, or `Offer 2 · 1 delivery`.
    ///
    /// Said on every offer here, unlike the running shift's heading, which
    /// states it only for a group. This screen is where a driver decides which
    /// offer a delivery belongs in, and an offer of one is a fact they are
    /// choosing between rather than the invisible ordinary case. It is
    /// ``NumberedOffer/membershipStatement`` rather than the grouped one for the
    /// same reason: an offer of one did not arrive together with anything.
    private func offerHeading(_ offer: NumberedOffer) -> String {
        "\(offer.title) · \(offer.membershipStatement)"
    }

    private func deliveryRow(_ numbered: NumberedDelivery) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(numbered.statusTitle)
            if let place = numbered.delivery.pickupPlace {
                Text(place.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What a correction does and does not touch, before the driver makes one.
    private var explanationSection: some View {
        Section {
            Text(
                """
                Correcting grouping only changes which deliveries you recorded as accepted together. \
                \(OfferCorrectionPlan.unchangedStatement) A delivery keeps every step you recorded \
                for it, whether or not it has finished, and stays in this shift. An offer left with \
                no deliveries is removed. Offers are numbered by when you accepted them, so the \
                numbers may change after a correction.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("offerCorrectionExplanation")
        }
    }

    /// A shift with no offers at all, which is a shift with no deliveries.
    private var emptySection: some View {
        Section {
            Text("No deliveries recorded in this shift")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("offerCorrectionUnavailable")
        } footer: {
            Text("Grouping describes which deliveries you accepted together, so there is nothing to correct yet.")
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offerCorrectionMessage")
        }
    }

    // MARK: Destinations

    /// Which correction a pushed screen is choosing a destination for.
    ///
    /// Identities rather than models, because a navigation value outlives the
    /// row that produced it and a `PersistentModel` held across a store change
    /// is exactly the stale reference the services refuse. They are resolved
    /// back to the shift's own numbered rows on the way in, and never shown.
    private enum CorrectionTarget: Hashable {
        case delivery(UUID)
        case offer(UUID)
    }

    @ViewBuilder
    private func destination(for target: CorrectionTarget) -> some View {
        switch target {
        case let .delivery(id):
            if let numbered = offers.flatMap(\.deliveries).first(where: { $0.id == id }) {
                deliveryDestinations(numbered)
            }
        case let .offer(id):
            if let offer = offers.first(where: { $0.id == id }) {
                offerDestinations(offer)
            }
        }
    }

    /// Where one delivery can go: another offer of this shift, or one of its
    /// own.
    ///
    /// The two are separate sections because they are different corrections.
    /// Moving says this delivery arrived with those; splitting says it arrived
    /// on its own, and records a new acceptance from the delivery's own
    /// timestamp rather than from anything typed.
    private func deliveryDestinations(_ numbered: NumberedDelivery) -> some View {
        let source = offer(containing: numbered)
        let destinations = moveDestinations(for: numbered)

        return List {
            if destinations.isEmpty {
                Section {
                    Text("No other offer this delivery could have arrived in")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("offerCorrectionNoDestinations")
                }
            } else {
                Section {
                    ForEach(destinations) { destination in
                        Button(offerHeading(destination)) {
                            pending = PendingCorrection(
                                operation: .move(numbered.id, into: destination.id),
                                plan: .move(numbered, from: source, to: destination)
                            )
                        }
                        .accessibilityLabel("Move \(numbered.title) to \(destination.title)")
                        .accessibilityIdentifier("offerCorrectionDestinationButton")
                    }
                } header: {
                    Text("Accepted together with")
                } footer: {
                    Text(
                        """
                        Choose the offer you accepted \(numbered.title) in. Offers accepted after \
                        this delivery was are not listed: an offer cannot contain work you accepted \
                        before it.
                        """
                    )
                }
            }

            if source == nil || source?.isGrouped == true {
                Section {
                    Button("New Offer of Its Own") {
                        pending = PendingCorrection(
                            operation: .split(numbered.id),
                            plan: .split(numbered, from: source)
                        )
                    }
                    .accessibilityLabel("Put \(numbered.title) in a new offer of its own")
                    .accessibilityIdentifier("offerCorrectionSplitButton")
                } header: {
                    Text("Accepted on its own")
                } footer: {
                    Text(
                        """
                        Records \(numbered.title) as an offer of one, accepted at the time already \
                        recorded for it. Nothing is asked for and nothing is guessed.
                        """
                    )
                }
            }
        }
        .navigationTitle("Move \(numbered.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Which offer this one's deliveries move to.
    ///
    /// The direction is in every label: this offer is the one that goes, and the
    /// one tapped is the one that stays. A combination in the wrong direction
    /// leaves the driver reading their shift under the offer they were trying to
    /// get rid of.
    private func offerDestinations(_ offer: NumberedOffer) -> some View {
        List {
            Section {
                ForEach(mergeDestinations(for: offer)) { destination in
                    Button(offerHeading(destination)) {
                        pending = PendingCorrection(
                            operation: .merge(offer.id, into: destination.id),
                            plan: .merge(offer, into: destination)
                        )
                    }
                    .accessibilityLabel("Combine \(offer.title) into \(destination.title)")
                    .accessibilityIdentifier("offerCorrectionDestinationButton")
                }
            } header: {
                Text("Keep this offer")
            } footer: {
                Text(
                    """
                    Every delivery in \(offer.title) moves to the offer you choose, and \
                    \(offer.title) is then removed. The offer you choose keeps its own acceptance \
                    time. Offers accepted after \(offer.title)'s deliveries were are not listed.
                    """
                )
            }
        }
        .navigationTitle("Combine \(offer.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moveDestinations(for numbered: NumberedDelivery) -> [NumberedOffer] {
        let allowed = Set(
            OfferCorrectionService(context: modelContext)
                .moveDestinations(for: numbered.delivery)
                .map(\.id)
        )
        return offers.filter { allowed.contains($0.id) }
    }

    private func mergeDestinations(for offer: NumberedOffer) -> [NumberedOffer] {
        let allowed = Set(
            OfferCorrectionService(context: modelContext)
                .mergeDestinations(for: offer.offer)
                .map(\.id)
        )
        return offers.filter { allowed.contains($0.id) }
    }

    private func offer(containing numbered: NumberedDelivery) -> NumberedOffer? {
        offers.first { $0.deliveries.contains { $0.id == numbered.id } }
    }

    // MARK: Applying

    /// A correction the driver has chosen and not yet confirmed.
    ///
    /// It carries identities and the sentences the alert shows, so the alert can
    /// describe the correction after the row that raised it has gone.
    private struct PendingCorrection: Identifiable {
        /// Each case carries **everything** the correction acts on, so a target
        /// and an operation that do not belong together cannot be built. The
        /// alternative, a target beside an operation, needs an unreachable
        /// branch that has to invent a refusal sentence for a state nothing can
        /// reach.
        enum Operation {
            case move(UUID, into: UUID)
            case split(UUID)
            case merge(UUID, into: UUID)
            case separate(UUID)
        }

        let operation: Operation
        let plan: OfferCorrectionPlan

        var id: String { plan.title }
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { isShowing in if !isShowing { pending = nil } }
        )
    }

    private func apply(_ correction: PendingCorrection) {
        pending = nil
        message = nil

        // Back to the list either way: a correction that succeeded leaves the
        // destination screen describing rows that may no longer exist, and one
        // that failed says why in the list's own message.
        path.removeAll()

        let service = OfferCorrectionService(context: modelContext)
        do {
            switch correction.operation {
            case let .move(id, destinationID):
                try service.move(try requireDelivery(id), into: try requireOffer(destinationID))
            case let .split(id):
                try service.split([try requireDelivery(id)])
            case let .merge(id, destinationID):
                try service.merge(try requireOffer(id), into: try requireOffer(destinationID))
            case let .separate(id):
                try service.separate(try requireOffer(id))
            }
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That grouping could not be corrected."
        }
    }

    /// The row this correction names, read back from the shift at the moment it
    /// is applied rather than captured when the alert was raised.
    private func requireDelivery(_ id: UUID) throws -> Delivery {
        guard let delivery = shift.deliveries.first(where: { $0.id == id }) else {
            throw OfferCorrectionError.deliveryNoLongerExists
        }
        return delivery
    }

    private func requireOffer(_ id: UUID) throws -> Offer {
        guard let offer = shift.offers.first(where: { $0.id == id }) else {
            throw OfferCorrectionError.offerNoLongerExists
        }
        return offer
    }
}

#if DEBUG
#Preview("Correcting a stacked offer") {
    PreviewSupport.rootView(container: PreviewSupport.stackedOfferContainer())
}
#endif
