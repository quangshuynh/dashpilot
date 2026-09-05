import Foundation

/// A failure reported by the platform while location updates are running.
nonisolated enum LocationTrackingFailure: Equatable, Sendable {
    /// No position could be determined right now. Core Location keeps trying,
    /// so this is not a reason to tear capture down — an underground garage or
    /// a dead spot resolves itself.
    case temporarilyUnavailable
    /// Updates will not produce positions until something changes outside the
    /// app.
    case unavailable
}

/// The seam between route capture and Core Location's position updates.
///
/// Separate from ``LocationAuthorizationProviding`` on purpose. Authorization
/// answers "may the app read location"; this answers "here is a position".
/// Merging them would produce one type that owns permission, updates, filtering
/// and everything added later.
///
/// The surface is the smallest that supports foreground capture: start, stop,
/// a stream of candidates and a failure channel. Regions, headings, visits,
/// significant-change monitoring and background updates are absent because
/// nothing implemented uses them.
///
/// It exists to make the pipeline testable. Filtering, shift association and
/// persistence have to be verifiable from synthetic samples, without a
/// simulator location feed.
@MainActor
protocol LocationTrackingProviding: AnyObject {
    /// Whether the platform is currently delivering updates.
    var isUpdating: Bool { get }

    /// Invoked for every position the platform produces, before any judgement.
    var onSample: ((LocationSample) -> Void)? { get set }

    /// Invoked when the platform reports it cannot produce positions.
    var onFailure: ((LocationTrackingFailure) -> Void)? { get set }

    /// Begins delivering positions. Callers are responsible for checking that
    /// location is authorized and usable first.
    func startUpdates()

    /// Stops delivering positions.
    func stopUpdates()
}
