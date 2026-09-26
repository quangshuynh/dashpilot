import OSLog
import SwiftData
import SwiftUI

/// History on the root screen: the current Monday-to-Sunday week's completed
/// shifts, and the way to everything else.
///
/// ## Why the query lives here
///
/// A `@Query` is built once, when its view is initialised, so a predicate naming
/// a week has to be built by a view that is initialised again when the week
/// changes. ``RootView`` owns the clock (read on appearance, on return to the
/// foreground, and at the week's own end) and hands this view the week; a new
/// week initialises a new query. Nothing else about when the week rolls over
/// moved.
///
/// ## What it reads, and what it deliberately does not
///
/// The week's own shifts, through ``HistoryFetchScope/currentWeek(_:)``, and a
/// **count** of every other completed shift. It does not hold the rest of a
/// driver's history: at five years that was 3,132 objects fetched and
/// partitioned on every store save, on the screen a driver reads while working.
/// How many *weeks* those other shifts fall in needs each one's start, so it is
/// worked out off the main actor and only when the count or the week changes.
///
/// ## The week's own figures
///
/// The section opens with ``HistoryWeekSummaryView`` over the shifts this view
/// already holds, so the summary reads nothing the list did not: it measures
/// those shifts' routes off the main actor, once per revision of what they
/// record, and never walks another week. A route batch saved while a shift runs
/// changes no completed shift, so it restarts nothing.
///
/// `Export All History` is a control here and nothing more: the export reads
/// the whole store through its own fetch, never this view's rows.
struct CurrentWeekHistorySection: View {
    /// The week the list is scoped to, or `nil` for a calendar that cannot
    /// describe it, in which case every completed shift is listed.
    let week: HistoryWeek?

    /// The instant that decided ``week``, for naming it `This Week`.
    let now: Date

    let exportAllHistory: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    @Query private var shifts: [Shift]

    /// How many completed shifts sit outside the week, or `nil` before the
    /// first count. A count realises no row, so it is cheap to re-read.
    @State private var otherShiftCount: Int?

    /// How many weeks those shifts fall in, worked out off the main actor for
    /// the count it was worked out for.
    @State private var otherWeeks: HistoryOtherWeeksSummary?

    init(week: HistoryWeek?, now: Date, exportAllHistory: @escaping () -> Void) {
        self.week = week
        self.now = now
        self.exportAllHistory = exportAllHistory
        _shifts = Query(HistoryFetchScope.currentWeek(week))
    }

    private var hasOtherWeeks: Bool { (otherShiftCount ?? 0) > 0 }

    private var hasAnyHistory: Bool { !shifts.isEmpty || hasOtherWeeks }

