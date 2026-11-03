import Foundation

/// Eight displayed Monday-Sunday weeks and one preceding comparison week.
/// Calendar stepping, timezone, and membership come from ReportingPeriod.
nonisolated struct InsightsWindow: Equatable, Sendable {
    static let displayedWeekCount = 8
    let weeks: [ReportingPeriod]
    let precedingWeek: ReportingPeriod
    let fetchPeriod: ReportingPeriod
    let calendar: Calendar

    init?(endingAt date: Date, calendar: Calendar) {
        guard let last = ReportingPeriod(unit: .week, containing: date, calendar: calendar) else { return nil }
        var weeks = [last]
        for _ in 1..<Self.displayedWeekCount {
            guard let previous = weeks[0].previous(using: calendar) else { return nil }
            weeks.insert(previous, at: 0)
        }
        guard let preceding = weeks[0].previous(using: calendar),
              let finalDay = calendar.date(byAdding: .day, value: -1, to: last.end),
              let fetch = ReportingPeriod(from: preceding.start, through: finalDay, calendar: calendar) else { return nil }
        self.weeks = weeks
        precedingWeek = preceding
        fetchPeriod = fetch
        self.calendar = calendar
    }
}

nonisolated struct InsightsWeek: Equatable, Sendable, Identifiable {
    let metrics: PeriodMetrics
    let previous: PeriodMetrics
    var id: Date { metrics.period.start }
    var period: ReportingPeriod { metrics.period }

    var rankedExpenses: [ExpenseCategoryTotal] {
        metrics.expenses.categoryTotals.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.category.rawValue < $1.category.rawValue
        }
    }

    func comparison(asOf now: Date, calendar: Calendar) -> PeriodComparison? {
        PeriodComparisonCalculator().comparison(of: metrics, with: previous, asOf: now, calendar: calendar)
    }
}

nonisolated struct InsightsSeries: Equatable, Sendable {
    let window: InsightsWindow
    let weeks: [InsightsWeek]
    var hasRecords: Bool { weeks.contains { $0.metrics.hasAnyRecords } }

    /// This series if it was built for `window`, otherwise `nil`. A load that
    /// finishes after the driver moved to other weeks is never shown for them.
    func showing(_ window: InsightsWindow?) -> InsightsSeries? {
        self.window == window ? self : nil
    }
}

/// No chart arithmetic: the existing calculators own every total, rate and coverage.
/// Missing weeks remain present. Aggregates are ephemeral and rebuilt after edits.
nonisolated enum InsightsSeriesBuilder {
    static func build(shifts: [PeriodShiftRecord], expenses: [ExpenseRecord], window: InsightsWindow) throws -> InsightsSeries {
        let calculator = PeriodMetricsCalculator()
        var previous = calculator.metrics(of: shifts, expenses: expenses, in: window.precedingWeek)
        var points: [InsightsWeek] = []
        for period in window.weeks {
            try Task.checkCancellation()
            let metrics = calculator.metrics(of: shifts, expenses: expenses, in: period)
            points.append(InsightsWeek(metrics: metrics, previous: previous))
            previous = metrics
        }
        return InsightsSeries(window: window, weeks: points)
    }
}

/// Which weeks the trend chart labels, and with what.
///
/// Every other week, always including the newest, so four labels share the
/// axis on any phone rather than eight. A label names its month only where the
/// month changes from the label before it ("Sep 14", "28", "Oct 12", "26"), so
/// each one is short and none is ambiguous. Exact ranges are never read from
/// these: the selected-week menu and the weekly values give them in full.
nonisolated enum InsightsAxisLabels {
    static func labels(for weeks: [ReportingPeriod], calendar: Calendar, locale: Locale) -> [(week: ReportingPeriod, label: String)] {
        let labelled = weeks.enumerated()
            .filter { (weeks.count - 1 - $0.offset).isMultiple(of: 2) }
            .map(\.element)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        var previousMonth: Int?
        return labelled.map { week in
            let month = calendar.component(.month, from: week.start)
            defer { previousMonth = month }
            let label = month == previousMonth
                ? week.start.formatted(style.day())
                : week.start.formatted(style.month(.abbreviated).day())
            return (week, label)
        }
    }
}
