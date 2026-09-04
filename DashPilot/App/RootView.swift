import SwiftData
import SwiftUI

/// Entry screen: the shift control on top, completed shifts below.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

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
                        ActiveShiftPanel(shift: activeShift, end: endShift)
                    } else {
                        StartShiftPanel(start: startShift)
                    }
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
    }

    private func endShift() {
        perform { try ShiftService(context: modelContext).endActiveShift() }
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
    RootView()
        .modelContainer(PreviewSupport.emptyContainer())
}

#Preview("Active shift") {
    RootView()
        .modelContainer(PreviewSupport.populatedContainer())
}

#Preview("History only") {
    RootView()
        .modelContainer(PreviewSupport.populatedContainer(includingActiveShift: false))
}
#endif
