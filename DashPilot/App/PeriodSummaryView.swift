import SwiftData
import SwiftUI

/// What the completed shifts of one day or one week add up to.
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
/// The routes are measured in a task rather than in `body`, for the reason the
/// history row measures in one: a week can hold several shifts and each holds
/// thousands of positions. The arithmetic over the measured result stays in the
/// body, which is what keeps the summary correct the moment a driver edits an
/// amount and comes back.
struct PeriodSummaryView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    /// Every completed shift. The period's own shifts are selected from these by
    /// ``ReportingPeriod/contains(_:)``, which is also the rule the calculator
    /// applies — this filter exists to avoid measuring routes the period will
    /// not use, not to decide membership.
    @Query(filter: #Predicate<Shift> { $0.endedAt != nil }, sort: \Shift.startedAt, order: .reverse)
    private var completedShifts: [Shift]

    @State private var unit: ReportingPeriodUnit = .day

    /// A moment inside the selected period. Stepping moves this to the
    /// neighbouring period's start, so the selection survives a 23- or 25-hour
    /// day without any arithmetic on seconds here.
    @State private var anchor = Date.now

    /// Fixed when the screen appears rather than read continuously: which period
    /// is "current" must not change under the driver mid-read.
    @State private var now = Date.now

    /// The measured routes, and the selection they were measured for.
    @State private var measurement: RouteMeasurement?

    /// Exporting the selected period. The sheet writes the file when it opens,
    /// so this stays false until the driver asks.
    @State private var isExporting = false

    private let calculator = PeriodMetricsCalculator()

    var body: some View {
        List {
            Section {
                periodSelector
            }

            if let metrics {
                if metrics.isEmpty {
                    emptySection(metrics)
                } else {
                    summarySection(metrics)
                    earningsSection(metrics)
                    drivingSection(metrics)
                    deliveriesSection(metrics)
                    // Only for a period that holds something. A period with no
                    // completed shift has nothing to export, and an export
                    // control over an empty state is an offer the app would
                    // have to refuse.
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
        // On the list rather than on the section that presents it: the sections
        // are rebuilt whenever the routes are re-measured, and a sheet attached
        // to one that briefly disappears goes with it.
        .sheet(isPresented: $isExporting) {
            if let period {
                ShiftExportSheet(scope: .period(period))
            }
        }
    }

    // MARK: Period selection

    private var periodSelector: some View {
        VStack(spacing: 12) {
            Picker("Period", selection: $unit) {
                ForEach(ReportingPeriodUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("periodUnitPicker")

            HStack {
                stepButton(
                    systemImage: "chevron.left",
                    label: "Previous \(unit.stepNoun)",
                    identifier: "periodPreviousButton",
                    destination: period?.previous(using: calendar)
                )

                Spacer(minLength: 8)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let period {
                        Text(period.rangeStatement(locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenTitle)
                .accessibilityIdentifier("periodTitle")

                Spacer(minLength: 8)

                stepButton(
                    systemImage: "chevron.right",
                    label: "Next \(unit.stepNoun)",
                    identifier: "periodNextButton",
                    // Nothing is offered beyond the period the driver is in.
                    // A future week holds no records, and an empty state for one
                    // is a screen that looks broken rather than informative.
                    destination: isCurrent ? nil : period?.next(using: calendar)
                )
            }
        }
        .padding(.vertical, 4)
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
                "Elapsed",
                spokenAs: "elapsed shift time",
                duration: metrics.elapsedDuration,
                coverage: metrics.elapsedCoverage,
                identifier: "periodElapsedTime"
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
                Only completed shifts are counted, and a shift belongs to the \(unit.stepNoun) it \
                started on — one that runs past midnight is counted whole, on the \(unit.stepNoun) it \
                began. Elapsed time is the whole of those shifts. Delivery active time is the part of \
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

            rateRow(metrics, .perElapsedHour, identifier: "periodElapsedHourRate")
            rateRow(metrics, .perDeliveryActiveHour, identifier: "periodActiveHourRate")
        } header: {
            Text("Earnings")
        } footer: {
            Text(earningsExplanation(metrics))
        }
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
                Recorded mileage is what the routes measured, not the miles driven: capture is \
                foreground-only, and the distance across a gap is left out rather than guessed at. \
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
                    Writes the completed shifts of this \(unit.stepNoun), their deliveries, and this \
                    summary — each figure with the count of shifts it was worked out from — as a file \
                    on this device. The counts are in the JSON export; the CSV is the flat list of \
                    shifts and deliveries. Recorded positions are not included.
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
    /// one for the selected date.
    private var period: ReportingPeriod? {
        ReportingPeriod(unit: unit, containing: anchor, calendar: calendar)
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

    /// The completed shifts belonging to the selected period.
    private var shiftsInPeriod: [Shift] {
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
        guard let period, let measurement, measurement.token == measurementToken else { return nil }
        let records = shiftsInPeriod.map { shift in
            shift.periodRecord(for: measurement.distances[shift.id] ?? .none)
        }
        return calculator.metrics(of: records, in: period)
    }

    /// Identifies the measurement the screen currently needs: which shifts, in
    /// which period. A route changes only while its shift is running, and a
    /// running shift is never in here, so this is the whole of what invalidates
    /// a measurement.
    private var measurementToken: String {
        let start = period.map { "\($0.unit.rawValue)@\($0.start.timeIntervalSince1970)" } ?? "none"
        return ([start] + shiftsInPeriod.map(\.id.uuidString)).joined(separator: "|")
    }

    private func measureRoutes() {
        let token = measurementToken
        var distances: [UUID: RouteDistance] = [:]
        for shift in shiftsInPeriod {
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

#Preview("Empty period") {
    NavigationStack {
        PeriodSummaryView()
    }
    .modelContainer(PreviewSupport.emptyContainer())
}
#endif
