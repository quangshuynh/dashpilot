import Foundation
import OSLog

/// The app's view of its permission to read location.
///
/// Responsibilities are deliberately narrow: hold the current
/// ``LocationAuthorization``, keep it in step with the platform, and request
/// permission when — and only when — asking can achieve something. It does not
/// start location updates, record coordinates, or know what location will
/// eventually be used for. Tracking belongs to a separate service so this one
/// does not grow into an object that owns permission, recording, mileage and
/// analytics at once.
///
/// `@MainActor` because it drives visible state; SwiftUI observes it directly.
@MainActor
@Observable
final class LocationAuthorizationService {
    /// The current permission facts. Read by the interface; never set from it.
    private(set) var authorization: LocationAuthorization

    @ObservationIgnored private let provider: any LocationAuthorizationProviding

    /// The shipping configuration, backed by Core Location.
    convenience init() {
        self.init(provider: CoreLocationAuthorizationProvider())
    }

    init(provider: any LocationAuthorizationProviding) {
        self.provider = provider
        authorization = provider.authorization

        provider.onChange = { [weak self] updated in
            self?.apply(updated)
        }

        AppLog.location.info(
            "Location authorization observed: \(Self.describe(self.authorization), privacy: .public)"
        )
    }

    /// Asks iOS to present the When In Use permission prompt.
    ///
    /// Refused unless the status is not determined. iOS presents the prompt
    /// exactly once, so re-requesting after a denial does nothing visible: a
    /// button that appeared to do nothing would read as a broken app, and the
    /// driver's real recovery is in Settings.
    func requestAuthorization() {
        guard authorization.canRequestAuthorization else {
            AppLog.location.notice(
                "Ignored an authorization request in state \(Self.describe(self.authorization), privacy: .public); the system prompt is only shown once"
            )
            return
        }
        provider.requestWhenInUseAuthorization()
    }

    /// Re-reads platform state that arrives without a callback.
    ///
    /// Called when the app returns to the foreground: a driver who changes
    /// Location Services or the app's permission in Settings comes back to a
    /// screen that has to already be correct.
    func refresh() {
        provider.refresh()
    }

    private func apply(_ updated: LocationAuthorization) {
        let previous = authorization
        guard updated != previous else { return }
        authorization = updated

        if updated.status != previous.status {
            AppLog.location.info(
                "Authorization changed: \(Self.describe(status: previous.status), privacy: .public) -> \(Self.describe(status: updated.status), privacy: .public)"
            )
        }
        if updated.servicesEnabled != previous.servicesEnabled {
            AppLog.location.info(
                "Location Services availability changed: enabled=\(updated.servicesEnabled, privacy: .public)"
            )
        }
        if updated.accuracy != previous.accuracy {
            AppLog.location.info(
                "Accuracy authorization changed: \(Self.describe(accuracy: previous.accuracy), privacy: .public) -> \(Self.describe(accuracy: updated.accuracy), privacy: .public)"
            )
        }
    }

    // MARK: Log descriptions
    //
    // Permission state is not sensitive; coordinates are, and none are read by
    // this service, so nothing here can leak a location.

    private static func describe(_ authorization: LocationAuthorization) -> String {
        let accuracy = authorization.grantedAccuracy.map(describe(accuracy:)) ?? "n/a"
        return "status=\(describe(status: authorization.status)) servicesEnabled=\(authorization.servicesEnabled) accuracy=\(accuracy)"
    }

    private static func describe(status: LocationAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .authorizedWhenInUse: "authorizedWhenInUse"
        case .authorizedAlways: "authorizedAlways"
        case .unrecognised(let rawValue): "unrecognised(\(rawValue))"
        }
    }

    private static func describe(accuracy: LocationAccuracyAuthorization) -> String {
        switch accuracy {
        case .full: "full"
        case .reduced: "reduced"
        case .unrecognised(let rawValue): "unrecognised(\(rawValue))"
        }
    }
}
