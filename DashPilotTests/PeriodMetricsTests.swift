import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a calendar period's completed shifts add up to, and — more often — what
/// they deliberately do not.
///
/// Every record is a plain value, so nothing here needs a store or a rendered
/// view. Calendar behaviour itself lives in `ReportingPeriodTests`; these fix the
/// calendar to UTC and concentrate on the aggregation rules.
@Suite("Period metrics")
struct PeriodMetricsTests {
    private let calculator = PeriodMetricsCalculator()
    private let calendar: Calendar
    private let start: Date
    private let day: ReportingPeriod
    private let week: ReportingPeriod

    /// One mile in metres, so a test can state a distance in the unit the
    /// per-mile rate is expressed in.
    private static let metresPerMile = 1609.344

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        // Wednesday, 17 June 2026, midnight UTC.
        start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17)))
        day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        week = try #require(ReportingPeriod(unit: .week, containing: start, calendar: calendar))
    }

    // MARK: Fixtures

    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    /// A route that measured `miles`, partial only when a gap is asked for.
    private func route(miles: Double, gapCount: Int = 0, usesInferredContinuity: Bool = false) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: gapCount,
            usableSampleCount: 40,
            usesInferredContinuity: usesInferredContinuity
        )
    }

    /// A route that measured nothing: positions exist, but no two of them were
    /// captured continuously.
    private func unmeasurableRoute(usableSampleCount: Int = 3) -> RouteDistance {
        RouteDistance(
            metres: 0,
            segmentCount: 0,
            gapCount: 1,
            usableSampleCount: usableSampleCount,
            usesInferredContinuity: false
        )
    }

    /// A measurable delivery active time of `duration`.
    private func activeTime(
        _ duration: TimeInterval,
        counted: Int = 1,
        merged: Int = 1
    ) -> DeliveryActiveTime {
        DeliveryActiveTime(
            duration: duration,
            sourceIntervalCount: counted,
            countedIntervalCount: counted,
            mergedIntervalCount: merged,
            unfinishedIntervalCount: 0,
            malformedIntervalCount: 0
        )
    }

    /// Deliveries recorded but describing no usable interval — measurable is
    /// exactly what this is not.
    private func unmeasurableActiveTime(sources: Int = 2) -> DeliveryActiveTime {
        DeliveryActiveTime(
            duration: 0,
            sourceIntervalCount: sources,
            countedIntervalCount: 0,
            mergedIntervalCount: 0,
            unfinishedIntervalCount: sources,
            malformedIntervalCount: 0
        )
    }

    private func record(
        startedAt: Date? = nil,
        isCompleted: Bool = true,
        elapsed: TimeInterval? = 3 * 3600,
        earnings: Money? = nil,
        route recordedDistance: RouteDistance = .none,
        active: DeliveryActiveTime = .none,
        deliveries: DeliverySummary = DeliverySummary(completed: 0, cancelled: 0),
        waits: [PickupWaitSample] = [],
        places: Set<UUID> = [],
        deliveryEarnings: [Money] = [],
        terminalDeliveries: Int = 0
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: startedAt ?? at(9),
            isCompleted: isCompleted,
            elapsedDuration: elapsed,
            grossEarnings: earnings,
            recordedDistance: recordedDistance,
            deliveryActiveTime: active,
            deliverySummary: deliveries,
            pickupWaits: waits,
            pickupPlaceIDs: places,
            recordedDeliveryEarnings: deliveryEarnings,
            terminalDeliveryCount: terminalDeliveries
        )
    }

    private func wait(minutes: Double, at hours: Double = 10) -> PickupWaitSample {
        PickupWaitSample(duration: minutes * 60, pickedUpAt: at(hours))
    }

    // MARK: Which shifts count

    @Test("A period with no completed shift has no figures at all, not zeroes")
    func emptyPeriodInventsNothing() {
        let metrics = calculator.metrics(of: [], in: day)

        #expect(metrics.isEmpty)
        #expect(metrics.completedShiftCount == 0)
        #expect(metrics.recordedGrossEarnings == nil)
        #expect(metrics.elapsedDuration == nil)
        #expect(metrics.deliveryActiveDuration == nil)
        #expect(metrics.nonDeliveryDuration == nil)
        #expect(metrics.medianPickupWait == nil)
        #expect(!metrics.recordedDistance.isMeasured)
        #expect(metrics.deliverySummary.recorded == 0)
        for kind in PeriodRateKind.allCases {
            #expect(!metrics.rate(kind).isAvailable)
        }
    }

    /// A running shift's elapsed time is still growing and its amount is not
    /// final. Including it would make a historical total change every second.
    @Test("A running shift never enters a historical period total")
    func runningShiftIsExcluded() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("40.00"), active: activeTime(3600)),
                record(isCompleted: false, elapsed: nil, earnings: nil)
            ],
            in: day
        )

        #expect(metrics.completedShiftCount == 1)
        #expect(metrics.recordedGrossEarnings == (try money("40.00")))
        #expect(metrics.earningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 1))
    }

    @Test("A shift that started in a neighbouring day is not in this day")
    func neighbouringDaysAreExcluded() throws {
        let metrics = calculator.metrics(
            of: [
                record(startedAt: at(9), earnings: try money("40.00")),
                record(startedAt: at(-3), earnings: try money("999.00")),
                record(startedAt: at(26), earnings: try money("999.00"))
            ],
            in: day
        )

        #expect(metrics.completedShiftCount == 1)
        #expect(metrics.recordedGrossEarnings == (try money("40.00")))
    }

    @Test("A shift crossing midnight is counted whole, in the day it started")
    func crossMidnightShiftIsCountedWhole() throws {
        // Starts at 22:00 and runs four hours into the next day.
        let overnight = record(startedAt: at(22), elapsed: 4 * 3600, earnings: try money("60.00"))

        let started = calculator.metrics(of: [overnight], in: day)
        let nextDay = try #require(day.next(using: calendar))
        let finished = calculator.metrics(of: [overnight], in: nextDay)

        #expect(started.completedShiftCount == 1)
        #expect(started.elapsedDuration == 4 * 3600.0, "Nothing is cut off at midnight")
        #expect(started.recordedGrossEarnings == (try money("60.00")))
        #expect(finished.isEmpty, "And nothing is counted a second time in the day it ended")
    }

    @Test("A week gathers the shifts of its days")
    func weekGathersItsDays() throws {
        let metrics = calculator.metrics(
            of: [
                record(startedAt: at(9), earnings: try money("40.00")),
                record(startedAt: at(33), earnings: try money("50.00")),
                record(startedAt: at(-20), earnings: try money("60.00")),
                record(startedAt: at(24 * 9), earnings: try money("999.00"))
            ],
            in: week
        )

        #expect(metrics.completedShiftCount == 3)
        #expect(metrics.recordedGrossEarnings == (try money("150.00")))
    }

    // MARK: Earnings

    @Test("One shift's amount is the period's subtotal, complete")
    func oneShiftIsItsOwnSubtotal() throws {
        let metrics = calculator.metrics(of: [record(earnings: try money("86.25"))], in: day)

        #expect(metrics.recordedGrossEarnings == (try money("86.25")))
        #expect(metrics.earningsCoverage.isComplete)
    }

    @Test("Several amounts add up exactly, with no binary floating point")
    func amountsAddUpExactly() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("0.10")),
                record(earnings: try money("0.20")),
                record(earnings: try money("86.25"))
            ],
            in: day
        )

        // The pair that a Double would total to 0.30000000000000004.
        #expect(metrics.recordedGrossEarnings == (try money("86.55")))
    }

    /// The rule the whole result type exists for.
    @Test("A shift with no amount is left out of the total but counted in coverage")
    func missingAmountIsExcludedAndCounted() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("120.00")),
                record(earnings: try money("164.50")),
                record(earnings: nil),
                record(earnings: nil)
            ],
            in: day
        )

        #expect(metrics.recordedGrossEarnings == (try money("284.50")))
        #expect(metrics.earningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 4))
        #expect(!metrics.earningsCoverage.isComplete)
        #expect(metrics.earningsCoverageStatement == "2 of 4 shifts")
    }

    @Test("A missing amount is never read as zero")
    func missingAmountIsNotZero() throws {
        let withMissing = calculator.metrics(
            of: [record(earnings: try money("100.00")), record(earnings: nil)],
            in: day
        )
        let withZero = calculator.metrics(
            of: [record(earnings: try money("100.00")), record(earnings: .zero)],
            in: day
        )

        #expect(withMissing.recordedGrossEarnings == withZero.recordedGrossEarnings)
        #expect(
            withMissing.earningsCoverage != withZero.earningsCoverage,
            "The amounts match; what differs is how many shifts answered"
        )
        #expect(withZero.earningsCoverage.isComplete)
        #expect(!withMissing.earningsCoverage.isComplete)
    }

    @Test("An explicit zero counts as a recorded amount")
    func explicitZeroIsRecorded() throws {
        let metrics = calculator.metrics(of: [record(earnings: .zero)], in: day)

        #expect(metrics.recordedGrossEarnings == Money.zero)
        #expect(metrics.earningsCoverage.isComplete)
        #expect(metrics.earningsStatement(locale: Locale(identifier: "en_US")) == "$0.00 recorded")
    }

    @Test("A period where nobody recorded an amount has no total")
    func noRecordedAmountsMeansNoTotal() {
        let metrics = calculator.metrics(of: [record(earnings: nil), record(earnings: nil)], in: day)

        #expect(metrics.recordedGrossEarnings == nil)
        #expect(metrics.earningsStatement() == nil)
        #expect(metrics.earningsCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 2))
    }

    // MARK: The earnings source

    /// The period's headline is the **shift** amount. Delivery amounts are
    /// optional and routinely absent, so summing them here would read every
    /// unrecorded delivery as one that paid nothing.
    @Test("Amounts recorded against deliveries never enter the headline total")
    func deliveryAmountsStayOutOfTheHeadline() throws {
        let metrics = calculator.metrics(
            of: [
                record(
                    earnings: try money("86.25"),
                    deliveryEarnings: [try money("14.75"), try money("9.50")],
                    terminalDeliveries: 3
                )
            ],
            in: day
        )

        #expect(metrics.recordedGrossEarnings == (try money("86.25")))
        #expect(metrics.recordedDeliveryEarnings == (try money("24.25")))
        #expect(metrics.recordedGrossEarnings != metrics.recordedDeliveryEarnings)
    }

    @Test("The period total does not move when delivery amounts change")
    func headlineIsUnaffectedByDeliveryAmounts() throws {
        let base = calculator.metrics(
            of: [record(earnings: try money("86.25"), terminalDeliveries: 3)],
            in: day
        )
        let withDeliveryAmounts = calculator.metrics(
            of: [
                record(
                    earnings: try money("86.25"),
                    deliveryEarnings: [try money("40.00"), try money("40.00"), try money("40.00")],
                    terminalDeliveries: 3
                )
            ],
            in: day
        )

        #expect(base.recordedGrossEarnings == withDeliveryAmounts.recordedGrossEarnings)
        #expect(base.grossPerElapsedHour == withDeliveryAmounts.grossPerElapsedHour)
    }

    /// A missing shift amount is *not* quietly replaced by the delivery amounts
    /// recorded inside that shift.
    @Test("Delivery amounts are not a fallback for a missing shift amount")
    func deliveryAmountsAreNotAFallback() throws {
        let metrics = calculator.metrics(
            of: [record(earnings: nil, deliveryEarnings: [try money("22.00")], terminalDeliveries: 2)],
            in: day
        )

        #expect(metrics.recordedGrossEarnings == nil)
        #expect(metrics.recordedDeliveryEarnings == (try money("22.00")))
        #expect(!metrics.grossPerElapsedHour.isAvailable)
    }

    @Test("The delivery subtotal states how many deliveries answered")
    func deliverySubtotalStatesItsCoverage() throws {
        let metrics = calculator.metrics(
            of: [
                record(deliveryEarnings: [try money("14.75"), try money("9.50")], terminalDeliveries: 2),
                record(deliveryEarnings: [], terminalDeliveries: 1)
            ],
            in: day
        )

        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 3))
        let statement = try #require(metrics.deliveryEarningsStatement(locale: Locale(identifier: "en_US")))
        #expect(statement == "$24.25 recorded across 2 of 3 deliveries")
    }

    /// The difference between a shift total and its deliveries is ordinary —
    /// bonuses, adjustments, stacked payouts, unrecorded deliveries — so nothing
    /// computes or presents it.
    @Test("Nothing derives a shortfall between the two subtotals")
    func noShortfallIsDerived() throws {
        let metrics = calculator.metrics(
            of: [
                record(
                    earnings: try money("86.25"),
                    deliveryEarnings: [try money("14.75")],
                    terminalDeliveries: 3
                )
            ],
            in: day
        )

        let spoken = try #require(metrics.spokenDeliveryEarningsStatement(locale: Locale(identifier: "en_US")))
        #expect(spoken.contains("separate record"))
        for claim in ["missing", "shortfall", "unaccounted", "$71.50"] {
            #expect(!spoken.contains(claim), "A difference is not a discrepancy: \(spoken)")
        }
    }

    // MARK: Elapsed time

    @Test("Elapsed time is the sum of the completed shifts' own durations")
    func elapsedTimeSums() {
        let metrics = calculator.metrics(
            of: [record(elapsed: 3 * 3600), record(elapsed: 4.5 * 3600)],
            in: day
        )

        #expect(metrics.elapsedDuration == 7.5 * 3600.0)
        #expect(metrics.elapsedCoverage.isComplete)
    }

    /// A stored row the app cannot have written is excluded rather than turned
    /// into a shift of no length, which would drag every rate derived from it.
    @Test("A completed shift with no usable duration is excluded and counted")
    func malformedDurationIsExcluded() {
        let metrics = calculator.metrics(
            of: [record(elapsed: 3 * 3600), record(elapsed: nil), record(elapsed: -60)],
            in: day
        )

        #expect(metrics.elapsedDuration == 3 * 3600.0)
        #expect(metrics.elapsedCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
    }

    // MARK: Delivery active time

    @Test("Delivery active time sums the per-shift unions")
    func activeTimeSumsPerShiftUnions() {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 3 * 3600, active: activeTime(65 * 60, counted: 3, merged: 2)),
                record(elapsed: 2 * 3600, active: activeTime(40 * 60))
            ],
            in: day
        )

        #expect(metrics.deliveryActiveDuration == 105 * 60.0)
        #expect(metrics.deliveryActiveCoverage.isComplete)
    }

    /// The union already happened per shift. A stacked pair contributes its
    /// overlap once, and the period simply adds the shift's answer.
    @Test("Stacked deliveries are not double-counted at period level")
    func stackingIsNotDoubleCounted() {
        // 65 minutes of union where the deliveries' own durations sum to 75.
        let stacked = record(elapsed: 3 * 3600, active: activeTime(65 * 60, counted: 3, merged: 2))

        let metrics = calculator.metrics(of: [stacked], in: day)

        #expect(metrics.deliveryActiveDuration == 65 * 60.0)
        #expect(metrics.deliveryActiveDuration != 75 * 60.0)
    }

    @Test("A shift with no deliveries contributes no active time and is counted")
    func shiftWithoutDeliveriesIsCounted() {
        let metrics = calculator.metrics(
            of: [record(active: activeTime(30 * 60)), record(active: .none)],
            in: day
        )

        #expect(metrics.deliveryActiveDuration == 30 * 60.0)
        #expect(metrics.deliveryActiveCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    @Test("Deliveries that describe no usable interval leave active time unmeasured")
    func unmeasurableActiveTimeIsExcluded() {
        let metrics = calculator.metrics(
            of: [record(active: unmeasurableActiveTime()), record(active: unmeasurableActiveTime())],
            in: day
        )

        #expect(metrics.deliveryActiveDuration == nil, "Unmeasurable is not a duration of zero")
        #expect(metrics.deliveryActiveCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 2))
    }

    // MARK: Non-delivery time

    /// Summed per shift rather than derived from two period totals, which can
    /// come from different sets of shifts.
    @Test("Non-delivery time is derived per shift and then summed")
    func nonDeliveryTimeIsSummedPerShift() {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 3 * 3600, active: activeTime(65 * 60)),
                record(elapsed: 2 * 3600, active: activeTime(40 * 60))
            ],
            in: day
        )

        // (180 − 65) + (120 − 40) minutes.
        #expect(metrics.nonDeliveryDuration == 195 * 60.0)
        #expect(metrics.nonDeliveryCoverage.isComplete)
    }

    /// The mismatch this rule exists to prevent: the shift with no measurable
    /// active time contributes elapsed but no non-delivery time, so subtracting
    /// the two period totals would produce a figure belonging to neither.
    @Test("Non-delivery time is not the difference of two period totals")
    func nonDeliveryTimeIsNotADifferenceOfTotals() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 3 * 3600, active: activeTime(60 * 60)),
                record(elapsed: 5 * 3600, active: .none)
            ],
            in: day
        )

        let elapsed = try #require(metrics.elapsedDuration)
        let active = try #require(metrics.deliveryActiveDuration)
        #expect(metrics.nonDeliveryDuration == 2 * 3600.0)
        #expect(metrics.nonDeliveryDuration != elapsed - active, "That difference would be 7 hours")
        #expect(metrics.nonDeliveryCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    @Test("Non-delivery time is never negative")
    func nonDeliveryTimeIsNeverNegative() throws {
        // Anomalous: more active time than the shift it happened in.
        let metrics = calculator.metrics(
            of: [record(elapsed: 3600, active: activeTime(2 * 3600))],
            in: day
        )

        #expect(try #require(metrics.nonDeliveryDuration) >= 0)
    }

    // MARK: Mileage

    @Test("Recorded mileage sums the routes that measured something")
    func mileageSumsMeasuredRoutes() throws {
        let metrics = calculator.metrics(
            of: [record(route: route(miles: 12.5)), record(route: route(miles: 30.1))],
            in: day
        )

        #expect(abs(metrics.recordedDistance.miles - 42.6) < 0.000_01)
        #expect(metrics.routeCoverage.measuredShiftCount == 2)
        #expect(metrics.routeCoverage.unmeasurableShiftCount == 0)
    }

    @Test("A shift with no route contributes nothing and is counted as unmeasured")
    func shiftWithoutARouteIsCounted() throws {
        let metrics = calculator.metrics(
            of: [record(route: route(miles: 10)), record(route: .none), record(route: unmeasurableRoute())],
            in: day
        )

        #expect(abs(metrics.recordedDistance.miles - 10) < 0.000_01)
        #expect(metrics.routeCoverage.measuredShiftCount == 1)
        #expect(metrics.routeCoverage.unmeasurableShiftCount == 2)
        #expect(metrics.routeCoverage.totalShiftCount == 3)
    }

    /// A partial route's distance is factual, so it stays in the total. What it
    /// is not allowed to do is disappear: the count of partial routes is what
    /// makes the total readable as a floor.
    @Test("A partial route contributes its distance and is counted as partial")
    func partialRoutesContributeAndAreCounted() throws {
        let metrics = calculator.metrics(
            of: [
                record(route: route(miles: 20, gapCount: 2)),
                record(route: route(miles: 15, gapCount: 1)),
                record(route: route(miles: 7.6))
            ],
            in: day
        )

        #expect(abs(metrics.recordedDistance.miles - 42.6) < 0.000_01)
        #expect(metrics.routeCoverage.partialShiftCount == 2)
        #expect(metrics.mileageCoverageStatement == "3 of 3 shifts measured · 2 partial")
    }

    @Test("A route from before capture continuity was recorded counts as partial")
    func legacyRouteIsPartial() {
        let metrics = calculator.metrics(
            of: [record(route: route(miles: 10, usesInferredContinuity: true))],
            in: day
        )

        #expect(metrics.routeCoverage.partialShiftCount == 1)
    }

    /// A shift whose route measured nothing is missing entirely, which the
    /// unmeasured count states; calling it *partial* would understate it.
    @Test("An unmeasurable route is not counted as a partial one")
    func unmeasurableRouteIsNotPartial() {
        let metrics = calculator.metrics(of: [record(route: unmeasurableRoute())], in: day)

        #expect(metrics.routeCoverage.partialShiftCount == 0)
        #expect(metrics.routeCoverage.unmeasurableShiftCount == 1)
    }

    @Test("A period whose routes measured nothing says so rather than showing zero miles")
    func unmeasuredPeriodSaysSo() {
        let metrics = calculator.metrics(of: [record(route: .none)], in: day)

        #expect(metrics.mileageStatement() == "No route measured")
        #expect(!metrics.recordedDistance.isMeasured)
    }

    /// The word that keeps the figure honest, in the visible text rather than
    /// only in the documentation.
    @Test("Period mileage is called recorded, never a driven total")
    func mileageIsCalledRecorded() {
        let metrics = calculator.metrics(of: [record(route: route(miles: 42.6, gapCount: 2))], in: day)

        let statement = metrics.mileageStatement(locale: Locale(identifier: "en_US"))
        #expect(statement.contains("recorded"))
        for claim in ["driven", "total mileage", "distance travelled"] {
            #expect(!statement.lowercased().contains(claim), "Showed: \(statement)")
        }
        #expect(metrics.mileagePartialExplanation?.contains("more miles were driven") == true)
    }

    // MARK: Rates — aggregate, never a mean of rates

    /// The fixture is built so the wrong answer is obviously wrong: two shifts
    /// paying the same amount over one hour and nine hours are $100/hr and
    /// $11.11/hr, whose mean is $55.56. The period earned $200 over 10 hours.
    @Test("The elapsed-hour rate is aggregate over aggregate, not a mean of shift rates")
    func elapsedHourRateIsNotAMeanOfRates() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 3600, earnings: try money("100.00")),
                record(elapsed: 9 * 3600, earnings: try money("100.00"))
            ],
            in: day
        )

        #expect(metrics.grossPerElapsedHour.amount == (try money("20.00")))
        #expect(metrics.grossPerElapsedHour.amount != (try money("55.56")), "The mean of the two shift rates")
        #expect(metrics.grossPerElapsedHour.coverage.isComplete)
    }

    @Test("The active-hour rate is aggregate over aggregate, not a mean of shift rates")
    func activeHourRateIsNotAMeanOfRates() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 4 * 3600, earnings: try money("60.00"), active: activeTime(3600)),
                record(elapsed: 6 * 3600, earnings: try money("60.00"), active: activeTime(3 * 3600))
            ],
            in: day
        )

        // $120 over 4 active hours, not the mean of $60/hr and $20/hr.
        #expect(metrics.grossPerDeliveryActiveHour.amount == (try money("30.00")))
        #expect(metrics.grossPerDeliveryActiveHour.amount != (try money("40.00")))
    }

    @Test("The per-mile rate is aggregate over aggregate, not a mean of shift rates")
    func perMileRateIsNotAMeanOfRates() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("100.00"), route: route(miles: 10)),
                record(earnings: try money("20.00"), route: route(miles: 40))
            ],
            in: day
        )

        // $120 over 50 recorded miles, not the mean of $10.00 and $0.50.
        #expect(metrics.grossPerRecordedMile.amount == (try money("2.40")))
        #expect(metrics.grossPerRecordedMile.amount != (try money("5.25")))
    }

    // MARK: Rates — the paired subset

    @Test("The elapsed-hour rate uses only shifts with both an amount and elapsed time")
    func elapsedHourRateUsesThePairedSubset() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 2 * 3600, earnings: try money("50.00")),
                record(elapsed: 8 * 3600, earnings: nil),
                record(elapsed: nil, earnings: try money("70.00"))
            ],
            in: day
        )

        #expect(metrics.grossPerElapsedHour.amount == (try money("25.00")))
        #expect(metrics.grossPerElapsedHour.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
    }

    @Test("The active-hour rate uses only shifts with both an amount and active time")
    func activeHourRateUsesThePairedSubset() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("45.00"), active: activeTime(90 * 60)),
                record(earnings: try money("99.00"), active: unmeasurableActiveTime()),
                record(earnings: nil, active: activeTime(5 * 3600))
            ],
            in: day
        )

        #expect(metrics.grossPerDeliveryActiveHour.amount == (try money("30.00")))
        #expect(
            metrics.grossPerDeliveryActiveHour.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3)
        )
    }

    @Test("The per-mile rate uses only shifts with both an amount and a measurable route")
    func perMileRateUsesThePairedSubset() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("50.00"), route: route(miles: 10)),
                record(earnings: try money("30.00"), route: unmeasurableRoute()),
                record(earnings: nil, route: route(miles: 20))
            ],
            in: day
        )

        #expect(metrics.grossPerRecordedMile.amount == (try money("5.00")))
        #expect(metrics.grossPerRecordedMile.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
    }

    /// The failure this pairing prevents: an amount from an unmeasured shift
    /// landing on another shift's mileage denominator.
    @Test("An amount without a denominator never joins another shift's denominator")
    func numeratorNeverBorrowsAnotherShiftsDenominator() throws {
        let paired = calculator.metrics(
            of: [record(earnings: try money("50.00"), route: route(miles: 10))],
            in: day
        )
        let withUnmeasuredExtra = calculator.metrics(
            of: [
                record(earnings: try money("50.00"), route: route(miles: 10)),
                record(earnings: try money("500.00"), route: .none)
            ],
            in: day
        )

        #expect(paired.grossPerRecordedMile.amount == withUnmeasuredExtra.grossPerRecordedMile.amount)
        #expect(withUnmeasuredExtra.grossPerRecordedMile.coverage.contributingCount == 1)
    }

    @Test("A recorded zero is a valid numerator over a real denominator")
    func explicitZeroIsAValidNumerator() throws {
        let alone = calculator.metrics(of: [record(elapsed: 2 * 3600, earnings: .zero)], in: day)
        let mixed = calculator.metrics(
            of: [record(elapsed: 2 * 3600, earnings: .zero), record(elapsed: 2 * 3600, earnings: try money("50.00"))],
            in: day
        )

        #expect(alone.grossPerElapsedHour.amount == Money.zero)
        #expect(alone.grossPerElapsedHour.coverage.isComplete)
        #expect(mixed.grossPerElapsedHour.amount == (try money("12.50")), "$50 over 4 hours")
    }

    /// A zero denominator takes its shift out of the rate entirely — including
    /// its amount, which must not land on another shift's hours.
    @Test("A zero denominator excludes its shift's amount as well")
    func zeroDenominatorExcludesItsNumerator() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 0, earnings: try money("50.00")),
                record(elapsed: 2 * 3600, earnings: try money("30.00"))
            ],
            in: day
        )

        #expect(metrics.grossPerElapsedHour.amount == (try money("15.00")), "$30 over 2 hours, not $80")
        #expect(metrics.grossPerElapsedHour.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    @Test("A zero recorded distance excludes its shift from the per-mile rate")
    func zeroDistanceExcludesItsNumerator() throws {
        let zeroDistance = RouteDistance(
            metres: 0,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 12,
            usesInferredContinuity: false
        )

        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("50.00"), route: zeroDistance),
                record(earnings: try money("30.00"), route: route(miles: 10))
            ],
            in: day
        )

        #expect(metrics.grossPerRecordedMile.amount == (try money("3.00")))
        #expect(metrics.grossPerRecordedMile.coverage.contributingCount == 1)
    }

    @Test("A rate no shift can support is absent, with its coverage at zero")
    func unsupportedRateIsAbsent() throws {
        let metrics = calculator.metrics(
            of: [record(earnings: nil, route: route(miles: 10)), record(earnings: nil, route: route(miles: 5))],
            in: day
        )

        #expect(metrics.grossPerRecordedMile.amount == nil)
        #expect(metrics.rateStatement(.perRecordedMile) == nil)
        #expect(metrics.grossPerRecordedMile.coverage == MetricCoverage(contributingCount: 0, eligibleCount: 2))
    }

    @Test("Every rate states the subset it was worked out from")
    func ratesStateTheirBasis() throws {
        let metrics = calculator.metrics(
            of: [
                record(elapsed: 2 * 3600, earnings: try money("50.00"), route: route(miles: 10), active: activeTime(3600)),
                record(elapsed: 2 * 3600, earnings: nil, route: route(miles: 10), active: activeTime(3600))
            ],
            in: day
        )

        #expect(
            metrics.rateBasisStatement(.perRecordedMile)
                == "Based on 1 of 2 shifts with both earnings and a measurable route"
        )
        #expect(metrics.rateBasisStatement(.perElapsedHour).contains("1 of 2"))
        #expect(metrics.rateBasisStatement(.perDeliveryActiveHour).contains("1 of 2"))
    }

    /// One shift's rate and the period's rate over that same shift must agree to
    /// the cent — they go through the same division.
    @Test("A single-shift period agrees with that shift's own rate")
    func singleShiftPeriodAgreesWithTheShiftRate() throws {
        let earnings = try money("86.25")
        let distance = route(miles: 12.5)
        let shiftMetrics = ShiftMetricsCalculator().metrics(
            grossEarnings: earnings,
            elapsedDuration: 3 * 3600,
            recordedDistance: distance,
            deliveryActiveTime: activeTime(65 * 60)
        )
        let periodMetrics = calculator.metrics(
            of: [record(elapsed: 3 * 3600, earnings: earnings, route: distance, active: activeTime(65 * 60))],
            in: day
        )

        #expect(periodMetrics.grossPerElapsedHour.amount == shiftMetrics.grossPerElapsedHour.amount)
        #expect(periodMetrics.grossPerDeliveryActiveHour.amount == shiftMetrics.grossPerDeliveryActiveHour.amount)
        #expect(periodMetrics.grossPerRecordedMile.amount == shiftMetrics.grossPerRecordedMile.amount)
    }

    // MARK: Pickup wait

    /// The median is over every recorded wait in the period. A median of each
    /// place's median would weight a place visited once the same as one visited
    /// five times.
    @Test("The period median is taken over individual samples, not over place medians")
    func medianIsOverIndividualSamples() {
        let metrics = calculator.metrics(
            of: [
                record(waits: (0..<5).map { _ in wait(minutes: 10) }),
                record(waits: [wait(minutes: 40)])
            ],
            in: day
        )

        #expect(metrics.medianPickupWait == 10 * 60.0)
        #expect(metrics.medianPickupWait != 25 * 60.0, "The median of the two places' medians")
        #expect(metrics.pickupWaitSampleCount == 6)
    }

    @Test("A long wait stays in the samples rather than being trimmed")
    func longWaitsAreRetained() {
        let metrics = calculator.metrics(
            of: [record(waits: [wait(minutes: 6), wait(minutes: 11), wait(minutes: 41)])],
            in: day
        )

        #expect(metrics.medianPickupWait == 11 * 60.0)
        #expect(metrics.pickupWaitSampleCount == 3)
    }

    @Test("A period with no recorded wait has no median")
    func noWaitsMeansNoMedian() {
        let metrics = calculator.metrics(of: [record(waits: [])], in: day)

        #expect(metrics.medianPickupWait == nil)
        #expect(metrics.pickupWaitSampleCount == 0)
        #expect(metrics.pickupWaitStatement == nil)
        #expect(metrics.pickupWaitBasisStatement == "No recorded pickup waits")
    }

    @Test("The wait figure is described as recorded and never as a prediction")
    func waitWordingClaimsNothingAboutTheFuture() {
        let metrics = calculator.metrics(
            of: [record(waits: [wait(minutes: 8), wait(minutes: 10)])],
            in: day
        )

        let spoken = metrics.spokenPickupWaitStatement.lowercased()
        #expect(spoken.contains("median recorded pickup wait"))
        for claim in ["expect", "predict", "typical", "usually", "will "] {
            #expect(!spoken.contains(claim), "Showed: \(spoken)")
        }
    }

    @Test("Pickup places are counted once across the period")
    func pickupPlacesAreCountedOnce() {
        let shared = UUID()
        let other = UUID()

        let metrics = calculator.metrics(
            of: [record(places: [shared, other]), record(places: [shared])],
            in: day
        )

        #expect(metrics.pickupPlaceCount == 2)
        #expect(metrics.pickupPlaceStatement == "2 pickup places recorded")
    }

    // MARK: Delivery counts

    @Test("Delivered and cancelled deliveries are counted separately")
    func deliveryOutcomesAreCountedSeparately() {
        let metrics = calculator.metrics(
            of: [
                record(deliveries: DeliverySummary(completed: 4, cancelled: 1)),
                record(deliveries: DeliverySummary(completed: 3, cancelled: 0))
            ],
            in: day
        )

        #expect(metrics.deliverySummary.completed == 7)
        #expect(metrics.deliverySummary.cancelled == 1)
        #expect(metrics.deliverySummary.recorded == 8)
    }

    /// Unreachable through the app — a shift cannot end while a delivery runs —
    /// but a store holding such a row must show it rather than have it silently
    /// counted as completed.
    @Test("An unfinished delivery on a completed shift is not counted as completed")
    func unfinishedDeliveryIsNotCompleted() {
        let metrics = calculator.metrics(
            of: [record(deliveries: DeliverySummary(completed: 2, cancelled: 1, inProgress: 1))],
            in: day
        )

        #expect(metrics.deliverySummary.completed == 2)
        #expect(metrics.deliverySummary.inProgress == 1)
        #expect(metrics.deliverySummary.recorded == 4)
    }

    // MARK: Wording

    @Test("A period with no completed shift says so instead of showing zeroes")
    func emptyPeriodStatesItself() {
        let dayMetrics = calculator.metrics(of: [], in: day)
        let weekMetrics = calculator.metrics(of: [], in: week)

        #expect(dayMetrics.emptyStatement == "No completed shifts recorded on this day.")
        #expect(weekMetrics.emptyStatement == "No completed shifts recorded this week.")
    }

    @Test("The spoken earnings sentence carries its own denominator")
    func spokenEarningsCarryTheirDenominator() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("120.00")),
                record(earnings: try money("164.50")),
                record(earnings: nil),
                record(earnings: nil)
            ],
            in: day
        )

        #expect(
            metrics.spokenEarningsStatement(locale: Locale(identifier: "en_US"))
                == "Recorded gross earnings, $284.50, across 2 of 4 completed shifts."
        )
    }

    @Test("The spoken mileage sentence carries its coverage and its partiality")
    func spokenMileageCarriesItsCoverage() {
        let metrics = calculator.metrics(
            of: [
                record(route: route(miles: 20, gapCount: 2)),
                record(route: route(miles: 22.6, gapCount: 1)),
                record(route: .none)
            ],
            in: day
        )

        let spoken = metrics.spokenMileageStatement(locale: Locale(identifier: "en_US"))
        #expect(spoken.contains("Recorded mileage, 42.6 miles"))
        #expect(spoken.contains("across 2 of 3 completed shifts"))
        #expect(spoken.contains("2 with partial route capture"))
    }

    @Test("The spoken rate sentence names its numerator and its subset")
    func spokenRateNamesItsBasis() throws {
        let metrics = calculator.metrics(
            of: [
                record(earnings: try money("50.00"), route: route(miles: 10)),
                record(earnings: nil, route: route(miles: 10))
            ],
            in: day
        )

        let spoken = metrics.spokenRateStatement(.perRecordedMile, locale: Locale(identifier: "en_US"))
        #expect(spoken.contains("gross earnings per recorded mile"))
        #expect(spoken.contains("1 of 2 shifts with both earnings and a measurable route"))
        #expect(!spoken.lowercased().contains("per mile driven"))
    }

    @Test("An absent rate is spoken as an absence, never as zero")
    func absentRateIsSpokenAsAnAbsence() {
        let metrics = calculator.metrics(of: [record(earnings: nil)], in: day)

        for kind in PeriodRateKind.allCases {
            let spoken = metrics.spokenRateStatement(kind)
            #expect(spoken.hasPrefix("No "))
            #expect(!spoken.contains("$0.00"))
        }
    }

    @Test("The shift count is stated with the right noun")
    func shiftCountIsStated() {
        #expect(calculator.metrics(of: [record()], in: day).shiftCountStatement == "1 completed shift")
        #expect(calculator.metrics(of: [record(), record()], in: day).shiftCountStatement == "2 completed shifts")
    }
}

