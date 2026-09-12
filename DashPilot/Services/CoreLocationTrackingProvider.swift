import CoreLocation
import Foundation
import OSLog

/// The Core Location implementation of ``LocationTrackingProviding``.
///
/// Owns a `CLLocationManager` used only for position updates. It makes no
/// judgement about the positions it forwards and writes nothing: every candidate
/// goes to ``LocationTrackingService``, which decides what to keep.
///
/// ## Continuing outside the foreground
///
/// The app declares the `location` background mode, and this type sets
/// `allowsBackgroundLocationUpdates` while a session is running so an update
/// stream started on screen keeps running when the driver switches to another
/// app or locks the phone. iOS shows its own indicator for the whole of that,
/// which is the disclosure the driver actually sees.
///
/// Two things are deliberately absent, and they are what keeps the app at When
/// In Use authorization:
///
/// - **Nothing starts a session from the background.** With When In Use, iOS
///   continues a stream that began in the foreground; it does not deliver one
///   that did not.
/// - **No significant-location-change or region monitoring**, so nothing here
///   ever relaunches the app. A process iOS terminates stays stopped until the
///   driver opens DashPilot again.
///
/// iOS guarantees no background execution, and nothing here pretends otherwise.
@MainActor
final class CoreLocationTrackingProvider: NSObject, LocationTrackingProviding {
    private let manager: CLLocationManager

    private(set) var isUpdating = false

    let supportsBackgroundUpdates: Bool

    private(set) var allowsBackgroundUpdates = false

    var onSample: ((LocationSample) -> Void)?
    var onFailure: ((LocationTrackingFailure) -> Void)?

    override init() {
        manager = CLLocationManager()
        supportsBackgroundUpdates = Self.bundleDeclaresLocationBackgroundMode()
        super.init()
        manager.delegate = self
        Self.configure(manager)
        if !supportsBackgroundUpdates {
            AppLog.routeCapture.notice(
                "This build declares no location background mode; capture will stop when the app leaves the foreground"
            )
        }
    }

    /// Whether the built app declares the `location` background mode.
    ///
    /// Read from the bundle rather than assumed. Assigning
    /// `allowsBackgroundLocationUpdates = true` without the declaration is not a
    /// no-op and not an error to catch: iOS raises an exception and the process
    /// dies. A build setting is easy to drop, and losing background capture is a
    /// far better failure than crashing the moment a driver starts a shift.
    private static func bundleDeclaresLocationBackgroundMode() -> Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }

    /// The manager settings route capture depends on.
    ///
    /// Separated from `init` so the policy can be asserted directly: every one
    /// of these is invisible from outside this type, and each is a choice with
    /// a consequence for what a shift records.
    ///
    /// - `desiredAccuracy`: best available. The point of capture is to describe
    ///   where a vehicle went, and a coarser setting would spend the same
    ///   battery on a route the acceptance policy would then reject.
    /// - `activityType`: tells Core Location the motion to expect, so it can
    ///   tune its own filtering for vehicle movement.
    /// - `distanceFilter`: none. Quality is judged in one place, by
    ///   ``RouteSampleFilter``, and splitting that decision between Core
    ///   Location and the app would make the retained route depend on two
    ///   policies.
    /// - `pausesLocationUpdatesAutomatically`: **off, and this is the one that
    ///   matters on a real shift.** Left at its default, iOS pauses updates
    ///   once it decides the device has stopped moving, which on a delivery
    ///   shift is a driver waiting at a pickup, and it does not resume them on
    ///   its own. The app would go on saying it was recording while it recorded
    ///   nothing for the rest of the shift. It stays off for as long as a shift
    ///   is being recorded, which is the whole of the time a session runs.
    static func configure(_ manager: CLLocationManager) {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Starts a session, asking for it to survive the app leaving the foreground.
    ///
    /// The background flag is set here rather than once at init so it is held
    /// only while a shift is actually being recorded. It is set *before*
    /// `startUpdatingLocation()`: a session that began without it does not
    /// acquire it by having the flag set afterwards.
    func startUpdates() {
        guard !isUpdating else { return }
        setAllowsBackgroundUpdates(supportsBackgroundUpdates)
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        setAllowsBackgroundUpdates(false)
    }

    private func setAllowsBackgroundUpdates(_ allowed: Bool) {
        guard allowed != allowsBackgroundUpdates else { return }
        // Guarded by the declaration check, not by a `try`: the platform raises
        // rather than throwing when the two disagree.
        guard !allowed || supportsBackgroundUpdates else { return }
        manager.allowsBackgroundLocationUpdates = allowed
        allowsBackgroundUpdates = allowed
        AppLog.routeCapture.info(
            "Background location updates allowed: \(allowed, privacy: .public)"
        )
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
