import Foundation

/// Derives a completed shift's rates from what DashPilot already stores.
///
/// ## The rule this type exists for
///
/// **A missing input never becomes a zero.** A shift with no amount recorded is
/// not a shift that paid nothing; a shift with no measurable route is not a
/// shift that drove nowhere. Either would produce a number the interface could
/// show, and both would be inventions. Every input this calculation cannot use
/// produces a ``ShiftRateUnavailability`` naming the reason instead.
///
/// It takes plain values rather than a `Shift`, so both rates can be tested
/// without a store, a container or a rendered view. ``Shift/metrics(for:using:)``
/// is the adapter that reads the model's own fields into it.
///
/// ## Precision
///
/// Money stays exact. The numerator is the `Decimal` the driver typed and never
/// passes through binary floating point, and division happens through
/// ``Money/divided(by:scale:mode:)``.
///
/// The *denominators* are the boundary. A duration is a `TimeInterval` and a
/// distance is a `Double` of metres — both are binary measurements before this
/// calculation ever sees them, and neither can be made exact after the fact. So
/// each crosses into `Decimal` exactly once, here, rounded to a scale far finer
/// than anything the result is read at: a duration to the millisecond, a
/// distance to a millionth of a mile. Converting repeatedly, or letting a
/// `Double` reach the division itself, is what accumulates error, and neither
/// happens.
///
/// The quotient is kept to ``rateScale`` fraction digits — four more than the
/// two a rate is displayed at — so that the value the display rounds is
/// effectively the exact quotient rather than one already rounded at an
/// adjacent scale.
nonisolated struct ShiftMetricsCalculator: Equatable, Sendable {
    /// Fraction digits kept on a derived rate.
    ///
    /// Presentation rounds to ``Money/displayScale``; this is deliberately much
    /// finer, so rounding happens once, where it is a display decision, rather
    /// than twice at scales close enough for the first to move the second.
    static let rateScale = 6

    /// Fraction digits kept when a duration becomes a decimal number of seconds.
    ///
    /// A shift is measured in hours and its timestamps come from `Date`, so a
    /// millisecond is already far below anything an hourly rate can express.
    static let durationScale = 3

    /// Fraction digits kept when a distance becomes a decimal number of miles.
    ///
    /// A millionth of a mile is under two millimetres — many orders of magnitude
    /// finer than positions carrying error radii of up to 100 m.
    static let distanceScale = 6

    private static let secondsPerHour = Decimal(3600)

    init() {}

    /// Derives both rates.
    ///
    /// - Parameters:
    ///   - grossEarnings: what the driver recorded the shift paid, or `nil` if
    ///     they have not. `nil` is never read as zero.
    ///   - elapsedDuration: the shift's wall-clock length, or `nil` while it is
    ///     still running.
    ///   - recordedDistance: what the shift's retained route measured. It
    ///     already distinguishes an unmeasurable route from a measured one, and
    ///     that distinction is carried through rather than flattened here.
    ///   - deliveryActiveTime: the union of the shift's delivery intervals, from
    ///     ``DeliveryActiveTimeCalculator``. It defaults to ``DeliveryActiveTime/none``,
    ///     which is the truthful reading of a shift with no deliveries to
    ///     measure and produces no active-hour rate rather than a fabricated one.
    func metrics(
        grossEarnings: Money?,
        elapsedDuration: TimeInterval?,
        recordedDistance: RouteDistance,
        deliveryActiveTime: DeliveryActiveTime = .none
    ) -> ShiftMetrics {
        ShiftMetrics(
            grossEarnings: grossEarnings,
            elapsedDuration: elapsedDuration,
            recordedDistance: recordedDistance,
            deliveryActiveTime: deliveryActiveTime,
            grossPerElapsedHour: hourlyRate(of: grossEarnings, over: elapsedDuration),
            grossPerDeliveryActiveHour: activeHourlyRate(
                of: grossEarnings,
                over: deliveryActiveTime,
                elapsedDuration: elapsedDuration
            ),
            grossPerRecordedMile: mileageRate(of: grossEarnings, over: recordedDistance, elapsedDuration: elapsedDuration)
        )
    }

    // MARK: Rates

    /// Gross earnings per hour of **elapsed** shift time.
    ///
    /// The denominator is the whole wall-clock length of the shift, waiting and
    /// idling included. It is the figure that does not depend on the driver
    /// having recorded their deliveries, which is why it stays even though
    /// ``activeHourlyRate(of:over:elapsedDuration:)`` now exists beside it.
    private func hourlyRate(of grossEarnings: Money?, over elapsedDuration: TimeInterval?) -> ShiftRate {
        guard let elapsedDuration else { return .unavailable(.shiftNotCompleted) }
        guard let grossEarnings else { return .unavailable(.earningsNotRecorded) }
        // A shift ended at the moment it started — including one whose end was
        // clamped to its start by a backwards device clock — covers no time to
        // earn over.
        return rate(of: grossEarnings, overHoursIn: elapsedDuration, otherwise: .noElapsedTime)
    }

    /// Gross earnings per hour at least one recorded delivery was active.
    ///
    /// The denominator is the **union** of the shift's delivery intervals, so
    /// two deliveries carried at the same time contribute their overlap once.
    /// Summing their durations instead would let the denominator exceed the
    /// shift and would drive the rate down precisely when a driver stacked well.
    ///
    /// Still gross, and still one amount recorded for the whole shift: no
    /// earnings are attributed to an individual delivery anywhere in DashPilot.
    /// The three absent cases are kept apart for the reason every other pair is
    /// — a shift with no deliveries, one whose deliveries describe no usable
    /// interval, and one whose deliveries genuinely covered no time are three
    /// different facts, and none of them is a rate of zero.
    private func activeHourlyRate(
        of grossEarnings: Money?,
        over deliveryActiveTime: DeliveryActiveTime,
        elapsedDuration: TimeInterval?
    ) -> ShiftRate {
        guard elapsedDuration != nil else { return .unavailable(.shiftNotCompleted) }
        guard let grossEarnings else { return .unavailable(.earningsNotRecorded) }
        guard deliveryActiveTime.isAvailable else {
            return .unavailable(
                deliveryActiveTime.sourceIntervalCount == 0
                    ? .noDeliveriesRecorded
                    : .deliveryActiveTimeNotMeasurable
            )
        }
        return rate(of: grossEarnings, overHoursIn: deliveryActiveTime.duration, otherwise: .zeroDeliveryActiveTime)
    }

    /// An amount divided by a duration expressed in hours, or `reason` when the
    /// duration cannot be a denominator.
    ///
    /// Shared by both hourly rates so there is one crossing into decimal
    /// seconds, one conversion to hours and one rounding scale between them. A
    /// second copy would be free to drift, and two hourly figures on the same
    /// screen disagreeing in the last cent is exactly the kind of difference
    /// nobody would think to look for.
    private func rate(
        of grossEarnings: Money,
        overHoursIn duration: TimeInterval,
        otherwise reason: ShiftRateUnavailability
    ) -> ShiftRate {
        guard
            let seconds = Self.decimal(duration, scale: Self.durationScale),
            seconds > 0,
            let rate = grossEarnings.divided(by: seconds / Self.secondsPerHour, scale: Self.rateScale)
        else {
            return .unavailable(reason)
        }
        return .available(rate)
    }

    /// Gross earnings per mile the route **recorded**.
    ///
    /// Whether the route covers the whole shift is not this calculation's
    /// judgement to make: the quotient over a partial route is a real figure
    /// over a real denominator, and ``RouteDistance/isPartial`` travels with it
    /// so a caller can say what the denominator was.
    private func mileageRate(
        of grossEarnings: Money?,
        over recordedDistance: RouteDistance,
        elapsedDuration: TimeInterval?
    ) -> ShiftRate {
        guard elapsedDuration != nil else { return .unavailable(.shiftNotCompleted) }
        guard let grossEarnings else { return .unavailable(.earningsNotRecorded) }
        guard recordedDistance.isMeasured else {
            // Nothing usable at all, versus positions that no continuous stretch
            // of capture joined. Neither is a distance of zero.
            return .unavailable(
                recordedDistance.usableSampleCount == 0 ? .noRouteRecorded : .routeNotMeasurable
            )
        }
        guard let miles = Self.decimal(recordedDistance.miles, scale: Self.distanceScale), miles >= 0 else {
            // A measured distance that cannot be expressed as a number is not a
            // measurement, whatever the segment count says.
            return .unavailable(.routeNotMeasurable)
        }
        guard miles > 0, let rate = grossEarnings.divided(by: miles, scale: Self.rateScale) else {
            return .unavailable(.zeroRecordedDistance)
        }
        return .available(rate)
    }

    // MARK: The precision boundary

    /// Converts a binary measurement into a decimal one, rounded to `scale`
    /// fraction digits.
    ///
    /// The single crossing from `Double` to `Decimal` in this calculation.
    /// `Decimal(_: Double)` is deliberately not used: it reinterprets a binary
    /// value whose exact expansion is longer than the measurement means, and the
    /// result then depends on the platform's conversion rather than on a rule
    /// stated here. Scaling to an integer and dividing by a power of ten is
    /// explicit, testable and the same everywhere.
    ///
    /// Returns `nil` for a value that is not finite or is too large to scale
    /// without overflowing, which is a malformed measurement rather than a
    /// small or large one.
    static func decimal(_ value: Double, scale: Int) -> Decimal? {
        guard value.isFinite else { return nil }
        let scaled = (value * pow(10, Double(scale))).rounded()
        guard let units = Int64(exactly: scaled) else { return nil }
        return Decimal(units) / pow(10, scale)
    }
}

extension Shift {
    /// This shift's derived metrics.
    ///
    /// The adapter between the model and ``ShiftMetricsCalculator``: it reads
    /// the shift's own recorded facts and hands them over, and holds no rule of
    /// its own. Nothing here is stored — the metrics are recomputed from the
    /// shift every time they are asked for.
    ///
    /// `recordedDistance` is passed in rather than measured here because
    /// measuring a route walks every position it holds, and the caller normally
    /// already has the result — the history row measures once when it appears.
    /// ``Shift/recordedDistance(using:)`` is what produces it.
    ///
    /// Delivery active time is derived here rather than passed in, because a
    /// shift holds a handful of deliveries where it holds thousands of
    /// positions: the union sorts a list short enough that measuring it on
    /// demand costs nothing worth arranging around.
    func metrics(
        for recordedDistance: RouteDistance,
        using calculator: ShiftMetricsCalculator = ShiftMetricsCalculator()
    ) -> ShiftMetrics {
        calculator.metrics(
            grossEarnings: grossEarnings,
            elapsedDuration: completedDuration,
            recordedDistance: recordedDistance,
            deliveryActiveTime: deliveryActiveTime()
        )
    }
}
