import SwiftUI

/// Selected-week finances reuse the report loader, calculator, and expense editor.
/// Category selection affects only the rows and their explicitly filtered subtotal.
struct MoneyWorkspace: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @State private var selectedWeek: Date?
    @State private var category: ExpenseCategory?
    @State private var showsFuel = false
    @State private var hasRequestedFuel = false
    @State private var loader = PeriodLoadStore()
    @State private var retryRevision = 0
    @State private var actions = ExpenseActions()

    private var period: ReportingPeriod? {
        ReportingPeriod(unit: .week, containing: selectedWeek ?? now, calendar: calendar)
    }
    private var summary: MoneyPeriodSummary? {
        guard case .loaded(let snapshot) = loader.state,
              snapshot.money?.metrics.period == period else { return nil }
        return snapshot.money
    }

    var body: some View {
        List {
            Section {
                NavigationLink { InsightsView(initialPeriod: period) } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis").frame(minHeight: 44)
                }
                .accessibilityIdentifier("insightsLink")
                weekSelector
                Button { actions.editing = .new } label: {
                    Label("Add Expense", systemImage: "plus").dashFont(.emphasis).frame(minHeight: 44)
                }
                .accessibilityIdentifier("moneyAddExpenseButton")
            }
            if period == nil {
                Section { DashNotice(title: "This week is unavailable", message: "Check your calendar settings.", symbol: "calendar") }
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
        .onChange(of: showsFuel) { _, expanded in if expanded { hasRequestedFuel = true } }
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
    }

    private var weekSelector: some View {
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            Text(period?.rangeStatement(calendar: calendar, locale: locale) ?? "Week unavailable")
                .dashFont(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("moneyDateRange")
            HStack {
                Button { selectedWeek = period?.previous(using: calendar)?.start } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(period == nil)
                .accessibilityLabel("Previous Money week")
                .accessibilityIdentifier("moneyPreviousWeek")
                Spacer(minLength: DashSpacing.xs)
                Button("This Week") { selectedWeek = nil }
                    .frame(minHeight: 44)
                    .disabled(selectedWeek == nil)
                    .accessibilityLabel("Show this week's finances")
                Spacer(minLength: DashSpacing.xs)
                Button { selectedWeek = period?.next(using: calendar)?.start } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(period == nil || period?.isCurrent(asOf: now) == true)
                .accessibilityLabel("Next Money week")
                .accessibilityIdentifier("moneyNextWeek")
            }
        }
        .padding(.vertical, DashSpacing.sm)
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
        } header: { Text("Selected week") }
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
                             detail: "Selected week · \(rows.count) recorded expenses", keepsFigureTogether: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("moneyFilteredSubtotal")
            }
            if rows.isEmpty {
                DashNotice(title: !summary.hasAnyExpense ? "No expenses recorded yet"
                           : summary.rows.isEmpty ? "No expenses this week" : "No expenses in this category",
                           message: "Add a cost you paid for, or explore another week.", symbol: "creditcard")
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
            Text("Filtering changes this list and subtotal. The overview always includes all recorded expenses in the selected week.")
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
