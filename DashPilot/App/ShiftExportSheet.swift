import SwiftData
import SwiftUI

/// Writes one export and hands it to the system share sheet.
///
/// ## One screen, two choices, no configuration
///
/// A format, and Share. There is deliberately no column picker, no date-range
/// builder and no options list: the scope was decided by the control that
/// opened this sheet — *this shift*, *this week*, *all history* — and a sheet
/// full of switches would be a second place where a driver could accidentally
/// leave something out of their own records.
///
/// ## What it says before the file leaves
///
/// The file's name, how much it holds, what the chosen format carries, and the
/// one thing about exporting that is genuinely different from everything else
/// DashPilot does: the file is written on the device, and where it goes next is
/// the driver's choice, made in the system share sheet. That is stated plainly
/// rather than warned about — sharing your own records is the point of the
/// feature.
///
/// ## When the file is written
///
/// When the sheet appears, and again when the format changes. Never before the
/// driver asked, never in the background, and never on a schedule. The previous
/// file is removed as the next is written, so the app never accumulates copies
/// of a driver's history — see ``ExportFileStore``.
struct ShiftExportSheet: View {
    let scope: ExportScope

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var format: ExportFileFormat = .json

    /// The written file, or `nil` while it is being written or after it failed.
    @State private var file: ExportedFile?

    @State private var failure: ShiftExportError?

    var body: some View {
        NavigationStack {
            Form {
                formatSection
                fileSection
                privacySection
            }
            .navigationTitle(scope.actionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("dismissExportButton")
                }
            }
            // Rewritten when the format changes, and not before the sheet is on
            // screen. `.task` rather than `.onAppear` so a slow store read
            // cannot block the presentation.
            .task(id: format) { generate() }
        }
    }

    // MARK: Sections

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $format) {
                ForEach(ExportFileFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Export format")
            .accessibilityIdentifier("exportFormatPicker")
        } header: {
            Text("Format")
        } footer: {
            Text(format.explanation)
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        Section {
            if let failure {
                Label(
                    failure.errorDescription ?? "The export could not be created.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("exportFailureMessage")
            } else if let file {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.fileName)
                        .font(.subheadline.weight(.semibold))
                        // The name is one long token; truncating it would hide
                        // the extension, which is the part that says what the
                        // file is.
                        .fixedSize(horizontal: false, vertical: true)
                    Text(file.sizeStatement(locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(file.fileName). \(file.sizeStatement(locale: locale))")
                .accessibilityIdentifier("exportFileName")

                // `ShareLink` is the system share sheet: DashPilot hands over a
                // file and takes no part in choosing where it goes.
                ShareLink(item: file.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(format.spokenShareLabel)
                .accessibilityIdentifier("shareExportButton")
            } else {
                Text("Preparing the export…")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportPreparing")
            }
        } header: {
            Text("File")
        }
    }

    private var privacySection: some View {
        Section {
            Text(
                """
                The file is created on this device. DashPilot has no network access and sends nothing \
                anywhere — where the file goes next is whatever you pick in the share sheet, and once \
                it is there it is outside DashPilot.
                """
            )
            Text(
                """
                It holds what you recorded: shift and delivery times, the amounts you typed, recorded \
                mileage and the pickup places you named. Recorded positions are not included. It is \
                not a tax statement and not a record from any delivery platform.
                """
            )
            Text(expenseStatement)
        } header: {
            Text("What Leaves the Device")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// What the file says about recorded costs, which depends on both the scope
    /// and the format rather than on one of them.
    ///
    /// A single shift carries none at all: an expense belongs to a date rather
    /// than to a shift, so there is no set of them this file could honestly
    /// claim. The CSV carries none either, because its rows are deliveries.
    private var expenseStatement: String {
        switch (scope, format) {
        case (.shift, _):
            """
            Expenses you recorded are not in a single shift's file. An expense belongs to a date \
            rather than to a shift, so DashPilot cannot say which ones were part of this one. Export \
            a day, week, month or range for costs alongside the work.
            """
        case (_, .csv):
            """
            Expenses you recorded are not in the CSV: its rows are deliveries, and an expense belongs \
            to a date rather than to one. Export JSON to include them.
            """
        case (_, .json):
            """
            Expenses you recorded in this period are included, with their notes, and so is what your \
            recorded gross earnings come to after them. That figure is not profit: costs you did not \
            record are not in it.
            """
        }
    }

    // MARK: Writing

    private func generate() {
        file = nil
        failure = nil
        do {
            file = try ShiftExportService(context: modelContext, calendar: calendar)
                .export(scope, as: format)
        } catch let error as ShiftExportError {
            failure = error
        } catch {
            failure = .writeFailed
        }
    }
}

#if DEBUG
#Preview("One shift") {
    PreviewSupport.exportSheet(.singleShift)
}

#Preview("A week") {
    PreviewSupport.exportSheet(.week)
}
#endif
