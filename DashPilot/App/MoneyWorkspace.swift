import SwiftUI

/// Selected-period finances reuse the report loader, calculator, and expense editor.
/// Category selection affects only the rows and their explicitly filtered subtotal.
/// ``MoneyPeriodSelection`` decides the period from the calendar alone.
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
    @State private var hasRequestedFuel = false
    @State private var loader = PeriodLoadStore()
    @State private var retryRevision = 0
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

    var body: some View {
        List {
            Section {
                NavigationLink { InsightsView(initialPeriod: selection.insightsWeek(asOf: now, calendar: calendar)) } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis").frame(minHeight: 44)
                }
                .accessibilityIdentifier("insightsLink")
                presetMenu
                periodHeading
                Button { actions.editing = .new } label: {
                    Label("Add Expense", systemImage: "plus").dashFont(.emphasis).frame(minHeight: 44)
                }
                .accessibilityIdentifier("moneyAddExpenseButton")
            }
            if period == nil {
                Section { DashNotice(title: "This period is unavailable", message: "Check your calendar settings.", symbol: "calendar") }
            } else if let summary {
                overview(summary.metrics)
                expenseSection(summary)
                fuelSection(summary)
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
                Text("Explore days, weeks, months and custom dates. Compare previous periods and export your records from a summary.")
            }
        }
        .dashCanvas()
        .navigationTitle("Money")
        .workspaceDestinations()
        .modifier(ExpenseActionPresentation(actions: actions))
        .modifier(PeriodLoading(request: period.map {
            PeriodLoadRequest(period: $0, includesExpenseRows: true, includesFuelEstimates: hasRequestedFuel)
        }, store: loader, retryRevision: retryRevision))
        .sheet(isPresented: $isChoosingRange) {
            CustomRangeSheet(start: selection.customRange?.start ?? currentWeekStart,
                             end: selection.customRange?.lastInstant ?? now,
                             latestSelectableDay: now) { start, end in
                selection.selectCustom(from: start, through: end, calendar: calendar)
            }
        }
        .onChange(of: showsFuel) { _, expanded in if expanded { hasRequestedFuel = true } }
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
    }

    private var currentWeekStart: Date {
        ReportingPeriod(unit: .week, containing: now, calendar: calendar)?.start ?? now
    }

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

    private func overview(_ metrics: PeriodMetrics) -> some View {
        Section {
            DashMetric(value: metrics.recordedGrossEarnings?.formatted(locale: locale) ?? "Earnings not recorded",
                       label: "Recorded gross earnings",
                       detail: "Based on \(metrics.earningsCoverage.statement(noun: "completed shift"))",
                       isFigure: metrics.recordedGrossEarnings != nil, emphasis: .financial, keepsFigureTogether: true)
                .padding(.vertical, DashSpacing.md)
                .listRowBackground(ShiftActivityPalette.cloud)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("moneyGross")
            DashValueRow(title: "Recorded expenses",
                         value: metrics.expenses.recordedTotal?.formatted(locale: locale) ?? "No expenses recorded",
                         detail: metrics.expenseBasisStatement + ". Only costs you entered.",
                         isFigure: metrics.expenses.hasRecords, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metrics.spokenExpenseStatement(locale: locale))
                .accessibilityIdentifier("moneyExpenses")
            DashValueRow(title: metrics.netTitle, value: metrics.netStatement(locale: locale) ?? "Not available",
                         detail: metrics.netAfterRecordedExpenses.isAvailable
                            ? "\(metrics.netBasisStatement). \(metrics.netCautionStatement)"
                            : metrics.netUnavailableExplanation,
                         isFigure: metrics.netAfterRecordedExpenses.isAvailable, isProminent: true, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metrics.spokenNetStatement(locale: locale))
                .accessibilityIdentifier("moneyNet")
        } header: { Text("Selected \(noun)") }
    }

    private func expenseSection(_ summary: MoneyPeriodSummary) -> some View {
        let rows = summary.rows(in: category)
        return Section {
            Picker("Category", selection: $category) {
                Text("All expenses").tag(Optional<ExpenseCategory>.none)
                ForEach(ExpenseCategory.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .accessibilityIdentifier("moneyCategoryFilter")
            .accessibilityValue(category?.title ?? "All expenses")
            if let subtotal = summary.subtotal(in: category) {
                DashValueRow(title: category.map { "\($0.title) subtotal" } ?? "All categories subtotal",
                             value: subtotal.formatted(locale: locale),
                             detail: "Selected \(noun) · \(rows.count) recorded expenses", keepsFigureTogether: true)
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
            if category == nil, !summary.metrics.expenses.categoryTotals.isEmpty {
                DisclosureGroup("Category subtotals") {
                    ForEach(summary.metrics.expenses.categoryTotals) { total in
                        DashValueRow(title: total.category.title, value: total.total.formatted(locale: locale), keepsFigureTogether: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(summary.metrics.categoryStatement(total, locale: locale))
                    }
                }
            }
        } header: { Text("Expenses · Newest first") } footer: {
            Text("Filtering changes this list and subtotal. The overview always includes all recorded expenses in the selected \(noun).")
        }
    }

    private func fuelSection(_ summary: MoneyPeriodSummary) -> some View {
        let metrics = summary.metrics
        return Section {
            DisclosureGroup("Estimated fuel consumption", isExpanded: $showsFuel) {
                if !summary.includesFuelEstimates {
                    ProgressView("Loading fuel estimates…")
                } else {
                    DashValueRow(title: "Estimated fuel cost",
                                 value: metrics.fuel.estimatedCost?.formatted(locale: locale) ?? "Not available",
                                 detail: metrics.fuel.spokenStatement(locale: locale), isFigure: metrics.fuel.isAvailable, keepsFigureTogether: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(metrics.fuel.spokenStatement(locale: locale))
                        .accessibilityIdentifier("moneyEstimatedFuel")
                }
                Text("Uses recorded miles and each shift's saved vehicle assumptions. Recorded fuel purchases and estimated consumption are different views of cost. This estimate is never subtracted from net after recorded expenses.")
                    .dashFont(.supporting).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
