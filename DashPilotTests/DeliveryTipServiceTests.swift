import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedTipSave: Error {}

/// The writes behind an additional tip: recording one, correcting one, removing
/// one, and what each leaves behind when the store refuses.
///
/// The claim every rollback test here makes is the one a driver depends on:
/// **the interface never shows money the store does not hold.** A refused save
/// discards the whole operation, and the authoritative state is read back
/// through a **fresh context**, because a context that has rolled back may still
/// be holding relationship caches from before it.
///
/// Every amount and timestamp is invented.
@MainActor
@Suite("Delivery additional tip service")
struct DeliveryTipServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    /// One finished shift holding one delivered delivery that records `$10.00`.
    @discardableResult
    private func deliveredDelivery(
        in context: ModelContext,
        gross: Money? = Money(exact: "10.00")
    ) throws -> Delivery {
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
        return delivery
    }

    private func refusingService(_ context: ModelContext) -> DeliveryService {
        DeliveryService(context: context, commit: { _ in throw RefusedTipSave() })
    }

    // MARK: Recording

    @Test("Recording a tip stores it and leaves the platform amount exactly as it was")
    func recordsATip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)

        let tip = try DeliveryService(context: context)
            .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        #expect(tip.amount == Money(exact: "5.00"))
        #expect(tip.method == .cash)
        #expect(tip.recordedAt == at(1_900))
        #expect(tip.delivery?.id == delivery.id)

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<DeliveryTip>()).first)
        #expect(stored.amount == Money(exact: "5.00"))
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.grossEarnings == Money(exact: "10.00"))
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "15.00"))
    }

    @Test("Two tips on one delivery are two stored rows")
    func recordsSeveralTips() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)

        try service.addAdditionalTip(Money(exact: "3.00")!, method: .cash, on: delivery, at: at(1_900))
        try service.addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(5_400))

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<DeliveryTip>()).count == 2)
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "18.00"))
        #expect(storedDelivery.additionalTipsInOrder.map(\.method) == [.cash, .platform])
    }

    @Test("An amount of nothing is refused, and nothing is written")
    func refusesANonPositiveAmount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)

        #expect(throws: DeliveryLifecycleError.invalidTip(.amountNotPositive)) {
            try DeliveryService(context: context)
                .addAdditionalTip(.zero, method: .cash, on: delivery, at: at(1_900))
        }

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<DeliveryTip>()).isEmpty)
    }

    @Test("A delivery still in progress is refused, and the sentence says when one can be recorded")
    func refusesAnActiveDelivery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let shift = Shift(startedAt: start)
        context.insert(shift)
        let recorded = try shift.beginOffer(deliveryCount: 1, at: at(300))
        context.insert(recorded.offer)
        let delivery = recorded.deliveries[0]
        context.insert(delivery)
        try context.save()

        #expect(throws: DeliveryLifecycleError.invalidTip(.deliveryNotFinished)) {
            try DeliveryService(context: context)
                .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(400))
        }

        let sentence = DeliveryLifecycleError.invalidTip(.deliveryNotFinished).errorDescription
        #expect(sentence?.contains("delivered or cancelled") == true)
    }

    /// Recording an amount is the one delivery write that does not need a
    /// running shift, and a tip is recorded the same way: it is a review action
    /// performed from a finished shift's history.
    @Test("A finished shift is where a tip is recorded, and that is not a refusal")
    func recordsOnAFinishedShift() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        #expect(delivery.shift?.isActive == false)

        try DeliveryService(context: context)
            .addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(9_000))

        #expect(delivery.additionalTips.count == 1)
    }

    @Test("A refused save leaves no tip in the store and none on the delivery")
    func recordingRollsBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedTipSave())) {
            try refusingService(context)
                .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))
        }

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<DeliveryTip>()).isEmpty, "Read back through a fresh context")
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.additionalTips.isEmpty)
        #expect(
            storedDelivery.effectiveEarnings.amount == Money(exact: "10.00"),
            "And the total is still what the platform amount alone says"
        )
    }

    // MARK: Correcting

    @Test("Correcting a tip replaces its amount and method, and moves nothing else")
    func correctsATip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)
        let tip = try service.addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        try service.updateAdditionalTip(tip, amount: Money(exact: "6.50")!, method: .platform)

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<DeliveryTip>()).first)
        #expect(stored.amount == Money(exact: "6.50"))
        #expect(stored.method == .platform)
        #expect(stored.recordedAt == at(1_900), "The moment it was recorded is not a thing a correction rewrites")
        #expect(stored.id == tip.id, "Correcting a tip is not deleting one and recording another")

        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.grossEarnings == Money(exact: "10.00"))
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "16.50"))
    }

    @Test("Correcting one tip leaves its siblings exactly as they are")
    func correctionLeavesSiblingsAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)
        let first = try service.addAdditionalTip(Money(exact: "3.00")!, method: .cash, on: delivery, at: at(1_900))
        try service.addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(5_400))

        try service.updateAdditionalTip(first, amount: Money(exact: "4.00")!, method: .cash)

        let fresh = ModelContext(container)
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        let tips = storedDelivery.additionalTipsInOrder
        #expect(tips.map(\.amount) == [Money(exact: "4.00"), Money(exact: "5.00")])
        #expect(tips.map(\.method) == [.cash, .platform])
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "19.00"))
    }

    @Test("A refused correction leaves the tip exactly as the store already held it")
    func correctionRollsBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let tip = try DeliveryService(context: context)
            .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedTipSave())) {
            try refusingService(context).updateAdditionalTip(tip, amount: Money(exact: "99.00")!, method: .platform)
        }

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<DeliveryTip>()).first)
        #expect(stored.amount == Money(exact: "5.00"))
        #expect(stored.method == .cash)
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "15.00"))
    }

    // MARK: Removing

    @Test("Removing a tip takes the row away and leaves the platform amount alone")
    func deletesATip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)
        let tip = try service.addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        try service.deleteAdditionalTip(tip)

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<DeliveryTip>()).isEmpty, "The row is gone rather than zeroed")
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.grossEarnings == Money(exact: "10.00"))
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "10.00"))
        #expect(!storedDelivery.effectiveEarnings.hasAdditionalTips)
    }

    @Test("Removing one of two leaves the other and its own contribution")
    func deletesOneOfTwo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)
        let first = try service.addAdditionalTip(Money(exact: "3.00")!, method: .cash, on: delivery, at: at(1_900))
        try service.addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(5_400))

        try service.deleteAdditionalTip(first)

        let fresh = ModelContext(container)
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.additionalTipsInOrder.map(\.amount) == [Money(exact: "5.00")])
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "15.00"))
    }

    @Test("A refused removal leaves the tip where it was")
    func deletionRollsBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let tip = try DeliveryService(context: context)
            .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedTipSave())) {
            try refusingService(context).deleteAdditionalTip(tip)
        }

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<DeliveryTip>()).first)
        #expect(stored.amount == Money(exact: "5.00"))
        let storedDelivery = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(storedDelivery.effectiveEarnings.amount == Money(exact: "15.00"))
    }

    // MARK: Cascade

    @Test("Deleting the shift takes its deliveries' tips with it, leaving no orphan")
    func deletingAShiftRemovesItsTips() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let shift = try #require(delivery.shift)
        try DeliveryService(context: context)
            .addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))

        try ShiftService(context: context).deleteCompletedShift(shift)

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<Shift>()).isEmpty)
        #expect(try fresh.fetch(FetchDescriptor<Delivery>()).isEmpty)
        #expect(
            try fresh.fetch(FetchDescriptor<DeliveryTip>()).isEmpty,
            "A tip means nothing apart from the delivery it was recorded against"
        )
    }

    // MARK: What a correction to the delivery leaves alone

    @Test("Reopening a delivery marked delivered by mistake keeps every tip on it")
    func reopeningKeepsTips() throws {
        let container = try makeContainer()
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
        try delivery.setGrossEarnings(Money(exact: "10.00")!)
        try context.save()

        let service = DeliveryService(context: context)
        try service.addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))
        try service.reopenDelivered(delivery)

        #expect(delivery.state == .pickedUp)
        #expect(
            delivery.additionalTips.count == 1,
            "Removing money on the app's own authority is the one thing a mis-tap recovery must not do"
        )
        #expect(delivery.grossEarnings == Money(exact: "10.00"))
    }

    @Test("Correcting a historical completion to a cancellation keeps every tip on it")
    func historicalCancellationKeepsTips() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let delivery = try deliveredDelivery(in: context)
        let service = DeliveryService(context: context)
        try service.addAdditionalTip(Money(exact: "5.00")!, method: .platform, on: delivery, at: at(1_900))

        try service.correctCompletionToCancellation(delivery)

        #expect(delivery.state == .cancelled)
        #expect(delivery.additionalTips.count == 1)
        #expect(delivery.effectiveEarnings.amount == Money(exact: "15.00"))
    }

    /// A tip already recorded is money that already arrived, so a delivery
    /// reopened from a mistaken completion must still let the driver fix a typo
    /// in one. The finished-delivery rule is about **creating** a tip.
    @Test("An existing tip can be corrected on a delivery that has been reopened")
    func correctsATipOnAReopenedDelivery() throws {
        let container = try makeContainer()
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
        try context.save()

        let service = DeliveryService(context: context)
        let tip = try service.addAdditionalTip(Money(exact: "5.00")!, method: .cash, on: delivery, at: at(1_900))
        try service.reopenDelivered(delivery)

        try service.updateAdditionalTip(tip, amount: Money(exact: "6.00")!, method: .cash)
        #expect(tip.amount == Money(exact: "6.00"))

        #expect(throws: DeliveryLifecycleError.invalidTip(.deliveryNotFinished)) {
            try service.addAdditionalTip(Money(exact: "2.00")!, method: .cash, on: delivery, at: at(2_000))
        }
    }
}
