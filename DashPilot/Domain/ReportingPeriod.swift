import Foundation

/// The kinds of span DashPilot summarises completed shifts over.
///
/// Three of them are calendar periods the driver's own calendar defines — a day,
/// a week, a month. The fourth is a range the driver picked by its dates.
///
/// A unit is a **selection boundary and nothing else**. None of them changes what
/// a figure means, which shifts contribute to one, or how a rate is worked out:
/// ``PeriodMetricsCalculator`` never asks a period what unit it is.
nonisolated enum ReportingPeriodUnit: String, CaseIterable, Sendable, Hashable, Identifiable {
    case day
    case week
    case month
    case custom

    var id: String { rawValue }

    /// The label on the control that chooses this unit.
    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .custom: "Custom"
        }
    }

    /// The calendar component a period of this unit is built from, or `nil` for
    /// a range that is not a calendar period at all.
    ///
    /// `.weekOfYear` rather than `.weekOfMonth`: a week straddling the end of a
    /// month is one week, and must not be cut at the month boundary.
    ///
    /// `.custom` has none on purpose. A driver-chosen range has no calendar
    /// component to build it from and no neighbouring range to step to, and
    /// giving it a nominal one would invent both.
    var component: Calendar.Component? {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .custom: nil
        }
    }

    /// Whether a period of this unit can be built by asking a calendar which one
    /// contains a date, and stepped to its neighbours.
    var isCalendarPeriod: Bool { component != nil }

    /// What one step backwards or forwards moves by, and the noun the screen
    /// uses for the span in a sentence.
    ///
    /// `range` for a custom selection: it is not a day, a week or a month, and
    /// calling it one of those in a sentence about which shifts it holds would
    /// be the one place this feature could mislead.
    var stepNoun: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .custom: "range"
        }
    }

    /// The units a period can be built for from a date and a calendar.
    static var calendarUnits: [ReportingPeriodUnit] { allCases.filter(\.isCalendarPeriod) }
}

/// One span, and the rule for which completed shifts belong to it.
///
/// ## Built by `Calendar`, never by arithmetic on seconds
///
/// A day is not 86,400 seconds. It is 23 hours on the day the clocks go forward
/// and 25 on the day they go back, which weekday a week starts on depends on
/// the driver's own calendar settings, and a month is 28, 29, 30 or 31 days
/// long. Every boundary here comes from `Calendar.dateInterval(of:for:)`, which
/// knows all of that. Nothing in this type adds a fixed number of seconds to
/// reach a boundary, and nothing assumes a period's length.
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
///
/// A custom range is half-open too, and is built to be: the driver picks two
/// *inclusive* calendar dates and this type converts them into
/// `startOfFirstDay ..< startOfDayAfterTheLastOne`. There is one internal
/// representation, so a month, a week and a range the driver typed are all the
/// same shape by the time anything counts a shift.
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
    ///
    /// Returns `nil` for ``ReportingPeriodUnit/custom``, which has no calendar
    /// period containing a date — use ``init(from:through:calendar:)``.
    init?(unit: ReportingPeriodUnit, containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard let component = unit.component,
              let interval = calendar.dateInterval(of: component, for: date) else { return nil }
        self.unit = unit
        start = interval.start
        end = interval.end
    }

    /// The custom range covering the **inclusive** calendar dates `startDate`
    /// through `endDate`.
    ///
    /// ## Inclusive outside, half-open inside
    ///
    /// A driver choosing *September 1* to *September 7* means seven days, the
    /// seventh included. Internally that is `Sep 1 00:00 ..< Sep 8 00:00`, so
    /// membership is decided by the same `[start, end)` rule as every other
    /// period and a shift starting at midnight on the 8th is outside it. The
    /// conversion happens here, once, so no other part of the app has to know
    /// that the interface and the domain count the last day differently.
    ///
    /// Both bounds are reduced to the start of their day in `calendar`, so the
    /// time of day carried by a date picker's value cannot shorten or lengthen
    /// the range. The day boundaries come from the calendar rather than from
    /// midnight arithmetic, because in some time zones midnight is a moment that
    /// does not exist on the day the clocks go forward.
    ///
    /// - Returns: `nil` if `endDate` falls on an earlier day than `startDate`, or
    ///   if the calendar cannot describe either day. A reversed range is
    ///   **refused, never swapped**: a driver who typed the dates the wrong way
    ///   round asked for something this app cannot honestly answer, and quietly
    ///   answering a different question would hide the mistake inside a figure.
    ///   A range of one calendar day is valid.
    init?(from startDate: Date, through endDate: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard let firstDay = calendar.dateInterval(of: .day, for: startDate),
              let lastDay = calendar.dateInterval(of: .day, for: endDate),
              firstDay.start <= lastDay.start else { return nil }
        unit = .custom
        start = firstDay.start
        end = lastDay.end
    }

    /// Whether a moment belongs to this period.
    ///
    /// **The membership rule for the whole feature**, and the same one for every
    /// unit. A completed shift is assigned to the period containing its
    /// `startedAt`, so a shift running past midnight belongs entirely to the day
    /// it began on — and, for the same reason, entirely to the month or range
    /// that day is in. Nothing splits a shift's money, mileage or deliveries
    /// across a boundary: those figures describe one working session, and cutting
    /// them at midnight would invent a division the records do not contain.
    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Whether `date` falls inside this period — the period the driver is
    /// currently living in.
    func isCurrent(asOf date: Date) -> Bool {
        contains(date)
    }

    /// The last instant that is still inside the period.
    ///
    /// For displaying and naming only. Membership is always decided by
    /// ``contains(_:)`` against the exclusive ``end``, never against this.
    var lastInstant: Date { end.addingTimeInterval(-1) }

    /// How many calendar days the period covers, in `calendar`.
    ///
    /// Asked of the calendar rather than divided out of the span's length, so a
    /// range containing a 23- or 25-hour day still counts whole days.
    func dayCount(using calendar: Calendar = .autoupdatingCurrent) -> Int? {
        calendar.dateComponents([.day], from: start, to: end).day
    }

    /// The period of the same unit immediately before this one, or `nil` if the
    /// calendar cannot reach it — which includes every custom range, since a
    /// range the driver chose has no neighbour.
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
    /// so a 23- or 25-hour day, or a 28-day February, lands on the right boundary
    /// rather than an hour or three days inside or outside it.
    private func stepped(by value: Int, using calendar: Calendar) -> ReportingPeriod? {
        guard let component = unit.component,
              let moved = calendar.date(byAdding: component, value: value, to: start) else { return nil }
        return ReportingPeriod(unit: unit, containing: moved, calendar: calendar)
    }
}

