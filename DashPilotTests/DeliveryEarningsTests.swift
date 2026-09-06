import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Errors substituted for a real save, so what a refused write leaves behind can
/// be asserted.
private struct RefusedSave: Error {}

/// A store, a shift and the deliveries every earnings test is written over.
///
/// Built through the real services rather than by inserting rows, so the rules
/// under test are the ones a driver's taps would go through.
@MainActor
private struct EarningsFixture {
    let container: ModelContainer
    let context: ModelContext
    let shifts: ShiftService
    let deliveries: DeliveryService
    let shift: Shift
    let start: Date

    /// `commit` substitutes for `ModelContext.save()`, which is the only way to
    /// exercise what a refused save leaves behind.
    init(
        start: Date = Date(timeIntervalSince1970: 1_756_000_000),
        commit: ((ModelContext) throws -> Void)? = nil
    ) throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        self.context = context
        self.start = start
        shifts = ShiftService(context: context)
        deliveries = commit.map { DeliveryService(context: context, commit: $0) }
            ?? DeliveryService(context: context)
        shift = try shifts.startShift(at: start)
    }

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// One delivery accepted at `accepted` and delivered `lasting` minutes
    /// later, through the ordinary lifecycle.
    @discardableResult
    func deliver(acceptedAt accepted: Double, lasting minutes: Double) throws -> Delivery {
        let delivery = try deliveries.startDelivery(at: at(accepted))
        try deliveries.markArrivedAtPickup(delivery, at: at(accepted + minutes / 3))
        try deliveries.markPickedUp(delivery, at: at(accepted + minutes / 2))
        try deliveries.markDelivered(delivery, at: at(accepted + minutes))
        return delivery
    }

    @discardableResult
    func cancel(acceptedAt accepted: Double, after minutes: Double) throws -> Delivery {
        let delivery = try deliveries.startDelivery(at: at(accepted))
        try deliveries.markArrivedAtPickup(delivery, at: at(accepted + minutes / 2))
        try deliveries.cancelDelivery(delivery, at: at(accepted + minutes))
        return delivery
    }

    /// Ends the shift, which is the state every earnings flow happens in.
    func endShift(at minutes: Double = 240) throws {
        try shifts.endActiveShift(at: at(minutes))
    }

    /// A second context over the same store, which is the only way to read what
    /// the store actually holds after a rollback — see `PickupPlaceCorrectionTests`,
    /// where the same limitation is documented.
    func reopened() -> ModelContext { ModelContext(container) }

    func storedDeliveries() throws -> [Delivery] {
        try context.fetch(FetchDescriptor<Delivery>()).sorted(by: Delivery.acceptedBefore)
    }
}

// MARK: - The model's rules

