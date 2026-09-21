import SwiftData
import SwiftUI

/// The driver's reusable preferences: the vehicles they work in, which one they
/// are working in now, and what a gallon currently costs.
///
/// ## What this screen is, and the one sentence it has to get across
///
/// Everything here is a **default for the next shift**. Nothing on this screen
/// changes a shift the driver has already worked, and the footers say so in as
/// many words, because it is the one thing a driver could reasonably assume the
/// other way: typing a new gas price looks like correcting a figure, and it is
/// not.
///
/// The figures are copied onto a shift when it starts, and from that moment the
/// shift owns its copy. See ``FuelDefaults``.
///
/// ## Why it is a preferences surface rather than another delivery action
///
/// It is reached from a gear in the navigation bar, which is where a phone
/// keeps preferences, and it is deliberately not a row in the list a driver
/// opens the app to read: a setting is something they touch when they change
/// vehicle or notice the price has moved, which is a stopped-vehicle task and a
/// rare one. The bar also costs the History list no height, which every row
/// added to the main screen does.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// Oldest first: the order the driver added them, which does not move when
    /// one is renamed.
    @Query(sort: \VehicleProfile.createdAt, order: .forward)
    private var vehicles: [VehicleProfile]

    /// The settings row, if one exists yet. A driver who has never changed a
    /// setting has none, and this screen draws perfectly well without it.
    @Query private var settingsRows: [DriverSettings]

    @State private var editingVehicle: VehicleEditorSubject?
    @State private var isEditingGasPrice = false
    @State private var failure: String?

    private var settings: DriverSettings? { settingsRows.first }

    private var selectedVehicleID: UUID? { settings?.selectedVehicleID }

    private var gasPrice: Money? { settings?.gasPricePerGallon }

    var body: some View {
        List {
            Section {
                if vehicles.isEmpty {
                    Text("No vehicles yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("vehiclesEmptyState")
                } else {
                    ForEach(vehicles) { vehicle in
                        VehicleRow(
                            vehicle: vehicle,
                            isSelected: vehicle.id == selectedVehicleID,
                            locale: locale,
                            select: { select(vehicle) },
                            edit: { editingVehicle = .existing(vehicle) }
                        )
                    }
                }

                Button {
                    editingVehicle = .new
                } label: {
                    Label("Add Vehicle", systemImage: "plus")
                }
                .accessibilityLabel("Add a vehicle")
                .accessibilityIdentifier("addVehicleButton")
            } header: {
                Text("Vehicles")
            } footer: {
                Text(vehiclesFooter)
            }

            Section {
                Button {
                    isEditingGasPrice = true
                } label: {
                    LabeledContent("Current gas price") {
                        Text(gasPriceStatement)
                            .monospacedDigit()
                            .foregroundStyle(gasPrice == nil ? .secondary : .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current gas price")
                .accessibilityValue(spokenGasPrice)
                .accessibilityHint("Changes what your next shift records. Shifts you have already worked keep their own.")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("currentGasPriceRow")
            } header: {
                Text("Fuel")
            } footer: {
                Text(
                    """
                    What you last paid for a gallon, kept so you type it once. DashPilot looks up no \
                    prices, knows no stations and uses nothing about where you are. Changing it \
                    changes what your next shift records, and never a shift you have already worked.
                    """
                )
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingVehicle) { subject in
            VehicleProfileEditor(vehicle: subject.vehicle)
        }
        .sheet(isPresented: $isEditingGasPrice) {
            CurrentGasPriceEditor()
        }
        .alert(
            "Setting Not Changed",
            isPresented: isShowingFailure,
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) { failure = nil }
        } message: { message in
            Text(message)
        }
    }

    /// What the vehicles section means, in the state it is actually in.
    ///
    /// Three sentences at most, and the middle one is the load-bearing one: an
    /// edit or a delete here is not a correction to anything recorded.
    private var vehiclesFooter: String {
        let stability = """
            The selected vehicle's miles per gallon is recorded on each shift when it starts. \
            Editing or deleting a vehicle changes what your next shift records, and never a shift \
            you have already worked.
            """
        if vehicles.isEmpty {
            return """
                Add the vehicle you deliver in so its miles per gallon is typed once rather than on \
                every shift. \(stability)
                """
        }
        if selectedVehicleID == nil {
            return "Select the vehicle you are working in. \(stability)"
        }
        return stability
    }

    private var gasPriceStatement: String {
        guard let gasPrice else { return "Not set" }
        return "\(gasPrice.formatted(locale: locale)) / gallon"
    }

    private var spokenGasPrice: String {
        guard let gasPrice else { return "Not set" }
        return "\(gasPrice.formatted(locale: locale)) per gallon"
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { isShowing in if !isShowing { failure = nil } }
        )
    }

    /// Selects a vehicle, or clears the selection when the selected one is
    /// tapped again.
    ///
    /// Tapping the selected vehicle clearing it is deliberate: without that
    /// there is no way back to "no vehicle selected" short of deleting the
    /// profile, and a driver who has stopped using the app's estimates should
    /// not have to delete a record to say so.
    private func select(_ vehicle: VehicleProfile) {
        do {
            try SettingsService(context: modelContext)
                .selectVehicle(vehicle.id == selectedVehicleID ? nil : vehicle)
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? "That vehicle could not be selected."
        }
    }
}

/// One vehicle in the list: its name, its fuel economy, whether it is the one
/// new shifts are recorded under, and a way to correct it.
///
/// Two controls rather than one row that does both, because they answer
/// different questions and one of them is a write the driver may not have meant.
/// The row selects; the trailing control edits.
private struct VehicleRow: View {
    let vehicle: VehicleProfile
    let isSelected: Bool
    let locale: Locale
    let select: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack {
            Button(action: select) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // Space is reserved whether or not the mark is drawn, so
                    // the names do not shift sideways as the selection moves.
                    Image(systemName: "checkmark")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.name)
                        Text(economyStatement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                // The whole row, including the space between its lines: a plain
                // button is hit-testable only where its content draws.
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(
                isSelected
                    ? "Stops recording new shifts under this vehicle."
                    : "Records new shifts under this vehicle."
            )
            .accessibilityIdentifier("vehicleRow")

            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(vehicle.name)")
            .accessibilityIdentifier("editVehicleButton")
        }
    }

    private var economyStatement: String {
        "\(MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)) MPG"
    }

    /// The name, the figure with its unit spoken in full, and the selection.
    ///
    /// "MPG" is spelled out, because a metric has to say its unit to a listener
    /// who has no caption in view, and the selection is stated rather than left
    /// to a mark nobody can see.
    private var spokenLabel: String {
        let economy = MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)
        let selection = isSelected ? "Selected. " : ""
        return "\(selection)\(vehicle.name), \(economy) miles per gallon"
    }
}

/// Which vehicle a sheet is editing: an existing one, or one being created.
///
/// The same shape ``ExpenseListView`` uses, and for the same reason: `sheet(item:)`
/// needs one identifiable value covering both cases.
private enum VehicleEditorSubject: Identifiable {
    case new
    case existing(VehicleProfile)

    var id: String {
        switch self {
        case .new: "new"
        case let .existing(vehicle): vehicle.id.uuidString
        }
    }

    var vehicle: VehicleProfile? {
        switch self {
        case .new: nil
        case let .existing(vehicle): vehicle
        }
    }
}

#if DEBUG
#Preview("Settings with vehicles") {
    PreviewSupport.settingsView(withVehicles: true)
}

#Preview("Settings with nothing recorded") {
    PreviewSupport.settingsView(withVehicles: false)
}
#endif
