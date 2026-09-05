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

    private var activeShift: Shift? { unfinishedShifts.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let activeShift {
                        ActiveShiftPanel(
                            shift: activeShift,
                            captureState: routeCapture.state,
                            end: endShift
                        )
                    } else {
                        StartShiftPanel(start: startShift)
                    }
                }

                Section {
                    LocationAuthorizationPanel()
                } header: {
                    Text("Location")
                }

                Section {
                    ForEach(completedShifts) { shift in
                        CompletedShiftRow(shift: shift)
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
            // A shift that was still running when the app was terminated is
            // still running now, so capture resumes here rather than waiting for
            // the driver to touch anything.
            .task { routeCapture.synchronize() }
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

private struct ActiveShiftPanel: View {
    let shift: Shift
    let captureState: RouteCaptureState
    let end: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shift in Progress", systemImage: "record.circle")
                .font(.headline)
                .foregroundStyle(.red)
                .accessibilityIdentifier("activeShiftStatus")

            // Elapsed time is derived from the start timestamp on every tick and
            // never stored, so it cannot drift away from the recorded times.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ElapsedTimeLabel(elapsed: shift.elapsed(asOf: context.date))
            }

            LabeledContent("Started") {
                Text(shift.startedAt, format: .dateTime.hour().minute())
            }
            .font(.subheadline)

            RouteCaptureStatusView(state: captureState)

            Button(action: end) {
                Text("End Shift")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .accessibilityIdentifier("endShiftButton")
        }
        .padding(.vertical, 8)
    }
}

private struct ElapsedTimeLabel: View {
    let elapsed: TimeInterval

    var body: some View {
        Text(duration.formatted(.time(pattern: .hourMinuteSecond)))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityIdentifier("elapsedTime")
            .accessibilityLabel("Elapsed time")
            // Spoken to the minute: a per-second read-out is noise for VoiceOver.
            .accessibilityValue(duration.formatted(.units(allowed: [.hours, .minutes], width: .wide)))
    }

    private var duration: Duration { .seconds(elapsed) }
}

/// One finished shift in history: when it ran, what its route measured, what
/// the driver recorded it paid, and the way to record or change that.
private struct CompletedShiftRow: View {
    let shift: Shift

    /// Measured when the row appears rather than inside `body`.
    ///
    /// A shift's route can hold thousands of positions, and a view's body is
    /// re-evaluated whenever the list redraws. Nothing is cached in the store —
    /// the number is still derived from the route every time the row is built.
    @State private var recordedDistance: RouteDistance?

    /// Earnings are edited in a sheet rather than in the row: a draft the
    /// driver can abandon, instead of a field that writes to the store as they
    /// type.
    @State private var isEditingEarnings = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                heading
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let recordedMileage {
                    Text(recordedMileage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // One element so VoiceOver reads the shift as a shift, rather than
            // four unrelated fragments. The button below stays separate,
            // because it has to remain individually reachable.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("completedShiftRow")

            Button {
                isEditingEarnings = true
            } label: {
                Label(
                    shift.grossEarnings == nil ? "Add Earnings" : "Edit Earnings",
                    systemImage: shift.grossEarnings == nil ? "plus.circle" : "pencil"
                )
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("editShiftEarningsButton")
        }
        .padding(.vertical, 4)
        .task(id: shift.id) { recordedDistance = shift.recordedDistance() }
        .sheet(isPresented: $isEditingEarnings) {
            ShiftEarningsEditor(shift: shift)
        }
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

    /// The amount, and only the amount. No rate: what a shift paid per hour or
    /// per recorded mile is a separate calculation that has not been built, and
    /// a figure sitting next to a duration and a distance must not imply one.
    @ViewBuilder
    private var recordedEarnings: some View {
        if let earnings = shift.grossEarnings {
            Text(earnings.formatted())
                .font(.headline)
                .monospacedDigit()
        }
    }

    /// What the route can honestly be said to show.
    ///
    /// The wording never claims to be every mile driven. Capture is
    /// foreground-only and its gaps are excluded from the total, so "recorded"
    /// is the strongest word available; "partial route" is added when the shift
    /// is known to have stretches the route does not cover.
    ///
    /// A route with nothing measurable in it says so rather than showing
    /// `0.0 mi`, which a driver would read as "you did not move" instead of "no
    /// distance could be measured".
    private var recordedMileage: String? {
        guard let recordedDistance else { return nil }
        guard recordedDistance.isMeasured else {
            return recordedDistance.usableSampleCount == 0
                ? "No route recorded"
                : "Not enough route recorded to measure"
        }
        let miles = recordedDistance.formattedMiles()
        return recordedDistance.isPartial ? "\(miles) recorded · partial route" : "\(miles) recorded"
    }

    private var detail: String {
        let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt = shift.endedAt, let completedDuration = shift.completedDuration else {
            return started
        }
        let ended = endedAt.formatted(date: .omitted, time: .shortened)
        // Shifts are measured in hours, but a shift ended moments after it
        // started should read as seconds rather than as "0 min".
        let units: Set<Duration.UnitsFormatStyle.Unit> = completedDuration < 60
            ? [.minutes, .seconds]
            : [.hours, .minutes]
        let length = Duration.seconds(completedDuration)
            .formatted(.units(allowed: units, width: .abbreviated))
        return "\(started) – \(ended) · \(length)"
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