@MainActor
@Suite("Delivery earnings")
struct DeliveryEarningsTests {
    @Test("A new delivery has no earnings, which is not an amount of zero")
    func startsWithNoEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        #expect(delivery.grossEarnings == nil)
        #expect(delivery.grossEarnings != Money.zero)
    }

    @Test("A delivered delivery records what it paid, exactly as entered")
    func recordsEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let earnings = try #require(Money(exact: "14.75"))

        try delivery.setGrossEarnings(earnings)

        #expect(delivery.grossEarnings == earnings)
        #expect(delivery.grossEarnings?.amount == Decimal(string: "14.75"))
    }

    @Test("A delivery still in progress cannot record earnings")
    func refusesEarningsWhileActive() throws {
        let fixture = try EarningsFixture()
        let running = try fixture.deliveries.startDelivery(at: fixture.at(5))

        #expect(throws: DeliveryError.deliveryNotFinished) {
            try running.setGrossEarnings(try #require(Money(exact: "14.75")))
        }
        #expect(running.grossEarnings == nil, "A refused entry stores nothing")
    }

    @Test("Every unfinished state refuses an amount", arguments: [DeliveryState.accepted, .arrivedAtPickup, .pickedUp])
    func refusesEveryActiveState(state: DeliveryState) throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliveries.startDelivery(at: fixture.at(5))
        if state != .accepted {
            try fixture.deliveries.markArrivedAtPickup(delivery, at: fixture.at(10))
        }
        if state == .pickedUp {
            try fixture.deliveries.markPickedUp(delivery, at: fixture.at(16))
        }

        #expect(delivery.state == state)
        #expect(throws: DeliveryError.deliveryNotFinished) {
            try delivery.setGrossEarnings(try #require(Money(exact: "14.75")))
        }
    }

    @Test("A cancelled delivery may carry an amount, and is not forced to zero")
    func cancelledDeliveryMayRecordEarnings() throws {
        let fixture = try EarningsFixture()
        let cancelled = try fixture.cancel(acceptedAt: 5, after: 20)
        let compensation = try #require(Money(exact: "3.25"))

        try cancelled.setGrossEarnings(compensation)

        #expect(cancelled.state == .cancelled)
        #expect(cancelled.grossEarnings == compensation, "Compensation for a cancelled order is real money")
    }

    @Test("Negative earnings are refused")
    func refusesNegativeEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        #expect(throws: DeliveryError.negativeEarnings) {
            try delivery.setGrossEarnings(try #require(Money(exact: "-1.00")))
        }
        #expect(delivery.grossEarnings == nil)
    }

    @Test("Zero is an amount a driver may record")
    func recordsZero() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        try delivery.setGrossEarnings(.zero)

        #expect(delivery.grossEarnings == Money.zero)
        #expect(delivery.grossEarnings != nil, "Recording nothing earned is not the same as recording nothing")
    }

    @Test("Editing replaces the previous amount rather than adding to it")
    func editReplaces() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try delivery.setGrossEarnings(try #require(Money(exact: "14.75")))

        try delivery.setGrossEarnings(try #require(Money(exact: "9.50")))

        #expect(delivery.grossEarnings == Money(exact: "9.50"))
    }

    @Test("A refused edit leaves the stored amount untouched")
    func refusedEditKeepsTheStoredAmount() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let recorded = try #require(Money(exact: "14.75"))
        try delivery.setGrossEarnings(recorded)

        #expect(throws: DeliveryError.negativeEarnings) {
            try delivery.setGrossEarnings(try #require(Money(exact: "-5.00")))
        }

        #expect(delivery.grossEarnings == recorded)
    }

    @Test("Removing earnings returns the delivery to having none, not to zero")
    func removesEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try delivery.setGrossEarnings(try #require(Money(exact: "14.75")))

        delivery.clearGrossEarnings()

        #expect(delivery.grossEarnings == nil)
        #expect(delivery.grossEarnings != Money.zero)
    }

    @Test("Removing earnings a delivery never had is harmless")
    func removingNothingIsHarmless() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        delivery.clearGrossEarnings()

        #expect(delivery.grossEarnings == nil)
    }

    @Test("Amounts that binary floating point cannot represent survive exactly")
    func keepsExactDecimals() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        try delivery.setGrossEarnings(try #require(Money(exact: "0.10")))

        let stored = try #require(delivery.grossEarnings)
        #expect(stored + (try #require(Money(exact: "0.20"))) == Money(exact: "0.30"))
    }

    @Test("An amount does not disturb the rest of the delivery")
    func leavesTheDeliveryOtherwiseUnchanged() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let deliveredAt = delivery.deliveredAt

        try delivery.setGrossEarnings(try #require(Money(exact: "14.75")))

        #expect(delivery.state == .delivered)
        #expect(delivery.deliveredAt == deliveredAt)
        #expect(delivery.pickupWait == 300, "The wait it recorded is the wait it recorded")
        #expect(delivery.completedDuration == 1_800)
        #expect(delivery.pickupPlace == nil)
    }

    @Test("The lifecycle can be completed without any amount")
    func lifecycleNeedsNoAmount() throws {
        let fixture = try EarningsFixture()

        let delivered = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let cancelled = try fixture.cancel(acceptedAt: 60, after: 20)
        try fixture.endShift()

        #expect(delivered.state == .delivered, "Nothing about finishing a delivery asks for a figure")
        #expect(cancelled.state == .cancelled)
        #expect(delivered.grossEarnings == nil)
        #expect(!fixture.shift.isActive, "And a shift ends with no amount on any of its deliveries")
    }
}

