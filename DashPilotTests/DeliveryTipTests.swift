import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Tips a delivery received outside what the platform recorded paying for it:
/// the row's own rules, and the arithmetic that turns them plus a platform
/// amount into what the delivery actually paid.
///
/// The claims this suite exists for are a pair. **Several tips stay several
/// facts**: two tips on one delivery are two events with two methods, and
/// nothing collapses them into one mutable figure. And **a missing platform
/// amount has no total**: a delivery carrying a tip and no recorded pay earned
/// the tip plus an amount nobody wrote down, so there is no effective figure to
/// state and none is invented.
///
/// Every amount and timestamp is invented.
@MainActor
@Suite("Delivery additional tips")
struct DeliveryTipTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// One finished delivery in an in-memory store, with no money on it.
    private func deliveredDelivery(
        gross: Money? = nil
    ) throws -> (context: ModelContext, delivery: Delivery) {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let shift = Shift(startedAt: start)
        context.insert(shift)
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(1_020))
        try delivery.markDelivered(at: at(1_800))
        try shift.end(at: at(7_200))
        if let gross { try delivery.setGrossEarnings(gross) }
        try context.save()

        return (context, delivery)
    }

    @discardableResult
    private func record(
        _ minorUnits: Int,
        _ method: DeliveryTipMethod,
        at seconds: TimeInterval,
        on delivery: Delivery,
        in context: ModelContext
    ) throws -> DeliveryTip {
        let tip = try delivery.recordAdditionalTip(Money(minorUnits: minorUnits), method: method, at: at(seconds))
        context.insert(tip)
        try context.save()
        return tip
    }

    // MARK: The arithmetic

    @Test("Platform pay with no tips is what the delivery paid, to the cent")
    func platformPayAloneIsTheTotal() {
        let earnings = EffectiveDeliveryEarnings(platformPay: Money(exact: "10.00"))

        #expect(earnings.amount == Money(exact: "10.00"))
        #expect(!earnings.hasAdditionalTips)
        #expect(earnings.additionalTipCount == 0)
        #expect(
            earnings.additionalTipsTotal == nil,
            "No tip recorded is not a tip of nothing, so there is no total of them"
        )
        #expect(earnings.isRecorded)
    }

    @Test("A cash tip is added to the platform's own amount")
    func cashTipIsAdded() {
        let earnings = EffectiveDeliveryEarnings(
            platformPay: Money(exact: "10.00"),
            additionalTips: [Money(exact: "5.00")!]
        )

        #expect(earnings.amount == Money(exact: "15.00"))
        #expect(earnings.additionalTipsTotal == Money(exact: "5.00"))
        #expect(earnings.additionalTipCount == 1)
    }

    @Test("Two tips are two facts, and the total is both of them")
    func twoTipsAreAdded() {
        let earnings = EffectiveDeliveryEarnings(
            platformPay: Money(exact: "10.00"),
            additionalTips: [Money(exact: "3.00")!, Money(exact: "5.00")!]
        )

        #expect(earnings.amount == Money(exact: "18.00"))
        #expect(earnings.additionalTipsTotal == Money(exact: "8.00"))
        #expect(earnings.additionalTipCount == 2)
        #expect(earnings.additionalTips == [Money(exact: "3.00"), Money(exact: "5.00")])
    }

    /// The arithmetic is `Decimal` throughout, so amounts that a binary float
    /// cannot hold exactly survive being added.
    @Test("Tenths and cents add exactly, with no floating point anywhere")
    func amountsAddExactly() {
        let earnings = EffectiveDeliveryEarnings(
            platformPay: Money(exact: "10.10"),
            additionalTips: [Money(exact: "0.20")!, Money(exact: "0.30")!]
        )

        #expect(earnings.amount == Money(exact: "10.60"))
        #expect(earnings.amount?.formatted(locale: Locale(identifier: "en_US")) == "$10.60")
    }

    @Test("A recorded zero platform amount is a real numerator and the tips add to it")
    func zeroPlatformPayIsRecorded() {
        let earnings = EffectiveDeliveryEarnings(
            platformPay: .zero,
            additionalTips: [Money(exact: "4.00")!]
        )

        #expect(earnings.amount == Money(exact: "4.00"), "Recorded as paying nothing, plus a tip that arrived")
        #expect(earnings.isRecorded, "A recorded zero is a figure the driver typed, not an absence")
    }

    // MARK: The missing half

    @Test("A tip with no platform amount beside it has no total, and the tip is not it")
    func missingPlatformPayHasNoTotal() {
        let earnings = EffectiveDeliveryEarnings(
            platformPay: nil,
            additionalTips: [Money(exact: "5.00")!]
        )

        #expect(earnings.amount == nil, "The delivery paid the tip plus an amount nobody wrote down")
        #expect(!earnings.isRecorded)
        #expect(earnings.additionalTipsTotal == Money(exact: "5.00"), "What was recorded is still stated")
        #expect(earnings.hasAdditionalTips)
    }

    @Test("A delivery with neither has neither, and nothing is zero")
    func nothingRecorded() {
        let earnings = EffectiveDeliveryEarnings(platformPay: nil)

        #expect(earnings.amount == nil)
        #expect(earnings.additionalTipsTotal == nil)
        #expect(!earnings.hasAdditionalTips)
    }

    // MARK: The row's own rules

    @Test("A tip has to be more than nothing")
    func zeroIsRefused() throws {
        let (_, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))

        #expect(throws: DeliveryTipError.amountNotPositive) {
            _ = try delivery.recordAdditionalTip(.zero, method: .cash, at: at(1_900))
        }
        #expect(throws: DeliveryTipError.amountNotPositive) {
            _ = try delivery.recordAdditionalTip(Money(exact: "-1.00")!, method: .cash, at: at(1_900))
        }
        #expect(delivery.additionalTips.isEmpty, "Nothing was recorded by either refusal")
    }

    /// The asymmetry with a gross amount is deliberate: a recorded `$0.00`
    /// gross says the delivery paid nothing, and a `$0.00` tip says nothing at
    /// all.
    @Test("A recorded gross of zero is still allowed, which a tip of zero is not")
    func zeroGrossIsStillAllowed() throws {
        let (_, delivery) = try deliveredDelivery()

        try delivery.setGrossEarnings(.zero)
        #expect(delivery.grossEarnings == Money.zero)
        #expect(throws: DeliveryTipError.amountNotPositive) {
            _ = try delivery.recordAdditionalTip(.zero, method: .platform, at: at(1_900))
        }
    }

    @Test("A delivery still in progress cannot receive one")
    func activeDeliveryIsRefused() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(600))

        #expect(throws: DeliveryTipError.deliveryNotFinished) {
            _ = try delivery.recordAdditionalTip(Money(exact: "5.00")!, method: .cash, at: at(700))
        }
    }

    /// A customer waiting when an order falls through can still have handed
    /// over cash, and refusing to record it would make the driver attribute it
    /// somewhere it did not happen.
    @Test("A cancelled delivery can receive one")
    func cancelledDeliveryIsAllowed() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.cancel(at: at(900))

        let tip = try delivery.recordAdditionalTip(Money(exact: "4.00")!, method: .cash, at: at(1_000))
        context.insert(tip)

        #expect(delivery.additionalTips.count == 1)
        #expect(delivery.state == .cancelled)
    }

    @Test("Correcting a tip replaces its amount and method and moves no timestamp")
    func correctionKeepsTheMoment() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))
        let tip = try record(300, .cash, at: 1_900, on: delivery, in: context)

        try tip.update(amount: Money(exact: "4.50")!, method: .platform)

        #expect(tip.amount == Money(exact: "4.50"))
        #expect(tip.method == .platform)
        #expect(tip.recordedAt == at(1_900), "Correcting what a tip was says nothing about when it was recorded")
        #expect(delivery.effectiveEarnings.amount == Money(exact: "14.50"))
    }

    @Test("A correction to nothing is refused and writes neither value")
    func correctionToZeroIsRefused() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))
        let tip = try record(300, .cash, at: 1_900, on: delivery, in: context)

        #expect(throws: DeliveryTipError.amountNotPositive) {
            try tip.update(amount: .zero, method: .platform)
        }
        #expect(tip.amount == Money(exact: "3.00"), "The refusal happens before either value is written")
        #expect(tip.method == .cash)
    }

    // MARK: Several tips on one delivery

    @Test("Two tips of different methods are both recorded, and both count")
    func twoMethodsOnOneDelivery() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))

        try record(300, .cash, at: 1_900, on: delivery, in: context)
        try record(500, .platform, at: 5_400, on: delivery, in: context)

        let tips = delivery.additionalTipsInOrder
        #expect(tips.count == 2)
        #expect(tips.map(\.method) == [.cash, .platform])
        #expect(tips.map(\.amount) == [Money(exact: "3.00"), Money(exact: "5.00")])
        #expect(delivery.effectiveEarnings.amount == Money(exact: "18.00"))
    }

    @Test("Two tips of the same amount stay two records rather than one doubled one")
    func identicalTipsStayDistinct() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))

        let first = try record(500, .cash, at: 1_900, on: delivery, in: context)
        let second = try record(500, .cash, at: 5_400, on: delivery, in: context)

        #expect(first.id != second.id)
        #expect(delivery.additionalTips.count == 2)
        #expect(delivery.effectiveEarnings.amount == Money(exact: "20.00"))
    }

    @Test("Tips are read oldest first, whatever order the relationship returns them in")
    func tipsAreOrdered() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))

        try record(500, .platform, at: 5_400, on: delivery, in: context)
        try record(300, .cash, at: 1_900, on: delivery, in: context)

        #expect(delivery.additionalTipsInOrder.map(\.recordedAt) == [at(1_900), at(5_400)])
    }

    // MARK: What a tip is not

    @Test("Recording a tip never touches what the platform paid")
    func platformPayIsUntouched() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))

        try record(500, .cash, at: 1_900, on: delivery, in: context)

        #expect(delivery.grossEarnings == Money(exact: "10.00"), "The stored amount is exactly what was typed")
        #expect(
            delivery.effectiveEarnings.platformPay == Money(exact: "10.00"),
            "And the total is derived from it rather than replacing it"
        )
    }

    /// The double-counting case, stated as arithmetic. A driver who correctly
    /// leaves a platform-included tip inside the recorded amount and a driver
    /// who records it again reach different totals, and only the first is right.
    @Test("A tip already inside the platform amount is not recorded twice by the app")
    func noDoubleCounting() throws {
        let (_, included) = try deliveredDelivery(gross: Money(exact: "15.00"))
        #expect(
            included.effectiveEarnings.amount == Money(exact: "15.00"),
            "A platform amount that already contains its tip is the whole of what the delivery paid"
        )

        let (context, separate) = try deliveredDelivery(gross: Money(exact: "10.00"))
        try record(500, .cash, at: 1_900, on: separate, in: context)
        #expect(
            separate.effectiveEarnings.amount == Money(exact: "15.00"),
            "And a tip that reached the driver outside it reaches the same total once"
        )
    }

    @Test("An expectation is untouched by a tip, and enters none of the arithmetic")
    func expectedPayIsIndependent() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.setExpectedEarnings(Money(exact: "8.50")!)
        try delivery.markPickedUp(at: at(1_020))
        try delivery.markDelivered(at: at(1_800))
        try delivery.setGrossEarnings(Money(exact: "10.00")!)

        try record(500, .cash, at: 1_900, on: delivery, in: context)

        #expect(delivery.expectedEarnings == Money(exact: "8.50"), "Still exactly what was expected")
        #expect(delivery.effectiveEarnings.amount == Money(exact: "15.00"), "And no part of the total")
        #expect(
            !delivery.hasUnconfirmedExpectedEarnings,
            "The gross is what resolves an expectation; a tip neither confirms nor consumes one"
        )
    }

    @Test("Removing the platform amount leaves the tips and takes the total away")
    func removingPlatformPayRemovesTheTotal() throws {
        let (context, delivery) = try deliveredDelivery(gross: Money(exact: "10.00"))
        try record(500, .cash, at: 1_900, on: delivery, in: context)

        delivery.clearGrossEarnings()

        #expect(delivery.additionalTips.count == 1, "The tip is its own recorded fact")
        #expect(delivery.effectiveEarnings.amount == nil, "And there is no longer a total to state")
        #expect(delivery.effectiveEarnings.additionalTipsTotal == Money(exact: "5.00"))
        #expect(delivery.hasRecordedMoney, "Money is still recorded against it")
    }

    @Test("A delivery holding only tips still counts as holding recorded money")
    func hasRecordedMoney() throws {
        let (context, delivery) = try deliveredDelivery()
        #expect(!delivery.hasRecordedMoney)

        try record(500, .cash, at: 1_900, on: delivery, in: context)
        #expect(delivery.hasRecordedMoney)
    }

    // MARK: The method

    @Test("A stored method this build cannot name reads as no method, and the amount still counts")
    func unknownMethodReadsAsAbsent() {
        #expect(DeliveryTipMethod.stored("cash") == .cash)
        #expect(DeliveryTipMethod.stored("platform") == .platform)
        #expect(
            DeliveryTipMethod.stored("voucher") == nil,
            "Both cases are substantive claims, so neither may stand in for a word this build does not know"
        )
    }

    @Test("Every method says what it is, and only the platform one warns about double counting")
    func methodWording() {
        #expect(DeliveryTipMethod.allCases.count == 2)
        for method in DeliveryTipMethod.allCases {
            #expect(!method.title.isEmpty)
            #expect(method.spokenTitle == method.title.lowercased())
            #expect(!method.explanation.isEmpty)
        }
        #expect(
            DeliveryTipMethod.platform.explanation.lowercased().contains("only record it here if it is not already"),
            "The platform sentence is where the double-counting warning lives"
        )
        #expect(DeliveryTipMethod.cash.explanation.lowercased().contains("not part of what the platform recorded"))
    }

    // MARK: Wording

    @Test("A tip typed as a negative is refused in the words of a tip")
    func moneyInputSubjectNamesTheTip() {
        #expect(MoneyInputError.negative.message(for: .additionalTip) == "A tip cannot be a negative amount. Enter what you received.")
        #expect(
            MoneyInputError.negative.message(for: .additionalTip)
                != MoneyInputError.negative.message(for: .grossEarnings),
            "A driver typing a tip is not recording gross earnings and must not be told they are"
        )
        #expect(MoneyInputError.empty.message(for: .additionalTip).contains("tip"))
    }

    @Test("The row's spoken sentences name the delivery and say what the figure is not")
    func spokenWording() {
        let (_, delivery) = try! deliveredDelivery(gross: Money(exact: "10.00"))
        let numbered = NumberedDelivery(number: 2, delivery: delivery)

        #expect(numbered.spokenPlatformPayBesideTips("$10.00").contains("Delivery 2"))
        #expect(
            numbered.spokenPlatformPayBesideTips("$10.00").contains("not the whole of what it paid"),
            "A listener has no rows to compare, so the sentence has to say this is one half"
        )
        #expect(numbered.spokenAdditionalTips("$5.00", tipCount: 1).contains("1 additional tip"))
        #expect(numbered.spokenAdditionalTips("$8.00", tipCount: 2).contains("2 additional tips"))
        #expect(numbered.spokenEffectiveEarnings("$18.00").contains("platform pay and tips together"))
        #expect(numbered.spokenNoPlatformPayBesideTips.contains("no total"))
        #expect(numbered.additionalTipsActionTitle(hasTips: false) == "Add a Tip")
        #expect(numbered.additionalTipsActionTitle(hasTips: true) == "Edit Tips")
        #expect(numbered.spokenAdditionalTipsLabel(tipCount: 0) == "Add an additional tip to Delivery 2")
        #expect(numbered.spokenAdditionalTipsLabel(tipCount: 2).contains("2 additional tips"))
    }

    @Test("A tip whose method cannot be named is spoken as one, rather than as either method")
    func spokenTipWithoutAMethod() {
        let spoken = NumberedDelivery.spokenTip(number: 1, amount: "$5.00", method: nil, recordedAt: "7:42 PM")

        #expect(spoken.contains("no method recorded"))
        #expect(!spoken.lowercased().contains("cash"))
        #expect(!spoken.lowercased().contains("platform"))
    }

    /// Nothing on any tip surface may call the figure profit, take-home or a
    /// wage: it is gross of every cost, exactly as the platform amount is.
    @Test("No tip sentence claims anything about profit or take-home pay")
    func wordingClaimsNothing() {
        let (_, delivery) = try! deliveredDelivery(gross: Money(exact: "10.00"))
        let numbered = NumberedDelivery(number: 1, delivery: delivery)

        let sentences = [
            numbered.spokenPlatformPayBesideTips("$10.00"),
            numbered.spokenAdditionalTips("$5.00", tipCount: 1),
            numbered.spokenEffectiveEarnings("$15.00"),
            numbered.spokenNoPlatformPayBesideTips,
            DeliveryTipMethod.cash.explanation,
            DeliveryTipMethod.platform.explanation
        ]

        for sentence in sentences {
            let lowered = sentence.lowercased()
            for forbidden in ["profit", "take-home", "wage", "deductible", "net "] {
                #expect(!lowered.contains(forbidden), "\(forbidden) appeared in: \(sentence)")
            }
        }
    }
}
