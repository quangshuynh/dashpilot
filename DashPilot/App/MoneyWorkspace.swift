import SwiftUI

/// Selected-period finances reuse the report loader, calculator, and expense editor.
/// Category selection affects only the rows and their explicitly filtered subtotal.
/// ``MoneyPeriodSelection`` decides the period from the calendar alone.
///
/// Two bounded reads serve the screen. The financial read (shifts and expenses
/// only) fills the summary, activity, comparison and expenses first. A second
/// read realizes deliveries and routes for delivery active time, recorded
/// mileage, the rates over them, delivery pay with tips and the fuel estimate,
/// and its section waits for it without holding up the figures above.
/// Each result is shown only for the period it was built for.
struct MoneyWorkspace: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var now = Date.now
    @State private var selection = MoneyPeriodSelection()
    @State private var isChoosingRange = false
    @State private var category: ExpenseCategory?
    @State private var showsFuel = false
    @State private var loader = PeriodLoadStore()
    @State private var detailLoader = PeriodLoadStore()
    @State private var retryRevision = 0
    @State private var detailRetryRevision = 0
    @State private var actions = ExpenseActions()

    private var period: ReportingPeriod? {
        selection.period(asOf: now, calendar: calendar)
    }
    private var preset: MoneyPeriodSelection.Preset? { selection.preset(asOf: now, calendar: calendar) }
    /// "week", "month" or "range", for sentences about the selection.
    private var noun: String { period?.unit.stepNoun ?? "period" }
    private var summary: MoneyPeriodSummary? {
        guard case .loaded(let snapshot) = loader.state,
              snapshot.money?.metrics.period == period else { return nil }
        return snapshot.money
    }
    /// Delivery and route figures, only ever for the period on screen.
    private var detail: PeriodMetrics? {
        guard case .loaded(let snapshot) = detailLoader.state,
              let current = snapshot.current, current.period == period else { return nil }
        return current
    }

    var body: some View {
        List {
            Section {
                presetMenu
                periodHeading
                if let period, period.contains(now) {
                    Text("\(period.unit == .custom ? "Range" : noun.capitalized) in progress. Only completed shifts contribute so far.")
                        .dashFont(.supporting).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("moneyInProgress")
                }
            }
            if period == nil {
                Section { DashNotice(title: "This period is unavailable", message: "Check your calendar settings.", symbol: "calendar") }
            } else if let summary {
                MoneySummarySection(metrics: summary.metrics, noun: noun)
                if !summary.metrics.hasAnyRecords {
                    Section {
                        DashNotice(title: "Nothing recorded in this \(noun)",
                                   message: "Completed shifts and expenses dated in this \(noun) appear here. Choose another period or add an expense.",
                                   symbol: "calendar")
                            .accessibilityIdentifier("moneyPeriodEmpty")
                    }
                } else {
                    workDetailSection(summary.metrics)
                    if let activity = summary.activity {
                        MoneyActivitySection(activity: activity, now: now)
                    }
                }
                expenseSection(summary)
                comparisonSection(summary)
                if !summary.metrics.isEmpty { fuelSection }
            } else if loader.state == .failed {
                PeriodLoadFailure(retry: { retryRevision += 1 })
            } else {
                Section { ProgressView("Loading financial records…").accessibilityIdentifier("moneyLoading") }
            }
            Section {
                NavigationLink(value: WorkspaceDestination.expenses) {
                    Label("All Recorded Expenses", systemImage: "creditcard").frame(minHeight: 44)
                }
                .accessibilityIdentifier("expensesLink")
                NavigationLink {
                    PeriodSummaryView(initialPeriod: period)
                } label: {
                    Label("Period Summaries", systemImage: "calendar").frame(minHeight: 44)
                }
                .accessibilityIdentifier("periodSummaryLink")
            } header: { Text("Financial history") } footer: {
                Text("Insights charts eight weeks at a time. Summaries explore days, weeks, months and custom dates, compare previous periods and export your records.")
            }
        }
        .dashCanvas()
        .navigationTitle("Money")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { InsightsView(initialPeriod: selection.insightsWeek(asOf: now, calendar: calendar)) } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                .accessibilityLabel("Insights")
                .accessibilityHint("Charts eight weeks of recorded history")
                .accessibilityIdentifier("insightsLink")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { actions.editing = .new } label: { Label("Add Expense", systemImage: "plus") }
                    .accessibilityLabel("Add Expense")
                    .accessibilityIdentifier("moneyAddExpenseButton")
            }
        }
        .workspaceDestinations()
        .modifier(ExpenseActionPresentation(actions: actions))
        .modifier(PeriodLoading(request: period.map {
            PeriodLoadRequest(period: $0, previous: $0.precedingEquivalent(using: calendar),
                              includesExpenseRows: true, activityCalendar: calendar)
        }, store: loader, retryRevision: retryRevision))
        .modifier(PeriodLoading(request: period.map {
            PeriodLoadRequest(period: $0, includesRouteDetails: true)
        }, store: detailLoader, retryRevision: detailRetryRevision))
        .sheet(isPresented: $isChoosingRange) {
            CustomRangeSheet(start: selection.customRange?.start ?? currentWeekStart,
                             end: selection.customRange?.lastInstant ?? now,
                             latestSelectableDay: now) { start, end in
                selection.selectCustom(from: start, through: end, calendar: calendar)
            }
        }
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
    }

    private var currentWeekStart: Date {
        ReportingPeriod(unit: .week, containing: now, calendar: calendar)?.start ?? now
    }

    // MARK: Period controls

    /// One native menu row. Each control below sits in its own row or uses a
    /// bordered style: a List row runs every plain button it holds on one tap,
    /// which is how Previous Week used to run This Week and Next Week as well.
    private var presetMenu: some View {
        Menu {
            ForEach(MoneyPeriodSelection.Preset.allCases) { option in
                Button { choose(option) } label: {
                    if option == preset { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
                .accessibilityIdentifier("moneyPreset-\(option.rawValue)")
            }
        } label: {
            LabeledContent("Period") {
                HStack(spacing: DashSpacing.xs) {
                    Text(preset?.title ?? "Earlier Week")
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Reporting period")
        .accessibilityValue(preset?.title ?? "Earlier week")
        .accessibilityIdentifier("moneyPeriodMenu")
    }

    /// Custom Range shows the dates already applied, or asks for some. Cancel
    /// leaves whatever was selected before.
    private func choose(_ option: MoneyPeriodSelection.Preset) {
        if option == .customRange, selection.customRange == nil {
            isChoosingRange = true
        } else {
            selection.select(option, asOf: now, calendar: calendar)
        }
    }

    /// Names the exact bounds every figure below describes. Week arrows appear
    /// only while a week is selected.
    @ViewBuilder
    private var periodHeading: some View {
        if selection.browsesWeeks {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DashSpacing.sm) {
                    periodLabel
                    HStack { previousButton; Spacer(minLength: DashSpacing.md); nextButton }
                }
            } else {
                HStack(spacing: DashSpacing.sm) { previousButton; periodLabel; nextButton }
            }
        } else {
            VStack(spacing: DashSpacing.sm) {
                periodLabel
                if preset == .customRange {
                    Button { isChoosingRange = true } label: {
                        Text("Change Dates").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Change custom date range")
                    .accessibilityIdentifier("moneyChangeDates")
                }
            }
        }
    }

    private var periodLabel: some View {
        VStack(spacing: DashSpacing.xs) {
            Text(periodTitle)
                .dashFont(.emphasis)
            Text(period?.rangeStatement(calendar: calendar, locale: locale) ?? "")
                .dashFont(.supporting).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenPeriod)
        .accessibilityIdentifier("moneyDateRange")
    }

    /// Last Week is named as the preset that chose it; every other title is
    /// the period's own, so a heading never claims a week the dates do not show.
    private var periodTitle: String {
        guard let period else { return "Period unavailable" }
        if preset == .lastWeek { return "Last Week" }
        return period.title(asOf: now, calendar: calendar, locale: locale)
    }

    private var spokenPeriod: String {
        guard let period else { return "Period unavailable" }
        let spoken = period.spokenTitle(asOf: now, calendar: calendar, locale: locale)
        return preset == .lastWeek ? "Last Week, \(period.rangeStatement(calendar: calendar, locale: locale))" : spoken
    }

    private var previousButton: some View {
        Button { selection.selectPrevious(asOf: now, calendar: calendar) } label: {
            Image(systemName: "chevron.left").frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .disabled(!selection.canSelectPrevious(asOf: now, calendar: calendar))
        .accessibilityLabel("Previous week")
        .accessibilityIdentifier("moneyPreviousWeek")
    }

    private var nextButton: some View {
        Button { selection.selectNext(asOf: now, calendar: calendar) } label: {
            Image(systemName: "chevron.right").frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .disabled(!selection.canSelectNext(asOf: now, calendar: calendar))
        .accessibilityLabel("Next week")
        .accessibilityIdentifier("moneyNextWeek")
    }

    // MARK: Time, distance and deliveries

    /// Figures that need deliveries and routes. Working time and the working
    /// hour rate are in the summary already, from the financial read.
    @ViewBuilder
    private func workDetailSection(_ financial: PeriodMetrics) -> some View {
        if !financial.isEmpty {
            Section {
                if let detail {
                    MoneyWorkDetailRows(metrics: detail)
                } else if detailLoader.state == .failed {
                    DashNotice(title: "Couldn't load time and mileage", message: "The figures above are unaffected.",
                               symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    Button("Try Again") { detailRetryRevision += 1 }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Try loading time and mileage again")
                        .accessibilityIdentifier("moneyDetailRetry")
                } else {
                    ProgressView("Loading time and mileage…").accessibilityIdentifier("moneyDetailLoading")
                }
            } header: { Text("Time, distance and deliveries") } footer: {
                Text("Delivery active time counts overlapping deliveries once. Recorded mileage is the distance your accepted route samples support, not necessarily everything you drove. Delivery records are independent of shift gross and are never added to it.")
            }
        }
    }

    // MARK: Comparison

    @ViewBuilder
    private func comparisonSection(_ summary: MoneyPeriodSummary) -> some View {
        if let comparison = summary.comparison(asOf: now, calendar: calendar),
           comparison.current.hasAnyRecords || comparison.previousHasRecords {
            Section {
                Text(comparison.previousPeriodStatement(asOf: now, calendar: calendar, locale: locale))
                    .dashFont(.emphasis)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("moneyComparisonPrevious")
                if let note = comparison.inProgressStatement { Text(note).dashFont(.body).fixedSize(horizontal: false, vertical: true) }
                if let note = comparison.previousEmptyStatement { Text(note).dashFont(.body).fixedSize(horizontal: false, vertical: true) }
                // Against a period with nothing recorded every row would read
                // "compared with Not recorded"; the statement above says it once.
                if comparison.previousHasRecords {
                    FinancialComparisonRows(comparison: comparison, identifierPrefix: "moneyComparison")
                }
            } header: { Text(comparison.title) } footer: {
                Text(comparison.cautionStatement)
            }
        }
    }

    // MARK: Expenses

    private func expenseSection(_ summary: MoneyPeriodSummary) -> some View {
        let rows = summary.rows(in: category)
        return Section {
            if category == nil, !summary.metrics.expenses.categoryTotals.isEmpty {
                MoneyCategoryBreakdown(totals: summary.metrics.expenses.categoryTotals,
                                       statement: { summary.metrics.categoryStatement($0, locale: locale) }) { category = $0 }
            }
            Picker("Category", selection: $category) {
                Text("All expenses").tag(Optional<ExpenseCategory>.none)
                ForEach(ExpenseCategory.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .accessibilityIdentifier("moneyCategoryFilter")
            .accessibilityValue(category?.title ?? "All expenses")
            if let subtotal = summary.subtotal(in: category) {
                DashValueRow(title: category.map { "\($0.title) subtotal" } ?? "All categories subtotal",
                             value: subtotal.formatted(locale: locale),
                             detail: "Selected \(noun) · \(rows.count) recorded \(rows.count == 1 ? "expense" : "expenses")", keepsFigureTogether: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("moneyFilteredSubtotal")
            }
            if rows.isEmpty {
                DashNotice(title: !summary.hasAnyExpense ? "No expenses recorded yet"
                           : summary.rows.isEmpty ? "No expenses in this \(noun)" : "No expenses in this category",
                           message: "Add a cost you paid for, or choose another period.", symbol: "creditcard")
                    .accessibilityIdentifier("moneyExpensesEmpty")
                if category != nil {
                    Button("Clear Filter") { category = nil }.frame(minHeight: 44)
                        .accessibilityIdentifier("moneyClearFilter")
                }
            }
            ForEach(rows) { row in ExpenseRecordButton(row: row, actions: actions) }
        } header: { Text("Expenses · Newest first") } footer: {
            Text("Filtering changes this list and subtotal. The summary always includes all recorded expenses in the selected \(noun). Only costs you entered appear; estimated fuel is separate.")
        }
    }

    private var fuelSection: some View {
        Section {
            DisclosureGroup("Estimated fuel consumption", isExpanded: $showsFuel) {
                if let detail {
                    DashValueRow(title: "Estimated fuel cost",
                                 value: detail.fuel.estimatedCost?.formatted(locale: locale) ?? "Not available",
                                 detail: detail.fuel.spokenStatement(locale: locale), isFigure: detail.fuel.isAvailable, keepsFigureTogether: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(detail.fuel.spokenStatement(locale: locale))
                        .accessibilityIdentifier("moneyEstimatedFuel")
                } else {
                    ProgressView("Loading fuel estimates…")
                }
                Text("Uses recorded miles and each shift's saved vehicle assumptions. Recorded fuel purchases and estimated consumption are different views of cost. This estimate is never subtracted from net after recorded expenses.")
                    .dashFont(.supporting).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
