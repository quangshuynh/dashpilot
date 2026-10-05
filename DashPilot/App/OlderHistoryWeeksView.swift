import SwiftData
import SwiftUI

/// Every completed shift that is not in the week the driver is in, grouped by
/// the week it belongs to, newest week first.
///
/// ## Why this is a screen and not a disclosure on the last one
///
/// History is scoped to the current week so that the list a driver opens the
/// app to read stays the length of a working week. The work before it is not
/// hidden, archived or summarised away: it is one tap behind a named control,
/// on a screen that says which week each shift belongs to. Nothing here mutates
/// anything, and a shift opens the same detail screen it opens from the current
/// week.
///
/// ## What it costs to show, measured
///
/// Opening it is the one place History reads more than a week, and that is the
/// driver asking for it. It fetches the completed shifts **outside** the current
/// week through ``HistoryFetchScope/otherWeeks(_:)`` and groups them with the
/// same ``HistoryWeek/partition(_:by:asOf:calendar:)`` the app has always used,
/// once per body: about 20 ms on an on-disk store holding six months of work
/// with full routes, and about 100 ms at five years.
///
/// What made it lag as weeks accumulated (reported from a real device on
/// October 3 2026) was not that: each row measured its own route **on the main
/// actor** as it scrolled into view, by a fetch whose cost grew with every
/// position the store held, about 120 ms a row at six months, and the week
/// summary above measured the same routes again. A week now measures its routes
/// once, off the main actor, through
/// ``HistoryFetchScope/weekPresentation(of:shiftIDs:in:)``, and hands each row
/// its distance; the fetch itself is by the relationship's key. The list is
/// still not paged: entry stays tens of milliseconds where the rows were whole
/// seconds, and a cursor would add a rule for what a partly loaded week means
/// without addressing the measured cost. `HistoryFetchScopeMeasurementTests` is
/// where to look again if stores grow past that.
struct OlderHistoryWeeksView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase

    /// What "now" is, for deciding which week is the current one and therefore
    /// which weeks belong on this screen. Re-read on return to the foreground,
    /// for the reason the previous screen re-reads it.
    @State private var now = Date.now

    var body: some View {
        OlderHistoryWeeksList(week: HistoryWeek(containing: now, calendar: calendar), now: now)
            .navigationTitle("Older Weeks")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
    }
}

/// The weeks themselves, for one current week.
///
/// A view of its own because its `@Query` names that week, and a query is built
/// when its view is initialised: a new week initialises a new one.
private struct OlderHistoryWeeksList: View {
    let week: HistoryWeek?
    let now: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    /// Every completed shift outside the current week, newest first. Grouped
    /// below by the partition rather than by a second statement of where a
    /// week begins.
    @Query private var otherShifts: [Shift]

    init(week: HistoryWeek?, now: Date) {
        self.week = week
        self.now = now
        _otherShifts = Query(HistoryFetchScope.otherWeeks(week))
    }

    var body: some View {
        // Once per body: the grouping walks every shift on this screen, and the
        // list, the empty notice and each section read the same result.
        let weeks = HistoryWeek.partition(otherShifts, by: \.startedAt, asOf: now, calendar: calendar)?
            .otherWeeks ?? []

        List {
            if weeks.isEmpty {
                Section {
                    DashNotice(
                        title: "No older weeks",
                        message: "Every completed shift is in the week you are in.",
                        symbol: "calendar"
                    )
                    .accessibilityIdentifier("olderHistoryWeeksEmptyNotice")
                }
            }

            ForEach(weeks) { group in
                OlderWeekSection(
                    group: group,
                    heading: heading(for: group.week),
                    spokenHeading: spokenHeading(for: group.week),
                    shiftCount: shiftCount(group.elements.count)
                )
            }
        }
    }

    /// `Sep 7 – 13, 2026`, written by `Foundation` in the week's own calendar
    /// and locale rather than assembled here.
    ///
    /// The dates rather than `Week of Sep 7`, because a heading on this screen
    /// has to say where a week **ends** as well as where it starts: a driver
    /// looking for a particular shift is scanning for the range it fell in. The
    /// screen's own title says these are weeks, and VoiceOver hears the fuller
    /// sentence below.
    private func heading(for week: HistoryWeek) -> String {
        week.rangeStatement(calendar: calendar, locale: locale)
    }

    private func spokenHeading(for week: HistoryWeek) -> String {
        week.spokenTitle(asOf: now, calendar: calendar, locale: locale)
    }

    private func shiftCount(_ count: Int) -> String {
        count == 1 ? "1 completed shift" : "\(count) completed shifts"
    }
}

/// One older week: its summary, then its shifts, under the dates it covers.
///
/// A view of its own so the distances the summary measures off the main actor
/// can be held per week and handed to that week's rows, which then never
/// measure their own routes as they scroll into view.
private struct OlderWeekSection: View {
    let group: HistoryWeekGroup<Shift>
    let heading: String
    let spokenHeading: String
    let shiftCount: String

    @State private var distances: [UUID: RouteDistance] = [:]

    var body: some View {
        Section {
            // Before the rows, because the question a driver opens this
            // screen with is "how did that week go" and the answer should not
            // have to be assembled by opening six shifts. It is a row of the
            // section rather than part of the heading so that the dates stay
            // one line.
            HistoryWeekSummaryView(
                week: group.week,
                shifts: group.elements,
                spokenWeekTitle: spokenHeading,
                measured: { distances = $0 }
            )

            ForEach(group.elements) { shift in
                // A link to the screen rather than to the value the root
                // pushes by: a `navigationDestination(for:)` belongs to the view
                // that declares it, and this screen is itself pushed onto that
                // stack, so a value-based link here finds no destination.
                NavigationLink {
                    CompletedShiftDetailView(shift: shift)
                } label: {
                    CompletedShiftRow(shift: shift, measuredDistance: distances[shift.id])
                }
                .accessibilityIdentifier("olderWeekShiftRow")
            }
        } header: {
            // The dates the week covers, out of the heading's own uppercasing,
            // in the emphasis role so where one week ends and the next begins
            // is the most obvious thing on a screen of weeks.
            Text(heading)
                .dashFont(.emphasis)
                .foregroundStyle(.primary)
                .textCase(nil)
                .accessibilityLabel(spokenHeading)
                .accessibilityIdentifier("olderWeekHeader")
        } footer: {
            Text(shiftCount)
                .dashFont(.supporting)
        }
    }
}

#if DEBUG
#Preview("Older weeks") {
    NavigationStack {
        OlderHistoryWeeksView()
    }
    .modelContainer(PreviewSupport.olderWeeksContainer())
}
#endif
