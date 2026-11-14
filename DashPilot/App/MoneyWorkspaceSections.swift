import Charts
import SwiftUI

// MARK: Summary

/// The figures Money leads with: recorded gross, then expenses, net, the
/// working-hour rate and working time as compact tiles. All five come from the
/// financial read, so they appear without waiting for routes.
struct MoneySummarySection: View {
    let metrics: PeriodMetrics
    let noun: String
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            DashMetric(value: metrics.recordedGrossEarnings?.formatted(locale: locale) ?? "Earnings not recorded",
                       label: "Recorded gross earnings",
                       detail: "Based on \(metrics.earningsCoverage.statement(noun: "completed shift"))",
                       isFigure: metrics.recordedGrossEarnings != nil, emphasis: .financial, keepsFigureTogether: true)
                .padding(.vertical, DashSpacing.md)
                .listRowBackground(ShiftActivityPalette.cloud)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("moneyGross")
            tiles
            Text(metrics.netAfterRecordedExpenses.isAvailable
                 ? "Net is \(metrics.netBasisStatement.lowercasedFirst). \(metrics.netCautionStatement)"
                 : metrics.netUnavailableExplanation)
                .dashFont(.supporting).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("moneyNetExplanation")
        } header: { Text("Selected \(noun)") }
    }

    @ViewBuilder
    private var tiles: some View {
        let expenses = MoneyTile(
            title: "Recorded expenses",
            value: metrics.expenses.recordedTotal?.formatted(locale: locale) ?? "None recorded",
            caption: metrics.expenseBasisStatement,
            isFigure: metrics.expenses.hasRecords,
            spoken: metrics.spokenExpenseStatement(locale: locale), identifier: "moneyExpenses")
        let net = MoneyTile(
            title: metrics.netTitle,
            value: metrics.netStatement(locale: locale) ?? "Not available",
            caption: metrics.netAfterRecordedExpenses.isAvailable ? "Gross less recorded expenses" : "Needs recorded earnings and expenses",
            isFigure: metrics.netAfterRecordedExpenses.isAvailable,
            spoken: metrics.spokenNetStatement(locale: locale), identifier: "moneyNet")
        let rate = metrics.rate(.perWorkingHour)
        let hourly = MoneyTile(
            title: "Gross per working hour",
            value: metrics.rateStatement(.perWorkingHour, locale: locale) ?? "Not available",
            caption: rate.isAvailable ? rate.coverage.statement(noun: "shift") : "Needs earnings and working time",
            isFigure: rate.isAvailable,
            spoken: metrics.spokenRateStatement(.perWorkingHour, locale: locale), identifier: "moneyHourlyRate")
        let working = MoneyTile(
            title: "Working time",
            value: metrics.workingDuration.map(DurationText.short) ?? "Not recorded",
            caption: metrics.workingDuration == nil ? "No completed shift" : "\(metrics.workingCoverage.statement(noun: "shift")) · pauses excluded",
            isFigure: metrics.workingDuration != nil,
            spoken: metrics.workingDuration.map {
                "Working time, \(DurationText.spoken($0)), \(metrics.workingCoverage.spokenStatement()). Pauses are excluded."
            } ?? "No working time recorded.",
            identifier: "moneyWorkingTime")
        if dynamicTypeSize.isAccessibilitySize {
            expenses
            net
            hourly
            working
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: DashSpacing.lg, verticalSpacing: DashSpacing.xl) {
                GridRow { expenses; net }
                GridRow { hourly; working }
            }
            .padding(.vertical, DashSpacing.sm)
        }
    }
}

/// One compact figure: its value, what it is, and what is behind it. A
/// sentence standing in for a missing figure is drawn in the quieter colour.
struct MoneyTile: View {
    let title: String
    let value: String
    let caption: String
    var isFigure = true
    let spoken: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            Text(value)
                .dashFont(isFigure ? .metric : .body)
                .monospacedDigit()
                .foregroundStyle(isFigure ? .primary : .secondary)
                .lineLimit(isFigure ? 1 : nil)
                .minimumScaleFactor(isFigure ? 0.5 : 1)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .dashFont(.metricLabel).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .dashFont(.supporting).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Time, distance and deliveries

/// Figures that need deliveries and routes, from the second read.
struct MoneyWorkDetailRows: View {
    let metrics: PeriodMetrics
    @Environment(\.locale) private var locale

