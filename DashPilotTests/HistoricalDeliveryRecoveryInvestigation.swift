import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Evidence for `feat/historical-delivery-recovery`: what a **completed** shift
/// holding a non-terminal delivery actually does to the readers that already
/// exist.
///
/// ## Why this suite exists, and why it changes nothing
///
/// A driver who marks a delivery delivered by mistake can take it back while the
/// shift is running. Once the shift has ended the app refuses, and the question
/// this interval asked is whether that refusal is a missing feature or a load
/// bearing rule. The answer could not be settled by reading: several of the
/// readers involved degrade quietly rather than fail, so what a period summary,
/// an export and an offer would actually say had to be measured.
///
/// So this suite **constructs the row the app refuses to create** and asserts
/// what every affected reader does with it. It is a record of an investigation,
/// not a specification of wanted behaviour: nothing here asks for a change, and
/// several assertions below describe output the project considers wrong. They
/// are written down so the refusal is supported by measurements rather than by
/// an argument, and so that anyone who later proposes historical reopening
/// starts from the list of things it would have to answer for.
///
/// ## How the row is built
///
/// Only through the **models**, never through a service. `ShiftService.endShift`
/// refuses to end a shift holding an active delivery, and
/// `DeliveryService.reopenDelivered` refuses an ended shift, so the two service
/// guards are asserted first and then deliberately stepped around by calling
/// `Delivery.reopenFromDelivered()` on a shift that has already ended. That the
/// construction needs a model-level call is itself part of the finding.
///
/// Every timestamp, amount and place below is invented.
@MainActor
@Suite("Historical delivery recovery investigation")
struct HistoricalDeliveryRecoveryInvestigation {
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

    /// A shift with `deliveryCount` deliveries, each driven to delivered through
    /// the service, then ended through the service.
    ///
    /// Everything here goes through the shipping path, so the store this returns
    /// is one the app really produces.
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

