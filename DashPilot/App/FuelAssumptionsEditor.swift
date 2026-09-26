import SwiftData
import SwiftUI

/// Records or changes the two assumptions a completed shift's fuel estimate is
/// worked out under.
///
/// Presented only from a finished shift in history, by the rule that governs
/// ``ShiftEarningsEditor``: typing figures is a stopped-vehicle task, so nothing
/// anywhere offers this during a running shift, and ``Shift`` refuses it as
/// well, because a screen that is merely never presented is not a rule.
///
/// Editing is a **draft**. Both typed fields are view state; the store is
/// written once, when the driver taps Save or Remove. Cancelling, or dismissing
/// the sheet, leaves the recorded pair exactly as it was, and nothing is written
/// per keystroke.
///
/// **The pair moves together.** Both fields are read and validated before
/// anything is saved, so an edit that corrects a valid price and mistypes an
/// economy leaves the shift with the pair it already had rather than half of a
/// new one.
///
/// ## What the fields are seeded from
///
/// This shift's own assumptions, where it has any. Otherwise the driver's
/// **current defaults** — their selected vehicle and the gas price in Settings —
/// and failing those the most recent shift that recorded some, through
/// ``ShiftService/mostRecentFuelAssumptions()``. Seeding a text field is not
/// deriving a figure: nothing is recorded against this shift until Save, and no
/// shift recorded earlier changes because a later one, or a setting, records
/// something else.
///
/// ## `Use Current Defaults`, and why it is offered rather than applied
///
/// A shift worked before Settings existed, or before the driver filled them in,
/// records nothing. **Nothing fills it in for them**: an old shift with no
/// assumptions keeps none, because writing today's figures into last month's
/// work would put an assumption the driver never made into their history. What
/// they get instead is one explicit control that fills these fields with what
/// Settings currently holds, which they then Save — or do not.
///
/// ## The vehicle name follows the fuel economy
///
/// A shift records which vehicle its economy came from only when that economy
/// **is** the selected vehicle's, which is what filling the fields from the
/// defaults produces. A driver who types a different figure records no vehicle,
/// because DashPilot does not know which vehicle covers that many miles on a
/// gallon. The rule itself lives on ``FuelDefaults`` and ``Shift``.
struct FuelAssumptionsEditor: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The drafts. Seeded on appearance, and read by nothing but ``save()``.
    @State private var milesPerGallonText = ""
    @State private var gasPriceText = ""
    @State private var message: String?

    /// Whether the fields were filled from somewhere other than this shift,
    /// which is a different thing to tell the driver: those figures are a
    /// suggestion, and this shift records nothing until they save.
    @State private var isSeededFromElsewhere = false

    /// What Settings currently holds, read once when the sheet appears.
    ///
    /// Read once rather than on demand so that the figures the driver is shown,
    /// the figures `Use Current Defaults` fills in and the vehicle name saved
    /// beside them are all the same reading.
    @State private var currentDefaults = FuelDefaults.none

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case milesPerGallon
        case gasPrice
    }

    private var hasRecordedAssumptions: Bool { shift.fuelAssumptions.hasAny }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Miles per gallon") {
                        TextField(milesPerGallonPlaceholder, text: $milesPerGallonText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .milesPerGallon)
                            .monospacedDigit()
                            .accessibilityIdentifier("fuelMilesPerGallonField")
                            .accessibilityLabel("Miles per gallon")
                            .onChange(of: milesPerGallonText) { _, _ in message = nil }
                    }

                    LabeledContent("Gas price per gallon") {
                        TextField(gasPricePlaceholder, text: $gasPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .gasPrice)
                            .monospacedDigit()
                            .accessibilityIdentifier("fuelGasPriceField")
                            .accessibilityLabel("Gas price per gallon")
                            .onChange(of: gasPriceText) { _, _ in message = nil }
                    }

                    if let message {
                        DashValidationMessage(message: message, identifier: "fuelAssumptionsValidationMessage")
                    }
                } header: {
                    Text("Fuel Assumptions")
                } footer: {
                    Text(footerStatement)
                }

                if currentDefaults.hasAny {
                    Section {
                        Button("Use Current Defaults", action: fillFromCurrentDefaults)
                            .accessibilityHint("Fills these fields with your settings. Nothing is recorded until you save.")
                            .accessibilityIdentifier("useCurrentDefaultsButton")
                    } footer: {
                        Text(currentDefaultsStatement)
                    }
                }

                if hasRecordedAssumptions {
                    Section {
                        Button("Remove Fuel Assumptions", role: .destructive, action: remove)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeFuelAssumptionsButton")
                    } footer: {
                        Text(
                            """
                            Removes both figures entirely, so this shift has no fuel estimate at all. That is \
                            not the same as recording that it used no fuel.
                            """
                        )
                    }
                }
            }
            .navigationTitle(hasRecordedAssumptions ? "Edit Fuel" : "Add Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelFuelAssumptionsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveFuelAssumptionsButton")
                }
            }
        }
        .onAppear(perform: seed)
    }

    /// What the two fields mean, and where the figures in them came from.
    ///
    /// The estimate wording lives on the detail screen, which is where the
    /// figure is; this says the part that belongs to entry. Both sentences avoid
    /// calling the result an expense, and neither promises the estimate covers
    /// the driving DashPilot did not record.
    private var footerStatement: String {
        let common = """
            DashPilot estimates fuel as recorded miles divided by miles per gallon, priced at this gas \
            price. Both are your own assumptions, kept on this device and kept with this shift: \
            entering different figures later does not change any shift you have already recorded. \
            This is an estimate, not a recorded expense.
            """
        guard isSeededFromElsewhere else { return common }
        return """
            These figures are filled in to save typing, and are not yet recorded against this \
            shift. Nothing is until you tap Save. \(common)
            """
    }

    /// What the defaults control would fill in, named rather than left to a tap
    /// to reveal.
    private var currentDefaultsStatement: String {
        var parts: [String] = []
        if let vehicle = currentDefaults.vehicleName,
           let economy = currentDefaults.assumptions.milesPerGallon {
            parts.append("\(vehicle), \(MilesPerGallonInput(locale: locale).text(for: economy)) MPG")
        } else if let economy = currentDefaults.assumptions.milesPerGallon {
            parts.append("\(MilesPerGallonInput(locale: locale).text(for: economy)) MPG")
        }
        if let price = currentDefaults.assumptions.gasPricePerGallon {
            parts.append("\(price.formatted(locale: locale)) / gallon")
        }
        let figures = parts.joined(separator: " · ")
        return """
            Fills the fields above with your settings: \(figures). Nothing is recorded against this \
            shift until you tap Save.
            """
    }

    private var milesPerGallonPlaceholder: String { MilesPerGallonInput(locale: locale).placeholder }
    private var gasPricePlaceholder: String { MoneyInput(locale: locale).placeholder }

    private func seed() {
        currentDefaults = SettingsService(context: modelContext).currentFuelDefaults()

        let recorded = shift.fuelAssumptions
        let assumptions: FuelAssumptions
        if recorded.hasAny {
            assumptions = recorded
            isSeededFromElsewhere = false
        } else if currentDefaults.hasAny {
            // The driver's own current defaults before an older shift's
            // recorded pair: they said what they are driving and what fuel
            // costs, and that is a better suggestion than a figure inferred
            // from history.
            assumptions = currentDefaults.assumptions
            isSeededFromElsewhere = true
        } else {
            assumptions = ShiftService(context: modelContext).mostRecentFuelAssumptions()
            isSeededFromElsewhere = assumptions.hasAny
        }

        fill(from: assumptions)
        focusedField = .milesPerGallon
    }

    /// Fills both fields from the driver's settings, writing nothing.
    ///
    /// The explicit action an older shift needs. It is a fill rather than a
    /// save, so the driver still sees what they are about to record and can
    /// change or abandon it, and a shift recorded before Settings existed keeps
    /// recording nothing until they choose otherwise.
    private func fillFromCurrentDefaults() {
        fill(from: currentDefaults.assumptions)
        isSeededFromElsewhere = true
        message = nil
    }

    private func fill(from assumptions: FuelAssumptions) {
        if let milesPerGallon = assumptions.milesPerGallon {
            milesPerGallonText = MilesPerGallonInput(locale: locale).text(for: milesPerGallon)
        }
        if let gasPrice = assumptions.gasPricePerGallon {
            gasPriceText = MoneyInput(locale: locale).text(for: gasPrice)
        }
    }

    /// Reads both fields, then writes once.
    ///
    /// An empty field is **not** a zero: it means the driver has not recorded
    /// that half, and the estimate then says which half is missing. Both fields
    /// are parsed before anything is handed to the store, so a refusal names the
    /// field that caused it and leaves the shift untouched.
    private func save() {
        let milesPerGallon: Decimal?
        do {
            milesPerGallon = try readMilesPerGallon()
        } catch {
            // Typed, so `error` is the fuel economy's own failure and carries
            // the sentence written for it.
            message = error.errorDescription ?? "That fuel economy could not be saved."
            focusedField = .milesPerGallon
            return
        }

        let gasPrice: Money?
        do {
            gasPrice = try readGasPrice()
        } catch {
            // Said in the terms of what was being typed: a driver entering a
            // price at a pump is not recording gross earnings.
            message = error.message(for: .gasPricePerGallon)
            focusedField = .gasPrice
            return
        }

        do {
            try ShiftService(context: modelContext).setFuelAssumptions(
                milesPerGallon: milesPerGallon,
                gasPricePerGallon: gasPrice,
                vehicleName: currentDefaults.vehicleName(accompanying: milesPerGallon),
                on: shift
            )
            dismiss()
        } catch {
            // The sheet stays open with what the driver typed: figures that
            // could not be saved are not a reason to make them type again.
            message = (error as? any LocalizedError)?.errorDescription
                ?? "Those figures could not be saved."
        }
    }

    private func readMilesPerGallon() throws(MilesPerGallonInputError) -> Decimal? {
        guard !milesPerGallonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try MilesPerGallonInput(locale: locale).milesPerGallon(from: milesPerGallonText)
    }

    private func readGasPrice() throws(MoneyInputError) -> Money? {
        guard !gasPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try MoneyInput(locale: locale).amount(from: gasPriceText)
    }

    private func remove() {
        do {
            try ShiftService(context: modelContext).clearFuelAssumptions(on: shift)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "Those figures could not be removed."
        }
    }
}

#if DEBUG
#Preview("Add fuel assumptions") {
    PreviewSupport.fuelAssumptionsEditor(withRecordedAssumptions: false)
}

#Preview("Edit fuel assumptions") {
    PreviewSupport.fuelAssumptionsEditor(withRecordedAssumptions: true)
}
#endif
