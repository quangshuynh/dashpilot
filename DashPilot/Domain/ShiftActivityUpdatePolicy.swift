import Foundation

/// How two Live Activity snapshots differ, judged by what a driver would see.
nonisolated enum ShiftActivityChange: Equatable, Sendable {
    /// Nothing a reader could notice moved. The surface already says this.
    case none
    /// Only the route figure moved.
    case route
    /// Something that changes what the surface means moved: the paused state,
    /// the deliveries, or which controls apply.
    case material
}

/// When the app hands ActivityKit a new snapshot, and when it does not.
///
/// ## Why there is a policy at all
///
/// The obvious implementation pushes an update whenever anything could have
/// changed, which on a shift being recorded at one position a second is an
/// update every second or two, for hours, for a surface the driver is not
/// looking at. ActivityKit budgets updates and the system draws each one; a
/// cadence chosen by the app rather than by the data is the difference between
/// a Live Activity and a background load.
///
/// ## The two figures that need no updates at all
///
/// **Working time is not in this policy**, and that is deliberate rather than an
/// omission. It grows at exactly the rate wall-clock time does while a shift
/// runs, so the snapshot carries an anchor and the system draws a clock from it
/// with no further updates for the length of the shift. While the shift is
/// paused the figure does not move at all. Either way, a new snapshot carrying
/// only a later working time would be asking the system to redraw a number it
/// already has. See `ShiftActivityAttributes.ContentState.workingTimerAnchor`.
///
/// ``ShiftActivityAttributes/ContentState/asOf`` is excluded for the same
/// reason: it is the anchor's other half, and on its own it says nothing.
///
/// The delivery timers are a third, and they are counted as **material** rather
/// than excluded. Each is an acceptance instant, so time passing does not move
/// one and no update is needed to keep a delivery's clock right; what has to be
/// pushed is the list *changing*. One delivery finishing as another starts
/// leaves every count on the card where it was, so without this the surface
/// would keep counting an order that had already been delivered.
///
/// ## What is left
///
/// - A **material** change is pushed at once. Pausing, resuming, a delivery
///   starting, advancing or finishing, a control appearing or disappearing:
///   each of them changes what the surface means, and a driver who paused and
///   saw no acknowledgement would reasonably press it again.
/// - A **route** change waits for ``routeInterval``. The figure is shown to a
///   tenth of a mile, so at road speed it moves every few seconds, and none of
///   those steps is worth a redraw on a locked screen. Half a minute keeps the
///   figure honest to about a mile at motorway speed and to far less in traffic.
/// - **No** change is never pushed.
nonisolated enum ShiftActivityUpdatePolicy {
    /// The shortest interval between two updates that differ only in the route
    /// figure.
    static let routeInterval: TimeInterval = 30

    /// What moved between two snapshots.
    static func change(
        from previous: ShiftActivityAttributes.ContentState?,
        to next: ShiftActivityAttributes.ContentState
    ) -> ShiftActivityChange {
        guard let previous else { return .material }

        let isMaterial = previous.isPaused != next.isPaused
            || previous.activeDeliveryCount != next.activeDeliveryCount
            || previous.completedDeliveryCount != next.completedDeliveryCount
            || previous.deliveryStatus != next.deliveryStatus
            || previous.activeDeliveryTimers != next.activeDeliveryTimers
            || previous.controls != next.controls
        if isMaterial { return .material }

        let routeMoved = previous.mileageStatement != next.mileageStatement
            || previous.partialRouteMarker != next.partialRouteMarker
        return routeMoved ? .route : .none
    }

    /// Whether a change of this kind should be handed to ActivityKit now.
    ///
    /// - Parameters:
    ///   - change: what moved.
    ///   - lastPushedAt: when the app last handed over a snapshot, or `nil` if
    ///     it has not.
    ///   - now: the instant being decided at.
    static func shouldPush(_ change: ShiftActivityChange, lastPushedAt: Date?, now: Date) -> Bool {
        switch change {
        case .none:
            false
        case .material:
            true
        case .route:
            // A clock that has moved backwards must not be able to hold the
            // figure still for as long as it is wrong by, so a reference date
            // before the last push counts as enough time having passed.
            lastPushedAt.map { now < $0 || now.timeIntervalSince($0) >= routeInterval } ?? true
        }
    }
}
