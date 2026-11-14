import Foundation
import Testing
@testable import DashPilot

/// Gross, recorded expenses, estimated fuel and the nets and rates built from
/// them: which source each figure reads, which subset each rate divides over,
/// and the two things that must never happen, which are counting fuel twice and
/// treating a fuel purchase as the fuel a shift used.
///
/// Every amount, distance and time here is invented.
@Suite("Profitability reconciliation")
struct ProfitabilityReconciliationTests {
    private let week: ReportingPeriod
    private let monday: Date
    private let calculator = PeriodMetricsCalculator()

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)))
        week = try #require(ReportingPeriod(unit: .week, containing: monday, calendar: calendar))
    }

    private func dollars(_ cents: Int) -> Money { Money(minorUnits: cents) }

    /// A consumption over `miles` at 25 MPG and $3.50 a gallon.
    private func fuel(miles: Decimal, partial: Bool = false) -> FuelEstimate {
        let gallons = miles / 25
        return .available(
            FuelConsumption(
                recordedMiles: miles,
                milesPerGallon: 25,
                gasPricePerGallon: dollars(350),
                gallons: gallons,
                cost: dollars(350) * gallons,
                isRoutePartial: partial
            )
        )
    }

    private func route(miles: Double) -> RouteDistance {
        RouteDistance(metres: miles * 1_609.344, segmentCount: 10, gapCount: 0, usableSampleCount: 11, usesInferredContinuity: false)
    }

    private func shift(
        day: Int = 0,
        hours: Double,
        elapsedHours: Double? = nil,
        gross: Int?,
        miles: Double? = nil,
        fuel estimate: FuelEstimate = .unavailable(.milesPerGallonNotRecorded)
    ) -> PeriodShiftRecord {
        PeriodShiftRecord(
            startedAt: monday.addingTimeInterval(Double(day) * 86_400),
            workingDuration: hours * 3600,
            grossEarnings: gross.map(dollars),
            recordedDistance: miles.map(route) ?? .none,
            fuelEstimate: estimate,
            elapsedDuration: (elapsedHours ?? hours) * 3600
        )
    }

    private func expense(_ cents: Int, _ category: ExpenseCategory, day: Int = 0) -> ExpenseRecord {
        ExpenseRecord(occurredAt: monday.addingTimeInterval(Double(day) * 86_400 + 3600), amount: dollars(cents), category: category)
    }

    // MARK: Double counting

    @Test("A recorded fuel purchase and estimated fuel are never subtracted together")
    func fuelIsNeverCountedTwice() {
        let metrics = calculator.metrics(
            of: [shift(hours: 4, gross: 10_000, miles: 50, fuel: fuel(miles: 50))],
            expenses: [expense(4_000, .fuel), expense(1_000, .parkingAndTolls)],
            in: week
        )

        #expect(metrics.recordedGrossEarnings == dollars(10_000))
        #expect(metrics.fuel.estimatedCost == dollars(700), "50 miles at 25 MPG is 2 gallons, $7.00 at $3.50")
        #expect(metrics.recordedFuelPurchases?.total == dollars(4_000))
        #expect(metrics.netAfterRecordedExpenses.amount == dollars(5_000), "Gross less what was recorded paid; no estimate")
        #expect(metrics.estimatedNetAfterFuel.amount == dollars(9_300), "Gross less the estimate; no purchase")
        #expect(metrics.netAfterRecordedExpenses.amount != dollars(10_000 - 4_000 - 1_000 - 700))
    }

    @Test("A fuel purchase made during a shift is not that shift's fuel use")
    func purchaseIsNotConsumption() {
        // No vehicle assumptions: buying fuel says nothing about what was burned.
        let metrics = calculator.metrics(
            of: [shift(hours: 4, gross: 10_000, miles: 50)],
            expenses: [expense(4_500, .fuel)],
            in: week
        )

        #expect(metrics.fuel.estimatedCost == nil)
        #expect(metrics.fuel.shiftCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 1))
        #expect(metrics.estimatedNetAfterFuel.amount == nil)
        #expect(metrics.estimatedNetAfterFuel.unavailability == .noShiftHasBoth)
        #expect(metrics.recordedFuelPurchases?.total == dollars(4_500), "Still shown, as what was paid")
    }

    @Test("An expense-only period keeps its purchases and estimates nothing")
    func expenseOnlyPeriod() {
        let metrics = calculator.metrics(of: [], expenses: [expense(3_000, .fuel, day: 2)], in: week)

        #expect(metrics.isEmpty)
        #expect(metrics.hasAnyRecords)
        #expect(metrics.recordedFuelPurchases?.recordCount == 1)
        #expect(metrics.fuel == .none)
        #expect(metrics.netAfterRecordedExpenses.amount == nil, "No recorded gross to subtract from")
        #expect(metrics.estimatedNetAfterFuel.perWorkingHour.amount == nil)
    }

    // MARK: Missing data

    @Test("Missing mileage leaves every fuel-based figure unavailable and the gross rate intact")
    func missingMileage() throws {
        let estimate = FuelEstimateCalculator().estimate(
            recordedDistance: .none,
            assumptions: FuelAssumptions(milesPerGallon: 25, gasPricePerGallon: dollars(350))
        )
        #expect(estimate == .unavailable(.noRouteRecorded))

        let metrics = calculator.metrics(of: [shift(hours: 4, gross: 10_000, fuel: estimate)], in: week)
        #expect(metrics.grossPerWorkingHour.amount == dollars(2_500))
        #expect(metrics.grossPerRecordedMile.amount == nil)
        #expect(metrics.fuel.estimatedCost == nil)
        #expect(metrics.estimatedNetAfterFuel.amount == nil)
        #expect(metrics.estimatedNetAfterFuel.perRecordedMile.amount == nil)

        let profitability = ShiftProfitability(recordedEarnings: dollars(10_000), fuelEstimate: estimate, workingDuration: 4 * 3600)
        #expect(profitability.estimatedNetPerRecordedMile == .unavailable(.fuelNotEstimated))
    }

    // MARK: Paired rates

    @Test("Each rate divides over its own paired subset, summed before dividing")
    func pairedRates() throws {
        let metrics = calculator.metrics(
            of: [
                // Gross, fuel and working time.
                shift(day: 0, hours: 4, gross: 10_000, miles: 50, fuel: fuel(miles: 50)),
                // Gross and time, no fuel estimate.
                shift(day: 1, hours: 2, gross: 6_000),
                // Fuel and time, no gross.
                shift(day: 2, hours: 1, gross: nil, miles: 10, fuel: fuel(miles: 10))
            ],
            in: week
        )

        #expect(metrics.grossPerWorkingHour.amount == Money(amount: Decimal(string: "26.666667")!), "$160 over 6 hours")
        #expect(metrics.grossPerWorkingHour.coverage == MetricCoverage(contributingCount: 2, eligibleCount: 3))

        let net = metrics.estimatedNetAfterFuel
        #expect(net.amount == dollars(9_300), "Only the shift with both")
        #expect(net.perWorkingHour.amount == dollars(2_325), "$93 over 4 hours")
        #expect(net.perWorkingHour.coverage == MetricCoverage(contributingCount: 1, eligibleCount: 3))
        #expect(net.perRecordedMile.amount == dollars(186), "$93 over 50 miles")
        #expect(metrics.fuel.estimatedCost == dollars(840), "Fuel estimates cover both shifts with an estimate")
    }

    @Test("Gross and net per recorded mile reconcile to the fuel per mile over the same shifts")
    func perMileReconciles() throws {
        let metrics = calculator.metrics(of: [shift(hours: 4, gross: 10_000, miles: 50, fuel: fuel(miles: 50))], in: week)

        let gross = try #require(metrics.grossPerRecordedMile.amount)
        let net = try #require(metrics.estimatedNetAfterFuel.perRecordedMile.amount)
        #expect(gross == dollars(200))
        #expect(gross - net == dollars(14), "$7.00 of fuel over 50 miles")
    }

    @Test("A shift with no working time is left out of the hourly net, not the per-mile net")
    func zeroWorkingTime() {
        let net = calculator.metrics(
            of: [
                shift(day: 0, hours: 0, gross: 2_000, miles: 10, fuel: fuel(miles: 10)),
                shift(day: 1, hours: 2, gross: 5_000, miles: 10, fuel: fuel(miles: 10))
            ],
            in: week
        ).estimatedNetAfterFuel

        #expect(net.perWorkingHour.coverage.contributingCount == 1)
        #expect(net.perWorkingHour.amount == dollars(2_430), "($50.00 - $1.40) over 2 hours")
        #expect(net.perRecordedMile.coverage.contributingCount == 2)
        #expect(net.perRecordedMile.amount == dollars(336), "($70.00 - $2.80) over 20 miles")
    }

    @Test("A negative estimated net is a real result, and its rates stay negative")
    func negativeNet() {
        let net = calculator.metrics(of: [shift(hours: 2, gross: 500, miles: 50, fuel: fuel(miles: 50))], in: week)
            .estimatedNetAfterFuel
        #expect(net.amount == dollars(-200))
        #expect(net.perWorkingHour.amount == dollars(-100))
        #expect(net.perRecordedMile.amount == dollars(-4))
    }

    @Test("A shift's own net per recorded mile divides by the miles its fuel was estimated over")
    func shiftNetPerMile() {
        let profitability = ShiftProfitability(recordedEarnings: dollars(10_000), fuelEstimate: fuel(miles: 50), workingDuration: 4 * 3600)
        #expect(profitability.estimatedNetAfterFuel == .available(dollars(9_300)))
        #expect(profitability.estimatedNetPerWorkingHour == .available(dollars(2_325)))
        #expect(profitability.estimatedNetPerRecordedMile == .available(dollars(186)))

        let stationary = ShiftProfitability(recordedEarnings: dollars(10_000), fuelEstimate: fuel(miles: 0), workingDuration: 4 * 3600)
        #expect(stationary.estimatedNetPerRecordedMile == .unavailable(.zeroRecordedDistance))
        #expect(!EstimatedNetUnavailability.zeroRecordedDistance.explanation.isEmpty)
    }

    // MARK: Time

    @Test("Total shift time includes pauses; working time, the hourly denominator, does not")
    func elapsedAndWorking() {
        let metrics = calculator.metrics(
            of: [
                shift(day: 0, hours: 4.5, elapsedHours: 5, gross: 9_000),
                shift(day: 1, hours: 3, gross: 6_000)
            ],
            in: week
        )

        #expect(metrics.elapsedDuration == TimeInterval(8 * 3600))
        #expect(metrics.workingDuration == 7.5 * 3600)
        #expect(metrics.pausedDuration == 1_800)
        #expect(metrics.elapsedCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
        #expect(metrics.grossPerWorkingHour.amount == dollars(2_000), "$150 over 7.5 working hours, not 8")
    }

    @Test("Running shifts contribute nothing to a period")
    func runningShiftsAreExcluded() {
        let running = PeriodShiftRecord(startedAt: monday, isCompleted: false, workingDuration: nil, grossEarnings: nil,
                                        fuelEstimate: fuel(miles: 40), elapsedDuration: nil)
        let metrics = calculator.metrics(of: [running], in: week)
        #expect(metrics.isEmpty)
        #expect(metrics.fuel == .none)
    }

    // MARK: Assumptions

    @Test("The assumptions behind a period's estimate are stated, as a range where shifts differ")
    func assumptionStatements() {
        let locale = Locale(identifier: "en_US")
        let one = PeriodFuelAssumptions(consumptions: [fuel(miles: 10).consumption!, fuel(miles: 20).consumption!])
        #expect(one.statement(locale: locale) == "At 25 MPG and $3.50 a gallon")

        let other = FuelConsumption(recordedMiles: 10, milesPerGallon: 30, gasPricePerGallon: dollars(329),
                                    gallons: Decimal(string: "0.333333")!, cost: dollars(110), isRoutePartial: false)
        let mixed = PeriodFuelAssumptions(consumptions: [fuel(miles: 10).consumption!, other])
        #expect(mixed.statement(locale: locale) == "At 25 to 30 MPG and $3.29 to $3.50 a gallon, as each shift recorded")
        #expect(mixed.spokenStatement(locale: locale)?.contains("miles per gallon") == true)
        #expect(PeriodFuelAssumptions.none.statement(locale: locale) == nil)

        let metrics = calculator.metrics(of: [shift(hours: 2, gross: 4_000, miles: 10, fuel: .available(other))], in: week)
        #expect(metrics.fuel.assumptions.milesPerGallon == 30...30)
    }
}
