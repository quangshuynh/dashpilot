import Foundation

/// Why a rate could not be derived for a shift.
///
/// Each case is a different fact about the shift, and they are kept apart for
/// the reason the rest of this project keeps `nil` and zero apart: "no amount
/// was entered" and "the amount entered was zero" are different statements, and
/// so are "nothing was recorded of the route" and "the route was recorded and
/// measured zero metres". Collapsing any pair of these into one would let the
/// interface say something the data does not support.
nonisolated enum ShiftRateUnavailability: CaseIterable, Equatable, Sendable {
    /// The shift is still running. Finalised rates describe finished shifts.
    case shiftNotCompleted
    /// The driver has not recorded what the shift paid. Not the same as `$0.00`.
    case earningsNotRecorded
    /// The shift covered no measurable time, so there are no hours to divide by.
    case noElapsedTime
    /// The shift recorded no deliveries, so there is no delivery active time.
    case noDeliveriesRecorded
    /// Deliveries were recorded, but none of them describes a usable interval
    /// within the shift — an unfinished one on a finished shift, or timestamps
    /// that do not form a stretch of it. Not the same as no deliveries, and not
    /// a duration of zero.
    case deliveryActiveTimeNotMeasurable
    /// Delivery intervals were measured and they covered no time. This is a
    /// measurement, not an absence of one.
    case zeroDeliveryActiveTime
    /// The shift retained no usable position at all.
    case noRouteRecorded
    /// Positions were retained, but no two of them were recorded continuously,
    /// so no distance could be measured between them.
    case routeNotMeasurable
    /// A distance was measured and it was zero. The vehicle's recorded positions
    /// did not move; this is a measurement, not an absence of one.
    case zeroRecordedDistance
}

nonisolated extension ShiftRateUnavailability {
    /// Why the driver is not being shown a rate, in one sentence.
    ///
    /// A compact history row can afford to show nothing at all for an absent
    /// rate; a detail screen cannot, because "what exactly happened in this
    /// shift" includes why a figure the driver expected is missing. Each
    /// sentence states the fact and, where there is one, the thing that would
    /// produce the rate — without ever implying the missing value is zero.
    var explanation: String {
        switch self {
        case .shiftNotCompleted:
            "This shift is still running. Rates are worked out once it ends."
        case .earningsNotRecorded:
            "Add what this shift paid to see this rate."
        case .noElapsedTime:
            "This shift covered no measurable time, so there are no hours to divide by."
        case .noDeliveriesRecorded:
            "No deliveries were recorded during this shift, so there is no delivery active time to divide by."
        case .deliveryActiveTimeNotMeasurable:
            "The deliveries recorded for this shift do not describe a stretch of it, so no delivery active time could be measured."
        case .zeroDeliveryActiveTime:
            "The deliveries recorded for this shift covered no measurable time."
        case .noRouteRecorded:
            "No usable position was recorded for this shift, so there are no miles to divide by."
        case .routeNotMeasurable:
            "No two recorded positions were captured continuously, so no distance could be measured to divide by."
        case .zeroRecordedDistance:
            "The recorded positions did not move, so the distance measured was zero."
        }
    }
}

/// A derived rate, or the reason there is not one.
///
/// A `Money?` would carry the value but lose the reason, and every reason here
/// is something the interface may need to behave differently about. Nothing
/// substitutes zero for an absent rate.
nonisolated enum ShiftRate: Equatable, Sendable {
    case available(Money)
    case unavailable(ShiftRateUnavailability)

    /// The rate, or `nil` when there is not one.
    var amount: Money? {
        switch self {
        case let .available(amount): amount
        case .unavailable: nil
        }
    }

    var isAvailable: Bool { amount != nil }

    /// Why there is no rate, or `nil` when there is one.
    var unavailability: ShiftRateUnavailability? {
        switch self {
        case .available: nil
        case let .unavailable(reason): reason
        }
    }
}

