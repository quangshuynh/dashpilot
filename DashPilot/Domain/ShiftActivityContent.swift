import Foundation

/// Which delivery a surface with no card to tap is allowed to act on.
///
/// One rule, in one place, because two surfaces now need it and they must not
/// disagree. A spoken "record the next step" and a Lock Screen button both name
/// no particular order, so each may act **only while exactly one delivery is in
/// progress**. With two, every way of choosing (the newest, the oldest, the one
/// furthest along) writes the driver's action into a record they did not mean,
/// and the mistake is not one they can see happening.
///
/// Generic over the element on purpose: the intent layer resolves a `Delivery`,
/// the Live Activity's content resolves a `DeliveryState`, and the rule is about
/// the count rather than about what is being counted.
nonisolated enum UnambiguousDelivery {
    /// The one delivery a request that names none can mean, or `nil` when there
    /// is not exactly one.
    static func target<Element>(among active: [Element]) -> Element? {
        active.count == 1 ? active.first : nil
    }
}

nonisolated extension ShiftActivityDeliveryStep {
    /// The Live Activity's word for one of the app's delivery actions, or `nil`
    /// for the one action that is not a step of an existing delivery.
    ///
    /// The mapping exists because the widget extension cannot see
    /// ``DeliveryAction``. It maps and never decides: which step comes next is
    /// ``DeliveryState/nextAction``'s answer, here as everywhere else.
    init?(_ action: DeliveryAction) {
        switch action {
        case .start: return nil
        case .arriveAtPickup: self = .arriveAtPickup
        case .pickUp: self = .pickUp
        case .complete: self = .complete
        }
    }
}

/// What the shift's Live Activity is told, derived from what the app already
/// knows about the shift.
///
/// ## It derives, and it decides one thing
///
/// Every figure here comes from ``ActiveShiftMetrics``, which is the running
/// shift's panel's own reading of the store. Nothing is recalculated, relaxed or
/// rounded differently for the Lock Screen: the mileage sentence is
/// ``RouteQuality``'s, the working duration is ``Shift/workingDuration(asOf:)``'s,
/// the counts are ``DeliverySummary``'s.
///
/// The one decision it makes is **which controls the surface offers**, and it
/// makes it from the shift's own facts using the rules the services enforce:
///
/// - Every **running** shift offers Start Delivery, whatever else it offers.
///   Stacked deliveries are supported, so one more order is always a thing the
///   driver may be accepting, and the control names no existing delivery: it
///   always means create exactly one. A **paused** shift does not offer it,
///   because ``DeliveryService`` refuses a start on one.
/// - A running shift with no delivery open also offers Pause and End. Both are
///   refused by ``ShiftService`` while a delivery is open, so neither is offered
///   then.
/// - A running shift with exactly one delivery open also offers that delivery's
///   next step, and nothing else.
/// - A running shift with **two or more** deliveries open offers Start Delivery
///   and nothing else. That is the ambiguity refusal, unchanged: there is no
///   step to offer because there is no "the delivery", and Pause and End are
///   refused by the rule above. What Start Delivery adds does not depend on
///   which order the driver meant, so it is not part of that refusal.
/// - A paused shift offers Resume and End. Ending a paused shift is permitted
///   and closes the pause at the end instant, so refusing it here would be this
///   surface inventing a stricter rule than the app's.
///
/// A control is a courtesy and never a permission. Pressing one runs
/// ``IntentLifecycleService``, which asks the store, so a snapshot that is a
/// moment out of date costs a refusal sentence rather than a wrong write.
nonisolated enum ShiftActivityContent {
    /// The snapshot to hand ActivityKit.
    ///
    /// - Parameters:
    ///   - metrics: the running shift's live figures, as of `asOf`.
    ///   - deliveryInProgress: the state of the **one** delivery in progress, or
    ///     `nil` when there is none or when there is more than one. Resolved by
    ///     ``UnambiguousDelivery`` rather than by anything here.
    ///   - asOf: the instant the figures were read at.
    ///   - locale: the locale the mileage sentence is written in.
    static func state(
        of metrics: ActiveShiftMetrics,
        deliveryInProgress: DeliveryState?,
        asOf: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> ShiftActivityAttributes.ContentState {
        let step = deliveryInProgress?.nextAction.flatMap(ShiftActivityDeliveryStep.init)

        return ShiftActivityAttributes.ContentState(
            isPaused: metrics.isPaused,
            workingDuration: metrics.workingDuration,
            asOf: asOf,
            mileageStatement: metrics.mileageStatement(locale: locale),
            partialRouteMarker: metrics.partialMarker,
            activeDeliveryCount: metrics.deliverySummary.inProgress,
            completedDeliveryCount: metrics.deliverySummary.completed,
            deliveryStatus: deliveryInProgress?.statusDescription,
            controls: controls(for: metrics, nextStep: step)
        )
    }

    /// The controls this shift may offer, in the order they are shown.
    ///
    /// The delivery step comes first where there is one, then Start Delivery:
    /// both are pressed many times a shift, the step belongs to an order already
    /// in the car, and the two lifecycle controls are pressed once each.
    private static func controls(
        for metrics: ActiveShiftMetrics,
        nextStep: ShiftActivityDeliveryStep?
    ) -> [ShiftActivityControl] {
        if metrics.isPaused { return [.resume, .end] }

        // Running, so one more delivery is always something the driver may be
        // accepting, and the control that starts one names no existing record.
        if let nextStep { return [.deliveryStep(nextStep), .startDelivery] }
        // Pausing and ending are both refused while any delivery is open, so a
        // running shift that has one and offered no step offers only the start.
        guard metrics.deliverySummary.inProgress == 0 else { return [.startDelivery] }
        return [.startDelivery, .pause, .end]
    }
}

extension Shift {
    /// This shift's Live Activity snapshot, as of `referenceDate`.
    ///
    /// The adapter between the model and the derivation, holding no rule of its
    /// own. `recordedDistance` is passed in rather than measured here for the
    /// reason ``Shift/activeMetrics(for:asOf:)`` takes it: measuring a route
    /// walks every position it holds, and a shift in progress is exactly the
    /// case where the caller should be extending a measurement rather than
    /// repeating one.
    func activityContentState(
        for recordedDistance: RouteDistance,
        asOf referenceDate: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> ShiftActivityAttributes.ContentState {
        ShiftActivityContent.state(
            of: activeMetrics(for: recordedDistance, asOf: referenceDate),
            deliveryInProgress: UnambiguousDelivery.target(among: activeDeliveries)?.state,
            asOf: referenceDate,
            locale: locale
        )
    }
}