// MARK: - Through the service

@MainActor
@Suite("Delivery earnings service")
struct DeliveryEarningsServiceTests {
    @Test("The service saves a recorded amount")
    func persistsEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        let stored = try #require(try fixture.storedDeliveries().first)
        #expect(stored.grossEarnings == Money(exact: "14.75"))
        #expect(!fixture.context.hasChanges, "The amount is committed, not left pending")
    }

    @Test("The service records an amount on a delivery whose shift has ended")
    func recordsAfterTheShiftEnds() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()

        // The point of the whole flow: entry happens afterwards, from history,
        // rather than on a card the driver may be looking at while driving.
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(delivery.grossEarnings == Money(exact: "14.75"))
        #expect(!fixture.shift.isActive)
    }

    @Test("The service refuses an amount on a delivery still in progress")
    func refusesAnActiveDelivery() throws {
        let fixture = try EarningsFixture()
        let running = try fixture.deliveries.startDelivery(at: fixture.at(5))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.deliveryNotFinished)) {
            try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: running)
        }
        #expect(running.grossEarnings == nil)
    }

    @Test("The service refuses a negative amount")
    func refusesNegativeEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        #expect(throws: DeliveryLifecycleError.invalidTransition(.negativeEarnings)) {
            try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "-0.01")), on: delivery)
        }
        #expect(delivery.grossEarnings == nil)
    }

    @Test("The service removes a recorded amount")
    func removesEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        try fixture.deliveries.clearGrossEarnings(on: delivery)

        let stored = try #require(try fixture.storedDeliveries().first)
        #expect(stored.grossEarnings == nil)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Both refusals can be explained to the driver")
    func refusalsAreExplained() {
        #expect(
            DeliveryLifecycleError.invalidTransition(.deliveryNotFinished).errorDescription
                == "Earnings can be recorded once the delivery has been delivered or cancelled."
        )
        #expect(
            DeliveryLifecycleError.invalidTransition(.negativeEarnings).errorDescription
                == "Gross earnings cannot be negative."
        )
    }

    @Test("A refused save leaves the store holding what it held")
    func aRefusedSaveKeepsTheStoredAmount() throws {
        let fixture = try EarningsFixture(commit: { _ in throw RefusedSave() })
        // The delivery and its first amount are written through a service that
        // can save; only the edit meets the refusing commit.
        let writing = DeliveryService(context: fixture.context)
        let delivery = try writing.startDelivery(at: fixture.at(5))
        try writing.markArrivedAtPickup(delivery, at: fixture.at(15))
        try writing.markPickedUp(delivery, at: fixture.at(20))
        try writing.markDelivered(delivery, at: fixture.at(35))
        try writing.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "99.99")), on: delivery)
        }

        #expect(!fixture.context.hasChanges, "The rollback left nothing pending")

        // Read fresh: a rollback restores the store, and the store is what a
        // relaunch would show.
        let stored = try fixture.reopened().fetch(FetchDescriptor<Delivery>())
        #expect(stored.count == 1)
        #expect(stored.first?.grossEarnings == Money(exact: "14.75"), "The store still holds the previous amount")
    }

    @Test("A refused removal leaves the amount in the store")
    func aRefusedRemovalKeepsTheAmount() throws {
        let fixture = try EarningsFixture(commit: { _ in throw RefusedSave() })
        let writing = DeliveryService(context: fixture.context)
        let delivery = try writing.startDelivery(at: fixture.at(5))
        try writing.markArrivedAtPickup(delivery, at: fixture.at(15))
        try writing.markPickedUp(delivery, at: fixture.at(20))
        try writing.markDelivered(delivery, at: fixture.at(35))
        try writing.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try fixture.deliveries.clearGrossEarnings(on: delivery)
        }

        let stored = try fixture.reopened().fetch(FetchDescriptor<Delivery>())
        #expect(stored.first?.grossEarnings == Money(exact: "14.75"))
    }
}

