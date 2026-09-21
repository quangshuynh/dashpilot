import Foundation

/// Why a shift has no estimated net.
///
/// Each case is a different fact, kept apart for the reason
/// ``ShiftRateUnavailability`` and ``FuelEstimateUnavailability`` keep theirs
/// apart: a shift that recorded no earnings, one with no fuel estimate and one
/// with no working hours to divide by are three different things to tell a
/// driver, and none of them is a net of zero.
nonisolated enum EstimatedNetUnavailability: CaseIterable, Equatable, Sendable {
    /// The shift is still running. A net describes a finished shift, as every
    /// other derived figure here does.
    case shiftNotCompleted
    /// The driver has not recorded what the shift paid. Not the same as `$0.00`,
    /// and not something a total of the shift's deliveries may be substituted
    /// for.
    case earningsNotRecorded
    /// There is no estimated fuel cost to subtract. Which half is missing is
    /// said by ``FuelEstimateUnavailability`` in the fuel section itself, rather
    /// than repeated here.
    case fuelNotEstimated
    /// The shift covered no measurable working time, so there are no hours to
    /// divide by. Reached by a shift of no length and by one kept paused
    /// throughout.
    case noWorkingTime
}

nonisolated extension EstimatedNetUnavailability {
    /// Why the driver is not being shown a net, in one sentence.
    var explanation: String {
        switch self {
        case .shiftNotCompleted:
            "This shift is still running. Estimated net is worked out once it ends."
        case .earningsNotRecorded:
            "Add what this shift paid to see an estimated net."
        case .fuelNotEstimated:
            "Add your miles per gallon and a gas price to see an estimated net after fuel."
        case .noWorkingTime:
            "This shift recorded no working time, so there are no hours to divide by."
        }
    }
}

/// An estimated net figure, or the reason there is not one.
///
/// A `Money?` would carry the figure and lose the reason. Nothing substitutes
/// zero for an absent net, and the value **may legitimately be negative**: a
/// shift whose estimated fuel exceeded what it paid is a real outcome, not an
/// error to clamp.
nonisolated enum EstimatedNet: Equatable, Sendable {
    case available(Money)
    case unavailable(EstimatedNetUnavailability)

    /// The figure, or `nil` when there is not one.
    var amount: Money? {
        switch self {
        case let .available(amount): amount
        case .unavailable: nil
        }
    }

    var isAvailable: Bool { amount != nil }

    /// Why there is no figure, or `nil` when there is one.
    var unavailability: EstimatedNetUnavailability? {
        switch self {
        case .available: nil
        case let .unavailable(reason): reason
        }
    }
}

