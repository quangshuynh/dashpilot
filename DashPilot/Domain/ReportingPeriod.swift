import Foundation

/// The lengths of calendar period DashPilot summarises completed shifts over.
///
/// Two, deliberately. A day and a week are the spans a driver already plans in;
/// a month or a year would need the same coverage vocabulary and would answer a
/// question nobody has asked of this app yet.
nonisolated enum ReportingPeriodUnit: String, CaseIterable, Sendable, Hashable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    /// The label on the control that chooses this unit.
    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        }
    }

    /// The calendar component a period of this unit is built from.
    ///
    /// `.weekOfYear` rather than `.weekOfMonth`: a week straddling the end of a
    /// month is one week, and must not be cut at the month boundary.
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        }
    }

    /// What one step backwards or forwards moves by, in words.
    var stepNoun: String {
        switch self {
        case .day: "day"
        case .week: "week"
        }
    }
}

/// One calendar span, and the rule for which completed shifts belong to it.
///
/// ## Built by `Calendar`, never by arithmetic on seconds
///
/// A day is not 86,400 seconds. It is 23 hours on the day the clocks go forward
/// and 25 on the day they go back, and which weekday a week starts on depends on
/// the driver's own calendar settings. Every boundary here comes from
/// `Calendar.dateInterval(of:for:)`, which knows all of that. Nothing in this
/// type adds a fixed number of seconds to reach a boundary, and nothing assumes
/// a period's length.
///
/// The calendar is supplied by the caller rather than read from
/// `Calendar.current` inside, so a test can pin a time zone and a first weekday
/// and get the same answer on every machine. The app passes the driver's own
/// calendar, which is why a week starts on the day *their* device says it does
/// rather than on an ISO Monday this app chose for them.
///
/// ## Half-open
///
/// The span is `[start, end)`. A shift starting at exactly midnight belongs to
/// the day that is beginning, and to that day only — a closed range would put it
/// in two consecutive days, and a summary that counts one shift twice is worse
/// than no summary at all.
nonisolated struct ReportingPeriod: Equatable, Sendable, Hashable {
    let unit: ReportingPeriodUnit

    /// The first instant of the period.
    let start: Date

    /// The first instant *after* the period. Never part of it.
    let end: Date

    /// The period of `unit` that `date` falls in.
    ///
    /// Optional rather than trapping: the calendar is a value the caller
    /// supplies, and no arrangement of one should be able to crash a driver's
    /// device. `Calendar` produces an interval for every ordinary instant.
    init?(unit: ReportingPeriodUnit, containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard let interval = calendar.dateInterval(of: unit.component, for: date) else { return nil }
        self.unit = unit
        start = interval.start
        end = interval.end
    }

    /// Whether a moment belongs to this period.
    ///
    /// **The membership rule for the whole feature.** A completed shift is
    /// assigned to the period containing its `startedAt`, so a shift running past
    /// midnight belongs entirely to the day it began on. Nothing splits a shift's
    /// money, mileage or deliveries across a boundary: those figures describe one
    /// working session, and cutting them at midnight would invent a division the
    /// records do not contain.
    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Whether `date` falls inside this period — the period the driver is
    /// currently living in.
    func isCurrent(asOf date: Date) -> Bool {
        contains(date)
    }

    /// The period of the same unit immediately before this one, or `nil` if the
    /// calendar cannot reach it.
    func previous(using calendar: Calendar = .autoupdatingCurrent) -> ReportingPeriod? {
        stepped(by: -1, using: calendar)
    }

    /// The period of the same unit immediately after this one, or `nil` if the
    /// calendar cannot reach it.
    func next(using calendar: Calendar = .autoupdatingCurrent) -> ReportingPeriod? {
        stepped(by: 1, using: calendar)
    }

    /// A step of whole calendar units from this period's start.
    ///
    /// `Calendar` takes the step and the result is then re-derived into a period,
    /// so a 23- or 25-hour day lands on the right boundary rather than an hour
    /// inside or outside it.
    private func stepped(by value: Int, using calendar: Calendar) -> ReportingPeriod? {
        guard let moved = calendar.date(byAdding: unit.component, value: value, to: start) else { return nil }
        return ReportingPeriod(unit: unit, containing: moved, calendar: calendar)
    }
}

// MARK: Wording

nonisolated extension ReportingPeriod {
    /// What this period is called on screen.
    ///
    /// The period the driver is in is named for what it is to them — `Today`,
    /// `This Week` — because that is what they came to look at. Nothing calls a
    /// current week *complete* or *final*: it holds the records so far, and
    /// naming the week rather than describing it is what keeps that honest.
    ///
    /// Everything else is named by its dates. There is deliberately no "Last
    /// Week" or "3 weeks ago": relative names past the nearest ones stop being
    /// easier to read than the dates they stand for.
    func title(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if isCurrent(asOf: now) {
            return unit == .day ? "Today" : "This Week"
        }
        if unit == .day, isDayBefore(now, calendar: calendar) {
            return "Yesterday"
        }
        switch unit {
        case .day:
            return start.formatted(.dateTime.weekday(.abbreviated).month().day().locale(locale))
        case .week:
            return "Week of \(start.formatted(.dateTime.month().day().locale(locale)))"
        }
    }

    /// The dates the period actually covers, written out.
    ///
    /// Shown under the title so `This Week` is never the only thing on screen
    /// saying which days were counted.
    func rangeStatement(locale: Locale = .autoupdatingCurrent) -> String {
        switch unit {
        case .day:
            return start.formatted(.dateTime.weekday().month().day().locale(locale))
        case .week:
            let style = Date.FormatStyle.dateTime.month().day().locale(locale)
            // The last instant inside the period rather than its exclusive end,
            // so a week reads as ending on its last day, not on the next one.
            return "\(start.formatted(style)) – \(end.addingTimeInterval(-1).formatted(style))"
        }
    }

    /// What VoiceOver hears in place of the title, which on its own can be a
    /// bare date with nothing saying what it is a date of.
    func spokenTitle(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let name = title(asOf: now, calendar: calendar, locale: locale)
        return unit == .day ? name : "\(name), \(rangeStatement(locale: locale))"
    }

    /// Whether this period is the day before the one `now` falls in.
    private func isDayBefore(_ now: Date, calendar: Calendar) -> Bool {
        ReportingPeriod(unit: .day, containing: now, calendar: calendar)?.previous(using: calendar) == self
    }
}