// MARK: - The parser is the same one

@Suite("Delivery earnings input")
struct DeliveryEarningsInputTests {
    private let us = MoneyInput(locale: Locale(identifier: "en_US"))
    private let germany = MoneyInput(locale: Locale(identifier: "de_DE"))

    /// The delivery editor reads its text through the same ``MoneyInput`` the
    /// shift editor does, so these assert that the shared rules reach a delivery
    /// rather than re-testing the parser — `MoneyInputTests` owns that.
    @Test("An ordinary amount, a zero, and a locale that writes the separator differently")
    func acceptsWhatItShould() throws {
        #expect(try us.amount(from: "14.75") == Money(exact: "14.75"))
        #expect(try us.amount(from: "0") == Money.zero)
        #expect(try germany.amount(from: "14,75") == Money(exact: "14.75"))
    }

    @Test("A negative amount cannot reach a delivery at all")
    func refusesNegative() {
        #expect(throws: MoneyInputError.negative) { try us.amount(from: "-14.75") }
    }

    @Test("More precision than a cent is refused rather than rounded away")
    func refusesExcessiveScale() {
        #expect(throws: MoneyInputError.excessiveScale) { try us.amount(from: "14.755") }
    }

    @Test("A pathological amount is refused")
    func refusesOversized() {
        #expect(throws: MoneyInputError.tooLarge) { try us.amount(from: "1000000.01") }
    }

    @Test("The refusals name no particular subject, because both editors show them")
    func messagesFitBothEditors() {
        let messages = [MoneyInputError.empty, .tooLarge].compactMap(\.errorDescription)

        #expect(messages.count == 2)
        #expect(
            messages.allSatisfy { !$0.contains("shift") && !$0.contains("delivery") },
            "One parser now serves a shift editor and a delivery editor: \(messages)"
        )
    }
}

// MARK: - Independence from the shift's own amount

