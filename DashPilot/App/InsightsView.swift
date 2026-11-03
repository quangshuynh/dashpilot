import Charts
import SwiftUI

/// A bounded financial history inside Money. Standard controls and readable rows
/// provide every chart value without requiring a chart gesture.
struct InsightsView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var now = Date.now
    @State private var navigation: InsightsNavigation
    @State private var metric = InsightsMetric.earnings
    @State private var loader = PeriodLoadStore()
    @State private var retryRevision = 0

    init(initialPeriod: ReportingPeriod? = nil) {
        let now = Date.now
        _now = State(initialValue: now)
        // A historical Money selection stays fixed. The latest range follows
        // calendar changes, rather than freezing the week when Insights opened.
        _navigation = State(initialValue: InsightsNavigation(initialPeriod: initialPeriod, asOf: now))
    }

    private var window: InsightsWindow? { navigation.window(asOf: now, calendar: calendar) }
    /// Decided by the calendar, so the week controls never wait for a load.
    private var selectedPeriod: ReportingPeriod? { navigation.selectedPeriod(asOf: now, calendar: calendar) }
    /// Loaded figures, only ever for the window on screen.
    private var series: InsightsSeries? {
        guard case .loaded(let snapshot) = loader.state else { return nil }
        return snapshot.insights?.showing(window)
    }
    private var selected: InsightsWeek? {
        series?.weeks.first { $0.period == selectedPeriod }
    }

    var body: some View {
        List {
            if let window, let selectedPeriod {
                rangeSection(window)
                weekSection(window, selectedPeriod: selectedPeriod)
                if let series, let selected {
                    if series.hasRecords {
                        trendSection(series, selected: selected)
                        expenseSection(selected)
                        comparisonSection(selected)
                        Section {
                            Text("Completed shifts belong to the week they started. Expenses belong to their recorded dates. Pauses are excluded from working time. Corrections update this history.")
                            Text("Shift gross and delivery gross are independent. Only shift gross appears here. These records describe past work, not future earnings.")
                            Text("Open the selected week report for recorded mileage, delivery history, saved hourly target context and export options.")
                        } header: { Text("About these records") }
                            .dashFont(.body)
                    }
                } else if loader.state == .failed {
                    PeriodLoadFailure { retryRevision += 1 }
                }
            } else {
                Section { Text("This reporting range is unavailable. Check your calendar settings.") }
            }
        }
        .dashCanvas()
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(PeriodLoading(request: window.map {
            PeriodLoadRequest(period: $0.fetchPeriod, insightsWindow: $0)
        }, store: loader, retryRevision: retryRevision))
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now; retryRevision += 1 }
    }

    private func rangeSection(_ window: InsightsWindow) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DashSpacing.md) {
                Text("Eight weeks of history").dashFont(.title)
                Text("Monday through Sunday").dashFont(.body).foregroundStyle(.secondary)
                if let first = window.weeks.first, let last = window.weeks.last {
                    Text((first.start..<last.lastInstant).formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)))
                        .dashFont(.supporting).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("insightsRange")
                }
            }
            .padding(.vertical, DashSpacing.md)
            .listRowBackground(ShiftActivityPalette.cloud)
            pairedControls {
                Button {
                    navigation.showEarlierWeeks(asOf: now, calendar: calendar)
                } label: { navigationLabel("Earlier Weeks", symbol: "chevron.left") }
                .accessibilityLabel("Earlier weeks")
                .accessibilityHint("Shows the eight weeks before these")
                .accessibilityIdentifier("insightsEarlierWeeks")
            } trailing: {
                Button { navigation.showLatestWeeks() } label: {
                    navigationLabel("Latest Weeks", symbol: nil, trailing: true)
                }
                .disabled(!navigation.canShowLatestWeeks(asOf: now, calendar: calendar))
                .accessibilityIdentifier("insightsLatestWeeks")
            }
        }
    }

    /// The selected week and the controls that move it. Drawn from the
    /// calendar alone, so they are present while figures load, after a refresh
    /// and for weeks with nothing recorded.
    private func weekSection(_ window: InsightsWindow, selectedPeriod: ReportingPeriod) -> some View {
        Section {
            Menu {
                Picker("Selected week", selection: Binding(
                    get: { selectedPeriod.start },
                    set: { navigation.select($0, asOf: now, calendar: calendar) }
                )) {
                    ForEach(window.weeks.reversed(), id: \.start) { week in
                        Text(week.rangeStatement(calendar: calendar, locale: locale)).tag(week.start)
                    }
                }
            } label: {
                menuLabel("Selected week", value: selectedPeriod.rangeStatement(calendar: calendar, locale: locale))
            }
            .accessibilityLabel("Selected week")
            .accessibilityValue(selectedPeriod.rangeStatement(calendar: calendar, locale: locale))
            .accessibilityIdentifier("insightsWeekPicker")
            pairedControls {
                Button {
                    navigation.selectPrevious(asOf: now, calendar: calendar)
                } label: { navigationLabel("Previous Week", symbol: "chevron.left") }
                .disabled(!navigation.canSelectPrevious(asOf: now, calendar: calendar))
                .accessibilityIdentifier("insightsPreviousWeek")
            } trailing: {
                Button {
                    navigation.selectNext(asOf: now, calendar: calendar)
                } label: { navigationLabel("Next Week", symbol: "chevron.right", trailing: true) }
                .disabled(!navigation.canSelectNext(asOf: now, calendar: calendar))
                .accessibilityIdentifier("insightsNextWeek")
            }
            if selectedPeriod.contains(now) {
                Text("Week in progress. Only completed shifts contribute so far.")
                    .dashFont(.body).accessibilityIdentifier("insightsInProgress")
            }
            if let series, let selected {
                if series.hasRecords {
                    metricRow(selected, identifier: "insightsSelectedValue")
                    DashValueRow(title: "Working time", value: selected.metrics.workingDuration.map(DurationText.short) ?? "Not recorded",
                                 detail: selected.metrics.workingCoverage.statement(noun: "completed shift") + ". Pauses excluded.")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Working time, \(selected.metrics.workingDuration.map(DurationText.spoken) ?? "not recorded"). \(selected.metrics.workingCoverage.statement(noun: "completed shift")). Pauses excluded.")
                    NavigationLink { PeriodSummaryView(initialPeriod: selected.period) } label: {
                        Label("Open Selected Week Report", systemImage: "calendar")
                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("insightsReportLink")
                } else {
                    DashNotice(title: "No records in these weeks", message: "Completed shifts and dated expenses appear here when you record them. Explore earlier weeks or return to Money to add an expense.", symbol: "chart.bar")
                        .accessibilityIdentifier("insightsEmpty")
                }
            } else if loader.state != .failed {
                ProgressView("Loading weekly history…")
                    .accessibilityIdentifier("insightsLoading")
            }
        } header: { Text("Selected week") }
    }

    /// Two controls side by side where both labels fit on one line each, and
    /// stacked where they do not, so neither label wraps mid-word on a narrow
    /// screen or at a large text size.
    private func pairedControls<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leading = leading()
        let trailing = trailing()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DashSpacing.md) {
                leading.lineLimit(1)
                Spacer(minLength: DashSpacing.md)
                trailing.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: DashSpacing.md) {
                leading
                trailing
            }
        }
        .frame(minHeight: 44)
        .buttonStyle(.borderless)
    }

    @ViewBuilder private func navigationLabel(_ title: String, symbol: String?, trailing: Bool = false) -> some View {
        if typeSize.isAccessibilitySize || symbol == nil {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
        } else if let symbol, trailing {
            HStack(spacing: DashSpacing.sm) {
                Text(title)
                Image(systemName: symbol).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        } else if let symbol {
            Label(title, systemImage: symbol)
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    private func menuLabel(_ title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: DashSpacing.lg) {
            VStack(alignment: .leading, spacing: DashSpacing.sm) {
                Text(title).dashFont(.supporting).foregroundStyle(.secondary)
                Text(value).dashFont(.emphasis).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func trendSection(_ series: InsightsSeries, selected: InsightsWeek) -> some View {
        Section {
            Menu {
                Picker("Trend", selection: $metric) {
                    ForEach(InsightsMetric.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                menuLabel("Trend", value: metric.title)
            }
            .accessibilityLabel("Trend")
            .accessibilityValue(metric.title)
            .accessibilityIdentifier("insightsMetricPicker")
            if !typeSize.isAccessibilitySize {
                if series.weeks.contains(where: { metric.amount($0) != nil }) {
                    trendChart(series, selected: selected)
                } else {
                    Text(metric == .earnings ? "No shift earnings recorded in these weeks." : "No week has both recorded shift earnings and valid positive working time.")
                        .dashFont(.body).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Read All Weekly Values") { weeklyValues(series) }
                .accessibilityIdentifier("insightsAllValues")
        } header: { Text(metric.title) } footer: {
            Text(metric.explanation)
        }
    }

    private func metricRow(_ week: InsightsWeek, identifier: String) -> some View {
        let amount = metric.amount(week)
        return DashValueRow(title: metric.title, value: amount?.formatted(locale: locale) ?? metric.absentStatement,
                            detail: metric.coverageStatement(week), isFigure: amount != nil,
                            isProminent: true, keepsFigureTogether: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metric.title), \(amount?.formatted(locale: locale) ?? metric.absentStatement). \(metric.coverageStatement(week))")
            .accessibilityIdentifier(identifier)
    }

    private func weeklyValues(_ series: InsightsSeries) -> some View {
        ForEach(series.weeks.reversed()) { week in
            VStack(alignment: .leading, spacing: DashSpacing.sm) {
                Text(week.period.rangeStatement(calendar: calendar, locale: locale)).dashFont(.emphasis)
                Text(metric.amount(week)?.formatted(locale: locale) ?? metric.absentStatement).monospacedDigit()
                Text(metric.coverageStatement(week)).dashFont(.supporting).foregroundStyle(.secondary)
                if week.period.contains(now) { Text("Week in progress").dashFont(.supporting) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(week.period.rangeStatement(calendar: calendar, locale: locale)). \(metric.title), \(metric.amount(week)?.formatted(locale: locale) ?? metric.absentStatement). \(metric.coverageStatement(week)) \(week.period.contains(now) ? "Week in progress." : "")")
        }
    }

    /// The chart's category for a week: unique within any eight weeks.
    private func key(_ week: InsightsWeek) -> String { key(forStart: week.id) }

    private func trendChart(_ series: InsightsSeries, selected: InsightsWeek) -> some View {
        let labels = InsightsAxisLabels.labels(for: series.weeks.map(\.period), calendar: calendar, locale: locale)
        let labelled = Dictionary(uniqueKeysWithValues: labels.map { (key(forStart: $0.week.start), $0.label) })
        return VStack(alignment: .leading, spacing: DashSpacing.md) {
            Chart {
                // A band behind the selected week, so the selection is visible
                // even where its amount is zero or missing.
                RectangleMark(x: .value("Week starting", key(selected)))
                    .foregroundStyle(ShiftActivityPalette.accent.opacity(0.14))
                    .accessibilityHidden(true)
                ForEach(series.weeks) { week in
                if let amount = metric.amount(week) {
                    BarMark(x: .value("Week starting", key(week)), y: .value(metric.title, chartValue(amount)))
                        .foregroundStyle(ShiftActivityPalette.accent)
                        // The selected week stays at full strength; the rest
                        // recede, so the chart shows which bar the values
                        // below describe. Shape and position are unchanged.
                        .opacity(week.id == selected.id ? 1 : 0.55)
                        .accessibilityLabel(week.period.rangeStatement(calendar: calendar, locale: locale))
                        .accessibilityValue("\(amount.formatted(locale: locale)). \(metric.coverageStatement(week))")
                    if amount.isZero || !metric.coverage(week).isComplete {
                        PointMark(x: .value("Week starting", key(week)), y: .value(metric.title, chartValue(amount)))
                            .symbol(amount.isZero ? BasicChartSymbolShape.circle : BasicChartSymbolShape.triangle)
                            .foregroundStyle(ShiftActivityPalette.accent)
                            .accessibilityHidden(true)
                    }
                }
                }
            }
            .chartXScale(domain: series.weeks.map(key))
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: Money.displayCurrencyCode).notation(.compactName).precision(.fractionLength(0...2)))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: labels.map { key(forStart: $0.week.start) }) { value in
                    AxisValueLabel(collisionResolution: .greedy) {
                        if let key = value.as(String.self), let label = labelled[key] {
                            Text(label).lineLimit(1).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("\(metric.title), eight weekly values. Use Selected week or Read All Weekly Values for exact amounts and coverage.")
            .accessibilityIdentifier("insightsTrendChart")
            Text("Week starting · USD\(metric == .hourly ? " per working hour" : "")")
                .dashFont(.supporting).foregroundStyle(.secondary)
            Text("Triangle: partial coverage. Dot at zero: recorded zero. A blank week has no qualifying amount. The shaded week is the selected week. Read all weekly values below for coverage.")
                .dashFont(.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DashSpacing.md)
    }

    private func key(forStart start: Date) -> String {
        start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
    }

    private func expenseSection(_ week: InsightsWeek) -> some View {
        Section {
            DashValueRow(title: "Selected week's recorded expenses",
                         value: week.metrics.expenses.recordedTotal?.formatted(locale: locale) ?? "No expenses recorded",
                         detail: expenseCountStatement(week.metrics.expenses.recordCount) + ". Only costs you entered.",
                         isFigure: week.metrics.expenses.hasRecords, keepsFigureTogether: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insightsExpenseTotal")
            ForEach(week.rankedExpenses) { total in
                VStack(alignment: .leading, spacing: DashSpacing.md) {
                    DashValueRow(title: total.category == .fuel ? "Fuel, including charging" : total.category.title,
                                 value: total.total.formatted(locale: locale),
                                 detail: expenseCountStatement(total.recordCount), keepsFigureTogether: true)
                    if !typeSize.isAccessibilitySize, let maximum = week.rankedExpenses.first?.total, maximum > .zero {
                        Chart {
                            BarMark(x: .value("Recorded expenses", chartValue(total.total)), y: .value("Category", total.category.title))
                                .foregroundStyle(ShiftActivityPalette.accent)
                        }
                        .chartXScale(domain: 0...chartValue(maximum)).chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: 12).accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("Recorded expense breakdown") } footer: {
            Text("Categories are ordered by recorded amount. Categories without entries are omitted, not treated as zero. No entered expenses does not mean no spending. Estimated fuel is separate.")
        }
    }

    @ViewBuilder private func comparisonSection(_ week: InsightsWeek) -> some View {
        if let comparison = week.comparison(asOf: now, calendar: calendar) {
            Section {
                Text("Selected week compared with \(week.previous.period.rangeStatement(calendar: calendar, locale: locale))")
                    .dashFont(.emphasis)
                if let note = comparison.inProgressStatement { Text(note).dashFont(.body) }
                if let note = comparison.previousEmptyStatement { Text(note).dashFont(.body) }
                ForEach(comparison.entries.filter { [.recordedGrossEarnings, .workingTime, .rate(.perWorkingHour), .recordedExpenses].contains($0.metric) }) { entry in
                    VStack(alignment: .leading, spacing: DashSpacing.sm) {
                        Text(entry.metric.title).dashFont(.emphasis)
                        Text(entry.valuesStatement(locale: locale)).monospacedDigit()
                        if !comparison.isCurrentPeriodInProgress, let change = entry.changeStatement(locale: locale) {
                            Text([change, entry.percentStatement(locale: locale)].compactMap { $0 }.joined(separator: " · "))
                        }
                        if let basis = entry.basisStatement { Text(basis).dashFont(.supporting) }
                        if let refusal = entry.refusalStatement(noun: "week"), entry.percentageRefusal != .currentPeriodInProgress {
                            Text(refusal).dashFont(.supporting).foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            } header: { Text("Previous week") } footer: {
                Text("Differences describe entered records. Coverage can change after corrections. Recorded expenses have no known completeness, so no expense percentage is shown.")
            }
        }
    }

    /// Chart geometry only. Authoritative amounts and labels remain Decimal-backed Money.
    private func chartValue(_ money: Money) -> Double { NSDecimalNumber(decimal: money.amount).doubleValue }

    private func expenseCountStatement(_ count: Int) -> String {
        "\(count) recorded \(count == 1 ? "expense" : "expenses")"
    }
}

private enum InsightsMetric: String, CaseIterable, Identifiable {
    case earnings, hourly
    var id: String { rawValue }
    var title: String { self == .earnings ? "Recorded gross earnings" : "Gross per working hour" }
    var absentStatement: String { self == .earnings ? "Earnings not recorded" : "Not available" }
    func amount(_ week: InsightsWeek) -> Money? {
        self == .earnings ? week.metrics.recordedGrossEarnings : week.metrics.grossPerWorkingHour.amount
    }
    func coverage(_ week: InsightsWeek) -> MetricCoverage {
        self == .earnings ? week.metrics.earningsCoverage : week.metrics.grossPerWorkingHour.coverage
    }
    func coverageStatement(_ week: InsightsWeek) -> String {
        let coverage = coverage(week)
        let basis = coverage.statement(noun: "completed shift")
        let status = coverage.hasContributors && !coverage.isComplete ? "Partial coverage. " : ""
        return status + basis + (self == .hourly ? " with earnings and valid positive working time." : " with recorded earnings.")
    }
    var explanation: String {
        self == .earnings
            ? "Recorded completed-shift gross only. Missing earnings stay missing; recorded zero remains a value. Running shifts are excluded."
            : "Recorded gross divided by working hours from the same qualifying shifts. This is not an average of shift rates. Missing earnings and invalid or zero working time do not contribute."
    }
}
