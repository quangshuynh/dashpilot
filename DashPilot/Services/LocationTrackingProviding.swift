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
/// The surface is the smallest that supports the capture the app implements:
/// start, stop, a stream of candidates, a failure channel, and whether this
/// build may keep an already running session going once the app is no longer in
/// front. Regions, headings, visits and significant-change monitoring are absent
/// because nothing implemented uses them.
///
/// It exists to make the pipeline testable. Filtering, shift association and
/// persistence have to be verifiable from synthetic samples, without a
/// simulator location feed.
@MainActor
protocol LocationTrackingProviding: AnyObject {
    /// Whether the platform is currently delivering updates.
    var isUpdating: Bool { get }

    /// Whether this build may keep delivering updates while the app is not in
    /// the foreground.
    ///
    /// A property of the *build*, not of the moment: it is what the app declared
    /// to iOS, so it cannot change while the app runs. It is exposed because
    /// setting the manager's background flag without the matching declaration
    /// terminates the process, and because the capture service has to know
    /// whether leaving the foreground is a continuation or a gap.
    var supportsBackgroundUpdates: Bool { get }

    /// Whether the platform has actually been told to deliver updates outside
    /// the foreground right now.
    ///
    /// Separate from ``supportsBackgroundUpdates`` because permission to ask and
    /// having asked are different facts. It is set while a session is running
    /// and cleared when it stops, so the app never holds the background grant
    /// open over a shift it is not recording.
    var allowsBackgroundUpdates: Bool { get }

    /// Invoked for every position the platform produces, before any judgement.
    var onSample: ((LocationSample) -> Void)? { get set }

    /// Invoked when the platform reports it cannot produce positions.
    var onFailure: ((LocationTrackingFailure) -> Void)? { get set }

    /// Begins delivering positions, and asks for them to continue outside the
    /// foreground when this build may.
    ///
    /// Callers are responsible for checking that location is authorized and
    /// usable first, and for only starting while the app is in the foreground:
    /// When In Use authorization lets a running session continue into the
    /// background, not a new one begin there.
    func startUpdates()

    /// Stops delivering positions and gives up the background grant with them.
    func stopUpdates()
}
