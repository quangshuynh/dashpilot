import Foundation
import Testing
@testable import DashPilot

/// What a shift's recorded miles are estimated to have consumed, and what that
/// fuel cost.
///
/// ## The claim this suite exists for
///
/// **Fuel cost is gallons priced, never miles priced.** The one arithmetic
/// mistake this feature can make is
/// `recordedMiles * gasPricePerGallon`, which is wrong by a factor of the
/// vehicle's fuel economy and looks entirely plausible on screen. Several tests
/// below compute that product explicitly and assert the estimate is **not** it.
///
/// ## And the rule beside it
///
/// **A missing assumption is never zero.** A shift with no fuel economy recorded
/// is not a shift that used no fuel, and one with no price recorded is not one
/// whose fuel was free. Each absence produces the reason naming it. An explicit
/// price of zero is a different matter: it is a recorded fact and produces a
/// recorded estimate of nothing.
///
/// Every figure here is invented.
@Suite("Fuel estimate")
struct FuelEstimateTests {
    private let calculator = FuelEstimateCalculator()

    /// Exactly one mile, so a distance in the tests below is stated in miles and
    /// converted here rather than by hand.
    private static let metresPerMile = 1_609.344

    /// A measured route covering `miles`, with no detected gap.
    private func route(miles: Double, gaps: Int = 0, segments: Int = 1, usableSamples: Int = 10) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: segments,
            gapCount: gaps,
            usableSampleCount: usableSamples,
            usesInferredContinuity: false
        )
    }

    private func assumptions(_ milesPerGallon: String?, _ gasPrice: String?) throws -> FuelAssumptions {
        FuelAssumptions(
            milesPerGallon: try milesPerGallon.map { try #require(Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))) },
            gasPricePerGallon: try gasPrice.map { try #require(Money(exact: $0)) }
        )
    }

    // MARK: The arithmetic

    @Test("Gallons are recorded miles divided by miles per gallon")
    func gallonsDivideMilesByEconomy() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: try assumptions("25", "3.50")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.gallons == Decimal(2), "50 recorded miles at 25 mpg is 2 gallons")
    }

    @Test("Fuel cost is the gallons priced, not the miles priced")
    func costPricesGallonsRatherThanMiles() throws {
        let gasPrice = try #require(Money(exact: "3.50"))
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: try assumptions("25", "3.50")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.cost == Money(minorUnits: 700), "2 gallons at $3.50 is $7.00")

        // The mistake this feature exists to make impossible, computed here so
        // the assertion is against the actual wrong answer rather than against a
        // number that merely happens to differ.
        let milesPriced = gasPrice * consumption.recordedMiles
        #expect(milesPriced == Money(minorUnits: 17_500))
        #expect(consumption.cost != milesPriced, "Pricing a mile as though it were a gallon is the defect")
    }

    @Test("A quotient that does not divide evenly stays exact to the working scale")
    func inexactQuotientStaysExact() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 100),
            assumptions: try assumptions("30", "3.00")
        )

        let consumption = try #require(estimate.consumption)
        // 100 / 30 kept to six places, which is the scale the cost is derived at.
        #expect(consumption.gallons == Decimal(string: "3.333333"))
        #expect(consumption.cost.amount == Decimal(string: "9.999999"))
        #expect(consumption.cost.rounded() == Money(minorUnits: 1_000), "It reads $10.00, rounded once, for display")
    }

    @Test("Money stays decimal: a price binary floating point cannot hold is exact")
    func moneyStaysDecimal() throws {
        // 10 recorded miles at 10 mpg is exactly one gallon, so the cost is the
        // price itself and any drift would be the arithmetic's own.
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 10),
            assumptions: try assumptions("10", "0.10")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.gallons == Decimal(1))
        #expect(consumption.cost.amount == Decimal(string: "0.10"))
        #expect(consumption.cost == Money(minorUnits: 10))
    }

    @Test("A fractional fuel economy is honoured to the cent of a mile per gallon")
    func fractionalEconomy() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 57),
            assumptions: try assumptions("28.5", "4.00")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.gallons == Decimal(2))
        #expect(consumption.cost == Money(minorUnits: 800))
    }

    // MARK: Missing is not zero

    @Test("No fuel economy recorded means no estimate, not an estimate of nothing")
    func missingEconomyHasNoEstimate() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: try assumptions(nil, "3.50")
        )

        #expect(estimate == .unavailable(.milesPerGallonNotRecorded))
        #expect(estimate.cost == nil)
        #expect(estimate.cost != Money.zero)
    }

    @Test("No gas price recorded means no estimate, not free fuel")
    func missingPriceHasNoEstimate() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: try assumptions("25", nil)
        )

        #expect(estimate == .unavailable(.gasPriceNotRecorded))
        #expect(estimate.cost == nil)
    }

    @Test("The missing fuel economy is named before the missing price")
    func economyIsNamedFirst() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: .none
        )

        #expect(
            estimate == .unavailable(.milesPerGallonNotRecorded),
            "A shift with neither is sent to the figure it will keep, rather than to the one it retypes each fill-up"
        )
    }

    @Test("A fuel economy of zero cannot be divided by, and the calculation refuses it")
    func zeroEconomyIsRefused() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: FuelAssumptions(milesPerGallon: .zero, gasPricePerGallon: Money(minorUnits: 350))
        )

        #expect(estimate.isAvailable == false, "Nothing divides by zero, and no estimate is invented for it")
    }

    @Test("A recorded gas price of zero is a fact, and produces an estimate of nothing")
    func zeroPriceIsRecordedRatherThanMissing() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50),
            assumptions: try assumptions("25", "0.00")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.gallons == Decimal(2), "The fuel was still used; it is the price that was nothing")
        #expect(consumption.cost == Money.zero)
        #expect(estimate.cost != nil, "An explicit zero is a recorded estimate, not an absent one")
    }

    // MARK: The route it estimates over

    @Test("A shift with no usable position has no mileage to estimate over")
    func noRouteHasNoEstimate() throws {
        let estimate = calculator.estimate(
            recordedDistance: .none,
            assumptions: try assumptions("25", "3.50")
        )

        #expect(estimate == .unavailable(.noRouteRecorded))
    }

    @Test("Positions that no continuous stretch joins are kept apart from no route at all")
    func unmeasurableRouteIsItsOwnReason() throws {
        let unmeasurable = RouteDistance(
            metres: 0,
            segmentCount: 0,
            gapCount: 3,
            usableSampleCount: 4,
            usesInferredContinuity: false
        )

        let estimate = calculator.estimate(
            recordedDistance: unmeasurable,
            assumptions: try assumptions("25", "3.50")
        )

        #expect(estimate == .unavailable(.routeNotMeasurable))
    }

    @Test("A measured route that covered no distance is a measurement, and estimates nothing used")
    func zeroMeasuredDistanceEstimatesNothing() throws {
        let stationary = RouteDistance(
            metres: 0,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 10,
            usesInferredContinuity: false
        )

        let estimate = calculator.estimate(
            recordedDistance: stationary,
            assumptions: try assumptions("25", "3.50")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.gallons == .zero)
        #expect(consumption.cost == Money.zero)
    }

    @Test("A partial route estimates over what was recorded, and says the figure is a floor")
    func partialRouteIsCarriedThrough() throws {
        let estimate = calculator.estimate(
            recordedDistance: route(miles: 50, gaps: 2, segments: 3),
            assumptions: try assumptions("25", "3.50")
        )

        let consumption = try #require(estimate.consumption)
        #expect(consumption.cost == Money(minorUnits: 700), "The estimate is over the miles that were recorded")
        #expect(consumption.isRoutePartial, "And it carries the fact that more were driven than recorded")
    }

    @Test("A route recorded before capture continuity existed is partial too")
    func legacyRouteIsPartial() throws {
        let legacy = RouteDistance(
            metres: 50 * Self.metresPerMile,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 10,
            usesInferredContinuity: true
        )

        let consumption = try #require(
            calculator.estimate(recordedDistance: legacy, assumptions: try assumptions("25", "3.50")).consumption
        )
        #expect(consumption.isRoutePartial)
    }

    @Test("Changing the recorded mileage rederives the estimate, and nothing is scaled by time")
    func mileageChangeRederivesTheEstimate() throws {
        let assumptions = try assumptions("25", "3.50")

        let before = try #require(calculator.estimate(recordedDistance: route(miles: 50), assumptions: assumptions).consumption)
        let after = try #require(calculator.estimate(recordedDistance: route(miles: 30), assumptions: assumptions).consumption)

        #expect(before.cost == Money(minorUnits: 700))
        #expect(after.cost == Money(minorUnits: 420), "30 recorded miles at 25 mpg is 1.2 gallons, at $3.50 is $4.20")
        #expect(after.milesPerGallon == before.milesPerGallon, "The assumptions did not move; the mileage did")
        #expect(after.gasPricePerGallon == before.gasPricePerGallon)
    }

    // MARK: What it carries

    @Test("The consumption states the assumptions it was derived under")
    func consumptionCarriesItsAssumptions() throws {
        let consumption = try #require(
            calculator.estimate(
                recordedDistance: route(miles: 50),
                assumptions: try assumptions("25", "3.50")
            ).consumption
        )

        #expect(consumption.milesPerGallon == Decimal(25))
        #expect(consumption.gasPricePerGallon == Money(minorUnits: 350))
        #expect(consumption.recordedMiles == Decimal(50))
    }

    @Test("Gallons are written with their unit, and spelled out for a listener")
    func gallonsAreFormatted() throws {
        let consumption = try #require(
            calculator.estimate(
                recordedDistance: route(miles: 50),
                assumptions: try assumptions("25", "3.50")
            ).consumption
        )
        let locale = Locale(identifier: "en_US")

        #expect(consumption.formattedGallons(locale: locale) == "2.00 gal")
        #expect(
            consumption.formattedGallons(width: .wide, locale: locale) == "2.00 gallons",
            "`gal` reads well and hears badly, so a listener is given the word"
        )
    }

    @Test("Every reason has a sentence, and none of them claims the missing value is zero")
    func everyReasonExplainsItself() {
        for reason in FuelEstimateUnavailability.allCases {
            let explanation = reason.explanation
            #expect(!explanation.isEmpty)
            #expect(!explanation.contains("$0"))
            #expect(!explanation.lowercased().contains("zero"))
        }
    }

    @Test("Nothing about a fuel estimate calls itself an expense, a deduction or a profit")
    func nothingClaimsMoreThanAnEstimate() throws {
        let consumption = try #require(
            calculator.estimate(
                recordedDistance: route(miles: 50),
                assumptions: try assumptions("25", "3.50")
            ).consumption
        )

        let sentences = FuelEstimateUnavailability.allCases.map(\.explanation)
            + [consumption.formattedGallons(locale: Locale(identifier: "en_US"))]

        for sentence in sentences {
            let lowered = sentence.lowercased()
            #expect(!lowered.contains("expense"))
            #expect(!lowered.contains("deduct"))
            #expect(!lowered.contains("profit"))
            #expect(!lowered.contains("tax"))
        }
    }

    // MARK: The assumptions value

    @Test("A shift with neither assumption has none, and one with either has some")
    func assumptionsReportWhatTheyHold() throws {
        #expect(FuelAssumptions.none.hasAny == false)
        #expect(FuelAssumptions.none.isComplete == false)

        let economyOnly = try assumptions("25", nil)
        #expect(economyOnly.hasAny)
        #expect(economyOnly.isComplete == false)

        let both = try assumptions("25", "3.50")
        #expect(both.isComplete)
    }
}

