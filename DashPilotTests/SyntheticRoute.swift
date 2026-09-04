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
}
