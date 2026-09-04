import Foundation

/// Whether the user has granted DashPilot permission to read the device location.
///
/// This mirrors `CLAuthorizationStatus` rather than reusing it so the rest of the
/// app can reason about permission without importing Core Location, and so an
/// unrecognised platform value has somewhere to go instead of being forced into
/// a case that means something else.
nonisolated enum LocationAuthorizationStatus: Equatable, Sendable {
    /// The user has not been asked yet. This is the only state in which iOS will
    /// present the permission prompt.
    case notDetermined
    /// The user was asked and declined, or later turned the permission off.
    case denied
    /// Permission is withheld by a restriction the user cannot lift from within
    /// Settings — parental controls or a device management profile.
    case restricted
    /// Granted while the app is in use.
    case authorizedWhenInUse
    /// Granted at all times, including background delivery.
    case authorizedAlways
    /// A value the platform reports that this app does not recognise.
    ///
    /// Treated as "no location available" and never as a grant, so a future
    /// Core Location case cannot accidentally be read as permission.
    case unrecognised(rawValue: Int)

    /// Whether the app may read location at all in this state.
    var grantsAccess: Bool {
        switch self {
        case .authorizedWhenInUse, .authorizedAlways: true
        case .notDetermined, .denied, .restricted, .unrecognised: false
        }
    }
}

/// How precise the granted location is.
///
/// Deliberately separate from ``LocationAuthorizationStatus``: a driver can grant
/// permission and still withhold precise location, which is an authorized state
/// with materially different measurement quality. Collapsing the two into one
/// enum would hide that.
nonisolated enum LocationAccuracyAuthorization: Equatable, Sendable {
    /// Precise location.
    case full
    /// Approximate location. Core Location reports a coarse, periodically
    /// updated position rather than a precise fix.
    case reduced
    /// A value the platform reports that this app does not recognise.
    case unrecognised(rawValue: Int)
}

/// Everything the app knows about its permission to read location.
///
/// The three facts are stored separately because the platform reports them
/// separately and they fail independently: system-wide Location Services can be
/// switched off while this app is still authorized, and an authorized app can
/// still be limited to reduced accuracy.
nonisolated struct LocationAuthorization: Equatable, Sendable {
    /// Whether Location Services is enabled for the device as a whole.
    var servicesEnabled: Bool
    var status: LocationAuthorizationStatus
    /// As reported by the platform. Only meaningful once ``status`` grants
    /// access — see ``grantedAccuracy``.
    var accuracy: LocationAccuracyAuthorization

    init(
        servicesEnabled: Bool,
        status: LocationAuthorizationStatus,
        accuracy: LocationAccuracyAuthorization
    ) {
        self.servicesEnabled = servicesEnabled
        self.status = status
        self.accuracy = accuracy
    }

    /// Whether the app can currently read location: it needs both the
    /// system-wide switch and its own grant.
    var isUsable: Bool { servicesEnabled && status.grantsAccess }

    /// The accuracy actually in force, or `nil` when no permission is granted.
    ///
    /// Core Location reports an accuracy value even before the user has been
    /// asked, which would otherwise read as "full accuracy granted".
    var grantedAccuracy: LocationAccuracyAuthorization? {
        status.grantsAccess ? accuracy : nil
    }

    /// Whether iOS would present the permission prompt if asked now.
    ///
    /// The system shows it exactly once, while the status is not determined.
    /// Asking in any other state is a no-op, so the app must not offer it as an
    /// action the driver can keep tapping.
    var canRequestAuthorization: Bool { status == .notDetermined }

    /// The single condition the interface should describe.
    ///
    /// Precedence is deliberate:
    ///
    /// 1. `restricted` outranks everything, because enabling Location Services
    ///    or opening Settings will not give this app permission, and offering
    ///    either would be a false promise.
    /// 2. Location Services being off outranks the app's own grant, because
    ///    nothing works until it is on — an app that is authorized still cannot
    ///    read location, and that has to be said plainly.
    /// 3. Otherwise the app's own authorization is what matters.
    var condition: Condition {
        if case .restricted = status { return .restricted }
        guard servicesEnabled else { return .servicesDisabled }

        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorizedWhenInUse: return .authorized(scope: .whenInUse, accuracy: accuracy)
        case .authorizedAlways: return .authorized(scope: .always, accuracy: accuracy)
        case .restricted: return .restricted
        case .unrecognised(let rawValue): return .unrecognised(rawValue: rawValue)
        }
    }

    /// What, if anything, the driver can do about the current condition.
    var recovery: Recovery {
        switch condition {
        case .notDetermined: .requestAuthorization
        // Only the app's own permission can be re-enabled from its Settings
        // page; the rest have no action this app can honestly offer.
        case .denied: .openSettings
        case .servicesDisabled: .enableLocationServices
        case .restricted, .authorized, .unrecognised: .none
        }
    }

    /// Which of the platform's grants is held. Recorded because the two differ
    /// in what they permit later, not because the app uses `always` today.
    nonisolated enum AuthorizationScope: Equatable, Sendable {
        case whenInUse
        case always
    }

    /// The mutually exclusive states the interface explains.
    nonisolated enum Condition: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case servicesDisabled
        case authorized(scope: AuthorizationScope, accuracy: LocationAccuracyAuthorization)
        case unrecognised(rawValue: Int)
    }

    /// The recovery path offered to the driver.
    ///
    /// `enableLocationServices` carries no deep link on purpose: iOS exposes a
    /// URL for an app's own settings page, not for the system-wide Location
    /// Services switch, so the app describes where to go rather than opening
    /// somewhere that does not contain the control.
    nonisolated enum Recovery: Equatable, Sendable {
        case requestAuthorization
        case openSettings
        case enableLocationServices
        case none
    }
}
