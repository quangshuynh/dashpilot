import SwiftUI
import UIKit

/// Explains DashPilot's location permission and offers the one recovery that
/// applies to the current state.
///
/// The panel never asks for permission on its own. iOS presents the prompt
/// once, and a prompt that appears at launch — before the driver has any reason
/// to grant it — is the surest way to have it declined for good. The request is
/// always a deliberate tap.
///
/// Everything here is a single line of explanation and at most one large
/// button, because a driver may read this in a parked car.
struct LocationAuthorizationPanel: View {
    @Environment(LocationAuthorizationService.self) private var service
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .accessibilityIdentifier("locationAuthorizationStatus")

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            action
        }
        .padding(.vertical, 8)
        // A container rather than a combined element: the recovery button has
        // to stay individually reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("locationAuthorizationPanel")
    }

    private var authorization: LocationAuthorization { service.authorization }

    @ViewBuilder
    private var action: some View {
        switch authorization.recovery {
        case .requestAuthorization:
            Button {
                service.requestAuthorization()
            } label: {
                Text("Enable Location").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("enableLocationButton")

        case .openSettings:
            // Opens DashPilot's own page in Settings, which is where its
            // location permission can be switched back on.
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    openURL(settingsURL)
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("openLocationSettingsButton")
            }

        // Neither a system-wide switch nor a device restriction can be reached
        // from this app, so no button is offered that would not work.
        case .enableLocationServices, .none:
            EmptyView()
        }
    }

    private var title: String {
        switch authorization.condition {
        case .notDetermined: "Location Not Enabled"
        case .denied: "Location Access Off"
        case .restricted: "Location Access Restricted"
        case .servicesDisabled: "Location Services Off"
        case .authorized(_, .reduced): "Approximate Location"
        case .authorized: "Location Access On"
        case .unrecognised: "Location Status Unknown"
        }
    }

    private var symbol: String {
        switch authorization.condition {
        case .authorized(_, .full): "location.fill"
        case .authorized: "location.circle"
        case .notDetermined: "location"
        case .denied, .servicesDisabled, .restricted, .unrecognised: "location.slash"
        }
    }

    private var tint: Color {
        switch authorization.condition {
        case .authorized(_, .full): .green
        case .authorized: .orange
        case .notDetermined: .accentColor
        case .denied, .servicesDisabled, .restricted, .unrecognised: .secondary
        }
    }

    /// Copy describes what the permission allows, and says plainly what the app
    /// does with it: it records the route of a running shift while the app is
    /// open, and nothing at any other time. Permission granted is not the same
    /// as a route being captured — whether capture is actually running is shown
    /// on the running shift itself, not here.
    private var explanation: String {
        switch authorization.condition {
        case .notDetermined:
            "DashPilot needs your permission before it can record where you drive during a shift."
        case .denied:
            "Location access is off for DashPilot, so it cannot record your route during a shift. You can turn it back on in Settings."
        case .restricted:
            "Location access is restricted on this device and cannot be changed from DashPilot. This is usually a parental control or a device management profile."
        case .servicesDisabled:
            "Location Services is off for this device, so no app can use location. Turn it on in Settings, under Privacy & Security."
        case .authorized(_, .full):
            "DashPilot can use precise location while a shift is running and the app is open. Your route is stored on this device only."
        case .authorized(_, .reduced):
            "DashPilot has approximate location only, which is usually too imprecise to record a useful route. Precise Location can be turned on in Settings."
        case .authorized(_, .unrecognised):
            "DashPilot has location access, but this version of iOS reports an accuracy setting it does not recognise."
        case .unrecognised:
            "DashPilot cannot read its location permission on this version of iOS, so location features are unavailable."
        }
    }
}

#if DEBUG
private func panelPreview(_ authorization: LocationAuthorization) -> some View {
    List {
        Section {
            LocationAuthorizationPanel()
        }
    }
    .environment(LocationAuthorizationService(provider: StubLocationAuthorizationProvider(authorization)))
}

#Preview("Not determined") {
    panelPreview(LocationAuthorization(servicesEnabled: true, status: .notDetermined, accuracy: .full))
}

#Preview("Authorized, full accuracy") {
    panelPreview(LocationAuthorization(servicesEnabled: true, status: .authorizedWhenInUse, accuracy: .full))
}

#Preview("Authorized, reduced accuracy") {
    panelPreview(LocationAuthorization(servicesEnabled: true, status: .authorizedWhenInUse, accuracy: .reduced))
}

#Preview("Denied") {
    panelPreview(LocationAuthorization(servicesEnabled: true, status: .denied, accuracy: .full))
}

#Preview("Restricted") {
    panelPreview(LocationAuthorization(servicesEnabled: true, status: .restricted, accuracy: .full))
}

#Preview("Services disabled") {
    panelPreview(LocationAuthorization(servicesEnabled: false, status: .authorizedWhenInUse, accuracy: .full))
}
#endif
