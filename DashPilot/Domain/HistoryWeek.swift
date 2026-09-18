import Foundation

/// One Monday-to-Sunday week of history, and the rule for which records belong
/// to it.
///
/// ## Why History has a week of its own
///
/// The History list is the screen a driver opens to read what they have just
/// been doing, and the answer they want is almost always *this week*. Showing
/// every shift ever recorded puts the most recent one at the top of a list that
/// grows without limit, so History is scoped to the current week and everything
/// older is reached through its own screen. Nothing is deleted, archived or
/// moved: this type decides what is **shown where**, and nothing else.
///
/// ## Built from `ReportingPeriod`, not from new boundary arithmetic
///
/// Every boundary here comes from ``ReportingPeriod`` with
/// ``ReportingPeriodUnit/week``, which is the app's one implementation of a
/// calendar week: `Calendar.dateInterval(of:for:)` decides where a week starts
/// and ends, the span is half-open, and a week containing a daylight-saving
/// transition is 167 or 169 hours rather than a fixed 168. This type adds no
/// second rule for any of that, and it adds no seconds to any date.
///
/// ## The one thing it does decide: Monday
///
/// A period summary's week starts on the day the **driver's own device** says a
/// week starts, which in the United States is Sunday. History's week always
/// starts on **Monday**, because a working week is what this list is scoped to
/// and a driver reading it should not have to know their calendar's first
/// weekday to know which shifts they are looking at.
///
/// That is expressed by pinning `firstWeekday` on a copy of the driver's own
/// calendar, in ``mondayFirst(_:)``, and passing the result to
/// ``ReportingPeriod``. **The time zone, the calendar identifier and every other
/// setting are the driver's**, so which instant Monday 00:00 is remains a
/// question their calendar answers, exactly as it does everywhere else in the
/// app.
///
/// It also means History's week and the period summary's week can differ by a
/// day for a driver whose device starts the week on Sunday. Both screens name
/// the dates they cover, which is what keeps the difference readable rather
/// than hidden.
nonisolated struct HistoryWeek: Equatable, Sendable, Hashable, Identifiable {
    /// The underlying calendar period. Every boundary question is answered by
    /// this, never by arithmetic here.
    let period: ReportingPeriod

    /// The week's first instant: Monday 00:00 in the driver's own time zone.
    var start: Date { period.start }

    /// The first instant *after* the week: the following Monday 00:00. Never
    /// part of it.
    var end: Date { period.end }

    /// Stable across a redraw, and unique per week: a week is identified by the
    /// Monday it begins on.
    var id: Date { start }

    /// The week that `date` falls in, on a Monday-first copy of `calendar`.
    ///
    /// Optional rather than trapping, for the same reason ``ReportingPeriod``
    /// is: the calendar is a value the caller supplies, and no arrangement of
    /// one should be able to crash a driver's device.
    init?(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard let period = ReportingPeriod(
            unit: .week,
            containing: date,
            calendar: Self.mondayFirst(calendar)
        ) else { return nil }
        self.period = period
    }

    /// Whether a moment belongs to this week.
    ///
    /// Half-open, like every other period in the app: a shift started at
    /// exactly Monday 00:00 belongs to the week that is beginning, and to that
    /// week only.
    func contains(_ date: Date) -> Bool { period.contains(date) }

    /// `calendar` with its first weekday pinned to Monday, and nothing else
    /// changed.
    ///
    /// The single place History's Monday rule is expressed. Time zone, calendar
    /// identifier and locale settings travel through untouched, so this changes
    /// which day a week starts on and never which instant a day starts at.
    static func mondayFirst(_ calendar: Calendar) -> Calendar {
        var mondayFirst = calendar
        // 1 is Sunday in every calendar `Foundation` exposes this on, so 2 is
        // Monday. A named constant rather than a literal at each use, because a
        // bare `2` in a view would be unreadable.
        mondayFirst.firstWeekday = 2
        return mondayFirst
    }
}

// MARK: Wording

