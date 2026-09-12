import Foundation

/// The walk that turns a shift's retained positions into a ``RouteDistance``,
/// held open so a route still being recorded can be extended rather than
/// remeasured.
///
/// ## Why this type exists
///
/// ``RouteMileageCalculator`` measures a route in one pass, which is the right
/// shape for a finished shift: the positions are all there, the walk happens
/// once, and the result is thrown away. A shift in progress asks the same
/// question every few seconds of a route that has grown by a handful of
/// positions, and re-walking thousands of them each time to add one leg is work
/// the answer does not need.
///
/// So the pairwise rule lives here, in a value that remembers where the walk
/// reached, and ``RouteMileageCalculator`` is expressed in terms of it. There is
/// **one** implementation of what makes two positions continuous, what a gap is
/// and which positions are usable, and a whole-route measurement and an extended
/// one cannot drift apart because they are the same code.
///
/// ## The one thing it does that the calculator does not
///
/// **It consumes a route in timestamp order and does not reorder it
/// afterwards.** A position appended with a timestamp at or before the last one
/// already consumed is dropped, exactly as the whole-route walk drops a second
/// position sharing a timestamp. That is the same rule for a route that arrives
/// in order, which is the only kind capture produces: ``RouteSampleFilter``
/// rejects a candidate that is a duplicate of, or earlier than, the last one
/// retained for the shift.
///
/// The difference only shows on a store that already holds an out-of-order
/// route, where the one-pass measurement sorts it and an extension in progress
/// cannot. Live figures are a reading of a shift still being recorded; the
/// figure a shift is finally reported with is always the one-pass measurement.
///
/// ## What it deliberately does not do
///
/// It does not re-judge the quality of stored positions, for the reason
/// ``RouteMileageCalculator`` does not: accuracy, staleness, implausible speed
/// and negligible movement are ``RouteSampleFilter``'s rules, applied once when
/// a sample is captured. The only positions rejected here are ones that could
/// not describe anywhere on Earth.
nonisolated struct RouteMileageAccumulator: Equatable, Sendable {
    /// The longest silence between two retained positions still treated as one
    /// continuous stretch of route, in seconds. See
    /// ``RouteMileageCalculator/maximumSampleInterval``, which is where the
    /// value is chosen and explained.
    let maximumSampleInterval: TimeInterval

    /// Distance counted within continuous capture so far, in metres.
    private(set) var metres = 0.0

    /// Unbroken stretches of two or more positions that have contributed
    /// distance.
    private(set) var segmentCount = 0

    /// Breaks counted **between** consumed positions. Uncovered ends of the
    /// shift are added by ``distance(covering:)``, which is where the shift's
    /// own window is known.
    private(set) var interiorGapCount = 0

    /// Positions consumed after malformed ones were discarded and positions
    /// sharing a timestamp were collapsed.
    private(set) var usableSampleCount = 0

    /// Whether any distance was counted between positions whose continuity was
    /// inferred from their timestamps rather than recorded.
    private(set) var usesInferredContinuity = false

    /// The first position consumed, which is where the route starts.
    private(set) var firstPoint: RoutePoint?

    /// The last position consumed, which the next one is judged against.
    private(set) var lastPoint: RoutePoint?

    /// Whether the pair measured last extended the segment already counted.
    private var isContinuingSegment = false

    init(maximumSampleInterval: TimeInterval = 120) {
        self.maximumSampleInterval = maximumSampleInterval
    }

    /// Extends the walk with more of the route.
    ///
    /// `points` may arrive in any order and hold anything the store returned:
    /// they are filtered, ordered and deduplicated here by the same rules the
    /// one-pass measurement applies, and then walked. Positions at or before the
    /// last one already consumed are dropped — see the note on ordering above.
    mutating func append(_ points: some Sequence<RoutePoint>) {
        for point in Self.orderedUsablePoints(in: points) {
            consume(point)
        }
    }

    /// What the route has measured so far.
    ///
    /// `window` is the shift the route belongs to, when it is known. Without it
    /// the result can only describe the gaps *between* positions, which is what
    /// a shift still being recorded has: its window is still growing, and
    /// measuring against the moment it is read would report a gap for every red
    /// light. See ``Shift/completedWindow``.
    func distance(covering window: ClosedRange<Date>? = nil) -> RouteDistance {
        RouteDistance(
            metres: metres,
            segmentCount: segmentCount,
            gapCount: interiorGapCount + uncoveredEdgeCount(in: window),
            usableSampleCount: usableSampleCount,
            usesInferredContinuity: usesInferredContinuity
        )
    }

    // MARK: Walking

    private mutating func consume(_ point: RoutePoint) {
        guard let previous = lastPoint else {
            firstPoint = point
            lastPoint = point
            usableSampleCount = 1
            return
        }
        // The same instant twice, or a step backwards, is not a leg of route.
        // Two different positions at one instant contradict each other, and
        // using both would add a jump between them that no vehicle drove.
        guard point.timestamp > previous.timestamp else { return }

        usableSampleCount += 1
        lastPoint = point

        let link = continuity(from: previous, to: point)
        guard link != .broken else {
            interiorGapCount += 1
            isContinuingSegment = false
            return
        }

        if link == .inferred { usesInferredContinuity = true }
        if !isContinuingSegment {
            segmentCount += 1
            isContinuingSegment = true
        }
        metres += GeographicDistance.metres(
            fromLatitude: previous.latitude,
            longitude: previous.longitude,
            toLatitude: point.latitude,
            longitude: point.longitude
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
    /// middle, and it is the shape an interrupted route takes: a shift started
    /// by voice records nothing until the app is opened, and a process iOS ends
    /// records nothing afterwards, which for the last leg of a shift may be the
    /// rest of it.
    ///
    /// The vehicle may equally have been parked for those minutes, in which case
    /// nothing was missed. The route cannot tell the two apart, so this counts
    /// them the same way and the interface says the distance may be incomplete
    /// rather than claiming it is not.
    private func uncoveredEdgeCount(in window: ClosedRange<Date>?) -> Int {
        guard let window else { return 0 }
        guard let first = firstPoint, let last = lastPoint else {
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

    /// The positions the walk will consider: usable, and in a deterministic
    /// order.
    ///
    /// Sorting by timestamp alone is not a total order, so positions recorded at
    /// the same instant would be walked in whatever order the store happened to
    /// return them and the total would depend on it. Coordinates break the tie.
    /// Collapsing positions that share a timestamp is left to ``consume(_:)``,
    /// which applies the same rule across an append boundary as within one.
    static func orderedUsablePoints(in points: some Sequence<RoutePoint>) -> [RoutePoint] {
        points.filter(isUsable).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            if lhs.latitude != rhs.latitude { return lhs.latitude < rhs.latitude }
            return lhs.longitude < rhs.longitude
        }
    }

    /// Whether a stored position describes somewhere the Earth has, at a moment
    /// the clock can express.
    ///
    /// The same coordinate rule the capture filter applies, for the same reason:
    /// `(0, 0)` is the value a zeroed coordinate takes, and no delivery happens
    /// in the Gulf of Guinea.
    static func isUsable(_ point: RoutePoint) -> Bool {
        guard point.timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
        guard point.latitude.isFinite, point.longitude.isFinite else { return false }
        guard abs(point.latitude) <= 90, abs(point.longitude) <= 180 else { return false }
        return !(point.latitude == 0 && point.longitude == 0)
    }
}
