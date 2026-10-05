import SwiftData
import SwiftUI

/// The target gross earnings per working hour the driver's next shifts will be
/// compared with.
///
/// A personal benchmark, said as one: it is not recorded earnings and not a
/// claim about what a shift should pay. Like the gas price it is a default for
/// shifts **not yet started**, copied onto each shift when it starts, so
/// changing it here never reclassifies a shift already worked.
struct HourlyTargetEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var targetText = ""
    @State private var message: String?
    @State private var hasRecordedTarget = false

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: DashSpacing.sm) {
                        Text("Per working hour")
                            .dashFont(.metricLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField(placeholder, text: $targetText)
                            .dashFont(.body)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .monospacedDigit()
                            .accessibilityIdentifier("hourlyTargetField")
                            .accessibilityLabel("Target gross earnings per working hour")
                            .onChange(of: targetText) { _, _ in message = nil }
                    }
                    .padding(.vertical, DashSpacing.xs)

                    if let message {
                        DashValidationMessage(message: message, identifier: "hourlyTargetValidationMessage")
                    }
                } header: {
                    Text("Target Hourly Earnings")
                } footer: {
                    Text(
                        """
                        A personal benchmark, compared with each shift's gross earnings per working \
                        hour. Each shift records the target when it starts, so a change applies to \
                        your next shift and never to one already worked.
                        """
                    )
                }

                if hasRecordedTarget {
                    Section {
                        Button("Remove Target", role: .destructive, action: remove)
                            .dashFont(.body)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeHourlyTargetButton")
                    } footer: {
                        Text("Shifts you start afterwards record no target. Shifts already worked keep theirs.")
                    }
                }
            }
            .navigationTitle("Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelHourlyTargetButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveHourlyTargetButton")
                }
            }
        }
        .onAppear(perform: seed)
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func seed() {
        let recorded = SettingsService(context: modelContext).hourlyTarget()
        hasRecordedTarget = recorded != nil
        if let recorded {
            targetText = MoneyInput(locale: locale).text(for: recorded)
        }
        isFocused = true
    }

    /// An empty field is refused rather than read as a target of zero; Remove
    /// is how a driver says they want none.
    private func save() {
        let target: Money
        do {
            target = try MoneyInput(locale: locale).amount(from: targetText)
        } catch {
            message = error.message(for: .hourlyTarget)
            return
        }
        do {
            try SettingsService(context: modelContext).setHourlyTarget(target)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription ?? "That target could not be saved."
        }
    }

    private func remove() {
        do {
            try SettingsService(context: modelContext).setHourlyTarget(nil)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription ?? "The target could not be removed."
        }
    }
}
