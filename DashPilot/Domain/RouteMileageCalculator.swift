import Foundation

/// Measures the distance a shift's retained route actually recorded.
///
/// ## The rule this type exists for
///
/// **A gap in capture is never counted as driven distance.** A position, then a
/// period where DashPilot was not recording, then another position is not a
/// straight line the driver drove; it is two pieces of route with an unknown
/// amount of driving between them. Measuring across it would silently invent
/// mileage, and inventing mileage is worse than reporting less of it.
///
/// So the route is split into continuous segments, distance is summed within
/// each segment, and the distance between segments is left out and counted as a
/// gap instead.
///
/// ## What makes two positions continuous
///
/// Two things, and both must hold:
///
/// 1. **They were recorded in the same capture session.** The capture service
///    stamps every retained sample with the identifier of the stretch of
///    capture it belongs to, so a change of identifier is direct evidence that
///    capture stopped and restarted in between. Positions stored before schema
///    v3 have no identifier; continuity between two of them is inferred from
///    time alone, and the result says so.
/// 2. **They are no further apart in time than ``maximumSampleInterval``.** The
///    identifier proves the app kept recording, not that positions kept
///    arriving. A long silence inside one session — a tunnel, a dead signal, a
///    parked vehicle — is not something to measure a straight line across.
///
/// ## What this type deliberately does not do
///
/// It does not re-judge the quality of stored positions. Accuracy thresholds,
/// staleness, implausible speed and negligible movement are ``RouteSampleFilter``'s
/// rules, applied once when a sample is captured; repeating them here would be
/// two policies to keep in agreement. The only positions rejected here are ones
/// that could not describe anywhere on Earth, because stored data should not be
/// assumed to stay perfect forever and a malformed row must not produce a
/// nonsensical total.
///
/// It also does not infer idle time from the route. The capture filter drops
/// movement under five metres, so a parked vehicle records nothing at all, and
/// a stretch of route with no positions in it is not evidence of anything.
nonisolated struct RouteMileageCalculator: Equatable, Sendable {
    /// The longest silence between two retained positions still treated as one
    /// continuous stretch of route, in seconds.
    ///
    /// While a vehicle is moving, accepted positions arrive seconds apart, so
    /// this is far longer than ordinary driving produces and does not fragment
    /// a normally captured route. Two minutes without one means either the
    /// vehicle was stationary — in which case the straight line left out is a
    /// few metres and nothing is lost — or positions stopped arriving, in which
    /// case the straight line cannot be trusted.
    ///
    /// It is an initial engineering choice, not a calibrated one: nothing has
    /// been recorded on a real shift to tune it against. It is a property so it
    /// can be tuned when there is.
    var maximumSampleInterval: TimeInterval = 120

    init(maximumSampleInterval: TimeInterval = 120) {
        self.maximumSampleInterval = maximumSampleInterval
    }

    /// Measures one shift's route.
    ///
    /// The caller supplies the positions of a single shift. Mixing shifts would
    /// measure the drive home from one and the drive out of the next as one
    /// segment, so the calculation never fetches anything itself.
    ///
    /// `window` is the shift the route belongs to, when it is known. Without it
    /// the calculation can only see the gaps *between* positions, and a shift
    /// whose capture stopped an hour before it ended would look completely
    /// recorded. With it, a route that does not reach the beginning or the end
    /// of its shift counts that as a gap too.
    ///
    /// Persisted data is not assumed to be well formed: positions arrive in
    /// whatever order the store returns them, and are sorted, deduplicated and
    /// checked here. The capture filter already prevents all of this under
    /// normal operation; this is what keeps an imperfect route from producing a
    /// wrong number or a crash years later.
    func distance(of points: [RoutePoint], covering window: ClosedRange<Date>? = nil) -> RouteDistance {
        let ordered = orderedUsablePoints(in: points)
        let edgeGaps = uncoveredEdgeCount(of: ordered, in: window)

        guard ordered.count > 1 else {
            return RouteDistance(
                metres: 0,
                segmentCount: 0,
                gapCount: edgeGaps,
                usableSampleCount: ordered.count,
                usesInferredContinuity: false
            )
        }

        var metres = 0.0
        var gapCount = edgeGaps
        var segmentCount = 0
        var usesInferredContinuity = false
        // Whether the pair just measured extended the segment already counted.
        var isContinuingSegment = false

        for (start, end) in zip(ordered, ordered.dropFirst()) {
            let link = continuity(from: start, to: end)
            guard link != .broken else {
                gapCount += 1
                isContinuingSegment = false
                continue
            }

            if link == .inferred { usesInferredContinuity = true }
            if !isContinuingSegment {
                segmentCount += 1
                isContinuingSegment = true
            }
            metres += GeographicDistance.metres(
                fromLatitude: start.latitude,
                longitude: start.longitude,
                toLatitude: end.latitude,
                longitude: end.longitude
            )
        }

        return RouteDistance(
            metres: metres,
            segmentCount: segmentCount,
            gapCount: gapCount,
            usableSampleCount: ordered.count,
            usesInferredContinuity: usesInferredContinuity
        )
    }

    // MARK: Continuity

    private enum Continuity: Equatable {
        /// Capture recorded both positions in the same session.
        case recorded
        /// Neither position records a session, so continuity is only a
        /// reasonable reading of their timestamps.
        case inferred
        /// Capture stopped between the two, or a session boundary makes it
        /// impossible to say it did not.
        case broken
    }

    private func continuity(from start: RoutePoint, to end: RoutePoint) -> Continuity {
        guard end.timestamp.timeIntervalSince(start.timestamp) <= maximumSampleInterval else {
            return .broken
        }
        switch (start.captureSessionID, end.captureSessionID) {
        case let (startSession?, endSession?):
            return startSession == endSession ? .recorded : .broken
        case (nil, nil):
            return .inferred
        default:
            // One side was recorded with continuity tracking and the other was
            // not, which can only happen where a legacy route meets a new one.
            // That boundary is exactly where capture is known to have stopped.
            return .broken
        }
    }

    /// How many ends of the shift the route does not reach.
    ///
    /// A shift whose first position arrives long after it started, or whose last
    /// position is long before it ended, was not being recorded for part of its
    /// length. That is the same kind of unmeasured stretch as a gap in the
    /// middle, and it is the shape a foreground-only route usually takes: the
    /// driver switches to another app and DashPilot stops recording until they
    /// come back, which for the last leg of a shift may be never.
    ///
    /// The vehicle may equally have been parked for those minutes, in which case
    /// nothing was missed. The route cannot tell the two apart, so this counts
    /// them the same way and the interface says the distance may be incomplete
    /// rather than claiming it is not.
    private func uncoveredEdgeCount(of ordered: [RoutePoint], in window: ClosedRange<Date>?) -> Int {
        guard let window else { return 0 }
        guard let first = ordered.first, let last = ordered.last else {
            // Nothing at all was recorded. That is one uncovered stretch, unless
            // the shift was too short to have recorded anything.
            return window.upperBound.timeIntervalSince(window.lowerBound) > maximumSampleInterval ? 1 : 0
        }

        var count = 0
        if first.timestamp.timeIntervalSince(window.lowerBound) > maximumSampleInterval { count += 1 }
        if window.upperBound.timeIntervalSince(last.timestamp) > maximumSampleInterval { count += 1 }
        return count
    }

    // MARK: Ordering

    /// The positions the calculation will walk: usable, in a deterministic
    /// order, with no two sharing a timestamp.
    ///
    /// Sorting by timestamp alone is not a total order, so positions recorded at
    /// the same instant would be walked in whatever order the store happened to
    /// return them and the total would depend on it. Coordinates break the tie,
    /// and then only the first position at any instant is kept: two different
    /// positions at one instant contradict each other, and using both would add
    /// a jump between them that no vehicle drove.
    private func orderedUsablePoints(in points: [RoutePoint]) -> [RoutePoint] {
        let sorted = points.filter(Self.isUsable).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            if lhs.latitude != rhs.latitude { return lhs.latitude < rhs.latitude }
            return lhs.longitude < rhs.longitude
        }

        var deduplicated: [RoutePoint] = []
        deduplicated.reserveCapacity(sorted.count)
        for point in sorted where point.timestamp != deduplicated.last?.timestamp {
            deduplicated.append(point)
        }
        return deduplicated
    }

    /// Whether a stored position describes somewhere the Earth has, at a moment
    /// the clock can express.
    ///
    /// The same coordinate rule the capture filter applies, for the same reason:
    /// `(0, 0)` is the value a zeroed coordinate takes, and no delivery happens
    /// in the Gulf of Guinea.
    private static func isUsable(_ point: RoutePoint) -> Bool {
        guard point.timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
        guard point.latitude.isFinite, point.longitude.isFinite else { return false }
        guard abs(point.latitude) <= 90, abs(point.longitude) <= 180 else { return false }
        return !(point.latitude == 0 && point.longitude == 0)
    }
}
