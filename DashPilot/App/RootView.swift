import SwiftData
import SwiftUI

/// Entry screen. Lists recorded shifts newest first.
///
/// Starting and ending shifts is not implemented yet, so this screen is
/// read-only and empty on a fresh install.
struct RootView: View {
    @Query(sort: \Shift.startedAt, order: .reverse) private var shifts: [Shift]

    var body: some View {
        NavigationStack {
            Group {
                if shifts.isEmpty {
                    ContentUnavailableView(
                        "No Shifts Recorded",
                        systemImage: "steeringwheel",
                        description: Text("Recorded shifts will appear here.")
                    )
                } else {
                    List(shifts) { shift in
                        ShiftRow(shift: shift)
                    }
                }
            }
            .navigationTitle("DashPilot")
        }
    }
}

private struct ShiftRow: View {
    let shift: Shift

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shift.startedAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let duration = shift.completedDuration else { return "In progress" }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

#if DEBUG
#Preview("Empty") {
    RootView()
        .modelContainer(PreviewSupport.emptyContainer())
}

#Preview("With shifts") {
    RootView()
        .modelContainer(PreviewSupport.populatedContainer())
}
#endif
