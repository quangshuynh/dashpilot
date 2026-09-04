#if DEBUG
import Foundation

/// A ``LocationTrackingProviding`` whose positions are supplied by the caller.
///
/// The capture pipeline has to be verifiable: that a good sample is retained,
/// that a duplicate, a stale fix, a wild jump or a sample from outside the shift
/// window is not, and that nothing at all is kept once a shift has ended. None
/// of that can be demonstrated against a simulator location feed, which delivers
/// whatever it likes when it likes.
///
/// So this stub replaces Core Location and nothing else. Coordinates fed through
/// it in tests and previews are synthetic. Debug builds only.
@MainActor
final class StubLocationTrackingProvider: LocationTrackingProviding {
    private(set) var isUpdating = false

    var onSample: ((LocationSample) -> Void)?
    var onFailure: ((LocationTrackingFailure) -> Void)?

    /// How many times updates have been started. Tests assert on this to show
    /// that capture starts when it should and is not restarted needlessly.
    private(set) var startCount = 0

    /// How many times updates have been stopped.
    private(set) var stopCount = 0

    func startUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        startCount += 1
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        stopCount += 1
    }

    /// Delivers a candidate as Core Location's delegate callback would.
    ///
    /// Silently does nothing while updates are stopped, matching the real
    /// provider: a stopped manager produces no callbacks.
    func emit(_ sample: LocationSample) {
        guard isUpdating else { return }
        onSample?(sample)
    }

    /// Delivers a candidate even though updates are stopped.
    ///
    /// Only for testing the pipeline's own guards; the platform does not do
    /// this.
    func emitWhileStopped(_ sample: LocationSample) {
        onSample?(sample)
    }

    func fail(_ failure: LocationTrackingFailure) {
        onFailure?(failure)
    }
}
#endif
