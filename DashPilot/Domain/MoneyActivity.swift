import Foundation

/// How finely Money divides the selected period for its activity chart and
/// its list of days.
///
/// Decided by the period's length in calendar days alone, so the same period
/// always divides the same way: whole days up to a month, Monday-Sunday weeks
/// up to about six months, and calendar months beyond that. A long custom range
/// therefore never draws hundreds of bars on a small iPhone.
nonisolated enum MoneyActivityGranularity: String, Equatable, Sendable {
    case day, week, month

    /// The longest period, in days, divided into days.
    static let longestDailyPeriod = 31
    /// The longest period, in days, divided into weeks.
    static let longestWeeklyPeriod = 186

    init?(for period: ReportingPeriod, calendar: Calendar) {
        guard let days = period.dayCount(using: calendar), days > 0 else { return nil }
        if days <= Self.longestDailyPeriod {
            self = .day
        } else if days <= Self.longestWeeklyPeriod {
            self = .week
        } else {
            self = .month
        }
    }

    var unit: ReportingPeriodUnit {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }

    /// "day", "week" or "month", for sentences about one bucket.
    var noun: String { rawValue }
}

/// One slice of the selected period and what was recorded in it.
///
/// The metrics come from ``PeriodMetricsCalculator`` over the same records as
/// the period's own figures, by the same rules: shifts belong wholly to the
/// slice containing their start, expenses to the slice containing their own
/// date. Every recorded shift and expense in the period lands in exactly one
/// slice, so the slices reconcile with the period's totals.
nonisolated struct MoneyActivityBucket: Equatable, Sendable, Identifiable {
    /// The slice, clipped to the selected period. A whole calendar day, week or
    /// month where the period allows it, otherwise a custom range over the part
    /// of it inside the period.
    let period: ReportingPeriod
    let metrics: PeriodMetrics

    var id: Date { period.start }

    /// Whether a completed shift or an expense was recorded in this slice.
    var hasRecords: Bool { metrics.hasAnyRecords }
}

/// The selected period, divided for the activity chart and the list of days.
nonisolated struct MoneyActivity: Equatable, Sendable {
    let granularity: MoneyActivityGranularity

    /// Every slice of the period in chronological order, including slices with
    /// no records.
    let buckets: [MoneyActivityBucket]

    /// The slices that have begun by `now`, and any later slice holding a
    /// record. A period in progress does not present the days still to come as
    /// days with nothing recorded.
    func buckets(startedBy now: Date) -> [MoneyActivityBucket] {
        buckets.filter { $0.period.start <= now || $0.hasRecords }
    }

    /// The slices holding a completed shift or an expense, newest first.
    var recordedBuckets: [MoneyActivityBucket] {
        buckets.filter(\.hasRecords).reversed()
    }

    /// Whether any slice has an amount to draw: recorded shift gross or a
    /// recorded expense. A recorded `$0.00` counts.
    var hasChartableAmounts: Bool {
        buckets.contains { $0.metrics.recordedGrossEarnings != nil || $0.metrics.expenses.recordedTotal != nil }
    }
}

nonisolated enum MoneyActivityBuilder {
    /// Divides `period` and summarises each slice.
    ///
    /// - Parameters:
    ///   - shifts: candidate shift records, in any order. The calculator keeps
    ///     only completed shifts that started inside each slice.
    ///   - expenses: candidate expenses, in any order.
    ///   - period: the selected period. Every reporting period starts and ends
    ///     at a calendar day boundary, so its slices do too.
    ///   - calendar: the calendar whose days, weeks and months divide it. A
    ///     23- or 25-hour day is still one day.
    static func build(
        shifts: [PeriodShiftRecord],
        expenses: [ExpenseRecord],
        in period: ReportingPeriod,
        calendar: Calendar
    ) throws -> MoneyActivity? {
        guard let granularity = MoneyActivityGranularity(for: period, calendar: calendar) else { return nil }
        let slices = slices(of: period, by: granularity, calendar: calendar)
        guard !slices.isEmpty else { return nil }

        // Group once rather than asking every slice to scan every record, so a
        // long range stays linear in its records.
        var shiftGroups = Array(repeating: [PeriodShiftRecord](), count: slices.count)
        for shift in shifts {
            if let index = index(of: shift.startedAt, in: slices) { shiftGroups[index].append(shift) }
        }
        var expenseGroups = Array(repeating: [ExpenseRecord](), count: slices.count)
        for expense in expenses {
            if let index = index(of: expense.occurredAt, in: slices) { expenseGroups[index].append(expense) }
        }

        let calculator = PeriodMetricsCalculator()
        var buckets: [MoneyActivityBucket] = []
        buckets.reserveCapacity(slices.count)
        for (index, slice) in slices.enumerated() {
            try Task.checkCancellation()
            buckets.append(MoneyActivityBucket(
                period: slice,
                metrics: calculator.metrics(of: shiftGroups[index], expenses: expenseGroups[index], in: slice)
            ))
        }
        return MoneyActivity(granularity: granularity, buckets: buckets)
    }

    /// Consecutive, non-overlapping slices covering `period` exactly.
    static func slices(
        of period: ReportingPeriod,
        by granularity: MoneyActivityGranularity,
        calendar: Calendar
    ) -> [ReportingPeriod] {
        var slices: [ReportingPeriod] = []
        var cursor = period.start
        while cursor < period.end {
            guard let whole = ReportingPeriod(unit: granularity.unit, containing: cursor, calendar: calendar),
                  whole.end > cursor else { break }
            let start = max(whole.start, period.start)
            let end = min(whole.end, period.end)
            if start == whole.start, end == whole.end {
                slices.append(whole)
            } else if let clipped = ReportingPeriod(from: start, through: end.addingTimeInterval(-1), calendar: calendar) {
                slices.append(clipped)
            } else {
                break
            }
            cursor = end
        }
        return slices
    }

    /// The slice holding `date`, by the half-open rule every period uses.
    private static func index(of date: Date, in slices: [ReportingPeriod]) -> Int? {
        var low = 0
        var high = slices.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let slice = slices[middle]
            if date < slice.start {
                high = middle - 1
            } else if date >= slice.end {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }
}
