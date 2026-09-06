import Foundation

/// Why one delivery has no gross-per-hour figure.
///
/// Kept apart for the reason every other absence in this project is: "no amount
/// was entered" and "the amount entered was zero" are different statements, and
/// so are "this delivery was cancelled" and "this delivery took no time".
/// Collapsing any pair of them would let the interface say something the data
/// does not support.
nonisolated enum DeliveryRateUnavailability: CaseIterable, Equatable, Sendable {
    /// The delivery was not delivered — it is still running, or it was
    /// cancelled.
    ///
    /// One case for both, deliberately. A rate needs a lifecycle that ran from
    /// acceptance to *completion*, and a cancelled delivery has no completion to
    /// measure to. Deriving one to its cancellation instead would put a figure
    /// in the same column as deliveries that finished, and inventing the phrase
    /// "cancelled hourly rate" for it. A cancelled delivery may still carry an
    /// amount the driver was paid, and showing that amount is the whole of what
    /// DashPilot claims about it.
    case deliveryNotCompleted
    /// The driver has not recorded what this delivery paid. Not the same as
    /// `$0.00`.
    case earningsNotRecorded
    /// The delivery's lifecycle covered no measurable time — accepted and
    /// delivered in the same instant, including one clamped there by a
    /// backwards device clock. This is a measurement, not an absence of one.
    case zeroDuration
}

nonisolated extension DeliveryRateUnavailability {
    /// Why the driver is not being shown a rate, in one sentence.
    ///
    /// Each states the fact and, where there is one, the thing that would
    /// produce the rate — without ever implying the missing value is zero.
    var explanation: String {
        switch self {
        case .deliveryNotCompleted:
            "This rate is worked out for deliveries that were completed, over the time from accepting one to delivering it."
        case .earningsNotRecorded:
            "Add what this delivery paid to see this rate."
        case .zeroDuration:
            "This delivery was accepted and delivered in the same moment, so there is no time to divide by."
        }
    }
}

/// A delivery's gross earnings per hour of its own lifecycle, or the reason
/// there is not one.
///
/// ## What the denominator is
///
/// **One delivery's own elapsed lifecycle**, from `acceptedAt` to `deliveredAt`.
/// Nothing else: not the shift, not the driver's working day, and not any
/// stretch of time shared with another delivery.
///
/// ## Why these figures must never be added up
///
/// Deliveries overlap. A driver carrying two orders at once has two lifecycles
/// running over the same minutes, so two thirty-minute deliveries are not an
/// hour of anything — they may be thirty minutes of the driver's evening. This
/// figure is therefore a fact about *one* delivery and is never summed,
/// averaged or compared across a shift; the one figure that spans deliveries is
/// the shift's delivery active time, which unions their intervals rather than
/// adding their durations. See ``DeliveryActiveTimeCalculator``.
///
/// ## What it is not
///
/// Not an hourly wage, not an active shift rate and not a driving rate. The
/// numerator is gross — nothing for fuel, wear, insurance or tax is subtracted
/// anywhere in DashPilot — and the denominator measures how long the delivery
/// was open, which says nothing about what the driver was doing during it.
nonisolated enum DeliveryEarningsRate: Equatable, Sendable {
    case available(Money)
    case unavailable(DeliveryRateUnavailability)

    /// The rate, or `nil` when there is not one.
    var amount: Money? {
        switch self {
        case let .available(amount): amount
        case .unavailable: nil
        }
    }

    var isAvailable: Bool { amount != nil }

    /// Why there is no rate, or `nil` when there is one.
    var unavailability: DeliveryRateUnavailability? {
        switch self {
        case .available: nil
        case let .unavailable(reason): reason
        }
    }
}

extension Delivery {
    /// This delivery's gross earnings per hour of its own recorded lifecycle.
    ///
    /// Derived on demand and never stored, like every other rate in DashPilot: a
    /// stored figure would be a second answer to a question the amount and the
    /// timestamps already answer, and it would keep the old answer after either
    /// changed.
    ///
    /// Both inputs come from this delivery alone — the amount the driver typed
    /// against it, and ``completedDuration``, which exists only for a delivery
    /// that was actually delivered. No other delivery's timing, and no part of
    /// the shift's own amount, enters the calculation, so two stacked deliveries
    /// produce two independent figures however far their lifecycles overlap.
    ///
    /// The arithmetic is ``ShiftMetricsCalculator/grossPerHour(of:over:)``, the
    /// one definition of an amount per hour in the app, so this figure and the
    /// shift's two hourly rates round identically.
    var grossPerDeliveryHour: DeliveryEarningsRate {
        guard let completedDuration else { return .unavailable(.deliveryNotCompleted) }
        guard let grossEarnings else { return .unavailable(.earningsNotRecorded) }
        guard let rate = ShiftMetricsCalculator.grossPerHour(of: grossEarnings, over: completedDuration) else {
            return .unavailable(.zeroDuration)
        }
        return .available(rate)
    }
}
