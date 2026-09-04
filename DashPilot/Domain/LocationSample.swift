import Foundation

/// One candidate position produced by the tracking layer.
///
/// A plain value rather than a `CLLocation` so the acceptance policy, the
/// services and their tests can be written without Core Location. It carries
/// only the four facts the capture pipeline uses: when the fix was taken, where
/// it was, and how good it is. Speed, course, altitude and vertical accuracy are
/// deliberately absent — nothing implemented needs them, and a coordinate
/// history is sensitive enough that fields should be added when a feature
/// requires them rather than because `CLLocation` exposes them.
nonisolated struct LocationSample: Equatable, Sendable {
    /// When the platform fixed this position, not when it was delivered.
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Radius of uncertainty in metres. Core Location reports a negative value
    /// when the position is invalid, which is preserved here rather than
    /// normalised away, so the acceptance policy can reject it explicitly.
    var horizontalAccuracy: Double

    init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}
