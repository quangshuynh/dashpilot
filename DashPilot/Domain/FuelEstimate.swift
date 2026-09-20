import Foundation

/// The two facts a fuel estimate is worked out from, as one shift recorded them.
///
/// Both are optional and independent: a driver may know their vehicle's fuel
/// economy without having recorded what they last paid for fuel, and the
/// interface has to be able to say which half is missing. Neither is ever read
/// as zero.
///
/// ## Why a shift carries its own copy
///
/// These are **assumptions**, and an assumption that moves rewrites history. A
/// driver who buys a more economical car, or who fills up at a higher price next
/// month, has not changed what last Tuesday's shift cost them in fuel. So the
/// pair a shift was estimated under is recorded on that shift and is what its
/// estimate is always derived from. Nothing anywhere reads a current, global
/// figure into a finished shift.
///
/// What *is* global is a convenience only: the editor seeds its fields from the
/// most recent shift that recorded assumptions, so a driver types them once
/// rather than every time. Seeding a field is not the same as deriving a figure,
/// and nothing about an older shift changes when a newer one records something
/// different.
nonisolated struct FuelAssumptions: Equatable, Sendable {
    /// The vehicle's fuel economy in miles per gallon, or `nil` when the driver
    /// has not recorded it.
    ///
    /// A `Decimal` rather than a ``Money``, because it is not money: it is a
    /// ratio the driver typed, and it is the **divisor** of the estimate. It is
    /// always greater than zero where it is present, because ``Shift`` refuses
    /// anything else: a vehicle that covers no distance on a gallon is not a
    /// measurement and cannot be divided by.
    let milesPerGallon: Decimal?

    /// What a gallon of fuel cost, or `nil` when the driver has not recorded it.
    ///
    /// Zero is allowed and is a different fact from missing: fuel really can
    /// have cost the driver nothing on a particular shift, and an explicit
    /// ``Money/zero`` says so. `nil` says nobody wrote a price down.
    let gasPricePerGallon: Money?

    /// Neither assumption recorded, which is what every shift carried before
    /// fuel estimation existed and what every new shift carries.
    static let none = FuelAssumptions(milesPerGallon: nil, gasPricePerGallon: nil)

    init(milesPerGallon: Decimal?, gasPricePerGallon: Money?) {
        self.milesPerGallon = milesPerGallon
        self.gasPricePerGallon = gasPricePerGallon
    }

    /// Whether either assumption was recorded.
    ///
    /// The question a screen asks before saying anything about fuel at all: a
    /// shift carrying neither has nothing to show and nothing to remove.
    var hasAny: Bool { milesPerGallon != nil || gasPricePerGallon != nil }

    /// Whether both were recorded, which is what an estimate needs.
    var isComplete: Bool { milesPerGallon != nil && gasPricePerGallon != nil }
}

/// Why a shift has no estimated fuel cost.
///
/// Each case is a different fact about the shift, kept apart for the reason
/// ``ShiftRateUnavailability`` keeps its own cases apart: "no fuel economy was
/// entered", "no price was entered" and "there is no measured mileage to
/// estimate over" are three different things to tell a driver, and none of them
/// is an estimate of `$0.00`.
///
/// **A missing assumption is never zero.** A shift with no gas price recorded is
/// not a shift whose fuel was free, and a shift with no fuel economy recorded is
/// not one that used no fuel.
nonisolated enum FuelEstimateUnavailability: CaseIterable, Equatable, Sendable {
    /// The driver has not recorded the vehicle's miles per gallon.
    case milesPerGallonNotRecorded
    /// The driver has not recorded what a gallon of fuel cost.
    case gasPriceNotRecorded
    /// The shift retained no usable position, so it has no recorded mileage to
    /// estimate over. Not the same as a shift that recorded no distance.
    case noRouteRecorded
    /// Positions were retained, but no two of them were recorded continuously,
    /// so no distance could be measured to estimate over.
    case routeNotMeasurable
}

nonisolated extension FuelEstimateUnavailability {
    /// Why the driver is not being shown an estimate, in one sentence.
    ///
    /// Each one states the fact and, where there is one, the thing that would
    /// produce the estimate, without ever implying the missing value is zero.
    var explanation: String {
        switch self {
        case .milesPerGallonNotRecorded:
            "Add your vehicle's miles per gallon to estimate this shift's fuel."
        case .gasPriceNotRecorded:
            "Add what a gallon of fuel cost to estimate this shift's fuel."
        case .noRouteRecorded:
            "No usable position was recorded for this shift, so there are no recorded miles to estimate fuel over."
        case .routeNotMeasurable:
            """
            No two recorded positions were captured continuously, so there are no recorded miles to \
            estimate fuel over.
            """
        }
    }
}

