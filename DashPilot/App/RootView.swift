import SwiftData
import SwiftUI

/// Entry screen: the shift control on top, completed shifts below.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationAuthorizationService.self) private var locationAuthorization
    @Environment(LocationTrackingService.self) private var routeCapture
    @Environment(\.scenePhase) private var scenePhase

    /// Unfinished shifts, newest first.
    ///
    /// SwiftData is the only place shift state lives, so a shift that was still
    /// running when the app was terminated simply reappears here on the next
    /// launch — there is nothing for the driver to restore by hand. The query
    /// is not limited to one row on purpose: if the store ever holds more than
    /// one unfinished shift, the newest is shown and ``ShiftService`` reports
    /// the anomaly rather than the screen hiding it.
    @Query(filter: #Predicate<Shift> { $0.endedAt == nil }, sort: \Shift.startedAt, order: .reverse)
    private var unfinishedShifts: [Shift]

    @Query(filter: #Predicate<Shift> { $0.endedAt != nil }, sort: \Shift.startedAt, order: .reverse)
    private var completedShifts: [Shift]

    @State private var lifecycleError: ShiftLifecycleError?

    /// Exporting every completed shift.
    @State private var isExportingHistory = false

    private var activeShift: Shift? { unfinishedShifts.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let activeShift {
                        ActiveShiftPanel(
                            shift: activeShift,
                            captureState: routeCapture.state,
                            pause: pauseShift,
                            resume: resumeShift,
                            end: endShift
                        )
                    } else {
                        StartShiftPanel(start: startShift)
                    }
                }

                if let activeShift {
                    Section {
                        // A paused shift is one the driver has said they are not
                        // working, and a delivery started on it would be time
                        // the app is simultaneously reporting as not worked. The
                        // control is replaced by the reason rather than removed,
                        // so the section does not silently vanish.
                        if activeShift.isPaused {
                            Text("Deliveries are not recorded while the shift is paused. Resume the shift to start one.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pausedDeliveryNotice")
                        } else {
                            DeliveryControlPanel(shift: activeShift)
                        }
                    } header: {
                        Text("Delivery")
                    } footer: {
                        Text(
                            """
                            DashPilot records only what you tap. It is not connected to any delivery \
                            platform and cannot tell when an order was offered, handed over or received.
                            """
                        )
                    }
                }

                Section {
                    LocationAuthorizationPanel()
                } header: {
                    Text("Location")
                }

                Section {
                    // The entry point to everything that spans shifts, at the
                    // head of history rather than buried inside one shift: a
                    // summary of a day, a week, a month or a chosen range is not
                    // a property of any single shift in it.
                    //
                    // Named for what the screen is rather than for the four
                    // lengths it offers: listing them here would have to be
                    // corrected every time one is added, and the screen already
                    // says which one it is showing.
                    NavigationLink {
                        PeriodSummaryView()
                    } label: {
                        Label("Period Summaries", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("periodSummaryLink")

                    // Beside the summaries rather than inside a shift: this one
                    // spans every shift there is. Absent when history is empty,
                    // because an export control over no records is an offer the
                    // app would have to refuse.
                    if !completedShifts.isEmpty {
                        Button {
                            isExportingHistory = true
                        } label: {
                            Label(ExportScope.allHistory.actionTitle, systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel(ExportScope.allHistory.spokenActionLabel)
                        .accessibilityIdentifier("exportAllHistoryButton")
                    }

                    ForEach(completedShifts) { shift in
                        // The whole row is one destination: a finished shift is
                        // a thing to open, not a row with controls scattered
                        // across it. Everything that was a button here now
                        // lives on the screen it opens.
                        NavigationLink(value: shift) {
                            CompletedShiftRow(shift: shift)
                        }
                        .accessibilityIdentifier("completedShiftRow")
                    }
                } header: {
                    Text("History")
                } footer: {
                    if completedShifts.isEmpty {
                        Text("Completed shifts will appear here.")
                    }
                }
            }
            .navigationTitle("DashPilot")
            .toolbar {
                // In the bar rather than in the list, for two reasons. An
                // expense belongs to no shift, so there is no section of this
                // screen it is part of — and every row this screen gains pushes
                // the shift history further down, which is the list a driver
                // opens the app to read. The bar keeps it reachable from
                // wherever they have scrolled to.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExpenseListView()
                    } label: {
                        // The word, not a glyph. A `Label` here renders as its
                        // icon alone in the navigation bar, and a credit-card
                        // symbol in a corner does not say "the costs you
                        // recorded" to anyone who has not already found the
                        // screen once.
                        Text("Expenses")
                    }
                    .accessibilityLabel("Recorded expenses")
                    .accessibilityIdentifier("expensesLink")
                }
            }
            .navigationDestination(for: Shift.self) { shift in
                CompletedShiftDetailView(shift: shift)
            }
            .sheet(isPresented: $isExportingHistory) {
                ShiftExportSheet(scope: .allHistory)
            }
            // A shift that was still running when the app was terminated is
            // still running now, so capture resumes here rather than waiting for
            // the driver to touch anything.
            .task {
                routeCapture.synchronize()
                // A share that was interrupted by termination can leave a file
                // in the temporary export directory. It is cleared once per
                // launch so the app never holds a copy of a driver's history
                // they did not ask it to keep.
                ShiftExportService(context: modelContext).purgeTemporaryExports()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // Location permission and the system-wide Location Services
                    // switch are changed outside the app, and Core Location
                    // reports neither while DashPilot is backgrounded, so both
                    // the panel and capture are re-read on return rather than
                    // left showing a stale state.
                    locationAuthorization.refresh()
                    routeCapture.enterForeground()
                case .background:
                    routeCapture.enterBackground()
                case .inactive:
                    // Transient: the app switcher, a call banner, the
                    // notification shade. Stopping here would chop the route
                    // into fragments for interruptions the driver never left
                    // the app for. `.background` is the state that means the app
                    // is no longer running in the foreground.
                    break
                @unknown default:
                    break
                }
            }
            // Capture follows the store's shift state, so it is reconciled
            // whenever the active shift changes — including changes this screen
            // did not make.
            .onChange(of: activeShift?.id) { _, _ in routeCapture.synchronize() }
            // Pausing does not change which shift is active, so the line above
            // does not fire for it. This one catches a pause or resume recorded
            // from anywhere, including an App Intent run while this screen is
            // open, without waiting for the next position to be rejected.
            .onChange(of: activeShift?.lifecycleState) { _, _ in routeCapture.synchronize() }
            .onChange(of: locationAuthorization.authorization) { _, _ in routeCapture.synchronize() }
            .alert(
                "Shift Not Updated",
                isPresented: isShowingLifecycleError,
                presenting: lifecycleError
            ) { _ in
                Button("OK", role: .cancel) { lifecycleError = nil }
            } message: { error in
                Text(error.errorDescription ?? "The shift could not be updated.")
            }
        }
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }

    private func startShift() {
        perform { try ShiftService(context: modelContext).startShift() }
        // After, not before: capture starts only once the store holds a running
        // shift, so a refused or failed start cannot leave it recording.
        routeCapture.synchronize()
    }

    private func pauseShift() {
        // Before, so that no position recorded after the tap is judged against a
        // shift the store is about to record as paused. `synchronize()`
        // afterwards restarts capture if the pause did not go through, which is
        // why stopping first latches nothing: capture always ends up describing
        // what the store actually holds.
        routeCapture.prepareForShiftPause()
        perform { try ShiftService(context: modelContext).pauseActiveShift() }
        routeCapture.synchronize()
    }

    private func resumeShift() {
        // After, not before: capture starts only once the store holds a shift
        // that is running again, so a refused or failed resume cannot leave it
        // recording against a shift the driver has not resumed.
        perform { try ShiftService(context: modelContext).resumeActiveShift() }
        routeCapture.synchronize()
    }

    private func endShift() {
        // Before, so that no candidate can be judged against a shift the store
        // has already closed. `synchronize()` afterwards restarts capture if the
        // end did not go through, which is why stopping first latches nothing.
        routeCapture.prepareForShiftEnd()
        perform { try ShiftService(context: modelContext).endActiveShift() }
        routeCapture.synchronize()
    }

    /// Surfaces a rejected or failed transition instead of leaving the tap
    /// looking like it worked.
    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch let error as ShiftLifecycleError {
            lifecycleError = error
        } catch {
            lifecycleError = .storeUnavailable(underlying: error)
        }
    }
}

