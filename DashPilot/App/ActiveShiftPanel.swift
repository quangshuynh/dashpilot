import OSLog
import SwiftData
import SwiftUI

/// The open measurement of the running shift's route, shared by the two
/// panels that read it: the header, which shows the recorded miles, and the
/// controls below the deliveries, which decide whether the vehicle correction
/// may still be offered.
///
/// Held by ``RootView`` and written only by ``ActiveShiftPanel``'s reading
/// loop. Observable per property, so only the views that read
/// ``measurement`` are redrawn when it moves; the root list is not. It is a
/// faster reading of stored rows, never a stored figure, and is thrown away
/// with the shift.
@MainActor
@Observable
final class ActiveRouteReading {
    var measurement: ActiveRouteMeasurement?
}

/// The head of the shift in progress: what state it is in, how long it has
/// been worked, what its route has recorded so far, and the one control that
/// changes the vehicle's state (Park, Resume Driving, or Resume Shift).
///
/// ## What it is for
///
/// A live reading of a shift, not a preview of the shift's final report. Every
/// figure on it is true at the moment it is read and is derived from the same
/// rows and the same calculations the finished shift is reported with; nothing
/// is estimated forward, nothing is projected, and a figure whose data
/// requirements are not met is withheld with the reason rather than filled in.
/// See ``ActiveShiftMetrics``.
///
/// ## Where it sits
///
/// First on the screen, above the deliveries. Pause, End, the vehicle and the
/// capture status are ``ActiveShiftControlsPanel``, below the deliveries:
/// they are tapped once a shift or read rarely, and the delivery cards' next
/// steps are what a driver reaches for between them.
///
/// ## The states
///
/// Running, paused and parked are kept visually distinct rather than
/// distinguished by a button title. Running is a red recording label with a
/// ticking figure. Paused is an orange banner with a pause symbol that says
/// working time stopped, over a figure that does not move. Parked is a blue
/// banner with the parking sign that says working time is still counting,
/// under the running label, over a figure that still ticks. Each banner's own
/// control (Resume Shift, Resume Driving) sits directly under it.
///
/// ## What it costs
///
/// The route is measured **incrementally**. The panel extends an open
/// ``ActiveRouteMeasurement`` with the positions recorded since the last
/// reading, rather than walking the whole route again; see ``refreshInterval``
/// for the cadence and ``ActiveShiftRouteService`` for the queries. Nothing
/// derived is written to the store.
struct ActiveShiftPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let shift: Shift
    /// The route reading this panel keeps current, shared with
    /// ``ActiveShiftControlsPanel``.
    let routeReading: ActiveRouteReading
    let resume: () -> Void
    /// Records that the driver has parked and is walking away from the vehicle.
    let park: () -> Void
    /// Records that the driver is driving again.
    let resumeDriving: () -> Void
    /// What the pickup workflow did at the Park or Resume Driving this screen
    /// last pressed, while it still describes the vehicle's current state.
    /// `nil` for a stretch parked or resumed from another surface.
    var pickupWorkflow: PickupWorkflowFeedback?
    /// Takes back the one delivery event the workflow just recorded.
    var undoPickupWorkflowStep: () -> Void = {}

    /// How often the stored route is read again while the shift is running.
    ///
    /// Not a redraw interval: the working figure ticks once a second on its own
    /// timeline, and this is only how often the *store* is asked whether the
    /// route has grown. Two seconds is under the interval between flushes of the
    /// capture batch, so a driver never waits on this for a number that already
    /// exists, and it is far longer than the reading costs.
    ///
    /// The reading is a count and, when the count moved, a fetch of the rows
    /// after the last one measured. Measured on the simulator against a stored
    /// route of 8,000 positions, that costs 1.1 ms when nothing has arrived and
    /// 2.3 ms when four positions have, and it barely moves with the length of
    /// the route. Measuring the whole route instead costs **247 ms** at the same
    /// length and grows with it, which is the reason this panel does not simply
    /// call ``Shift/recordedDistance(using:)`` in its body: a quarter of a second
    /// on the main actor, repeated for every reason a body is re-evaluated,
    /// would stall the one screen a driver looks at while driving. The figures
    /// are in `context.md`.
    private static let refreshInterval: TimeInterval = 2

    private var routeMeasurement: ActiveRouteMeasurement? {
        get { routeReading.measurement }
        nonmutating set { routeReading.measurement = newValue }
    }

    private var isPaused: Bool { shift.isPaused }

    private var isRouteSuspended: Bool { shift.isRouteSuspended }

    /// Everything the panel states about the shift, as of now.
    ///
    /// `nil` until the route has been read once, which is what keeps the panel
    /// from claiming "no route recorded" in the moment before it has looked.
    /// Nothing is calculated here: ``Shift/activeMetrics(for:asOf:)`` is the
    /// adapter, and the rules are the domain's.
    private var metrics: ActiveShiftMetrics? {
        routeMeasurement.map { shift.activeMetrics(for: $0.recordedDistance, asOf: .now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xl) {
            // What state the shift is in, first, because it changes what every
            // figure below means; then the one control that leaves a paused or
            // parked state, directly under the banner that names it.
            VStack(alignment: .leading, spacing: DashSpacing.md) {
                statusRow
                parkedNotice
                pickupWorkflowNotice
                leavingControl
            }

            // The one figure that exists and moves while a shift runs. Earnings
            // cannot lead here: a running shift may not record an amount, so a
            // headline of earnings would be a permanent absence.
            workingTime

            if let metrics {
                DashMetricRow {
                    recordedMileage(metrics)
                    deliveries(metrics)
                }
                earnings(metrics)
            }

            parkControl
        }
        .padding(.vertical, DashSpacing.md)
        // Reading the store on a cadence rather than with the body. A body is
        // re-evaluated for reasons that have nothing to do with the route — a
        // clock tick, a sibling row, a scroll — and measuring a route on each of
        // them would be work proportional to the length of the shift, paid for
        // nothing.
        .task(id: shift.id) {
            routeMeasurement = nil
            measureRoute()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { return }
                // A paused shift records nothing, so there is nothing to read.
                // Resuming is caught by the lifecycle change below rather than
                // by this loop noticing eventually.
                if shift.lifecycleState == .running { measureRoute() }
            }
        }
        // Pausing flushes the positions captured up to the tap, and ending a
        // pause opens a new capture session. Both change what the figure should
        // say now rather than in a couple of seconds.
        .onChange(of: shift.lifecycleState) { _, _ in measureRoute() }
    }

    /// Which state the shift is in, and when it started.
    ///
    /// Running is the recording label. Paused is a banner of its own, which
    /// says the one fact that makes it paused (working time stopped) so the
    /// difference from parked never rests on its colour. Parked is **not** a
    /// value here, because a parked shift is still running and still counting
    /// working time: it is the banner under this row, about the route.
    @ViewBuilder
    private var statusRow: some View {
        let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
        if isPaused {
            let pausedAt = shift.openPause?.startedAt.formatted(date: .omitted, time: .shortened)
            DashStateBanner(
                title: ShiftLifecycleState.paused.title,
                detail: pausedAt.map { "Working time stopped at \($0). Started \(started)." }
                    ?? "Working time stopped. Started \(started).",
                symbol: "pause.circle.fill",
                tint: DashStatusTint.paused
            )
            .accessibilityIdentifier("pausedShiftStatus")
        } else {
            let status = DashStatusLabel(
                title: ShiftLifecycleState.running.title,
                symbol: "record.circle",
                tint: DashStatusTint.running
            )
            .accessibilityIdentifier("activeShiftStatus")
            let startedText = Text("Started \(started)")
                .dashFont(.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Beside each other where both fit whole, stacked where they do
            // not: at the largest sizes side by side broke the status inside
            // its words.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DashSpacing.xs) {
                    status
                    startedText
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
                        status.fixedSize()
                        Spacer(minLength: DashSpacing.md)
                        startedText.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: DashSpacing.xs) {
                        status
                        startedText
                    }
                }
            }
        }
    }

    /// Extends the route measurement with whatever the store has gained.
    ///
    /// A store that cannot be read leaves the previous figure standing: a route
    /// that could not be read is not a route of no miles, and replacing a real
    /// figure with "no route recorded" because one query failed would be exactly
    /// the invention this app refuses elsewhere.
    private func measureRoute() {
        do {
            routeMeasurement = try ActiveShiftRouteService(context: modelContext)
                .measurement(extending: routeMeasurement, of: shift)
        } catch {
            AppLog.routeCapture.error("Could not read the running shift's route: \(error)")
        }
    }

    /// The working figure, ticking only while the shift is actually running.
    ///
    /// While paused it is rendered once rather than on a timeline. The
    /// subtraction already holds it still, because the open pause grows exactly
    /// as fast as elapsed time, so a per-second refresh would redraw an
    /// unchanged number every second for as long as the driver is on their
    /// break.
    @ViewBuilder
    private var workingTime: some View {
        if isPaused {
            WorkingTimeLabel(working: shift.workingDuration(asOf: .now), isPaused: true)
        } else {
            // Derived from the stored timestamps on every tick and never stored,
            // so it cannot drift away from the recorded times.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                WorkingTimeLabel(working: shift.workingDuration(asOf: context.date), isPaused: false)
            }
        }
    }

    /// What the route has recorded so far, and what qualifies it.
    ///
    /// The word "recorded" is part of the figure rather than a caption beside
    /// it, and the partial marker travels with it, because this is the number a
    /// driver is most likely to read as "miles I drove". Both come from
    /// ``RouteQuality`` through ``ActiveShiftMetrics``, so this panel and the
    /// finished shift's screen cannot drift into saying different things about
    /// the same route.
    ///
    /// The segment and gap counts sit under it in caption type. They are what
    /// makes the partiality concrete without the panel having to explain it: the
    /// sentence that does explain it is on the shift's own screen, and a driver
    /// in a cradle is not the audience for a paragraph.
    private func recordedMileage(_ metrics: ActiveShiftMetrics) -> some View {
        let distance = metrics.recordedDistance
        let detail = [metrics.partialMarker, metrics.captureStatement].compactMap { $0 }

        return DashMetric(
            value: distance.isMeasured
                ? distance.formattedMiles(locale: locale)
                : metrics.mileageStatement(locale: locale),
            label: "Recorded miles",
            detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
            isFigure: distance.isMeasured
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded mileage")
        // The spoken form folds the partial-route claim into a sentence: the
        // two-word marker is legible beside the figure and unintelligible heard
        // on its own.
        .accessibilityValue(
            [metrics.spokenMileageStatement(locale: locale), metrics.captureStatement]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
        .accessibilityIdentifier("liveRecordedMileage")
    }

    /// How many deliveries are open, and how many the shift has finished.
    ///
    /// Two figures, finished and in progress, read as one element with the
    /// sentence the shift has always spoken.
    private func deliveries(_ metrics: ActiveShiftMetrics) -> some View {
        let summary = metrics.deliverySummary

        return DashMetricRow {
            DashMetric(
                value: "\(summary.completed)",
                label: "Delivered",
                detail: summary.cancelled > 0 ? "\(summary.cancelled) cancelled" : nil
            )
            DashMetric(value: "\(summary.inProgress)", label: "In progress")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deliveries")
        .accessibilityValue(metrics.spokenDeliveryStatement)
        .accessibilityIdentifier("liveDeliveryCounts")
    }

    /// The amount recorded for the shift and the rates derived from it, or the
    /// one sentence saying why there are none yet.
    ///
    /// Every branch here is the existing rule, not a relaxed one. A shift's
    /// gross earnings cannot be recorded until it has finished, so in practice a
    /// running shift shows the sentence; the figures are rendered from
    /// ``ShiftMetrics`` all the same, so that the panel states whatever the data
    /// actually supports rather than a hard-coded absence. Nothing is inferred
    /// from the amounts recorded against individual deliveries: those are a
    /// separate fact, and adding them up would read every delivery with no
    /// amount as one that paid nothing.
    @ViewBuilder
    private func earnings(_ metrics: ActiveShiftMetrics) -> some View {
        if let gross = metrics.grossEarnings {
            LabeledContent("Recorded") {
                Text(gross.formatted(locale: locale)).monospacedDigit()
            }
            .dashFont(.body)
            .accessibilityLabel("Recorded gross earnings")
            .accessibilityIdentifier("liveRecordedGross")
        }

        rateRow("Per working hour", spokenAs: "gross earnings per working hour", rate: metrics.rates.grossPerWorkingHour)
        rateRow(
            "Per active delivery hour",
            spokenAs: "gross earnings per active delivery hour",
            rate: metrics.rates.grossPerDeliveryActiveHour
        )
        rateRow(
            "Per recorded mile",
            spokenAs: "gross earnings per recorded mile",
            rate: metrics.rates.grossPerRecordedMile
        )

        if let notice = metrics.rateNotice {
            Text(notice)
                .dashFont(.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("liveRateNotice")
        }
    }

    /// One rate, and only when there is one.
    ///
    /// An unavailable rate leaves nothing behind — no dash, no `$0.00` — because
    /// a rate that could not be derived and a rate of zero are different facts.
    /// The reason is said once, below, rather than three times.
    @ViewBuilder
    private func rateRow(_ title: String, spokenAs spokenTitle: String, rate: ShiftRate) -> some View {
        if let amount = rate.amount {
            LabeledContent(title) {
                Text(amount.formatted(locale: locale)).monospacedDigit()
            }
            .dashFont(.body)
            .accessibilityLabel(spokenTitle)
        }
    }

    /// What the driver is told while the vehicle is recorded as parked.
    ///
    /// Prominent and permanent for as long as the state lasts, because the
    /// expensive failure of this feature is forgetting to leave it: a driver who
    /// drives the rest of the shift parked records none of it. The shift's own
    /// status above still says the shift is running, which is the fact this
    /// notice must not contradict; what it says is that the **route** is not
    /// being recorded, and when it stopped.
    @ViewBuilder
    private var parkedNotice: some View {
        if isRouteSuspended, let parkedAt = shift.openRouteSuspension?.startedAt {
            let time = parkedAt.formatted(date: .omitted, time: .shortened)
            // A symbol, a word and a tint of its own: parked is not paused,
            // and the line under the title says the one fact that makes the
            // difference, which clock is still running.
            DashStateBanner(
                title: "Parked · route not recording",
                detail: "Since \(time). Your shift is still running and working time is still counting.",
                symbol: "parkingsign.circle.fill",
                tint: DashStatusTint.parked
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                """
                Parked. DashPilot stopped recording your route at \(time). Your shift is still running and \
                its working time is still counting.
                """
            )
            .accessibilityIdentifier("parkedShiftNotice")
        }
    }

    /// What the driver's pickup workflow just recorded, or declined to, at
    /// Park, below the parked notice. Resume Driving's line is drawn below the
    /// list by ``TransientUndoBar``, so its leaving moves no delivery card.
    ///
    /// A line and not an alert: Park is the tap before a driver walks into a
    /// shop and Resume the tap before they pull away, and nothing here should
    /// stand between them and either. A symbol and words carry the result, never
    /// the tint alone. It names the delivery, because with stacked orders "an
    /// order" would leave the driver to work out which, and it says the event
    /// was recorded **automatically when you parked** rather than detected,
    /// because DashPilot saw nothing: the driver's setting and their tap did it.
    ///
    /// Undo is offered beside a recorded event for the same short window the
    /// app's immediate undo of a Delivered uses, and takes back exactly what
    /// that press recorded: one delivery's event, or the same event for every
    /// delivery of a shared pickup, all of them or none. It is its own control
    /// with its own spoken label, which names what goes back and says the
    /// vehicle stays as it is.
    @ViewBuilder
    private var pickupWorkflowNotice: some View {
        if let pickupWorkflow {
            let notice = pickupWorkflow.notice
            VStack(alignment: .leading, spacing: DashSpacing.md) {
                Label {
                    VStack(alignment: .leading, spacing: DashSpacing.xs) {
                        // Body, not a caption: this says a lifecycle event was
                        // written, or asks the driver to record one.
                        Text(notice.title)
                            .dashFont(.emphasis)
                        Text(notice.detail)
                            .dashFont(.body)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: notice.symbolName)
                        .foregroundStyle(notice.recordedAnEvent ? Color.accentColor : Color.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.spokenLabel)
                .accessibilityIdentifier("pickupWorkflowNotice")

                if let action = pickupWorkflow.undoableAction {
                    Button(action: undoPickupWorkflowStep) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(action.spokenUndoLabel)
                    .accessibilityIdentifier("undoPickupWorkflowStepButton")
                }
            }
            .dashInsetSurface()
        }
    }

    /// The control that leaves a paused or parked state, directly under the
    /// banner that names it, and prominent: it is the one the driver came back
    /// to the app to press.
    @ViewBuilder
    private var leavingControl: some View {
        if isPaused {
            Button(action: resume) {
                Text("Resume Shift")
                    .dashFont(.control)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("resumeShiftButton")
        } else if isRouteSuspended {
            Button(action: resumeDriving) {
                Label("Resume Driving", systemImage: "car.fill")
                    .dashFont(.control)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Resume driving. DashPilot starts recording your route again.")
            .accessibilityIdentifier("resumeDrivingButton")
        }
    }

    /// Parking, under the figures and above the deliveries, because it is the
    /// one shift control a driver reaches for several times a shift. Bordered,
    /// never prominent: the prominent control while a shift runs is a
    /// delivery's next step, and a driver who never parks should not meet a
    /// second one.
    ///
    /// Withheld while paused rather than refused there: a paused shift records
    /// no route either, so parking would claim a second reason for a stop the
    /// driver already has one for.
    @ViewBuilder
    private var parkControl: some View {
        if !isPaused, !isRouteSuspended {
            Button(action: park) {
                Label("Parked for a Pickup", systemImage: "parkingsign.circle")
                    .dashFont(.control)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(
                """
                Parked for a pickup. Stops recording your route while you are away from the vehicle. \
                Your shift keeps running.
                """
            )
            .accessibilityIdentifier("parkShiftButton")
        }
    }
}

/// The shift's own once-a-shift controls and its context, below the
/// deliveries: Pause or End, the vehicle the shift recorded, and whether the
/// route is being recorded.
///
/// Below the delivery cards because each of these is tapped once a shift or
/// read rarely, while a card's next step is tapped many times. Nothing here is
/// prominent. While paused, Resume Shift is in the header under the paused
/// banner, and only End remains here.
struct ActiveShiftControlsPanel: View {
    @Environment(\.locale) private var locale

    let shift: Shift
    /// The header's route reading, read here only to decide whether the
    /// vehicle correction may still be offered.
    let routeReading: ActiveRouteReading
    let captureState: RouteCaptureState
    let pause: () -> Void
    let end: () -> Void

    /// Whether the vehicle correction sheet is open.
    ///
    /// Raised only by the driver tapping `Change`. Nothing presents it on its
    /// own: a modal that appeared during a shift would be the mid-drive
    /// interruption this whole surface is designed against.
    @State private var isCorrectingVehicle = false

    private var isPaused: Bool { shift.isPaused }

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xl) {
            pauseAndEnd

            // Context rather than controls: quieter, and last.
            VStack(alignment: .leading, spacing: DashSpacing.md) {
                vehicleContext(measuring: routeReading.measurement?.recordedDistance)
                RouteCaptureStatusView(state: captureState)
            }
        }
        .padding(.vertical, DashSpacing.md)
        .sheet(isPresented: $isCorrectingVehicle) {
            ShiftVehicleCorrectionEditor(shift: shift)
        }
    }

    /// Which vehicle assumptions this shift is using.
    ///
    /// ## It reads the shift and never Settings
    ///
    /// The name and the economy are ``Shift``'s own snapshot, taken when the
    /// shift started, through ``ShiftVehicleContext``. Nothing here reaches a
    /// ``VehicleProfile``, the current selection or the current gas price, so
    /// changing any of those mid-shift leaves this row exactly where it is, and
    /// a shift that recorded nothing says so rather than borrowing what is
    /// selected today. That is the whole point of the row: Settings answers
    /// which vehicle the **next** shift will record, and a driver who forgot to
    /// switch needs the answer about this one.
    ///
    /// ## Where it sits, and how quiet it is
    ///
    /// Below the deliveries and the shift controls, above the capture status:
    /// the part of the screen that carries context rather than the numbers a
    /// driver glances at. It is two short lines, and the row itself is never a
    /// control: the only thing tappable here is the small `Change` beside it,
    /// and only while the correction is allowed.
    ///
    /// The gas price is deliberately not here. It is an input to the fuel
    /// estimate a finished shift reports, and the one screen a driver reads
    /// while working is not where a price belongs.
    private func vehicleContext(measuring recordedDistance: RouteDistance?) -> some View {
        let context = shift.vehicleContext

        return HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            // A symbol rather than a "Vehicle" caption, so the row costs one
            // line of height where it has one fact and two where it has both.
            Image(systemName: "car.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text(context.title)
                    .dashFont(.body)
                    // Secondary where nothing was recorded, because an absence
                    // should not read with the weight of a fact.
                    .foregroundStyle(context.isRecorded ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let economy = context.economyStatement(locale: locale) {
                    Text(economy)
                        .dashFont(.supporting)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(context.spokenLabel)
            .accessibilityValue(context.spokenValue(locale: locale))
            .accessibilityIdentifier("activeShiftVehicle")

            Spacer(minLength: DashSpacing.md)

            if mayCorrectVehicle(measuring: recordedDistance) {
                changeVehicleButton
            }
        }
    }

    /// The control that opens the correction, and it is absent rather than
    /// disabled once the correction is no longer allowed.
    ///
    /// A dead action is worse than no action: a driver who taps a greyed control
    /// learns nothing, and one who taps a live one that refuses learns it too
    /// late. The row above stays readable either way, which is the part that has
    /// to survive.
    ///
    /// Small, borderless and trailing, because it is secondary to everything
    /// else on this panel: the driving workflow is the delivery controls and the
    /// lifecycle buttons, and this is a settings-style correction reached
    /// deliberately.
    private var changeVehicleButton: some View {
        Button("Change") { isCorrectingVehicle = true }
            .dashFont(.supporting)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .accessibilityLabel("Change this shift's vehicle")
            .accessibilityHint("Only before DashPilot has recorded any driving on this shift")
            .accessibilityIdentifier("changeShiftVehicleButton")
    }

    /// Whether to offer the correction at all.
    ///
    /// Read from the measurement the panel already holds rather than from a walk
    /// of the route, which is why it takes the distance instead of asking the
    /// shift. ``Shift/correctRunningFuelAssumptions(_:using:)`` is where the rule
    /// actually lives and is what refuses a stale tap; this only decides whether
    /// to draw a control, so a reading that is a moment out of date costs a
    /// refusal sentence rather than a wrong write.
    ///
    /// **`nil` withholds it.** In the moment before the route has been read once
    /// the panel does not know whether anything was recorded, and not offering a
    /// correction is the safe direction to be wrong in.
    private func mayCorrectVehicle(measuring recordedDistance: RouteDistance?) -> Bool {
        guard let recordedDistance else { return false }
        return !recordedDistance.isMeasured
    }


    /// Pause and End, side by side where they fit and stacked where they do
    /// not, so neither title is ever shortened. While paused, End alone.
    ///
    /// End is bordered and red rather than prominent: the prominent control
    /// during a shift is a delivery's next step above, which is tapped many
    /// times a shift, while this one is tapped once. It stays available while paused:
    /// a driver who has finished has finished, and making them resume a shift
    /// they are not working in order to end it would record work that did not
    /// happen.
    @ViewBuilder
    private var pauseAndEnd: some View {
        let pauseOrNothing = Group {
            if !isPaused {
                Button(action: pause) {
                    Text("Pause Shift")
                        .dashFont(.control)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("pauseShiftButton")
            }
        }

        let endButton = Button(action: end) {
            Text("End Shift")
                .dashFont(.control)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
        .accessibilityIdentifier("endShiftButton")

        ViewThatFits(in: .horizontal) {
            HStack(spacing: DashSpacing.lg) {
                pauseOrNothing
                endButton
            }
            VStack(spacing: DashSpacing.lg) {
                pauseOrNothing
                endButton
            }
        }
    }
}

/// The big figure on a shift in progress: how long it has been **worked**.
///
/// Working time rather than elapsed time, because that is the figure every rate
/// the shift will produce divides by, and a driver watching one number during
/// the shift and reading a different one afterwards would have no way to tell
/// which was wrong.
struct WorkingTimeLabel: View {
    let working: TimeInterval
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            // Never scaled down to fit: at the largest sizes the figure is
            // allowed its full height, and tabular figures keep it from moving
            // sideways as it ticks.
            Text(duration.formatted(.time(pattern: .hourMinuteSecond)))
                .dashFont(.metricHero)
                .foregroundStyle(isPaused ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(isPaused ? "Worked so far · paused" : "Worked so far")
                .dashFont(.metricLabel)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workingTime")
        .accessibilityLabel(isPaused ? "Working time, paused" : "Working time")
        .accessibilityValue(spokenDuration)
    }

    private var duration: Duration { .seconds(working) }

    /// The figure as VoiceOver hears it.
    ///
    /// To the minute while the shift runs, because a per-second read-out of a
    /// number that changes every second is noise. To the **second** while it is
    /// paused, for the same reason: the figure does not change, so it is not
    /// re-announced, and a driver asking what they have worked at the moment
    /// they stopped should be told exactly rather than to the nearest minute.
    private var spokenDuration: String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = isPaused
            ? [.hours, .minutes, .seconds]
            : [.hours, .minutes]
        return duration.formatted(.units(allowed: allowed, width: .wide))
    }
}
