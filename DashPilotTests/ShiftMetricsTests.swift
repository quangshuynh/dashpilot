import Foundation
import SwiftData
import Testing
@testable import DashPilot

@Suite("Completed shift metrics")
struct ShiftMetricsTests {
    private let calculator = ShiftMetricsCalculator()
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// One mile in metres, so a test can state a distance in the unit the rate
    /// is expressed in. The same constant Foundation converts with.
    private static let metresPerMile = 1609.344

    /// A measured route covering `miles`, with no gaps unless one is asked for.
    private func measuredRoute(
        miles: Double,
        gapCount: Int = 0,
        usableSampleCount: Int = 40,
        usesInferredContinuity: Bool = false
    ) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: gapCount,
            usableSampleCount: usableSampleCount,
            usesInferredContinuity: usesInferredContinuity
        )
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    // MARK: Gross earnings per elapsed shift hour

    @Test("A normal completed shift earns a rate over its whole elapsed time")
    func hourlyRateOfANormalShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("28.75")))
    }

    @Test("A shift of exactly one hour earns its whole amount per hour")
    func hourlyRateOfAnHour() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("24.80"),
            elapsedDuration: 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("24.80")))
    }

    @Test("A fractional hour divides by the fraction, not by a rounded hour")
    func hourlyRateOfAFractionalShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("37.20"),
            elapsedDuration: 90 * 60,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("24.80")))
    }

    @Test("A shift of a few seconds is a real rate, however large")
    func hourlyRateOfAVeryShortShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("5.00"),
            elapsedDuration: 36,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("500.00")))
    }

    @Test("A long shift divides by all of its hours")
    func hourlyRateOfALongShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("412.50"),
            elapsedDuration: 11 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("37.50")))
    }

    @Test("A shift recorded as paying nothing has a rate of zero, not an absent one")
    func hourlyRateOfZeroEarnings() throws {
        let metrics = calculator.metrics(
            grossEarnings: .zero,
            elapsedDuration: 4 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .available(.zero))
        #expect(metrics.grossPerElapsedHour.amount?.isZero == true)
    }

    @Test("A shift with no amount recorded has no hourly rate, and is not treated as zero")
    func hourlyRateWithoutEarnings() {
        let metrics = calculator.metrics(
            grossEarnings: nil,
            elapsedDuration: 4 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .unavailable(.earningsNotRecorded))
        #expect(metrics.grossPerElapsedHour.amount == nil)
    }

    @Test("A completed shift covering no time has no hourly rate")
    func hourlyRateOfAZeroLengthShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("12.00"),
            elapsedDuration: 0,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour == .unavailable(.noElapsedTime))
    }

    @Test("A duration that is not a number is refused rather than divided by")
    func hourlyRateOfAMalformedDuration() throws {
        for duration in [Double.nan, .infinity, -3600] {
            let metrics = calculator.metrics(
                grossEarnings: try money("12.00"),
                elapsedDuration: duration,
                recordedDistance: .none
            )

            #expect(metrics.grossPerElapsedHour == .unavailable(.noElapsedTime))
        }
    }

    @Test("A running shift has no finalised rates at all")
    func noRatesWhileRunning() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("40.00"),
            elapsedDuration: nil,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerElapsedHour == .unavailable(.shiftNotCompleted))
        #expect(metrics.grossPerRecordedMile == .unavailable(.shiftNotCompleted))
        #expect(metrics.hasAnyRate == false)
    }

    // MARK: Precision

    @Test("The amount the driver typed is carried through the calculation unchanged")
    func earningsPrecisionSurvives() throws {
        let earnings = try money("86.25")

        let metrics = calculator.metrics(
            grossEarnings: earnings,
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossEarnings == earnings)
        #expect(metrics.grossEarnings?.amount == Decimal(string: "86.25"))
    }

    @Test("Rates are exact for amounts binary floating point cannot represent")
    func ratesAreExact() throws {
        // 0.30 over a tenth of an hour. In `Double`, 0.1 + 0.2 != 0.3 and this
        // is the arithmetic that would show it.
        let hourly = calculator.metrics(
            grossEarnings: try money("0.30"),
            elapsedDuration: 360,
            recordedDistance: .none
        )
        #expect(hourly.grossPerElapsedHour == .available(try money("3.00")))

        let perMile = calculator.metrics(
            grossEarnings: try money("0.30"),
            elapsedDuration: 3600,
            recordedDistance: measuredRoute(miles: 0.1)
        )
        #expect(perMile.grossPerRecordedMile == .available(try money("3.00")))
    }

    @Test("A rate keeps more precision than it is displayed at")
    func ratesKeepMoreThanDisplayPrecision() throws {
        // $100.00 over three hours does not divide into cents.
        let metrics = calculator.metrics(
            grossEarnings: try money("100.00"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        let rate = try #require(metrics.grossPerElapsedHour.amount)
        #expect(rate.amount == Decimal(string: "33.333333"))
        #expect(rate.rounded().amount == Decimal(string: "33.33"))
    }

    @Test("A duration is converted to a decimal once, at a fixed scale")
    func decimalConversionIsExplicit() {
        #expect(ShiftMetricsCalculator.decimal(1.5, scale: 3) == Decimal(string: "1.5"))
        #expect(ShiftMetricsCalculator.decimal(0.0004, scale: 3) == Decimal.zero)
        #expect(ShiftMetricsCalculator.decimal(2.0005, scale: 3) == Decimal(string: "2.001"))
        #expect(ShiftMetricsCalculator.decimal(.nan, scale: 3) == nil)
        #expect(ShiftMetricsCalculator.decimal(.infinity, scale: 3) == nil)
        #expect(ShiftMetricsCalculator.decimal(1e30, scale: 6) == nil)
    }

    // MARK: Gross earnings per recorded mile

    @Test("A measured route earns a rate over the miles it recorded")
    func mileageRateOfAMeasuredRoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerRecordedMile == .available(try money("8.625")))
    }

    @Test("One recorded mile earns the whole amount per recorded mile")
    func mileageRateOfOneMile() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("12.34"),
            elapsedDuration: 3600,
            recordedDistance: measuredRoute(miles: 1)
        )

        #expect(metrics.grossPerRecordedMile == .available(try money("12.34")))
    }

    @Test("A fractional distance divides by the fraction")
    func mileageRateOfFractionalMiles() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("45.00"),
            elapsedDuration: 3600,
            recordedDistance: measuredRoute(miles: 4.5)
        )

        #expect(metrics.grossPerRecordedMile == .available(try money("10.00")))
    }

    @Test("A long route divides by all of it")
    func mileageRateOfALargeRoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("1250.00"),
            elapsedDuration: 10 * 3600,
            recordedDistance: measuredRoute(miles: 250)
        )

        #expect(metrics.grossPerRecordedMile == .available(try money("5.00")))
    }

    @Test("A partial route still produces a rate, and says the denominator is partial")
    func mileageRateOfAPartialRoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10, gapCount: 2)
        )

        #expect(metrics.grossPerRecordedMile == .available(try money("8.625")))
        #expect(metrics.isRoutePartial, "A caller must be able to say the miles are only the recorded ones")
    }

    @Test("A legacy route whose continuity was only inferred is partial too")
    func mileageRateOfAnInferredRoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10, usesInferredContinuity: true)
        )

        #expect(metrics.grossPerRecordedMile.isAvailable)
        #expect(metrics.isRoutePartial)
    }

    @Test("The denominator is the recorded distance and nothing else")
    func mileageRateUsesRecordedDistanceOnly() throws {
        let earnings = try money("86.25")
        let complete = calculator.metrics(
            grossEarnings: earnings,
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10)
        )
        // The same recorded distance, but the shift is known to have stretches
        // the route never covered and many more stored positions. Neither is a
        // mileage the rate may reach for.
        let partial = calculator.metrics(
            grossEarnings: earnings,
            elapsedDuration: 9 * 3600,
            recordedDistance: measuredRoute(miles: 10, gapCount: 7, usableSampleCount: 4000)
        )

        #expect(complete.grossPerRecordedMile == partial.grossPerRecordedMile)
    }

    @Test("A shift recorded as paying nothing has a per-mile rate of zero")
    func mileageRateOfZeroEarnings() throws {
        let metrics = calculator.metrics(
            grossEarnings: .zero,
            elapsedDuration: 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerRecordedMile == .available(.zero))
    }

    @Test("A shift with no amount recorded has no per-mile rate")
    func mileageRateWithoutEarnings() {
        let metrics = calculator.metrics(
            grossEarnings: nil,
            elapsedDuration: 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerRecordedMile == .unavailable(.earningsNotRecorded))
    }

    @Test("A shift with no route recorded has no per-mile rate, not a rate of zero miles")
    func mileageRateWithoutARoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerRecordedMile == .unavailable(.noRouteRecorded))
        #expect(metrics.grossPerRecordedMile.amount == nil)
    }

    @Test("Positions that no continuous stretch joined are reported as unmeasurable, not as no route")
    func mileageRateWithInsufficientSamples() throws {
        let insufficient = RouteDistance(
            metres: 0,
            segmentCount: 0,
            gapCount: 1,
            usableSampleCount: 1,
            usesInferredContinuity: false
        )

        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: insufficient
        )

        #expect(metrics.grossPerRecordedMile == .unavailable(.routeNotMeasurable))
    }

    @Test("A route measured at zero distance is a measurement, distinct from an absent one")
    func mileageRateOfZeroDistance() throws {
        let stationary = RouteDistance(
            metres: 0,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 12,
            usesInferredContinuity: false
        )

        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: stationary
        )

        #expect(metrics.grossPerRecordedMile == .unavailable(.zeroRecordedDistance))
        #expect(
            metrics.grossPerRecordedMile != .unavailable(.noRouteRecorded),
            "Measuring zero miles and recording no route are different facts"
        )
    }

    @Test("A distance that is not a number is refused rather than divided by", arguments: [Double.nan, .infinity, -100])
    func mileageRateOfAMalformedDistance(metres: Double) throws {
        let malformed = RouteDistance(
            metres: metres,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 12,
            usesInferredContinuity: false
        )

        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: malformed
        )

        #expect(metrics.grossPerRecordedMile == .unavailable(.routeNotMeasurable))
    }

    // MARK: Combined state

    @Test("Earnings, elapsed time and a measured route give both rates")
    func bothRatesAvailable() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerElapsedHour == .available(try money("28.75")))
        #expect(metrics.grossPerRecordedMile == .available(try money("8.625")))
        #expect(metrics.hasAnyRate)
        #expect(metrics.isRoutePartial == false)
    }

    @Test("An unmeasurable route leaves the hourly rate intact")
    func hourlyRateSurvivesAnUnmeasurableRoute() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none
        )

        #expect(metrics.grossPerElapsedHour.isAvailable)
        #expect(metrics.grossPerRecordedMile.isAvailable == false)
        #expect(metrics.hasAnyRate)
    }

    @Test("Missing earnings removes both rates, and only for that reason")
    func missingEarningsRemovesBothRates() {
        let metrics = calculator.metrics(
            grossEarnings: nil,
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerElapsedHour == .unavailable(.earningsNotRecorded))
        #expect(metrics.grossPerRecordedMile == .unavailable(.earningsNotRecorded))
        #expect(metrics.hasAnyRate == false)
    }

    @Test("Zero earnings over valid denominators gives two rates of zero")
    func zeroEarningsGivesZeroRates() {
        let metrics = calculator.metrics(
            grossEarnings: .zero,
            elapsedDuration: 3 * 3600,
            recordedDistance: measuredRoute(miles: 10)
        )

        #expect(metrics.grossPerElapsedHour == .available(.zero))
        #expect(metrics.grossPerRecordedMile == .available(.zero))
    }

    @Test("The metrics carry the inputs they were derived from")
    func metricsCarryTheirInputs() throws {
        let route = measuredRoute(miles: 10, gapCount: 1)
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: route
        )

        #expect(metrics.grossEarnings == (try money("86.25")))
        #expect(metrics.elapsedDuration == TimeInterval(3 * 3600))
        #expect(metrics.recordedDistance == route)
    }

    // MARK: Gross earnings per delivery active hour

    /// A delivery active time built from plain values, so a rate test states its
    /// own denominator instead of assembling deliveries to reach one.
    private func activeTime(
        minutes: Double,
        sourceIntervalCount: Int = 1,
        countedIntervalCount: Int = 1,
        mergedIntervalCount: Int = 1
    ) -> DeliveryActiveTime {
        DeliveryActiveTime(
            duration: minutes * 60,
            sourceIntervalCount: sourceIntervalCount,
            countedIntervalCount: countedIntervalCount,
            mergedIntervalCount: mergedIntervalCount,
            unfinishedIntervalCount: 0,
            malformedIntervalCount: 0
        )
    }

    @Test("A completed shift earns a rate over the hours its deliveries were active")
    func activeHourlyRateOfANormalShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 5 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 180)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .available(try money("28.75")))
    }

    @Test("A fractional active hour divides by the fraction, not by a rounded hour")
    func activeHourlyRateOfAFractionalHour() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("37.20"),
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 90)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .available(try money("24.80")))
    }

    /// The interval's central claim, read through the rate: two deliveries
    /// overlapping by twenty minutes give a denominator of forty minutes, not of
    /// the fifty-five their durations sum to, and the rate follows the union.
    @Test("Stacked deliveries change the denominator to their union, not their sum")
    func activeHourlyRateUsesTheUnionedDenominator() throws {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let union = DeliveryActiveTimeCalculator().activeTime(
            of: [
                DeliveryActiveInterval(start: start, end: start.addingTimeInterval(30 * 60)),
                DeliveryActiveInterval(
                    start: start.addingTimeInterval(10 * 60),
                    end: start.addingTimeInterval(40 * 60)
                )
            ]
        )

        let metrics = calculator.metrics(
            grossEarnings: try money("20.00"),
            elapsedDuration: 2 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: union
        )

        #expect(union.duration == 40 * 60)
        #expect(metrics.grossPerDeliveryActiveHour == .available(try money("30.00")))
        #expect(
            metrics.grossPerDeliveryActiveHour != .available(try money("21.818182")),
            "Summing the two durations would divide by 55 minutes and understate the rate"
        )
    }

    @Test("A shift recorded as paying nothing has an active rate of zero, not an absent one")
    func activeHourlyRateOfZeroEarnings() throws {
        let metrics = calculator.metrics(
            grossEarnings: .zero,
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 120)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .available(.zero))
    }

    @Test("A shift with no amount recorded has no active rate, and is not treated as zero")
    func activeHourlyRateWithoutEarnings() {
        let metrics = calculator.metrics(
            grossEarnings: nil,
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 120)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.earningsNotRecorded))
        #expect(metrics.grossPerDeliveryActiveHour.amount == nil)
    }

    @Test("A shift that recorded no deliveries has no active rate, and says so in its own words")
    func activeHourlyRateWithoutDeliveries() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("48.00"),
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: .none
        )

        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.noDeliveriesRecorded))
        #expect(metrics.grossPerElapsedHour == .available(try money("12.00")), "The elapsed rate is unaffected")
    }

    @Test("Deliveries that describe no usable interval are not the same as no deliveries")
    func activeHourlyRateWithUnusableDeliveries() throws {
        let unusable = DeliveryActiveTime(
            duration: 0,
            sourceIntervalCount: 2,
            countedIntervalCount: 0,
            mergedIntervalCount: 0,
            unfinishedIntervalCount: 1,
            malformedIntervalCount: 1
        )

        let metrics = calculator.metrics(
            grossEarnings: try money("48.00"),
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: unusable
        )

        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.deliveryActiveTimeNotMeasurable))
    }

    @Test("Deliveries measured at no length produce no rate rather than an infinite one")
    func activeHourlyRateOfZeroActiveTime() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("48.00"),
            elapsedDuration: 4 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 0)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.zeroDeliveryActiveTime))
        #expect(metrics.grossPerDeliveryActiveHour.amount == nil)
    }

    @Test("A running shift reports no active rate, whatever its deliveries hold")
    func activeHourlyRateOfARunningShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("48.00"),
            elapsedDuration: nil,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 60)
        )

        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.shiftNotCompleted))
    }

    /// Both hourly figures divide the same amount through the same code path, so
    /// a shift whose deliveries covered all of it must report them identically
    /// rather than differ in the last cent.
    @Test("The two hourly rates agree when the deliveries covered the whole shift")
    func hourlyRatesAgreeOverTheSameDenominator() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("103.75"),
            elapsedDuration: 7 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 7 * 60)
        )

        #expect(metrics.grossPerDeliveryActiveHour == metrics.grossPerElapsedHour)
    }

    @Test("Rates are available whenever any denominator is")
    func hasAnyRateCountsTheActiveHourlyRate() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("30.00"),
            elapsedDuration: 0,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 45)
        )

        #expect(metrics.grossPerElapsedHour == .unavailable(.noElapsedTime))
        #expect(metrics.grossPerDeliveryActiveHour == .available(try money("40.00")))
        #expect(metrics.hasAnyRate)
    }

    // MARK: Non-delivery time

    @Test("Non-delivery time is the shift's elapsed time less its delivery active time")
    func nonDeliveryTimeOfANormalShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("86.25"),
            elapsedDuration: 3 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 65)
        )

        #expect(metrics.nonDeliveryDuration == TimeInterval(115 * 60))
    }

    @Test("A shift its deliveries covered entirely has no non-delivery time, rather than none reported")
    func nonDeliveryTimeOfAFullyCoveredShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("40.00"),
            elapsedDuration: 2 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 120)
        )

        #expect(metrics.nonDeliveryDuration == 0)
    }

    @Test("A shift with nothing measurable reports no non-delivery time rather than the whole shift")
    func nonDeliveryTimeWithoutDeliveries() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("40.00"),
            elapsedDuration: 2 * 3600,
            recordedDistance: .none,
            deliveryActiveTime: .none
        )

        #expect(metrics.nonDeliveryDuration == nil)
    }

    @Test("A running shift has no non-delivery time to report")
    func nonDeliveryTimeOfARunningShift() throws {
        let metrics = calculator.metrics(
            grossEarnings: nil,
            elapsedDuration: nil,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 30)
        )

        #expect(metrics.nonDeliveryDuration == nil)
    }

    /// Clipping already makes this unreachable through the shift adapter. It is
    /// asserted anyway, because a negative duration must never reach a driver's
    /// screen whatever a damaged store holds.
    @Test("Non-delivery time never goes negative, whatever the stored data claims")
    func nonDeliveryTimeIsNeverNegative() throws {
        let metrics = calculator.metrics(
            grossEarnings: try money("40.00"),
            elapsedDuration: 30 * 60,
            recordedDistance: .none,
            deliveryActiveTime: activeTime(minutes: 90)
        )

        #expect(metrics.nonDeliveryDuration == 0)
    }
}