/// Reading a stored shift into the value the aggregation works over.
@Suite("Period shift records")
@MainActor
struct PeriodShiftRecordTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    @Test("A completed shift's record carries its own recorded facts")
    func recordCarriesTheShiftsFacts() throws {
        let context = ModelContext(try container())
        let shift = Shift(startedAt: start)
        try shift.end(at: at(180))
        try shift.setGrossEarnings(Money(minorUnits: 8625))
        context.insert(shift)

        let delivered = Delivery(shift: shift, acceptedAt: at(5))
        try delivered.markArrivedAtPickup(at: at(10))
        try delivered.markPickedUp(at: at(21))
        try delivered.markDelivered(at: at(30))
        try delivered.setGrossEarnings(Money(minorUnits: 1475))
        context.insert(delivered)

        let cancelled = Delivery(shift: shift, acceptedAt: at(40))
        try cancelled.markArrivedAtPickup(at: at(45))
        try cancelled.cancel(at: at(60))
        context.insert(cancelled)

        let record = shift.periodRecord(for: .none)

        #expect(record.startedAt == start)
        #expect(record.isCompleted)
        #expect(record.elapsedDuration == 180 * 60.0)
        #expect(record.grossEarnings == Money(minorUnits: 8625))
        #expect(record.deliverySummary.completed == 1)
        #expect(record.deliverySummary.cancelled == 1)
        #expect(record.terminalDeliveryCount == 2)
        #expect(record.recordedDeliveryEarnings == [Money(minorUnits: 1475)])
        #expect(record.pickupWaits.count == 1, "Only the delivery that recorded both ends of a wait")
        #expect(record.pickupWaits.first?.duration == 11 * 60.0)
    }

    @Test("A running shift's record says so, and carries no elapsed duration")
    func runningShiftRecordIsIncomplete() throws {
        let context = ModelContext(try container())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let record = shift.periodRecord(for: .none)

        #expect(!record.isCompleted)
        #expect(record.elapsedDuration == nil)
    }

    @Test("Distinct pickup places are read from the shift's deliveries")
    func recordReadsDistinctPickupPlaces() throws {
        let context = ModelContext(try container())
        let shift = Shift(startedAt: start)
        try shift.end(at: at(180))
        context.insert(shift)

        let noodles = PickupPlace(name: try PickupPlaceName("Nowhere Noodles"), createdAt: start)
        let diner = PickupPlace(name: try PickupPlaceName("Example Diner"), createdAt: start)
        context.insert(noodles)
        context.insert(diner)

        for (index, place) in [noodles, diner, noodles].enumerated() {
            let delivery = Delivery(shift: shift, acceptedAt: at(Double(index) * 30 + 5))
            delivery.setPickupPlace(place)
            context.insert(delivery)
        }

        #expect(shift.periodRecord(for: .none).pickupPlaceIDs == [noodles.id, diner.id])
    }

    /// End to end through the models: which place a wait happened at stops
    /// mattering the moment the sample qualifies.
    @Test("A period median over stored shifts uses every sample, whatever place it was at")
    func periodMedianOverStoredShiftsIgnoresPlaceIdentity() throws {
        let context = ModelContext(try container())
        let calendar = Calendar(identifier: .gregorian)
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))

        let shift = Shift(startedAt: start)
        try shift.end(at: at(300))
        context.insert(shift)

        let busy = PickupPlace(name: try PickupPlaceName("Nowhere Noodles"), createdAt: start)
        let rare = PickupPlace(name: try PickupPlaceName("Example Diner"), createdAt: start)
        context.insert(busy)
        context.insert(rare)

        // Five 10-minute waits at one place and a single 40-minute wait at
        // another: the median of the samples is 10 minutes, while the median of
        // the two places' medians would be 25.
        for index in 0..<5 {
            let accepted = at(Double(index) * 20)
            let delivery = Delivery(shift: shift, acceptedAt: accepted)
            try delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(60))
            try delivery.markPickedUp(at: accepted.addingTimeInterval(11 * 60))
            try delivery.markDelivered(at: accepted.addingTimeInterval(15 * 60))
            delivery.setPickupPlace(busy)
            context.insert(delivery)
        }

        let slow = Delivery(shift: shift, acceptedAt: at(200))
        try slow.markArrivedAtPickup(at: at(201))
        try slow.markPickedUp(at: at(241))
        try slow.markDelivered(at: at(250))
        slow.setPickupPlace(rare)
        context.insert(slow)

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        #expect(metrics.pickupWaitSampleCount == 6)
        #expect(metrics.medianPickupWait == 10 * 60.0)
        #expect(metrics.pickupPlaceCount == 2)
    }

    // MARK: Schema

    /// Everything a period shows is derived. Nothing about aggregation touches
    /// the store's shape, and nothing it computes writes to the store.
    ///
    /// The current schema version is asserted in the suite belonging to whatever
    /// version is current, not here: a figure repeated across suites is one that
    /// gets updated in four places and forgotten in the fifth. What matters to a
    /// period summary is that no aggregate is stored at all, which is what the
    /// rest of this test says.
    @Test("Aggregation persists nothing")
    func aggregationPersistsNothing() throws {

        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))
        for aggregate in ["weeklyEarnings", "periodEarnings", "totalDistance", "deliveryCount", "activeDuration"] {
            #expect(!properties.contains(aggregate), "No aggregate is persisted")
        }

        let context = ModelContext(try container())
        let stored = Shift(startedAt: start)
        try stored.end(at: at(180))
        try stored.setGrossEarnings(Money(minorUnits: 8625))
        context.insert(stored)
        try context.save()

        let calendar = Calendar(identifier: .gregorian)
        let period = try #require(ReportingPeriod(unit: .week, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [stored.periodRecord(for: .none)], in: period)

        #expect(metrics.completedShiftCount == 1)
        #expect(!context.hasChanges, "Deriving a period summary is a read")
    }
}
