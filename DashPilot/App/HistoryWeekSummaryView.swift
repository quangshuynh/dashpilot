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
    /// Where the summary sits, which decides only how loud its headline is.
    enum Placement {
        /// Above the week the driver is in, on the root screen: the headline
        /// is the largest figure in History.
        case currentWeek
        /// Above one week of many on Older Weeks: the same hierarchy, one step
        /// quieter, so a screen of weeks reads as a list rather than a wall of
        /// headlines.
        case olderWeek

        var headline: DashMetric.Emphasis {
            switch self {
            case .currentWeek: .hero
            case .olderWeek: .standard
            }
        }

        var identifier: String {
            switch self {
            case .currentWeek: "currentWeekSummary"
            case .olderWeek: "olderWeekSummary"
            }
        }
    }

    let week: HistoryWeek
    let shifts: [Shift]

    /// What the section's heading says aloud, so the summary, which is one
    /// element, names its own week rather than relying on the heading having
    /// been heard first.
    let spokenWeekTitle: String

    var placement: Placement = .olderWeek

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    /// Derived when the section appears. `nil` while the routes are still being
    /// measured, which is a state the screen says plainly rather than filling
    /// with zeros.
    @State private var summary: HistoryWeekSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.lg) {
            if let summary {
                let lines = summary.lines(locale: locale)

                // The three figures that answer "what did this week look like",
                // in the order a driver asks it: what it paid, then how long and
                // how far. Earnings lead on their own line and the two
                // quantities share a row, which becomes a column where it
                // cannot hold them.
                if let earnings = lines.first(where: { $0.id == .earnings }) {
                    metric(earnings, emphasis: placement.headline)
                }
                DashMetricRow {
                    ForEach(lines.filter { $0.id == .working || $0.id == .mileage }) { line in
                        metric(line, emphasis: .standard)
                    }
                }

                Divider()

                // Context under the figures, quieter: the work itself, then the
                // estimates only where the week has them. Each estimate keeps its
                // coverage under it, because a partial figure without the count
                // behind it reads as a claim about the whole week.
                VStack(alignment: .leading, spacing: DashSpacing.md) {
                    Text(summary.activityStatement)
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(lines.filter { $0.id == .estimatedFuel || $0.id == .estimatedNet }) { line in
                        DashValueRow(
                            title: line.title,
                            value: line.value,
                            detail: line.detail,
                            isFigure: line.isFigure
                        )
                    }
                }
            } else {
                Text("Working out this week…")
                    .dashFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DashSpacing.sm)
        // Keyed on the week **and** what its shifts record, so editing one of
        // them works this week out again and nothing else. Reading the
        // revision here is also what makes this body observe those facts. The
        // previous figures stay on screen until the new ones arrive.
        .task(id: SummaryKey(week: week.id, revision: HistoryWeekRevision(shifts))) { await derive() }
        // One element, so a listener hears the week as a week rather than as a
        // dozen unrelated fragments, and hears each unit and each coverage said
        // in full.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier(placement.identifier)
    }

    /// One of the three headline figures: the value, what it is, and the
    /// coverage behind it. A figure that was never recorded is drawn as the
    /// words that say so, in the quieter role, never as a zero.
    private func metric(_ line: HistoryWeekSummaryLine, emphasis: DashMetric.Emphasis) -> some View {
        DashMetric(
            value: line.value,
            label: line.title,
            detail: line.detail,
            isFigure: line.isFigure,
            emphasis: emphasis
        )
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

/// What a week's summary is worked out for: which week, and the revision of
/// the facts its shifts record.
private struct SummaryKey: Equatable {
    let week: Date
    let revision: HistoryWeekRevision
}
