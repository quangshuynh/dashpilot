import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedEndSave: Error {}

/// Correcting a completed shift's end through the store: what one correction
/// writes, what it takes out of the route, which figures follow it, which
/// figures must not, and what a refused save leaves behind.
///
/// ## The claim this suite exists for
///
/// **Mileage is re-measured, never scaled.** A shift shortened from four hours
/// to three has not lost a quarter of its miles; it has lost whichever positions
/// were fixed after the corrected end, and the distance is whatever the
/// remaining positions support. The fixture below is built so those two readings
/// give obviously different numbers, and the assertions name the one that is
/// correct.
///
/// ## And the claim beside it
///
/// **A later end fabricates nothing.** No position and no metre appears for the
/// stretch gained. What does change is the route's coverage: a route that no
/// longer reaches its shift's end is a partial route, and that is the existing
/// model saying the added stretch has no evidence behind it rather than this
/// feature inventing a way to say so.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held model and the authoritative store can disagree
/// after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp, amount and coordinate here is invented.
@MainActor
@Suite("Shift end correction service")
struct ShiftEndCorrectionServiceTests {
    private let calendar: Calendar
    private let start: Date
    private let day: ReportingPeriod

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        // Wednesday, 17 June 2026, 04:00 UTC, so a four-hour shift and every
        // correction to it stay inside one day.
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17)))
        start = midnight.addingTimeInterval(4 * 3600)
        day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
    }

    /// `minutes` after the shift's start.
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotEndCorrectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func corrections(_ context: ModelContext) -> ShiftEndCorrectionService {
        ShiftEndCorrectionService(context: context)
    }

    private func refusing(_ context: ModelContext) -> ShiftEndCorrectionService {
        ShiftEndCorrectionService(context: context, commit: { _ in throw RefusedEndSave() })
    }

    // MARK: The fixture

    /// A four-hour shift recorded as ending at 04:00 in, whose route is three
    /// separate capture sessions.
    ///
    /// | Minutes in | What was recorded |
    /// | --- | --- |
    /// | 30 to 33 | Ten positions, 400 m apart: 3,600 m |
    /// | 180 to 183 | Ten more, a second session: 3,600 m |
    /// | 200 to 203 | Ten more, a third session: 3,600 m |
    /// | 240 | The recorded end |
    ///
    /// The three sessions are deliberately equal, so a distance measured from the
    /// positions that remain and a distance scaled by the ratio of the durations
    /// cannot be confused for each other: correcting the end from 240 to 190
    /// leaves two thirds of the metres and would leave 79% of them if anything
    /// here scaled by time.
    @discardableResult
    private func lateEndShift(in context: ModelContext, earnings: Money? = Money(minorUnits: 12_000)) throws -> Shift {
        let shift = Shift(startedAt: start)
        context.insert(shift)

        for (index, startMinute) in [30.0, 180.0, 200.0].enumerated() {
            let session = UUID()
            for step in 0..<10 {
                context.insert(
                    RouteSample(
                        shift: shift,
                        sample: SyntheticRoute.sample(
                            at: at(startMinute).addingTimeInterval(Double(step) * 20),
                            northMetres: Double(index) * 9_000 + Double(step) * 400
                        ),
                        captureSessionID: session
                    )
                )
            }
        }

        try shift.end(at: at(240))
        if let earnings { try shift.setGrossEarnings(earnings) }
        try context.save()
        return shift
    }

    /// One delivery on `shift`, taken through its whole lifecycle between the
    /// two offsets.
    ///
    /// The arrival and the pickup sit a third and two thirds of the way through,
    /// because the lifecycle refuses a completion that skips them and because
    /// they are two more instants an end correction has to be judged against.
    @discardableResult
    private func delivery(
        on shift: Shift,
        acceptedAt acceptedMinute: Double,
        deliveredAt deliveredMinute: Double,
        in context: ModelContext,
        earnings: Money? = nil
    ) throws -> Delivery {
        let offer = Offer(shift: shift, acceptedAt: at(acceptedMinute))
        context.insert(offer)
        let delivery = Delivery(shift: shift, offer: offer, acceptedAt: at(acceptedMinute))
        context.insert(delivery)

        let span = deliveredMinute - acceptedMinute
        try delivery.markArrivedAtPickup(at: at(acceptedMinute + span / 3))
        try delivery.markPickedUp(at: at(acceptedMinute + 2 * span / 3))
        try delivery.markDelivered(at: at(deliveredMinute))
        if let earnings { try delivery.setGrossEarnings(earnings) }
        try context.save()
        return delivery
    }

    private func storedSamples(of shift: Shift, in context: ModelContext) throws -> [RouteSample] {
        let shiftID = shift.id
        return try context.fetch(
            FetchDescriptor<RouteSample>(
                predicate: #Predicate { $0.shift?.id == shiftID },
                sortBy: [SortDescriptor(\.timestamp)]
            )
        )
    }

    /// A number of seconds, typed as the duration it is. See
    /// `ShiftPauseCorrectionServiceTests` for why the wrapper is needed.
    private func seconds(_ value: TimeInterval) -> TimeInterval { value }

    // MARK: Moving the end earlier

    @Test("An earlier end removes the route recorded after it and keeps everything at or before it")
    func earlierEndTrimsTheRouteAfterTheBoundary() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        #expect(try storedSamples(of: shift, in: context).count == 30)

        try corrections(context).correct(shift, to: at(190))

        let remaining = try storedSamples(of: shift, in: context)
        #expect(remaining.count == 20, "The third session left the shift; the first two did not")
        #expect(
            remaining.allSatisfy { $0.timestamp <= self.at(190) },
            "Nothing after the corrected end is still attached to the shift"
        )
        #expect(
            try context.fetch(FetchDescriptor<RouteSample>()).count == 20,
            "The rows are deleted rather than detached, so no orphaned coordinate is left in the store"
        )
        #expect(!context.hasChanges, "The correction was saved, not left pending")
    }

    @Test("A position fixed exactly at the corrected end is kept")
    func theBoundaryItselfIsEvidenceInsideTheShift() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        // The third session's first position is fixed at exactly 200 minutes in.
        try corrections(context).correct(shift, to: at(200))

        let remaining = try storedSamples(of: shift, in: context)
        #expect(remaining.count == 21)
        #expect(remaining.last?.timestamp == at(200), "The driver said they stopped then, and that fix is inside it")
    }

    @Test("Mileage is measured again from the positions that remain, not scaled by the time removed")
    func mileageIsRemeasuredRatherThanScaled() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = shift.recordedDistance()
        #expect(SyntheticRoute.isCloseEnough(before.metres, to: 10_800), "Three sessions of 3,600 m")
        #expect(before.segmentCount == 3)

        try corrections(context).correct(shift, to: at(190))

        let after = shift.recordedDistance()
        #expect(
            SyntheticRoute.isCloseEnough(after.metres, to: 7_200),
            "Two sessions of 3,600 m remain, measured from their own coordinates"
        )
        // The shift lost 50 of its 240 minutes. A figure scaled by that ratio
        // would be about 8,550 m, which is the reading this feature must never
        // produce.
        #expect(
            !SyntheticRoute.isCloseEnough(after.metres, to: 10_800 * 190 / 240),
            "A mileage proportional to the elapsed time is the one answer that is always wrong"
        )
        #expect(after.segmentCount == 2, "The third segment left with its positions")
    }

    @Test("No endpoint is invented between the last retained position and the corrected end")
    func nothingIsInterpolatedToTheBoundary() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        try corrections(context).correct(shift, to: at(190))

        let remaining = try storedSamples(of: shift, in: context)
        #expect(
            remaining.last?.timestamp == at(183),
            "The last position is where capture left it, seven minutes before the corrected end"
        )
        #expect(remaining.count == 20, "Nothing was added to reach the boundary")
        #expect(
            shift.recordedDistance().gapCount == 3,
            "The uncovered stretch before the end is counted as the gap it is, not measured across"
        )
    }

    @Test("Trimming a whole capture session removes the gap that session was on the far side of")
    func segmentsAndGapsFollowTheRouteThatRemains() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = shift.recordedDistance()
        #expect(before.segmentCount == 3)
        #expect(
            before.gapCount == 4,
            "Two breaks between sessions, one before the first position and one after the last"
        )

        try corrections(context).correct(shift, to: at(190))

        let after = shift.recordedDistance()
        #expect(after.segmentCount == 2)
        #expect(after.gapCount == 3, "One break between the two sessions, and one at each end")
        #expect(after.usableSampleCount == 20)
        #expect(after.isPartial, "A route with gaps is still a floor, and says so")
    }

    @Test("A session the boundary falls inside keeps its part and stays one session")
    func apartialCaptureSessionKeepsItsIdentity() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        let thirdSessionID = try #require(try storedSamples(of: shift, in: context).last?.captureSessionID)

        // Partway through the third session's three minutes.
        try corrections(context).correct(shift, to: at(201).addingTimeInterval(40))

        let remaining = try storedSamples(of: shift, in: context)
        let survivors = remaining.filter { $0.captureSessionID == thirdSessionID }
        #expect(survivors.count == 6, "Six of the session's ten positions were fixed at or before the boundary")
        #expect(
            Set(survivors.map(\.captureSessionID)).count == 1,
            "They keep the session they were recorded in; nothing is restamped"
        )
        #expect(
            shift.recordedDistance().segmentCount == 3,
            "The part of the session that remains is still a continuous stretch of route"
        )
    }

    // MARK: Moving the end later

    @Test("A later end adds no position and no metre")
    func laterEndFabricatesNoRoute() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = shift.recordedDistance()

        try corrections(context).correct(shift, to: at(300))

        let after = shift.recordedDistance()
        #expect(try storedSamples(of: shift, in: context).count == 30, "No position was created")
        #expect(after.metres == before.metres, "and no metre was, either")
        #expect(after.segmentCount == before.segmentCount)
        #expect(after.usableSampleCount == before.usableSampleCount)
    }

    @Test("A later end that the route does not reach is reported as the partial route it is")
    func laterEndKeepsItsMissingCoverageVisible() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        try corrections(context).correct(shift, to: at(300))

        let after = shift.recordedDistance()
        #expect(
            after.gapCount == 4,
            "The stretch with nothing recorded in it is still one uncovered stretch, not a longer claim"
        )
        #expect(after.isPartial, "The existing model already says the shift is not fully covered")
        #expect(
            RouteQuality(after).partialMarker == "partial route",
            "and the wording the screen reads follows from it rather than from anything written here"
        )
    }

    // MARK: Time and earnings

    @Test("Elapsed and working durations follow the corrected end")
    func durationsFollowTheEnd() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        #expect(shift.completedDuration == seconds(240 * 60))
        #expect(shift.completedWorkingDuration == seconds(240 * 60))

        try corrections(context).correct(shift, to: at(190))

        #expect(shift.completedDuration == seconds(190 * 60))
        #expect(shift.completedWorkingDuration == seconds(190 * 60), "No pause, so working is elapsed to the second")
        #expect(shift.endedAt == at(190))
        #expect(shift.startedAt == start, "The start does not move")
    }

    @Test("A pause the shorter shift still contains keeps its whole length out of the working time")
    func workingDurationStillSubtractsThePauses() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        context.insert(ShiftPause(shift: shift, startedAt: at(60), endedAt: at(90)))
        try context.save()

        #expect(shift.completedPausedTime?.duration == seconds(30 * 60))
        #expect(shift.completedWorkingDuration == seconds(210 * 60))

        try corrections(context).correct(shift, to: at(190))

        #expect(shift.completedPausedTime?.duration == seconds(30 * 60), "The pause itself did not move")
        #expect(shift.completedWorkingDuration == seconds(160 * 60))
        #expect(shift.pausesInOrder.first?.startedAt == at(60))
        #expect(shift.pausesInOrder.first?.endedAt == at(90))
    }

    @Test("The hourly rate follows the corrected working duration")
    func hourlyRateFollowsTheCorrection() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        // $120.00 over four hours.
        #expect(shift.metrics(for: shift.recordedDistance()).grossPerWorkingHour == .available(Money(minorUnits: 3_000)))

        try corrections(context).correct(shift, to: at(180))

        // The same $120.00 over three.
        #expect(shift.metrics(for: shift.recordedDistance()).grossPerWorkingHour == .available(Money(minorUnits: 4_000)))
    }

    @Test("The per-mile rate follows the mileage that was measured again")
    func perMileRateFollowsTheRemeasuredRoute() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = shift.metrics(for: shift.recordedDistance()).grossPerRecordedMile
        try corrections(context).correct(shift, to: at(190))
        let after = shift.metrics(for: shift.recordedDistance()).grossPerRecordedMile

        #expect(before != after, "Fewer recorded miles for the same amount is a higher figure per mile")
        guard case let .available(beforeAmount) = before, case let .available(afterAmount) = after else {
            Issue.record("Both rates should be available: the shift has an amount and a measured route")
            return
        }
        #expect(afterAmount > beforeAmount)
    }

    @Test("Nothing the driver typed or recorded about money moves")
    func moneyAndDeliveriesAreUntouched() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        let delivered = try delivery(
            on: shift,
            acceptedAt: 100,
            deliveredAt: 120,
            in: context,
            earnings: Money(minorUnits: 1_450)
        )
        context.insert(try delivered.recordAdditionalTip(Money(minorUnits: 500), method: .cash, at: at(130)))
        try context.save()

        try corrections(context).correct(shift, to: at(190))

        #expect(shift.grossEarnings == Money(minorUnits: 12_000), "The shift's own amount is exactly as recorded")
        #expect(delivered.grossEarnings == Money(minorUnits: 1_450))
        #expect(delivered.additionalTips.count == 1)
        #expect(delivered.effectiveEarnings.amount == Money(minorUnits: 1_950))
        #expect(delivered.acceptedAt == at(100), "and no delivery timestamp moved")
        #expect(delivered.deliveredAt == at(120))
        #expect(delivered.state == .delivered)
        #expect(shift.deliveryActiveTime().duration == seconds(20 * 60))
    }

    // MARK: Refusals through the store

    @Test("A running shift is refused, whatever a screen might present")
    func runningShiftIsRefused() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try context.save()

        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.shiftNotCompleted)) {
            try corrections(context).correct(shift, to: at(190))
        }
        #expect(shift.endedAt == nil)
    }

    @Test("An end before the shift started is refused and writes nothing")
    func endBeforeTheStartIsRefused() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.notAfterShiftStart)) {
            try corrections(context).correct(shift, to: self.start.addingTimeInterval(-60))
        }
        #expect(shift.endedAt == at(240), "The recorded end is exactly as it was")
        #expect(try storedSamples(of: shift, in: context).count == 30, "and so is the whole route")
        #expect(!context.hasChanges)
    }

    @Test("An end that would swallow recorded delivery work is refused and removes no route")
    func deliveryBoundaryIsRefusedBeforeAnythingIsDeleted() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        try delivery(on: shift, acceptedAt: 100, deliveredAt: 195, in: context)

        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.precedesRecordedDeliveryWork)) {
            try corrections(context).correct(shift, to: self.at(190))
        }
        #expect(shift.endedAt == at(240))
        #expect(
            try storedSamples(of: shift, in: context).count == 30,
            "The route is read only after the proposal is accepted"
        )
        #expect(!context.hasChanges)
    }

    @Test("An end that would leave a recorded pause outside the shift is refused")
    func pauseBoundaryIsRefused() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        context.insert(ShiftPause(shift: shift, startedAt: at(180), endedAt: at(200)))
        try context.save()

        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.cutsThroughRecordedPause)) {
            try corrections(context).correct(shift, to: self.at(190))
        }
        #expect(shift.endedAt == at(240))
        #expect(shift.pausesInOrder.first?.endedAt == at(200), "and the pause is not shortened to fit")
    }

    @Test("An end reaching into a later shift is refused")
    func overlappingTheNextShiftIsRefused() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let later = Shift(startedAt: at(300))
        context.insert(later)
        try later.end(at: at(360))
        try context.save()

        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.overlapsAnotherShift)) {
            try corrections(context).correct(shift, to: self.at(330))
        }
        #expect(shift.endedAt == at(240))
        #expect(corrections(context).refusal(on: shift, to: at(290)) == nil, "An end before it begins is fine")
    }

    @Test("A running shift recorded later still bounds the one being corrected")
    func anUnfinishedLaterShiftBoundsTheCorrection() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        context.insert(Shift(startedAt: at(300)))
        try context.save()

        #expect(corrections(context).refusal(on: shift, to: at(330)) == .overlapsAnotherShift)
    }

    @Test("A shift the store no longer holds is refused before anything is read")
    func aDeletedShiftIsRefused() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        context.delete(shift)

        #expect(throws: ShiftEndCorrectionError.shiftNoLongerExists) {
            try corrections(context).correct(shift, to: self.at(190))
        }
    }

    // MARK: Asking without writing

    @Test("Asking what would be refused writes nothing and removes nothing")
    func askingIsNotWriting() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        #expect(corrections(context).refusal(on: shift, to: at(190)) == nil)
        #expect(corrections(context).refusal(on: shift, to: start) == .notAfterShiftStart)
        #expect(shift.endedAt == at(240))
        #expect(try storedSamples(of: shift, in: context).count == 30)
        #expect(!context.hasChanges)
    }

    @Test("The count a confirmation states is the number of positions that would be deleted")
    func routeEvidenceCountMatchesWhatTrimmingRemoves() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)
        let service = corrections(context)

        #expect(service.routeEvidenceCount(on: shift, after: at(190)) == 10)
        #expect(service.routeEvidenceCount(on: shift, after: at(240)) == 0, "Nothing lies after the recorded end")
        #expect(service.routeEvidenceCount(on: shift, after: at(300)) == 0, "and a later end removes nothing")
        #expect(service.routeEvidenceCount(on: shift, after: at(20)) == 30)

        try service.correct(shift, to: at(190))
        #expect(try storedSamples(of: shift, in: context).count == 20, "which is exactly what it said")
    }

    // MARK: Atomicity

    @Test("A refused save leaves the recorded end and the whole route exactly as they were")
    func aRefusedSaveChangesNothingInTheStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try lateEndShift(in: context)
        let shiftID = shift.id

        #expect(throws: ShiftEndCorrectionError.storeUnavailable(underlying: RefusedEndSave())) {
            try refusing(context).correct(shift, to: self.at(190))
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.endedAt == at(240), "The end the store holds is the one it held")
        #expect(
            try storedSamples(of: stored, in: reopened).count == 30,
            "and not one position was taken from it"
        )
        #expect(
            try reopened.fetch(FetchDescriptor<RouteSample>()).count == 30,
            "There is no ordering in which the route goes and the end stays"
        )
    }

    @Test("A correction the store accepted survives a reopen, end and route together")
    func theCorrectionSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try lateEndShift(in: context)
        let shiftID = shift.id
        try corrections(context).correct(shift, to: at(190))

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.endedAt == at(190))
        #expect(stored.completedDuration == seconds(190 * 60))
        #expect(try reopened.fetch(FetchDescriptor<RouteSample>()).count == 20)
        #expect(SyntheticRoute.isCloseEnough(stored.recordedDistance().metres, to: 7_200))
    }

    // MARK: Repeating a correction

    @Test("Applying the same corrected end twice leaves exactly the same shift")
    func correctingTwiceIsIdempotent() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        try corrections(context).correct(shift, to: at(190))
        let onceEnded = shift.endedAt
        let onceMetres = shift.recordedDistance().metres
        let onceCount = try storedSamples(of: shift, in: context).count

        try corrections(context).correct(shift, to: at(190))

        #expect(shift.endedAt == onceEnded)
        #expect(shift.recordedDistance().metres == onceMetres)
        #expect(try storedSamples(of: shift, in: context).count == onceCount)
    }

    @Test("Correcting twice in steps reaches the same shift as correcting once")
    func steppingBackTwiceMatchesGoingStraightThere() throws {
        let stepped = try makeContext()
        let steppedShift = try lateEndShift(in: stepped)
        try corrections(stepped).correct(steppedShift, to: at(210))
        try corrections(stepped).correct(steppedShift, to: at(190))

        let direct = try makeContext()
        let directShift = try lateEndShift(in: direct)
        try corrections(direct).correct(directShift, to: at(190))

        #expect(steppedShift.endedAt == directShift.endedAt)
        #expect(steppedShift.recordedDistance() == directShift.recordedDistance())
        #expect(
            try storedSamples(of: steppedShift, in: stepped).map(\.timestamp)
                == (try storedSamples(of: directShift, in: direct).map(\.timestamp)),
            "The route that remains is the same route, however the driver got there"
        )
    }

    @Test("An end moved earlier and then back again does not bring the route back")
    func trimmingIsNotUndoneByALaterCorrection() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        try corrections(context).correct(shift, to: at(190))
        try corrections(context).correct(shift, to: at(240))

        #expect(shift.endedAt == at(240), "The end is back where it started")
        #expect(
            try storedSamples(of: shift, in: context).count == 20,
            "and the deleted positions are gone for good, which is what the confirmation said"
        )
        #expect(SyntheticRoute.isCloseEnough(shift.recordedDistance().metres, to: 7_200))
    }

    // MARK: Periods

    @Test("The shift stays in the period it was already in, and the period's figures follow it")
    func periodFiguresFollowWithoutMembershipMoving() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: day
        )
        #expect(before.completedShiftCount == 1)
        #expect(before.workingDuration == seconds(240 * 60))

        try corrections(context).correct(shift, to: at(190))

        let after = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: day
        )
        #expect(after.completedShiftCount == 1, "The shift's start did not move, so neither did its period")
        #expect(after.workingDuration == seconds(190 * 60))
        #expect(SyntheticRoute.isCloseEnough(after.recordedDistance.metres, to: 7_200))
        #expect(after.recordedGrossEarnings == Money(minorUnits: 12_000), "The amount it contributes is unchanged")
        #expect(
            after.grossPerWorkingHour.amount != before.grossPerWorkingHour.amount,
            "and the rate over the period's hours follows the hours"
        )
    }

    // MARK: Export

    @Test("A corrected shift exports the corrected facts through the fields that already carried them")
    func exportCarriesTheCorrectionWithNoNewField() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        let before = try shift.exportRecord(for: shift.recordedDistance())

        try corrections(context).correct(shift, to: at(190))

        let after = try shift.exportRecord(for: shift.recordedDistance())

        // Every assertion below is about a **value** moving. No field is added,
        // removed or redefined by this feature, which is why the format version
        // does not move: `endedAt`, the two durations and the route figures have
        // carried exactly this since the format had them.
        #expect(after.endedAt == at(190))
        #expect(after.startedAt == before.startedAt)
        #expect(after.elapsedSeconds == 190 * 60)
        #expect(after.workingSeconds == 190 * 60)
        #expect(after.pauseCount == 0)
        #expect(after.route.segmentCount == 2, "The trimmed route exports the segments it has")
        #expect(after.route.usableSampleCount == 20)
        #expect(after.grossEarnings == before.grossEarnings, "and the amount the driver typed is untouched")
    }

    @Test("A shift corrected to still be running would be refused by export, and cannot be")
    func exportStillRefusesARunningShift() throws {
        let context = try makeContext()
        let shift = try lateEndShift(in: context)

        // There is no correction that leaves a shift unfinished: the end is
        // rewritten, never cleared. Asserted because it is the one way this
        // feature could have put a growing shift into a document claiming to be
        // history.
        try corrections(context).correct(shift, to: at(190))
        #expect(shift.endedAt != nil)
        #expect(!shift.isActive)
    }
}
