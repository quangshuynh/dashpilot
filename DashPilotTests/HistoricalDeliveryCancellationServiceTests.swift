import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedHistoricalSave: Error {}

/// Correcting a historical completion through the store: which shifts allow it,
/// what one correction writes, what it must leave exactly as it was, and what a
/// refused save leaves behind.
///
/// ## Why so much of this suite is about things not moving
///
/// The correction exists to change **one** fact about a finished shift, and a
/// finished shift is what every historical figure in the app is built from. So
/// the interesting claims are almost all negative: the shift stays ended, the
/// union of delivery intervals does not move, the period the shift belongs to
/// does not change, the mileage is untouched, and the delivery-earnings coverage
/// cannot reach the state `HistoricalDeliveryRecoveryInvestigation` measured for
/// the *other* correction on this row.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held model and the authoritative store can disagree
/// after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp, amount and place here is invented.
@MainActor
@Suite("Historical delivery cancellation service")
struct HistoricalDeliveryCancellationServiceTests {
    private let calendar: Calendar
    private let start: Date
    private let day: ReportingPeriod

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        // Wednesday, 17 June 2026, midnight UTC.
        start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17)))
        day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotHistoricalCancellationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    /// A shift with `deliveryCount` deliveries in one offer, each driven to
    /// delivered through the service, then ended through the service.
    ///
    /// Everything goes through the shipping path, so the store this returns is
    /// one the app really produces, and the correction is applied to a real
    /// completed shift rather than to a hand-built row.
    @discardableResult
    private func completedShift(
        in context: ModelContext,
        deliveryCount: Int = 1,
        endingAt: TimeInterval = 7_200
    ) throws -> (shift: Shift, deliveries: [Delivery]) {
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        let shift = try shifts.startShift(at: start)
        let offer = try deliveries.startOffer(deliveryCount: deliveryCount, at: at(60))

        for (index, delivery) in offer.deliveriesInOrder.enumerated() {
            let step = TimeInterval(index) * 60
            try deliveries.markArrivedAtPickup(delivery, at: at(600 + step))
            try deliveries.markPickedUp(delivery, at: at(900 + step))
            try deliveries.markDelivered(delivery, at: at(1_500 + step))
        }

        try shifts.endActiveShift(at: at(endingAt))
        return (shift, offer.deliveriesInOrder)
    }

    private func refusing(_ context: ModelContext) -> DeliveryService {
        DeliveryService(context: context, commit: { _ in throw RefusedHistoricalSave() })
    }

    // MARK: The correction itself

    @Test("A completed shift's delivered delivery becomes cancelled at the instant it recorded")
    func correctsOneHistoricalCompletion() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        let service = DeliveryService(context: context)

        try service.correctCompletionToCancellation(delivery)

        #expect(delivery.state == .cancelled)
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.cancelledAt == at(1_500))
    }

    @Test("Only the ending moves, and it survives a reopen of the store")
    func onlyTheEndingMoves() throws {
        let (url, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let deliveryID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
            let (_, deliveries) = try completedShift(in: context)
            let delivery = try #require(deliveries.first)
            deliveryID = delivery.id
            try DeliveryService(context: context).correctCompletionToCancellation(delivery)
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let stored = try #require(
            try reopened.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID }
        )

        #expect(stored.state == .cancelled)
        #expect(stored.deliveredAt == nil)
        #expect(stored.cancelledAt == at(1_500))
        // The events before the ending, asserted as values: a correction that
        // shifted one of them by a second would pass a presence check.
        #expect(stored.acceptedAt == at(60))
        #expect(stored.arrivedAtPickupAt == at(600))
        #expect(stored.pickedUpAt == at(900))
        // And the shift is exactly as finished as it was.
        #expect(stored.shift?.endedAt == at(7_200))
        #expect(stored.shift?.isActive == false)
    }

    /// The rule the whole interval rests on, asserted against a real store
    /// rather than against the value type alone.
    @Test("The delivery stays terminal and the shift gains no work in progress")
    func theShiftStaysTerminalThroughout() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let service = DeliveryService(context: context)

        try service.correctCompletionToCancellation(try #require(deliveries.first))

        #expect(shift.lifecycleState == .ended)
        #expect(shift.endedAt == at(7_200))
        #expect(shift.activeDeliveries.isEmpty)
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
        #expect(shift.deliverySummary.inProgress == 0)
        #expect(try DeliveryService(context: context).activeDeliveries().isEmpty)
    }

    @Test("A second correction is refused and writes nothing")
    func aSecondCorrectionIsRefused() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        let service = DeliveryService(context: context)
        try service.correctCompletionToCancellation(delivery)

        #expect(throws: DeliveryLifecycleError.invalidCancellation(.alreadyCancelled)) {
            try service.correctCompletionToCancellation(delivery)
        }
        #expect(delivery.cancelledAt == at(1_500))
        #expect(delivery.deliveredAt == nil)
        #expect(context.hasChanges == false)
    }

    @Test("A delivery cancelled during the shift is refused and does not move")
    func anAlreadyCancelledDeliveryIsRefused() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        try shifts.startShift(at: start)
        let delivery = try service.startDelivery(at: at(60))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.cancelDelivery(delivery, at: at(1_000))
        try shifts.endActiveShift(at: at(7_200))

        #expect(throws: DeliveryLifecycleError.invalidCancellation(.alreadyCancelled)) {
            try service.correctCompletionToCancellation(delivery)
        }
        #expect(delivery.cancelledAt == at(1_000))
    }

    /// The load-bearing shift rule, and the half that sends the driver
    /// somewhere useful rather than merely refusing.
    @Test("A running shift refuses it, and the reopening that belongs there still works")
    func aRunningShiftIsRefused() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        try shifts.startShift(at: start)
        let delivery = try service.startDelivery(at: at(60))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.markPickedUp(delivery, at: at(900))
        try service.markDelivered(delivery, at: at(1_500))

        #expect(throws: DeliveryLifecycleError.cannotCorrectOnRunningShift) {
            try service.correctCompletionToCancellation(delivery)
        }
        #expect(delivery.state == .delivered)
        #expect(delivery.deliveredAt == at(1_500))
        #expect(delivery.cancelledAt == nil)

        // The correction the running shift does offer is unaffected.
        #expect(try service.reopenDelivered(delivery) == .pickedUp)
    }

    @Test("A paused shift is refused too, because a paused shift has not ended")
    func aPausedShiftIsRefused() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        try shifts.startShift(at: start)
        let delivery = try service.startDelivery(at: at(60))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.markPickedUp(delivery, at: at(900))
        try service.markDelivered(delivery, at: at(1_500))
        try shifts.pauseActiveShift(at: at(1_800))

        #expect(throws: DeliveryLifecycleError.cannotCorrectOnRunningShift) {
            try service.correctCompletionToCancellation(delivery)
        }
        #expect(delivery.state == .delivered)

        // And it is allowed once that shift is actually finished, which is the
        // point: the refusal is about the shift being unfinished, not about the
        // pause.
        try shifts.resumeActiveShift(at: at(2_400))
        try shifts.endActiveShift(at: at(7_200))
        try service.correctCompletionToCancellation(delivery)
        #expect(delivery.state == .cancelled)
    }

    @Test("The refusals say what they refused, and send the driver to the right correction")
    func theRefusalsAreWorded() {
        #expect(
            DeliveryLifecycleError.cannotCorrectOnRunningShift.errorDescription?
                .contains("reopened and finished properly") == true
        )
        #expect(
            DeliveryLifecycleError.invalidCancellation(.alreadyCancelled).errorDescription?
                .contains("already recorded as cancelled") == true
        )
        #expect(
            DeliveryLifecycleError.invalidCancellation(.notDelivered).errorDescription?
                .contains("no completion to correct") == true
        )
        // Every case carries a sentence, so nothing can reach a screen as an
        // empty message.
        for refusal in HistoricalCancellationRefusal.allCases {
            let sentence = DeliveryLifecycleError.invalidCancellation(refusal).errorDescription
            #expect(sentence?.isEmpty == false, "\(refusal) has no sentence")
        }
    }

    @Test("A refused save leaves the delivery exactly as delivered as the store had it")
    func aRefusedSaveRollsBack() throws {
        let (url, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let container = try ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)
        let (_, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        let deliveryID = delivery.id

        #expect(throws: DeliveryLifecycleError.storeUnavailable(underlying: RefusedHistoricalSave())) {
            try refusing(context).correctCompletionToCancellation(delivery)
        }

        #expect(context.hasChanges == false)

        // The store is what a relaunch shows, and it still holds the completion.
        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first { $0.id == deliveryID })
        #expect(stored.state == .delivered)
        #expect(stored.deliveredAt == at(1_500))
        #expect(stored.cancelledAt == nil)
        #expect(stored.acceptedAt == at(60))
        #expect(stored.arrivedAtPickupAt == at(600))
        #expect(stored.pickedUpAt == at(900))
    }

    // MARK: The offer, and the siblings

    @Test("A one-delivery offer becomes cancelled")
    func aSoleDeliveryMakesItsOfferCancelled() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context)
        let corrected = try #require(deliveries.first)

        try DeliveryService(context: context).correctCompletionToCancellation(corrected)

        let offer = try #require(corrected.offer)
        #expect(offer.state == .cancelled)
        #expect(offer.state.isTerminal)
        #expect(offer.deliveries.count == 1)
        #expect(shift.offers.count == 1)
    }

    @Test("One of a two-delivery offer leaves the offer partly completed and the sibling untouched")
    func oneOfAGroupedOfferIsCorrected() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let corrected = try #require(deliveries.first)
        let sibling = try #require(deliveries.last)
        let offer = try #require(corrected.offer)

        try DeliveryService(context: context).correctCompletionToCancellation(corrected)

        #expect(offer.state == .partiallyCompleted)
        #expect(offer.state.isTerminal)
        // Membership is not rewritten: the correction reads one delivery and
        // writes one delivery.
        #expect(offer.deliveries.count == 2)
        #expect(corrected.offer === offer)
        #expect(sibling.offer === offer)
        #expect(offer.acceptedAt == at(60))
        // And the sibling is byte for byte what it was.
        #expect(sibling.state == .delivered)
        #expect(sibling.acceptedAt == at(60))
        #expect(sibling.arrivedAtPickupAt == at(660))
        #expect(sibling.pickedUpAt == at(960))
        #expect(sibling.deliveredAt == at(1_560))
        #expect(sibling.cancelledAt == nil)
        #expect(shift.numberedDeliveries.map(\.number) == [1, 2])
    }

    @Test("Correcting every delivery of an offer makes the offer cancelled")
    func everyDeliveryOfAnOfferIsCorrected() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let service = DeliveryService(context: context)

        for delivery in deliveries {
            try service.correctCompletionToCancellation(delivery)
        }

        #expect(try #require(deliveries.first?.offer).state == .cancelled)
    }

    // MARK: What must not move

    /// Every figure the interval promised to preserve, measured on one store
    /// before and after.
    @Test("The shift's own metrics are unchanged apart from how its deliveries ended")
    func theShiftsMetricsAreUnchanged() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        try shift.setGrossEarnings(Money(minorUnits: 8_625))
        try context.save()

        let activeTimeBefore = shift.deliveryActiveTime()
        let workingBefore = shift.completedWorkingDuration
        let elapsedBefore = shift.completedDuration
        let metricsBefore = shift.metrics(for: .none)
        let waitsBefore = shift.deliveriesInOrder.map(\.pickupWait)

        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        #expect(shift.deliveryActiveTime() == activeTimeBefore)
        #expect(shift.deliveryActiveTime().unfinishedIntervalCount == 0)
        #expect(shift.completedWorkingDuration == workingBefore)
        #expect(shift.completedDuration == elapsedBefore)
        #expect(shift.grossEarnings == Money(minorUnits: 8_625))
        #expect(shift.deliveriesInOrder.map(\.pickupWait) == waitsBefore)
        // The rates are derived from the shift's own gross over its working and
        // delivery-active time, none of which the correction touches.
        let metricsAfter = shift.metrics(for: .none)
        #expect(metricsAfter.grossPerWorkingHour == metricsBefore.grossPerWorkingHour)
        #expect(metricsAfter.grossPerDeliveryActiveHour == metricsBefore.grossPerDeliveryActiveHour)
        // The one thing that does move, and the one thing that should.
        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
    }

    @Test("Recorded mileage and the route behind it are untouched")
    func theRouteIsUntouched() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context)
        let session = UUID()
        for step in 0..<12 {
            let point = SyntheticRoute.point(
                at: shift.startedAt.addingTimeInterval(Double(step) * 20),
                northMetres: Double(step) * 400,
                captureSessionID: session
            )
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: point.timestamp,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    horizontalAccuracy: 8,
                    captureSessionID: session
                )
            )
        }
        try context.save()

        let distanceBefore = shift.recordedDistance()
        let sampleCountBefore = shift.routeSampleCount

        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        #expect(shift.recordedDistance() == distanceBefore)
        #expect(shift.routeSampleCount == sampleCountBefore)
    }

    @Test("The money on the delivery is preserved, and neither amount becomes the other")
    func theMoneyIsPreserved() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        try shifts.startShift(at: start)
        let delivery = try service.startDelivery(at: at(60))
        try service.markArrivedAtPickup(delivery, at: at(600))
        try service.setExpectedEarnings(Money(minorUnits: 850), on: delivery)
        try service.markPickedUp(delivery, at: at(900))
        try service.markDelivered(delivery, at: at(1_500))
        try service.setGrossEarnings(Money(minorUnits: 1_275), on: delivery)
        try shifts.endActiveShift(at: at(7_200))

        try service.correctCompletionToCancellation(delivery)

        #expect(delivery.grossEarnings == Money(minorUnits: 1_275))
        #expect(delivery.expectedEarnings == Money(minorUnits: 850))
        // A cancelled delivery may truthfully carry a recorded amount, so the
        // amount is still editable afterwards and is not silently erased.
        try service.setGrossEarnings(Money(minorUnits: 500), on: delivery)
        #expect(delivery.grossEarnings == Money(minorUnits: 500))
    }

    @Test("A pickup place keeps the delivery, and the place keeps its recorded wait")
    func thePickupPlaceAndItsWaitSurvive() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        let places = PickupPlaceService(context: context)
        try places.assignPlace(named: "Corner Noodle Bar", to: delivery, at: at(1_600))
        let place = try #require(delivery.pickupPlace)
        let sample = try #require(PickupWaitSample(delivery))

        try DeliveryService(context: context).correctCompletionToCancellation(delivery)

        #expect(delivery.pickupPlace === place)
        #expect(PickupWaitSample(delivery) == sample)
        #expect(delivery.pickupWait == 300)
    }

    // MARK: The period the shift is reported in

    @Test("Period membership, working time and active time are all unchanged")
    func thePeriodIsUnchanged() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        try shift.setGrossEarnings(Money(minorUnits: 8_625))
        try context.save()

        let before = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        let after = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        #expect(after.completedShiftCount == before.completedShiftCount)
        #expect(after.completedShiftCount == 1)
        #expect(after.workingDuration == before.workingDuration)
        #expect(after.deliveryActiveDuration == before.deliveryActiveDuration)
        #expect(after.nonDeliveryDuration == before.nonDeliveryDuration)
        #expect(after.recordedGrossEarnings == before.recordedGrossEarnings)
        #expect(after.grossPerWorkingHour == before.grossPerWorkingHour)
        #expect(after.medianPickupWait == before.medianPickupWait)
        #expect(after.pickupWaitSampleCount == before.pickupWaitSampleCount)
        // The counts move, and nothing goes into "in progress".
        #expect(after.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
        #expect(after.deliverySummary.inProgress == 0)
        #expect(after.deliverySummary.spokenStatement.contains("still in progress") == false)
    }

    /// The regression for the anomaly `feat/historical-delivery-recovery`
    /// measured, and the reason this correction is the shape the app can carry.
    ///
    /// Reopening a delivery inside a completed shift preserves a recorded gross
    /// amount while dropping the delivery out of `terminalDeliveryCount`, so the
    /// coverage sentence claims more contributors than eligible records
    /// (`2 of 1 delivery`). A cancellation is still terminal, so both halves of
    /// that fraction move together, which is to say neither of them moves at all.
    @Test("Delivery-earnings coverage cannot outnumber its eligible records")
    func deliveryEarningsCoverageStaysPossible() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let service = DeliveryService(context: context)
        for delivery in deliveries {
            try service.setGrossEarnings(Money(minorUnits: 900), on: delivery)
        }

        let before = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)
        #expect(before.deliveryEarningsCoverage.contributingCount == 2)
        #expect(before.deliveryEarningsCoverage.eligibleCount == 2)

        try service.correctCompletionToCancellation(try #require(deliveries.first))

        let after = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        // The amount survives, exactly as it survives a reopening.
        #expect(try #require(deliveries.first).grossEarnings == Money(minorUnits: 900))
        #expect(after.recordedDeliveryEarnings == Money(minorUnits: 1_800))
        // And the denominator survives with it, which is the whole difference.
        #expect(after.deliveryEarningsCoverage.contributingCount == 2)
        #expect(after.deliveryEarningsCoverage.eligibleCount == 2)
        #expect(after.deliveryEarningsCoverage.contributingCount <= after.deliveryEarningsCoverage.eligibleCount)
        #expect(
            after.deliveryEarningsCoverage.statement(noun: "delivery", pluralNoun: "deliveries")
                == "2 of 2 deliveries"
        )
        #expect(shift.periodRecord(for: .none).terminalDeliveryCount == 2)
    }

    @Test("A corrected delivery that carried no amount is still counted as an eligible record")
    func anUnpaidCorrectedDeliveryStaysEligible() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let service = DeliveryService(context: context)
        try service.setGrossEarnings(Money(minorUnits: 900), on: try #require(deliveries.last))

        try service.correctCompletionToCancellation(try #require(deliveries.first))

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        // Missing is not zero: one of the two recorded an amount, and the
        // corrected one is still a terminal delivery that recorded none.
        #expect(metrics.deliveryEarningsCoverage.contributingCount == 1)
        #expect(metrics.deliveryEarningsCoverage.eligibleCount == 2)
        #expect(metrics.deliveryEarningsCoverage.isComplete == false)
    }

    // MARK: Nothing outside the store is touched

    /// The hazard the previous investigation named and cleared for reopening,
    /// asserted here for the operation that actually ships.
    @Test("Route capture stays idle and no Live Activity is requested")
    func noBackgroundSurfaceWakesUp() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context)
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(
                servicesEnabled: true,
                status: .authorizedWhenInUse,
                accuracy: .full
            )
        )
        let tracking = LocationTrackingService(context: context, authorization: authorization, provider: provider)
        let presenter = RecordingShiftActivityPresenter()
        let liveActivity = ShiftLiveActivityService(context: context, presenter: presenter, now: { self.at(7_300) })

        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        tracking.synchronize()
        liveActivity.reconcile()

        #expect(provider.isUpdating == false)
        #expect(provider.startCount == 0)
        #expect(tracking.state == .idle)
        #expect(presenter.startCount == 0)
        #expect(presenter.live.isEmpty)
    }

    // MARK: The export

    private func exportedShift(_ shift: Shift) throws -> [String: Any] {
        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let parsed = try JSONSerialization.jsonObject(with: try ExportDocumentEncoder().json(for: document))
        let object = try #require(parsed as? [String: Any])
        let shifts = try #require(object["shifts"] as? [[String: Any]])
        return try #require(shifts.first)
    }

    @Test("JSON carries the correction through the fields it already has")
    func jsonCarriesTheCorrection() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        let service = DeliveryService(context: context)
        try service.setGrossEarnings(Money(minorUnits: 900), on: try #require(deliveries.first))

        try service.correctCompletionToCancellation(try #require(deliveries.first))

        let exported = try exportedShift(shift)
        let rows = try #require(exported["deliveries"] as? [[String: Any]])
        let corrected = try #require(rows.first)
        let sibling = try #require(rows.last)

        #expect(corrected["state"] as? String == "cancelled")
        // An explicit null rather than an absent key, which is what the format
        // already promises for every optional in it.
        #expect(corrected["deliveredAt"] is NSNull)
        #expect(corrected["cancelledAt"] as? String == ExportTimestamp.string(at(1_500)))
        // The grouping key is a fact about which acceptance this delivery came
        // in, and a correction to how it ended says nothing about that.
        #expect(corrected["offerNumber"] as? Int == 1)
        #expect(corrected["number"] as? Int == 1)
        // Derived from a completion the delivery no longer records, so both go.
        #expect(corrected["acceptedToDeliveredSeconds"] is NSNull)
        #expect(corrected["grossPerDeliveryHour"] is NSNull)
        // The recorded amount and the recorded wait are facts of their own.
        // A quoted decimal string, which is how every amount in this format is
        // written: a JSON number would be read back as a binary float.
        #expect(corrected["grossEarnings"] as? String == "9.00")
        #expect(corrected["pickupWaitSeconds"] as? Int == 300)

        // The sibling is written exactly as it was.
        #expect(sibling["state"] as? String == "delivered")
        #expect(sibling["deliveredAt"] as? String == ExportTimestamp.string(at(1_560)))
        #expect(sibling["cancelledAt"] is NSNull)

        // The shift's own two counts follow the deliveries under them.
        #expect(exported["deliveredCount"] as? Int == 1)
        #expect(exported["cancelledCount"] as? Int == 1)
        // And the union of their intervals does not move, because the instant
        // did not: both were accepted at 60 s and the later one ended at
        // 1_560 s, so the union is 1_500 s whichever of them says it ended by
        // being delivered.
        #expect(exported["deliveryActiveSeconds"] as? Int == 1_500)
    }

    @Test("The format version does not move, because nothing in the file changed meaning")
    func theFormatVersionIsUnmoved() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context)
        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let parsed = try JSONSerialization.jsonObject(with: try ExportDocumentEncoder().json(for: document))
        let object = try #require(parsed as? [String: Any])

        // Both `deliveredAt` and `cancelledAt` were already in the format, and
        // `cancelled` was already one of the states a delivery could be exported
        // in. Nothing was added, removed, renamed or redefined.
        #expect(object["formatVersion"] as? Int == 3)
        #expect(ExportFormat.version == 3)
    }

    @Test("CSV says the same thing through the columns it already has")
    func csvCarriesTheCorrection() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        try DeliveryService(context: context).correctCompletionToCancellation(try #require(deliveries.first))

        let document = ExportDocument(
            scope: .allHistory,
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let text = String(decoding: try ExportDocumentEncoder().csv(for: document), as: UTF8.self)
        let records = text.split(separator: "\r\n", omittingEmptySubsequences: true).map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        let header = try #require(records.first)
        #expect(header.count == 36)
        let rows = records.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
        #expect(rows.count == 2)

        let corrected = try #require(rows.first)
        #expect(corrected["deliveryState"] == "cancelled")
        // An empty cell, never a zero, for a fact the delivery no longer holds.
        #expect(corrected["deliveryDeliveredAt"] == "")
        #expect(corrected["deliveryCancelledAt"] == ExportTimestamp.string(at(1_500)))
        #expect(corrected["deliveryAcceptedToDeliveredSeconds"] == "")
        #expect(corrected["deliveryGrossPerDeliveryHour"] == "")
        // Untouched by the correction.
        #expect(corrected["deliveryNumber"] == "1")
        #expect(corrected["deliveryOfferNumber"] == "1")
        #expect(corrected["deliveryAcceptedAt"] == ExportTimestamp.string(at(60)))
        #expect(corrected["deliveryArrivedAtPickupAt"] == ExportTimestamp.string(at(600)))
        #expect(corrected["deliveryPickedUpAt"] == ExportTimestamp.string(at(900)))
        #expect(corrected["deliveryPickupWaitSeconds"] == "300")
        // The shift columns repeated on every row follow the deliveries.
        #expect(corrected["shiftDeliveredCount"] == "1")
        #expect(corrected["shiftCancelledCount"] == "1")
        #expect(corrected["shiftDeliveryActiveSeconds"] == "1500")

        let sibling = try #require(rows.last)
        #expect(sibling["deliveryState"] == "delivered")
        #expect(sibling["deliveryDeliveredAt"] == ExportTimestamp.string(at(1_560)))
        #expect(sibling["deliveryCancelledAt"] == "")
    }
}