/// Reading what a driver types for a vehicle's fuel economy.
///
/// The one rule that is this type's own is that **zero is refused**, which is
/// the opposite of the money parser's rule and is the reason the two are not one
/// type: a price of nothing is a fact, and a vehicle that covers nothing on a
/// gallon is not.
@Suite("Miles per gallon input")
struct MilesPerGallonInputTests {
    private let input = MilesPerGallonInput(locale: Locale(identifier: "en_US"))

    @Test("A plain figure is read exactly")
    func readsAPlainFigure() throws {
        #expect(try input.milesPerGallon(from: "28.5") == Decimal(string: "28.5"))
        #expect(try input.milesPerGallon(from: "25") == Decimal(25))
    }

    @Test("Zero is refused, because it is the divisor")
    func refusesZero() {
        #expect(throws: MilesPerGallonInputError.notPositive) {
            try input.milesPerGallon(from: "0")
        }
        #expect(throws: MilesPerGallonInputError.notPositive) {
            try input.milesPerGallon(from: "0.00")
        }
    }

    @Test("A negative figure reads as the same rule, which is the one that explains itself")
    func refusesNegative() {
        #expect(throws: MilesPerGallonInputError.notPositive) {
            try input.milesPerGallon(from: "-5")
        }
    }

    @Test("An empty field, a word and too many places each have their own refusal")
    func refusesMalformedText() {
        #expect(throws: MilesPerGallonInputError.empty) { try input.milesPerGallon(from: "   ") }
        #expect(throws: MilesPerGallonInputError.notANumber) { try input.milesPerGallon(from: "thirty") }
        #expect(throws: MilesPerGallonInputError.notANumber) { try input.milesPerGallon(from: "28.5.1") }
        #expect(throws: MilesPerGallonInputError.excessiveScale) { try input.milesPerGallon(from: "28.555") }
    }

    @Test("A figure beyond the app's one guard is refused as too large")
    func refusesAbsurdFigures() {
        #expect(throws: MilesPerGallonInputError.tooLarge) {
            try input.milesPerGallon(from: "1000001")
        }
    }

    @Test("The locale's own decimal separator is what a driver types")
    func readsAnotherLocale() throws {
        let german = MilesPerGallonInput(locale: Locale(identifier: "de_DE"))

        #expect(try german.milesPerGallon(from: "28,5") == Decimal(string: "28.5"))
        #expect(german.text(for: try #require(Decimal(string: "28.5"))) == "28,5")
    }

    @Test("Seeding a field and reading it back gives the same figure")
    func roundTripsThroughAField() throws {
        let economy = try #require(Decimal(string: "31.25"))

        #expect(input.text(for: economy) == "31.25")
        #expect(try input.milesPerGallon(from: input.text(for: economy)) == economy)
    }

    @Test("Trailing zeroes are dropped when a field is seeded")
    func dropsTrailingZeroes() throws {
        #expect(input.text(for: try #require(Decimal(string: "28.50"))) == "28.5")
    }

    @Test("Every refusal says what the rule was")
    func everyRefusalExplainsItself() {
        let errors: [MilesPerGallonInputError] = [.empty, .notANumber, .excessiveScale, .notPositive, .tooLarge]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