/// What DashPilot can honestly say about how a completed shift performed.
///
/// Everything here is **derived** — from the shift's own timestamps, the amount
/// the driver typed, and the distance measured from the shift's retained route.
/// Nothing in it is persisted: a stored rate would be a second answer to a
/// question the store can already answer, and it would keep the old answer after
/// the calculation improved. See ``ShiftMetricsCalculator``.
///
/// Every rate is **gross**. The numerator is the figure the driver recorded for
/// the shift, with no expenses, fuel, wear or tax subtracted, and nothing is
/// imported from a delivery platform.
///
/// The inputs are carried alongside the rates so a caller can present a rate
/// with the terms it was derived under — a per-recorded-mile rate over a partial
/// route is a different statement from one over a complete route, and the caller
/// must be able to tell.
nonisolated struct ShiftMetrics: Equatable, Sendable {
    /// The amount recorded for the shift, or `nil` if none was.
    let grossEarnings: Money?

    /// The shift's elapsed wall-clock duration, or `nil` while it is running.
    ///
    /// Elapsed, not worked: this is the whole time between starting and ending
    /// the shift, waiting and repositioning included. ``deliveryActiveTime``
    /// says how much of it a recorded delivery was open for, which is a
    /// different and much narrower claim.
    let elapsedDuration: TimeInterval?

    /// What the shift's retained route measured, including how much of the
    /// shift it covers.
    let recordedDistance: RouteDistance

    /// How much of the shift at least one recorded delivery was active for,
    /// with deliveries worked at the same time counted once.
    let deliveryActiveTime: DeliveryActiveTime

    /// Gross earnings divided by the shift's **elapsed** hours.
    ///
    /// Waiting and idling included, because the denominator is the whole shift.
    /// Deliberately kept alongside ``grossPerDeliveryActiveHour`` rather than
    /// replaced by it: the two answer different questions, and this one is the
    /// figure that does not depend on how diligently the driver recorded their
    /// deliveries.
    let grossPerElapsedHour: ShiftRate

    /// Gross earnings divided by the hours at least one delivery was active.
    ///
    /// Still **gross**, and still earnings the driver typed for the whole shift.
    /// It is not an active wage, a true hourly rate, a working rate or a net
    /// one: the denominator is time a recorded delivery was open, which is not
    /// a measure of effort, movement or work, and the numerator has had nothing
    /// subtracted from it.
    ///
    /// The denominator is the union of the delivery intervals, so overlapping
    /// stacked deliveries make it smaller than the sum of their durations and
    /// this rate correspondingly higher.
    let grossPerDeliveryActiveHour: ShiftRate

    /// Gross earnings divided by the miles the route actually **recorded**.
    ///
    /// The denominator is recorded mileage, which is normally less than the
    /// mileage driven: capture is foreground-only and distance across a gap is
    /// excluded rather than guessed. A caller presenting this rate must not
    /// describe it as earnings per mile driven — see ``isRoutePartial``.
    let grossPerRecordedMile: ShiftRate

    /// Whether the mileage this rate divides by is known to be incomplete.
    var isRoutePartial: Bool { recordedDistance.isPartial }

    /// Whether any rate could be derived at all.
    var hasAnyRate: Bool {
        grossPerElapsedHour.isAvailable
            || grossPerDeliveryActiveHour.isAvailable
            || grossPerRecordedMile.isAvailable
    }

    /// The shift's elapsed time that no recorded delivery was active for, or
    /// `nil` when there is nothing to subtract from or nothing measured to
    /// subtract. **Not idle time** — see
    /// ``DeliveryActiveTime/nonDeliveryDuration(inElapsed:)``, which is the one
    /// place the subtraction is defined.
    var nonDeliveryDuration: TimeInterval? {
        deliveryActiveTime.nonDeliveryDuration(inElapsed: elapsedDuration)
    }
}
