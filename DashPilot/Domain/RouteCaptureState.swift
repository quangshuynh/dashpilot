import Foundation

/// Why route capture is not running.
nonisolated enum RouteCaptureUnavailableReason: Equatable, Sendable {
    /// The driver has not been asked for location permission yet.
    case permissionRequired
    /// Permission was declined or later switched off.
    case permissionDenied
    /// Permission is withheld by a device restriction the app cannot lift.
    case permissionRestricted
    /// The system-wide Location Services switch is off.
    case locationServicesOff
    /// The platform reports an authorization state this app does not recognise.
    case authorizationUnknown
    /// Core Location accepted the request but reported that it cannot produce
    /// positions.
    case locationFailed
    /// The local store could not be read or written, so samples cannot be
    /// associated with a shift or kept.
    case storeUnavailable
}

/// What route capture is doing, as far as the driver is concerned.
///
/// Deliberately a small closed set. Tracking state has to be visible — a driver
/// who believes their route is being recorded when it is not has lost the
/// shift's data — so every way capture can fail resolves to one of these rather
/// than to silence.
nonisolated enum RouteCaptureState: Equatable, Sendable {
    /// No shift is running, so there is nothing to capture.
    case idle
    /// Samples are being collected and retained.
    case tracking
    /// A shift is running but DashPilot is not in the foreground.
    ///
    /// Capture is foreground-only, so this is a normal, expected state rather
    /// than a failure. It is named rather than hidden because the route has a
    /// gap in it.
    case pausedInBackground
    /// A shift is running and capture cannot proceed.
    case unavailable(RouteCaptureUnavailableReason)

    /// Whether samples are actually being retained right now.
    var isCapturing: Bool { self == .tracking }

    /// Whether a shift is running, in whatever capture state.
    var accompaniesActiveShift: Bool { self != .idle }
}

extension RouteCaptureUnavailableReason {
    /// The reason capture cannot run given the app's permission state, or `nil`
    /// if permission is not the obstacle.
    ///
    /// Derived from ``LocationAuthorization`` rather than restated: the
    /// authorization layer stays the one place permission is interpreted, and
    /// this only translates its conclusion into the capture vocabulary.
    init?(_ authorization: LocationAuthorization) {
        guard !authorization.isUsable else { return nil }
        switch authorization.condition {
        case .notDetermined: self = .permissionRequired
        case .denied: self = .permissionDenied
        case .restricted: self = .permissionRestricted
        case .servicesDisabled: self = .locationServicesOff
        case .unrecognised: self = .authorizationUnknown
        // `isUsable` is false, so an authorized condition here means the
        // system-wide switch is off; `condition` reports that case first.
        case .authorized: self = .locationServicesOff
        }
    }
}
