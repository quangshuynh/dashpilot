import Foundation

/// Why a candidate sample was not retained.
///
/// The raw values are the strings written to the log. Every one of them
/// describes the *rule* that rejected the sample and never the sample itself,
/// so rejection logging cannot leak a position.
nonisolated enum RouteSampleRejection: String, Equatable, Sendable, CaseIterable {
    /// Latitude, longitude or both are outside the valid range, not finite, or
    /// the null island placeholder.
    case invalidCoordinate
    /// Core Location reports a negative or non-finite radius of uncertainty,
    /// which means the position itself is not valid.
    case invalidAccuracy
    /// The fix is valid but too imprecise to be worth keeping.
    case poorAccuracy
    /// The shift this sample would belong to has already ended.
    case shiftEnded
    /// The fix predates the start of the shift.
    case beforeShiftStart
    /// The fix is older than the pipeline is willing to accept, typically the
    /// cached last known position Core Location delivers when updates start.
    case stale
    /// Same timestamp as the last accepted sample.
    case duplicateTimestamp
    /// Earlier timestamp than the last accepted sample.
    case outOfOrder
    /// Too close to the last accepted sample to describe movement.
    case negligibleMovement
    /// Separation from the last accepted sample implies a speed no vehicle
    /// reaches, so one of the two positions is wrong.
    case implausibleSpeed
}

/// The outcome of judging one candidate sample.
nonisolated enum RouteSampleDecision: Equatable, Sendable {
    case accept
    case reject(RouteSampleRejection)

    var isAccepted: Bool {
        if case .accept = self { return true }
        return false
    }

    var rejection: RouteSampleRejection? {
        if case .reject(let reason) = self { return reason }
        return nil
    }
}

