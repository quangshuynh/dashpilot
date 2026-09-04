import CoreLocation
import Foundation
import OSLog

/// The Core Location implementation of ``LocationAuthorizationProviding``.
///
/// Owns the one `CLLocationManager` the app needs today and uses it only to
/// read authorization and to request When In Use permission. It never starts
/// location updates, so no coordinate is produced, held or written anywhere by
/// this type.
@MainActor
final class CoreLocationAuthorizationProvider: NSObject, LocationAuthorizationProviding {
    private let manager: CLLocationManager

    private(set) var authorization: LocationAuthorization {
        didSet {
            guard authorization != oldValue else { return }
            onChange?(authorization)
        }
    }

    var onChange: ((LocationAuthorization) -> Void)?

    override init() {
        manager = CLLocationManager()
        // `CLLocationManager.locationServicesEnabled()` blocks, and Apple warns
        // against calling it on the main thread, so the authoritative value is
        // fetched off-main by `refresh()` immediately after init. Assuming the
        // switch is on until then keeps the app from flashing a "Location
        // Services are off" message at every launch for the common case.
        authorization = LocationAuthorization(
            servicesEnabled: true,
            status: LocationAuthorizationStatus(manager.authorizationStatus),
            accuracy: LocationAccuracyAuthorization(manager.accuracyAuthorization)
        )
        super.init()
        // Setting the delegate also delivers an immediate authorization callback.
        manager.delegate = self
        refresh()
    }

    func requestWhenInUseAuthorization() {
        // When In Use is the only scope the app has implemented behaviour for.
        // Requesting Always here because background route capture may exist
        // later would ask a driver to grant more than the app can currently
        // justify, and iOS will not re-prompt once a scope has been chosen.
        AppLog.location.info("Requesting When In Use authorization")
        manager.requestWhenInUseAuthorization()
    }

    /// Re-reads the system-wide Location Services switch.
    ///
    /// Core Location has no callback for it, so it is polled: once at init, and
    /// again whenever the app returns to the foreground or the authorization
    /// callback fires. A driver who turns it off has to leave the app to do so.
    func refresh() {
        let currentStatus = LocationAuthorizationStatus(manager.authorizationStatus)
        let currentAccuracy = LocationAccuracyAuthorization(manager.accuracyAuthorization)

        Task {
            let enabled = await Self.servicesEnabled()
            authorization = LocationAuthorization(
                servicesEnabled: enabled,
                status: currentStatus,
                accuracy: currentAccuracy
            )
        }
    }

    /// Reads the blocking Location Services check away from the main actor.
    private nonisolated static func servicesEnabled() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            CLLocationManager.locationServicesEnabled()
        }.value
    }
}

extension CoreLocationAuthorizationProvider: CLLocationManagerDelegate {
    /// Fires for authorization *and* accuracy changes, and once when the
    /// delegate is set.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Core Location delivers delegate callbacks on the run loop the manager
        // was created on, and this manager is created on the main actor.
        MainActor.assumeIsolated {
            refresh()
        }
    }
}

// MARK: - Platform mapping

extension LocationAuthorizationStatus {
    /// Maps Core Location's status, preserving anything unrecognised rather
    /// than defaulting it into a known case.
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorizedWhenInUse: self = .authorizedWhenInUse
        case .authorizedAlways: self = .authorizedAlways
        @unknown default:
            AppLog.location.fault(
                "Unrecognised CLAuthorizationStatus raw value \(status.rawValue, privacy: .public); treating as no access"
            )
            self = .unrecognised(rawValue: Int(status.rawValue))
        }
    }
}

extension LocationAccuracyAuthorization {
    init(_ accuracy: CLAccuracyAuthorization) {
        switch accuracy {
        case .fullAccuracy: self = .full
        case .reducedAccuracy: self = .reduced
        @unknown default:
            AppLog.location.fault(
                "Unrecognised CLAccuracyAuthorization raw value \(accuracy.rawValue, privacy: .public); treating as reduced"
            )
            self = .unrecognised(rawValue: Int(accuracy.rawValue))
        }
    }
}
