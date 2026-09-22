import SwiftData
import SwiftUI

/// How one week in History went, above that week's shifts.
///
/// ## It totals nothing of its own
///
/// Every figure comes from ``HistoryWeekSummary``, which is
/// ``PeriodMetricsCalculator`` over the week's own ``ReportingPeriod``. This
/// view chooses no subset, adds nothing up, and decides no wording: it draws the
/// lines it is given, in the order it is given them. A total assembled in a view
/// body is the second definition this project keeps out of the app.
///
/// ## Why it measures in a task rather than in `body`
///
/// The summary needs every shift in the week measured, and a shift's route can
/// hold thousands of positions. A `List` materialises a section when it comes
/// near the viewport, so the work happens for the weeks a driver actually
/// scrolls to and once each, rather than for every week in the store on every
/// redraw. Nothing is cached in the store: the figures are derived from the
/// route and the recorded facts each time the section is built, exactly as
/// ``CompletedShiftRow`` derives its own.
struct HistoryWeekSummaryView: View {
    let week: HistoryWeek
    let shifts: [Shift]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    /// Derived when the section appears. `nil` while the routes are still being
    /// measured, which is a state the screen says plainly rather than filling
    /// with zeros.
    @State private var summary: HistoryWeekSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary {
                ForEach(summary.lines(locale: locale)) { line in
                    row(line)
                }
            } else {
                Text("Working out this week…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: week.id) { summary = derive() }
        // One element, so a listener hears the week as a week rather than as ten
        // unrelated fragments, and hears each unit and each coverage said in
        // full. The heading above already names the dates.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier("olderWeekSummary")
    }

    /// One figure: what it is, what it says, and what is behind it.
    ///
    /// Two columns at ordinary text sizes and one at accessibility sizes, for
    /// the reason ``CompletedShiftRow``'s heading stacks: a shortened label
    /// beside a shortened figure is worse than a second line, and the first
    /// thing a truncation takes is the word that makes a figure honest.
    @ViewBuilder
    private func row(_ line: HistoryWeekSummaryLine) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(line.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(line.value)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(line.value)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
            }

            if let detail = line.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Wrap rather than truncate: a coverage statement cut in
                    // half reads as a claim about the whole week.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("olderWeekSummaryLine.\(line.id.rawValue)")
    }

    private var spokenLabel: String {
        guard let summary else { return "Working out this week." }
        return summary.spokenSummary(locale: locale)
    }

    /// Measures each shift's route once and hands the records to the one
    /// aggregation.
    ///
    /// The expenses overload is deliberately not used: an ``Expense`` belongs to
    /// a date rather than to a shift, this screen is a list of shifts, and a
    /// cost recorded on a day nobody worked has nothing to do with the week's
    /// shifts. What a period cost, and what its earnings come to after those
    /// costs, is on the period summary.
    private func derive() -> HistoryWeekSummary {
        HistoryWeekSummary(
            week: week,
            records: shifts.map { $0.periodRecord(for: $0.recordedDistance()) }
        )
    }
}