private struct StartShiftPanel: View {
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No Shift in Progress")
                .font(.headline)
            Text("Start a shift when you begin driving. DashPilot records its start and end times on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: start) {
                Text("Start Shift")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("startShiftButton")
        }
        .padding(.vertical, 8)
    }
}

/// One finished shift in history: what shift it was, and roughly how it went.
///
/// Deliberately three lines and no controls. The row's job is to be scanned and
/// tapped; everything it used to carry inline — the second rate, the route's
/// segments and gaps, the earnings editor, and now deletion — belongs to
/// ``CompletedShiftDetailView``, which has the room to explain it.
///
/// What survives here is what a driver picking a shift out of a list needs:
/// when it ran, how long it lasted, what it paid, what its route recorded, and
/// the one rate that answers "how did this shift go" — gross earnings per shift
/// hour. The per-recorded-mile rate needs its denominator explained to be read
/// correctly, and that explanation is a detail-screen thing.
private struct CompletedShiftRow: View {
    let shift: Shift

    /// Measured when the row appears rather than inside `body`.
    ///
    /// A shift's route can hold thousands of positions, and a view's body is
    /// re-evaluated whenever the list redraws. Nothing is cached in the store —
    /// the number is still derived from the route every time the row is built.
    @State private var recordedDistance: RouteDistance?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading
            Text(schedule)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    // Wrap rather than truncate. The first thing a truncation
                    // takes is the end of "recorded", which is the word that
                    // makes the mileage honest.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .task(id: shift.id) { recordedDistance = shift.recordedDistance() }
        // One element so VoiceOver reads the shift as a shift rather than three
        // unrelated fragments, with an explicit label because the abbreviations
        // that read well — "mi", "/hr", "·" — are poor to hear.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The date, with the recorded amount alongside it — or under it once the
    /// text is large enough that two items cannot share a line without one of
    /// them being truncated. A shortened date and a shortened amount are both
    /// worse than a second line.
    @ViewBuilder
    private var heading: some View {
        let date = Text(shift.startedAt, format: .dateTime.weekday(.abbreviated).month().day())
            .font(.headline)

        if dynamicTypeSize.isAccessibilitySize {
            date
            recordedEarnings
        } else {
            HStack(alignment: .firstTextBaseline) {
                date
                Spacer(minLength: 8)
                recordedEarnings
            }
        }
    }