/// What one finished shift is estimated to have been left with after fuel.
///
/// ## The one subtraction this type performs
///
/// ```
/// estimated net after fuel = recorded shift earnings − estimated fuel cost
/// ```
///
/// and then, over the shift's **working** hours:
///
/// ```
/// estimated net per working hour = estimated net after fuel / working hours
/// ```
///
/// Nothing else is subtracted, added or allocated anywhere here.
///
/// ## Recorded and estimated stay visibly apart
///
/// The left-hand side of that subtraction is **recorded**: it is the amount the
/// driver typed for this shift. The right-hand side is **estimated**: it is
/// arithmetic over a measured distance and two assumptions. The result is an
/// estimate, and every name here says so.
///
/// ## Why recorded expenses are not in it, and this is the part to read
///
/// DashPilot records operating expenses, and deliberately attaches **none of
/// them to a shift**: an ``Expense`` has no relationship to ``Shift`` or
/// ``Delivery``, belongs to the period containing its own date, and nothing in
/// the app attributes a cost to a stretch of work. That is a domain decision
/// older than this type, and splitting a tank of fuel or a year's insurance
/// across the shifts it covered would be exactly the invention the decision
/// exists to refuse.
///
/// So a shift has no recorded expenses to net against, and this type does not
/// invent a way to give it some. **Net after recorded expenses is a period
/// figure** (``PeriodNetAfterExpenses``) and stays one. What a completed shift
/// can honestly say is what it paid and what its recorded miles are estimated to
/// have cost in fuel, which is what this is.
///
/// ## The double-counting the app does not resolve for you
///
/// ``ExpenseCategory/fuel`` exists, and a driver may well have recorded the
/// fill-up that paid for these miles. The estimate here and that expense can
/// therefore describe overlapping money, in different places, on different
/// screens. DashPilot **states this rather than reconciling it**: it does not
/// know which shifts a tank of fuel was burned on, it does not subtract an
/// estimated cost from a recorded one, and it never nets the two together in any
/// figure. Automatic reconciliation would require the app to decide which
/// recorded purchase belongs to which shift, which is precisely what it has no
/// evidence for.
///
/// ## What it is not
///
/// Not profit, not take-home pay, not a taxable figure, not an accounting
/// result and not a guarantee of anything. Nothing for wear, insurance,
/// maintenance, depreciation, self-employment tax or any other cost of driving
/// is subtracted, and no figure here was read from a delivery platform.
///
/// ## What its numerator is, and is not
///
/// The recorded earnings are the shift's **own** recorded amount. They are never
/// a total of the amounts recorded against individual deliveries, and no
/// delivery tip is ever part of them: shift gross and delivery gross are
/// independent recorded facts, and adding delivery amounts into a shift figure
/// would read every delivery with no amount as one that paid nothing. What a
/// delivery actually paid, tips included, is ``EffectiveDeliveryEarnings``, and
/// it stays where it is.
nonisolated struct ShiftProfitability: Equatable, Sendable {
    /// What the driver recorded this shift paid, or `nil` when they recorded
    /// nothing. **Gross**, and never derived from the shift's deliveries.
    let recordedEarnings: Money?

    /// What this shift's recorded miles are estimated to have cost in fuel, or
    /// the reason there is no estimate.
    let fuelEstimate: FuelEstimate

    /// The denominator of ``estimatedNetPerWorkingHour``: elapsed time less the
    /// stretches the driver paused, or `nil` while the shift is running.
    ///
    /// **The same figure ``ShiftMetrics/workingDuration`` is**, passed in rather
    /// than recomputed, so the hourly net and the hourly gross on the same
    /// screen divide by exactly the same seconds.
    let workingDuration: TimeInterval?

    /// ``recordedEarnings`` less the estimated fuel cost, or the reason there is
    /// no such figure.
    ///
    /// May be negative, which is a real outcome and is presented as one.
    let estimatedNetAfterFuel: EstimatedNet

    /// ``estimatedNetAfterFuel`` over the shift's working hours, or the reason
    /// there is no such figure.
    let estimatedNetPerWorkingHour: EstimatedNet

    /// Whether the estimate behind these figures is over a route known to cover
    /// less than the shift.
    ///
    /// True exactly when the fuel estimate's own route was partial, which makes
    /// the fuel a floor and therefore the net a **ceiling**: more fuel was used
    /// than was estimated, so less was left than is stated here.
    var isRoutePartial: Bool { fuelEstimate.consumption?.isRoutePartial ?? false }

    /// Whether either figure could be derived at all.
    var hasAnyFigure: Bool {
        estimatedNetAfterFuel.isAvailable || estimatedNetPerWorkingHour.isAvailable
    }

    /// **The** derivation, and the only one.
    ///
    /// - Parameters:
    ///   - recordedEarnings: the amount recorded for the shift, or `nil`. Never
    ///     read as zero.
    ///   - fuelEstimate: what the shift's recorded miles are estimated to have
    ///     cost, from ``FuelEstimateCalculator``. Its absence is carried through
    ///     rather than treated as no fuel used.
    ///   - workingDuration: the shift's working time, or `nil` while it runs.
    ///     It is what decides whether the shift has finished as well as what the
    ///     hourly figure divides by, exactly as it does in
    ///     ``ShiftMetricsCalculator``.
    init(recordedEarnings: Money?, fuelEstimate: FuelEstimate, workingDuration: TimeInterval?) {
        self.recordedEarnings = recordedEarnings
        self.fuelEstimate = fuelEstimate
        self.workingDuration = workingDuration

        let net = Self.net(recordedEarnings: recordedEarnings, fuelEstimate: fuelEstimate, workingDuration: workingDuration)
        estimatedNetAfterFuel = net
        estimatedNetPerWorkingHour = Self.hourly(net: net, workingDuration: workingDuration)
    }

    private static func net(
        recordedEarnings: Money?,
        fuelEstimate: FuelEstimate,
        workingDuration: TimeInterval?
    ) -> EstimatedNet {
        guard workingDuration != nil else { return .unavailable(.shiftNotCompleted) }
        guard let recordedEarnings else { return .unavailable(.earningsNotRecorded) }
        guard let cost = fuelEstimate.cost else { return .unavailable(.fuelNotEstimated) }
        return .available(recordedEarnings - cost)
    }

    private static func hourly(net: EstimatedNet, workingDuration: TimeInterval?) -> EstimatedNet {
        switch net {
        case let .unavailable(reason):
            return .unavailable(reason)
        case let .available(amount):
            guard let workingDuration else { return .unavailable(.shiftNotCompleted) }
            // The app's one hourly division, shared with both of the shift's
            // gross rates and with a delivery's own. A second copy would be free
            // to drift, and two hourly figures on one screen disagreeing in the
            // last cent is exactly the difference nobody thinks to look for.
            guard let rate = ShiftMetricsCalculator.grossPerHour(of: amount, over: workingDuration) else {
                return .unavailable(.noWorkingTime)
            }
            return .available(rate)
        }
    }
}

extension Shift {
    /// What this shift is estimated to have been left with after fuel.
    ///
    /// The adapter between the model and ``ShiftProfitability``, holding no rule
    /// of its own. Nothing is stored: the figures are derived from the recorded
    /// amount, the shift's own timestamps and pauses, and the route's
    /// measurement, every time they are asked for.
    ///
    /// `recordedDistance` is passed in rather than measured here for the reason
    /// ``metrics(for:using:)`` takes one: measuring a route walks every position
    /// it holds, and the caller normally already has the result.
    func profitability(
        for recordedDistance: RouteDistance,
        using calculator: FuelEstimateCalculator = FuelEstimateCalculator()
    ) -> ShiftProfitability {
        ShiftProfitability(
            recordedEarnings: grossEarnings,
            fuelEstimate: fuelEstimate(for: recordedDistance, using: calculator),
            // The very same definition the shift's gross hourly rate divides by.
            workingDuration: completedWorkingDuration
        )
    }
}