nonisolated extension HistoryWeek {
    /// What this week is called on screen: `This Week`, or `Week of Sep 7`.
    ///
    /// Delegated to ``ReportingPeriod/title(asOf:calendar:locale:)`` so History
    /// and the period summaries name a week the same way, and so the month name
    /// and the date order are the driver's own rather than ones this app
    /// assembled.
    func title(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        period.title(asOf: now, calendar: Self.mondayFirst(calendar), locale: locale)
    }

    /// The dates the week actually covers, written out, so a heading saying
    /// `This Week` is never the only thing on screen saying which days it holds.
    func rangeStatement(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        period.rangeStatement(calendar: Self.mondayFirst(calendar), locale: locale)
    }

    /// What VoiceOver hears in place of a heading that can otherwise be a bare
    /// pair of dates with nothing saying what they are dates of.
    func spokenTitle(
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        period.spokenTitle(asOf: now, calendar: Self.mondayFirst(calendar), locale: locale)
    }
}

/// The records of one week, in the order they were given.
///
/// A group is a heading and a sequence. It merges nothing, sums nothing and
/// re-sorts nothing: the elements arrive in the order the caller's query
/// already put them in and leave in that order, so History's newest-first
/// ordering inside a week is the query's rule and not this type's.
nonisolated struct HistoryWeekGroup<Element>: Identifiable {
    let week: HistoryWeek

    /// The records belonging to ``week``, in the order they were given.
    let elements: [Element]

    var id: Date { week.id }

    /// Whether this group holds nothing. A current week legitimately can; an
    /// older group never is, because a week with no records is not built.
    var isEmpty: Bool { elements.isEmpty }
}

/// History split into the week the driver is in and the weeks before it.
///
/// ## Why one call rather than two
///
/// The default list and the older-weeks screen have to agree exactly about
/// where the boundary is: a record that neither of them claimed would be a
/// record the driver can no longer reach. Deriving both sides from one pass
/// over one collection is what makes that impossible to get wrong.
nonisolated struct HistoryWeekPartition<Element> {
    /// The current Monday-to-Sunday week, and the records in it. Present even
    /// when it holds nothing, because a screen scoped to this week has to say
    /// which week it is scoped to whether or not anything is in it.
    let currentWeek: HistoryWeekGroup<Element>

    /// Every other week that holds a record, newest week first, each with the
    /// records in the order they were given. Weeks with no records are absent
    /// rather than present and empty.
    ///
    /// **Other**, not *older*: a record dated after this week cannot be produced
    /// by working, but a device clock moved backwards can leave one in a store,
    /// and it is listed here, at the top, rather than being hidden from every
    /// screen there is.
    let otherWeeks: [HistoryWeekGroup<Element>]

    /// Whether anything at all sits outside the current week.
    var hasOtherWeeks: Bool { !otherWeeks.isEmpty }

    /// How many records sit outside the current week.
    var otherWeekRecordCount: Int { otherWeeks.reduce(0) { $0 + $1.elements.count } }
}

nonisolated extension HistoryWeek {
    /// Splits `elements` into the current week and the weeks around it.
    ///
    /// - Parameters:
    ///   - elements: the records to arrange, in the order they should appear.
    ///   - date: the instant each record is placed by. For a completed shift
    ///     that is its `startedAt`, which is the same instant every period in
    ///     the app already assigns a shift by; nothing here introduces a second
    ///     rule for which week a shift belongs to.
    ///   - now: the instant that decides which week is current.
    ///   - calendar: the driver's calendar. Its first weekday is replaced by
    ///     Monday and everything else is used as given.
    /// - Returns: the split, or `nil` if the calendar cannot describe the week
    ///   containing `now` — in which case the caller has no current week to
    ///   scope a screen to and should show what it has.
    static func partition<Element>(
        _ elements: [Element],
        by date: (Element) -> Date,
        asOf now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> HistoryWeekPartition<Element>? {
        guard let currentWeek = HistoryWeek(containing: now, calendar: calendar) else { return nil }

        var current: [Element] = []
        var order: [HistoryWeek] = []
        var members: [HistoryWeek: [Element]] = [:]

        for element in elements {
            let moment = date(element)
            if currentWeek.contains(moment) {
                current.append(element)
                continue
            }
            // A record the calendar cannot place has no week to be shown under.
            // It stays with the current week rather than disappearing, which is
            // the one outcome worth ruling out.
            guard let week = HistoryWeek(containing: moment, calendar: calendar) else {
                current.append(element)
                continue
            }
            if members[week] == nil {
                order.append(week)
            }
            members[week, default: []].append(element)
        }

        let others = order
            .sorted { $0.start > $1.start }
            .map { HistoryWeekGroup(week: $0, elements: members[$0] ?? []) }

        return HistoryWeekPartition(
            currentWeek: HistoryWeekGroup(week: currentWeek, elements: current),
            otherWeeks: others
        )
    }
}
