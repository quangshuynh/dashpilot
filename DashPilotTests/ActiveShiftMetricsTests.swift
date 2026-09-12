import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What DashPilot says about the shift the driver is in the middle of.
///
/// The rules under test are the live ones: that a route measured a few positions
/// at a time is the same route measured in one pass, that nothing is counted
/// across a pause or a gap, that working time stops while the shift is paused,
/// and that a figure whose inputs are missing is withheld with a reason rather
/// than filled in with a zero.
@MainActor
@Suite("Active shift metrics")
struct ActiveShiftMetricsTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    /// A straight run of positions, one every `interval` seconds, `metres` apart.
    private func run(
        from index: Int,
        count: Int,
        session: UUID?,
        interval: TimeInterval = 1,
        metres: Double = 20
    ) -> [RoutePoint] {
        (index..<(index + count)).map { step in
            SyntheticRoute.point(
                at: at(Double(step) * interval),
                northMetres: Double(step) * metres,
                captureSessionID: session
            )
        }
    }

    // MARK: The walk is the same walk

    @Test("A route extended a few positions at a time measures what measuring it whole does")
    func extendingMatchesMeasuringWhole() {
        let first = UUID()
        let second = UUID()
        // Two capture sessions with a break between them, which is the shape a
        // paused shift produces, plus a long silence inside the second.
        let route = run(from: 0, count: 40, session: first)
            + run(from: 200, count: 30, session: second)
            + run(from: 600, count: 25, session: second)

        let whole = RouteMileageCalculator().distance(of: route)

        var walk = RouteMileageAccumulator()
        for batch in stride(from: 0, to: route.count, by: 7) {
            walk.append(route[batch..<min(batch + 7, route.count)])
        }

        #expect(walk.distance() == whole)
        #expect(whole.isMeasured)
        #expect(whole.segmentCount == 3)
    }

    @Test("Extending in batches of one measures what measuring the route whole does")
    func extendingOneAtATimeMatchesMeasuringWhole() {
        let session = UUID()
        let route = run(from: 0, count: 60, session: session)

        var walk = RouteMileageAccumulator()
        for point in route { walk.append([point]) }

        #expect(walk.distance() == RouteMileageCalculator().distance(of: route))
    }

    @Test("A shift's own window is applied to an extended route exactly as to a whole one")
    func extendingRespectsTheShiftWindow() {
        let session = UUID()
        // The route starts five minutes into the shift and stops five minutes
        // before it ends, which is two uncovered ends.
        let route = run(from: 300, count: 30, session: session)
        let window = start...at(1_200)

        var walk = RouteMileageAccumulator()
        walk.append(route.shuffled())

        #expect(walk.distance(covering: window) == RouteMileageCalculator().distance(of: route, covering: window))
        #expect(walk.distance(covering: window).gapCount == 2)
        #expect(walk.distance().gapCount == 0, "A shift still running has no window, so it has no uncovered ends")
    }

    @Test("No distance is measured across a change of capture session")
    func measuresNoDistanceAcrossACaptureSessionChange() {
        let before = run(from: 0, count: 10, session: UUID())
        // Resuming mints one new session, and the driver is 2 km further on.
        let resumedSession = UUID()
        let after = (0..<10).map { step in
            SyntheticRoute.point(
                at: at(20 + Double(step)),
                northMetres: 2_000 + Double(step) * 20,
                captureSessionID: resumedSession
            )
        }

        var walk = RouteMileageAccumulator()
        walk.append(before)
        let atPause = walk.distance()
        walk.append(after)
        let afterResume = walk.distance()

        // Nine legs of 20 m on each side, and nothing at all for the 2 km
        // between where capture stopped and where it started again.
        #expect(SyntheticRoute.isCloseEnough(atPause.metres, to: 180))
        #expect(SyntheticRoute.isCloseEnough(afterResume.metres, to: 360))
        #expect(afterResume.gapCount == 1)
        #expect(afterResume.segmentCount == 2)
        #expect(afterResume.isPartial)
    }

    @Test("A position at or before the last one consumed is not counted")
    func refusesToWalkBackwards() {
        let session = UUID()
        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 5, session: session))
        let measured = walk.distance()

        // The same instant again, at a different place, and then an older one.
        walk.append([
            SyntheticRoute.point(at: at(4), northMetres: 9_999, captureSessionID: session),
            SyntheticRoute.point(at: at(1), northMetres: 8_888, captureSessionID: session)
        ])

        #expect(walk.distance() == measured, "Neither may add a jump to a route that was walked in order")
    }

    @Test("Mileage grows as positions are recorded and stops when they stop")
    func growsWhileRecordingAndStopsWhenItDoes() {
        let session = UUID()
        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 2, session: session))
        let first = walk.distance().metres

        walk.append(run(from: 2, count: 3, session: session))
        let second = walk.distance().metres

        // Nothing more arrives, which is what a parked vehicle, a paused shift
        // and a lost permission all look like from here.
        walk.append([RoutePoint]())
        let third = walk.distance().metres

        #expect(first > 0)
        #expect(second > first)
        #expect(third == second)
    }

    // MARK: Deciding what to read

    @Test("A measurement whose row count has not moved reads nothing more")
    func planIsUpToDateWhenNothingWasAdded() {
        var measurement = ActiveRouteMeasurement(shiftID: UUID())
        measurement.extend(with: run(from: 0, count: 5, session: UUID()), rowsRead: 5, storedRowCount: 5)

        #expect(measurement.plan(againstStoredRowCount: 5) == .upToDate)
    }

    @Test("A measurement reads only the rows after the last position it consumed")
    func planExtendsAfterTheLastConsumedPosition() {
        var measurement = ActiveRouteMeasurement(shiftID: UUID())
        #expect(measurement.plan(againstStoredRowCount: 5) == .extend(after: nil))

        measurement.extend(with: run(from: 0, count: 5, session: UUID()), rowsRead: 5, storedRowCount: 5)

        #expect(measurement.plan(againstStoredRowCount: 9) == .extend(after: at(4)))
    }

    @Test("A measurement whose rows have disappeared is taken again from scratch")
    func planRemeasuresWhenRowsDisappear() {
        var measurement = ActiveRouteMeasurement(shiftID: UUID())
        measurement.extend(with: run(from: 0, count: 10, session: UUID()), rowsRead: 10, storedRowCount: 10)

        // A rollback elsewhere on the shared context discards route samples that
        // capture has not flushed. A figure standing on rows the store no longer
        // holds is not a figure to keep extending.
        #expect(measurement.plan(againstStoredRowCount: 7) == .remeasure)
    }

    @Test("Rows read but not yet saved are counted, so discarding them is noticed")
    func noticesDiscardedUnsavedRows() {
        var measurement = ActiveRouteMeasurement(shiftID: UUID())
        // A context hands back its unsaved inserts as well as its saved rows, so
        // a reading can consume more than the store reports holding.
        measurement.extend(with: run(from: 0, count: 12, session: UUID()), rowsRead: 12, storedRowCount: 10)

        #expect(measurement.consumedRowCount == 12)
        #expect(
            measurement.plan(againstStoredRowCount: 10) == .remeasure,
            "A rollback that discarded the unsaved rows must not leave the figure standing on them"
        )
    }

    @Test("A row the walk could not use still keeps the measurement level with the store")
    func countsRowsRatherThanUsablePositions() {
        var measurement = ActiveRouteMeasurement(shiftID: UUID())
        let malformed = RoutePoint(timestamp: at(1), latitude: 0, longitude: 0, captureSessionID: UUID())
        measurement.extend(with: [malformed], rowsRead: 1, storedRowCount: 1)

        #expect(measurement.recordedDistance.usableSampleCount == 0)
        #expect(
            measurement.plan(againstStoredRowCount: 1) == .upToDate,
            "A row the walk declined must not make every later reading look like a discard"
        )
    }

    // MARK: Working time

    @Test("Working time is frozen while the shift is paused, and elapsed time is not")
    func workingTimeIsFrozenWhilePaused() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.beginPause(at: at(600))

        let atPause = shift.activeMetrics(for: .none, asOf: at(600))
        let tenMinutesLater = shift.activeMetrics(for: .none, asOf: at(1_200))

        #expect(atPause.workingDuration == 600)
        #expect(tenMinutesLater.workingDuration == 600, "A paused shift accrues no working time")
        #expect(tenMinutesLater.elapsedDuration == 1_200, "Elapsed time is the span, pauses included")
        #expect(tenMinutesLater.pausedTime.duration == 600)
        #expect(tenMinutesLater.isPaused)
        #expect(tenMinutesLater.lifecycleState == .paused)
    }

    @Test("Working time starts growing again from the moment the shift is resumed")
    func workingTimeResumes() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.beginPause(at: at(600))
        try shift.endOpenPause(at: at(1_200))

        let metrics = shift.activeMetrics(for: .none, asOf: at(1_500))

        #expect(metrics.elapsedDuration == 1_500)
        #expect(metrics.pausedTime.duration == 600)
        #expect(metrics.workingDuration == 900)
        #expect(metrics.lifecycleState == .running)
    }

    @Test("A shift that was never paused works for exactly as long as it has run")
    func workingEqualsElapsedWithoutAPause() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let metrics = shift.activeMetrics(for: .none, asOf: at(4_321))

        #expect(metrics.workingDuration == metrics.elapsedDuration)
        #expect(metrics.pausedTime == .none)
    }

    // MARK: What the panel says

    @Test("A shift with no position recorded says so rather than reporting no miles")
    func noRouteIsNotZeroMiles() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let metrics = shift.activeMetrics(for: .none, asOf: at(300))

        #expect(metrics.mileageLine(locale: .init(identifier: "en_US")) == "No route recorded")
        #expect(metrics.captureStatement == nil)
        #expect(!metrics.recordedDistance.isMeasured)
    }

    @Test("One recorded position is not enough to measure, and does not read as no route at all")
    func onePositionIsNotEnoughToMeasure() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 1, session: UUID()))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(300))

        #expect(metrics.mileageLine(locale: .init(identifier: "en_US")) == "Not enough route recorded to measure")
        #expect(metrics.recordedDistance.usableSampleCount == 1)
        #expect(metrics.captureStatement == nil)
    }

    @Test("A measured route states its mileage as recorded, with its segments and gaps beneath it")
    func statesRecordedMileage() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 81, session: UUID(), metres: 20))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(300))

        // 80 legs of 20 m is 1.6 km, which is almost exactly a mile.
        #expect(metrics.mileageLine(locale: .init(identifier: "en_US")) == "1.0 mi recorded")
        #expect(metrics.captureStatement == "1 capture segment · No capture gaps detected")
        #expect(metrics.partialMarker == nil, "No gap detected is not a claim that the route is complete")
    }

    @Test("A route with a break in it is marked partial while the shift is still running")
    func marksAPartialRoute() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 20, session: UUID()))
        walk.append(run(from: 400, count: 20, session: UUID()))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(500))

        #expect(metrics.partialMarker == "partial route")
        #expect(metrics.mileageLine(locale: .init(identifier: "en_US")).hasSuffix("· partial route"))
        #expect(metrics.captureStatement == "2 capture segments · 1 capture gap")
        #expect(metrics.spokenMileageStatement(locale: .init(identifier: "en_US")).contains("more miles were driven"))
    }

    @Test("The spoken mileage spells out the unit and carries the partial claim as a sentence")
    func spokenMileageIsSaidInWords() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 81, session: UUID(), metres: 20))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(300))

        let spoken = metrics.spokenMileageStatement(locale: .init(identifier: "en_US"))
        #expect(spoken.contains("miles"))
        #expect(!spoken.contains(" mi "))
    }

    // MARK: Deliveries

    @Test("A running shift with no deliveries says so rather than showing a zero")
    func statesNoDeliveryInProgress() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        #expect(shift.activeMetrics(for: .none, asOf: at(60)).deliveryStatement == "No delivery in progress")
    }

    @Test("A running shift counts the deliveries open now and the ones it has finished")
    func countsActiveAndFinishedDeliveries() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let delivered = Delivery(shift: shift, acceptedAt: at(60))
        try delivered.markArrivedAtPickup(at: at(120))
        try delivered.markPickedUp(at: at(180))
        try delivered.markDelivered(at: at(600))
        let cancelled = Delivery(shift: shift, acceptedAt: at(200))
        try cancelled.cancel(at: at(300))
        _ = Delivery(shift: shift, acceptedAt: at(700))
        _ = Delivery(shift: shift, acceptedAt: at(800))

        let metrics = shift.activeMetrics(for: .none, asOf: at(900))

        #expect(metrics.deliveryStatement == "2 deliveries in progress · 1 completed · 1 cancelled")
        #expect(metrics.spokenDeliveryStatement == "2 deliveries in progress. 1 delivered. 1 cancelled")
        #expect(metrics.deliverySummary.inProgress == 2)
    }

    // MARK: Earnings and rates

    @Test("A running shift infers no earnings and derives no rate")
    func derivesNoRateWhileRunning() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 81, session: UUID(), metres: 20))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(3_600))

        #expect(metrics.grossEarnings == nil, "A missing amount is never a zero")
        #expect(!metrics.rates.hasAnyRate)
        #expect(metrics.rates.grossPerWorkingHour.unavailability == .shiftNotCompleted)
        #expect(metrics.rates.grossPerDeliveryActiveHour.unavailability == .shiftNotCompleted)
        #expect(metrics.rates.grossPerRecordedMile.unavailability == .shiftNotCompleted)
    }

    @Test("The reason no rate is shown is the shift's own reason, said once")
    func statesWhyThereIsNoRate() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let metrics = shift.activeMetrics(for: .none, asOf: at(3_600))
        let notice = try #require(metrics.rateNotice)

        #expect(notice == ShiftRateUnavailability.shiftNotCompleted.explanation)
        #expect(notice.contains("still running"))
        // Nothing about the missing figure may be phrased as an amount.
        #expect(!notice.contains("0"))
    }

    @Test("Recording an amount is refused while the shift runs, so the panel has none to show")
    func anAmountCannotBeRecordedOnARunningShift() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        #expect(throws: ShiftError.shiftNotCompleted) {
            try shift.setGrossEarnings(Money(amount: 100))
        }
        #expect(shift.activeMetrics(for: .none, asOf: at(3_600)).grossEarnings == nil)
    }

    @Test("A running shift is never described as ended")
    func isNeverEnded() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        #expect(shift.activeMetrics(for: .none, asOf: at(60)).lifecycleState == .running)
        try shift.beginPause(at: at(60))
        #expect(shift.activeMetrics(for: .none, asOf: at(90)).lifecycleState == .paused)
    }

    @Test("The live figures never claim miles driven, total mileage or a completed route")
    func makesNoClaimItCannotSupport() throws {
        let context = ModelContext(try makeContainer())
        let shift = Shift(startedAt: start)
        context.insert(shift)

        var walk = RouteMileageAccumulator()
        walk.append(run(from: 0, count: 20, session: UUID()))
        walk.append(run(from: 400, count: 20, session: UUID()))
        let metrics = shift.activeMetrics(for: walk.distance(), asOf: at(500))

        let locale = Locale(identifier: "en_US")
        let sentences = [
            metrics.mileageLine(locale: locale),
            metrics.spokenMileageStatement(locale: locale),
            metrics.captureStatement,
            metrics.deliveryStatement,
            metrics.rateNotice
        ].compactMap { $0 }

        for sentence in sentences {
            let lowered = sentence.lowercased()
            #expect(!lowered.contains("miles driven") || lowered.contains("more miles were driven"))
            #expect(!lowered.contains("total mileage"))
            #expect(!lowered.contains("complete route"))
            #expect(!lowered.contains("estimated"))
            #expect(!lowered.contains("projected"))
        }
    }
}
