import Foundation

/// The seam between the app's authorization logic and Core Location.
///
/// This is intentionally the smallest surface that supports the current
/// behaviour: read the permission facts, be told when they change, and ask for
/// permission once. It is *not* a wrapper around Core Location in general —
/// location updates, regions, headings and accuracy escalation are not here,
/// and should get their own seam when a feature actually needs them.
///
/// Its purpose is testability: application behaviour around denied, restricted,
/// reduced-accuracy and services-disabled states has to be verifiable without a
/// simulator permission database or a tapped system alert.
@MainActor
protocol LocationAuthorizationProviding: AnyObject {
    /// The permission facts as last read from the platform.
    var authorization: LocationAuthorization { get }

    /// Invoked whenever ``authorization`` changes. Set by the owning service.
    var onChange: ((LocationAuthorization) -> Void)? { get set }

    /// Asks the platform to present the When In Use permission prompt.
    ///
    /// Callers are responsible for only asking when the prompt can actually be
    /// shown; the platform silently ignores the request otherwise.
    func requestWhenInUseAuthorization()

    /// Re-reads state the platform does not report through a callback.
    func refresh()
}
