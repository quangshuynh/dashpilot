import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a finished shift is estimated to have been left with after fuel, and
/// the several things that deliberately do not enter that figure.
///
/// ## The claim this suite exists for
///
/// **Recorded and estimated never merge.** The earnings are the amount the
/// driver typed; the fuel is arithmetic over a measured distance and two
/// assumptions; the result is an estimate and is named one. Nothing here turns
/// an estimate into a recorded expense, and nothing turns a recorded expense
/// into part of a shift's net.
///
/// ## And the boundary beside it
///
/// **An expense belongs to a period, not to a shift.** `Expense` has no
/// relationship to `Shift`, by a decision older than this feature, so a shift
/// has no recorded expenses to net against and this type does not invent some.
/// Several tests below record an expense and assert that not one shift figure
/// moves.
///
/// Every figure, time and coordinate here is invented.
@MainActor
@Suite("Shift profitability")
struct ShiftProfitabilityTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private static let metresPerMile = 1_609.344

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func economy(_ value: String) throws -> Decimal {
        try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    /// A measured route covering `miles`.
    private func route(miles: Double, gaps: Int = 0) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: gaps,
            usableSampleCount: 10,
            usesInferredContinuity: false
        )
    }

    /// A four-hour shift that recorded `$100.00`, 50 recorded miles, 25 mpg and
    /// `$3.50` a gallon: two gallons, `$7.00` of fuel, `$93.00` left, `$23.25`
    /// an hour.
    private func shift(
        in context: ModelContext,
        earnings: Money? = Money(minorUnits: 10_000),
        milesPerGallon: String? = "25",
        gasPrice: Money? = Money(minorUnits: 350)
    ) throws -> Shift {
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.end(at: start.addingTimeInterval(4 * 3600))
        if let earnings { try shift.setGrossEarnings(earnings) }
        try shift.setFuelAssumptions(
            milesPerGallon: try milesPerGallon.map { try economy($0) },
            gasPricePerGallon: gasPrice
        )
        return shift
    }

    // MARK: The subtraction

    @Test("Estimated net after fuel is the recorded earnings less the estimated fuel cost")
    func netIsEarningsLessFuel() throws {
        let context = try makeContext()
        let shift = try shift(in: context)

        let profitability = shift.profitability(for: route(miles: 50))

        #expect(profitability.recordedEarnings == Money(minorUnits: 10_000))
        #expect(profitability.fuelEstimate.cost == Money(minorUnits: 700))
        #expect(profitability.estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)))
    }

    @Test("Estimated net per working hour divides by the same working time the gross rate does")
    func hourlyNetSharesTheGrossDenominator() throws {
        let context = try makeContext()
        let shift = try shift(in: context)
        let distance = route(miles: 50)

        let metrics = shift.metrics(for: distance)
        let profitability = shift.profitability(for: distance)

        let workingDuration = try #require(metrics.workingDuration)
        #expect(profitability.workingDuration == workingDuration, "One definition of working time, not two")
        #expect(metrics.grossPerWorkingHour == .available(Money(minorUnits: 2_500)), "$100.00 over four hours")
        #expect(
            profitability.estimatedNetPerWorkingHour == .available(Money(minorUnits: 2_325)),
            "$93.00 over the same four hours"
        )

        // The same division, applied to the same seconds, reached two ways.
        let net = try #require(profitability.estimatedNetAfterFuel.amount)
        #expect(
            profitability.estimatedNetPerWorkingHour.amount
                == ShiftMetricsCalculator.grossPerHour(of: net, over: workingDuration)
        )
    }

    @Test("Pausing the shift moves the hourly net, because it moves the working time")
    func pauseRederivesTheHourlyNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)
        let distance = route(miles: 50)

        #expect(shift.profitability(for: distance).estimatedNetPerWorkingHour == .available(Money(minorUnits: 2_325)))

        // An hour of the four was recorded as paused, so three hours were
        // worked. Nothing about the fuel or the earnings changes.
        context.insert(
            ShiftPause(
                shift: shift,
                startedAt: start.addingTimeInterval(3_600),
                endedAt: start.addingTimeInterval(7_200)
            )
        )
        try context.save()

        let paused = shift.profitability(for: distance)
        // Written as a `TimeInterval` rather than as an integer literal: an
        // `Optional<Double>` compared with an `Int` resolves through
        // `AnyHashable`, which compiles and is always false.
        #expect(paused.workingDuration == TimeInterval(3 * 3_600))
        #expect(paused.estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)), "The net itself did not move")
        #expect(paused.estimatedNetPerWorkingHour == .available(Money(minorUnits: 3_100)), "$93.00 over three hours")
        #expect(
            paused.estimatedNetPerWorkingHour.amount == shift.metrics(for: distance).grossPerWorkingHour.amount
                .flatMap { _ in paused.estimatedNetPerWorkingHour.amount },
            "And it followed the same denominator the gross rate followed"
        )
    }

    @Test("A shift whose estimated fuel came to more than it paid has a negative net, not a clamped one")
    func negativeNetIsStated() throws {
        let context = try makeContext()
        let shift = try shift(in: context, earnings: Money(minorUnits: 500))

        let profitability = shift.profitability(for: route(miles: 50))

        #expect(profitability.estimatedNetAfterFuel == .available(-Money(minorUnits: 200)), "$5.00 less $7.00")
        let hourly = try #require(profitability.estimatedNetPerWorkingHour.amount)
        #expect(hourly.isNegative)
    }

    @Test("Changing the recorded mileage rederives the net, and nothing is stored")
    func mileageChangeRederivesTheNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)

        #expect(shift.profitability(for: route(miles: 50)).estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)))
        #expect(shift.profitability(for: route(miles: 30)).estimatedNetAfterFuel == .available(Money(minorUnits: 9_580)))
    }

    @Test("Correcting the shift's end changes the recorded mileage, and the net follows it")
    func endCorrectionRederivesTheNet() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        // Three equal capture sessions of 3,600 m.
        for (index, startMinute) in [30.0, 180.0, 200.0].enumerated() {
            let session = UUID()
            for step in 0..<10 {
                context.insert(
                    RouteSample(
                        shift: shift,
                        sample: SyntheticRoute.sample(
                            at: start.addingTimeInterval(startMinute * 60 + Double(step) * 20),
                            northMetres: Double(index) * 9_000 + Double(step) * 400
                        ),
                        captureSessionID: session
                    )
                )
            }
        }
        try shift.end(at: start.addingTimeInterval(240 * 60))
        try shift.setGrossEarnings(Money(minorUnits: 10_000))
        try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        try context.save()

        let before = shift.profitability(for: shift.recordedDistance())
        let beforeNet = try #require(before.estimatedNetAfterFuel.amount)

        try ShiftEndCorrectionService(context: context).correct(shift, to: start.addingTimeInterval(190 * 60))

        let after = shift.profitability(for: shift.recordedDistance())
        let afterNet = try #require(after.estimatedNetAfterFuel.amount)

        #expect(afterNet > beforeNet, "Fewer recorded miles is less estimated fuel, so more is left")
        #expect(after.recordedEarnings == before.recordedEarnings, "The recorded amount did not move")
        #expect(
            after.workingDuration ?? 0 < before.workingDuration ?? 0,
            "And the shorter shift is what the hourly figure now divides by"
        )
    }

    // MARK: Missing is not zero

    @Test("With no fuel estimate there is no net, and the reason names the fuel")
    func missingFuelHasNoNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context, milesPerGallon: nil)

        let profitability = shift.profitability(for: route(miles: 50))

        #expect(profitability.estimatedNetAfterFuel == .unavailable(.fuelNotEstimated))
        #expect(profitability.estimatedNetPerWorkingHour == .unavailable(.fuelNotEstimated))
        #expect(profitability.estimatedNetAfterFuel.amount != Money.zero)
    }

    @Test("With no fuel estimate the shift's recorded figures are all still there")
    func missingFuelLeavesTheRecordedFiguresIntact() throws {
        let context = try makeContext()
        let shift = try shift(in: context, milesPerGallon: nil, gasPrice: nil)
        let distance = route(miles: 50)

        let metrics = shift.metrics(for: distance)
        #expect(metrics.grossEarnings == Money(minorUnits: 10_000))
        #expect(metrics.grossPerWorkingHour == .available(Money(minorUnits: 2_500)))
        #expect(metrics.grossPerRecordedMile == .available(Money(minorUnits: 200)), "$100.00 over 50 recorded miles")
        #expect(metrics.workingDuration == TimeInterval(4 * 3_600))

        // And the net says why it is absent rather than the screen losing the
        // rest of the shift.
        #expect(shift.profitability(for: distance).recordedEarnings == Money(minorUnits: 10_000))
    }

    @Test("With no recorded earnings there is no net, and nothing substitutes the deliveries' amounts")
    func missingEarningsHasNoNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context, earnings: nil)

        // A delivery that recorded an amount, which must not become the shift's.
        let offer = Offer(shift: shift, acceptedAt: start.addingTimeInterval(600))
        context.insert(offer)
        let delivery = Delivery(shift: shift, offer: offer, acceptedAt: start.addingTimeInterval(600))
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: start.addingTimeInterval(900))
        try delivery.markPickedUp(at: start.addingTimeInterval(1_200))
        try delivery.markDelivered(at: start.addingTimeInterval(1_800))
        try delivery.setGrossEarnings(Money(minorUnits: 1_475))
        try context.save()

        let profitability = shift.profitability(for: route(miles: 50))

        #expect(profitability.recordedEarnings == nil)
        #expect(profitability.estimatedNetAfterFuel == .unavailable(.earningsNotRecorded))
        #expect(
            profitability.estimatedNetAfterFuel.amount == nil,
            "A shift with no amount recorded is not one that paid what its deliveries did"
        )
    }

    @Test("A running shift has no net, and says so rather than reporting no earnings")
    func runningShiftHasNoNet() throws {
        let context = try makeContext()
        let running = Shift(startedAt: start)
        context.insert(running)

        let profitability = running.profitability(for: route(miles: 50))

        #expect(profitability.workingDuration == nil)
        #expect(profitability.estimatedNetAfterFuel == .unavailable(.shiftNotCompleted))
        #expect(profitability.estimatedNetPerWorkingHour == .unavailable(.shiftNotCompleted))
    }

    @Test("A shift kept paused throughout has a net but no hourly figure")
    func noWorkingTimeHasNoHourlyNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)
        context.insert(
            ShiftPause(shift: shift, startedAt: start, endedAt: start.addingTimeInterval(4 * 3600))
        )
        try context.save()

        let profitability = shift.profitability(for: route(miles: 50))

        #expect(profitability.estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)))
        #expect(profitability.estimatedNetPerWorkingHour == .unavailable(.noWorkingTime))
    }

    // MARK: Delivery money stays where it is

    @Test("A tip moves what its delivery paid, and moves no figure on the shift")
    func tipsDoNotEnterTheShiftNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)

        let offer = Offer(shift: shift, acceptedAt: start.addingTimeInterval(600))
        context.insert(offer)
        let delivery = Delivery(shift: shift, offer: offer, acceptedAt: start.addingTimeInterval(600))
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: start.addingTimeInterval(900))
        try delivery.markPickedUp(at: start.addingTimeInterval(1_200))
        try delivery.markDelivered(at: start.addingTimeInterval(1_800))
        try delivery.setGrossEarnings(Money(minorUnits: 1_475))
        try context.save()

        let before = shift.profitability(for: route(miles: 50))

        context.insert(
            try delivery.recordAdditionalTip(Money(minorUnits: 500), method: .cash, at: start.addingTimeInterval(1_900))
        )
        try context.save()

        // The delivery's own effective earnings move, by the existing rule.
        #expect(delivery.effectiveEarnings.amount == Money(minorUnits: 1_975))

        // The shift's do not, by the rule that keeps shift gross and delivery
        // gross independent.
        let after = shift.profitability(for: route(miles: 50))
        #expect(after.recordedEarnings == before.recordedEarnings)
        #expect(after.estimatedNetAfterFuel == before.estimatedNetAfterFuel)
        #expect(after.estimatedNetPerWorkingHour == before.estimatedNetPerWorkingHour)
    }

    // MARK: Recorded expenses are a different fact, in a different place

    @Test("Recording an expense moves no shift figure, because an expense belongs to a period")
    func expensesDoNotEnterTheShiftNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)
        let distance = route(miles: 50)

        let before = shift.profitability(for: distance)

        context.insert(
            try Expense(occurredAt: start.addingTimeInterval(1_800), amount: Money(minorUnits: 4_210), category: .fuel)
        )
        try context.save()

        let after = shift.profitability(for: distance)
        #expect(after.estimatedNetAfterFuel == before.estimatedNetAfterFuel)
        #expect(after.estimatedNetPerWorkingHour == before.estimatedNetPerWorkingHour)
        #expect(
            after.estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)),
            "Still the recorded earnings less the estimated fuel, and nothing else"
        )
    }

    @Test("Deriving a net creates no expense and changes none")
    func derivingTheNetTouchesNoExpense() throws {
        let context = try makeContext()
        let shift = try shift(in: context)
        let purchase = try Expense(occurredAt: start, amount: Money(minorUnits: 4_210), category: .fuel)
        context.insert(purchase)
        try context.save()

        _ = shift.profitability(for: route(miles: 50))
        _ = shift.fuelEstimate(for: route(miles: 50))

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1, "Nothing was created")
        #expect(expenses.first?.amount == Money(minorUnits: 4_210), "And nothing was changed")
        #expect(expenses.first?.category == .fuel)
        #expect(context.hasChanges == false, "Deriving a figure writes nothing at all")
    }

    @Test("Net after recorded expenses stays a period figure, and the two nets are different statements")
    func netAfterExpensesRemainsAPeriodFigure() throws {
        let context = try makeContext()
        let shift = try shift(in: context)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))

        let purchase = try Expense(occurredAt: start.addingTimeInterval(1_800), amount: Money(minorUnits: 4_210), category: .fuel)
        context.insert(purchase)
        try context.save()

        let metrics = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: route(miles: 50))],
            expenses: [purchase.expenseRecord],
            in: period
        )

        // The period nets the **recorded** expense against the **recorded**
        // earnings, which is the figure that has always existed.
        #expect(metrics.netAfterRecordedExpenses.amount == Money(minorUnits: 5_790), "$100.00 less $42.10")

        // The shift nets the **estimated** fuel against the same earnings, and
        // the two are deliberately different numbers about different things.
        #expect(shift.profitability(for: route(miles: 50)).estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)))
    }

    // MARK: Wording

    @Test("Every reason has a sentence, and none of them implies the missing figure is zero")
    func everyReasonExplainsItself() {
        for reason in EstimatedNetUnavailability.allCases {
            let explanation = reason.explanation
            #expect(!explanation.isEmpty)
            #expect(!explanation.contains("$0"))
            #expect(!explanation.lowercased().contains("zero"))
        }
    }

    @Test("Nothing about an estimated net calls itself profit, take-home or deductible")
    func nothingClaimsAccountingProfit() {
        for reason in EstimatedNetUnavailability.allCases {
            let lowered = reason.explanation.lowercased()
            #expect(!lowered.contains("profit"))
            #expect(!lowered.contains("take-home"))
            #expect(!lowered.contains("deduct"))
            #expect(!lowered.contains("tax"))
        }
    }

    // MARK: A partial route makes the net a ceiling

    @Test("A partial route is carried into the net, where it means the opposite of what it means for fuel")
    func partialRouteIsCarriedIntoTheNet() throws {
        let context = try makeContext()
        let shift = try shift(in: context)

        let profitability = shift.profitability(for: route(miles: 50, gaps: 2))

        #expect(profitability.isRoutePartial)
        #expect(
            profitability.estimatedNetAfterFuel == .available(Money(minorUnits: 9_300)),
            "The figure is over the miles that were recorded; the caveat says what that means"
        )
    }
}
