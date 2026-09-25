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
/// ## Why it measures in a task, off the main actor
///
/// The summary needs every shift in the week measured, and a shift's route can
/// hold thousands of positions. A `List` materialises a section when it comes
/// near the viewport, so the work happens for the weeks a driver actually
/// scrolls to and once each, rather than for every week in the store on every
/// redraw, and it runs on a context of its own off the main actor, because a
/// week of ordinary shifts is over half a second of route walking and the list
/// has to keep scrolling meanwhile. Nothing is cached in the store: the figures are derived from the
/// route and the recorded facts each time the section is built, exactly as
/// ``CompletedShiftRow`` derives its own.
struct HistoryWeekSummaryView: View {
    let week: HistoryWeek
    let shifts: [Shift]

    /// What the section's heading says aloud, so the summary, which is one
    /// element, names its own week rather than relying on the heading having
    /// been heard first.
    let spokenWeekTitle: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    /// Derived when the section appears. `nil` while the routes are still being
    /// measured, which is a state the screen says plainly rather than filling
    /// with zeros.
    @State private var summary: HistoryWeekSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary {
                let lines = summary.lines(locale: locale)
                let primary = lines.filter { $0.prominence == .primary }
                let secondary = lines.filter { $0.prominence == .secondary }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(primary) { row($0) }
                }
                if !secondary.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(secondary) { row($0) }
                    }
                }
            } else {
                Text("Working out this week…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: week.id) { await derive() }
        // One element, so a listener hears the week as a week rather than as a
        // dozen unrelated fragments, and hears each unit and each coverage said
        // in full.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier("olderWeekSummary")
    }

    /// One figure: what it is, what it says, and what is behind it.
    ///
    /// Primary figures are drawn larger and heavier than the rest; the order
    /// and the divider say the same thing, so the difference never rests on
    /// weight alone. Two columns at ordinary text sizes and one at
    /// accessibility sizes, for the reason ``CompletedShiftRow``'s heading
    /// stacks: a shortened label beside a shortened figure is worse than a
    /// second line, and the first thing a truncation takes is the word that
    /// makes a figure honest. Nothing here shrinks text to make it fit.
    @ViewBuilder
    private func row(_ line: HistoryWeekSummaryLine) -> some View {
        let isPrimary = line.prominence == .primary
        let titleFont: Font = isPrimary ? .subheadline : .footnote
        let valueFont: Font = isPrimary ? .headline : .footnote.weight(.medium)

        VStack(alignment: .leading, spacing: 1) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(line.title)
                    .font(titleFont)
                    .foregroundStyle(.secondary)
                Text(line.value)
                    .font(valueFont)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.title)
                        .font(titleFont)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(line.value)
                        .font(valueFont)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
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
        guard let summary else { return "\(spokenWeekTitle). Working out this week." }
        return summary.spokenSummary(weekTitle: spokenWeekTitle, locale: locale)
    }

    /// Measures each shift's route once and hands the records to the one
    /// aggregation, off the main actor.
    ///
    /// A week of ordinary shifts is over half a second of route walking, paid
    /// as the section scrolls into view, so it runs through
    /// ``HistoryFetchScope/weekSummary(of:shiftIDs:in:)`` on a context of its
    /// own and the list keeps scrolling meanwhile. The figures are the same:
    /// one calculator over the same saved facts.
    ///
    /// The expenses overload is deliberately not used: an ``Expense`` belongs to
    /// a date rather than to a shift, this screen is a list of shifts, and a
    /// cost recorded on a day nobody worked has nothing to do with the week's
    /// shifts. What a period cost, and what its earnings come to after those
    /// costs, is on the period summary.
    private func derive() async {
        let week = week
        let ids = shifts.map(\.id)
        let container = modelContext.container
        let derived = await Task.detached(priority: .userInitiated) {
            HistoryFetchScope.weekSummary(of: week, shiftIDs: ids, in: container)
        }.value
        guard !Task.isCancelled else { return }
        summary = derived
    }
}