/// The single place a candidate location is judged.
///
/// Core Location hands back whatever the hardware produced: cached fixes from
/// minutes ago, positions with a kilometre of uncertainty, repeated identical
/// callbacks while parked, and occasional jumps to somewhere the vehicle
/// cannot have reached. None of that is trustworthy on arrival.
///
/// Every rule lives here rather than in a delegate callback or a view, so the
/// policy can be read in one place and tested without Core Location, a store or
/// a running app. The filter is a pure value: it holds thresholds, not state.
/// The caller supplies the shift window and the previously accepted sample.
///
/// The thresholds are an initial, defensible choice for delivery driving on a
/// phone in a vehicle — not a universally optimal calibration. They are stored
/// as properties precisely so they can be tuned once there is recorded data to
/// tune them against.
nonisolated struct RouteSampleFilter: Equatable, Sendable {
    /// Largest radius of uncertainty worth keeping, in metres.
    ///
    /// A phone with a clear sky view reports single digit metres; an urban
    /// canyon or a first fix commonly reports 30–65 m, which still describes
    /// which road the vehicle is on. Approximate (reduced accuracy)
    /// authorization typically reports one to several kilometres, which does
    /// not. 100 m keeps the former and drops the latter.
    ///
    /// Note that reduced accuracy is *not* rejected as a category: samples are
    /// judged by the accuracy actually reported, so an approximate fix that
    /// happens to be precise enough is kept.
    var maximumHorizontalAccuracy: Double = 100

    /// How old a fix may be when it is judged, in seconds.
    ///
    /// Core Location delivers its cached last known position as soon as updates
    /// start, which can be from a previous shift in a different place. Thirty
    /// seconds is comfortably longer than a cold first fix takes and short
    /// enough to exclude a stale cache.
    var maximumAge: TimeInterval = 30

    /// Least movement, in metres, that counts as movement.
    ///
    /// A stationary phone wanders by a few metres as the fix is refined, and
    /// storing that wander would be storing noise. Five metres is under a
    /// second of travel at any driving speed, so no real movement is lost.
    var minimumDistance: Double = 5

    /// Fastest speed treated as physically possible, in metres per second.
    ///
    /// 62 m/s is about 139 mph: far above any delivery driving, so the rule
    /// only fires on a genuinely broken position rather than on fast driving.
    /// The intent is to catch a fix that has jumped to the wrong place, not to
    /// police speed.
    var maximumSpeed: Double = 62

    /// Shortest interval used as the denominator of the speed check, in seconds.
    ///
    /// Two fixes a fraction of a second apart turn ordinary GPS noise into an
    /// enormous apparent speed. Treating any interval shorter than this as one
    /// second keeps the rule from rejecting legitimate samples that simply
    /// arrived close together.
    var minimumSpeedInterval: TimeInterval = 1

    /// What the sample would be judged against.
    nonisolated struct Context: Equatable, Sendable {
        /// Start of the shift the sample would belong to.
        var shiftStart: Date
        /// End of that shift, or `nil` while it is still running. A non-nil
        /// value rejects every sample: a completed shift never grows.
        var shiftEnd: Date?
        /// The most recent sample already retained for this shift, if any.
        var lastAccepted: LocationSample?
        /// The current time, supplied rather than read so staleness is testable.
        var now: Date

        init(shiftStart: Date, shiftEnd: Date? = nil, lastAccepted: LocationSample? = nil, now: Date) {
            self.shiftStart = shiftStart
            self.shiftEnd = shiftEnd
            self.lastAccepted = lastAccepted
            self.now = now
        }
    }

    /// Judges one candidate against the policy.
    ///
    /// The order of the checks is deliberate: a sample is described by the
    /// first rule it breaks, cheapest and most fundamental first, so the reason
    /// reported for a given sample is deterministic.
    func evaluate(_ candidate: LocationSample, in context: Context) -> RouteSampleDecision {
        guard Self.hasValidCoordinate(candidate) else { return .reject(.invalidCoordinate) }
        guard candidate.horizontalAccuracy.isFinite, candidate.horizontalAccuracy >= 0 else {
            return .reject(.invalidAccuracy)
        }
        guard candidate.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return .reject(.poorAccuracy)
        }

        // The shift window comes before the quality rules that depend on
        // previous samples: a sample outside the window is not this shift's
        // business at all, regardless of how good it is.
        guard context.shiftEnd == nil else { return .reject(.shiftEnded) }
        guard candidate.timestamp >= context.shiftStart else { return .reject(.beforeShiftStart) }
        guard context.now.timeIntervalSince(candidate.timestamp) <= maximumAge else {
            return .reject(.stale)
        }

        guard let last = context.lastAccepted else { return .accept }

        let interval = candidate.timestamp.timeIntervalSince(last.timestamp)
        if interval == 0 { return .reject(.duplicateTimestamp) }
        if interval < 0 { return .reject(.outOfOrder) }

        let distance = Self.distance(from: last, to: candidate)
        guard distance >= minimumDistance else { return .reject(.negligibleMovement) }

        // Two uncertain fixes can appear to be far apart when the vehicle has
        // barely moved, so the movement that has to be explained is the
        // separation the error radii cannot account for.
        let unexplained = max(0, distance - (last.horizontalAccuracy + candidate.horizontalAccuracy))
        let speed = unexplained / max(interval, minimumSpeedInterval)
        guard speed <= maximumSpeed else { return .reject(.implausibleSpeed) }

        return .accept
    }

    // MARK: Geometry

    /// Whether a coordinate is one the Earth actually has.
    ///
    /// `(0, 0)` is rejected as well as out-of-range values: it is in the Gulf of
    /// Guinea, no delivery happens there, and it is the value a zeroed or
    /// default-initialised coordinate takes.
    private static func hasValidCoordinate(_ sample: LocationSample) -> Bool {
        guard sample.latitude.isFinite, sample.longitude.isFinite else { return false }
        guard abs(sample.latitude) <= 90, abs(sample.longitude) <= 180 else { return false }
        return !(sample.latitude == 0 && sample.longitude == 0)
    }

    /// Great-circle distance between two samples in metres.
    ///
    /// This exists to support the movement and speed rules and is **not** the
    /// app's mileage calculation: driven distance has to account for the whole
    /// retained route and the gaps in it, which is ``RouteMileageCalculator``'s
    /// job. Both measure two positions the same way, through
    /// ``GeographicDistance``, so capture and mileage cannot disagree about how
    /// far apart two fixes are.
    static func distance(from start: LocationSample, to end: LocationSample) -> Double {
        GeographicDistance.metres(
            fromLatitude: start.latitude,
            longitude: start.longitude,
            toLatitude: end.latitude,
            longitude: end.longitude
        )
    }
}
