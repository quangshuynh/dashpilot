import SwiftUI

/// One line describing whether the running shift's route is being recorded.
///
/// It is deliberately only a state. No map, no distance, no coordinates and no
/// sample count: nothing that has been implemented can be shown as a
/// measurement yet, and a screen that implied otherwise would be claiming a
/// capability the app does not have.
///
/// It is shown because the alternative is worse. A driver who assumes their
/// route is being recorded, while permission is off or the app spent the shift
/// in the background, loses the shift's data and only finds out afterwards.
struct RouteCaptureStatusView: View {
    let state: RouteCaptureState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routeCaptureStatus")
    }

    private var title: String {
        switch state {
        case .idle, .tracking: "Location tracking active"
        case .pausedInBackground: "Foreground tracking paused"
        case .unavailable(.permissionRequired): "Location permission required"
        case .unavailable: "Location unavailable"
        }
    }

    private var symbol: String {
        switch state {
        case .idle, .tracking: "location.fill"
        case .pausedInBackground: "pause.circle"
        case .unavailable: "location.slash"
        }
    }

    private var tint: Color {
        switch state {
        case .idle, .tracking: .green
        case .pausedInBackground: .orange
        case .unavailable: .secondary
        }
    }

    private var detail: String? {
        switch state {
        case .idle, .tracking:
            nil
        case .pausedInBackground:
            "DashPilot records your route only while it is open. Return to the app to continue."
        case .unavailable(.permissionRequired), .unavailable(.permissionDenied):
            "Turn on location access for DashPilot to record this shift's route."
        case .unavailable(.permissionRestricted):
            "Location access is restricted on this device, so the route cannot be recorded."
        case .unavailable(.locationServicesOff):
            "Location Services is off for this device, so the route cannot be recorded."
        case .unavailable(.authorizationUnknown):
            "DashPilot cannot read its location permission on this version of iOS."
        case .unavailable(.locationFailed):
            "The device cannot determine its location right now."
        case .unavailable(.storeUnavailable):
            "DashPilot could not save to its local data store, so the route is not being recorded."
        }
    }
}

#if DEBUG
#Preview("Capture states") {
    List {
        RouteCaptureStatusView(state: .tracking)
        RouteCaptureStatusView(state: .pausedInBackground)
        RouteCaptureStatusView(state: .unavailable(.permissionRequired))
        RouteCaptureStatusView(state: .unavailable(.locationServicesOff))
        RouteCaptureStatusView(state: .unavailable(.storeUnavailable))
    }
}
#endif