/// The adapter from the stored shift to the calculation, and the states a real
/// store can put it in.
@MainActor
@Suite("Shift metrics from the model")
struct ShiftMetricsModelTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    @Test("A completed shift derives its metrics from its own recorded facts")
    func metricsFromACompletedShift() throws {
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(3 * 3600))
        try shift.setGrossEarnings(#require(Money(exact: "86.25")))

        let metrics = shift.metrics(for: shift.recordedDistance())

        #expect(metrics.grossEarnings == Money(exact: "86.25"))
        #expect(metrics.elapsedDuration == TimeInterval(3 * 3600))
        let hourly = try #require(Money(exact: "28.75"))
        #expect(metrics.grossPerElapsedHour == .available(hourly))
        // No route was recorded, so there is nothing to divide miles into.
        #expect(metrics.grossPerRecordedMile == .unavailable(.noRouteRecorded))
    }

    @Test("A running shift reports no finalised metrics")
    func metricsOfARunningShift() throws {
        let shift = Shift(startedAt: start)

        let metrics = shift.metrics(for: shift.recordedDistance())

        #expect(metrics.elapsedDuration == nil)
        #expect(metrics.grossPerElapsedHour == .unavailable(.shiftNotCompleted))
        #expect(metrics.grossPerRecordedMile == .unavailable(.shiftNotCompleted))
    }

    @Test("A shift ended by a backwards device clock covers no time, so it earns no hourly rate")
    func metricsOfABackwardsClockShift() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)

        // The clock moved behind the recorded start; the service clamps the end
        // to the start rather than leaving the driver unable to finish.
        try service.endActiveShift(at: start.addingTimeInterval(-600))
        try service.setGrossEarnings(#require(Money(exact: "40.00")), on: shift)

        #expect(shift.completedDuration == 0)
        let metrics = shift.metrics(for: shift.recordedDistance())
        #expect(metrics.grossPerElapsedHour == .unavailable(.noElapsedTime))
        #expect(metrics.grossPerElapsedHour.amount == nil, "A clamped shift must not produce an infinite rate")
    }

    @Test("A shift whose stored route is measurable earns a per-recorded-mile rate")
    func metricsOfAShiftWithARoute() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(3600))
        context.insert(shift)

        let session = UUID()
        // Two positions 1609.344 m apart: exactly one recorded mile.
        for (index, northMetres) in [0.0, 1609.344].enumerated() {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: start.addingTimeInterval(Double(index) * 60),
                    latitude: 40.0 + northMetres / 111_320.0,
                    longitude: -75.0,
                    horizontalAccuracy: 8,
                    captureSessionID: session
                )
            )
        }
        try shift.setGrossEarnings(#require(Money(exact: "20.00")))

        let metrics = shift.metrics(for: shift.recordedDistance())

        let rate = try #require(metrics.grossPerRecordedMile.amount)
        // The synthetic offsets are built from a rounded metres-per-degree
        // constant and measured on a spherical Earth, so the mile is close
        // rather than exact. What is asserted is that the denominator is the
        // route's own measured mileage and nothing else.
        #expect(SyntheticRoute.isCloseEnough(metrics.recordedDistance.miles, to: 1))
        #expect(rate > (try #require(Money(exact: "19.50"))))
        #expect(rate < (try #require(Money(exact: "20.50"))))
        #expect(metrics.isRoutePartial, "The route covers a minute of a one-hour shift")
    }

    @Test("A malformed stored route leaves the metrics safe rather than nonsensical")
    func metricsOfAMalformedRoute() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(3600))
        context.insert(shift)

        // Rows no capture path can produce, in case a store is damaged or an
        // older build wrote something this one does not expect.
        let session = UUID()
        for (index, coordinate) in [(Double.nan, Double.nan), (0.0, 0.0), (95.0, -75.0)].enumerated() {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: start.addingTimeInterval(Double(index) * 30),
                    latitude: coordinate.0,
                    longitude: coordinate.1,
                    horizontalAccuracy: 8,
                    captureSessionID: session
                )
            )
        }
        try shift.setGrossEarnings(#require(Money(exact: "50.00")))

        let metrics = shift.metrics(for: shift.recordedDistance())

        let hourly = try #require(Money(exact: "50.00"))
        #expect(metrics.grossPerElapsedHour == .available(hourly))
        #expect(metrics.grossPerRecordedMile.amount == nil, "Nothing measurable must not become a rate")
        #expect(metrics.grossPerRecordedMile == .unavailable(.noRouteRecorded))
    }

}
