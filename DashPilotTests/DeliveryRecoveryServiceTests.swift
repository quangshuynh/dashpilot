import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedSave: Error {}

/// Reopening a delivery through the service: what one correction writes, what it
/// leaves alone, which shifts refuse it, and what a refused save leaves behind.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held model and the authoritative store can disagree
/// after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp and amount here is invented.
@MainActor
@Suite("Delivery recovery service")
struct DeliveryRecoveryServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotDeliveryRecoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func runningShift(
        in existing: ModelContext? = nil
    ) throws -> (context: ModelContext, shift: Shift, deliveries: DeliveryService) {
        let context = try existing ?? ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        return (context, shift, DeliveryService(context: context))
    }

    /// A delivery driven all the way to delivered through the service.
    @discardableResult
    private func deliver(
        _ delivery: Delivery,
        using service: DeliveryService,
        arrivingAt: TimeInterval = 600,
        pickingUpAt: TimeInterval = 900,
        deliveringAt: TimeInterval = 1500
    ) throws -> Delivery {
        try service.markArrivedAtPickup(delivery, at: at(arrivingAt))
        try service.markPickedUp(delivery, at: at(pickingUpAt))
        try service.markDelivered(delivery, at: at(deliveringAt))
        return delivery
    }

    private func refusing(_ context: ModelContext) -> DeliveryService {
        DeliveryService(context: context, commit: { _ in throw RefusedSave() })
    }

    // MARK: The correction itself

    @Test("A delivery delivered after a pickup is reopened to heading to the customer")
    func reopensToThePickedUpState() throws {
        let (context, shift, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        let restored = try service.reopenDelivered(delivery)

        #expect(restored == .pickedUp)
        #expect(delivery.state == .pickedUp)
        #expect(shift.activeDeliveries.map(\.id) == [delivery.id])
        #expect(!context.hasChanges, "The correction was saved, not left pending")
    }

    @Test("Only the delivered timestamp is removed, and it survives a reopen of the store")
    func clearsOnlyTheDeliveredTimestamp() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let (_, _, service) = try runningShift(in: context)
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)
        let deliveryID = delivery.id

        try service.reopenDelivered(delivery)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(
            try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID }
        )

        #expect(stored.deliveredAt == nil)
        #expect(stored.cancelledAt == nil)
        // Byte for byte. A correction that rewrote an event the driver recorded
        // would be correcting more than the mistake.
        #expect(stored.acceptedAt == at(300))
        #expect(stored.arrivedAtPickupAt == at(600))
        #expect(stored.pickedUpAt == at(900))
        #expect(stored.state == .pickedUp)
    }

    @Test("A reopened delivery can be delivered again, with the new time")
    func advancesAgainAfterwards() throws {
        let (_, shift, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        try service.reopenDelivered(delivery)
        try service.markDelivered(delivery, at: at(2100))

        #expect(delivery.state == .delivered)
        #expect(delivery.deliveredAt == at(2100))
        #expect(delivery.pickedUpAt == at(900), "The events before it never moved")
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 0))
    }

    @Test("Reopening the same delivery twice is refused the second time and writes nothing")
    func refusesASecondReopen() throws {
        let (context, _, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        try service.reopenDelivered(delivery)

        #expect(throws: DeliveryLifecycleError.invalidRecovery(.notDelivered)) {
            try service.reopenDelivered(delivery)
        }
        #expect(delivery.state == .pickedUp)
        #expect(delivery.pickedUpAt == at(900))
        #expect(!context.hasChanges, "A refusal leaves nothing for a later save to commit")
    }

    // MARK: What it refuses

    @Test("A cancelled delivery is refused, and nothing about it moves")
    func refusesACancelledDelivery() throws {
        let (context, _, service) = try runningShift()
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.cancelDelivery(delivery, at: at(700))

        #expect(throws: DeliveryLifecycleError.invalidRecovery(.cancelled)) {
            try service.reopenDelivered(delivery)
        }

        #expect(delivery.state == .cancelled)
        #expect(delivery.cancelledAt == at(700))
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(!context.hasChanges)
    }

    @Test("A delivery that is still running has nothing to reopen")
    func refusesAnActiveDelivery() throws {
        let (context, _, service) = try runningShift()
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))

        #expect(throws: DeliveryLifecycleError.invalidRecovery(.notDelivered)) {
            try service.reopenDelivered(delivery)
        }
        #expect(delivery.state == .arrivedAtPickup)
        #expect(!context.hasChanges)
    }

    @Test("A shift that has ended refuses it, and the delivery stays delivered")
    func refusesAfterTheShiftEnded() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let (_, shift, service) = try runningShift(in: context)
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)
        let deliveryID = delivery.id
        try ShiftService(context: context).endActiveShift(at: at(3600))

        #expect(throws: DeliveryLifecycleError.cannotReopenOnEndedShift) {
            try service.reopenDelivered(delivery)
        }

        // The refusal is what keeps an ended shift from holding a delivery
        // nothing could finish: every lifecycle step on it is refused too.
        #expect(shift.isActive == false)
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(
            try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID }
        )
        #expect(stored.state == .delivered)
        #expect(stored.deliveredAt == at(1500))
    }

    /// This is also the stale-surface case. A control drawn while the shift was
    /// running is refused here rather than by the screen that drew it, which is
    /// the rule every other lifecycle action on this service already follows.
    @Test("A paused shift refuses it, and allows it again once resumed")
    func refusesWhilePausedAndAllowsItAfterResuming() throws {
        let (context, _, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)
        let shifts = ShiftService(context: context)
        try shifts.pauseActiveShift(at: at(1800))

        #expect(throws: DeliveryLifecycleError.cannotReopenWhilePaused) {
            try service.reopenDelivered(delivery)
        }
        #expect(delivery.state == .delivered, "A pause is a refusal, not a correction")

        try shifts.resumeActiveShift(at: at(2400))

        #expect(try service.reopenDelivered(delivery) == .pickedUp)
    }

    @Test("A reopened delivery blocks the shift from ending, exactly as any running one does")
    func blocksTheShiftEnd() throws {
        let (context, _, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        try service.reopenDelivered(delivery)

        // This is what makes the refusal above sufficient: a shift cannot end
        // while the reopened delivery is open, so no completed shift and no
        // period aggregate can ever see one.
        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 1)) {
            try ShiftService(context: context).endActiveShift(at: at(3600))
        }

        try service.markDelivered(delivery, at: at(2100))
        try ShiftService(context: context).endActiveShift(at: at(3600))
    }

    // MARK: A refused save

    @Test("A refused save leaves the delivery exactly as delivered as the store had it")
    func rollsBackCompletely() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let (_, _, service) = try runningShift(in: context)
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)
        let deliveryID = delivery.id

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedSave())) {
            try refusing(context).reopenDelivered(delivery)
        }

        #expect(!context.hasChanges, "The rollback left nothing pending")

        // Read fresh: a rollback restores the store rather than the value the
        // live object is holding, and the store is what a relaunch would show.
        // The same reading every other refused-save test in this project makes.
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(
            try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID }
        )

        #expect(stored.state == .delivered, "The store never stopped holding it delivered")
        #expect(stored.deliveredAt == at(1500))
        #expect(stored.acceptedAt == at(300))
        #expect(stored.arrivedAtPickupAt == at(600))
        #expect(stored.pickedUpAt == at(900))
    }

    // MARK: Money

    @Test("A recorded amount stays recorded, and the expectation beside it")
    func keepsTheAmountsThroughTheStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let (_, _, service) = try runningShift(in: context)
        let delivery = try service.startDelivery(at: at(300))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.setExpectedEarnings(Money(minorUnits: 850), on: delivery)
        try service.markPickedUp(delivery, at: at(900))
        try service.markDelivered(delivery, at: at(1500))
        try service.setGrossEarnings(Money(minorUnits: 725), on: delivery)
        let deliveryID = delivery.id

        try service.reopenDelivered(delivery)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(
            try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID }
        )

        #expect(stored.grossEarnings == Money(minorUnits: 725), "Money the driver recorded is not deleted")
        #expect(stored.expectedEarnings == Money(minorUnits: 850), "and neither is the expectation beside it")
        // Recording a new amount is still refused while it is active, which is a
        // rule about writing rather than about holding.
        #expect(throws: DeliveryLifecycleError.invalidTransition(.deliveryNotFinished)) {
            try service.setGrossEarnings(Money(minorUnits: 900), on: delivery)
        }
        #expect(delivery.grossEarnings == Money(minorUnits: 725))
    }

    // MARK: Siblings, offers and the shift's figures

    @Test("A sibling in the same offer is untouched, and the offer becomes active again")
    func leavesTheSiblingAndRevivesTheOffer() throws {
        let (_, shift, service) = try runningShift()
        let offer = try service.startOffer(deliveryCount: 2, at: at(300))
        let ordered = offer.deliveriesInOrder
        let corrected = ordered[0]
        let sibling = ordered[1]
        try deliver(corrected, using: service)
        try deliver(sibling, using: service, arrivingAt: 700, pickingUpAt: 1000, deliveringAt: 1700)
        try service.setGrossEarnings(Money(minorUnits: 600), on: sibling)

        #expect(offer.state == .completed)
        #expect(offer.isTerminal)

        try service.reopenDelivered(corrected)

        #expect(offer.state == .inProgress, "An offer is terminal only while all of its deliveries are")
        #expect(offer.isTerminal == false)
        #expect(offer.deliveryCount == 2, "Membership is not what a lifecycle correction changes")
        #expect(corrected.offer?.id == offer.id)
        #expect(offer.activeDeliveries.map(\.id) == [corrected.id])

        #expect(sibling.state == .delivered, "The sibling is untouched")
        #expect(sibling.deliveredAt == at(1700))
        #expect(sibling.arrivedAtPickupAt == at(700))
        #expect(sibling.pickedUpAt == at(1000))
        #expect(sibling.grossEarnings == Money(minorUnits: 600))
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 0, inProgress: 1))
    }

    @Test("A delivery in another offer is untouched, and that offer stays terminal")
    func leavesAnotherOfferAlone() throws {
        let (_, shift, service) = try runningShift()
        let first = try service.startOffer(deliveryCount: 1, at: at(300))
        let second = try service.startOffer(deliveryCount: 1, at: at(1800))
        let corrected = try #require(first.deliveriesInOrder.first)
        let untouched = try #require(second.deliveriesInOrder.first)
        try deliver(corrected, using: service)
        try deliver(untouched, using: service, arrivingAt: 2000, pickingUpAt: 2200, deliveringAt: 2600)

        try service.reopenDelivered(corrected)

        #expect(first.state == .inProgress)
        #expect(second.state == .completed, "The other acceptance is not part of this correction")
        #expect(untouched.deliveredAt == at(2600))
        #expect(shift.offers.count == 2)
        #expect(shift.activeOffers.map(\.id) == [first.id])
    }

    @Test("A one-delivery offer's correction works exactly as a grouped one's does")
    func correctsAOneDeliveryOffer() throws {
        let (_, shift, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)
        let offer = try #require(delivery.offer)

        #expect(offer.state == .completed)

        try service.reopenDelivered(delivery)

        #expect(offer.state == .inProgress)
        #expect(offer.deliveryCount == 1)
        #expect(shift.numberedDeliveries.first?.number == 1, "and the number it had all shift is the number it keeps")
    }

    @Test("The shift stops counting it as completed, and its interval is open again")
    func movesTheShiftsOwnFigures() throws {
        let (_, shift, service) = try runningShift()
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 0))
        let beforeCorrection = shift.deliveryActiveTime()
        #expect(beforeCorrection.duration == 1200)
        #expect(beforeCorrection.countedIntervalCount == 1)

        try service.reopenDelivered(delivery)

        #expect(
            shift.deliverySummary == DeliverySummary(completed: 0, cancelled: 0, inProgress: 1),
            "A reopened delivery is one in progress, which is what it is"
        )
        let afterCorrection = shift.deliveryActiveTime()
        #expect(afterCorrection.duration == 0)
        #expect(afterCorrection.countedIntervalCount == 0)
        #expect(
            afterCorrection.unfinishedIntervalCount == 1,
            "Its active time is derived exactly as any unfinished delivery's is: not measured, not invented"
        )
        #expect(delivery.effectiveEarningsPerDeliveryHour == .unavailable(.deliveryNotCompleted))
    }

    // MARK: The Live Activity

    @Test("The shift's card reconciles from the store, with no rule of its own")
    func reconcilesTheLiveActivity() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let presenter = RecordingShiftActivityPresenter()
        let activity = ShiftLiveActivityService(
            context: context,
            presenter: presenter,
            now: { self.at(1800) },
            locale: { Locale(identifier: "en_US") }
        )
        let (_, _, service) = try runningShift(in: context)
        let delivery = try deliver(try service.startDelivery(at: at(300)), using: service)

        activity.reconcile()
        #expect(presenter.onlyContent?.activeDeliveryCount == 0)
        #expect(presenter.onlyContent?.completedDeliveryCount == 1)
        #expect(presenter.onlyContent?.deliveryStatus == nil)

        try service.reopenDelivered(delivery)
        activity.reconcile()

        #expect(presenter.onlyContent?.activeDeliveryCount == 1)
        #expect(presenter.onlyContent?.completedDeliveryCount == 0)
        #expect(presenter.onlyContent?.deliveryStatus == "Heading to the customer")
        #expect(
            presenter.onlyContent?.controls == [.deliveryStep(.complete), .startDelivery],
            "One delivery is open again, so the card offers that delivery's own next step"
        )
    }
}
