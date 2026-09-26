import SwiftData
import SwiftUI

/// Creates or corrects one vehicle profile.
///
/// Editing is a **draft**: both fields are view state and the store is written
/// once, when the driver taps Save or Delete. Cancelling leaves the profile
/// exactly as it was, and nothing is written per keystroke.
///
/// **Both fields move together.** The model checks the name and the fuel economy
/// before it writes either, so an edit that fixes the name and mistypes the
/// economy leaves the profile with the pair it already had.
struct VehicleProfileEditor: View {
    /// The profile being corrected, or `nil` when one is being created.
    let vehicle: VehicleProfile?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var name = ""
    @State private var milesPerGallonText = ""
    @State private var message: String?
    @State private var isConfirmingDeletion = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case milesPerGallon
    }

    private var isEditing: Bool { vehicle != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Each label above its field rather than beside it, so a long
                    // vehicle name and the largest text sizes get the whole
                    // width of the row instead of the half a trailing field has.
                    labeledField("Name") {
                        TextField("2020 Honda Civic", text: $name)
                            .dashFont(.body)
                            .focused($focusedField, equals: .name)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .onSubmit { focusedField = .milesPerGallon }
                            .accessibilityIdentifier("vehicleNameField")
                            .accessibilityLabel("Vehicle name")
                            .onChange(of: name) { _, _ in message = nil }
                    }

                    labeledField("Miles per gallon") {
                        TextField(milesPerGallonPlaceholder, text: $milesPerGallonText)
                            .dashFont(.body)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .milesPerGallon)
                            .monospacedDigit()
                            .accessibilityIdentifier("vehicleMilesPerGallonField")
                            .accessibilityLabel("Miles per gallon")
                            .onChange(of: milesPerGallonText) { _, _ in message = nil }
                    }

                    if let message {
                        DashValidationMessage(message: message, identifier: "vehicleValidationMessage")
                    }
                } header: {
                    Text("Vehicle")
                } footer: {
                    Text(
                        """
                        The name is yours to recognise, and the miles per gallon is what DashPilot \
                        divides a shift's recorded miles by. Both are kept on this device. Shifts \
                        you have already worked keep the figures they recorded, so changing these \
                        changes only what your next shift records.
                        """
                    )
                }

                if let vehicle {
                    Section {
                        Button("Delete Vehicle", role: .destructive) { isConfirmingDeletion = true }
                            .dashFont(.body)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("deleteVehicleButton")
                    } footer: {
                        Text(
                            """
                            Removes \(vehicle.name) from this list. Every shift you worked in it keeps its own \
                            miles per gallon, its estimated fuel and its name, so nothing you have \
                            recorded changes.
                            """
                        )
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Vehicle" : "Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelVehicleButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveVehicleButton")
                }
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Vehicle", role: .destructive, action: delete)
                    .accessibilityIdentifier("confirmDeleteVehicleButton")
                Button("Keep Vehicle", role: .cancel) {}
            } message: {
                Text("Shifts you worked in it are not changed. They keep the miles per gallon they recorded.")
            }
        }
        .onAppear(perform: seed)
    }

    /// A field under its own label, in the one shape every field on this
    /// sheet takes.
    private func labeledField(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            Text(title)
                .dashFont(.metricLabel)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            field()
        }
        .padding(.vertical, DashSpacing.xs)
    }

    private var deletionTitle: String {
        guard let vehicle else { return "Delete this vehicle?" }
        return "Delete \(vehicle.name)?"
    }

    private var milesPerGallonPlaceholder: String { MilesPerGallonInput(locale: locale).placeholder }

    private func seed() {
        if let vehicle {
            name = vehicle.name
            milesPerGallonText = MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)
            focusedField = .name
        } else {
            focusedField = .name
        }
    }

    /// Reads both fields, then writes once.
    ///
    /// Unlike the shift's fuel editor, neither field here is optional: a profile
    /// with no name cannot be picked out of a list, and one with no fuel economy
    /// is a row with nothing to contribute to a shift that starts under it.
    private func save() {
        let milesPerGallon: Decimal
        do {
            milesPerGallon = try MilesPerGallonInput(locale: locale).milesPerGallon(from: milesPerGallonText)
        } catch {
            message = error.errorDescription ?? "That fuel economy could not be saved."
            focusedField = .milesPerGallon
            return
        }

        let service = SettingsService(context: modelContext)
        do {
            if let vehicle {
                try service.updateVehicle(vehicle, name: name, milesPerGallon: milesPerGallon)
            } else {
                try service.addVehicle(name: name, milesPerGallon: milesPerGallon)
            }
            dismiss()
        } catch {
            // The sheet stays open with what the driver typed. A name that could
            // not be saved is not a reason to make them type it again.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That vehicle could not be saved."
            if case SettingsError.invalidVehicle(.invalidName) = error { focusedField = .name }
        }
    }

    private func delete() {
        guard let vehicle else { return }
        do {
            try SettingsService(context: modelContext).deleteVehicle(vehicle)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That vehicle could not be deleted."
        }
    }
}

