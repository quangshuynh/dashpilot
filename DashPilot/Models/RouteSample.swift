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

    /// The uninterrupted period of capture this sample was recorded in.
    ///
    /// Timestamps alone cannot tell a route apart from the gaps in it: capture
    /// stopping for twenty seconds while the app is backgrounded and a vehicle
    /// waiting twenty seconds at a light both look like twenty seconds without
    /// a sample. This is the smallest fact that separates them. The capture
    /// service mints one identifier each time updates start and stamps every
    /// sample it retains with it, so two samples sharing one were recorded with
    /// nothing in between, and a change of identifier is a gap the mileage
    /// calculation must not measure across.
    ///
    /// Optional because samples written before schema v3 do not have one. Their
    /// continuity is unknown rather than proven, and nothing backfills a value
    /// that cannot be derived.
    private(set) var captureSessionID: UUID?

    /// The shift this sample belongs to.
    ///
    /// Optional because SwiftData models the inverse of a to-many relationship
    /// that way, not because a sample without a shift is meaningful: the
    /// initializer requires one, and `Shift.routeSamples` cascades on delete so
    /// a sample cannot outlive its shift.
    private(set) var shift: Shift?

    init(
        shift: Shift,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        captureSessionID: UUID?
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.captureSessionID = captureSessionID
        self.shift = shift
    }

    /// The capture session is required rather than defaulted: a sample written
    /// without one claims unknown continuity, and that is a statement about the
    /// data which every caller should have to make deliberately.
    convenience init(shift: Shift, sample: LocationSample, captureSessionID: UUID?) {
        self.init(
            shift: shift,
            timestamp: sample.timestamp,
            latitude: sample.latitude,
            longitude: sample.longitude,
            horizontalAccuracy: sample.horizontalAccuracy,
            captureSessionID: captureSessionID
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

    /// The stored position as the value type the mileage calculation reasons about.
    var routePoint: RoutePoint {
        RoutePoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            captureSessionID: captureSessionID
        )
    }
}
