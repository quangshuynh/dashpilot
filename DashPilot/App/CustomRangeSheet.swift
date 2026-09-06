import SwiftUI

/// Choosing the two calendar dates a custom reporting range covers.
///
/// ## Inclusive dates, chosen as dates
///
/// The driver picks a **start day** and an **end day**, both included. Choosing
/// *September 1* and *September 7* selects seven days. That is what a date range
/// means everywhere else on a phone, and it is the reason this screen exists
/// rather than two `DatePicker`s left permanently on the summary: the
/// interface's inclusive end and the domain's exclusive one are converted in a
/// single place — ``ReportingPeriod/init(from:through:calendar:)`` — instead of
/// each screen deciding what "to" means.
///
/// ## A draft, applied on purpose
///
/// Nothing outside this sheet changes while the driver is choosing. The summary
/// is not recomputed on every turn of a picker, and **Cancel leaves the previous
/// selection exactly as it was**. A report that reshuffles itself under a moving
/// picker is both expensive — every shift's route is measured again — and hard
/// to read.
///
/// ## Not the future
///
/// Neither date may be later than today. DashPilot summarises records it already
/// holds; it does not forecast, and a range reaching into next week could only
/// ever be a period that is partly empty by definition. Today itself is
/// selectable, because a driver may well want the range to end with the shifts
/// they finished this morning.
struct CustomRangeSheet: View {
    /// The applied range's dates, so re-opening the sheet starts where the
    /// driver left off rather than back at a default.
    let start: Date
    let end: Date

    /// The last day that may be chosen. Passed in rather than read from the
    /// clock here, so the screen that owns the selection decides once what
    /// "today" is and this sheet cannot disagree with it mid-session.
    let latestSelectableDay: Date

    /// Called with the two inclusive dates when the driver applies them.
    let onApply: (Date, Date) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var draftStart: Date
    @State private var draftEnd: Date

    init(start: Date, end: Date, latestSelectableDay: Date, onApply: @escaping (Date, Date) -> Void) {
        self.start = start
        self.end = end
        self.latestSelectableDay = latestSelectableDay
        self.onApply = onApply
        _draftStart = State(initialValue: start)
        _draftEnd = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                datesSection
                selectionSection
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel, keep the current range")
                        .accessibilityIdentifier("customRangeCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draftStart, draftEnd)
                        dismiss()
                    }
                    .disabled(draftPeriod == nil)
                    .accessibilityLabel("Apply this date range")
                    .accessibilityIdentifier("customRangeApplyButton")
                }
            }
        }
    }

    // MARK: Sections

    private var datesSection: some View {
        Section {
            DatePicker(
                "Start date",
                selection: $draftStart,
                in: ...latestSelectableDay,
                displayedComponents: .date
            )
            .accessibilityIdentifier("customRangeStartPicker")

            DatePicker(
                "End date",
                selection: $draftEnd,
                in: ...latestSelectableDay,
                displayedComponents: .date
            )
            .accessibilityIdentifier("customRangeEndPicker")
        } header: {
            Text("Dates")
        } footer: {
            Text(
                """
                Both dates are included: a range from the 1st to the 7th covers seven days. Neither can \
                be later than today — DashPilot summarises shifts you have already finished, and \
                forecasts nothing.
                """
            )
        }
    }

    /// What the chosen dates select, or why they select nothing.
    ///
    /// An invalid range is **refused and named**, never quietly turned round.
    /// Reversing the dates for the driver would answer a question they did not
    /// ask and hide the fact that they typed the wrong one.
    @ViewBuilder
    private var selectionSection: some View {
        Section {
            if let draftPeriod {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draftPeriod.title(asOf: latestSelectableDay, calendar: calendar, locale: locale))
                        .font(.headline)
                    Text(draftPeriod.rangeStatement(calendar: calendar, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    draftPeriod.spokenTitle(asOf: latestSelectableDay, calendar: calendar, locale: locale)
                )
                .accessibilityIdentifier("customRangeSummary")
            } else {
                Label(
                    "The end date is before the start date. Choose an end date on or after the start date.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("customRangeInvalid")
            }
        } header: {
            Text("Selection")
        }
    }

    /// The range the current draft would produce, or `nil` when it is not one.
    private var draftPeriod: ReportingPeriod? {
        ReportingPeriod(from: draftStart, through: draftEnd, calendar: calendar)
    }
}

#if DEBUG
#Preview("A week of dates") {
    PreviewSupport.customRangeSheet()
}
#endif
