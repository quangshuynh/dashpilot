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

    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                if let activeShift, LaunchArgument.isPresent(LaunchArgument.liveActivityPreview) {
                    LiveActivityPreviewSection(shift: activeShift)
                }
                #endif

                Section {
                    if let activeShift {
                        ActiveShiftPanel(
                            shift: activeShift,
                            routeReading: routeReading,
                            resume: resumeShift,
                            park: park,
                            resumeDriving: resumeDriving,
                            pickupWorkflow: pickupWorkflow.flatMap { $0.describes(activeShift) ? $0 : nil },
                            undoPickupWorkflowStep: undoPickupWorkflowStep
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
                                .dashFont(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pausedDeliveryNotice")
                        } else {
                            DeliveryControlPanel(shift: activeShift, transientUndo: $transientUndo)
                        }
                    } header: {
                        Text("Deliveries")
                    } footer: {
                        Text("DashPilot records only what you tap. It is not connected to any delivery platform.")
                    }

                    // Below the deliveries: Pause and End are tapped once a
                    // shift, and the vehicle and capture lines are context.
                    Section {
                        ActiveShiftControlsPanel(
                            shift: activeShift,
                            routeReading: routeReading,
                            captureState: routeCapture.state,
                            pause: pauseShift,
                            end: endShift
                        )
                    } header: {
                        Text("Shift")
                    }
                }

                Section {
                    LocationAuthorizationPanel()
                } header: {
                    Text("Location")
                }

                CurrentWeekHistorySection(week: currentWeek, now: now) {
                    isExportingHistory = true
                }
            }
            // Below the list rather than in it, so arriving and leaving move no
            // delivery card under a driver's thumb. Only while the shift runs:
            // a paused or ended shift has nothing it could take back.
            .safeAreaInset(edge: .bottom) {
                if let transientUndo, activeShift?.lifecycleState == .running {
                    TransientUndoBar(undo: transientUndo, perform: takeBackTransientUndo)
                }
            }
            // Recording a newly accepted order, reachable from wherever the
            // list has been scrolled to. A safe-area bar rather than an overlay:
            // the list is inset by its height, so the last row scrolls fully
            // above it and nothing stays hidden underneath. Applied after the
            // Undo line, so the bar is at the very bottom and the line sits on
            // it. Not drawn while paused, when no delivery can be started.
            .safeAreaBar(edge: .bottom) {
                if let activeShift, activeShift.lifecycleState == .running {
                    DeliveryEntryBar(shift: activeShift)
                }
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
            .navigationTitle("DashPilot")
            .toolbar {
                // The conventional place for preferences, and the conventional
                // glyph, so a driver finds it where every other app keeps it.
                // Leading rather than beside Expenses, because the two answer
                // different questions and a bar with two trailing controls
                // invites a mis-tap with a thumb on the move.
                //
                // In the bar rather than in the list for the reason Expenses is:
                // every row this screen gains pushes the shift history further
                // down, and a setting is something a driver touches when they
                // change vehicle, not something they read.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Your vehicles and the gas price new shifts are recorded under.")
                    .accessibilityIdentifier("settingsLink")
                }

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

private struct StartShiftPanel: View {
    let start: () -> Void

    @Environment(\.locale) private var locale

    // Observed rather than read once, so a driver who changes vehicle in
    // Settings and comes back sees the new one without anything to refresh.
    // Reading them writes nothing: no settings row is created by looking.
    @Query private var vehicles: [VehicleProfile]
    @Query private var settingsRows: [DriverSettings]

    /// What the next shift will record, through the same rule the start copies.
    private var nextVehicle: NextShiftVehicleContext {
        NextShiftVehicleContext(
            defaults: SettingsService.fuelDefaults(settings: settingsRows.first, vehicles: vehicles)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xl) {
            // The state, said once and quietly: there is nothing running.
            DashStatusLabel(title: "No shift in progress", symbol: "circle.dashed", tint: .secondary)

            // What starting now would record, as the block the button sits
            // under rather than a caption beside it.
            nextVehicleBlock

            Button(action: start) {
                Text("Start Shift")
                    .dashFont(.control)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("startShiftButton")

            Text("DashPilot records a shift's start and end times on this device.")
                .dashFont(.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DashSpacing.md)
    }

    /// The vehicle the shift about to be started will record.
    ///
    /// Titled for what it is, `Next shift records`, so the name under it reads
    /// as the assumption about to be copied rather than as a setting. With
    /// nothing selected it says so in the quieter role and blocks nothing: a
    /// shift started with nothing to copy records no assumptions, as it always
    /// has. A separate element from the button, so `Start Shift` stays the
    /// plain action it was.
    private var nextVehicleBlock: some View {
        let vehicle = nextVehicle

        return HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            Image(systemName: "car.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text("Next shift records")
                    .dashFont(.eyebrow)
                    .foregroundStyle(.secondary)

                Text(vehicle.title)
                    .dashFont(vehicle.hasVehicle ? .title : .body)
                    // Secondary where none is selected, because an absence
                    // should not read with the weight of a fact.
                    .foregroundStyle(vehicle.hasVehicle ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = vehicle.detail(locale: locale) {
                    Text(detail)
                        .dashFont(.supporting)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vehicle.spokenLabel)
        .accessibilityValue(vehicle.spokenValue(locale: locale))
        .accessibilityHint("Recorded on the shift when you start it. Change it in Settings.")
        .accessibilityIdentifier("nextShiftVehicle")
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
