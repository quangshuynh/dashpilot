import Foundation
import Testing
@testable import DashPilot

/// What a period's shifts are estimated to have spent on fuel, what they are
/// estimated to have been left with after it, and — mostly — what neither figure
/// is allowed to be read as.
///
/// **Partial coverage is the subject.** A week of six shifts of which four
/// record enough to be estimated produces a real figure over four shifts, and
/// every test here exists to stop that being presented as a figure over six.
@Suite("Period fuel and estimated net")
struct PeriodFuelMetricsTests {
    private let calculator = PeriodMetricsCalculator()
    private let calendar: Calendar
    private let start: Date
    private let week: ReportingPeriod

    private static let metresPerMile = 1609.344

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        week = try #require(ReportingPeriod(unit: .week, containing: start, calendar: calendar))
    }

    // MARK: Fixtures

    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3_600) }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func decimal(_ string: String) throws -> Decimal {
        try #require(Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")))
    }

    private func route(miles: Double, gapCount: Int = 0) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: gapCount,
            usableSampleCount: 40,
            usesInferredContinuity: false
        )
    }

    /// A shift recording a fuel economy and a gas price over a measured route,
    /// estimated by the app's one fuel calculation rather than by this file.
    private func estimated(
        milesPerGallon: String,
        gasPrice: String,
        over recordedDistance: RouteDistance
    ) throws -> FuelEstimate {
        FuelEstimateCalculator().estimate(
            recordedDistance: recordedDistance,
            assumptions: FuelAssumptions(
                milesPerGallon: try decimal(milesPerGallon),
                gasPricePerGallon: try money(gasPrice)
            )
        )
    }

    private func record(
        startedAt: Date? = nil,
        earnings: Money? = nil,
        route recordedDistance: RouteDistance = .none,
        fuel: FuelEstimate = .unavailable(.milesPerGallonNotRecorded)
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: startedAt ?? at(9),
            isCompleted: true,
            workingDuration: 4 * 3_600,
            grossEarnings: earnings,
            recordedDistance: recordedDistance,
            fuelEstimate: fuel
        )
    }

    /// A shift with both halves: a recorded amount and an estimate over its
    /// route. `$4.00` a gallon at 25 MPG is `$0.16` a recorded mile, which keeps
    /// the arithmetic in these tests checkable by hand.
    private func coveredShift(
        at hours: Double,
        earnings: String?,
        miles: Double,
        gapCount: Int = 0
    ) throws -> PeriodShiftRecord {
        let measured = route(miles: miles, gapCount: gapCount)
        return record(
            startedAt: at(hours),
            earnings: try earnings.map(money),
            route: measured,
            fuel: try estimated(milesPerGallon: "25", gasPrice: "4.00", over: measured)
        )
    }

    // MARK: Coverage

    @Test("Every shift covered: the estimate is the whole period's, and says so")
    func everyShiftCovered() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                try coveredShift(at: 30, earnings: "80.00", miles: 25)
            ],
            in: week
        )

        // 75 recorded miles at 25 MPG is 3 gallons, at $4.00 is $12.00.
        #expect(metrics.fuel.estimatedCost == (try money("12.00")))
        #expect(metrics.fuel.estimatedGallons == (try decimal("3")))
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
        #expect(metrics.fuel.isComplete)
        #expect(metrics.fuel.mileageCoveragePercentage == 100)
        #expect(
            metrics.fuel.spokenStatement(locale: Locale(identifier: "en_US"))
                .contains("across every completed shift"),
            "Complete coverage is stated rather than left as the case with no caveat"
        )
    }

    @Test("Some shifts covered: the figure is real, and the counts behind it travel with it")
    func someShiftsCovered() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                try coveredShift(at: 30, earnings: "80.00", miles: 25),
                // Drove, recorded an amount, never entered a fuel economy.
                record(startedAt: at(54), earnings: try money("60.00"), route: route(miles: 40))
            ],
            in: week
        )

        #expect(metrics.fuel.estimatedCost == (try money("12.00")), "The covered shifts' estimates, added up")
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 3))
        #expect(!metrics.fuel.isComplete)

        // 75 of 115 recorded miles. The mileage coverage is the one that says
        // how much of the *driving* is behind the figure.
        #expect(
            abs(metrics.fuel.coveredDistance.miles - 75) < 0.001,
            "Covered miles are the covered shifts' own"
        )
        #expect(abs(metrics.fuel.totalDistance.miles - 115) < 0.001)
        #expect(metrics.fuel.mileageCoveragePercentage == 65)

        let statement = try #require(metrics.fuel.mileageCoverageStatement(locale: Locale(identifier: "en_US")))
        #expect(statement.contains("of"), "Showed: \(statement)")
        #expect(metrics.fuel.shiftCoverageStatement == "2 of 3 shifts")
    }

    @Test("No shift covered: unavailable rather than a period whose driving cost nothing")
    func noShiftCovered() throws {
        let metrics = calculator.metrics(
            of: [
                record(startedAt: at(9), earnings: try money("100.00"), route: route(miles: 50)),
                record(startedAt: at(30), earnings: try money("80.00"), route: route(miles: 25))
            ],
            in: week
        )

        #expect(metrics.fuel.estimatedCost == nil, "Missing is not zero")
        #expect(!metrics.fuel.isAvailable)
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 2))

        let explanation = try #require(metrics.fuel.unavailableExplanation)
        #expect(explanation.contains("not the same as using no fuel"))
        #expect(!metrics.fuel.spokenStatement().contains("$0.00"))
    }

    @Test("An empty period has no estimate and no net, and neither reads as a zero")
    func anEmptyPeriod() {
        let metrics = calculator.metrics(of: [PeriodShiftRecord](), in: week)

        #expect(metrics.fuel == .none)
        #expect(metrics.estimatedNetAfterFuel == .none)
        #expect(metrics.estimatedNetAfterFuel.unavailability == .noCompletedShifts)
    }

    @Test("A shift with assumptions but no measurable route contributes nothing and is uncovered")
    func anUnmeasuredRouteIsUncovered() throws {
        let unmeasurable = RouteDistance(
            metres: 0,
            segmentCount: 0,
            gapCount: 1,
            usableSampleCount: 3,
            usesInferredContinuity: false
        )

        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                record(
                    startedAt: at(30),
                    earnings: try money("80.00"),
                    route: unmeasurable,
                    fuel: try estimated(milesPerGallon: "25", gasPrice: "4.00", over: unmeasurable)
                )
            ],
            in: week
        )

        #expect(metrics.fuel.estimatedCost == (try money("8.00")), "Only the measured shift contributes")
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    // MARK: Different assumptions per shift

    @Test("Each shift is estimated under its own fuel economy")
    func differentFuelEconomies() throws {
        let first = route(miles: 50)
        let second = route(miles: 50)

        let metrics = calculator.metrics(
            of: [
                record(
                    startedAt: at(9),
                    route: first,
                    fuel: try estimated(milesPerGallon: "25", gasPrice: "4.00", over: first)
                ),
                record(
                    startedAt: at(30),
                    route: second,
                    // Half as economical over the same distance: twice the fuel.
                    fuel: try estimated(milesPerGallon: "12.5", gasPrice: "4.00", over: second)
                )
            ],
            in: week
        )

        // 2 gallons at $4.00 plus 4 gallons at $4.00.
        #expect(metrics.fuel.estimatedCost == (try money("24.00")))
        #expect(metrics.fuel.estimatedGallons == (try decimal("6")))
    }

    @Test("Each shift is estimated under its own gas price")
    func differentGasPrices() throws {
        let first = route(miles: 50)
        let second = route(miles: 50)

        let metrics = calculator.metrics(
            of: [
                record(
                    startedAt: at(9),
                    route: first,
                    fuel: try estimated(milesPerGallon: "25", gasPrice: "4.00", over: first)
                ),
                record(
                    startedAt: at(30),
                    route: second,
                    fuel: try estimated(milesPerGallon: "25", gasPrice: "3.00", over: second)
                )
            ],
            in: week
        )

        // 2 gallons at $4.00 plus 2 gallons at $3.00.
        #expect(metrics.fuel.estimatedCost == (try money("14.00")))
        #expect(
            metrics.fuel.estimatedCost != (try money("16.00")),
            "The period does not re-price every shift at one figure"
        )
    }

    @Test("A partial route in the covered subset makes the estimate a floor, and says so")
    func aPartialRouteIsStated() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50, gapCount: 2),
                try coveredShift(at: 30, earnings: "80.00", miles: 25)
            ],
            in: week
        )

        #expect(metrics.fuel.isAnyRoutePartial)
        #expect(metrics.fuel.spokenStatement().contains("more fuel"))
        #expect(metrics.estimatedNetAfterFuel.isAnyRoutePartial, "A floor on the fuel is a ceiling on the net")
    }

    // MARK: The estimated net, and the subset it is worked out over

    @Test("The net is worked out over the shifts that record both halves, not across the period")
    func theNetUsesThePairedSubset() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                // Estimated, but nobody wrote down what it paid.
                try coveredShift(at: 30, earnings: nil, miles: 25),
                // Paid, but no fuel economy recorded.
                record(startedAt: at(54), earnings: try money("60.00"), route: route(miles: 40))
            ],
            in: week
        )

        let net = metrics.estimatedNetAfterFuel
        #expect(net.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
        #expect(net.recordedEarnings == (try money("100.00")))
        // 50 recorded miles at 25 MPG is 2 gallons, at $4.00 is $8.00.
        #expect(net.estimatedFuel == (try money("8.00")))
        #expect(net.amount == (try money("92.00")))

        // The arithmetic the design exists to refuse: the period's whole
        // earnings less the period's whole estimated fuel.
        let wholePeriod = try #require(metrics.recordedGrossEarnings) - (try #require(metrics.fuel.estimatedCost))
        #expect(
            net.amount != wholePeriod,
            "A net must not take a figure from one subset off a figure from another"
        )
    }

    @Test("A partial-coverage net says which shifts it is, and does not read as the period's")
    func aPartialNetSaysWhatItCovers() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                record(startedAt: at(30), earnings: try money("80.00"), route: route(miles: 40))
            ],
            in: week
        )

        let net = metrics.estimatedNetAfterFuel
        #expect(!net.isComplete)
        let caution = try #require(net.subsetCautionStatement)
        #expect(caution.contains("1 of 2 shifts"))
        #expect(caution.contains("not this period's earnings less this period's fuel"))
        #expect(net.spokenStatement().contains("1 of 2 shifts"))
    }

    @Test("A fully covered net is stated as covering the period, rather than silently")
    func aCompleteNetSaysSo() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: "100.00", miles: 50),
                try coveredShift(at: 30, earnings: "80.00", miles: 25)
            ],
            in: week
        )

        let net = metrics.estimatedNetAfterFuel
        #expect(net.isComplete)
        #expect(net.subsetCautionStatement == nil)
        #expect(net.amount == (try money("168.00")), "$180.00 recorded less $12.00 estimated fuel")
        #expect(net.spokenStatement().contains("across every completed shift"))
    }

    @Test("A net with no shift recording both says which fact is missing")
    func noShiftHasBothHalves() throws {
        let metrics = calculator.metrics(
            of: [
                try coveredShift(at: 9, earnings: nil, miles: 50),
                record(startedAt: at(30), earnings: try money("80.00"), route: route(miles: 40))
            ],
            in: week
        )

        let net = metrics.estimatedNetAfterFuel
        #expect(net.amount == nil)
        #expect(net.unavailability == .noShiftHasBoth)
        #expect(net.coverage == MetricCoverage(contributingCount: 0, eligibleCount: 2))
        #expect(try #require(net.unavailability?.explanation).contains("not the same as earning nothing"))
    }

    @Test("A net below zero is a real outcome and is reported as one")
    func aNegativeNet() throws {
        let metrics = calculator.metrics(
            of: [try coveredShift(at: 9, earnings: "5.00", miles: 100)],
            in: week
        )

        // 100 recorded miles at 25 MPG is 4 gallons, at $4.00 is $16.00.
        #expect(metrics.estimatedNetAfterFuel.amount == (try money("-11.00")))
        #expect(metrics.estimatedNetAfterFuel.isAvailable)
    }

    // MARK: Recorded expenses stay separate

    @Test("A recorded fuel expense is not in the estimate, and the estimate is not in the expenses")
    func recordedFuelAndEstimatedFuelStayApart() throws {
        let expenses = [
            ExpenseRecord(occurredAt: at(12), amount: try money("45.00"), category: .fuel)
        ]

        let metrics = calculator.metrics(
            of: [try coveredShift(at: 9, earnings: "100.00", miles: 50)],
            expenses: expenses,
            in: week
        )

        // Each figure is exactly its own source. Nothing is added, nothing is
        // netted off, and neither is derived from the other: DashPilot does not
        // know which shifts a tank was burned on.
        #expect(metrics.expenses.recordedTotal == (try money("45.00")))
        #expect(metrics.fuel.estimatedCost == (try money("8.00")))

        // The two nets are distinct figures over distinct inputs.
        #expect(metrics.netAfterRecordedExpenses.amount == (try money("55.00")), "$100.00 less $45.00 recorded")
        #expect(metrics.estimatedNetAfterFuel.amount == (try money("92.00")), "$100.00 less $8.00 estimated")

        // And neither has the other taken off it, which is the double count.
        let bothSubtracted = try money("100.00") - (try money("45.00")) - (try money("8.00"))
        #expect(metrics.netAfterRecordedExpenses.amount != bothSubtracted)
        #expect(metrics.estimatedNetAfterFuel.amount != bothSubtracted)
    }

    @Test("Recording an expense moves no estimated figure, and estimating moves no expense figure")
    func theTwoModelsDoNotInteract() throws {
        let shifts = [try coveredShift(at: 9, earnings: "100.00", miles: 50)]

        let withoutExpenses = calculator.metrics(of: shifts, in: week)
        let withExpenses = calculator.metrics(
            of: shifts,
            expenses: [ExpenseRecord(occurredAt: at(12), amount: try money("45.00"), category: .fuel)],
            in: week
        )

        #expect(withExpenses.fuel == withoutExpenses.fuel)
        #expect(withExpenses.estimatedNetAfterFuel == withoutExpenses.estimatedNetAfterFuel)
        #expect(withoutExpenses.expenses.recordedTotal == nil)
    }

    // MARK: What a period does not do with an estimate

    @Test("A running shift's estimate never enters a period's fuel")
    func runningShiftsAreExcluded() throws {
        var running = try coveredShift(at: 30, earnings: "500.00", miles: 200)
        running = PeriodShiftRecord(
            startedAt: running.startedAt,
            isCompleted: false,
            workingDuration: running.workingDuration,
            grossEarnings: running.grossEarnings,
            recordedDistance: running.recordedDistance,
            fuelEstimate: running.fuelEstimate
        )

        let metrics = calculator.metrics(
            of: [try coveredShift(at: 9, earnings: "100.00", miles: 50), running],
            in: week
        )

        #expect(metrics.fuel.estimatedCost == (try money("8.00")))
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 1))
    }

    @Test("Two periods are not compared on an estimate, and nothing declares one more profitable")
    func estimatesAreNotCompared() throws {
        let covered = calculator.metrics(
            of: [try coveredShift(at: 9, earnings: "100.00", miles: 50)],
            in: week
        )
        let previous = try #require(week.precedingEquivalent(using: calendar))
        let uncovered = calculator.metrics(
            of: [
                record(
                    startedAt: previous.start.addingTimeInterval(9 * 3_600),
                    earnings: try money("100.00"),
                    route: route(miles: 50)
                )
            ],
            in: previous
        )

        let comparison = try #require(
            PeriodComparisonCalculator().comparison(
                of: covered,
                with: uncovered,
                asOf: week.start.addingTimeInterval(14 * 86_400),
                calendar: calendar
            )
        )

        // Estimated fuel and estimated net are deliberately absent from the
        // comparison. Two periods whose fuel coverage differs are not like with
        // like, and two estimated under different assumptions are two different
        // questions. Nothing here ranks, scores or declares a winner.
        let titles = comparison.entries.map(\.metric.title)
        #expect(
            titles.allSatisfy { !$0.lowercased().contains("estimated") },
            "Showed: \(titles)"
        )
        #expect(titles.allSatisfy { !$0.lowercased().contains("fuel") })
        #expect(
            !PeriodComparisonMetric.allMetrics.contains { $0.title.lowercased().contains("fuel") },
            "The closed list of compared figures holds no estimate"
        )
    }
}