@MainActor
@Suite("Delivery and shift earnings are independent")
struct DeliveryEarningsIndependenceTests {
    @Test("Recording a delivery amount does not touch the shift's")
    func deliveryAmountLeavesTheShiftAlone() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()
        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(fixture.shift.grossEarnings == Money(exact: "86.25"), "The shift total is the driver's own figure")
        #expect(delivery.grossEarnings == Money(exact: "14.75"))
    }

    @Test("Recording a shift amount does not touch its deliveries'")
    func shiftAmountLeavesDeliveriesAlone() throws {
        let fixture = try EarningsFixture()
        let recorded = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let untouched = try fixture.deliver(acceptedAt: 60, lasting: 30)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: recorded)

        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)

        #expect(recorded.grossEarnings == Money(exact: "14.75"))
        #expect(untouched.grossEarnings == nil, "No shift total is spread over the deliveries under it")
    }

    @Test("Removing a shift amount leaves every delivery amount standing")
    func removingTheShiftAmountKeepsDeliveryAmounts() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()
        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        try fixture.shifts.clearGrossEarnings(on: fixture.shift)

        #expect(fixture.shift.grossEarnings == nil)
        #expect(delivery.grossEarnings == Money(exact: "14.75"))
    }

    @Test("Removing a delivery amount leaves the shift's standing")
    func removingADeliveryAmountKeepsTheShiftTotal() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()
        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        try fixture.deliveries.clearGrossEarnings(on: delivery)

        #expect(fixture.shift.grossEarnings == Money(exact: "86.25"))
        #expect(delivery.grossEarnings == nil)
    }

    @Test("The delivery amounts may add up to less than the shift's, with no complaint")
    func deliveriesMayFallShortOfTheShiftTotal() throws {
        let fixture = try EarningsFixture()
        let first = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let second = try fixture.deliver(acceptedAt: 60, lasting: 30)
        try fixture.endShift()

        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "9.50")), on: second)

        // Ordinary: deliveries go unrecorded, and adjustments post at shift
        // level. Nothing in the app treats the difference as an error.
        #expect(fixture.shift.grossEarnings == Money(exact: "86.25"))
        #expect(first.grossEarnings == Money(exact: "14.75"))
        #expect(second.grossEarnings == Money(exact: "9.50"))
    }

    @Test("The delivery amounts may exceed the shift's, with no complaint")
    func deliveriesMayExceedTheShiftTotal() throws {
        let fixture = try EarningsFixture()
        let first = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let second = try fixture.deliver(acceptedAt: 60, lasting: 30)
        try fixture.endShift()

        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "10.00")), on: fixture.shift)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "9.50")), on: second)

        #expect(fixture.shift.grossEarnings == Money(exact: "10.00"), "Neither figure corrects the other")
        #expect(first.grossEarnings == Money(exact: "14.75"))
        #expect(second.grossEarnings == Money(exact: "9.50"))
    }

    @Test("A shift may hold an amount while every delivery holds none")
    func shiftOnlyIsValid() throws {
        let fixture = try EarningsFixture()
        let first = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let second = try fixture.deliver(acceptedAt: 60, lasting: 30)
        try fixture.endShift()

        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "86.25")), on: fixture.shift)

        #expect(first.grossEarnings == nil, "No amount is manufactured for a delivery")
        #expect(second.grossEarnings == nil)
    }

    @Test("Deliveries may hold amounts while the shift holds none")
    func deliveriesOnlyIsValid() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(fixture.shift.grossEarnings == nil, "No shift total is added up from its deliveries")
        #expect(delivery.grossEarnings == Money(exact: "14.75"))
    }

    @Test("Recorded, missing and explicit zero stay three distinguishable states")
    func threeStatesStayApart() throws {
        let fixture = try EarningsFixture()
        let paid = try fixture.deliver(acceptedAt: 5, lasting: 30)
        let unrecorded = try fixture.deliver(acceptedAt: 60, lasting: 30)
        let zero = try fixture.deliver(acceptedAt: 120, lasting: 30)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "12.00")), on: paid)
        try fixture.deliveries.setGrossEarnings(.zero, on: zero)

        #expect(paid.grossEarnings == Money(exact: "12.00"))
        #expect(unrecorded.grossEarnings == nil)
        #expect(zero.grossEarnings == Money.zero)
        #expect(unrecorded.grossEarnings != zero.grossEarnings, "Missing is not zero")

        // What a caller that wants a total must do: count what was recorded and
        // say how many rows it came from, rather than reading a missing amount
        // as nothing earned.
        let recorded = try fixture.storedDeliveries().compactMap(\.grossEarnings)
        #expect(recorded.count == 2, "Two of the three deliveries carry an amount")
        #expect(recorded.reduce(Money.zero, +) == Money(exact: "12.00"))
    }
}

// MARK: - Stacked deliveries