    var body: some View {
        duration("Delivery active time", spokenAs: "delivery active time", metrics.deliveryActiveDuration,
                 coverage: metrics.deliveryActiveCoverage, identifier: "moneyDeliveryActiveTime")
        duration("Non-delivery time", spokenAs: "non-delivery time", metrics.nonDeliveryDuration,
                 coverage: metrics.nonDeliveryCoverage, identifier: "moneyNonDeliveryTime")
        rate(.perDeliveryActiveHour, identifier: "moneyActiveHourRate")
        DashValueRow(title: "Recorded mileage", value: metrics.mileageStatement(locale: locale),
                     detail: [metrics.mileageCoverageStatement, metrics.mileagePartialExplanation].compactMap { $0 }.joined(separator: ". "),
                     isFigure: metrics.recordedDistance.isMeasured)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metrics.spokenMileageStatement(locale: locale))
            .accessibilityIdentifier("moneyMileage")
        rate(.perRecordedMile, identifier: "moneyMileRate")
        if let pay = metrics.recordedDeliveryEarnings {
            DashValueRow(title: "Recorded on deliveries", value: pay.formatted(locale: locale),
                         detail: metrics.deliveryEarningsCoverage.statement(noun: "finished delivery", pluralNoun: "finished deliveries")
                            + " with recorded pay, tips included",
                         keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metrics.spokenDeliveryEarningsStatement(locale: locale) ?? pay.formatted(locale: locale))
                .accessibilityIdentifier("moneyDeliveryEarnings")
            DashValueRow(title: "Additional tips on deliveries",
                         value: metrics.recordedAdditionalTips?.formatted(locale: locale) ?? "None recorded",
                         detail: metrics.recordedAdditionalTips == nil
                            ? "No additional tip on a delivery with recorded pay"
                            : "\(metrics.additionalTipsStatement(locale: locale) ?? ""). Part of the delivery amount above",
                         isFigure: metrics.recordedAdditionalTips != nil, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metrics.spokenAdditionalTipsStatement(locale: locale))
                .accessibilityIdentifier("moneyAdditionalTips")
        }
    }

    private func duration(_ title: String, spokenAs spokenTitle: String, _ value: TimeInterval?,
                          coverage: MetricCoverage, identifier: String) -> some View {
        DashValueRow(title: title, value: value.map(DurationText.short) ?? "Not measured",
                     detail: "\(coverage.statement(noun: "completed shift")) measured", isFigure: value != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value.map { "\(DurationText.spoken($0)) \(spokenTitle), \(coverage.spokenStatement())." }
                                ?? "No \(spokenTitle) measured \(coverage.spokenStatement(preposition: "in")).")
            .accessibilityIdentifier(identifier)
    }

    private func rate(_ kind: PeriodRateKind, identifier: String) -> some View {
        DashValueRow(title: kind.title, value: metrics.rateStatement(kind, locale: locale) ?? "Not available",
                     detail: metrics.rate(kind).isAvailable ? metrics.rateBasisStatement(kind) : kind.unavailableExplanation,
                     isFigure: metrics.rate(kind).isAvailable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metrics.spokenRateStatement(kind, locale: locale))
            .accessibilityIdentifier(identifier)
    }
}

// MARK: Activity

/// Recorded gross and recorded expenses across the selected period, as a chart
/// and as a list. The list is the chart's complete text alternative and the
/// only form at accessibility text sizes; each row opens that slice's report.
struct MoneyActivitySection: View {
    let activity: MoneyActivity
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let grossSeries = "Recorded gross"
    private static let expenseSeries = "Recorded expenses"

