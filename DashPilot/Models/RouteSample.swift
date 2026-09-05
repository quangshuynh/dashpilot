import Foundation
import SwiftData

/// One retained position from a shift's route.
///
/// A route sample exists only as part of a shift. It is written by the capture
/// pipeline after the acceptance policy has judged the candidate, so every row
/// in this table is a position the app decided to trust.
///
/// The stored fields are the minimum the pipeline justifies. Core Location also
/// reports speed, course, altitude and their accuracies; none of them are kept,
/// because nothing implemented reads them and a coordinate history is sensitive
/// enough that each additional field needs a reason.
@Model
nonisolated final class RouteSample {
    /// When the position was fixed by the platform, not when it was delivered
    /// to the app. Ordering and every time-based calculation use this.
    private(set) var timestamp: Date

    private(set) var latitude: Double

    private(set) var longitude: Double

    /// Radius of uncertainty in metres, as reported when the fix was taken.
    /// Retained so a later calculation can weigh a position rather than
    /// treating every retained sample as equally good.
    private(set) var horizontalAccuracy: Double

    /// The shift this sample belongs to.
    ///
    /// Optional because SwiftData models the inverse of a to-many relationship
    /// that way, not because a sample without a shift is meaningful: the
    /// initializer requires one, and `Shift.routeSamples` cascades on delete so
    /// a sample cannot outlive its shift.
    private(set) var shift: Shift?

    init(shift: Shift, timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.shift = shift
    }

    convenience init(shift: Shift, sample: LocationSample) {
        self.init(
            shift: shift,
            timestamp: sample.timestamp,
            latitude: sample.latitude,
            longitude: sample.longitude,
            horizontalAccuracy: sample.horizontalAccuracy
        )
    }

    /// The stored position as the value type the capture pipeline reasons about.
    var locationSample: LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy
        )
    }
}
