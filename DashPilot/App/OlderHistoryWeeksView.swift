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
/// ## What it costs to show
///
/// The query is the same one the previous screen runs, and the weeks are built
/// by the same ``HistoryWeek/partition(_:by:asOf:calendar:)`` call, so the two
/// lists cannot disagree about where the boundary is. A `List` materialises only
/// the rows near the viewport, and a row measures its own route only once it
/// appears, so opening a long history draws a screenful rather than a lifetime.
/// Fetching in pages is a separate piece of work: it needs a fetch limit, a
/// cursor and a rule for what a partial week means, and none of that is worth
/// building before a store exists that needs it.
struct OlderHistoryWeeksView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    /// Every completed shift, newest first. The current week's are dropped by
    /// the partition below rather than by the query, because the query's
    /// predicate would be a second statement of a boundary this app already has
    /// exactly one of.
    @Query(filter: #Predicate<Shift> { $0.endedAt != nil }, sort: \Shift.startedAt, order: .reverse)
    private var completedShifts: [Shift]

    /// What "now" is, for deciding which week is the current one and therefore
    /// which weeks belong on this screen. Re-read on return to the foreground,
    /// for the reason the previous screen re-reads it.
    @State private var now = Date.now

    private var weeks: [HistoryWeekGroup<Shift>] {
        HistoryWeek.partition(completedShifts, by: \.startedAt, asOf: now, calendar: calendar)?
            .otherWeeks ?? []
    }

    var body: some View {
        List {
            if weeks.isEmpty {
                Section {
                    Text("Every completed shift is in the week you are in.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("olderHistoryWeeksEmptyNotice")
                }
            }

            ForEach(weeks) { group in
                Section {
                    // Before the rows, because the question a driver opens this
                    // screen with is "how did that week go" and the answer
                    // should not have to be assembled by opening six shifts.
                    // It is a row of the section rather than part of the
                    // heading so that the dates stay one line, which is what
                    // keeps the list from being pushed down a screenful.
                    HistoryWeekSummaryView(week: group.week, shifts: group.elements)

                    ForEach(group.elements) { shift in
                        // A link to the screen rather than to the value the root
                        // pushes by. A `navigationDestination(for:)` belongs to
                        // the view that declares it, and this screen is itself
                        // pushed onto that stack, so a value-based link here
                        // finds no destination and a row tap does nothing. The
                        // destination is the same view either way.
                        NavigationLink {
                            CompletedShiftDetailView(shift: shift)
                        } label: {
                            CompletedShiftRow(shift: shift)
                        }
                        .accessibilityIdentifier("olderWeekShiftRow")
                    }
                } header: {
                    // The dates the week covers, out of the heading's own
                    // uppercasing, which makes an abbreviated month harder to
                    // read than it needs to be. A driver scrolling this screen
                    // is looking for a week, so the dates are the heading rather
                    // than a caption under one.
                    Text(heading(for: group.week))
                        .textCase(nil)
                        .accessibilityLabel(spokenHeading(for: group.week))
                        .accessibilityIdentifier("olderWeekHeader")
                } footer: {
                    Text(shiftCount(group.elements.count))
                }
            }
        }
        .navigationTitle("Older Weeks")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
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

#if DEBUG
#Preview("Older weeks") {
    NavigationStack {
        OlderHistoryWeeksView()
    }
    .modelContainer(PreviewSupport.olderWeeksContainer())
}
#endif