    var body: some View {
        let shown = activity.buckets(startedBy: now)
        Section {
            if !dynamicTypeSize.isAccessibilitySize, activity.hasChartableAmounts, !shown.isEmpty {
                chart(shown)
            }
            let recorded = activity.recordedBuckets
            if recorded.isEmpty {
                Text("Nothing recorded in any \(activity.granularity.noun) of this period.")
                    .dashFont(.body).foregroundStyle(.secondary)
            }
            ForEach(recorded) { bucket in
                NavigationLink { PeriodSummaryView(initialPeriod: bucket.period) } label: {
                    MoneyActivityRow(bucket: bucket, granularity: activity.granularity)
                }
                .accessibilityIdentifier("moneyActivityRow")
            }
        } header: { Text("By \(activity.granularity.noun)") } footer: {
            Text("Shifts count on the \(activity.granularity.noun) they started; expenses on their own dates, so a \(activity.granularity.noun) can hold expenses alone. Missing amounts leave a gap, a dot marks a recorded zero and a triangle marks partial earnings coverage. Open a \(activity.granularity.noun) for its full report.")
        }
    }

    private var chartUnit: Calendar.Component {
        switch activity.granularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    private var axisFormat: Date.FormatStyle {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return activity.granularity == .month ? base.month(.abbreviated) : base.month(.abbreviated).day()
    }

    private func chart(_ buckets: [MoneyActivityBucket]) -> some View {
        VStack(alignment: .leading, spacing: DashSpacing.md) {
            HStack(spacing: DashSpacing.lg) {
                legendEntry(Self.grossSeries, color: ShiftActivityPalette.accent)
                legendEntry(Self.expenseSeries, color: ShiftActivityPalette.estimateOutline)
            }
            .accessibilityHidden(true)
            Chart {
                ForEach(buckets) { bucket in
                    let label = bucket.period.rangeStatement(calendar: calendar, locale: locale)
                    if let gross = bucket.metrics.recordedGrossEarnings {
                        BarMark(x: .value("Date", bucket.period.start, unit: chartUnit), y: .value("Amount", chartValue(gross)))
                            .foregroundStyle(by: .value("Series", Self.grossSeries))
                            .position(by: .value("Series", Self.grossSeries))
                            .accessibilityLabel("\(label), recorded gross")
                            .accessibilityValue("\(gross.formatted(locale: locale)), \(bucket.metrics.earningsCoverage.spokenStatement())")
                        if gross.isZero || !bucket.metrics.earningsCoverage.isComplete {
                            PointMark(x: .value("Date", bucket.period.start, unit: chartUnit), y: .value("Amount", chartValue(gross)))
                                .symbol(gross.isZero ? BasicChartSymbolShape.circle : BasicChartSymbolShape.triangle)
                                .foregroundStyle(by: .value("Series", Self.grossSeries))
                                .position(by: .value("Series", Self.grossSeries))
                                .accessibilityHidden(true)
                        }
                    }
                    if let expenses = bucket.metrics.expenses.recordedTotal {
                        BarMark(x: .value("Date", bucket.period.start, unit: chartUnit), y: .value("Amount", chartValue(expenses)))
                            .foregroundStyle(by: .value("Series", Self.expenseSeries))
                            .position(by: .value("Series", Self.expenseSeries))
                            .accessibilityLabel("\(label), recorded expenses")
                            .accessibilityValue(expenses.formatted(locale: locale))
                        if expenses.isZero {
                            PointMark(x: .value("Date", bucket.period.start, unit: chartUnit), y: .value("Amount", 0))
                                .symbol(BasicChartSymbolShape.circle)
                                .foregroundStyle(by: .value("Series", Self.expenseSeries))
                                .position(by: .value("Series", Self.expenseSeries))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .chartForegroundStyleScale([Self.grossSeries: ShiftActivityPalette.accent,
                                        Self.expenseSeries: ShiftActivityPalette.estimateOutline])
            // Drawn outside the chart: the built-in legend inherits the
            // chart's accessibility label, so VoiceOver read each entry as the
            // whole chart.
            .chartLegend(.hidden)
            .chartXScale(domain: (buckets.first?.period.start ?? now)...(buckets.last?.period.end ?? now))
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: Money.displayCurrencyCode).notation(.compactName).precision(.fractionLength(0...1)))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat, collisionResolution: .greedy).foregroundStyle(.primary)
                }
            }
            .frame(height: 190)
            .accessibilityLabel("Recorded gross and recorded expenses by \(activity.granularity.noun). The list below states every amount.")
            .accessibilityIdentifier("moneyActivityChart")
            Text(activity.granularity == .day ? "USD" : "USD · each \(activity.granularity.noun) shown at its first day")
                .dashFont(.supporting).foregroundStyle(.secondary)
        }
        .padding(.vertical, DashSpacing.md)
    }

