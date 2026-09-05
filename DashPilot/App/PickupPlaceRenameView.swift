import SwiftData
import SwiftUI

/// Corrects the spelling of one pickup place, everywhere it appears.
///
/// ## What a driver is doing here
///
/// Fixing a name they typed. `Nowhere Noodle` where they meant `Nowhere
/// Noodles`, a capitalisation they have since decided against, a word they
/// abbreviated at a kerb and now cannot read. The place itself is not in
/// question — its deliveries, its recorded waits and its place in the recent
/// list are all staying exactly where they are.
///
/// ## One field, and nothing written until Save
///
/// The typed text is view state. The store is written once, when Save is
/// tapped; nothing happens while the driver types, and cancelling or dismissing
/// leaves the recorded name exactly as it was. The same two rules as naming a
/// place apply, from the same ``PickupPlaceName`` — this screen re-implements no
/// part of the policy.
///
/// ## Colliding with a place that already exists
///
/// If the new spelling is one another place is already found by, the rename is
/// refused and the message says which place and what to do instead: **merge**.
/// The two are different intentions and this screen does not quietly perform the
/// other one — renaming corrects a name, merging destroys a place, and a driver
/// fixing a typo has not asked for the second.
struct PickupPlaceRenameView: View {
    let place: PickupPlace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The draft. Seeded from the recorded spelling, and read only by ``save()``.
    @State private var text = ""
    @State private var message: String?

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                nameSection
            }
            .navigationTitle("Rename Pickup Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelPickupPlaceRenameButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("savePickupPlaceRenameButton")
                }
            }
        }
        .onAppear { text = place.displayName }
    }

    private var nameSection: some View {
        Section {
            TextField("Pickup place name", text: $text)
                .focused($isNameFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("pickupPlaceRenameField")
                // Every control on this screen names the place it acts on, for
                // the reason a delivery's controls name their delivery: reached
                // from a sheet, "Pickup place name" identifies its target by
                // nothing but what the driver remembers tapping.
                .accessibilityLabel("New name for pickup place, \(place.displayName)")
                .onChange(of: text) { _, _ in
                    // The message describes the text that produced it, so it
                    // goes as soon as the text does.
                    message = nil
                }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pickupPlaceRenameMessage")
            }
        } header: {
            Text("Name")
        } footer: {
            Text(Self.explanation)
        }
    }

    /// What a rename changes, and — said outright, because it is the thing a
    /// driver would otherwise be nervous about — what it does not.
    private static let explanation = """
        The new spelling replaces the old one everywhere this place appears, and a delivery you \
        record under it later joins this same place. Nothing else changes: every delivery already \
        recorded here stays here, no recorded time is altered, and the pickup waits at this place \
        are the same waits afterwards. If the name you type is one another pickup place already \
        uses, DashPilot says so rather than putting the two together — combining them is Merge, and \
        it is a separate, deliberate step.
        """

    private func save() {
        do {
            try PickupPlaceService(context: modelContext).rename(place, to: text)
            dismiss()
        } catch {
            // A name that was refused is not a reason to make the driver type it
            // again. The draft stays, and focus returns to the field.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That pickup place could not be renamed."
            isNameFocused = true
        }
    }
}

#if DEBUG
#Preview("Rename a pickup place") {
    PreviewSupport.pickupPlaceRename()
}
#endif
