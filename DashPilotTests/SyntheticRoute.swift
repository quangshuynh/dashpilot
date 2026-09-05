import Foundation
@testable import DashPilot

/// Builds synthetic positions for the capture tests.
///
/// The origin is a round number chosen for arithmetic, not a place anyone has
/// driven, and every position is derived from it by an explicit offset. No real
/// route, address or personal location history appears in this repository.
@MainActor
enum SyntheticRoute {
    static let originLatitude = 40.0
    static let originLongitude = -75.0

    /// Metres per degree of latitude, close enough for offsets of a few hundred
    /// metres and exact enough for the tests to assert on.
    static let metresPerDegreeLatitude = 111_320.0

    /// A position `northMetres` north of the origin.
    static func sample(
        at timestamp: Date,
        northMetres: Double = 0,
        horizontalAccuracy: Double = 8
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: originLatitude + northMetres / metresPerDegreeLatitude,
            longitude: originLongitude,
            horizontalAccuracy: horizontalAccuracy
        )
    }

    /// A stored position `northMetres` north of the origin, recorded in
    /// `captureSessionID`.
    ///
    /// `nil` for the session is how a position stored before schema v3 is
    /// represented: continuity around it was never recorded.
    static func point(
        at timestamp: Date,
        northMetres: Double = 0,
        captureSessionID: UUID?
    ) -> RoutePoint {
        RoutePoint(
            timestamp: timestamp,
            latitude: originLatitude + northMetres / metresPerDegreeLatitude,
            longitude: originLongitude,
            captureSessionID: captureSessionID
        )
    }

    /// Whether a measured distance matches what the offsets describe.
    ///
    /// Offsets are built from a rounded metres-per-degree constant and measured
    /// on a spherical Earth, so the two differ by about a tenth of a percent.
    /// The tolerance is wide enough to ignore that and far too narrow to hide a
    /// segment counted twice, a gap measured across, or a missing leg.
    static func isCloseEnough(_ measured: Double, to expected: Double, tolerance: Double = 0.003) -> Bool {
        abs(measured - expected) <= max(1, abs(expected) * tolerance)
    }
}
