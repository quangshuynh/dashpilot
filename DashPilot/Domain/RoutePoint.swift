import Foundation

/// One retained position of a shift's route, as the mileage calculation reads it.
///
/// A plain value rather than the stored ``RouteSample``, so distance can be
/// calculated and tested without SwiftData, a container or a running app. It
/// carries only what measuring a route needs: when the position was fixed,
/// where it was, and whether it was recorded without an interruption in capture.
///
/// Horizontal accuracy is deliberately absent. The acceptance policy has already
/// used it to decide the position was worth keeping, and nothing in the distance
/// calculation weighs positions by their error radius; a field that no rule
/// reads would only suggest a precision the result does not have.
nonisolated struct RoutePoint: Equatable, Sendable {
    /// When the platform fixed this position. Route order is defined by this.
    var timestamp: Date
    var latitude: Double
    var longitude: Double

    /// The uninterrupted period of capture this position was recorded in.
    ///
    /// Two positions sharing an identifier were recorded without capture
    /// stopping in between, which is what makes the distance between them
    /// trustworthy. A different identifier on either side means capture stopped
    /// and restarted — the app was backgrounded, permission was lost, a save
    /// failed, or the process was replaced — and whatever was driven in between
    /// was not recorded.
    ///
    /// `nil` means the position was stored before DashPilot recorded capture
    /// continuity (schema v2 and earlier). Continuity around it is unknown, not
    /// proven, and the calculation says so rather than assuming either way.
    var captureSessionID: UUID?

    init(timestamp: Date, latitude: Double, longitude: Double, captureSessionID: UUID?) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.captureSessionID = captureSessionID
    }
}
