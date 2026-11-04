import Foundation

/// The reporting period Money shows, chosen from a preset or by browsing weeks.
///
/// ## Decided by the calendar, never by loaded data
///
/// Like ``InsightsNavigation``, the selection holds dates and nothing a load
/// returned, so every control has an answer while a period is loading, after a
/// save, or for a period holding no records. Loaded figures are matched to the
/// period they were built for, and a result for any other period is never shown.
///
/// ## Presets and browsing
///
/// This Week and This Month follow the calendar: they are the period containing
/// `now`, whatever `now` has become. Last Week is the week before the current
/// one when it is chosen, and is then an ordinary browsed week. Previous and Next
/// step one Monday-Sunday week and exist only while a week is selected: a month
/// or a chosen range has no step that would be unambiguous. Next stops at the
/// week in progress. A custom range keeps its dates until the driver changes
/// them, including while another preset is shown.
nonisolated struct MoneyPeriodSelection: Equatable, Sendable {
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case thisWeek, lastWeek, thisMonth, customRange

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisWeek: "This Week"
            case .lastWeek: "Last Week"
            case .thisMonth: "This Month"
            case .customRange: "Custom Range"
            }
        }
    }

    private enum Mode: Equatable, Sendable {
        /// The start of a browsed week, or `nil` to follow the current week.
        case week(Date?)
        case thisMonth
        case custom
    }

    private var mode: Mode = .week(nil)

    /// The most recently applied custom range, kept while other presets show.
    private(set) var customRange: ReportingPeriod?

    init() {}

    /// The period every figure on the screen describes.
    func period(asOf now: Date, calendar: Calendar) -> ReportingPeriod? {
        switch mode {
        case .week(let start): ReportingPeriod(unit: .week, containing: start ?? now, calendar: calendar)
        case .thisMonth: ReportingPeriod(unit: .month, containing: now, calendar: calendar)
        case .custom: customRange
        }
    }

    /// The preset that names the selection, or `nil` for a browsed week that is
    /// neither this week nor last week.
    func preset(asOf now: Date, calendar: Calendar) -> Preset? {
        switch mode {
        case .thisMonth: return .thisMonth
        case .custom: return .customRange
        case .week:
            guard let selected = period(asOf: now, calendar: calendar),
                  let current = ReportingPeriod(unit: .week, containing: now, calendar: calendar) else { return nil }
            if selected == current { return .thisWeek }
            return selected == current.previous(using: calendar) ? .lastWeek : nil
        }
    }

    /// Whether Previous and Next apply: only a week has a neighbouring week.
    var browsesWeeks: Bool {
        if case .week = mode { return true }
        return false
    }

    mutating func select(_ preset: Preset, asOf now: Date, calendar: Calendar) {
        switch preset {
        case .thisWeek:
            mode = .week(nil)
        case .lastWeek:
            guard let current = ReportingPeriod(unit: .week, containing: now, calendar: calendar),
                  let previous = current.previous(using: calendar) else { return }
            mode = .week(previous.start)
        case .thisMonth:
            mode = .thisMonth
        case .customRange:
            // Shows the range already applied. Without one, the dates are
            // chosen through ``selectCustom(from:through:calendar:)``.
            if customRange != nil { mode = .custom }
        }
    }

    /// Applies two inclusive calendar dates. A reversed range is refused and
    /// leaves the selection exactly as it was.
    @discardableResult
    mutating func selectCustom(from startDate: Date, through endDate: Date, calendar: Calendar) -> Bool {
        guard let range = ReportingPeriod(from: startDate, through: endDate, calendar: calendar) else { return false }
        customRange = range
        mode = .custom
        return true
    }

    func canSelectPrevious(asOf now: Date, calendar: Calendar) -> Bool {
        browsesWeeks && period(asOf: now, calendar: calendar)?.previous(using: calendar) != nil
    }

    /// Possible until the selected week is the one in progress.
    func canSelectNext(asOf now: Date, calendar: Calendar) -> Bool {
        guard browsesWeeks, let selected = period(asOf: now, calendar: calendar) else { return false }
        return selected.end <= now && selected.next(using: calendar) != nil
    }

    mutating func selectPrevious(asOf now: Date, calendar: Calendar) {
        guard canSelectPrevious(asOf: now, calendar: calendar),
              let previous = period(asOf: now, calendar: calendar)?.previous(using: calendar) else { return }
        mode = .week(previous.start)
    }

    /// Reaching the week in progress follows the calendar again, so it stays
    /// This Week as the days move on.
    mutating func selectNext(asOf now: Date, calendar: Calendar) {
        guard canSelectNext(asOf: now, calendar: calendar),
              let next = period(asOf: now, calendar: calendar)?.next(using: calendar) else { return }
        mode = .week(next.contains(now) ? nil : next.start)
    }

    /// The week Insights opens on: the selected week, or the week holding the
    /// last day of a month or range, never one later than the current week.
    func insightsWeek(asOf now: Date, calendar: Calendar) -> ReportingPeriod? {
        guard let selected = period(asOf: now, calendar: calendar) else { return nil }
        if selected.unit == .week { return selected }
        return ReportingPeriod(unit: .week, containing: min(selected.lastInstant, now), calendar: calendar)
    }
}
