import SwiftData
import SwiftUI

/// Corrects the vehicle assumptions the **shift in progress** recorded when it
/// started.
///
/// ## The one case it is for
///
/// A driver with two vehicles starts a shift in the wrong one, or with a gas
/// price they have since seen is wrong, and notices before they have driven
/// anywhere. Until this, the only remedy was to wait for the shift to end and
/// correct it in history, which is a remedy nobody takes.
///
/// ## It is not a general correction, and that is deliberate
///
/// ``Shift/correctRunningFuelAssumptions(_:using:)`` allows it **only while the
/// shift's route has measured no distance**. Once a distance exists the sheet is
/// not offered, and a save that somehow reached the model is refused with the
/// sentence that says why. Correcting a shift that has driven belongs to the
/// finished shift's own fuel editor, and correcting the recorded history of
/// several shifts belongs to a feature that does not exist.
///
/// ## Two explicit choices, and Keep is the default
///
/// A vehicle and a gas price, each defaulting to **keeping what the shift
/// already recorded**, so a driver who opens this and taps Save records exactly
/// what was there. Nothing is written per tap: the choices are view state and
/// the store is written once, when Save is tapped.
///
/// ## Nothing in Settings moves
///
/// A profile is **copied**, never referenced: the shift takes that profile's
/// current name and economy as facts, and a profile renamed or deleted
/// afterwards leaves this shift saying what it recorded. The gas price is copied
/// the same way. No ``VehicleProfile`` and no ``DriverSettings`` row is written
/// here, and a later change to either moves nothing on this shift.
///
/// ## Driving safety
///
/// A settings-style list of large rows, reached deliberately from a small
/// control, with an explicit Save. There is no typing: every choice is a row to
/// tap, and the two figures come from records the driver made when they were
/// stopped. Nothing presents this sheet on its own.
struct ShiftVehicleCorrectionEditor: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The driver's vehicles, oldest first, read when the sheet appears.
    ///
    /// Read once rather than on demand so the row the driver taps and the name
    /// and economy that are copied on Save are one reading of the store.
    @State private var vehicles: [VehicleProfile] = []

    /// What Settings currently holds as the price of a gallon, or `nil`.
    @State private var currentGasPrice: Money?

    @State private var vehicleChoice: VehicleChoice = .keep
    @State private var priceChoice: PriceChoice = .keep
    @State private var message: String?

    /// Which vehicle the corrected shift would record.
    private enum VehicleChoice: Equatable {
        /// Whatever the shift already recorded, which may be nothing.
        case keep
        /// One of the driver's profiles, copied by value.
        case profile(UUID)
        /// No vehicle at all, which is a statement rather than a gap: the driver
        /// is saying this shift's economy is not one they have recorded.
        case noVehicle
    }

    /// Which gas price the corrected shift would record.
    private enum PriceChoice: Equatable {
        case keep
        case current
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choiceRow(
                        title: keepVehicleTitle,
                        detail: nil,
                        isChosen: vehicleChoice == .keep,
                        spokenLabel: "Keep \(keepVehicleTitle)",
                        identifier: "keepShiftVehicleRow"
                    ) { vehicleChoice = .keep }

                    ForEach(vehicles) { vehicle in
                        choiceRow(
                            title: vehicle.name,
                            detail: economyStatement(vehicle.milesPerGallon),
                            isChosen: vehicleChoice == .profile(vehicle.id),
                            spokenLabel: spokenVehicleLabel(vehicle),
                            identifier: "correctionVehicleRow"
                        ) { vehicleChoice = .profile(vehicle.id) }
                    }

                    choiceRow(
                        title: "No vehicle",
                        detail: nil,
                        isChosen: vehicleChoice == .noVehicle,
                        spokenLabel: "No vehicle. This shift records no fuel economy and no estimate",
                        identifier: "clearShiftVehicleRow"
                    ) { vehicleChoice = .noVehicle }
                } header: {
                    Text("Vehicle")
                } footer: {
                    Text(vehicleFooterStatement)
                }

                Section {
                    choiceRow(
                        title: keepPriceTitle,
                        detail: nil,
                        isChosen: priceChoice == .keep,
                        spokenLabel: "Keep \(keepPriceTitle)",
                        identifier: "keepShiftGasPriceRow"
                    ) { priceChoice = .keep }

                    if let currentGasPrice {
                        choiceRow(
                            title: "\(currentGasPrice.formatted(locale: locale)) per gallon",
                            detail: "From Settings",
                            isChosen: priceChoice == .current,
                            spokenLabel:
                                "\(currentGasPrice.formatted(locale: locale)) per gallon, your current setting",
                            identifier: "useCurrentGasPriceRow"
                        ) { priceChoice = .current }
                    }
                } header: {
                    Text("Gas Price")
                } footer: {
                    Text(priceFooterStatement)
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shiftVehicleValidationMessage")
                    }
                }
            }
            .navigationTitle("Shift Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelShiftVehicleButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        // Nothing to save is a disabled control rather than a
                        // refusal: tapping Save on the choices already recorded
                        // should not be able to report anything at all.
                        .disabled(!hasChange)
                        .accessibilityIdentifier("saveShiftVehicleButton")
                }
            }
        }
        .onAppear(perform: seed)
    }

    // MARK: Rows

    /// One tappable choice, with its mark and its whole sentence spoken.
    ///
    /// A row rather than a `Picker`, because the two figures belong under the
    /// names they describe and a wheel shows one line at a time. The tap target
    /// is the row, which is what a driver who is stopped but in a hurry needs.
    @ViewBuilder
    private func choiceRow(
        title: String,
        detail: String?,
        isChosen: Bool,
        spokenLabel: String,
        identifier: String,
        select: @escaping () -> Void
    ) -> some View {
        Button {
            message = nil
            select()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            // The row rather than the words, so the target is the whole cell.
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        // The mark is stated, because a checkmark is not a statement to a
        // listener.
        .accessibilityLabel(isChosen ? "Chosen. \(spokenLabel)" : spokenLabel)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Words

    private var keepVehicleTitle: String {
        let context = shift.vehicleContext
        guard let economy = context.economyStatement(locale: locale) else { return context.title }
        return "\(context.title) · \(economy)"
    }

    private var keepPriceTitle: String {
        guard let price = shift.fuelAssumptions.gasPricePerGallon else { return "No gas price recorded" }
        return "\(price.formatted(locale: locale)) per gallon"
    }

    private func economyStatement(_ milesPerGallon: Decimal) -> String {
        "\(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)) MPG"
    }

    private func spokenVehicleLabel(_ vehicle: VehicleProfile) -> String {
        let economy = MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)
        return "\(vehicle.name), \(economy) miles per gallon"
    }

    private var vehicleFooterStatement: String {
        let common = """
            This records the vehicle's current name and miles per gallon onto this shift, as a copy. \
            Renaming or deleting the vehicle afterwards leaves this shift saying what it recorded, \
            and nothing in Settings is changed.
            """
        guard vehicles.isEmpty else { return common }
        return "Add a vehicle in Settings to choose one here. \(common)"
    }

    private var priceFooterStatement: String {
        """
        You can only change this before DashPilot has recorded any driving on this shift, because \
        changing what a mile is assumed to cost after the miles are recorded would restate them. \
        Nothing is recorded until you tap Save.
        """
    }

    // MARK: Behaviour

    private func seed() {
        let settings = SettingsService(context: modelContext)
        vehicles = settings.vehicleProfiles()
        currentGasPrice = (try? settings.existingSettings())??.gasPricePerGallon
    }

    /// Whether the choices differ from what the shift already records.
    private var hasChange: Bool {
        vehicleChoice != .keep || priceChoice != .keep
    }

    /// The three facts the correction would record.
    ///
    /// Composed here rather than in the service, because what "keep" means is a
    /// property of the choices on this screen; what reaches the store is one
    /// explicit triple either way.
    private var correction: FuelDefaults {
        let vehicle: (name: String?, economy: Decimal?) = switch vehicleChoice {
        case .keep:
            (shift.vehicleContext.vehicleName, shift.vehicleContext.milesPerGallon)
        case let .profile(id):
            vehicles.first { $0.id == id }
                .map { (Optional($0.name), Optional($0.milesPerGallon)) } ?? (nil, nil)
        case .noVehicle:
            (nil, nil)
        }

        let price: Money? = switch priceChoice {
        case .keep: shift.fuelAssumptions.gasPricePerGallon
        case .current: currentGasPrice
        }

        return FuelDefaults(
            vehicleName: vehicle.name,
            milesPerGallon: vehicle.economy,
            gasPricePerGallon: price
        )
    }

    /// Writes the correction, or states the rule that refused it.
    ///
    /// A profile deleted from another screen while this sheet was open resolves
    /// to no vehicle rather than to an error, which is the same answer a deleted
    /// selection gets everywhere else in the app.
    private func save() {
        do {
            try ShiftService(context: modelContext)
                .correctRunningShiftFuelAssumptions(correction, on: shift)
            dismiss()
        } catch let error as ShiftLifecycleError {
            message = error.errorDescription
        } catch {
            message = ShiftLifecycleError.storeUnavailable(underlying: error).errorDescription
        }
    }
}
