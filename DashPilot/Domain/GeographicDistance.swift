import Foundation

/// Distance between two positions on the Earth's surface.
///
/// One implementation, used by both the capture filter's movement rules and the
/// mileage calculation, so a route measured for the driver and a route judged
/// for storage cannot disagree about how far apart two positions are.
///
/// Core Location's own `CLLocation.distance(from:)` would be equally correct and
/// slightly more precise, but it would put Core Location inside the domain
/// layer, where the calculations are deliberately framework-free and testable
/// without a device. The error that buys is far smaller than the error already
/// present in the positions being measured.
nonisolated enum GeographicDistance {
    /// Mean Earth radius in metres.
    ///
    /// The Earth is an ellipsoid, so a sphere of this radius is an
    /// approximation: it is accurate to roughly a few tenths of a percent, or a
    /// few metres per kilometre driven. Retained positions carry error radii of
    /// up to 100 m, and the app never claims mileage precise enough for tax
    /// reporting, so a spherical model is the honest level of precision here.
    static let earthRadius: Double = 6_371_008.8

    /// Great-circle distance in metres.
    ///
    /// Haversine rather than a flat latitude/longitude difference: a degree of
    /// longitude is a different distance at every latitude, so treating
    /// coordinates as a plane produces an error that grows with how far north or
    /// south the driver is working.
    static func metres(
        fromLatitude startLatitude: Double,
        longitude startLongitude: Double,
        toLatitude endLatitude: Double,
        longitude endLongitude: Double
    ) -> Double {
        let startLatitudeRadians = startLatitude * .pi / 180
        let endLatitudeRadians = endLatitude * .pi / 180
        let deltaLatitude = (endLatitude - startLatitude) * .pi / 180
        let deltaLongitude = (endLongitude - startLongitude) * .pi / 180

        let haversine = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(startLatitudeRadians) * cos(endLatitudeRadians)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * earthRadius * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
    }
}
