import CoreLocation
import Foundation
import OSLog

/// The Core Location implementation of ``LocationTrackingProviding``.
///
/// Owns a `CLLocationManager` used only for foreground position updates. It
/// makes no judgement about the positions it forwards and writes nothing: every
/// candidate goes to ``LocationTrackingService``, which decides what to keep.
///
/// **Foreground only.** `allowsBackgroundLocationUpdates` is never set, the app
/// declares no background location mode, and nothing here starts significant
/// location change or region monitoring. iOS suspends the app shortly after it
/// leaves the foreground, and updates stop with it — the service stops them
/// explicitly first so the behaviour is the app's decision rather than a side
/// effect of being suspended.
@MainActor
final class CoreLocationTrackingProvider: NSObject, LocationTrackingProviding {
    private let manager: CLLocationManager

    private(set) var isUpdating = false

    var onSample: ((LocationSample) -> Void)?
    var onFailure: ((LocationTrackingFailure) -> Void)?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // Best available accuracy: the point of capture is to describe where a
        // vehicle went, and a coarser setting would spend the same battery on a
        // route the acceptance policy would then reject.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Tells Core Location the motion to expect. It uses this to tune its
        // own filtering for vehicle movement.
        manager.activityType = .automotiveNavigation
        // No distance filter: quality is judged in one place, by
        // `RouteSampleFilter`, and splitting that decision between Core Location
        // and the app would make the retained route depend on two policies.
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func startUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }
}

extension CoreLocationTrackingProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Core Location delivers delegate callbacks on the run loop the manager
        // was created on, and this manager is created on the main actor. The
        // same guarantee the authorization provider relies on.
        MainActor.assumeIsolated {
            guard isUpdating else { return }
            for location in locations {
                onSample?(LocationSample(location))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            let failure = LocationTrackingFailure(error)
            // The error code is a platform constant, not user data.
            AppLog.routeCapture.error(
                "Location updates failed (\(String(describing: failure), privacy: .public)): \((error as NSError).code, privacy: .public)"
            )
            onFailure?(failure)
        }
    }
}

// MARK: - Platform mapping

private extension LocationSample {
    /// Keeps only the fields route capture justifies. Speed, course, altitude
    /// and their accuracies are discarded here rather than carried inward.
    init(_ location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }
}

private extension LocationTrackingFailure {
    init(_ error: any Error) {
        guard let clError = error as? CLError else {
            self = .unavailable
            return
        }
        switch clError.code {
        // Core Location keeps trying after this one, so tearing capture down
        // would turn a tunnel into a permanently stopped recording.
        case .locationUnknown: self = .temporarilyUnavailable
        default: self = .unavailable
        }
    }
}
