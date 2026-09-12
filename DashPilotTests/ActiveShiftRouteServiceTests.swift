import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Reading a running shift's route out of the store a few positions at a time.
///
/// The claim under test is that the live figure is the same figure the finished
/// shift is reported with: ``Shift/recordedDistance(using:)`` measures the whole
/// route in one pass, and every case here asserts the extended measurement
/// against it rather than against a number written down in the test.
@MainActor
@Suite("Active shift route service")
struct ActiveShiftRouteServiceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// Stores `count` positions, one a second, 20 m apart, in `session`.
    @discardableResult
    private func record(
        _ count: Int,
        from index: Int,
        for shift: Shift,
        in session: UUID,
        context: ModelContext
    ) throws -> [RouteSample] {
        let samples = (index..<(index + count)).map { step in
            RouteSample(
                shift: shift,
                sample: SyntheticRoute.sample(at: at(Double(step)), northMetres: Double(step) * 20),
                captureSessionID: session
            )
        }
        for sample in samples { context.insert(sample) }
        try context.save()
        return samples
    }

    // MARK: Extending

    @Test("A first reading measures the whole stored route")
    func measuresTheWholeRouteFirst() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(30, from: 0, for: shift, in: UUID(), context: context)

        let measurement = try ActiveShiftRouteService(context: context).measurement(extending: nil, of: shift)

        #expect(measurement.recordedDistance == shift.recordedDistance())
        #expect(measurement.consumedRowCount == 30)
        #expect(measurement.recordedDistance.isMeasured)
    }

    @Test("A reading with nothing new consumes nothing and changes nothing")
    func readsNothingWhenTheRouteHasNotGrown() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(30, from: 0, for: shift, in: UUID(), context: context)

        let service = ActiveShiftRouteService(context: context)
        let first = try service.measurement(extending: nil, of: shift)
        let second = try service.measurement(extending: first, of: shift)

        #expect(second == first)
        #expect(first.plan(againstStoredRowCount: 30) == .upToDate)
    }

    @Test("Extending a measurement position by position matches measuring the route whole")
    func extendingMatchesTheWholeRouteMeasurement() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let session = UUID()
        let service = ActiveShiftRouteService(context: context)

        var measurement: ActiveRouteMeasurement?
        var recorded = 0
        for batch in 0..<8 {
            try record(5, from: recorded, for: shift, in: session, context: context)
            recorded += 5
            measurement = try service.measurement(extending: measurement, of: shift)

            let live = try #require(measurement)
            #expect(live.recordedDistance == shift.recordedDistance(), "Batch \(batch) drifted from the whole-route measurement")
            #expect(live.consumedRowCount == recorded)
        }
    }

    @Test("The figure grows while positions are recorded")
    func growsWhilePositionsArrive() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let session = UUID()
        let service = ActiveShiftRouteService(context: context)

        try record(5, from: 0, for: shift, in: session, context: context)
        let first = try service.measurement(extending: nil, of: shift)

        try record(5, from: 5, for: shift, in: session, context: context)
        let second = try service.measurement(extending: first, of: shift)

        #expect(first.recordedDistance.metres > 0)
        #expect(second.recordedDistance.metres > first.recordedDistance.metres)
        #expect(second.recordedDistance.segmentCount == 1)
    }

    // MARK: A pause

    @Test("A paused shift's mileage does not move, however long the pause lasts")
    func mileageIsFrozenWhilePaused() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try record(20, from: 0, for: shift, in: UUID(), context: context)
        try shift.beginPause(at: at(20))
        try context.save()

        let service = ActiveShiftRouteService(context: context)
        let atPause = try service.measurement(extending: nil, of: shift)
        // Nothing is stored while paused: the filter rejects every candidate and
        // capture is stopped before the pause is even written.
        let later = try service.measurement(extending: atPause, of: shift)

        #expect(later.recordedDistance == atPause.recordedDistance)
        #expect(shift.activeMetrics(for: later.recordedDistance, asOf: at(2_000)).workingDuration == 20)
    }

    @Test("Resuming measures nothing across the break, however far the driver moved during it")
    func measuresNoDistanceAcrossAPause() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let before = UUID()
        try record(20, from: 0, for: shift, in: before, context: context)

        try shift.beginPause(at: at(20))
        try shift.endOpenPause(at: at(620))
        try context.save()

        let service = ActiveShiftRouteService(context: context)
        let atPause = try service.measurement(extending: nil, of: shift)

        // Ten minutes of driving happened during the break, and resuming mints a
        // new capture session, so none of it may be measured.
        let after = UUID()
        let resumed = (0..<20).map { step in
            RouteSample(
                shift: shift,
                sample: SyntheticRoute.sample(
                    at: at(620 + Double(step)),
                    northMetres: 12_000 + Double(step) * 20
                ),
                captureSessionID: after
            )
        }
        for sample in resumed { context.insert(sample) }
        try context.save()

        let afterResume = try service.measurement(extending: atPause, of: shift)

        #expect(afterResume.recordedDistance == shift.recordedDistance())
        #expect(
            SyntheticRoute.isCloseEnough(
                afterResume.recordedDistance.metres,
                to: atPause.recordedDistance.metres * 2
            ),
            "Only the two recorded stretches may be counted, and neither the 11.6 km between them"
        )
        #expect(afterResume.recordedDistance.gapCount == 1)
        #expect(afterResume.recordedDistance.segmentCount == 2)
        #expect(afterResume.recordedDistance.isPartial)
    }

    // MARK: Rows that disappear

    @Test("A measurement standing on rows the store no longer holds is taken again")
    func remeasuresWhenRowsDisappear() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let session = UUID()
        let samples = try record(30, from: 0, for: shift, in: session, context: context)

        let service = ActiveShiftRouteService(context: context)
        let measured = try service.measurement(extending: nil, of: shift)

        // The shape a rollback on the shared context leaves: rows this
        // measurement already counted are gone.
        for sample in samples.suffix(10) { context.delete(sample) }
        try context.save()

        let again = try service.measurement(extending: measured, of: shift)

        #expect(again.consumedRowCount == 20)
        #expect(again.recordedDistance == shift.recordedDistance())
        #expect(again.recordedDistance.metres < measured.recordedDistance.metres)
    }

    @Test("A measurement of another shift is never extended onto this one")
    func neverExtendsAcrossShifts() throws {
        let context = try makeContext()
        let first = Shift(startedAt: start)
        let second = Shift(startedAt: at(10_000))
        context.insert(first)
        context.insert(second)
        try record(20, from: 0, for: first, in: UUID(), context: context)

        let service = ActiveShiftRouteService(context: context)
        let firstMeasurement = try service.measurement(extending: nil, of: first)
        let secondMeasurement = try service.measurement(extending: firstMeasurement, of: second)

        #expect(secondMeasurement.shiftID == second.id)
        #expect(secondMeasurement.consumedRowCount == 0)
        #expect(secondMeasurement.recordedDistance == RouteDistance.none)
    }

    @Test("A shift with no route yet reports no route rather than no miles")
    func reportsNoRouteBeforeAnythingIsRecorded() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        let measurement = try ActiveShiftRouteService(context: context).measurement(extending: nil, of: shift)

        #expect(!measurement.recordedDistance.isMeasured)
        #expect(measurement.recordedDistance.usableSampleCount == 0)
        #expect(
            shift.activeMetrics(for: measurement.recordedDistance, asOf: at(60))
                .mileageLine(locale: Locale(identifier: "en_US")) == "No route recorded"
        )
    }

    // MARK: The smallest correct reading

    @Test("Only the positions recorded since the last reading are read again")
    func readsOnlyWhatIsNew() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let session = UUID()
        try record(1_000, from: 0, for: shift, in: session, context: context)

        let service = ActiveShiftRouteService(context: context)
        let measured = try service.measurement(extending: nil, of: shift)

        #expect(measured.plan(againstStoredRowCount: 1_000) == .upToDate)
        #expect(measured.lastConsumedTimestamp == at(999))

        try record(3, from: 1_000, for: shift, in: session, context: context)

        // The plan is what the query is built from, so asserting it is asserting
        // that 1,000 rows are not fetched again to add three.
        #expect(measured.plan(againstStoredRowCount: 1_003) == .extend(after: at(999)))

        let extended = try service.measurement(extending: measured, of: shift)
        #expect(extended.recordedDistance == shift.recordedDistance())
    }
}