    /// The amount, and only the amount. The rate derived from it is a separate
    /// line, in a smaller style, so the figure the driver actually recorded is
    /// never confused with the one DashPilot worked out.
    @ViewBuilder
    private var recordedEarnings: some View {
        if let earnings = shift.grossEarnings {
            Text(earnings.formatted(locale: locale))
                .font(.headline)
                .monospacedDigit()
        }
    }

    /// The third line: what the route recorded, and the shift's hourly rate.
    ///
    /// Both are omitted when they do not exist. An unavailable rate leaves
    /// nothing behind — no dash, no `$0.00` — because a shift with no amount
    /// recorded and a shift that paid nothing are different facts; the detail
    /// screen is where the difference is explained.
    private var summary: String? {
        guard let quality else { return nil }
        var parts = [quality.mileageStatement(locale: locale)]
        if let marker = quality.partialMarker {
            parts.append(marker)
        }
        if let hourly = metrics?.grossPerWorkingHour.amount {
            parts.append("\(hourly.formatted(locale: locale))/hr")
        }
        return parts.joined(separator: " · ")
    }

    /// When the shift ran and how long it was worked.
    ///
    /// The duration here is the **working** one, because it is the figure the
    /// rate on the line below divides by; a row showing elapsed time beside a
    /// per-working-hour rate would not multiply out. A shift that was paused
    /// says so, so the shorter figure is not read as a mistake.
    private var schedule: String {
        let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt = shift.endedAt, let working = shift.completedWorkingDuration else {
            return started
        }
        let ended = endedAt.formatted(date: .omitted, time: .shortened)
        var line = "\(started) – \(ended) · \(DurationText.short(working))"
        if pauseCount > 0 {
            line += pauseCount == 1 ? " · 1 pause" : " · \(pauseCount) pauses"
        }
        return line
    }

    /// How many stretches the driver paused this shift for.
    private var pauseCount: Int { shift.completedPausedTime?.intervalCount ?? 0 }

    /// What VoiceOver says instead of the abbreviations.
    ///
    /// Sentences rather than separators, spelled-out miles, and the partial
    /// route stated as a claim rather than as a two-word marker — the marker is
    /// legible beside the figure it qualifies and unintelligible on its own.
    private var accessibilityLabel: String {
        var sentences = [shift.startedAt.formatted(date: .complete, time: .omitted)]

        if let endedAt = shift.endedAt, let working = shift.completedWorkingDuration {
            let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
            let ended = endedAt.formatted(date: .omitted, time: .shortened)
            sentences.append("\(started) to \(ended)")
            sentences.append("\(DurationText.spoken(working)) worked")
            if let paused = shift.completedPausedTime, paused.hasPauses {
                sentences.append("\(DurationText.spoken(paused.duration)) paused")
            }
        }

        if let earnings = shift.grossEarnings {
            sentences.append("\(earnings.formatted(locale: locale)) gross earnings recorded")
        } else {
            sentences.append("No earnings recorded")
        }

        if let quality {
            sentences.append(quality.spokenMileageStatement(locale: locale))
        }

        if let hourly = metrics?.grossPerWorkingHour.amount {
            sentences.append("\(hourly.formatted(locale: locale)) gross earnings per working hour")
        }

        return sentences.joined(separator: ". ")
    }

    private var quality: RouteQuality? {
        recordedDistance.map(RouteQuality.init)
    }

    /// The rates this shift can support, derived from the amount recorded on it
    /// and the distance measured above.
    ///
    /// Deriving them here rather than in `.task` is deliberate: the expensive
    /// part is measuring the route, which happens once, and the rates are two
    /// divisions over the result. Recomputing them with the body is what keeps
    /// them correct the moment the driver adds, changes or removes an amount.
    /// Nothing is calculated in this view — ``ShiftMetricsCalculator`` owns
    /// every rule, including which rates exist at all.
    private var metrics: ShiftMetrics? {
        recordedDistance.map { shift.metrics(for: $0) }
    }
}

#if DEBUG
#Preview("No shift") {
    PreviewSupport.rootView(
        container: PreviewSupport.emptyContainer(),
        status: .notDetermined
    )
}

#Preview("Active shift") {
    PreviewSupport.rootView(container: PreviewSupport.populatedContainer())
}

#Preview("History only") {
    PreviewSupport.rootView(
        container: PreviewSupport.populatedContainer(includingActiveShift: false),
        status: .denied
    )
}
#endif
