import SwiftData
import SwiftUI

/// Stable scene shell. Session orchestration outlives each workspace presentation.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationAuthorizationService.self) private var locationAuthorization
    @Environment(LocationTrackingService.self) private var routeCapture
    /// Write-only from here. The panel below draws from the store; this is told
    /// to catch up whenever the store changes.
    @Environment(ShiftLiveActivityService.self) private var liveActivity
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar

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

    @State private var navigation = WorkspaceNavigation()
    @State private var workFocus: WorkFocusRequest?
    @State private var workPath = NavigationPath()
    @State private var pendingEarningsConfirmation: PendingDeliveryEarningsConfirmation?

    @State private var lifecycleError: ShiftLifecycleError?

    /// The running shift's route reading, shared by the panel above the
    /// deliveries and the controls below them. See ``ActiveRouteReading``.
    @State private var routeReading = ActiveRouteReading()

    /// What the pickup workflow did at the last Park or Resume Driving pressed
    /// in this screen. See ``PickupWorkflowFeedback``.
    @State private var pickupWorkflow: PickupWorkflowFeedback?

    /// Why taking back an automated step was refused, while that is on screen.
    @State private var undoError: DeliveryLifecycleError?

    /// The short-lived line and Undo a Delivered, or a step recorded while
    /// parked, leaves. See ``TransientUndoBar``.
    @State private var transientUndo: TransientUndo?

    /// Exporting every completed shift.
    @State private var isExportingHistory = false

    /// The welcome, shown once to a new driver. See ``OnboardingPolicy``.
    @State private var isShowingOnboarding = false

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

    /// The Monday-to-Sunday week History is scoped to.
    ///
    /// ``HistoryWeek`` owns the rule, and this is one calendar question rather
    /// than a pass over the store: the section below fetches that week's shifts
    /// and nothing else, and is initialised again when this changes.
    private var currentWeek: HistoryWeek? {
        HistoryWeek(containing: now, calendar: calendar)
    }

    private var workspaceTabs: some View {
        TabView(selection: $navigation.selection) {
            Tab("Home", systemImage: "house", value: Workspace.home) {
                NavigationStack {
                    HomeWorkspace(
                        activeShift: activeShift,
                        start: startShift,
                        continueShift: {
                            workFocus = WorkFocusRequest(destination: .activeShift)
                            workPath = NavigationPath()
                            navigation.selection = .work
                        },
                        history: {
                            workPath = NavigationPath()
                            workFocus = WorkFocusRequest(destination: .history)
                            navigation.selection = .work
                        },
                        money: { navigation.selection = .money }
                    )
                    .safeAreaInset(edge: .bottom) { sharedUndoBar }
                }
            }
            Tab("Work", systemImage: "briefcase", value: Workspace.work) {
                NavigationStack(path: $workPath) {
                    WorkWorkspace(
                        activeShift: activeShift,
                        routeReading: routeReading,
                        pickupWorkflow: pickupWorkflow,
                        currentWeek: currentWeek,
                        now: now,
                        focusRequest: workFocus,
                        transientUndo: $transientUndo,
                        pendingEarningsConfirmation: $pendingEarningsConfirmation,
                        startShift: startShift,
                        resumeShift: resumeShift,
                        park: park,
                        resumeDriving: resumeDriving,
                        pauseShift: pauseShift,
                        endShift: endShift,
                        undoPickupWorkflowStep: undoPickupWorkflowStep,
                        takeBackTransientUndo: takeBackTransientUndo,
                        exportAllHistory: { isExportingHistory = true }
                    )
                }
            }
            Tab("Money", systemImage: "creditcard", value: Workspace.money) {
                NavigationStack {
                    MoneyWorkspace()
                        .safeAreaInset(edge: .bottom) { sharedUndoBar }
                }
            }
        }
    }

    var body: some View {
        workspaceTabs
        // Selection is decided only once for this scene, never on foreground return.
        .onAppear { navigation.chooseInitialWorkspace(hasUnfinishedShift: activeShift != nil) }
        .task(id: transientUndo?.id) {
            guard transientUndo != nil else { return }
            var remaining = DeliveryControlPanel.undoSeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard scenePhase == .active, pendingEarningsConfirmation == nil else { continue }
                remaining -= 1
            }
            transientUndo = nil
        }
        // The window an automated step can be taken back in, which is the
        // one the app's immediate undo of a Delivered already keeps, counted
        // in one-second ticks for the reason that one is. Restarted by each
        // Park. When it passes, the Park line stays for as long as the
        // vehicle is parked, without its Undo. (Resume Driving's line is in
        // the bar below the list, which keeps its own window.)
        .task(id: pickupWorkflow?.id) {
            guard pickupWorkflow != nil else { return }
            for _ in 0..<DeliveryControlPanel.undoSeconds {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            pickupWorkflow?.undoableAction = nil
        }
        .alert(
            "Step Not Undone",
            isPresented: isShowingUndoError,
            presenting: undoError
        ) { _ in
            Button("OK", role: .cancel) { undoError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The step could not be undone.")
        }
        // The delivered record and its captured expectation survive workspace
        // presentation changes. The Undo window waits until this sheet closes.
        .sheet(item: $pendingEarningsConfirmation) { pending in
            DeliveryEarningsConfirmation(numbered: pending.numbered, expected: pending.expected)
        }
        .sheet(isPresented: $isExportingHistory) {
            ShiftExportSheet(scope: .allHistory)
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingView(context: .firstLaunch) {
                OnboardingRecord.markCompleted()
                isShowingOnboarding = false
            }
        }
        // A shift that was still running when the app was terminated is
        // still running now, so capture resumes here rather than waiting for
        // the driver to touch anything.
        .task {
            decideOnboarding()
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
        .task(id: currentWeek?.end) {
            guard let end = currentWeek?.end else { return }
            await advancePastWeekEnd(end)
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        // Capture follows the store's shift state, so it is reconciled
        // whenever the active shift changes — including changes this screen
        // did not make.
        .onChange(of: activeShift?.id) { _, _ in routeCapture.synchronize() }
        // Pausing does not change which shift is active, so the line above
        // does not fire for it. This one catches a pause or resume recorded
        // from anywhere, including an App Intent run while this screen is
        // open, without waiting for the next position to be rejected.
        .onChange(of: activeShift?.lifecycleState) { _, _ in
            routeCapture.synchronize()
            // A Delivered's Undo belongs to the running shift it was
            // recorded on; pausing or ending moves past it.
            transientUndo = nil
        }
        .onChange(of: activeShift?.id) { _, _ in transientUndo = nil }
        // Parking and driving again do not change the lifecycle state, so
        // neither line above fires for them. This catches a stretch closed
        // by a delivery step under the driver's resume-after-progress
        // setting, and one closed from the Lock Screen while this screen
        // is open, without waiting for the next position to be judged.
        .onChange(of: activeShift?.isRouteSuspended) { _, _ in routeCapture.synchronize() }
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

    private func handleScenePhase(_ phase: ScenePhase) {
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

    @ViewBuilder
    private var sharedUndoBar: some View {
        if let transientUndo, activeShift?.lifecycleState == .running {
            TransientUndoBar(undo: transientUndo, perform: takeBackTransientUndo)
        }
    }

    /// Shows the welcome to a new driver, records it as seen for a driver who
    /// already has history, and does nothing otherwise. The count reads no row.
    private func decideOnboarding() {
        let hasShifts = ((try? modelContext.fetchCount(FetchDescriptor<Shift>())) ?? 0) > 0
        switch OnboardingRecord.launchDecision(hasRecordedShifts: hasShifts) {
        case .present: isShowingOnboarding = true
        case .recordAsSeen: OnboardingRecord.markCompleted()
        case .none: break
        }
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

    private var isShowingUndoError: Binding<Bool> {
        Binding(
            get: { undoError != nil },
            set: { isShowing in if !isShowing { undoError = nil } }
        )
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }

    private func startShift() {
        perform {
            try ShiftService(context: modelContext).startShift()
            workFocus = WorkFocusRequest(destination: .activeShift)
            workPath = NavigationPath()
            navigation.selection = .work
        }
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

    private func park() {
        // Before, for the reason pausing stops first: no position taken after
        // the tap should be judged against a shift the store is about to record
        // as parked. `synchronize()` afterwards restarts capture if the write
        // did not go through.
        routeCapture.prepareForRouteSuspension()
        // The operation the intents and the Lock Screen run too, so the pickup
        // workflow behaves the same from every surface.
        var result: ParkVehicleResult?
        perform { result = try ParkVehicleService(context: modelContext).park() }
        // A line about the last resume says nothing about a vehicle parked
        // again, and its Undo would now be refused. A Delivered's Undo is about
        // a delivery and stays.
        if result != nil, transientUndo?.survivesParking == false {
            transientUndo = nil
        }
        pickupWorkflow = result.flatMap { result in
            guard let parkedAt = result.shift.openRouteSuspension?.startedAt,
                  let notice = result.pickup.notice else { return nil }
            return PickupWorkflowFeedback(
                moment: .parked(at: parkedAt),
                notice: notice,
                undoableAction: AutomatedPickupAction(result.automatedSteps)
            )
        }
        routeCapture.synchronize()
        liveActivity.reconcile()
    }

    private func resumeDriving() {
        // After, not before: capture starts only once the store holds a shift
        // that is driving again, so a refused or failed write cannot leave it
        // recording a walk.
        var result: ResumeDrivingResult?
        perform { result = try ParkVehicleService(context: modelContext).resumeDriving() }
        if let result {
            // The parked line goes with the stretch it described. What Resume
            // recorded is said below the list, so its leaving after the window
            // moves no delivery card; see ``TransientUndoBar``.
            pickupWorkflow = nil
            if let notice = result.pickup.notice {
                transientUndo = .resumed(notice, action: AutomatedPickupAction(result.automatedSteps))
            }
        }
        routeCapture.synchronize()
        liveActivity.reconcile()
    }

    /// Takes back the delivery events the workflow just recorded: one, or
    /// every delivery of a shared pickup together, and never part of them.
    ///
    /// **The vehicle is not touched**: no suspension is opened or closed and
    /// capture is not reconciled, because the driver did park and is driving.
    /// The offer goes whatever happens next, so a refusal cannot invite a second
    /// press; the line then says what was undone, or the alert says why not.
    private func undoPickupWorkflowStep() {
        guard var feedback = pickupWorkflow, let action = feedback.undoableAction else { return }
        feedback.undoableAction = nil
        do {
            try DeliveryService(context: modelContext).undoAutomatedSteps(action.steps)
            feedback.notice = action.undoneNotice
        } catch let error as DeliveryLifecycleError {
            undoError = error
        } catch {
            undoError = .storeUnavailable(underlying: error)
        }
        pickupWorkflow = feedback
        // A delivery's state moved, which is what the Lock Screen card shows.
        liveActivity.reconcile()
    }

    /// Takes back what the line below the list offers: a Delivered, or a step
    /// recorded while parked together with the driving it resumed.
    ///
    /// The offer goes whatever happens next, so a refusal cannot invite a
    /// second press; the line then says what was undone, or the alert says why
    /// not. For the parked case capture is stopped **first**, so positions still
    /// in memory are written before the ones since the resume are removed, and
    /// reconciled after, which leaves it stopped when the stretch reopened and
    /// recording when the Undo was refused.
    private func takeBackTransientUndo() {
        guard let undo = transientUndo, let offer = undo.offer else { return }
        transientUndo?.offer = nil
        do {
            switch offer {
            case let .delivered(deliveryID, _):
                transientUndo = nil
                let service = DeliveryService(context: modelContext)
                guard let delivery = try service.delivery(withID: deliveryID) else {
                    throw DeliveryLifecycleError.invalidRecovery(.notDelivered)
                }
                try service.reopenDelivered(delivery)
            case let .pickupWorkflow(action):
                // The vehicle is not touched: the driver did resume driving.
                try DeliveryService(context: modelContext).undoAutomatedSteps(action.steps)
                transientUndo = undo.undone(action.undoneNotice)
            case let .parkedProgress(action):
                routeCapture.prepareForRouteSuspension()
                defer { routeCapture.synchronize() }
                try DeliveryProgressService(context: modelContext).undo(action)
                transientUndo = undo.undone(action.undoneNotice)
            }
        } catch let error as DeliveryLifecycleError {
            undoError = error
        } catch {
            undoError = .storeUnavailable(underlying: error)
        }
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