@MainActor
@Suite("Stacked delivery earnings")
struct StackedDeliveryEarningsTests {
    /// Two deliveries whose lifecycles overlap almost entirely, which is what
    /// stacked work is.
    private func stackedPair(in fixture: EarningsFixture) throws -> (first: Delivery, second: Delivery) {
        let first = try fixture.deliveries.startDelivery(at: fixture.at(0))
        let second = try fixture.deliveries.startDelivery(at: fixture.at(10))
        try fixture.deliveries.markArrivedAtPickup(first, at: fixture.at(12))
        try fixture.deliveries.markArrivedAtPickup(second, at: fixture.at(14))
        try fixture.deliveries.markPickedUp(first, at: fixture.at(20))
        try fixture.deliveries.markPickedUp(second, at: fixture.at(22))
        try fixture.deliveries.markDelivered(second, at: fixture.at(40))
        try fixture.deliveries.markDelivered(first, at: fixture.at(30))
        return (first, second)
    }

    @Test("Two overlapping deliveries carry independent amounts")
    func independentAmounts() throws {
        let fixture = try EarningsFixture()
        let pair = try stackedPair(in: fixture)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: pair.first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "9.50")), on: pair.second)

        #expect(pair.first.grossEarnings == Money(exact: "14.75"))
        #expect(pair.second.grossEarnings == Money(exact: "9.50"))
    }

    @Test("Editing one stacked delivery's amount leaves the other's alone")
    func editingOneLeavesTheOther() throws {
        let fixture = try EarningsFixture()
        let pair = try stackedPair(in: fixture)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: pair.first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "9.50")), on: pair.second)

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "20.00")), on: pair.first)

        #expect(pair.first.grossEarnings == Money(exact: "20.00"))
        #expect(pair.second.grossEarnings == Money(exact: "9.50"))
    }

    @Test("Removing one stacked delivery's amount leaves the other's alone")
    func removingOneLeavesTheOther() throws {
        let fixture = try EarningsFixture()
        let pair = try stackedPair(in: fixture)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: pair.first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "9.50")), on: pair.second)

        try fixture.deliveries.clearGrossEarnings(on: pair.first)

        #expect(pair.first.grossEarnings == nil)
        #expect(pair.second.grossEarnings == Money(exact: "9.50"))
    }

    @Test("Overlapping lifecycles have no effect on what either delivery stores")
    func overlapDoesNotTouchTheAmounts() throws {
        let fixture = try EarningsFixture()
        let pair = try stackedPair(in: fixture)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: pair.first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: pair.second)

        // Twenty of the first delivery's thirty minutes are shared with the
        // second, and neither amount knows or cares.
        #expect(pair.first.completedDuration == 1_800)
        #expect(pair.second.completedDuration == 1_800)
        #expect(pair.first.grossEarnings == pair.second.grossEarnings)
        #expect(fixture.shift.deliveryActiveTime().hasOverlappingDeliveries)
    }

    @Test("Each stacked delivery's rate divides by its own duration only")
    func ratesUseOnlyTheirOwnDuration() throws {
        let fixture = try EarningsFixture()
        let pair = try stackedPair(in: fixture)
        try fixture.endShift()

        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "15.00")), on: pair.first)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "15.00")), on: pair.second)

        // Both ran thirty minutes, so both are $30.00 per recorded delivery
        // hour — even though between them they covered forty minutes of the
        // shift, not an hour. This is exactly why these figures are never added.
        #expect(pair.first.grossPerDeliveryHour == .available(try #require(Money(exact: "30"))))
        #expect(pair.second.grossPerDeliveryHour == .available(try #require(Money(exact: "30"))))

        let activeTime = fixture.shift.deliveryActiveTime()
        #expect(activeTime.duration == 2_400, "The shift's own figure unions the intervals rather than adding them")
    }
}

// MARK: - The delivery's own hourly figure