/// Records what a gallon of fuel currently costs.
///
/// Its own sheet rather than a field on the settings list, for the reason every
/// other amount in the app gets one: a money field needs a keyboard, a parse, a
/// refusal sentence and a Cancel that leaves the stored figure alone, and a row
/// that writes per keystroke has none of those.
struct CurrentGasPriceEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var gasPriceText = ""
    @State private var message: String?
    @State private var hasRecordedPrice = false

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: DashSpacing.sm) {
                        Text("Price per gallon")
                            .dashFont(.metricLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField(placeholder, text: $gasPriceText)
                            .dashFont(.body)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .monospacedDigit()
                            .accessibilityIdentifier("currentGasPriceField")
                            .accessibilityLabel("Gas price per gallon")
                            .onChange(of: gasPriceText) { _, _ in message = nil }
                    }
                    .padding(.vertical, DashSpacing.xs)

                    if let message {
                        DashValidationMessage(message: message, identifier: "currentGasPriceValidationMessage")
                    }
                } header: {
                    Text("Current Gas Price")
                } footer: {
                    Text(
                        """
                        What a gallon costs you now, kept so you type it once. It is recorded on \
                        each shift when that shift starts, so changing it here changes what your \
                        next shift records and never a shift you have already worked. DashPilot \
                        looks up no prices and uses nothing about where you are.
                        """
                    )
                }

                if hasRecordedPrice {
                    Section {
                        Button("Remove Gas Price", role: .destructive, action: remove)
                            .dashFont(.body)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeCurrentGasPriceButton")
                    } footer: {
                        Text(
                            """
                            Leaves DashPilot with no current price, so a shift that starts records \
                            none. That is not the same as recording that fuel costs nothing.
                            """
                        )
                    }
                }
            }
            .navigationTitle("Gas Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelCurrentGasPriceButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveCurrentGasPriceButton")
                }
            }
        }
        .onAppear(perform: seed)
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func seed() {
        let recorded = (try? SettingsService(context: modelContext).existingSettings())??.gasPricePerGallon
        hasRecordedPrice = recorded != nil
        if let recorded {
            gasPriceText = MoneyInput(locale: locale).text(for: recorded)
        }
        isFocused = true
    }

    /// An empty field is **not** a zero. It means the driver has not said what a
    /// gallon costs, which is what Remove records; saving an empty field is
    /// refused rather than read as free fuel.
    private func save() {
        let price: Money
        do {
            price = try MoneyInput(locale: locale).amount(from: gasPriceText)
        } catch {
            // Said in the terms of what was being typed: a driver entering a
            // price at a pump is not recording gross earnings.
            message = error.message(for: .gasPricePerGallon)
            return
        }

        do {
            try SettingsService(context: modelContext).setGasPricePerGallon(price)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That price could not be saved."
        }
    }

    private func remove() {
        do {
            try SettingsService(context: modelContext).clearGasPricePerGallon()
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That price could not be removed."
        }
    }
}

#if DEBUG
#Preview("Add a vehicle") {
    PreviewSupport.vehicleProfileEditor(existing: false)
}

#Preview("Edit a vehicle") {
    PreviewSupport.vehicleProfileEditor(existing: true)
}
#endif
