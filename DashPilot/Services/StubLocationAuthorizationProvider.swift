#if DEBUG
import Foundation

/// A ``LocationAuthorizationProviding`` whose state is set by the caller.
///
/// Lets tests and previews drive every authorization, accuracy and services
/// combination — including the ones a simulator cannot easily be put into —
/// without touching the real permission database or presenting a system alert.
/// Debug builds only; it is never compiled into a release of the app.
@MainActor
final class StubLocationAuthorizationProvider: LocationAuthorizationProviding {
    private(set) var authorization: LocationAuthorization
    var onChange: ((LocationAuthorization) -> Void)?

    /// How many times permission has been asked for. Tests assert on this to
    /// show that a request is made exactly when it can achieve something.
    private(set) var requestCount = 0

    /// How many times ``refresh()`` has been called.
    private(set) var refreshCount = 0

    /// What the platform would report after a prompt is answered, or `nil` to
    /// model a prompt that is never answered.
    var authorizationAfterRequest: LocationAuthorization?

    init(_ authorization: LocationAuthorization) {
        self.authorization = authorization
    }

    convenience init(
        servicesEnabled: Bool = true,
        status: LocationAuthorizationStatus = .notDetermined,
        accuracy: LocationAccuracyAuthorization = .full
    ) {
        self.init(
            LocationAuthorization(servicesEnabled: servicesEnabled, status: status, accuracy: accuracy)
        )
    }

    func requestWhenInUseAuthorization() {
        requestCount += 1
        if let answered = authorizationAfterRequest {
            update(to: answered)
        }
    }

    func refresh() {
        refreshCount += 1
    }

    /// Simulates the platform reporting a change, as Core Location's delegate
    /// callback would.
    func update(to authorization: LocationAuthorization) {
        guard authorization != self.authorization else { return }
        self.authorization = authorization
        onChange?(authorization)
    }

    func update(
        servicesEnabled: Bool? = nil,
        status: LocationAuthorizationStatus? = nil,
        accuracy: LocationAccuracyAuthorization? = nil
    ) {
        update(
            to: LocationAuthorization(
                servicesEnabled: servicesEnabled ?? authorization.servicesEnabled,
                status: status ?? authorization.status,
                accuracy: accuracy ?? authorization.accuracy
            )
        )
    }
}
#endif