// MARK: Wording

nonisolated extension ReportingPeriod {
    /// What this period is called on screen.
    ///
    /// The period the driver is in is named for what it is to them — `Today`,
    /// `This Week`, `This Month` — because that is what they came to look at.
    /// Nothing calls a current month *complete* or *final*: it holds the records
    /// so far, and naming the month rather than describing it is what keeps that
    /// honest.
    ///
    /// Everything else is named by its dates, through `Foundation`'s formatters
    /// so the month name and the range punctuation are the driver's own. There is
    /// deliberately no "Last Week" or "3 months ago": relative names past the
    /// nearest ones stop being easier to read than the dates they stand for.
    func title(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if unit != .custom, isCurrent(asOf: now) {
            switch unit {
            case .day: return "Today"
            case .week: return "This Week"
            case .month: return "This Month"
            case .custom: break
            }
        }
        if unit == .day, isDayBefore(now, calendar: calendar) {
            return "Yesterday"
        }
        let style = dayStyle(calendar: calendar, locale: locale)
        switch unit {
        case .day:
            return start.formatted(style.weekday(.abbreviated).month().day())
        case .week:
            return "Week of \(start.formatted(style.month().day()))"
        case .month:
            // The month's own name and its year, from the locale. Never a name
            // this app assembled: "September" is not a string DashPilot is
            // entitled to hard-code on a device set to another language.
            return start.formatted(style.month(.wide).year())
        case .custom:
            return datesStatement(calendar: calendar, locale: locale)
        }
    }

    /// The dates the period actually covers, written out.
    ///
    /// Shown under the title so `This Week` is never the only thing on screen
    /// saying which days were counted. A custom range's title already *is* its
    /// dates, so it says how many days were selected instead of repeating them.
    func rangeStatement(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch unit {
        case .day:
            return start.formatted(dayStyle(calendar: calendar, locale: locale).weekday().month().day())
        case .week, .month:
            return datesStatement(calendar: calendar, locale: locale)
        case .custom:
            guard let days = dayCount(using: calendar) else {
                return datesStatement(calendar: calendar, locale: locale)
            }
            return days == 1 ? "1 selected day" : "\(days) selected days"
        }
    }

    /// The period's first and last **days**, as one localised interval.
    ///
    /// Formatted from the last instant inside the period rather than from its
    /// exclusive end, so a week reads as ending on its last day rather than on
    /// the next one, and a single-day range reads as one date rather than two.
    ///
    /// `Foundation` writes the separator and decides whether the month or the
    /// year is worth repeating. Hand-assembling `"Sep 1 – 7, 2026"` would be
    /// correct in one language.
    private func datesStatement(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let style = Date.IntervalFormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        return style.format(start..<max(start, lastInstant))
    }

    /// The style every single date in this extension is written with.
    ///
    /// The period's **own** calendar and time zone travel with the wording,
    /// never the ones the process happens to be running in. `start` and
    /// `lastInstant` are boundary instants this calendar computed, and reading
    /// one back in another zone moves it across a day boundary: 23:59:59 on a
    /// period's last day is already the next day anywhere further east, so a
    /// September month named in a zone ahead of the calendar's reads as ending
    /// on 1 October, a date the period does not contain.
    private func dayStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// What VoiceOver hears in place of the title, which on its own can be a
    /// bare date with nothing saying what it is a date of.
    func spokenTitle(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let name = title(asOf: now, calendar: calendar, locale: locale)
        let dates = rangeStatement(calendar: calendar, locale: locale)
        switch unit {
        case .day:
            return name
        case .week, .month:
            return "\(name), \(dates)"
        case .custom:
            // Named as what it is before it is read out, because a bare pair of
            // dates does not say that a driver chose them or what they select.
            return "Custom reporting range, \(name), \(dates)"
        }
    }

    /// Whether this period is the day before the one `now` falls in.
    private func isDayBefore(_ now: Date, calendar: Calendar) -> Bool {
        ReportingPeriod(unit: .day, containing: now, calendar: calendar)?.previous(using: calendar) == self
    }
}