/// An estimate of what one shift's recorded miles consumed, and what that fuel
/// cost at the price the shift recorded.
///
/// ## What this is not
///
/// **It is not a recorded expense.** Nothing here creates, reads or changes an
/// ``Expense``. A driver who records a fuel purchase has recorded a cost they
/// actually paid; this is arithmetic over a distance and two assumptions, and
/// the two live in different places on purpose. See ``Expense`` and the
/// "Recorded expenses" documentation for the one ambiguity this leaves, which is
/// documented rather than reconciled automatically.
///
/// **It is not proof of anything.** Not of fuel actually bought, not of fuel
/// actually burned, not of what the vehicle cost to operate, and not a tax
/// deduction. It is what the recorded mileage would have consumed if the vehicle
/// really does the recorded miles per gallon, priced at the recorded price.
///
/// **It does not cover unrecorded driving.** The denominator is recorded
/// mileage, which is a floor on the miles driven: capture can be interrupted, and
/// the distance across a gap is left out rather than guessed. ``isRoutePartial``
/// travels with the figure so a caller can say so, and it must.
nonisolated struct FuelConsumption: Equatable, Sendable {
    /// The recorded miles the estimate was worked out over.
    let recordedMiles: Decimal

    /// The fuel economy the estimate assumed, exactly as the shift recorded it.
    let milesPerGallon: Decimal

    /// The price per gallon the estimate assumed, exactly as the shift recorded
    /// it.
    let gasPricePerGallon: Money

    /// `recordedMiles / milesPerGallon`, rounded to ``FuelEstimateCalculator/gallonScale``.
    ///
    /// **Never** `recordedMiles * gasPricePerGallon`: miles are not gallons, and
    /// a cost worked out that way would be wrong by whatever the vehicle's fuel
    /// economy is.
    let gallons: Decimal

    /// `gallons * gasPricePerGallon`, as an exact ``Money``.
    let cost: Money

    /// Whether the recorded mileage behind this estimate is known to be less
    /// than the mileage driven.
    ///
    /// True exactly when ``RouteDistance/isPartial`` is. An estimate over a
    /// partial route is a real figure over a real denominator, and it is a
    /// **floor**: more miles were driven than were recorded, so more fuel was
    /// used than this estimates.
    let isRoutePartial: Bool

    /// The gallons figure as the interface writes it: `"1.83 gal"`.
    ///
    /// The one place gallons become a string, so no view builds one from a
    /// number and a unit. `usage: .asProvided` is deliberate: the driver
    /// recorded miles per gallon and a price per gallon, so a locale that would
    /// rather read litres would be describing a quantity nobody entered.
    ///
    /// `width` exists for VoiceOver, exactly as it does on
    /// ``RouteDistance/formattedMiles(width:locale:)``: `gal` reads well and
    /// hears badly.
    func formattedGallons(
        width: Measurement<UnitVolume>.FormatStyle.UnitWidth = .abbreviated,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        Measurement(value: Self.displayGallons(gallons), unit: UnitVolume.gallons).formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(Self.gallonDisplayScale))
            )
            .locale(locale)
        )
    }

    /// Fraction digits a gallons figure is shown to.
    ///
    /// Two, because the mileage behind it is shown to one decimal of a mile and
    /// the economy is entered to the cent of a mile per gallon; a third would be
    /// describing precision the inputs do not have.
    static let gallonDisplayScale = 2

    /// The **display only** crossing from the exact `Decimal` to the `Double`
    /// `Measurement` formats.
    ///
    /// Nothing monetary goes through it: ``cost`` is derived from the exact
    /// `Decimal` gallons and the exact `Decimal` price, and this value is never
    /// read back into any arithmetic. It is rounded first so the conversion is
    /// of a two-place number rather than of a six-place one.
    private static func displayGallons(_ gallons: Decimal) -> Double {
        var source = gallons
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, gallonDisplayScale, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }
}

/// An estimated fuel consumption, or the reason there is not one.
///
/// A `Money?` would carry the cost and lose the reason, and every reason is
/// something the interface has to be able to say. Nothing substitutes zero for
/// an absent estimate.
nonisolated enum FuelEstimate: Equatable, Sendable {
    case available(FuelConsumption)
    case unavailable(FuelEstimateUnavailability)

    /// The estimated cost, or `nil` when there is no estimate.
    var cost: Money? {
        switch self {
        case let .available(consumption): consumption.cost
        case .unavailable: nil
        }
    }

    /// The estimated gallons, or `nil` when there is no estimate.
    var gallons: Decimal? {
        switch self {
        case let .available(consumption): consumption.gallons
        case .unavailable: nil
        }
    }

    /// The consumption, or `nil` when there is no estimate.
    var consumption: FuelConsumption? {
        switch self {
        case let .available(consumption): consumption
        case .unavailable: nil
        }
    }

    var isAvailable: Bool { consumption != nil }

    /// Why there is no estimate, or `nil` when there is one.
    var unavailability: FuelEstimateUnavailability? {
        switch self {
        case .available: nil
        case let .unavailable(reason): reason
        }
    }
}