    private func legendEntry(_ title: String, color: Color) -> some View {
        HStack(spacing: DashSpacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).dashFont(.supporting).foregroundStyle(.secondary)
        }
    }

    /// Chart geometry only. Authoritative amounts and labels remain Decimal-backed Money.
    private func chartValue(_ money: Money) -> Double { NSDecimalNumber(decimal: money.amount).doubleValue }
}

/// One slice that holds a record: what was earned and spent, and on what basis.
struct MoneyActivityRow: View {
    let bucket: MoneyActivityBucket
    let granularity: MoneyActivityGranularity
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var metrics: PeriodMetrics { bucket.metrics }
    private var title: String { bucket.period.rangeStatement(calendar: calendar, locale: locale) }

    private var grossText: String? {
        guard !metrics.isEmpty else { return nil }
        return metrics.recordedGrossEarnings.map { "Gross \($0.formatted(locale: locale))" } ?? "Earnings not recorded"
    }

    private var expenseText: String? {
        metrics.expenses.recordedTotal.map { "Expenses \($0.formatted(locale: locale))" }
    }

    private var basis: String {
        guard !metrics.isEmpty else {
            return "Expenses only · \(metrics.expenseBasisStatement.lowercasedFirst)"
        }
        let shifts = "\(metrics.completedShiftCount) completed \(metrics.completedShiftCount == 1 ? "shift" : "shifts")"
        let coverage = metrics.earningsCoverage.isComplete ? nil : "earnings on \(metrics.earningsCoverage.statement())"
        return [shifts, coverage].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            Text(title).dashFont(.emphasis).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashSpacing.lg) { amounts }
                VStack(alignment: .leading, spacing: DashSpacing.xs) { amounts }
            }
            Text(basis).dashFont(.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DashSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, grossText, expenseText, basis].compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Opens this \(granularity.noun)'s report")
    }

    @ViewBuilder private var amounts: some View {
        if let grossText {
            Text(grossText).dashFont(.body).monospacedDigit()
                .foregroundStyle(metrics.recordedGrossEarnings == nil ? .secondary : .primary)
        }
        if let expenseText { Text(expenseText).dashFont(.body).monospacedDigit() }
    }
}

// MARK: Category breakdown

/// The selected period's recorded expenses by category, in the categories' own
/// order. Tapping a category filters the list below to it; tapping the
/// selected one shows every category again. It stays in place while a filter
/// applies, so choosing one never moves the list under the driver's finger.
struct MoneyCategoryBreakdown: View {
    let totals: [ExpenseCategoryTotal]
    let selected: ExpenseCategory?
    let statement: (ExpenseCategoryTotal) -> String
    let select: (ExpenseCategory?) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let maximum = totals.map(\.total).max() ?? .zero
        ForEach(totals) { total in
            let isSelected = selected == total.category
            Button { select(isSelected ? nil : total.category) } label: {
                VStack(alignment: .leading, spacing: DashSpacing.sm) {
                    DashValueRow(title: isSelected ? "\(total.category.title) · Showing" : total.category.title,
                                 value: total.total.formatted(locale: locale),
                                 detail: "\(total.recordCount) recorded \(total.recordCount == 1 ? "expense" : "expenses")",
                                 keepsFigureTogether: true)
                    if !dynamicTypeSize.isAccessibilitySize, maximum > .zero {
                        Chart {
                            BarMark(x: .value("Recorded expenses", chartValue(total.total)), y: .value("Category", total.category.title))
                                .foregroundStyle(isSelected ? ShiftActivityPalette.accent : ShiftActivityPalette.estimateOutline)
                        }
                        .chartXScale(domain: 0...chartValue(maximum)).chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: 10).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statement(total))
            .accessibilityHint(isSelected ? "Shows every category again" : "Shows only \(total.category.title) expenses")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("moneyCategory-\(total.category.rawValue)")
        }
    }

    private func chartValue(_ money: Money) -> Double { NSDecimalNumber(decimal: money.amount).doubleValue }
}

private extension String {
    /// "Recorded gross ..." becomes "recorded gross ..." inside a sentence.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
