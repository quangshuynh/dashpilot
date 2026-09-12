import Foundation

/// A measurement of a shift's route that is still being recorded, held open so
/// the next few positions extend it instead of starting it again.
///
/// ## The problem it exists for
///
/// A finished shift's route is measured once, when a row or a screen appears. A
/// shift in progress is asked the same question every few seconds, of a route
/// that has grown by a handful of positions since the last answer. Walking the
/// whole route each time is work proportional to the length of the shift, paid
/// repeatedly, on the main actor, for an answer that differs from the last one
/// by a few metres. An eight-hour shift holds tens of thousands of positions and
/// the arithmetic is the cheap half: fetching them all out of the store and
/// mapping them is what actually costs.
///
/// So this keeps the walk open — ``RouteMileageAccumulator`` is the same code
/// that measures a finished route, one leg at a time — and remembers enough to
/// ask the store only for what it has not seen.
///
/// ## The correctness model
///
/// **Nothing derived is persisted.** This is a value held for as long as a
/// screen shows the running shift, and it is thrown away with it. The figure the
/// shift is finally reported with is measured from the stored route in one pass,
/// by ``Shift/recordedDistance(using:)``, exactly as it was before this type
/// existed. This is a faster reading of the same rows, never a second source of
/// truth for them.
///
/// **It extends forwards only.** A position at or before the last one consumed
/// is not counted, which is the rule ``RouteMileageAccumulator`` applies within
/// a single pass too, and which capture already guarantees: ``RouteSampleFilter``
/// rejects a candidate that duplicates or precedes the last sample retained for
/// the shift.
///
/// **It re-reads everything when rows disappear.** ``consumedRowCount`` is
/// compared against what the store actually holds before every extension, so a
/// rollback that discarded samples this measurement had already counted is
/// caught and the route is measured again from scratch. That is the one way a
/// live figure could otherwise be left standing on rows that no longer exist,
/// and it is cheap to rule out: a count is one aggregate query.
///
/// The gap it does not close is a store that both gained and lost the same
/// number of route rows between two readings. Capture only ever appends, and
/// rows only ever leave with the shift they belong to, so that shape is not one
/// the app can produce; it is recorded here rather than defended against.
nonisolated struct ActiveRouteMeasurement: Equatable, Sendable {
    /// The shift being measured. A measurement never outlives its shift: a
    /// different shift is a different route, and mixing them would measure the
    /// end of one and the start of the next as one leg.
    let shiftID: UUID

    /// The open walk. Its rules are the finished route's rules.
    private(set) var walk: RouteMileageAccumulator

    /// How many stored route rows this measurement has consumed, usable or not.
    ///
    /// Rows rather than positions, because it is compared against what the store
    /// reports it holds, and the store counts rows. A malformed row the walk
    /// discarded still occupies one.
    private(set) var consumedRowCount: Int

    init(shiftID: UUID, maximumSampleInterval: TimeInterval = 120) {
        self.shiftID = shiftID
        self.walk = RouteMileageAccumulator(maximumSampleInterval: maximumSampleInterval)
        self.consumedRowCount = 0
    }

    /// What the route has recorded so far.
    ///
    /// Measured with **no shift window**, because an unfinished shift has none.
    /// See ``ActiveShiftMetrics/recordedDistance``.
    var recordedDistance: RouteDistance { walk.distance() }

    /// The timestamp after which the store holds nothing this measurement has
    /// seen, or `nil` when it has consumed no usable position yet.
    var lastConsumedTimestamp: Date? { walk.lastPoint?.timestamp }

    /// Adds rows the store holds and this measurement had not seen.
    ///
    /// Both counts are needed, and neither alone is right.
    ///
    /// Counting the **rows actually read** is what catches a discard. A context
    /// hands back its unsaved inserts as well as its saved rows, so a reading
    /// can legitimately consume more rows than the store reports holding; taking
    /// the store's count instead would leave this measurement standing on rows a
    /// later rollback discarded, with nothing to notice by.
    ///
    /// Taking the **store's count** as a floor is what stops a row the walk
    /// declined, or one that arrived out of order and was not fetched, from
    /// leaving the two permanently out of step and every later reading asking
    /// for rows there are none of.
    ///
    /// - Parameters:
    ///   - points: the positions of the rows read, in any order.
    ///   - rowsRead: how many rows produced them, whether or not the walk could
    ///     use each one.
    ///   - storedRowCount: how many rows the store reported holding for this
    ///     shift when the reading began.
    mutating func extend(with points: some Sequence<RoutePoint>, rowsRead: Int, storedRowCount: Int) {
        walk.append(points)
        consumedRowCount = max(consumedRowCount + rowsRead, storedRowCount)
    }

    /// What reading the store again should do, given what it now holds.
    func plan(againstStoredRowCount storedRowCount: Int) -> ActiveRouteMeasurementPlan {
        if storedRowCount < consumedRowCount { return .remeasure }
        if storedRowCount == consumedRowCount { return .upToDate }
        return .extend(after: lastConsumedTimestamp)
    }
}

/// What extending a live route measurement requires of the store.
///
/// A plan rather than a fetch, so the decision is a rule that can be tested
/// without a container and the query is the only part that needs one.
nonisolated enum ActiveRouteMeasurementPlan: Equatable, Sendable {
    /// The store holds nothing the measurement has not counted. No query, no
    /// walk, no change: this is the answer during every stretch the driver is
    /// parked, waiting or paused.
    case upToDate

    /// Read the rows after this instant and add them. `nil` means the
    /// measurement has consumed no usable position yet, so every row is new.
    case extend(after: Date?)

    /// Rows this measurement had already counted are no longer in the store, so
    /// the figure standing on them cannot be extended. Measure the route again.
    case remeasure
}
