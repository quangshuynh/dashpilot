import SwiftData
import SwiftUI

/// Names, changes or removes the place one delivery was picked up from.
///
/// ## One field, and a shorter path than the field
///
/// The only thing asked for is a name. No address, no city, no phone number, no
/// store number, no category and no note: a pickup place exists so the driver
/// can recognise a recurring pickup later, and every extra field is more typing
/// at a kerb for something the app has no use for.
///
/// Above the field sit the places recently used, because the second time a
/// driver picks up from somewhere the honest interaction is **one tap, no
/// keyboard**. Tapping one records it and closes the sheet; the field is for a
/// place that is not there yet. Both are a single deliberate action, and both
/// are undoable — the place can be changed or removed afterwards.
///
/// ## Nothing here is required
///
/// This sheet is never in the way of the lifecycle. It is reached from a
/// secondary control on a delivery card or from a completed shift's history, and
/// a delivery with no pickup place is a complete, ordinary delivery.
///
/// ## Editing is a draft
///
/// The typed text is view state; the store is written once, when the driver taps
/// Save, Remove, or a recent place. Cancelling — or dismissing the sheet —
/// leaves what was recorded exactly as it was.
struct PickupPlaceEditor: View {
    let numbered: NumberedDelivery

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The draft. Seeded from the recorded place, and never read by anything but
    /// ``save()``.
    @State private var text = ""
    @State private var message: String?

    /// Read once when the sheet appears rather than in `body`, and held as
    /// values the list can render without re-querying on every keystroke.
    @State private var recentPlaces: [PickupPlace] = []

    @FocusState private var isNameFocused: Bool

    private var delivery: Delivery { numbered.delivery }

    private var recordedPlace: PickupPlace? { delivery.pickupPlace }

    var body: some View {
        NavigationStack {
            Form {
                if !offeredRecentPlaces.isEmpty {
                    recentSection
                }
                nameSection
                if recordedPlace != nil {
                    removeSection
                }
            }
            .navigationTitle(recordedPlace == nil ? "Add Pickup Place" : "Change Pickup Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelPickupPlaceButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("savePickupPlaceButton")
                }
            }
        }
        .onAppear {
            text = recordedPlace?.displayName ?? ""
            recentPlaces = (try? PickupPlaceService(context: modelContext).recentPlaces()) ?? []
        }
    }

    // MARK: Recent places

    /// The places worth offering: recently used, minus the one already recorded
    /// on this delivery, which would be a button that does nothing.
    private var offeredRecentPlaces: [PickupPlace] {
        recentPlaces.filter { $0.id != recordedPlace?.id }
    }

    private var recentSection: some View {
        Section {
            ForEach(offeredRecentPlaces) { place in
                Button {
                    use(place)
                } label: {
                    Label(place.displayName, systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The name alone would be read as a heading rather than as a
                // control that does something when tapped.
                .accessibilityLabel("Use \(place.displayName) as the pickup place for \(numbered.title)")
                .accessibilityIdentifier("recentPickupPlaceButton")
            }
        } header: {
            Text("Recent")
        } footer: {
            Text("Places you have picked up from recently, most recent first. Tapping one records it.")
        }
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            TextField("Pickup place name", text: $text)
                .focused($isNameFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("pickupPlaceNameField")
                .accessibilityLabel("Pickup place for \(numbered.title)")
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
                    .accessibilityIdentifier("pickupPlaceValidationMessage")
            }
        } header: {
            Text("Pickup Place")
        } footer: {
            Text(
                """
                The name you know this pickup by, kept on this device. DashPilot looks nothing up: \
                there is no address, no map and no connection to any delivery platform. A name that \
                matches one you have used before — in any capitalisation or spacing — records the \
                same place rather than a second one.
                """
            )
        }
    }

    // MARK: Removal

    private var removeSection: some View {
        Section {
            Button("Remove Pickup Place", role: .destructive, action: remove)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Remove pickup place from \(numbered.title)")
                .accessibilityIdentifier("removePickupPlaceButton")
        } footer: {
            Text(
                """
                Removes the place from this delivery only. The delivery and its recorded times are \
                kept, and the place stays available for your other deliveries.
                """
            )
        }
    }

    // MARK: Actions

    private func save() {
        perform { service in
            try service.assignPlace(named: text, to: delivery)
        }
    }

    private func use(_ place: PickupPlace) {
        perform { service in
            try service.assign(place, to: delivery)
        }
    }

    private func remove() {
        perform { service in
            try service.removePlace(from: delivery)
        }
    }

    /// Runs one store operation, closing the sheet on success and keeping it
    /// open with what the driver typed on failure.
    private func perform(_ operation: (PickupPlaceService) throws -> Void) {
        do {
            try operation(PickupPlaceService(context: modelContext))
            dismiss()
        } catch {
            // A name that could not be saved is not a reason to make the driver
            // type it again. Focus goes back to the field so the correction is
            // one tap closer.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That pickup place could not be saved."
            isNameFocused = true
        }
    }
}

#if DEBUG
#Preview("Add a pickup place") {
    PreviewSupport.pickupPlaceEditor(withRecordedPlace: false)
}

#Preview("Change a pickup place") {
    PreviewSupport.pickupPlaceEditor(withRecordedPlace: true)
}
#endif