@MainActor
@Suite("Gross per recorded delivery hour")
struct DeliveryEarningsRateTests {
    @Test("A delivered delivery divides its amount by its own elapsed lifecycle")
    func derivesTheRate() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        // 14.75 over half an hour.
        #expect(delivery.grossPerDeliveryHour == .available(try #require(Money(exact: "29.5"))))
    }

    @Test("A fractional duration divides exactly, without binary floating point")
    func fractionalDuration() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 20)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "10.00")), on: delivery)

        // A third of an hour: 10.00 / (1/3) is exactly 30.
        #expect(delivery.grossPerDeliveryHour == .available(try #require(Money(exact: "30"))))
    }

    @Test("An amount that does not divide evenly keeps the calculation's scale")
    func repeatingQuotient() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 45)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "10.00")), on: delivery)

        let rate = try #require(delivery.grossPerDeliveryHour.amount)
        // 10.00 over three quarters of an hour, kept to the calculation's scale
        // and rounded only for display.
        #expect(rate.amount == Decimal(string: "13.333333"))
        #expect(rate.formatted(locale: Locale(identifier: "en_US")) == "$13.33")
    }

    @Test("A recorded zero produces a rate of zero, which is a real figure")
    func zeroEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(.zero, on: delivery)

        #expect(delivery.grossPerDeliveryHour == .available(.zero))
    }

    @Test("No amount produces no rate, and says which input is missing")
    func missingEarnings() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 5, lasting: 30)

        #expect(delivery.grossPerDeliveryHour == .unavailable(.earningsNotRecorded))
        #expect(delivery.grossPerDeliveryHour.amount == nil, "Never a zero standing in for an absence")
    }

    @Test("A delivery accepted and delivered in the same moment has no denominator")
    func zeroDuration() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliveries.startDelivery(at: fixture.at(5))
        try fixture.deliveries.markArrivedAtPickup(delivery, at: fixture.at(5))
        try fixture.deliveries.markPickedUp(delivery, at: fixture.at(5))
        try fixture.deliveries.markDelivered(delivery, at: fixture.at(5))
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "14.75")), on: delivery)

        #expect(delivery.completedDuration == 0)
        #expect(delivery.grossPerDeliveryHour == .unavailable(.zeroDuration))
    }

    @Test("A cancelled delivery has an amount but no hourly figure")
    func cancelledHasNoRate() throws {
        let fixture = try EarningsFixture()
        let cancelled = try fixture.cancel(acceptedAt: 5, after: 30)
        try fixture.endShift()
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "3.25")), on: cancelled)

        #expect(cancelled.grossEarnings == Money(exact: "3.25"), "The amount is shown")
        #expect(
            cancelled.grossPerDeliveryHour == .unavailable(.deliveryNotCompleted),
            "There is no such thing as a cancelled hourly rate in DashPilot"
        )
    }

    @Test("A delivery still in progress has no hourly figure either")
    func activeHasNoRate() throws {
        let fixture = try EarningsFixture()
        let running = try fixture.deliveries.startDelivery(at: fixture.at(5))

        #expect(running.grossPerDeliveryHour == .unavailable(.deliveryNotCompleted))
    }

    @Test("Every reason can be explained to the driver")
    func everyReasonHasAnExplanation() {
        #expect(DeliveryRateUnavailability.allCases.allSatisfy { !$0.explanation.isEmpty })
        #expect(
            DeliveryRateUnavailability.allCases.allSatisfy { !$0.explanation.contains("0.00") },
            "No explanation may imply the missing figure is a zero"
        )
    }

    @Test("It rounds exactly as the shift's own hourly rates do")
    func sharesTheShiftRateArithmetic() throws {
        let fixture = try EarningsFixture()
        let delivery = try fixture.deliver(acceptedAt: 0, lasting: 45)
        try fixture.endShift(at: 45)
        try fixture.deliveries.setGrossEarnings(try #require(Money(exact: "10.00")), on: delivery)
        try fixture.shifts.setGrossEarnings(try #require(Money(exact: "10.00")), on: fixture.shift)

        // The same amount over the same 45 minutes, once as a shift and once as
        // a delivery: one definition of an amount per hour, so one answer.
        let metrics = fixture.shift.metrics(for: .none)
        #expect(delivery.grossPerDeliveryHour.amount == metrics.grossPerElapsedHour.amount)
    }
}
