import Foundation

/// Which eight Monday-Sunday weeks Insights shows and which of them is selected.
///
/// ## Decided by the calendar, never by loaded data
///
/// The selection used to be resolved against the series a background load
/// returned, falling back to the newest week whenever that series was absent
/// or did not contain it. While a window was loading, after a save or a return
/// to the foreground, or for weeks holding no records, there was then no week
/// to select and no control to change it, and a selection the series did not
/// hold silently became the newest week. Here the window and the selection are
/// both worked out from the calendar, so every control has an answer whatever
/// the load is doing, and loaded figures are only ever matched to the window
/// they were built for (``InsightsSeries/showing(_:)``).
///
/// ## Moving
///
/// Previous and Next step one week and carry on past either edge of the window,
/// which moves by a whole page of eight weeks so its pages stay the ones
/// Earlier Weeks shows. The only boundary is the week in progress: there is
/// nothing later to show. A window that reaches it becomes the latest window
/// again, which follows the calendar as weeks end.
nonisolated struct InsightsNavigation: Equatable, Sendable {
    /// The start of the window's last week, or `nil` to follow the current week.
    private(set) var windowEnd: Date?
    /// The start of the selected week, or `nil` for the window's newest week.
    private(set) var selectedWeek: Date?

    init(windowEnd: Date? = nil, selectedWeek: Date? = nil) {
        self.windowEnd = windowEnd
        self.selectedWeek = selectedWeek
    }

    /// Opens on `initialPeriod`'s week, the week Money had selected. The current
    /// week follows the calendar; an earlier one stays fixed.
    init(initialPeriod: ReportingPeriod?, asOf now: Date) {
        let isCurrent = initialPeriod?.contains(now) == true
        self.init(windowEnd: isCurrent ? nil : initialPeriod?.start,
                  selectedWeek: isCurrent ? nil : initialPeriod?.start)
    }

    func window(asOf now: Date, calendar: Calendar) -> InsightsWindow? {
        InsightsWindow(endingAt: windowEnd ?? now, calendar: calendar)
    }

    /// The selected week: always one of the window's weeks.
    ///
    /// A selection that has left the window, which only happens when the latest
    /// window moves on as a week ends, resolves to the window's nearest week
    /// rather than jumping to the newest.
    func selectedPeriod(asOf now: Date, calendar: Calendar) -> ReportingPeriod? {
        guard let weeks = window(asOf: now, calendar: calendar)?.weeks,
              let first = weeks.first, let last = weeks.last else { return nil }
        guard let selectedWeek else { return last }
        if let exact = weeks.first(where: { $0.contains(selectedWeek) }) { return exact }
        return selectedWeek < first.start ? first : last
    }

    /// Always possible: earlier weeks are shown, with or without records.
    func canSelectPrevious(asOf now: Date, calendar: Calendar) -> Bool {
        selectedPeriod(asOf: now, calendar: calendar)?.previous(using: calendar) != nil
    }

    /// Possible until the selected week is the one in progress.
    func canSelectNext(asOf now: Date, calendar: Calendar) -> Bool {
        guard let selected = selectedPeriod(asOf: now, calendar: calendar) else { return false }
        return selected.end <= now && selected.next(using: calendar) != nil
    }

    func canShowLatestWeeks(asOf now: Date, calendar: Calendar) -> Bool {
        window(asOf: now, calendar: calendar)?.weeks.last?.contains(now) != true
    }

    /// The eight weeks before these, selecting the newest of them: the week
    /// immediately before the window that was showing.
    mutating func showEarlierWeeks(asOf now: Date, calendar: Calendar) {
        guard let preceding = window(asOf: now, calendar: calendar)?.precedingWeek else { return }
        windowEnd = preceding.start
        selectedWeek = preceding.start
    }

    /// The eight weeks ending with the current one, selecting the current week.
    mutating func showLatestWeeks() {
        windowEnd = nil
        selectedWeek = nil
    }

    /// Selects the week starting at `weekStart`, which must be one the window
    /// shows; anything else is ignored rather than becoming a selection that
    /// silently resolves to another week.
    mutating func select(_ weekStart: Date, asOf now: Date, calendar: Calendar) {
        guard let weeks = window(asOf: now, calendar: calendar)?.weeks,
              weeks.contains(where: { $0.start == weekStart }) else { return }
        selectedWeek = weekStart
    }

    mutating func selectPrevious(asOf now: Date, calendar: Calendar) {
        guard let window = window(asOf: now, calendar: calendar),
              let selected = selectedPeriod(asOf: now, calendar: calendar),
              let previous = selected.previous(using: calendar) else { return }
        if selected == window.weeks.first {
            // Past the window's first week: the previous page, newest week.
            windowEnd = window.precedingWeek.start
        }
        selectedWeek = previous.start
    }

    mutating func selectNext(asOf now: Date, calendar: Calendar) {
        guard canSelectNext(asOf: now, calendar: calendar),
              let window = window(asOf: now, calendar: calendar),
              let selected = selectedPeriod(asOf: now, calendar: calendar),
              let next = selected.next(using: calendar) else { return }
        if selected == window.weeks.last {
            // Past the window's last week: the next page, whose oldest week is
            // `next`, unless that page would reach the current week, in which
            // case the latest window is shown instead.
            let pageEnd = calendar.date(
                byAdding: .weekOfYear, value: InsightsWindow.displayedWeekCount - 1, to: next.start
            )
            if let pageEnd, let endWeek = ReportingPeriod(unit: .week, containing: pageEnd, calendar: calendar),
               endWeek.end <= now {
                windowEnd = endWeek.start
            } else {
                windowEnd = nil
            }
        }
        selectedWeek = next.start
    }
}
