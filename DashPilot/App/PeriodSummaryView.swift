import SwiftData
import SwiftUI

/// What the completed shifts of one day, week, month or chosen date range add
/// up to.
///
/// ## What this screen is for
///
/// Answering *"what do the records DashPilot actually has say about this
/// period?"* — never *"what happened this week"*. Every figure here is followed
/// by the shifts it came from, because a subtotal over three of four shifts read
/// as a week's earnings is the one way this screen could lie.
///
/// ## Where the work happens
///
/// Nothing is calculated in this view. ``PeriodMetricsCalculator`` owns every
/// rule, including which figures exist at all; this reads the store, hands over
/// plain records, and writes down the result.
///
/// The four period lengths differ **only** in which shifts they select. A month
/// is not summarised from its weeks and a range is not summarised from its days:
/// each one hands the same calculator the underlying shift records it contains,
/// so a month's per-hour rate is its own amounts over its own hours rather than
/// an average of smaller periods' rates.
///
/// The routes are measured in a task rather than in `body`, for the reason the
/// history row measures in one: a week can hold several shifts and each holds
/// thousands of positions. The arithmetic over the measured result stays in the
/// body, which is what keeps the summary correct the moment a driver edits an
/// amount and comes back.
///
/// ## The period before this one
///
/// The comparison section reads the equivalent period immediately before the
/// selected one through the **same** calculator, over the same records, and
/// hands the two finished results to ``PeriodComparisonCalculator``. There is
/// one aggregation on this screen; the comparison is not a second one, and every
/// figure in it is the figure above it. Measuring both periods' routes is what
/// makes that true and is why a selection costs two measurements.
struct PeriodSummaryView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    /// Every completed shift. The period's own shifts are selected from these by
    /// ``ReportingPeriod/contains(_:)``, which is also the rule the calculator
    /// applies — this filter exists to avoid measuring routes the period will
    /// not use, not to decide membership.
    @Query(filter: #Predicate<Shift> { $0.endedAt != nil }, sort: \Shift.startedAt, order: .reverse)
    private var completedShifts: [Shift]

    /// Every recorded expense. Selected into the period by its **own** date, by
    /// the same half-open rule a shift is selected by — an expense belongs to no
    /// shift, so nothing here reads one through the work.
    ///
    /// Unfiltered by the query for the reason the shifts are: the calculator
    /// applies the membership rule, and reading them all costs nothing to
    /// measure.
    @Query(sort: \Expense.occurredAt, order: .reverse)
    private var recordedExpenses: [Expense]

    @State private var unit: ReportingPeriodUnit = .day

    /// A moment inside the selected calendar period. Stepping moves this to the
    /// neighbouring period's start, so the selection survives a 23- or 25-hour
    /// day, and a 28- or 31-day month, without any arithmetic on seconds here.
    @State private var anchor = Date.now

    /// What "now" is, for naming the period and for refusing a selection in the
    /// future.
    ///
    /// Read when the screen appears and again whenever the app returns to the
    /// foreground, rather than continuously: which period is "current" must not
    /// change under the driver mid-read, but it must not be wrong either. A
    /// summary opened before midnight and returned to after one held a "now"
    /// from the previous day, which called yesterday `Today`, disabled the step
    /// forward because the day on screen still looked current, and refused
    /// today as the end of a custom range. A driver on a long shift is exactly
    /// the person that happens to.
    ///
    /// Only the naming moves. The period on screen stays the one the driver was
    /// reading, so nothing they were looking at is swapped out; it is simply
    /// named correctly, and the step to the new current period becomes
    /// available.
    @State private var now = Date.now

    /// The custom range's two **inclusive** dates.
    ///
    /// Held here rather than in the sheet so switching to Day and back returns
    /// to the range the driver chose. Deliberately not persisted: a saved report
    /// is a feature with its own questions — naming, staleness, migration — and
    /// this interval does not answer them.
    @State private var customStart = Date.now
    @State private var customEnd = Date.now

    /// Whether the range selector is open.
    @State private var isChoosingRange = false

    /// Whether the custom range has been given its opening dates yet.
    @State private var hasSeededCustomRange = false

    /// The measured routes, and the selection they were measured for.
    @State private var measurement: RouteMeasurement?

    /// Exporting the selected period. The sheet writes the file when it opens,
    /// so this stays false until the driver asks.
    @State private var isExporting = false

    private let calculator = PeriodMetricsCalculator()

    /// The comparison between the selected period and the one before it. It
    /// aggregates nothing: it is handed the two results the calculator above
    /// produced.
    private let comparisons = PeriodComparisonCalculator()

    var body: some View {
        List {
            Section {
                periodSelector
            }

            if period == nil {
                // Only reachable if the calendar cannot describe the selection
                // at all. Said plainly rather than left as a spinner that never
                // resolves, and it names the one control that can fix it.
                Section {
                    Text("This selection cannot be summarised. Choose different dates.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("periodUnavailable")
                }
            } else if let metrics {
                if metrics.isEmpty {
                    emptySection(metrics)
                    // A period with no completed shift can still hold recorded
                    // costs: a driver can buy fuel on a day off. Dropping the
                    // section here would hide a record they entered behind a
                    // sentence about shifts.
                    if metrics.expenses.hasRecords {
                        expensesSection(metrics)
                    }
                } else {
                    summarySection(metrics)
                    earningsSection(metrics)
                    expensesSection(metrics)
                    drivingSection(metrics)
                    deliveriesSection(metrics)
                }
                // Last of the figures, and shown for an empty period too when
                // the one before it holds something: a day with no records is
                // one of the things a driver may be looking at the previous day
                // to understand.
                if let comparison, comparison.current.hasAnyRecords || comparison.previousHasRecords {
                    comparisonSection(comparison)
                }
                // Only for a period that holds something. A period with neither
                // a completed shift nor an expense has nothing to export, and an
                // export control over an empty state is an offer the app would
                // have to refuse.
                if metrics.hasAnyRecords {
                    exportSection
                }
            } else {
                Section {
                    Text("Working out this period…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: measurementToken) { measureRoutes() }
        .onAppear(perform: seedCustomRangeIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            // `.inactive` is deliberately not included, for the reason
            // `RootView` ignores it: the app switcher and a call banner are not
            // the driver leaving, and re-reading the clock for one of them could
            // rename the period they are mid-way through reading.
            if phase == .active { now = .now }
        }
        // On the list rather than on the section that presents it: the sections
        // are rebuilt whenever the routes are re-measured, and a sheet attached
        // to one that briefly disappears goes with it.
        .sheet(isPresented: $isExporting) {
            if let period {
                ShiftExportSheet(scope: .period(period))
            }
        }
        .sheet(isPresented: $isChoosingRange) {
            CustomRangeSheet(
                start: customStart,
                end: customEnd,
                latestSelectableDay: now
            ) { start, end in
                customStart = start
                customEnd = end
            }
        }
    }

    // MARK: Period selection

    private var periodSelector: some View {
        VStack(spacing: 12) {
            // Four short words still fit one segmented row on the narrowest
            // iPhone, and keeping them in one row is what stops Month and
            // Custom looking like a different kind of choice from Day and Week.
            // They are all the same choice: how much history to look at.
            Picker("Period", selection: $unit) {
                ForEach(ReportingPeriodUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("periodUnitPicker")

            if unit.isCalendarPeriod {
                steppingHeader
            } else {
                chosenRangeHeader
            }
        }
        .padding(.vertical, 4)
    }

    /// A calendar period: its name, with a step to either neighbour.
    private var steppingHeader: some View {
        HStack {
            stepButton(
                systemImage: "chevron.left",
                label: "Previous \(unit.stepNoun)",
                identifier: "periodPreviousButton",
                destination: period?.previous(using: calendar)
            )

            Spacer(minLength: 8)

            periodTitleLabel

            Spacer(minLength: 8)

            stepButton(
                systemImage: "chevron.right",
                label: "Next \(unit.stepNoun)",
                identifier: "periodNextButton",
                // Nothing is offered beyond the period the driver is in.
                // A future week or month holds no records, and an empty state
                // for one is a screen that looks broken rather than
                // informative.
                destination: isCurrent ? nil : period?.next(using: calendar)
            )
        }
    }

    /// A range the driver chose: its dates, and the way back to the picker.
    ///
    /// No chevrons. A custom range has no neighbour to step to — the range after
    /// *Sep 1–7* is not a thing the driver asked for — and offering one would
    /// invent a period nobody selected.
    private var chosenRangeHeader: some View {
        VStack(spacing: 10) {
            periodTitleLabel

            Button {
                isChoosingRange = true
            } label: {
                Label("Choose Dates", systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Choose custom date range")
            .accessibilityIdentifier("periodCustomRangeButton")
        }
    }

    private var periodTitleLabel: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let period {
                Text(period.rangeStatement(calendar: calendar, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenTitle)
        .accessibilityIdentifier("periodTitle")
    }

    private func stepButton(
        systemImage: String,
        label: String,
        identifier: String,
        destination: ReportingPeriod?
    ) -> some View {
        Button {
            if let destination { anchor = destination.start }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                // A comfortable target: this is a control a driver taps
                // repeatedly while reading, and a bare chevron is a small one.
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .disabled(destination == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Sections

    private func emptySection(_ metrics: PeriodMetrics) -> some View {
        Section {
            // Deliberately not a grid of zeroes. A week nobody drove is a week
            // with no records, not a week of no earnings and no miles.
            Text(metrics.emptyStatement)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("periodEmptyState")
        }
    }

    private func summarySection(_ metrics: PeriodMetrics) -> some View {
        Section {
            LabeledContent("Completed shifts") {
                Text("\(metrics.completedShiftCount)").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(metrics.shiftCountStatement)
            .accessibilityIdentifier("periodShiftCount")

            durationRow(
                "Working",
                spokenAs: "working shift time",
                duration: metrics.workingDuration,
                coverage: metrics.workingCoverage,
                identifier: "periodWorkingTime"
            )
            durationRow(
                "Delivery active",
                spokenAs: "delivery active time",
                duration: metrics.deliveryActiveDuration,
                coverage: metrics.deliveryActiveCoverage,
                identifier: "periodDeliveryActiveTime"
            )
            durationRow(
                "Non-delivery",
                spokenAs: "non-delivery time",
                duration: metrics.nonDeliveryDuration,
                coverage: metrics.nonDeliveryCoverage,
                identifier: "periodNonDeliveryTime"
            )
        } header: {
            Text("Summary")
        } footer: {
            Text(
                """
                Only completed shifts are counted, and a shift belongs to the \(unit.stepNoun) its \
                start time falls in — one that runs past midnight is counted whole, in the \
                \(unit.stepNoun) it began. Elapsed time is the whole of those shifts. Delivery active time is the part of \
                them a recorded delivery was open for, with deliveries worked at once counted once. \
                Non-delivery time is the rest: it is not idle time, and DashPilot does not know what \
                you were doing during either.
                """
            )
        }
    }

    private func earningsSection(_ metrics: PeriodMetrics) -> some View {
        Section {
            if let statement = metrics.earningsStatement(locale: locale) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statement)
                        .font(.headline)
                        .monospacedDigit()
                    Text(metrics.earningsCoverageStatement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(metrics.spokenEarningsStatement(locale: locale))
                .accessibilityIdentifier("periodEarnings")
            } else {
                Text("No amount recorded")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(metrics.spokenEarningsStatement(locale: locale))
                    .accessibilityIdentifier("periodEarnings")
            }

            rateRow(metrics, .perWorkingHour, identifier: "periodWorkingHourRate")
            rateRow(metrics, .perDeliveryActiveHour, identifier: "periodActiveHourRate")
        } header: {
            Text("Earnings")
        } footer: {
            Text(earningsExplanation(metrics))
        }
    }

    /// What the driver recorded the period cost, and what their recorded
    /// earnings come to after it.
    ///
    /// Shown even when nothing was recorded, and that is the point: a period
    /// with no expense in it says so in words, so a driver reading a gross
    /// figure can see that DashPilot is not quietly holding costs back — and so
    /// the absence of a net figure has a reason on screen beside it.
    private func expensesSection(_ metrics: PeriodMetrics) -> some View {
        Section {
            if let statement = metrics.expenseStatement(locale: locale) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statement)
                        .font(.headline)
                        .monospacedDigit()
                    Text(metrics.expenseBasisStatement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(metrics.spokenExpenseStatement(locale: locale))
                .accessibilityIdentifier("periodExpenses")
            } else {
                Text("No expenses recorded")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(metrics.spokenExpenseStatement(locale: locale))
                    .accessibilityIdentifier("periodExpenses")
            }

            // Only the categories with a record in them. A category listed at
            // $0.00 would say the driver recorded that it cost nothing.
            ForEach(metrics.expenses.categoryTotals) { total in
                LabeledContent(total.category.title) {
                    Text(total.total.formatted(locale: locale)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(metrics.categoryStatement(total, locale: locale))
                .accessibilityIdentifier("periodExpenseCategory")
            }

            netRow(metrics)
        } header: {
            Text("Expenses")
        } footer: {
            Text(
                """
                Expenses are what you entered, on the dates you gave them. They are not attached to a \
                shift or a delivery, nothing is divided across your work, and DashPilot records no \
                purchase and estimates no cost of its own — so anything you did not enter is missing \
                here rather than counted as nothing. \(metrics.netTitle) is those recorded costs \
                taken off your recorded gross earnings. It is not profit and it is not a tax figure.
                """
            )
        }
    }

    /// The net figure, or the sentence saying which half of it the period's
    /// records do not have.
    ///
    /// The caution line is not optional and is not a footnote: both halves are
    /// subtotals of what the driver entered, so the difference is an upper bound
    /// on what they actually netted, and the figure is meaningless without that.
    private func netRow(_ metrics: PeriodMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(metrics.netTitle) {
                if let statement = metrics.netStatement(locale: locale) {
                    Text(statement).monospacedDigit()
                } else {
                    Text("Not available").foregroundStyle(.secondary)
                }
            }
            Text(
                metrics.netAfterRecordedExpenses.isAvailable
                    ? "\(metrics.netBasisStatement). \(metrics.netCautionStatement)"
                    : metrics.netUnavailableExplanation
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metrics.spokenNetStatement(locale: locale))
        .accessibilityIdentifier("periodNetAfterExpenses")
    }

    private func drivingSection(_ metrics: PeriodMetrics) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(metrics.mileageStatement(locale: locale))
                    .font(.headline)
                    .monospacedDigit()
                Text(metrics.mileageCoverageStatement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(metrics.spokenMileageStatement(locale: locale))
            .accessibilityIdentifier("periodMileage")

            if let explanation = metrics.mileagePartialExplanation {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("periodMileagePartial")
            }

            rateRow(metrics, .perRecordedMile, identifier: "periodPerMileRate")
        } header: {
            Text("Driving")
        } footer: {
            Text(
                """
                Recorded mileage is what the routes measured, not the miles driven: recording can \
                be interrupted, and the distance across a gap is left out rather than guessed at. \
                A shift whose route measured nothing contributes no distance at all — it is never \
                counted as zero miles.
                """
            )
        }
    }

    private func deliveriesSection(_ metrics: PeriodMetrics) -> some View {
        Section {
            LabeledContent("Delivered") {
                Text("\(metrics.deliverySummary.completed)").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(metrics.deliverySummary.completed) delivered")
            .accessibilityIdentifier("periodDeliveredCount")

            LabeledContent("Cancelled") {
                Text("\(metrics.deliverySummary.cancelled)").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(metrics.deliverySummary.cancelled) cancelled")
            .accessibilityIdentifier("periodCancelledCount")

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Median recorded pickup wait") {
                    if let wait = metrics.pickupWaitStatement {
                        Text(wait).monospacedDigit()
                    } else {
                        Text("Not available").foregroundStyle(.secondary)
                    }
                }
                Text(metrics.pickupWaitBasisStatement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(metrics.spokenPickupWaitStatement)
            .accessibilityIdentifier("periodPickupWait")

            if let places = metrics.pickupPlaceStatement {
                Text(places)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("periodPickupPlaces")
            }

            if let subtotal = metrics.deliveryEarningsStatement(locale: locale) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recorded on deliveries")
                        .font(.subheadline)
                    Text(subtotal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(metrics.spokenDeliveryEarningsStatement(locale: locale) ?? subtotal)
                .accessibilityIdentifier("periodDeliveryEarnings")
            }
        } header: {
            Text("Deliveries")
        } footer: {
            Text(
                """
                Delivered and cancelled deliveries are counted apart and never added into one figure. \
                The median wait is the middle of the individual pickups recorded in this period, not \
                an average of the places they happened at, and it describes those pickups rather than \
                predicting the next one. Amounts recorded against individual deliveries are a separate \
                record from the shift amounts above: they are not added to them, and the difference \
                between the two is not a shortfall.
                """
            )
        }
    }

    /// The same figures, beside the equivalent period before this one.
    ///
    /// ## Nothing here is a verdict
    ///
    /// A difference between two periods is a difference between two sets of
    /// **records**, and the section says so in as many places as it takes: the
    /// change words are "more recorded" and "less recorded" rather than better
    /// and worse, the records behind both sides sit under every figure, and the
    /// footer refuses the reading the whole section invites.
    ///
    /// ``PeriodComparisonCalculator`` decides all of it. This lays the result
    /// out and adds no rule of its own — including which percentages exist,
    /// which is the decision most easily lost in a view body.
    private func comparisonSection(_ comparison: PeriodComparison) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(comparison.previousPeriodStatement(asOf: now, calendar: calendar, locale: locale))
                    .font(.subheadline)
                if let statement = comparison.previousEmptyStatement {
                    Text(statement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [
                    comparison.spokenPreviousPeriodStatement(asOf: now, calendar: calendar, locale: locale),
                    comparison.previousEmptyStatement
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            )
            .accessibilityIdentifier("periodComparisonPrevious")

            // The facts about this particular pair of periods: one of them has
            // not finished, they are different lengths, they are recorded to
            // different extents. Each is a reason a figure below moved, so they
            // sit in the section rather than in the footer, where the general
            // explanation lives.
            if let notes = comparisonNotes(comparison) {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("periodComparisonNotes")
            }

            ForEach(comparison.entries) { entry in
                comparisonRow(entry, noun: comparison.periodNoun)
            }
        } header: {
            Text(comparison.title)
        } footer: {
            Text(comparison.cautionStatement)
        }
    }

    /// One figure in both periods, the change between them, and the records
    /// behind each side.
    ///
    /// Both figures are printed, not just the difference. A driver has to be
    /// able to see what is being subtracted from what, and a lone `−$25.50`
    /// cannot be checked against anything they remember.
    private func comparisonRow(_ entry: PeriodComparisonEntry, noun: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.metric.title)
                .font(.subheadline)
            Text(entry.valuesStatement(locale: locale))
                .font(.headline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if let change = comparisonChangeStatement(entry, noun: noun) {
                Text(change)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The coverage of both sides, printed whether or not they agree. A
            // figure can move entirely because one period is more completely
            // filled in than the other, and that is exactly what this line is
            // for.
            if let basis = entry.basisStatement {
                Text(basis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.spokenStatement(noun: noun, locale: locale))
        .accessibilityIdentifier("periodComparison.\(entry.metric.id)")
    }

    /// The change, its percentage, and the row's own reason for having no
    /// percentage.
    ///
    /// The two reasons that belong to the pair of periods rather than to one
    /// figure — a period that has not finished, records short of their sources —
    /// are stated once above instead of on all ten rows.
    private func comparisonChangeStatement(_ entry: PeriodComparisonEntry, noun: String) -> String? {
        var parts = [entry.changeStatement(locale: locale), entry.percentStatement(locale: locale)]
            .compactMap { $0 }
        if entry.percentageRefusal?.isStatedOnTheRow == true, let refusal = entry.refusalStatement(noun: noun) {
            parts.append(refusal)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What is true of this pair of periods, in one paragraph or none.
    private func comparisonNotes(_ comparison: PeriodComparison) -> String? {
        let notes = [
            comparison.inProgressStatement,
            comparison.lengthStatement,
            comparison.coverageStatement
        ]
        .compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    /// Taking this day or week somewhere else.
    ///
    /// Last, under the figures it exports, and it names the period rather than
    /// saying "Export": the screen has a Day and a Week to choose between, and a
    /// control that does not say which one it means is a control that exports
    /// the wrong thing.
    @ViewBuilder
    private var exportSection: some View {
        if let period {
            let scope = ExportScope.period(period)
            Section {
                Button {
                    isExporting = true
                } label: {
                    Label(scope.actionTitle, systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(scope.spokenActionLabel)
                .accessibilityIdentifier("exportPeriodButton")
            } header: {
                Text("Export")
            } footer: {
                Text(
                    """
                    Writes the completed shifts of this \(unit.stepNoun), their deliveries, the \
                    expenses you recorded in it, and this summary — each figure with the count of \
                    records it was worked out from — as a file on this device. The counts and the \
                    expenses are in the JSON export; the CSV is the flat list of shifts and \
                    deliveries. Recorded positions are not included.
                    """
                )
            }
        }
    }

    // MARK: Rows

    /// One duration and the shifts behind it, or one sentence saying there is
    /// none.
    ///
    /// An absent duration is never a zero: a period whose shifts recorded no
    /// measurable delivery active time is not a period in which no time was
    /// spent on deliveries.
    @ViewBuilder
    private func durationRow(
        _ title: String,
        spokenAs spokenTitle: String,
        duration: TimeInterval?,
        coverage: MetricCoverage,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                if let duration {
                    Text(DurationText.short(duration)).monospacedDigit()
                } else {
                    Text("Not available").foregroundStyle(.secondary)
                }
            }
            if duration != nil, !coverage.isComplete {
                Text(coverage.statement())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(durationLabel(spokenTitle: spokenTitle, duration: duration, coverage: coverage))
        .accessibilityIdentifier(identifier)
    }

    private func durationLabel(spokenTitle: String, duration: TimeInterval?, coverage: MetricCoverage) -> String {
        guard let duration else {
            return "No \(spokenTitle) measured \(coverage.spokenStatement(preposition: "in"))."
        }
        return "\(DurationText.spoken(duration)) \(spokenTitle), \(coverage.spokenStatement())."
    }

    /// One period rate, or one sentence saying why there is not one.
    ///
    /// The basis line is not optional. A rate over four of six shifts and the
    /// same figure over all six are different statements, and the difference has
    /// to be on screen rather than in this file.
    private func rateRow(_ metrics: PeriodMetrics, _ kind: PeriodRateKind, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(kind.title) {
                if let statement = metrics.rateStatement(kind, locale: locale) {
                    Text(statement).monospacedDigit()
                } else {
                    Text("Not available").foregroundStyle(.secondary)
                }
            }
            Text(
                metrics.rate(kind).isAvailable
                    ? metrics.rateBasisStatement(kind)
                    : kind.unavailableExplanation
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metrics.spokenRateStatement(kind, locale: locale))
        .accessibilityIdentifier(identifier)
    }

    /// What the earnings figures mean, with the sentence about missing amounts
    /// added only when this period actually has some.
    private func earningsExplanation(_ metrics: PeriodMetrics) -> String {
        var sentences = [
            """
            Gross earnings are the amounts you recorded against these shifts, added up. Nothing is \
            imported, nothing has been subtracted for fuel, wear or tax, and amounts you recorded \
            against individual deliveries are never added into this figure.
            """
        ]
        if !metrics.earningsCoverage.isComplete {
            sentences.append(
                """
                Shifts with no amount recorded are left out of the total rather than counted as \
                \(Money.zero.formatted(locale: locale)); the count under each figure says how many \
                went into it.
                """
            )
        }
        sentences.append(
            """
            Each rate divides the amounts of the shifts that have both halves of it by those same \
            shifts' hours or miles. It is never an average of the shifts' own rates.
            """
        )
        return sentences.joined(separator: " ")
    }

    // MARK: Deriving

    /// The period the screen is showing, or `nil` if the calendar cannot build
    /// one for the current selection.
    ///
    /// One type for all four selections. A month and a chosen range arrive at
    /// the calculator as the same `[start, end)` span a day does, which is what
    /// keeps every metric rule identical across them.
    private var period: ReportingPeriod? {
        if unit == .custom {
            return ReportingPeriod(from: customStart, through: customEnd, calendar: calendar)
        }
        return ReportingPeriod(unit: unit, containing: anchor, calendar: calendar)
    }

    /// Starts the custom range at **this week so far**: the first day of the
    /// current week through today.
    ///
    /// Deterministic, never in the future, and the span the driver most likely
    /// just looked at under Week — so opening Custom shows familiar figures with
    /// the dates spelled out, ready to widen or narrow. It is described as
    /// selected dates and never as "a week": once either end moves it is neither
    /// a week nor a rolling seven days, and only the dates stay true.
    ///
    /// Runs once. After the driver has chosen a range, returning to this screen
    /// must not quietly reset it.
    private func seedCustomRangeIfNeeded() {
        guard !hasSeededCustomRange else { return }
        hasSeededCustomRange = true
        customEnd = now
        customStart = ReportingPeriod(unit: .week, containing: now, calendar: calendar)?.start ?? now
    }

    private var isCurrent: Bool {
        period?.isCurrent(asOf: now) ?? false
    }

    private var title: String {
        period?.title(asOf: now, calendar: calendar, locale: locale) ?? unit.title
    }

    private var spokenTitle: String {
        period?.spokenTitle(asOf: now, calendar: calendar, locale: locale) ?? unit.title
    }

    /// The equivalent period immediately before the selected one, which every
    /// figure in the comparison section is read from.
    ///
    /// ``ReportingPeriod/precedingEquivalent(using:)`` and never
    /// ``ReportingPeriod/previous(using:)``: the second is what the back chevron
    /// steps to and refuses a chosen range, and this one names the span an equal
    /// number of days before that range without moving the selection to it.
    private var comparisonPeriod: ReportingPeriod? {
        period?.precedingEquivalent(using: calendar)
    }

    /// The completed shifts belonging to the selected period.
    private var shiftsInPeriod: [Shift] {
        shifts(in: period)
    }

    /// The completed shifts belonging to the period before it.
    private var shiftsInComparisonPeriod: [Shift] {
        shifts(in: comparisonPeriod)
    }

    private func shifts(in period: ReportingPeriod?) -> [Shift] {
        guard let period else { return [] }
        return completedShifts.filter { period.contains($0.startedAt) }
    }

    /// What the period adds up to, or `nil` while its routes are still being
    /// measured.
    ///
    /// Absent rather than partial during measurement: a summary built over
    /// unmeasured routes would say "No route measured" for a fraction of a
    /// second, which is a claim rather than a loading state.
    private var metrics: PeriodMetrics? {
        metrics(of: shiftsInPeriod, in: period)
    }

    /// The same figures for the period before the selected one, or `nil` while
    /// its routes are still being measured.
    private var comparisonMetrics: PeriodMetrics? {
        metrics(of: shiftsInComparisonPeriod, in: comparisonPeriod)
    }

    /// The two results side by side, or `nil` when either is not ready or the
    /// calendar cannot name the period before this one.
    ///
    /// Built from the finished results rather than from the records, which is
    /// what keeps a compared figure identical to the figure above it: there is
    /// one aggregation in this screen, and the comparison is not a second one.
    private var comparison: PeriodComparison? {
        guard let metrics, let comparisonMetrics else { return nil }
        return comparisons.comparison(of: metrics, with: comparisonMetrics, asOf: now, calendar: calendar)
    }

    private func metrics(of shifts: [Shift], in period: ReportingPeriod?) -> PeriodMetrics? {
        guard let period, let measurement, measurement.token == measurementToken else { return nil }
        let records = shifts.map { shift in
            shift.periodRecord(for: measurement.distances[shift.id] ?? .none)
        }
        return calculator.metrics(
            of: records,
            // Every recorded expense, selected into the period by the calculator
            // on its own date. Nothing is measured for them, so they are not
            // part of the measurement token: adding one updates the figures on
            // the next body without a re-measure.
            expenses: recordedExpenses.map(\.expenseRecord),
            in: period
        )
    }

    /// Identifies the measurement the screen currently needs: which shifts, in
    /// which period. A route changes only while its shift is running, and a
    /// running shift is never in here, so this is the whole of what invalidates
    /// a measurement.
    ///
    /// Both bounds are in the token, not just the start: two custom ranges can
    /// begin on the same day and cover different numbers of shifts. The
    /// preceding period's shifts are in it too, because the comparison measures
    /// their routes as well and a selection that changes only the earlier of the
    /// two spans still needs a re-measure.
    private var measurementToken: String {
        let span = period.map {
            "\($0.unit.rawValue)@\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)"
        } ?? "none"
        let ids = (shiftsInPeriod + shiftsInComparisonPeriod).map(\.id.uuidString)
        return ([span] + ids).joined(separator: "|")
    }

    /// Measures both periods' routes in one pass.
    ///
    /// The comparison doubles the work a selection costs, which is the price of
    /// its second column being the same measurement as the first rather than a
    /// cheaper estimate of it. Measuring is why this runs in a task rather than
    /// in `body`.
    private func measureRoutes() {
        let token = measurementToken
        var distances: [UUID: RouteDistance] = [:]
        for shift in shiftsInPeriod + shiftsInComparisonPeriod {
            distances[shift.id] = shift.recordedDistance()
        }
        measurement = RouteMeasurement(token: token, distances: distances)
    }

    /// Measured routes, tagged with the selection they belong to.
    private struct RouteMeasurement {
        let token: String
        let distances: [UUID: RouteDistance]
    }
}

#if DEBUG
#Preview("Week with several shifts") {
    NavigationStack {
        PeriodSummaryView()
    }
    .modelContainer(PreviewSupport.periodSummaryContainer())
}

#Preview("Day beside the day before") {
    NavigationStack {
        PeriodSummaryView()
    }
    .modelContainer(PreviewSupport.periodComparisonContainer())
}

#Preview("Empty period") {
    NavigationStack {
        PeriodSummaryView()
    }
    .modelContainer(PreviewSupport.emptyContainer())
}
#endif