/// **The** definition of estimated fuel in DashPilot.
///
/// One calculation, in one place, over plain values. Every surface that shows an
/// estimated gallon or an estimated fuel cost comes through here, so a second
/// copy cannot drift and two screens cannot disagree in the last cent.
///
/// ## The arithmetic
///
/// ```
/// gallons = recordedMiles / milesPerGallon
/// cost    = gallons * gasPricePerGallon
/// ```
///
/// The middle step is the whole point. `recordedMiles * gasPricePerGallon` is
/// the mistake this type exists to make impossible: it prices a mile as though a
/// mile were a gallon, and is wrong by a factor of the vehicle's fuel economy.
///
/// ## Precision
///
/// Money stays exact. The price is the `Decimal` the driver typed and never
/// passes through binary floating point, and the multiplication is
/// ``Money/*(_:_:)``.
///
/// The **distance** is the boundary, exactly as it is in
/// ``ShiftMetricsCalculator``: a ``RouteDistance`` is a `Double` of metres
/// before this calculation ever sees it. It crosses into `Decimal` once, through
/// ``ShiftMetricsCalculator/decimal(_:scale:)``, which is the app's one crossing
/// rule, at ``ShiftMetricsCalculator/distanceScale``, a millionth of a mile.
nonisolated struct FuelEstimateCalculator: Equatable, Sendable {
    /// Fraction digits kept on the derived gallons figure.
    ///
    /// Deliberately much finer than the two gallons are displayed at, so
    /// rounding happens once where it is a display decision rather than twice at
    /// scales close enough for the first to move the second. The cost is derived
    /// from the figure at *this* scale.
    static let gallonScale = 6

    init() {}

    /// Estimates what a shift's recorded mileage consumed, and what it cost.
    ///
    /// - Parameters:
    ///   - recordedDistance: what the shift's retained route measured. It
    ///     already tells an unmeasurable route from a measured one, and that
    ///     distinction is carried through rather than flattened: a route with
    ///     nothing usable in it has no mileage to estimate over, which is not
    ///     the same as a route that measured zero.
    ///   - assumptions: the pair the shift recorded. A missing half produces the
    ///     reason naming it, never a zero.
    func estimate(
        recordedDistance: RouteDistance,
        assumptions: FuelAssumptions
    ) -> FuelEstimate {
        guard let milesPerGallon = assumptions.milesPerGallon else {
            return .unavailable(.milesPerGallonNotRecorded)
        }
        guard let gasPricePerGallon = assumptions.gasPricePerGallon else {
            return .unavailable(.gasPriceNotRecorded)
        }
        guard recordedDistance.isMeasured else {
            // Nothing usable at all, versus positions that no continuous stretch
            // of capture joined. Neither is a distance of zero, and neither is
            // fuel of zero.
            return .unavailable(
                recordedDistance.usableSampleCount == 0 ? .noRouteRecorded : .routeNotMeasurable
            )
        }
        guard
            let miles = ShiftMetricsCalculator.decimal(
                recordedDistance.miles,
                scale: ShiftMetricsCalculator.distanceScale
            ),
            miles >= 0
        else {
            // A measured distance that cannot be expressed as a number is not a
            // measurement, whatever the segment count says.
            return .unavailable(.routeNotMeasurable)
        }
        // A shift really can measure zero recorded miles, from positions that
        // did not move, and that is a measurement. It consumes no fuel and costs
        // nothing, which is a figure rather than a missing value.
        guard milesPerGallon > 0 else {
            // Unreachable through ``Shift``, which refuses a non-positive
            // economy at the point it is recorded. Kept because this type takes
            // plain values and a divisor of zero must never reach the division.
            return .unavailable(.milesPerGallonNotRecorded)
        }

        let gallons = Self.dividing(miles, by: milesPerGallon, scale: Self.gallonScale)

        return .available(
            FuelConsumption(
                recordedMiles: miles,
                milesPerGallon: milesPerGallon,
                gasPricePerGallon: gasPricePerGallon,
                gallons: gallons,
                cost: gasPricePerGallon * gallons,
                isRoutePartial: recordedDistance.isPartial
            )
        )
    }

    /// Exact decimal division, rounded half away from zero at `scale`.
    ///
    /// `Decimal` division is not exact for a quotient such as `10 / 3`, so the
    /// rounding is stated here rather than left to whatever the first consumer
    /// happens to do with it. The divisor is guaranteed positive by the caller.
    private static func dividing(_ dividend: Decimal, by divisor: Decimal, scale: Int) -> Decimal {
        var quotient = dividend / divisor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, scale, .plain)
        return rounded
    }
}
