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
    /// checked by the walk. The capture filter already prevents all of this
    /// under normal operation; this is what keeps an imperfect route from
    /// producing a wrong number or a crash years later.
    ///
    /// The walk itself lives in ``RouteMileageAccumulator``, which is the same
    /// code a shift still being recorded extends a position at a time. Measuring
    /// a whole route is that walk fed everything at once, so the two can never
    /// disagree about a gap, a segment or a metre.
    func distance(of points: [RoutePoint], covering window: ClosedRange<Date>? = nil) -> RouteDistance {
        var walk = RouteMileageAccumulator(maximumSampleInterval: maximumSampleInterval)
        walk.append(points)
        return walk.distance(covering: window)
    }
}