    /// The anomalous store: a completed shift whose first delivery no longer
    /// records a completion.
    ///
    /// The reopening is applied to the **model**, because that is the only way
    /// to reach this state. See the two service assertions below.
    private func completedShiftHoldingAReopenedDelivery(
        in context: ModelContext,
        deliveryCount: Int = 1
    ) throws -> (shift: Shift, reopened: Delivery, others: [Delivery]) {
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: deliveryCount)
        guard let reopened = deliveries.first else {
            Issue.record("The fixture recorded no delivery")
            throw DeliveryRecoveryRefusal.notDelivered
        }
        try reopened.reopenFromDelivered()
        try context.save()
        return (shift, reopened, Array(deliveries.dropFirst()))
    }

    // MARK: The two guards that make this state unreachable

    @Test("A shift refuses to end while a delivery is active, which is what proves every delivery in a completed shift terminal")
    func endingRefusesAnActiveDelivery() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let deliveries = DeliveryService(context: context)
        try shifts.startShift(at: start)
        let delivery = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(delivery, at: at(600))

        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 1)) {
            try shifts.endActiveShift(at: at(7_200))
        }
    }

    @Test("Reopening is refused once the shift has ended, and the store is untouched")
    func reopeningRefusesAnEndedShift() throws {
        let context = try makeContext()
        let (_, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        let service = DeliveryService(context: context)

        #expect(throws: DeliveryLifecycleError.cannotReopenOnEndedShift) {
            try service.reopenDelivered(delivery)
        }
        #expect(delivery.deliveredAt == at(1_500))
        #expect(delivery.state == .delivered)
    }

    // MARK: What the row costs, once it exists

    /// The finding that decided the interval.
    ///
    /// Reopening **removes** a timestamp and writes none. On a running shift the
    /// driver puts it back by finishing the delivery. On an ended shift nothing
    /// can: every lifecycle write goes through `validateShift(of:)`, which
    /// requires a running shift, so the delivery can never be delivered again,
    /// never be cancelled, and never be reopened again either. The correction is
    /// one-way and lossy.
    @Test("A delivery reopened inside a completed shift can never be finished, cancelled or reopened again")
    func aReopenedHistoricalDeliveryIsStuck() throws {
        let context = try makeContext()
        let (_, reopened, _) = try completedShiftHoldingAReopenedDelivery(in: context)
        let service = DeliveryService(context: context)

        #expect(reopened.state == .pickedUp)
        #expect(reopened.deliveredAt == nil)

        #expect(throws: DeliveryLifecycleError.deliveryNotOnARunningShift) {
            try service.markDelivered(reopened, at: at(1_800))
        }
        #expect(throws: DeliveryLifecycleError.deliveryNotOnARunningShift) {
            try service.cancelDelivery(reopened, at: at(1_800))
        }
        #expect(throws: DeliveryLifecycleError.cannotReopenOnEndedShift) {
            try service.reopenDelivered(reopened)
        }
    }

    @Test("The shift keeps its end, so nothing about the shift itself moves")
    func theShiftStaysEnded() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        #expect(shift.endedAt == at(7_200))
        #expect(shift.lifecycleState == .ended)
        #expect(shift.isActive == false)
        #expect(shift.completedDuration == 7_200)
    }

    // MARK: Delivery active time

    /// The union has no end to use, so the interval is dropped and counted.
    /// Nothing on any screen reads `unfinishedIntervalCount`, so the shortfall
    /// is invisible where the figure is shown.
    @Test("The reopened delivery leaves the shift's delivery active time unmeasurable")
    func activeTimeBecomesUnmeasurable() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        let activeTime = shift.deliveryActiveTime()
        #expect(activeTime.sourceIntervalCount == 1)
        #expect(activeTime.countedIntervalCount == 0)
        #expect(activeTime.unfinishedIntervalCount == 1)
        #expect(activeTime.isAvailable == false)
        #expect(activeTime.nonDeliveryDuration(inElapsed: shift.completedWorkingDuration) == nil)
    }

    @Test("With a sibling still delivered, the shift's active time silently shrinks instead")
    func activeTimeShrinksSilently() throws {
        let context = try makeContext()
        let (shift, _, others) = try completedShiftHoldingAReopenedDelivery(in: context, deliveryCount: 2)
        let sibling = try #require(others.first)

        let activeTime = shift.deliveryActiveTime()
        #expect(activeTime.sourceIntervalCount == 2)
        #expect(activeTime.countedIntervalCount == 1)
        #expect(activeTime.unfinishedIntervalCount == 1)
        // Only the sibling's own interval is left: accepted with the offer at
        // 60, delivered at 1_560.
        #expect(activeTime.isAvailable)
        #expect(activeTime.duration == sibling.deliveredAt!.timeIntervalSince(sibling.acceptedAt))
    }

    @Test("The shift's gross per delivery active hour stops being available")
    func theActiveHourRateIsLost() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)
        try shift.setGrossEarnings(Money(minorUnits: 12_000))

        let metrics = shift.metrics(for: .none)
        #expect(metrics.grossPerDeliveryActiveHour == .unavailable(.deliveryActiveTimeNotMeasurable))
        // The two rates that do not depend on a delivery interval are untouched.
        #expect(metrics.grossPerWorkingHour.amount != nil)
    }

    // MARK: Offers

    @Test("The offer inside a finished shift reports itself in progress, and never terminal")
    func theOfferNeverFinishes() throws {
        let context = try makeContext()
        let (shift, reopened, _) = try completedShiftHoldingAReopenedDelivery(in: context)
        let offer = try #require(reopened.offer)

        #expect(offer.state == .inProgress)
        #expect(offer.state.isTerminal == false)
        #expect(offer.state.isActive)
        #expect(offer.state.historyDescription == "In progress")
        #expect(shift.activeOffers.count == 1)
    }

    // MARK: The shift's own counts

    @Test("The completed shift counts a delivery as still in progress")
    func theShiftCountsWorkInProgress() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        #expect(shift.deliverySummary == DeliverySummary(completed: 0, cancelled: 0, inProgress: 1))
        #expect(shift.deliverySummary.statement == "0 deliveries completed · 1 still in progress")
        #expect(shift.activeDeliveries.count == 1)
    }

    // MARK: Period aggregation

    /// The coverage break, and the one that is a printed untruth rather than a
    /// degraded figure.
    ///
    /// `recordedDeliveryEarnings` reads every delivery's amount; the eligible
    /// count beside it is `terminalDeliveryCount`. Reopening moves the second
    /// and not the first, because a gross amount already recorded is
    /// deliberately preserved through a reopening. The coverage sentence then
    /// claims more contributors than it had eligible records.
    @Test("Recorded delivery earnings outnumber the deliveries the period says were eligible")
    func deliveryEarningsCoverageBreaks() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context, deliveryCount: 2)
        for delivery in deliveries { try delivery.setGrossEarnings(Money(minorUnits: 900)) }
        let reopened = try #require(deliveries.first)
        try reopened.reopenFromDelivered()
        try context.save()

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        // The amount survives the reopening, by design.
        #expect(reopened.grossEarnings == Money(minorUnits: 900))
        #expect(metrics.recordedDeliveryEarnings == Money(minorUnits: 1_800))
        #expect(metrics.deliveryEarningsCoverage.contributingCount == 2)
        #expect(metrics.deliveryEarningsCoverage.eligibleCount == 1)
        #expect(metrics.deliveryEarningsCoverage.statement(noun: "delivery", pluralNoun: "deliveries")
            == "2 of 1 delivery")
        // `missingCount` clamps and `isComplete` uses `>=`, so nothing throws
        // and nothing warns. The sentence above is the only symptom.
        #expect(metrics.deliveryEarningsCoverage.missingCount == 0)
        #expect(metrics.deliveryEarningsCoverage.isComplete)
    }

    @Test("A finished period reports a delivery still in progress")
    func thePeriodReportsWorkInProgress() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        #expect(metrics.deliverySummary.inProgress == 1)
        #expect(metrics.deliverySummary.completed == 0)
        #expect(metrics.deliverySummary.spokenStatement.contains("still in progress"))
        // Period membership itself is untouched: a shift belongs to the period
        // containing its `startedAt`, and the shift is still completed.
        #expect(metrics.completedShiftCount == 1)
    }

    @Test("The period loses its delivery active duration and the rate over it")
    func thePeriodLosesActiveTime() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)
        try shift.setGrossEarnings(Money(minorUnits: 12_000))

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        #expect(metrics.deliveryActiveDuration == nil)
        #expect(metrics.deliveryActiveCoverage == MetricCoverage(contributingCount: 0, eligibleCount: 1))
        #expect(metrics.grossPerDeliveryActiveHour.amount == nil)
        #expect(metrics.nonDeliveryDuration == nil)
    }

    // MARK: Export

    @Test("The shift exports, and its delivery carries an active state with a null delivered time")
    func theShiftStillExports() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        // Export eligibility is `endedAt != nil` and nothing else, so the file
        // is written rather than refused.
        let record = try shift.exportRecord(for: .none)
        let delivery = try #require(record.deliveries.first)

        #expect(record.deliveredCount == 0)
        #expect(record.cancelledCount == 0)
        #expect(delivery.state == .pickedUp)
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.acceptedToDeliveredSeconds == nil)
        #expect(record.deliveryActiveSeconds == nil)
        #expect(record.nonDeliverySeconds == nil)
        // The shift record has no in-progress column, so a reader totalling the
        // two counts it does carry is one delivery short with nothing saying so.
        #expect(record.deliveredCount + record.cancelledCount < record.deliveries.count)
    }

    @Test("A period export carries a non-zero in-progress count, which the format documents as impossible")
    func thePeriodExportCarriesWorkInProgress() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)

        #expect(PeriodDeliveriesExport(metrics).inProgressCount == 1)
    }

    // MARK: What is genuinely unaffected

    /// The half of the question that came back safe. Both surfaces key on
    /// `ShiftService.activeShift()`, which reads `endedAt == nil` and nothing
    /// about a delivery, so preserving the shift's end is sufficient to keep
    /// both stopped.
    @Test("Route capture stays stopped and idle")
    func routeCaptureDoesNotRestart() throws {
        let context = try makeContext()
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(servicesEnabled: true, status: .authorizedWhenInUse, accuracy: .full)
        )
        let tracking = LocationTrackingService(context: context, authorization: authorization, provider: provider)

        _ = try completedShiftHoldingAReopenedDelivery(in: context)
        tracking.synchronize()

        #expect(provider.isUpdating == false)
        #expect(provider.startCount == 0)
        #expect(tracking.state == .idle)
    }

    @Test("No Live Activity is created or left behind")
    func noLiveActivityIsCreated() throws {
        let context = try makeContext()
        let presenter = RecordingShiftActivityPresenter()
        let liveActivity = ShiftLiveActivityService(context: context, presenter: presenter, now: { self.at(7_300) })

        _ = try completedShiftHoldingAReopenedDelivery(in: context)
        liveActivity.reconcile()

        #expect(presenter.startCount == 0)
        #expect(presenter.live.isEmpty)
    }

    @Test("The shift cannot accept a new delivery, and no new shift is implied")
    func noNewWorkCanBeRecorded() throws {
        let context = try makeContext()
        let (shift, _, _) = try completedShiftHoldingAReopenedDelivery(in: context)

        #expect(throws: OfferError.shiftAlreadyEnded) {
            try shift.beginOffer(deliveryCount: 1, at: at(7_300))
        }
        #expect(throws: DeliveryLifecycleError.noActiveShift) {
            try DeliveryService(context: context).startDelivery(at: at(7_300))
        }
        #expect(try ShiftService(context: context).activeShift() == nil)
    }

    @Test("The recorded pickup wait and the money already entered are untouched")
    func theRecordedFactsSurvive() throws {
        let context = try makeContext()
        let (shift, deliveries) = try completedShift(in: context)
        let delivery = try #require(deliveries.first)
        try delivery.setGrossEarnings(Money(minorUnits: 725))
        let waitBefore = delivery.pickupWait
        try delivery.reopenFromDelivered()
        try context.save()

        #expect(delivery.acceptedAt == at(60))
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(delivery.pickedUpAt == at(900))
        #expect(delivery.pickupWait == waitBefore)
        #expect(delivery.grossEarnings == Money(minorUnits: 725))
        // The per-delivery rate goes, because it divides by acceptance to
        // completion and there is no completion any more.
        #expect(delivery.grossPerDeliveryHour == .unavailable(.deliveryNotCompleted))
        #expect(shift.periodRecord(for: .none).pickupWaits.count == 1)
    }
}
