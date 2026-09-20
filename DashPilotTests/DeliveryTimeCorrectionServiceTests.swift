import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedTimeCorrectionSave: Error {}

/// Correcting a finished delivery's recorded times through the store: what one
/// correction writes, what every figure derived from those times becomes, what
/// must not move at all, and what a refused save leaves behind.
///
/// ## Why so much of this suite is about things not moving
///
/// A delivery's timestamps are read by more of this app than any other fact it
/// holds: the delivery's own duration and wait, its hourly figure, the shift's
/// union of delivery intervals, and every period figure over those. The
/// interesting claims are therefore split in two — that all of those **do**
/// follow a correction, with no invalidation step anywhere, and that the route,
/// the mileage, the money, the grouping, the pickup identity and the terminal
/// outcome do **not**.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held model and the authoritative store can disagree
/// after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp, amount, place and coordinate here is invented.
@MainActor
@Suite("Delivery time correction service")
struct DeliveryTimeCorrectionServiceTests {
    private let calendar: Calendar
    private let start: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        // Wednesday, 17 June 2026, 04:00 UTC, so a four-hour shift and every
        // correction to it stay inside one day.
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17)))
        start = midnight.addingTimeInterval(4 * 3600)
    }

    /// `minutes` after the shift's start.
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotDeliveryTimeCorrectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func deliveries(_ context: ModelContext) -> DeliveryService {
        DeliveryService(context: context)
    }

    private func refusing(_ context: ModelContext) -> DeliveryService {
        DeliveryService(context: context, commit: { _ in throw RefusedTimeCorrectionSave() })
    }

    // MARK: The fixture

    /// A four-hour completed shift holding one delivery whose completion was
    /// recorded far too late, which is the real recovery case.
    ///
    /// | Minutes in | What the delivery records |
    /// | --- | --- |
    /// | 60 | Accepted |
    /// | 70 | Arrived at the pickup |
    /// | 80 | Picked up |
    /// | 180 | Delivered, an hour and a half after the food reached the door |
    ///
    /// Everything goes through the shipping path, so the store is one the app
    /// really produces. The recorded amount is `$24.00`, which over the two
    /// hours it appears to have taken is exactly `$12.00` per recorded delivery
    /// hour and over the forty minutes it really took is exactly `$36.00`. Both
    /// divide without a remainder on purpose: a rate that has to be rounded
    /// would put the rounding policy under test rather than the correction.
    @discardableResult
    private func lateDeliveryShift(in context: ModelContext) throws -> (shift: Shift, delivery: Delivery) {
        let shifts = ShiftService(context: context)
        let service = deliveries(context)
        let shift = try shifts.startShift(at: start)
        let offer = try service.startOffer(deliveryCount: 1, at: at(60))
        let delivery = try #require(offer.deliveriesInOrder.first)

        try service.markArrivedAtPickup(delivery, at: at(70))
        try service.markPickedUp(delivery, at: at(80))
        try service.markDelivered(delivery, at: at(180))
        try service.setGrossEarnings(Money(minorUnits: 2_400), on: delivery)
        try shifts.endActiveShift(at: at(240))

        return (shift, delivery)
    }

    /// The delivery's record with one stage moved, which is what an editor's
    /// draft is.
    private func proposal(
        _ delivery: Delivery,
        _ stage: DeliveryState,
        at minutes: Double
    ) -> DeliveryLifecycleRecord {
        DeliveryLifecycleRecord(delivery).replacing(stage, with: at(minutes))
    }

    // MARK: The correction itself

    @Test("A completion recorded late is corrected to when it happened")
    func correctsALateCompletion() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)

        let correction = try deliveries(context).correctRecordedTimes(
            delivery,
            to: proposal(delivery, .delivered, at: 100)
        )

        #expect(delivery.deliveredAt == at(100))
        #expect(correction.movedEvents == [.delivered])
        #expect(delivery.state == .delivered, "and it is still a delivered delivery")
    }

    @Test("Each of the four recorded stages can be corrected on its own")
    func correctsEachStage() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        let service = deliveries(context)

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .accepted, at: 55))
        #expect(delivery.acceptedAt == at(55))

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .arrivedAtPickup, at: 65))
        #expect(delivery.arrivedAtPickupAt == at(65))

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .pickedUp, at: 75))
        #expect(delivery.pickedUpAt == at(75))

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 105))
        #expect(delivery.deliveredAt == at(105))

        #expect(delivery.acceptedAt == at(55), "and the earlier corrections survived the later ones")
        #expect(delivery.arrivedAtPickupAt == at(65))
        #expect(delivery.pickedUpAt == at(75))
    }

    @Test("A correction survives a reopen of the store, instant by instant")
    func aCorrectionIsPersisted() throws {
        let (url, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let deliveryID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
            let (_, delivery) = try lateDeliveryShift(in: context)
            deliveryID = delivery.id
            try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID })

        #expect(stored.deliveredAt == at(100))
        // Asserted as values: a correction that shifted one of these by a second
        // would pass a presence check.
        #expect(stored.acceptedAt == at(60))
        #expect(stored.arrivedAtPickupAt == at(70))
        #expect(stored.pickedUpAt == at(80))
        #expect(stored.cancelledAt == nil)
        #expect(stored.shift?.endedAt == at(240), "and the shift's own end did not move")
    }

    // MARK: What the correction derives

    @Test("The delivery's completed duration follows the correction")
    func completedDurationFollows() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        #expect(delivery.completedDuration == 7_200, "Two hours as recorded")

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(delivery.completedDuration == 2_400, "and forty minutes once corrected")
    }

    @Test("The recorded pickup wait follows a corrected pickup, and is untouched by a corrected completion")
    func pickupWaitFollows() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        #expect(delivery.pickupWait == 600)

        let service = deliveries(context)
        try service.correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))
        #expect(delivery.pickupWait == 600, "A completion moving says nothing about the wait")

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .pickedUp, at: 90))
        #expect(delivery.pickupWait == 1_200, "and moving the pickup is what moves it")
    }

    @Test("The per-delivery hourly figure follows, over the same recorded amount")
    func hourlyRateFollows() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        #expect(
            delivery.effectiveEarningsPerDeliveryHour.amount == Money(minorUnits: 1_200),
            "$24.00 over the two hours it appears to have taken"
        )

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(
            delivery.effectiveEarningsPerDeliveryHour.amount == Money(minorUnits: 3_600),
            "$24.00 over the forty minutes it really took"
        )
        #expect(delivery.grossEarnings == Money(minorUnits: 2_400), "and the amount itself did not move")
    }

    @Test("A tipped delivery's hourly figure still reads both amounts after a correction")
    func tipsStayInTheNumerator() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        _ = try deliveries(context).addAdditionalTip(
            Money(minorUnits: 600),
            method: .cash,
            on: delivery,
            at: at(185)
        )

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(delivery.additionalTips.count == 1, "The tip is still recorded")
        #expect(delivery.effectiveEarnings.amount == Money(minorUnits: 3_000), "and still part of what it paid")
        #expect(
            delivery.effectiveEarningsPerDeliveryHour.amount == Money(minorUnits: 4_500),
            "$30.00 over forty minutes"
        )
    }

    @Test("The shift's delivery active time follows, and the union is what moves")
    func shiftActiveTimeFollows() throws {
        let context = try makeContext()
        let (shift, delivery) = try lateDeliveryShift(in: context)
        let window = try #require(shift.completedWindow)
        let calculator = DeliveryActiveTimeCalculator()

        #expect(
            calculator.activeTime(of: shift.deliveries.map(DeliveryActiveInterval.init), within: window).duration
                == 7_200
        )

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(
            calculator.activeTime(of: shift.deliveries.map(DeliveryActiveInterval.init), within: window).duration
                == 2_400,
            "The union is measured again from the corrected interval"
        )
    }

    @Test("Stacked deliveries stay independent, and the union is not the sum")
    func stackedDeliveriesStayIndependent() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = deliveries(context)
        let shift = try shifts.startShift(at: start)
        let offer = try service.startOffer(deliveryCount: 2, at: at(60))
        let first = try #require(offer.deliveriesInOrder.first)
        let second = try #require(offer.deliveriesInOrder.last)

        for delivery in [first, second] {
            try service.markArrivedAtPickup(delivery, at: at(70))
            try service.markPickedUp(delivery, at: at(80))
        }
        try service.markDelivered(first, at: at(120))
        try service.markDelivered(second, at: at(140))
        try shifts.endActiveShift(at: at(240))

        let window = try #require(shift.completedWindow)
        let calculator = DeliveryActiveTimeCalculator()
        #expect(
            calculator.activeTime(of: shift.deliveries.map(DeliveryActiveInterval.init), within: window).duration
                == 4_800,
            "Sixty to a hundred and forty is eighty minutes, not the two lifecycles added together"
        )

        try service.correctRecordedTimes(first, to: proposal(first, .delivered, at: 100))

        #expect(second.deliveredAt == at(140), "The sibling did not move")
        #expect(second.acceptedAt == at(60))
        #expect(second.pickedUpAt == at(80))
        #expect(first.deliveredAt == at(100))
        #expect(
            calculator.activeTime(of: shift.deliveries.map(DeliveryActiveInterval.init), within: window).duration
                == 4_800,
            "and the union is unchanged, because the sibling still reaches further than the one corrected"
        )
    }

    // MARK: What must not move

    @Test("The route and the shift's recorded mileage are untouched")
    func theRouteIsUntouched() throws {
        let context = try makeContext()
        let (shift, delivery) = try lateDeliveryShift(in: context)

        let session = UUID()
        for step in 0..<10 {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(
                        at: at(90).addingTimeInterval(Double(step) * 20),
                        northMetres: Double(step) * 400
                    ),
                    captureSessionID: session
                )
            )
        }
        try context.save()

        let before = shift.recordedDistance()
        #expect(before.metres > 0, "The fixture recorded a route to leave alone")

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        let samples = shift.routeSamples()
        #expect(samples.count == 10, "Not one position was deleted")
        #expect(samples.allSatisfy { $0.captureSessionID == session }, "and none was restamped")
        let after = shift.recordedDistance()
        #expect(after.metres == before.metres, "so the recorded mileage is exactly the distance it was")
        #expect(after.isPartial == before.isPartial)
    }

    @Test("The terminal outcome, the money, the place and the grouping are all left alone")
    func everythingElseIsLeftAlone() throws {
        let context = try makeContext()
        let (shift, delivery) = try lateDeliveryShift(in: context)
        let places = PickupPlaceService(context: context)
        _ = try places.assignPlace(named: "Synthetic Noodle House", to: delivery, at: at(70))
        _ = try deliveries(context).addAdditionalTip(
            Money(minorUnits: 500),
            method: .platform,
            on: delivery,
            at: at(185)
        )
        let offerID = delivery.offer?.id
        let placeID = delivery.pickupPlace?.id

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(delivery.state == .delivered, "Still terminal, and terminal the same way")
        #expect(delivery.cancelledAt == nil)
        #expect(delivery.grossEarnings == Money(minorUnits: 2_400))
        #expect(delivery.additionalTips.count == 1)
        #expect(delivery.additionalTips.first?.amount == Money(minorUnits: 500))
        #expect(delivery.expectedEarnings == nil, "and no amount was invented either")
        #expect(delivery.offer?.id == offerID, "The offer it arrived in is the same row")
        #expect(delivery.pickupPlace?.id == placeID, "and so is the place it named")
        #expect(shift.startedAt == start, "The shift's own boundary did not move")
        #expect(shift.endedAt == at(240))
    }

    @Test("A cancelled delivery's recorded times are correctable, and it stays cancelled")
    func aCancelledDeliveryIsCorrectable() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = deliveries(context)
        _ = try shifts.startShift(at: start)
        let offer = try service.startOffer(deliveryCount: 1, at: at(60))
        let delivery = try #require(offer.deliveriesInOrder.first)
        try service.markArrivedAtPickup(delivery, at: at(70))
        try service.cancelDelivery(delivery, at: at(150))
        try shifts.endActiveShift(at: at(240))

        try service.correctRecordedTimes(delivery, to: proposal(delivery, .cancelled, at: 95))

        #expect(delivery.state == .cancelled)
        #expect(delivery.cancelledAt == at(95))
        #expect(delivery.deliveredAt == nil, "Nothing turned it into a completion")
        #expect(delivery.arrivedAtPickupAt == at(70))
        #expect(delivery.completedDuration == nil, "and a cancelled delivery still has no delivery duration")
    }

    @Test("A stage a cancelled delivery never recorded is not created by correcting it")
    func anAbsentStageIsNotFabricated() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = deliveries(context)
        _ = try shifts.startShift(at: start)
        let offer = try service.startOffer(deliveryCount: 1, at: at(60))
        let delivery = try #require(offer.deliveriesInOrder.first)
        try service.cancelDelivery(delivery, at: at(90))
        try shifts.endActiveShift(at: at(240))

        #expect(delivery.arrivedAtPickupAt == nil, "It never reached a pickup")

        let withArrival = DeliveryLifecycleRecord(delivery).recordingAnArrival(at: at(70))
        #expect(throws: DeliveryLifecycleError.invalidTimeCorrection(.eventNotRecorded(.arrivedAtPickup))) {
            try service.correctRecordedTimes(delivery, to: withArrival)
        }
        #expect(delivery.arrivedAtPickupAt == nil, "and it still has not")
        #expect(!context.hasChanges)
    }

    // MARK: Refusals

    @Test("A time before the shift started is refused, and nothing is written")
    func anEventBeforeTheShiftIsRefused() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)

        #expect(throws: DeliveryLifecycleError.invalidTimeCorrection(.precedesShiftStart(.accepted))) {
            try self.deliveries(context).correctRecordedTimes(delivery, to: self.proposal(delivery, .accepted, at: -10))
        }
        #expect(delivery.acceptedAt == at(60))
        #expect(!context.hasChanges)
    }

    @Test("A time after the shift ended is refused, and nothing is written")
    func anEventAfterTheShiftIsRefused() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)

        #expect(throws: DeliveryLifecycleError.invalidTimeCorrection(.followsShiftEnd(.delivered))) {
            try self.deliveries(context).correctRecordedTimes(delivery, to: self.proposal(delivery, .delivered, at: 250))
        }
        #expect(delivery.deliveredAt == at(180))
        #expect(!context.hasChanges)
    }

    @Test("A time that breaks the lifecycle order is refused, and the refusal names the conflicting event")
    func anOutOfOrderTimeIsRefused() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)

        #expect(
            self.deliveries(context)
                .timeCorrectionRefusal(on: delivery, to: self.proposal(delivery, .delivered, at: 75))
                == .outOfOrder(event: .delivered, mustNotPrecede: .pickedUp),
            "and it names the pickup, which is the fact the driver has to correct next"
        )
        #expect(throws: DeliveryLifecycleError.self) {
            try self.deliveries(context).correctRecordedTimes(delivery, to: self.proposal(delivery, .delivered, at: 75))
        }
        #expect(delivery.deliveredAt == at(180), "Nothing was written")
        #expect(delivery.pickedUpAt == at(80), "and above all the pickup was not dragged back to make room")
        #expect(!context.hasChanges)
    }

    @Test("Correcting the conflicting event as well is what resolves it")
    func correctingBothResolvesTheConflict() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)

        let both = DeliveryLifecycleRecord(delivery)
            .replacing(.pickedUp, with: at(72))
            .replacing(.delivered, with: at(75))
        try deliveries(context).correctRecordedTimes(delivery, to: both)

        #expect(delivery.pickedUpAt == at(72))
        #expect(delivery.deliveredAt == at(75))
    }

    @Test("A delivery on a running shift is refused")
    func aRunningShiftIsRefused() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = deliveries(context)
        _ = try shifts.startShift(at: start)
        let offer = try service.startOffer(deliveryCount: 1, at: at(60))
        let delivery = try #require(offer.deliveriesInOrder.first)
        try service.markArrivedAtPickup(delivery, at: at(70))
        try service.markPickedUp(delivery, at: at(80))
        try service.markDelivered(delivery, at: at(120))

        #expect(throws: DeliveryLifecycleError.invalidTimeCorrection(.shiftNotCompleted)) {
            try service.correctRecordedTimes(delivery, to: self.proposal(delivery, .delivered, at: 100))
        }
        #expect(delivery.deliveredAt == at(120))
    }

    // MARK: Atomicity

    @Test("A refused save leaves every original instant, not some of them")
    func aRefusedSaveIsAtomic() throws {
        let (url, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let deliveryID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
            let (_, delivery) = try lateDeliveryShift(in: context)
            deliveryID = delivery.id

            // Every stage moves at once, which is the proposal a partial write
            // would leave visibly half applied.
            let everything = DeliveryLifecycleRecord(delivery)
                .replacing(.accepted, with: at(50))
                .replacing(.arrivedAtPickup, with: at(55))
                .replacing(.pickedUp, with: at(65))
                .replacing(.delivered, with: at(100))

            #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedTimeCorrectionSave())) {
                try self.refusing(context).correctRecordedTimes(delivery, to: everything)
            }
            #expect(!context.hasChanges, "The rollback left nothing pending")
        }

        // Read through a fresh context: an already-held model and the store can
        // disagree after a rollback, and the store is what a relaunch shows.
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID })

        #expect(stored.acceptedAt == at(60))
        #expect(stored.arrivedAtPickupAt == at(70))
        #expect(stored.pickedUpAt == at(80))
        #expect(stored.deliveredAt == at(180))
    }

    @Test("A correction judged against times that have since moved is refused rather than written over them")
    func aStaleCorrectionIsRefused() throws {
        let context = try makeContext()
        let (_, delivery) = try lateDeliveryShift(in: context)
        let service = deliveries(context)

        // Built while the sheet was open, on the times the delivery then had.
        let stale = try delivery.timeCorrection(to: proposal(delivery, .delivered, at: 150))

        // Something else corrects it first.
        try service.correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        #expect(throws: DeliveryTimeCorrectionRefusal.recordedTimesChanged) {
            try delivery.apply(stale)
        }
        #expect(delivery.deliveredAt == at(100), "and the newer time stands")
    }

    // MARK: Export

    @Test("Export carries the corrected times through the fields it already had")
    func exportCarriesTheCorrectionWithNoNewField() throws {
        let context = try makeContext()
        let (shift, delivery) = try lateDeliveryShift(in: context)

        let before = try shift.exportRecord(for: shift.recordedDistance())
        let recorded = try #require(before.deliveries.first)
        #expect(recorded.deliveredAt == at(180))
        #expect(recorded.acceptedToDeliveredSeconds == 7_200)

        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        let after = try shift.exportRecord(for: shift.recordedDistance())
        let corrected = try #require(after.deliveries.first)

        // Every assertion below is about a **value** moving. No field is added,
        // removed or redefined by this feature, which is why the format version
        // does not move: the four instants, the two durations and the hourly
        // figure have carried exactly this since the format had them.
        #expect(corrected.deliveredAt == at(100))
        #expect(corrected.acceptedAt == at(60), "and the instants that did not move exported as they were")
        #expect(corrected.arrivedAtPickupAt == at(70))
        #expect(corrected.pickedUpAt == at(80))
        #expect(corrected.state == recorded.state, "The terminal outcome is the one it exported before")
        #expect(corrected.acceptedToDeliveredSeconds == 2_400, "The derived duration followed")
        #expect(corrected.pickupWaitSeconds == recorded.pickupWaitSeconds, "and the wait did not")
        #expect(corrected.effectiveEarningsPerDeliveryHour != recorded.effectiveEarningsPerDeliveryHour)
        #expect(corrected.grossEarnings == recorded.grossEarnings, "over the amount the driver typed")
        #expect(after.route.usableSampleCount == before.route.usableSampleCount, "and no position left")
        #expect(after.endedAt == before.endedAt, "and the shift's own end did not move")
    }

    // MARK: The shift end correction it unblocks

    @Test("The real recovery: a late completion blocks an earlier shift end until the delivery is corrected")
    func theRealRecovery() throws {
        let context = try makeContext()
        let (shift, delivery) = try lateDeliveryShift(in: context)
        let endCorrections = ShiftEndCorrectionService(context: context)

        // 1. The driver actually stopped 2 hr 30 min in, and the end correction
        //    refuses because the delivery records a completion after that.
        let refusal = try #require(endCorrections.refusal(on: shift, to: at(150)))
        guard case let .precedesRecordedDeliveryWork(blocking) = refusal else {
            Issue.record("Expected the delivery refusal, met \(refusal)")
            return
        }

        // 2. It identifies the delivery and the event.
        #expect(blocking.deliveryNumber == 1)
        #expect(blocking.deliveryTitle == "Delivery 1")
        #expect(blocking.event == .delivered)
        #expect(blocking.occurredAt == at(180))
        let sentence = try #require(ShiftEndCorrectionError.invalidCorrection(refusal).errorDescription)
        #expect(sentence.contains("Delivery 1"))
        #expect(sentence.contains("Delivered"))

        // 3. The driver corrects the delivery's own record.
        try deliveries(context).correctRecordedTimes(delivery, to: proposal(delivery, .delivered, at: 100))

        // 4. The same end correction is now accepted.
        #expect(endCorrections.refusal(on: shift, to: at(150)) == nil)
        try endCorrections.correct(shift, to: at(150))

        #expect(shift.endedAt == at(150))
        #expect(shift.completedDuration == 9_000, "2 hr 30 min")
        #expect(delivery.deliveredAt == at(100), "and the delivery kept the time the driver corrected it to")
    }
}

private extension DeliveryLifecycleRecord {
    /// This record with an arrival written into it, which is the one thing the
    /// correction must refuse.
    ///
    /// ``replacing(_:with:)`` deliberately cannot do it, so the suite builds the
    /// forbidden shape directly rather than asserting against a draft the editor
    /// could never produce.
    func recordingAnArrival(at instant: Date) -> Self {
        Self(
            acceptedAt: acceptedAt,
            arrivedAtPickupAt: instant,
            pickedUpAt: pickedUpAt,
            deliveredAt: deliveredAt,
            cancelledAt: cancelledAt
        )
    }
}
