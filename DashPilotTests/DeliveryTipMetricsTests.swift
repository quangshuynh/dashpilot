import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What moves once a delivery can hold tips, and what deliberately does not.
///
/// Two claims, and the second is the one that keeps the figures honest.
///
/// **Where the product means what a delivery actually paid, it reads effective
/// earnings**: the delivery's own hourly figure, the shift's list of recorded
/// delivery amounts, and the period's delivery-earnings subtotal.
///
/// **Coverage does not move.** A delivery contributes when its *platform* amount
/// was recorded. A tip widens what a contributing delivery contributes and never
/// turns a delivery with no platform amount into one that is covered, because
/// such a delivery paid the tip plus an amount nobody wrote down.
///
/// Every amount and timestamp is invented.
@MainActor
@Suite("Delivery tip metrics")
struct DeliveryTipMetricsTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A calendar pinned to UTC, so which day a fixture's shift falls on is a
    /// property of the fixture rather than of the machine's region.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// One finished shift whose deliveries are described by `(gross, tips)`
    /// pairs, each delivered and 1,800 seconds long.
    private func shift(
        in context: ModelContext,
        gross shiftGross: Money? = nil,
        deliveries descriptions: [(gross: Money?, tips: [(Money, DeliveryTipMethod)])]
    ) throws -> Shift {
        let shift = Shift(startedAt: start)
        context.insert(shift)

        for (index, description) in descriptions.enumerated() {
            let accepted = at(Double(index) * 3_600 + 300)
            let recorded = try shift.beginOffer(deliveryCount: 1, at: accepted)
            context.insert(recorded.offer)
            let delivery = recorded.deliveries[0]
            context.insert(delivery)
            try delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(300))
            try delivery.markPickedUp(at: accepted.addingTimeInterval(600))
            try delivery.markDelivered(at: accepted.addingTimeInterval(1_800))
            if let gross = description.gross { try delivery.setGrossEarnings(gross) }
            for (amount, method) in description.tips {
                let tip = try delivery.recordAdditionalTip(amount, method: method, at: accepted.addingTimeInterval(2_000))
                context.insert(tip)
            }
        }

        try shift.end(at: at(4 * 3_600))
        if let shiftGross { try shift.setGrossEarnings(shiftGross) }
        try context.save()
        return shift
    }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: The delivery's own rate

    @Test("The delivery's hourly figure divides what it actually paid")
    func rateUsesEffectiveEarnings() throws {
        let context = try context()
        // 1,800 seconds is half an hour, so $10.00 plus $5.00 over it is $30.00
        // an hour, against the $20.00 the platform amount alone would give.
        let shift = try shift(
            in: context,
            deliveries: [(gross: Money(exact: "10.00"), tips: [(Money(exact: "5.00")!, .cash)])]
        )
        let delivery = try #require(shift.deliveriesInOrder.first)

        #expect(delivery.effectiveEarningsPerDeliveryHour.amount == Money(exact: "30.00"))
        #expect(
            ShiftMetricsCalculator.grossPerHour(of: Money(exact: "10.00")!, over: 1_800) == Money(exact: "20.00"),
            "Which is visibly not the figure the platform amount alone produces"
        )
    }

    @Test("A delivery with tips and no platform amount has no rate, rather than a smaller one")
    func rateNeedsThePlatformAmount() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            deliveries: [(gross: nil, tips: [(Money(exact: "5.00")!, .cash)])]
        )
        let delivery = try #require(shift.deliveriesInOrder.first)

        #expect(delivery.effectiveEarningsPerDeliveryHour.amount == nil)
        #expect(delivery.effectiveEarningsPerDeliveryHour.unavailability == .earningsNotRecorded)
        #expect(
            DeliveryRateUnavailability.earningsNotRecorded.explanation.contains("platform"),
            "And the sentence says which half is missing"
        )
    }

    @Test("A delivery with no tips keeps exactly the rate it always had")
    func rateIsUnmovedWithoutTips() throws {
        let context = try context()
        let shift = try shift(in: context, deliveries: [(gross: Money(exact: "10.00"), tips: [])])
        let delivery = try #require(shift.deliveriesInOrder.first)

        #expect(delivery.effectiveEarningsPerDeliveryHour.amount == Money(exact: "20.00"))
    }

    // MARK: The shift's own list

    @Test("A shift's recorded delivery amounts are what its deliveries actually paid")
    func shiftRecordUsesEffectiveEarnings() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            gross: Money(exact: "100.00"),
            deliveries: [
                (gross: Money(exact: "10.00"), tips: [(Money(exact: "3.00")!, .cash), (Money(exact: "5.00")!, .platform)]),
                (gross: Money(exact: "9.00"), tips: [])
            ]
        )

        let record = shift.periodRecord(for: .none)
        #expect(record.recordedDeliveryEarnings == [Money(exact: "18.00")!, Money(exact: "9.00")!])
        #expect(record.terminalDeliveryCount == 2)
        #expect(
            record.grossEarnings == Money(exact: "100.00"),
            "The shift's own amount is a separate fact and nothing adds a tip to it"
        )
    }

    /// The rule `AGENTS.md` states about earnings, checked at the one place a
    /// tip could have leaked into it.
    @Test("A tip changes no shift rate, because those divide the shift's own amount")
    func shiftRatesAreUntouched() throws {
        let context = try context()
        let withoutTips = try shift(
            in: context,
            gross: Money(exact: "100.00"),
            deliveries: [(gross: Money(exact: "10.00"), tips: [])]
        )
        let before = withoutTips.metrics(for: .none)

        let delivery = try #require(withoutTips.deliveriesInOrder.first)
        let tip = try delivery.recordAdditionalTip(Money(exact: "5.00")!, method: .cash, at: at(2_500))
        context.insert(tip)
        try context.save()

        let after = withoutTips.metrics(for: .none)
        #expect(after.grossEarnings == before.grossEarnings)
        #expect(after.grossPerWorkingHour.amount == before.grossPerWorkingHour.amount)
        #expect(after.grossPerDeliveryActiveHour.amount == before.grossPerDeliveryActiveHour.amount)
    }

    // MARK: The period

    @Test("The period's delivery subtotal adds up what its deliveries actually paid")
    func periodSubtotalUsesEffectiveEarnings() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            gross: Money(exact: "100.00"),
            deliveries: [
                (gross: Money(exact: "10.00"), tips: [(Money(exact: "5.00")!, .cash)]),
                (gross: Money(exact: "9.00"), tips: [(Money(exact: "1.50")!, .platform)])
            ]
        )

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        #expect(metrics.recordedDeliveryEarnings == Money(exact: "25.50"))
        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
        #expect(
            metrics.recordedGrossEarnings == Money(exact: "100.00"),
            "The period's headline earnings are still the shift amount, untouched by any of this"
        )
    }

    @Test("Tips across two shifts add into one period subtotal")
    func periodAggregatesAcrossShifts() throws {
        let context = try context()
        let first = try shift(
            in: context,
            deliveries: [(gross: Money(exact: "10.00"), tips: [(Money(exact: "5.00")!, .cash)])]
        )

        let second = Shift(startedAt: at(5 * 3_600))
        context.insert(second)
        let recorded = try second.beginOffer(deliveryCount: 1, at: at(5 * 3_600 + 300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(5 * 3_600 + 600))
        try delivery.markPickedUp(at: at(5 * 3_600 + 900))
        try delivery.markDelivered(at: at(5 * 3_600 + 1_800))
        try delivery.setGrossEarnings(Money(exact: "8.00")!)
        let tip = try delivery.recordAdditionalTip(Money(exact: "2.00")!, method: .platform, at: at(5 * 3_600 + 2_000))
        context.insert(tip)
        try second.end(at: at(7 * 3_600))
        try context.save()

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(
            of: [first.periodRecord(for: .none), second.periodRecord(for: .none)],
            in: period
        )

        #expect(metrics.recordedDeliveryEarnings == Money(exact: "25.00"))
        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 2, eligibleCount: 2))
    }

    // MARK: Coverage when the platform amount is missing

    @Test("A delivery holding only tips stays uncovered and adds nothing to the subtotal")
    func tipsAloneDoNotCover() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            deliveries: [
                (gross: Money(exact: "10.00"), tips: []),
                (gross: nil, tips: [(Money(exact: "5.00")!, .cash)])
            ]
        )

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        #expect(
            metrics.recordedDeliveryEarnings == Money(exact: "10.00"),
            "The tip is real and the delivery's total is not, so the subtotal takes neither"
        )
        #expect(
            metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2),
            "1 of 2, which is what it was before tips existed and for the same reason"
        )
        #expect(!metrics.deliveryEarningsCoverage.isComplete)
    }

    @Test("Coverage over a delivery with no money at all is what it always was")
    func coverageIsUnmovedWithoutTips() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            deliveries: [(gross: Money(exact: "10.00"), tips: []), (gross: nil, tips: [])]
        )

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        #expect(metrics.recordedDeliveryEarnings == Money(exact: "10.00"))
        #expect(metrics.deliveryEarningsCoverage == MetricCoverage(contributingCount: 1, eligibleCount: 2))
    }

    /// The subtotal's own sentence is unchanged, and still never calls itself
    /// the period's earnings.
    @Test("The subtotal is still stated as a subtotal across deliveries")
    func subtotalWordingIsUnchanged() throws {
        let context = try context()
        let shift = try shift(
            in: context,
            deliveries: [(gross: Money(exact: "10.00"), tips: [(Money(exact: "5.00")!, .cash)])]
        )

        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)
        let statement = try #require(metrics.deliveryEarningsStatement(locale: Locale(identifier: "en_US")))

        #expect(statement.contains("$15.00"))
        #expect(statement.contains("1 of 1 delivery"))

        let spoken = try #require(metrics.spokenDeliveryEarningsStatement(locale: Locale(identifier: "en_US")))
        #expect(spoken.contains("separate record from the shift amounts above"))
    }
}
