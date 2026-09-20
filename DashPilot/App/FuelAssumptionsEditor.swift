import SwiftData
import SwiftUI

/// Records or changes the two assumptions a completed shift's fuel estimate is
/// worked out under.
///
/// Presented only from a finished shift in history, by the rule that governs
/// ``ShiftEarningsEditor``: typing figures is a stopped-vehicle task, so nothing
/// anywhere offers this during a running shift, and ``Shift`` refuses it as well
/// — a screen that is merely never presented is not a rule.
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
/// This shift's own assumptions, where it has any. Otherwise the most recent
/// shift that recorded some, through
/// ``ShiftService/mostRecentFuelAssumptions()`` — which is the whole of what a
/// "default" means here. Seeding a text field is not deriving a figure: nothing
/// is recorded against this shift until Save, and no shift recorded earlier
/// changes because a later one records something else.
struct FuelAssumptionsEditor: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The drafts. Seeded on appearance, and read by nothing but ``save()``.
    @State private var milesPerGallonText = ""
    @State private var gasPriceText = ""
    @State private var message: String?

    /// Whether the fields were filled from an earlier shift rather than from
    /// this one, which is a different thing to tell the driver: those figures
    /// are a suggestion, and this shift records nothing until they save.
    @State private var isSeededFromAnotherShift = false

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
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("fuelAssumptionsValidationMessage")
                    }
                } header: {
                    Text("Fuel Assumptions")
                } footer: {
                    Text(footerStatement)
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
        guard isSeededFromAnotherShift else { return common }
        return """
            These figures are the ones you last recorded, filled in to save typing. Nothing is \
            recorded against this shift until you tap Save. \(common)
            """
    }

    private var milesPerGallonPlaceholder: String { MilesPerGallonInput(locale: locale).placeholder }
    private var gasPricePlaceholder: String { MoneyInput(locale: locale).placeholder }

    private func seed() {
        let recorded = shift.fuelAssumptions
        let assumptions: FuelAssumptions
        if recorded.hasAny {
            assumptions = recorded
            isSeededFromAnotherShift = false
        } else {
            assumptions = ShiftService(context: modelContext).mostRecentFuelAssumptions()
            isSeededFromAnotherShift = assumptions.hasAny
        }

        if let milesPerGallon = assumptions.milesPerGallon {
            milesPerGallonText = MilesPerGallonInput(locale: locale).text(for: milesPerGallon)
        }
        if let gasPrice = assumptions.gasPricePerGallon {
            gasPriceText = MoneyInput(locale: locale).text(for: gasPrice)
        }
        focusedField = .milesPerGallon
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
