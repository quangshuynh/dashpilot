import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Errors substituted for a real save, so what a refused write leaves behind can
/// be asserted.
private struct RefusedExpectedSave: Error {}

/// What a driver expects a delivery to pay, and the distance the app keeps
/// between that and what it recorded the delivery as having paid.
///
/// The claim under test is a negative one and it is the whole feature: recording
/// an expectation moves **nothing**. No delivery becomes paid, no shift figure
/// changes, no period total or rate moves, no export summary shifts, and nothing
/// reaches the Lock Screen. The positive claims, that the amount is stored,
/// edited, cleared and offered back, are the easy half.
///
/// Every amount, offset and place name below is invented.
@MainActor
@Suite("Expected delivery earnings")
struct ExpectedDeliveryEarningsTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// A store, a running shift and the two services, built through the real
    /// lifecycle rather than by inserting rows.
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let shifts: ShiftService
        let deliveries: DeliveryService
        let shift: Shift
    }

    private func makeFixture(commit: ((ModelContext) throws -> Void)? = nil) throws -> Fixture {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shifts = ShiftService(context: context)
        // The commit seam goes on the delivery service alone, so the shift the
        // fixture starts is always genuinely in the store.
        let deliveries = commit.map { DeliveryService(context: context, commit: $0) }
            ?? DeliveryService(context: context)
        return Fixture(
            container: container,
            context: context,
            shifts: shifts,
            deliveries: deliveries,
            shift: try shifts.startShift(at: start)
        )
    }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    // MARK: Recording, editing and clearing while active

    @Test("An active delivery records, edits and clears what it is expected to pay")
    func setEditAndClear() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))

        #expect(delivery.expectedEarnings == nil, "Nothing is expected until the driver says so")

        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        #expect(delivery.expectedEarnings == (try money("8.50")))

        try fixture.deliveries.setExpectedEarnings(try money("11.25"), on: delivery)
        #expect(delivery.expectedEarnings == (try money("11.25")), "An expectation is replaced, not added to")

        try fixture.deliveries.clearExpectedEarnings(on: delivery)
        #expect(delivery.expectedEarnings == nil)
    }

    @Test("An expectation can be recorded at every active state of the lifecycle")
    func allowedThroughoutTheActiveLifecycle() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))

        try fixture.deliveries.setExpectedEarnings(try money("6.00"), on: delivery)
        #expect(delivery.state == .accepted)

        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.setExpectedEarnings(try money("7.00"), on: delivery)
        #expect(delivery.state == .arrivedAtPickup, "Waiting at the pickup is the moment this is for")

        try fixture.deliveries.markPickedUp(delivery, at: at(18))
        try fixture.deliveries.setExpectedEarnings(try money("7.50"), on: delivery)
        #expect(delivery.state == .pickedUp)
        #expect(delivery.expectedEarnings == (try money("7.50")))
    }

    @Test("Expecting nothing and expecting no amount are different facts")
    func zeroIsNotMissing() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))

        try fixture.deliveries.setExpectedEarnings(.zero, on: delivery)
        let recorded = try #require(delivery.expectedEarnings)
        #expect(recorded.isZero)
        #expect(delivery.expectedEarnings != nil, "An explicit zero is a recorded expectation")

        try fixture.deliveries.clearExpectedEarnings(on: delivery)
        #expect(delivery.expectedEarnings == nil, "Clearing is not recording zero")
    }

    @Test("A negative expectation is refused, and says which amount it refused")
    func negativeRefused() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))

        #expect(throws: DeliveryLifecycleError.invalidTransition(.negativeExpectedEarnings)) {
            try fixture.deliveries.setExpectedEarnings(Money(minorUnits: -100), on: delivery)
        }
        #expect(delivery.expectedEarnings == nil)

        // The sentence names the expected amount rather than gross earnings,
        // which is the whole reason the case is separate.
        let message = DeliveryLifecycleError.invalidTransition(.negativeExpectedEarnings).errorDescription
        #expect(message == "An expected amount cannot be negative.")
        #expect(message?.lowercased().contains("gross") == false)
    }

    @Test("The money path is the app's own: Decimal through Money, parsed by MoneyInput")
    func usesTheExistingMoneyPath() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))

        // A locale that writes its decimal separator as a comma, through the one
        // parser every other amount in the app is typed into.
        let typed = try MoneyInput(locale: Locale(identifier: "de_DE")).amount(from: "11,05")
        try fixture.deliveries.setExpectedEarnings(typed, on: delivery)

        let stored = try #require(delivery.expectedEarnings)
        #expect(stored.amount == Decimal(string: "11.05", locale: Locale(identifier: "en_US_POSIX")))
        #expect(stored.formatted(locale: locale) == "$11.05")

        // The refusals are the parser's, said in the terms of what was typed.
        #expect(MoneyInputError.negative.message(for: .expectedEarnings) == "An expected amount cannot be negative.")
        #expect(MoneyInputError.empty.message(for: .expectedEarnings) != MoneyInputError.empty.message(for: .grossEarnings))
    }

    // MARK: The rule at the terminal boundary

    @Test("Completing a delivery records no gross and leaves the expectation exactly as it was")
    func completionFinalizesNothing() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.markPickedUp(delivery, at: at(18))

        try fixture.deliveries.markDelivered(delivery, at: at(30))

        #expect(delivery.state == .delivered)
        #expect(delivery.expectedEarnings == (try money("8.50")), "The expectation survives the transition")
        #expect(delivery.grossEarnings == nil, "Nothing finalizes an expectation by itself")
        #expect(delivery.hasUnconfirmedExpectedEarnings)
    }

    @Test("Cancelling fabricates no gross either")
    func cancellationFabricatesNoGross() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("9.75"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))

        try fixture.deliveries.cancelDelivery(delivery, at: at(25))

        #expect(delivery.state == .cancelled)
        #expect(delivery.expectedEarnings == (try money("9.75")))
        #expect(delivery.grossEarnings == nil, "An order that fell through paid nothing until the driver says it did")
        #expect(delivery.hasUnconfirmedExpectedEarnings)
    }

    @Test("A finished delivery refuses a new expectation but still allows one to be removed")
    func terminalDeliveryRefusesAnExpectation() throws {
        let fixture = try makeFixture()
        let delivered = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivered)
        try fixture.deliveries.markArrivedAtPickup(delivered, at: at(10))
        try fixture.deliveries.markPickedUp(delivered, at: at(18))
        try fixture.deliveries.markDelivered(delivered, at: at(30))

        let cancelled = try fixture.deliveries.startDelivery(at: at(35))
        try fixture.deliveries.cancelDelivery(cancelled, at: at(40))

        for delivery in [delivered, cancelled] {
            #expect(throws: DeliveryLifecycleError.invalidTransition(.deliveryNotActive)) {
                try fixture.deliveries.setExpectedEarnings(try money("4.00"), on: delivery)
            }
        }
        #expect(delivered.expectedEarnings == (try money("8.50")), "A refused write changes nothing")
        #expect(cancelled.expectedEarnings == nil)

        // Removing claims nothing, so it stays available afterwards.
        try fixture.deliveries.clearExpectedEarnings(on: delivered)
        #expect(delivered.expectedEarnings == nil)
    }

    @Test("Confirming records a gross amount beside the expectation rather than instead of it")
    func confirmingKeepsBothFacts() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.markPickedUp(delivery, at: at(18))
        try fixture.deliveries.markDelivered(delivery, at: at(30))

        // What the confirmation sheet does when the driver corrects the figure.
        try fixture.deliveries.setGrossEarnings(try money("6.25"), on: delivery)

        #expect(delivery.grossEarnings == (try money("6.25")))
        #expect(delivery.expectedEarnings == (try money("8.50")), "What was expected is still what was expected")
        #expect(!delivery.hasUnconfirmedExpectedEarnings)
    }

    @Test("Two amounts that happen to match are still two facts")
    func matchingAmountsAreNotOneFact() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.markPickedUp(delivery, at: at(18))
        try fixture.deliveries.markDelivered(delivery, at: at(30))

        #expect(delivery.expectedEarnings == (try money("8.50")))
        #expect(delivery.grossEarnings == nil, "An identical number would still not have been recorded")

        try fixture.deliveries.setGrossEarnings(try money("8.50"), on: delivery)
        #expect(delivery.grossEarnings == delivery.expectedEarnings)
        // The columns are still independent: removing one leaves the other.
        try fixture.deliveries.clearExpectedEarnings(on: delivery)
        #expect(delivery.grossEarnings == (try money("8.50")))
        #expect(delivery.expectedEarnings == nil)
    }

    // MARK: Stacked deliveries

    @Test("Stacked deliveries keep their own expected amounts")
    func stackedDeliveriesKeepTheirOwnAmounts() throws {
        let fixture = try makeFixture()
        let first = try fixture.deliveries.startDelivery(at: at(5))
        let second = try fixture.deliveries.startDelivery(at: at(7))
        let third = try fixture.deliveries.startDelivery(at: at(9))

        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: first)
        try fixture.deliveries.setExpectedEarnings(try money("3.25"), on: third)

        #expect(first.expectedEarnings == (try money("8.50")))
        #expect(second.expectedEarnings == nil, "A delivery nobody typed an amount for has none")
        #expect(third.expectedEarnings == (try money("3.25")))

        // Editing one leaves the others exactly as they were.
        try fixture.deliveries.setExpectedEarnings(try money("12.00"), on: second)
        #expect(first.expectedEarnings == (try money("8.50")))
        #expect(third.expectedEarnings == (try money("3.25")))

        // So does clearing one.
        try fixture.deliveries.clearExpectedEarnings(on: first)
        #expect(first.expectedEarnings == nil)
        #expect(second.expectedEarnings == (try money("12.00")))
        #expect(third.expectedEarnings == (try money("3.25")))
    }

    @Test("Completing one stacked delivery leaves the others' expectations untouched")
    func completingOneOfSeveralTouchesNoOther() throws {
        let fixture = try makeFixture()
        let first = try fixture.deliveries.startDelivery(at: at(5))
        let second = try fixture.deliveries.startDelivery(at: at(7))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: first)
        try fixture.deliveries.setExpectedEarnings(try money("4.10"), on: second)

        try fixture.deliveries.markArrivedAtPickup(first, at: at(10))
        try fixture.deliveries.markPickedUp(first, at: at(15))
        try fixture.deliveries.markDelivered(first, at: at(25))
        try fixture.deliveries.setGrossEarnings(try money("8.50"), on: first)

        #expect(second.state == .accepted, "The other delivery is untouched by the first finishing")
        #expect(second.expectedEarnings == (try money("4.10")))
        #expect(second.grossEarnings == nil, "Recording one delivery's earnings records nothing on another")
    }

    // MARK: What must not move

    @Test("An expectation moves no shift figure and no rate")
    func shiftFiguresAreUnmoved() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.markPickedUp(delivery, at: at(18))
        try fixture.deliveries.markDelivered(delivery, at: at(30))
        try fixture.shifts.endActiveShift(at: at(120))
        try fixture.shifts.setGrossEarnings(try money("100.00"), on: fixture.shift)

        let before = fixture.shift.metrics(for: .none)

        // An identical shift, built the same way from the same timestamps and
        // the same amount, differing in one thing: its delivery recorded an
        // expectation while it was still active, which is the only moment the
        // model allows one. Comparing the two is the claim under test.
        let second = try makeFixture()
        let seeded = try second.deliveries.startDelivery(at: at(5))
        try second.deliveries.setExpectedEarnings(try money("8.50"), on: seeded)
        try second.deliveries.markArrivedAtPickup(seeded, at: at(10))
        try second.deliveries.markPickedUp(seeded, at: at(18))
        try second.deliveries.markDelivered(seeded, at: at(30))
        try second.shifts.endActiveShift(at: at(120))
        try second.shifts.setGrossEarnings(try money("100.00"), on: second.shift)

        let after = second.shift.metrics(for: .none)

        #expect(after.grossEarnings == before.grossEarnings)
        #expect(after.grossPerWorkingHour.amount == before.grossPerWorkingHour.amount)
        #expect(after.grossPerDeliveryActiveHour.amount == before.grossPerDeliveryActiveHour.amount)
        #expect(after.grossPerRecordedMile.amount == before.grossPerRecordedMile.amount)
        #expect(seeded.expectedEarnings == (try money("8.50")), "The expectation really is on the record")
        #expect(seeded.grossPerDeliveryHour.amount == nil, "A delivery with no recorded amount has no rate")
        #expect(delivery.grossPerDeliveryHour.amount == nil)
    }

    @Test("An expectation-only delivery contributes nothing to a period's delivery earnings")
    func periodAggregatesAreUnmoved() throws {
        let fixture = try makeFixture()
        let expectedOnly = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: expectedOnly)
        try fixture.deliveries.markArrivedAtPickup(expectedOnly, at: at(10))
        try fixture.deliveries.markPickedUp(expectedOnly, at: at(18))
        try fixture.deliveries.markDelivered(expectedOnly, at: at(30))

        let recorded = try fixture.deliveries.startDelivery(at: at(35))
        try fixture.deliveries.setExpectedEarnings(try money("20.00"), on: recorded)
        try fixture.deliveries.markArrivedAtPickup(recorded, at: at(40))
        try fixture.deliveries.markPickedUp(recorded, at: at(45))
        try fixture.deliveries.markDelivered(recorded, at: at(55))
        try fixture.shifts.endActiveShift(at: at(120))
        try fixture.deliveries.setGrossEarnings(try money("6.25"), on: recorded)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let metrics = PeriodMetricsCalculator().metrics(
            of: [fixture.shift.periodRecord(for: .none)],
            in: period
        )

        // The subtotal is the one recorded amount, not the two expected ones and
        // not the sum of all three.
        #expect(metrics.recordedDeliveryEarnings == (try money("6.25")))
        #expect(metrics.deliveryEarningsCoverage.contributingCount == 1)
        #expect(metrics.deliveryEarningsCoverage.eligibleCount == 2, "Both deliveries were eligible to record one")
        #expect(metrics.recordedGrossEarnings == nil, "No shift amount was recorded, and none is inferred")
    }

    @Test("The period record carries only recorded delivery amounts")
    func periodRecordCarriesNoExpectation() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))
        try fixture.deliveries.markPickedUp(delivery, at: at(18))
        try fixture.deliveries.markDelivered(delivery, at: at(30))
        try fixture.shifts.endActiveShift(at: at(120))

        let record = fixture.shift.periodRecord(for: .none)
        #expect(record.recordedDeliveryEarnings.isEmpty, "An expectation is not a recorded amount")
        #expect(record.terminalDeliveryCount == 1)
    }

    @Test("Nothing about an expectation reaches the shift's Live Activity")
    func liveActivityStaysMoneyFree() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        try fixture.deliveries.setExpectedEarnings(try money("8.50"), on: delivery)
        try fixture.deliveries.markArrivedAtPickup(delivery, at: at(10))

        let state = fixture.shift.activityContentState(for: .none, asOf: at(20), locale: locale)
        let printed = [
            state.statusTitle,
            state.formattedWorkingTime,
            state.spokenWorkingTime,
            state.mileageLine,
            state.spokenMileageLine,
            state.deliveryLine,
            state.spokenDeliveryLine,
            state.spokenSummary,
            state.compactDeliveryCount,
            state.deliveryStatus,
            state.controlNotice
        ].compactMap { $0 } + state.controls.flatMap { [$0.title, $0.spokenLabel] }

        for line in printed {
            #expect(!line.contains("$"), "No amount reaches a Lock Screen: \(line)")
            #expect(!line.contains("8.50"), "Not even an expected one: \(line)")
            #expect(!line.lowercased().contains("expect"), "No expectation vocabulary: \(line)")
            #expect(!line.lowercased().contains("earn"), "No earnings vocabulary: \(line)")
        }

        // The snapshot is derived from a delivery's *state*, which is the
        // structural reason an amount cannot reach it.
        #expect(state.deliveryStatus == DeliveryState.arrivedAtPickup.statusDescription)
    }

    // MARK: Failure paths

    @Test("A refused save leaves the delivery with the amount the store holds")
    func refusedSaveRollsBack() throws {
        // Seeded through a service whose save works, then swapped for one whose
        // does not, so the rollback has something committed to return to.
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shifts = ShiftService(context: context)
        try shifts.startShift(at: start)

        let working = DeliveryService(context: context)
        let delivery = try working.startDelivery(at: at(5))
        try working.setExpectedEarnings(try money("8.50"), on: delivery)

        let refusing = DeliveryService(context: context) { _ in throw RefusedExpectedSave() }

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedExpectedSave())) {
            try refusing.setExpectedEarnings(try money("99.00"), on: delivery)
        }
        #expect(!context.hasChanges, "The rollback left nothing pending")

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedExpectedSave())) {
            try refusing.clearExpectedEarnings(on: delivery)
        }
        #expect(!context.hasChanges)

        // Read fresh, which is the claim that matters and the one this
        // repository asserts for every other refused write: a rollback restores
        // the store, and the store is what a relaunch would show. A model object
        // held across a rollback is not a reliable witness to it.
        let id = delivery.id
        let stored = try #require(
            try ModelContext(container)
                .fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id }))
                .first
        )
        #expect(stored.expectedEarnings == (try money("8.50")), "The store still holds the previous amount")
        #expect(stored.grossEarnings == nil, "And a refused expectation wrote no gross amount either")
    }

    @Test("A refused save does not leave a recorded gross amount behind either")
    func refusedConfirmationRecordsNothing() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        try ShiftService(context: context).startShift(at: start)

        let working = DeliveryService(context: context)
        let delivery = try working.startDelivery(at: at(5))
        try working.setExpectedEarnings(try money("8.50"), on: delivery)
        try working.markArrivedAtPickup(delivery, at: at(10))
        try working.markPickedUp(delivery, at: at(18))
        try working.markDelivered(delivery, at: at(30))

        let refusing = DeliveryService(context: context) { _ in throw RefusedExpectedSave() }
        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedExpectedSave())) {
            try refusing.setGrossEarnings(try money("8.50"), on: delivery)
        }

        let reread = ModelContext(container)
        let id = delivery.id
        let stored = try #require(
            try reread.fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id })).first
        )
        #expect(stored.grossEarnings == nil, "A refused confirmation records nothing")
        #expect(stored.expectedEarnings == (try money("8.50")), "And loses nothing")
    }

    // MARK: Wording

    @Test("Every spoken form names its delivery and says what the amount is not")
    func spokenFormsKeepTheDistinction() throws {
        let fixture = try makeFixture()
        let delivery = try fixture.deliveries.startDelivery(at: at(5))
        let numbered = NumberedDelivery(number: 2, delivery: delivery)

        #expect(numbered.expectedEarningsActionTitle(hasExpected: false) == "Add Expected Pay")
        #expect(numbered.expectedEarningsActionTitle(hasExpected: true) == "Change Expected Pay")

        for spoken in [
            numbered.spokenExpectedEarningsLabel(hasExpected: false),
            numbered.spokenExpectedEarningsLabel(hasExpected: true),
            numbered.spokenRemoveExpectedEarningsLabel,
            numbered.spokenExpectedEarnings("$8.50"),
            numbered.spokenExpectedEarningsBesideRecorded("$8.50")
        ] {
            #expect(spoken.contains("Delivery 2"), "A control names its delivery: \(spoken)")
        }

        // The figures carry the distinction in the sentence, because a listener
        // has no column heading to read it from.
        #expect(numbered.spokenExpectedEarnings("$8.50").contains("No gross earnings recorded yet"))
        #expect(numbered.spokenExpectedEarningsBesideRecorded("$8.50").contains("not what was recorded"))

        // And the printed label never borrows the word the recorded amount uses.
        #expect(!numbered.expectedEarningsActionTitle(hasExpected: false).lowercased().contains("earnings"))
    }
}
