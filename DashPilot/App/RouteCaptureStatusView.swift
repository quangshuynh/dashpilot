import SwiftUI

/// One line describing whether the running shift's route is being recorded.
///
/// It is deliberately only a state. No map, no distance, no coordinates and no
/// sample count: nothing that has been implemented can be shown as a
/// measurement yet, and a screen that implied otherwise would be claiming a
/// capability the app does not have.
///
/// It is shown because the alternative is worse. A driver who assumes their
/// route is being recorded, while permission is off or the recording stopped,
/// loses the shift's data and only finds out afterwards.
///
/// Recording now continues while the driver is in another app or the phone is
/// locked, which makes the opposite mistake possible: believing capture is
/// guaranteed. So the active state carries a line of its own saying what that
/// does and does not promise, rather than a green label and silence.
struct RouteCaptureStatusView: View {
    let state: RouteCaptureState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .dashFont(.status)
                .foregroundStyle(tint)

            if let detail {
                Text(detail)
                    .dashFont(.supporting)
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
        case .pausedInBackground: "Route recording paused"
        case .shiftPaused: "Route recording stopped"
        case .routeSuspended: "Route recording stopped while parked"
        case .unavailable(.permissionRequired): "Location permission required"
        case .unavailable: "Location unavailable"
        }
    }

    private var symbol: String {
        switch state {
        case .idle, .tracking: "location.fill"
        case .pausedInBackground: "pause.circle"
        case .shiftPaused: "pause.circle"
        case .routeSuspended: "parkingsign.circle"
        case .unavailable: "location.slash"
        }
    }

    private var tint: Color {
        switch state {
        case .idle, .tracking: .green
        case .pausedInBackground: .orange
        case .shiftPaused: .orange
        case .routeSuspended: .orange
        case .unavailable: .secondary
        }
    }

    private var detail: String? {
        switch state {
        case .idle, .tracking:
            """
            Recording continues while you use other apps or the screen is locked. \
            iOS can still stop it, and it does not restart on its own if DashPilot is closed.
            """
        case .pausedInBackground:
            "Recording starts when DashPilot is open. Open the app to record the rest of this shift."
        case .shiftPaused:
            """
            The shift is paused, so nothing is being recorded. Resuming starts a new recording, and \
            the distance between where you paused and where you resume is not counted.
            """
        case .routeSuspended:
            """
            You recorded the vehicle as parked, so nothing is being recorded while you are away from \
            it. Your shift is still running. Resuming starts a new recording, and the distance between \
            where you parked and where you drive off from is not counted.
            """
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
        RouteCaptureStatusView(state: .shiftPaused)
        RouteCaptureStatusView(state: .unavailable(.permissionRequired))
        RouteCaptureStatusView(state: .unavailable(.locationServicesOff))
        RouteCaptureStatusView(state: .unavailable(.storeUnavailable))
    }
}
#endif
