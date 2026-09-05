import SwiftData
import SwiftUI

/// Puts one pickup place's deliveries under another place, and removes the one
/// left empty.
///
/// ## Why this exists
///
/// A driver who typed `Nowhere Noodle` one night and `Nowhere Noodles` the next
/// has two places where they meant one, and their pickup waits are split across
/// both. Nothing detects that — DashPilot does no similarity matching of any
/// kind — so the correction is theirs to make, explicitly, on two places they
/// name themselves.
///
/// ## The direction is the whole screen
///
/// This place is the **source**; the one tapped is the **destination**. The
/// source's deliveries move to the destination and the source is then removed.
/// Every label says it in that order — the title, the row, the confirmation and
/// what VoiceOver reads — because a merge in the wrong direction leaves the
/// driver reading their history under a name they were trying to get rid of.
///
/// ## Nothing is suggested
///
/// The destinations are every other place in the catalogue, in alphabetical
/// order. There is no "did you mean", no similarity score, no highlighted
/// candidate and no ordering that hints at an answer: the app does not know
/// which two of a driver's places are the same one, and a list that pretends
/// otherwise would make the wrong merge the easy tap.
///
/// A new place cannot be created here. Merging into a name that does not exist
/// yet is a rename, and it is offered as one.
struct PickupPlaceMergeView: View {
    let source: PickupPlace

    /// Called once the store has accepted the merge, before this sheet closes.
    ///
    /// ``source`` no longer exists at that point, so the screen that presented
    /// this one — which is showing that place — has to stop reading it. Handing
    /// that back rather than deciding it here keeps this view responsible for
    /// one thing.
    let onMerged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Read once when the sheet appears, as values the list renders without
    /// re-querying.
    @State private var destinations: [PickupPlace] = []

    /// The destination awaiting confirmation. Nothing is written until it is
    /// confirmed.
    @State private var pendingDestination: PickupPlace?

    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if destinations.isEmpty {
                    noDestinationsSection
                } else {
                    destinationsSection
                }
                if let message {
                    failureSection(message)
                }
            }
            .navigationTitle("Merge Pickup Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelPickupPlaceMergeButton")
                }
            }
        }
        .onAppear {
            destinations = (try? PickupPlaceService(context: modelContext).mergeDestinations(for: source)) ?? []
        }
        // An alert rather than a confirmation dialog, for the reason deleting a
        // shift uses one: a dialog is a popover in some layouts, where iOS drops
        // the explicit Cancel button. A merge removes a place, so both choices
        // must always be on screen and labelled.
        .alert(
            Text(confirmationTitle),
            isPresented: isConfirming,
            presenting: pendingDestination
        ) { destination in
            Button("Merge", role: .destructive) { merge(into: destination) }
                .accessibilityIdentifier("confirmPickupPlaceMergeButton")
            Button("Cancel", role: .cancel) { pendingDestination = nil }
        } message: { destination in
            Text(Self.confirmationBody(source: source.displayName, destination: destination.displayName))
        }
    }

    // MARK: Destinations

    private var destinationsSection: some View {
        Section {
            ForEach(destinations) { destination in
                Button {
                    pendingDestination = destination
                } label: {
                    Label(destination.displayName, systemImage: "bag")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The direction, in full, in the label of the control that
                // performs it. "Nowhere Noodles" alone would be a name read out
                // with no indication of which way the deliveries move.
                .accessibilityLabel("Merge \(source.displayName) into \(destination.displayName)")
                .accessibilityIdentifier("pickupPlaceMergeDestinationButton")
            }
        } header: {
            Text("Keep this place")
        } footer: {
            Text(
                """
                Choose the place to keep. Every delivery recorded under \(source.displayName) moves \
                to it, and \(source.displayName) is then removed. The place you choose keeps its own \
                name and everything already recorded under it. Places are listed alphabetically; \
                DashPilot does not guess which two are the same.
                """
            )
        }
    }

    /// The one place in the catalogue has nothing to merge into.
    ///
    /// Said rather than shown as an empty list: a driver who taps Merge and sees
    /// nothing has been told the feature is broken.
    private var noDestinationsSection: some View {
        Section {
            Text("No other pickup place to merge into")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pickupPlaceMergeUnavailable")
        } footer: {
            Text(
                """
                Merging puts one pickup place's deliveries under another, so it needs a second place \
                to keep. \(source.displayName) is the only one recorded so far. To correct its \
                spelling instead, use Rename.
                """
            )
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pickupPlaceMergeMessage")
        }
    }

    // MARK: Confirmation

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { pendingDestination != nil },
            set: { isShowing in if !isShowing { pendingDestination = nil } }
        )
    }

    /// Names both places and the direction between them.
    ///
    /// Deliberately not `Combine places?`. A confirmation that does not say
    /// which name survives is a confirmation of nothing.
    private var confirmationTitle: String {
        guard let destination = pendingDestination else { return "Merge Pickup Place" }
        return "Merge \"\(source.displayName)\" into \"\(destination.displayName)\"?"
    }

    /// What actually happens, in the order it happens, without overstating it.
    ///
    /// The deliveries are said to **move**, never to be deleted: a merge removes
    /// a name, and every delivery, timestamp and recorded wait survives it under
    /// the other one.
    private static func confirmationBody(source: String, destination: String) -> String {
        """
        All deliveries recorded under \(source) will move to \(destination), keeping their recorded \
        times. \(source) will then be removed. This cannot be undone.
        """
    }

    private func merge(into destination: PickupPlace) {
        do {
            try PickupPlaceService(context: modelContext).merge(source, into: destination)
            pendingDestination = nil
            onMerged()
            dismiss()
        } catch {
            pendingDestination = nil
            message = (error as? any LocalizedError)?.errorDescription
                ?? "Those pickup places could not be merged."
        }
    }
}

#if DEBUG
#Preview("Choose a place to merge into") {
    PreviewSupport.pickupPlaceMerge()
}
#endif
