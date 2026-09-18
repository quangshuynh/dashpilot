import SwiftData
import SwiftUI

/// Entry screen: the shift control on top, completed shifts below.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationAuthorizationService.self) private var locationAuthorization
    @Environment(LocationTrackingService.self) private var routeCapture
    /// Write-only from here. The panel below draws from the store; this is told
    /// to catch up whenever the store changes.
    @Environment(ShiftLiveActivityService.self) private var liveActivity
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

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

    /// What "now" is, for deciding which Monday-to-Sunday week History is
    /// showing.
    ///
    /// Read when the screen appears, again whenever the app returns to the
    /// foreground, and again the moment the week itself ends. A driver working
    /// through Sunday night is exactly the person who would otherwise be left
    /// reading a list headed `This Week` that is describing the week before,
    /// with the shift they just finished filed under Older Weeks.
    @State private var now = Date.now

    private var activeShift: Shift? { unfinishedShifts.first }

    /// The completed shifts split into the current week and the weeks before
    /// it.
    ///
    /// ``HistoryWeek`` owns every rule here, including which week is current
    /// and which week a shift belongs to. This screen chooses nothing; it draws
    /// one side of the split and hands the other to ``OlderHistoryWeeksView``.
    private var history: HistoryWeekPartition<Shift>? {
        HistoryWeek.partition(completedShifts, by: \.startedAt, asOf: now, calendar: calendar)
    }

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

                    ForEach(currentWeekShifts) { shift in
                        // The whole row is one destination: a finished shift is
                        // a thing to open, not a row with controls scattered
                        // across it. Everything that was a button here now
                        // lives on the screen it opens.
                        NavigationLink(value: shift) {
                            CompletedShiftRow(shift: shift)
                        }
                        .accessibilityIdentifier("completedShiftRow")
                    }

                    // Last in the section, under the week it is an alternative
                    // to, and styled as an ordinary row rather than as the
                    // prominent thing on screen: this week is what History is
                    // for, and the older weeks are where a driver goes when they
                    // want something else. Absent when there is nothing older,
                    // because a screen that would open on an empty list is not
                    // worth offering.
                    if let history, history.hasOtherWeeks {
                        NavigationLink {
                            OlderHistoryWeeksView()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View Older Weeks")
                                    Text(olderWeeksSummary(history))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                            }
                        }
                        .accessibilityLabel("View older weeks. \(olderWeeksSummary(history))")
                        .accessibilityIdentifier("olderHistoryWeeksLink")
                    }
                } header: {
                    historyHeader
                } footer: {
                    historyFooter
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
                // A shift that was still running when the app was terminated is
                // still running now, and the activity it had may or may not have
                // survived with it. Reconciling adopts the one that did, starts
                // one that did not, and ends a card left behind by a shift that
                // has since ended.
                liveActivity.reconcile()
                // A share that was interrupted by termination can leave a file
                // in the temporary export directory. It is cleared once per
                // launch so the app never holds a copy of a driver's history
                // they did not ask it to keep.
                ShiftExportService(context: modelContext).purgeTemporaryExports()
            }
            // Restarted whenever the week on screen changes, which is what makes
            // one sleep enough: the task for the week that has just begun is
            // started by the same state change that ended the last one.
            .task(id: history?.currentWeek.week.end) {
                guard let end = history?.currentWeek.week.end else { return }
                await advancePastWeekEnd(end)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // The week History is scoped to is decided by the clock, and
                    // a driver can leave the app on Sunday night and return on
                    // Monday. Re-read here as well as at the boundary itself,
                    // because a suspended device does not run the sleep above on
                    // time.
                    now = .now
                    // Location permission and the system-wide Location Services
                    // switch are changed outside the app, and Core Location
                    // reports neither while DashPilot is backgrounded, so both
                    // the panel and capture are re-read on return rather than
                    // left showing a stale state.
                    locationAuthorization.refresh()
                    routeCapture.enterForeground()
                    // The driver can turn Live Activities off in Settings, and
                    // can dismiss the card by hand. Neither is reported to the
                    // app, so the surface is reconciled on return like the
                    // permission beside it.
                    liveActivity.reconcile()
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

    /// The shifts the default list draws: the current Monday-to-Sunday week's.
    ///
    /// Falls back to every completed shift if the calendar cannot describe the
    /// week containing now. That is not reachable with any ordinary calendar,
    /// and the fallback is deliberately the permissive one: a driver seeing
    /// more history than the screen intended can still find their work, and a
    /// driver seeing none cannot.
    private var currentWeekShifts: [Shift] {
        history?.currentWeek.elements ?? completedShifts
    }

    /// The section heading, naming the week the list is scoped to.
    ///
    /// **One line, and that is a constraint rather than a preference.** The
    /// first build put the dates on a second line under the word, and it cost
    /// nine red journeys: the header sits above the rows, so every point it
    /// grows pushes the list down, and the second `completedShiftRow` fell out
    /// of what the `List` had rendered. Nine journeys that open or count a
    /// second shift failed on a row that existed in the store and not in the
    /// accessibility tree. The dates moved to the footer, which is below the
    /// rows and can grow freely.
    ///
    /// VoiceOver still hears the dates here, because a listener has no footer
    /// in view to read afterwards.
    @ViewBuilder
    private var historyHeader: some View {
        if let week = history?.currentWeek.week {
            Text("History · \(week.title(asOf: now, calendar: calendar, locale: locale))")
                .accessibilityLabel("History. \(week.spokenTitle(asOf: now, calendar: calendar, locale: locale))")
                .accessibilityIdentifier("historyHeader")
        } else {
            Text("History")
        }
    }

    /// What the section says under itself: which days it is showing, and what
    /// it is not showing.
    ///
    /// Below the rows, so it may be as long as it needs to be. An empty current
    /// week is never left looking like an empty app: if there is older work the
    /// footer says so, and the control to reach it is the row directly above.
    @ViewBuilder
    private var historyFooter: some View {
        if completedShifts.isEmpty {
            Text("Completed shifts will appear here.")
        } else if let week = history?.currentWeek.week {
            let dates = week.rangeStatement(calendar: calendar, locale: locale)
            if currentWeekShifts.isEmpty {
                Text("No completed shifts in \(dates) yet. Earlier weeks are under View Older Weeks.")
                    .accessibilityIdentifier("emptyCurrentWeekNotice")
            } else if history?.hasOtherWeeks == true {
                Text("Showing \(dates). Everything before it is under View Older Weeks.")
            } else {
                Text("Showing \(dates).")
            }
        }
    }

    /// How much is waiting behind the older-weeks control.
    ///
    /// Counts and nothing else. Neither word says *older*, because
    /// ``HistoryWeekPartition/otherWeeks`` also carries a week later than this
    /// one where a device clock has been moved backwards, and the screen it
    /// opens names every week by its own dates.
    private func olderWeeksSummary(_ history: HistoryWeekPartition<Shift>) -> String {
        let weeks = history.otherWeeks.count
        let shifts = history.otherWeekRecordCount
        let weekText = weeks == 1 ? "1 week" : "\(weeks) weeks"
        let shiftText = shifts == 1 ? "1 shift" : "\(shifts) shifts"
        return "\(weekText) · \(shiftText)"
    }

    /// Moves ``now`` on when the week on screen ends.
    ///
    /// Sleeps exactly once, until the week's own exclusive end, rather than
    /// polling: the boundary instant is a date the calendar has already worked
    /// out. Waking re-reads the clock, which rebuilds the partition, and the
    /// task is restarted by its own `id` for the week that has just begun.
    ///
    /// The sleep is a duration on a monotonic clock, so a device suspended
    /// across the boundary can wake late. That is what the scene-phase read
    /// below covers: returning to the app always re-reads the clock.
    private func advancePastWeekEnd(_ end: Date) async {
        let interval = end.timeIntervalSince(.now)
        guard interval > 0 else {
            now = .now
            return
        }
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        now = .now
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
        // Same ordering, same reason: a refused start leaves no shift for the
        // activity to describe, and reconciling reads the store rather than the
        // tap.
        liveActivity.reconcile()
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
        liveActivity.reconcile()
    }

    private func resumeShift() {
        // After, not before: capture starts only once the store holds a shift
        // that is running again, so a refused or failed resume cannot leave it
        // recording against a shift the driver has not resumed.
        perform { try ShiftService(context: modelContext).resumeActiveShift() }
        routeCapture.synchronize()
        liveActivity.reconcile()
    }

    private func endShift() {
        // Before, so that no candidate can be judged against a shift the store
        // has already closed. `synchronize()` afterwards restarts capture if the
        // end did not go through, which is why stopping first latches nothing.
        routeCapture.prepareForShiftEnd()
        perform { try ShiftService(context: modelContext).endActiveShift() }
        routeCapture.synchronize()
        // A finished shift has no Live Activity. Reconciling ends it, and does
        // so immediately rather than leaving a card on the Lock Screen saying a
        // shift is being worked that has stopped.
        liveActivity.reconcile()
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
