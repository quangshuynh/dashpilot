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

private struct CompletedShiftRow: View {
    let shift: Shift

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shift.startedAt, format: .dateTime.weekday(.abbreviated).month().day())
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("completedShiftRow")
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