    var body: some View {
        Group {
            reportsSection
            historySection
        }
        .onAppear(perform: countOtherWeeks)
        // Every write reaches the store through a save, including a shift ended
        // by an intent and a shift deleted on a screen pushed from here, so a
        // save is when the count can have moved. Re-counting is a `COUNT` and
        // realises nothing.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            countOtherWeeks()
        }
        .onChange(of: week) { _, _ in countOtherWeeks() }
        .task(id: OtherWeeksKey(week: week, shiftCount: otherShiftCount)) {
            await summariseOtherWeeks()
        }
    }

    /// The two controls that span every shift there is, in a section of their
    /// own above the week.
    ///
    /// Apart from the week rather than inside it, so the week's section can open
    /// with the week's own figures and go straight into its shifts. Still above
    /// History rather than after it, because they are how a driver reaches a
    /// summary of a day, a month or a chosen range, and that entry point should
    /// not move down the screen as the week fills up.
    private var reportsSection: some View {
        Section {
            // Named for what the screen is rather than for the four lengths it
            // offers: listing them here would have to be corrected every time
            // one is added, and the screen already says which one it is showing.
            NavigationLink {
                PeriodSummaryView()
            } label: {
                Label("Period Summaries", systemImage: "calendar")
                    .dashFont(.body)
            }
            .accessibilityIdentifier("periodSummaryLink")

            // Absent when history is empty, because an export control over no
            // records is an offer the app would have to refuse.
            if hasAnyHistory {
                Button(action: exportAllHistory) {
                    Label(ExportScope.allHistory.actionTitle, systemImage: "square.and.arrow.up")
                        .dashFont(.body)
                }
                .accessibilityLabel(ExportScope.allHistory.spokenActionLabel)
                .accessibilityIdentifier("exportAllHistoryButton")
            }
        }
    }

    private var historySection: some View {
        Section {
            // The week's own figures, first, so the section answers "how is this
            // week going" before it lists the shifts that make it up. Absent for
            // an empty week, which the notice below speaks for: a summary of no
            // shifts would be a card of absences.
            if let week, !shifts.isEmpty {
                HistoryWeekSummaryView(
                    week: week,
                    shifts: shifts,
                    spokenWeekTitle: week.spokenTitle(asOf: now, calendar: calendar, locale: locale),
                    placement: .currentWeek
                )
            }

            ForEach(shifts) { shift in
                // The whole row is one destination: a finished shift is a thing
                // to open, not a row with controls scattered across it.
                NavigationLink(value: shift) {
                    CompletedShiftRow(shift: shift)
                }
                .accessibilityIdentifier("completedShiftRow")
            }

            if shifts.isEmpty {
                emptyNotice
            }

            // Last in the section, under the week it is an alternative to, and
            // styled as an ordinary row rather than as the prominent thing on
            // screen. Absent when there is nothing else, because a screen that
            // would open on an empty list is not worth offering.
            if hasOtherWeeks {
                NavigationLink {
                    OlderHistoryWeeksView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: DashSpacing.xs) {
                            Text("View Older Weeks")
                                .dashFont(.body)
                            Text(otherWeeksStatement)
                                .dashFont(.supporting)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
                .accessibilityLabel("View older weeks. \(otherWeeksStatement)")
                .accessibilityIdentifier("olderHistoryWeeksLink")
            }
        } header: {
            header
        } footer: {
            footer
        }
    }

    /// What an empty week says, in the one vocabulary every empty state uses.
    ///
    /// Two cases, because they mean different things: a driver with no history
    /// at all is told where it will come from, and one whose week is merely
    /// empty so far is told the earlier work is still there. Nothing older is
    /// pulled forward to fill the list.
    @ViewBuilder
    private var emptyNotice: some View {
        if hasOtherWeeks {
            DashNotice(
                title: "No completed shifts this week yet",
                message: "Earlier weeks are under View Older Weeks.",
                symbol: "calendar"
            )
            .accessibilityIdentifier("emptyCurrentWeekNotice")
        } else if otherShiftCount == 0 {
            DashNotice(
                title: "No completed shifts yet",
                message: "A shift appears here once you end it.",
                symbol: "clock"
            )
            .accessibilityIdentifier("emptyHistoryNotice")
        }
    }

    /// `2 weeks · 3 shifts`, or the shift count alone for the moment before the
    /// weeks have been worked out. Counts and nothing else; neither word says
    /// *older*, because a shift dated after this week is counted here too.
    private var otherWeeksStatement: String {
        let count = otherShiftCount ?? 0
        if let otherWeeks, otherWeeks.shiftCount == count {
            return otherWeeks.statement
        }
        return count == 1 ? "1 shift" : "\(count) shifts"
    }

    /// The section heading, naming the week the list is scoped to.
    ///
    /// **One line, and that is a constraint rather than a preference.** A
    /// two-line heading cost nine red journeys: the header sits above the rows,
    /// so every point it grows pushes the list down, and the second
    /// `completedShiftRow` fell out of what the `List` had rendered. The dates
    /// are in the footer, which is below the rows and can grow freely.
    ///
    /// VoiceOver still hears the dates here, because a listener has no footer in
    /// view to read afterwards.
    @ViewBuilder
    private var header: some View {
        if let week {
            Text("History · \(week.title(asOf: now, calendar: calendar, locale: locale))")
                .accessibilityLabel("History. \(week.spokenTitle(asOf: now, calendar: calendar, locale: locale))")
                .accessibilityIdentifier("historyHeader")
        } else {
            Text("History")
        }
    }

    /// Which days the section is showing. The empty states are rows of the
    /// section rather than footer text, so the footer only ever names the dates
    /// and where everything before them is.
    @ViewBuilder
    private var footer: some View {
        if let week, hasAnyHistory {
            let dates = week.rangeStatement(calendar: calendar, locale: locale)
            if hasOtherWeeks {
                Text("Showing \(dates). Everything before it is under View Older Weeks.")
            } else {
                Text("Showing \(dates).")
            }
        }
    }

    private func countOtherWeeks() {
        do {
            otherShiftCount = try HistoryFetchScope.otherWeekShiftCount(outside: week, in: modelContext)
        } catch {
            // Structural only: which read failed, never what it would have
            // counted. The list of this week's shifts is unaffected.
            AppLog.persistence.error("Failed to count shifts outside the current week")
        }
    }

    /// Works out how many weeks the other shifts fall in, through a context of
    /// its own and off the main actor.
    private func summariseOtherWeeks() async {
        guard let count = otherShiftCount, count > 0 else {
            otherWeeks = otherShiftCount == 0 ? HistoryOtherWeeksSummary.none : nil
            return
        }
        let container = modelContext.container
        let week = week
        let calendar = calendar
        let summary = await Task.detached(priority: .utility) {
            try? HistoryFetchScope.otherWeeksSummary(outside: week, in: container, calendar: calendar)
        }.value
        guard !Task.isCancelled else { return }
        otherWeeks = summary
    }
}

/// What the other-weeks summary is worked out for: a week and a count. A new
/// value of either starts the work again and cancels the stale one.
private struct OtherWeeksKey: Equatable {
    let week: HistoryWeek?
    let shiftCount: Int?
}
