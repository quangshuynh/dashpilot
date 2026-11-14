import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedTimeSave: Error {}

/// Correcting a shift's start and end through the store: what one correction
/// writes, what it removes, what it must leave alone, how the running shift and
/// its Live Activity follow it, and how reporting periods move with the start.
///
/// Rollback and relaunch claims are read through a **fresh context or a fresh
/// container**, because an already-held model and the authoritative store can
/// disagree, and the store is what a relaunch shows.
///
/// Every timestamp, amount and coordinate here is invented.
@MainActor
@Suite("Shift time correction service")
struct ShiftTimeCorrectionServiceTests {
    private let calendar: Calendar
    /// Wednesday, 17 June 2026, 09:00 UTC.
    private let nine: Date
    /// A clock far enough after every fixture that nothing is in the future.
    private let now: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        self.calendar = calendar
        nine = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9)))
        now = nine.addingTimeInterval(30 * 86_400)
    }

    private func at(_ minutes: Double) -> Date { nine.addingTimeInterval(minutes * 60) }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemoryContainer()
    }

    private func service(_ context: ModelContext, now: Date? = nil) -> ShiftTimeCorrectionService {
        let clock = now ?? self.now
        return ShiftTimeCorrectionService(context: context, now: { clock })
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotTimeCorrectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appending(path: "DashPilot.store"), { try? FileManager.default.removeItem(at: directory) })
    }

    /// Ten positions 400 m apart, 20 s apart, from `minute`: 3,600 m.
    private func session(at minute: Double, northFrom metres: Double, on shift: Shift, in context: ModelContext) {
        let id = UUID()
        for step in 0..<10 {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(
                        at: at(minute).addingTimeInterval(Double(step) * 20),
                        northMetres: metres + Double(step) * 400
                    ),
                    captureSessionID: id
                )
            )
        }
    }

    /// A finished 09:00 to 14:00 shift paying $100.00, with three equal route
    /// sessions at 10, 120 and 250 minutes in, one delivery accepted at 40 and
    /// delivered at 100 paying $12.00, and a $20.00 fuel purchase at 11:00.
    @discardableResult
    private func recordedShift(in context: ModelContext, delivery: Bool = true) throws -> Shift {
        let shift = Shift(startedAt: nine)
        context.insert(shift)
        session(at: 10, northFrom: 0, on: shift, in: context)
        session(at: 120, northFrom: 9_000, on: shift, in: context)
        session(at: 250, northFrom: 18_000, on: shift, in: context)
        if delivery {
            let offer = Offer(shift: shift, acceptedAt: at(40))
            context.insert(offer)
            let order = Delivery(shift: shift, offer: offer, acceptedAt: at(40))
            context.insert(order)
            try order.markArrivedAtPickup(at: at(55))
            try order.markPickedUp(at: at(70))
            try order.markDelivered(at: at(100))
            try order.setGrossEarnings(Money(minorUnits: 1_200))
        }
        try shift.end(at: at(300))
        try shift.setGrossEarnings(Money(minorUnits: 10_000))
        _ = try ExpenseService(context: context).record(
            amount: Money(minorUnits: 2_000), category: .fuel, occurredAt: at(120)
        )
        try context.save()
        return shift
    }

    private func samples(of shift: Shift, in context: ModelContext) throws -> [RouteSample] {
        let id = shift.id
        return try context.fetch(
            FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == id }, sortBy: [SortDescriptor(\.timestamp)])
        )
    }

    private func onlyShift(in context: ModelContext) throws -> Shift {
        try #require(try context.fetch(FetchDescriptor<Shift>()).first)
    }

    // MARK: Completed shifts

    @Test("A later start trims the route before it, re-measures mileage, and leaves orders, tips and expenses alone")
    func laterStartTrimsTheHead() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)
        let before = shift.recordedDistance()

        #expect(service(context).routeEvidenceLoss(on: shift, start: at(30)) == ShiftRouteEvidenceLoss(beforeStart: 10, afterEnd: 0))
        try service(context).correct(shift, start: at(30))

        #expect(shift.startedAt == at(30))
        #expect(shift.endedAt == at(300))
        #expect(shift.completedDuration == 4.5 * 3600, "9:30 AM to 2:00 PM is 4 hours 30 minutes")
        #expect(try samples(of: shift, in: context).count == 20)
        #expect(try context.fetch(FetchDescriptor<RouteSample>()).count == 20, "Deleted, not detached")
        let after = shift.recordedDistance()
        #expect(abs(after.metres - before.metres * 2 / 3) < 1, "Measured again from what remains, not scaled by time")

        #expect(shift.grossEarnings == Money(minorUnits: 10_000))
        let order = try #require(shift.deliveries.first)
        #expect(order.acceptedAt == at(40) && order.deliveredAt == at(100))
        #expect(order.grossEarnings == Money(minorUnits: 1_200))
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Offer>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Delivery>()).count == 1)
        #expect(!context.hasChanges)
    }

    @Test("A position fixed exactly at the corrected start is kept")
    func boundaryPositionIsKept() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context, delivery: false)

        try service(context).correct(shift, start: at(120))

        let remaining = try samples(of: shift, in: context)
        #expect(remaining.count == 20)
        #expect(remaining.first?.timestamp == at(120))
    }

    @Test("An earlier start adds no route and no miles")
    func earlierStartAddsNothing() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)
        let before = shift.recordedDistance()

        try service(context).correct(shift, start: at(-30))

        #expect(shift.completedDuration == 5.5 * 3600)
        #expect(try samples(of: shift, in: context).count == 30)
        #expect(shift.recordedDistance().metres == before.metres)
        #expect(shift.recordedDistance().isPartial, "The stretch gained has no evidence behind it")
    }

    @Test("Both times correct in one save, trimming each end")
    func bothTimesInOneSave() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)

        let loss = service(context).routeEvidenceLoss(on: shift, start: at(30), end: at(200))
        #expect(loss == ShiftRouteEvidenceLoss(beforeStart: 10, afterEnd: 10))
        try service(context).correct(shift, start: at(30), end: at(200))

        #expect(shift.startedAt == at(30) && shift.endedAt == at(200))
        #expect(try samples(of: shift, in: context).count == 10)
        #expect(shift.completedDuration == TimeInterval(170 * 60))
    }

    @Test("A refused save leaves both times and the whole route in the store")
    func refusedSaveChangesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let shift = try recordedShift(in: context)
        let refusing = ShiftTimeCorrectionService(
            context: context, now: { self.now }, commit: { _ in throw RefusedTimeSave() }
        )

        #expect(throws: ShiftTimeCorrectionError.storeUnavailable(underlying: RefusedTimeSave())) {
            try refusing.correct(shift, start: at(30), end: at(200))
        }

        let fresh = ModelContext(container)
        let stored = try onlyShift(in: fresh)
        #expect(stored.startedAt == nine && stored.endedAt == at(300))
        #expect(try fresh.fetch(FetchDescriptor<RouteSample>()).count == 30)
    }

    @Test("A refused time writes nothing and names the field")
    func refusalWritesNothing() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)

        #expect(throws: ShiftTimeCorrectionError.invalidCorrection(.start(.followsRecordedDeliveryWork(
            RecordedDeliveryEvent(deliveryNumber: 1, event: .accepted, occurredAt: at(40))
        )))) {
            try service(context).correct(shift, start: at(45))
        }
        #expect(throws: ShiftTimeCorrectionError.invalidCorrection(.end(.inFuture))) {
            try service(context, now: at(400)).correct(shift, start: nine, end: at(401))
        }
        #expect(shift.startedAt == nine && shift.endedAt == at(300))
        #expect(try samples(of: shift, in: context).count == 30)
        #expect(!context.hasChanges)
    }

    @Test("Another shift is never moved, and a correction into it is refused")
    func otherShiftsAreUntouched() throws {
        let context = ModelContext(try makeContainer())
        let earlier = Shift(startedAt: at(-300))
        context.insert(earlier)
        try earlier.end(at: at(-15))
        let shift = try recordedShift(in: context)

        #expect(service(context).refusal(on: shift, start: at(-20)) == .start(.overlapsAnotherShift))
        #expect(service(context).refusal(on: shift, start: at(-15)) == nil, "Starting as the last one ended is fine")

        try service(context).correct(shift, start: at(-15))
        #expect(earlier.startedAt == at(-300) && earlier.endedAt == at(-15))
        #expect(try context.fetch(FetchDescriptor<Shift>()).count == 2, "No duplicate shift")
    }

    @Test("A corrected start and end survive closing and reopening the store")
    func persistsAcrossRelaunch() throws {
        let store = try makeStoreURL()
        defer { store.cleanUp() }
        do {
            let container = try ModelContainerFactory.makeContainer(at: store.url)
            let context = ModelContext(container)
            let shift = try recordedShift(in: context)
            try ShiftTimeCorrectionService(context: context, now: { self.now }).correct(shift, start: at(30), end: at(280))
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: store.url))
        let shift = try onlyShift(in: reopened)
        #expect(shift.startedAt == at(30))
        #expect(shift.endedAt == at(280))
        #expect(shift.completedDuration == TimeInterval(250 * 60))
        #expect(try reopened.fetch(FetchDescriptor<RouteSample>()).count == 20)
        #expect(try reopened.fetch(FetchDescriptor<Delivery>()).count == 1)
    }

    // MARK: Reporting periods

    @Test("A start corrected across Monday midnight moves the shift and its totals into the previous week")
    func correctionMovesBetweenWeeks() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 0, minute: 10)))
        let shift = Shift(startedAt: monday)
        context.insert(shift)
        try shift.end(at: monday.addingTimeInterval(4 * 3600))
        try shift.setGrossEarnings(Money(minorUnits: 8_000))
        try context.save()

        let thisWeek = try #require(ReportingPeriod(unit: .week, containing: monday, calendar: calendar))
        let lastWeek = try #require(ReportingPeriod(unit: .week, containing: monday.addingTimeInterval(-86_400), calendar: calendar))
        func gross(_ period: ReportingPeriod) async throws -> Money? {
            let request = PeriodLoadRequest(period: period)
            return try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value.overview.earnings
        }
        #expect(try await gross(thisWeek) == Money(minorUnits: 8_000))
        #expect(try await gross(lastWeek) == nil)

        let correction = try service(context).correct(shift, start: monday.addingTimeInterval(-20 * 60))
        #expect(correction.reportingMove(calendar: calendar)?.changesWeek == true)

        #expect(try await gross(thisWeek) == nil, "The week it left no longer counts it")
        #expect(try await gross(lastWeek) == Money(minorUnits: 8_000), "The week it joined does")
        #expect(shift.completedDuration == TimeInterval(4 * 3600 + 20 * 60))
    }

    @Test("Period rates and times are recomputed from the corrected times, never left stale")
    func periodRatesFollowTheCorrection() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let shift = try recordedShift(in: context, delivery: false)
        let week = try #require(ReportingPeriod(unit: .week, containing: nine, calendar: calendar))
        func read() async throws -> PeriodMetrics {
            let request = PeriodLoadRequest(period: week, includesRouteDetails: true)
            return try #require(try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value.current)
        }

        let before = try await read()
        #expect(before.grossPerWorkingHour.amount == Money(minorUnits: 2_000), "$100.00 over 5 hours")
        #expect(before.elapsedDuration == TimeInterval(5 * 3600))

        try service(context).correct(shift, start: at(60))

        let after = try await read()
        #expect(after.grossPerWorkingHour.amount == Money(minorUnits: 2_500), "$100.00 over 4 hours")
        #expect(after.workingDuration == TimeInterval(4 * 3600))
        #expect(after.elapsedDuration == TimeInterval(4 * 3600))
        #expect(after.recordedGrossEarnings == Money(minorUnits: 10_000), "The amount itself never moves")
        #expect(after.expenses.recordedTotal == Money(minorUnits: 2_000), "Nor the expense")
        #expect(after.recordedDistance.metres < before.recordedDistance.metres, "The trimmed route is measured again")
    }

    @Test("A correction's save invalidates period reads")
    func correctionInvalidatesReports() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)
        final class Capture: @unchecked Sendable { var values: [Bool] = [] }
        let capture = Capture()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            capture.values.append(PeriodSaveInvalidation.affectsPeriods($0))
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try service(context).correct(shift, start: at(30))
        #expect(capture.values == [true])

        try service(context).correct(shift, start: at(30))
        #expect(capture.values == [true], "Re-recording the same times saves nothing")
    }

    // MARK: Running shifts

    @Test("A running shift's start is corrected without ending, pausing or restarting it")
    func runningShiftKeepsRunning() throws {
        let context = ModelContext(try makeContainer())
        let shift = try ShiftService(context: context).startShift(at: nine)
        session(at: 2, northFrom: 0, on: shift, in: context)
        session(at: 30, northFrom: 9_000, on: shift, in: context)
        try context.save()
        let delivery = try DeliveryService(context: context).startDelivery(at: at(20))

        try service(context, now: at(60)).correct(shift, start: at(10))

        #expect(shift.startedAt == at(10))
        #expect(shift.endedAt == nil)
        #expect(shift.lifecycleState == .running)
        #expect(try ShiftService(context: context).activeShift()?.id == shift.id, "The same row is the active shift")
        #expect(delivery.isActive && delivery.acceptedAt == at(20), "The active order is untouched")
        #expect(shift.elapsed(asOf: at(60)) == 50 * 60)
        #expect(shift.workingDuration(asOf: at(90)) == 80 * 60, "The timer continues from the corrected start")
        #expect(try samples(of: shift, in: context).count == 10, "Route before the corrected start left the shift")
    }

    @Test("A paused shift stays paused, with its open pause intact")
    func pausedShiftStaysPaused() throws {
        let context = ModelContext(try makeContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: nine)
        try shifts.pauseActiveShift(at: at(30))

        try service(context, now: at(60)).correct(shift, start: at(-15))

        #expect(shift.lifecycleState == .paused)
        #expect(shift.openPause?.startedAt == at(30))
        #expect(shift.workingDuration(asOf: at(60)) == 45 * 60)
        #expect(shift.workingDuration(asOf: at(120)) == 45 * 60, "Paused working time still does not grow")
    }

    @Test("A running correction survives a relaunch and stays the shift in progress")
    func runningCorrectionSurvivesRelaunch() throws {
        let store = try makeStoreURL()
        defer { store.cleanUp() }
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: store.url))
            let shift = try ShiftService(context: context).startShift(at: nine)
            try ShiftTimeCorrectionService(context: context, now: { self.at(60) }).correct(shift, start: at(-25))
        }

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: store.url))
        let active = try #require(try ShiftService(context: reopened).activeShift())
        #expect(active.startedAt == at(-25))
        #expect(active.isActive)
        // Background and foreground both re-read the same instant: the figure
        // is derived from the stored start, never from ticks counted while open.
        #expect(active.workingDuration(asOf: at(60)) == 85 * 60)
        #expect(active.workingDuration(asOf: at(600)) == 625 * 60)
    }

    @Test("Capture judges new positions against the corrected start")
    func captureUsesTheCorrectedStart() throws {
        let context = ModelContext(try makeContainer())
        let shift = try ShiftService(context: context).startShift(at: nine)
        try service(context, now: at(60)).correct(shift, start: at(20))

        let filter = RouteSampleFilter()
        let early = SyntheticRoute.sample(at: at(15))
        let decision = filter.evaluate(early, in: RouteSampleFilter.Context(shiftStart: shift.startedAt, now: at(15)))
        #expect(decision.rejection == .beforeShiftStart)
    }

    @Test("A live route measurement starts again after a start correction, even when capture refills the count")
    func liveMeasurementRestarts() throws {
        let context = ModelContext(try makeContainer())
        let shift = try ShiftService(context: context).startShift(at: nine)
        session(at: 2, northFrom: 0, on: shift, in: context)
        session(at: 30, northFrom: 9_000, on: shift, in: context)
        try context.save()
        let routes = ActiveShiftRouteService(context: context)
        let first = try routes.measurement(extending: nil, of: shift)
        #expect(first.consumedRowCount == 20)

        try service(context, now: at(60)).correct(shift, start: at(10))
        // Capture appends exactly as many rows as the correction removed.
        session(at: 40, northFrom: 30_000, on: shift, in: context)
        try context.save()

        let next = try routes.measurement(extending: first, of: shift)
        let expected = shift.recordedDistance()
        #expect(next.consumedRowCount == 20)
        #expect(abs(next.recordedDistance.metres - expected.metres) < 1, "Measured from the rows that remain")
        #expect(next.shiftStartedAt == at(10))
    }

    // MARK: Live Activity

    @Test("The Live Activity is pushed the corrected working time, anchored at the corrected start")
    func liveActivityFollowsTheCorrection() throws {
        let context = ModelContext(try makeContainer())
        let presenter = RecordingShiftActivityPresenter()
        var clock = at(60)
        let activity = ShiftLiveActivityService(
            context: context, presenter: presenter, now: { clock }, locale: { Locale(identifier: "en_US") }
        )
        let shift = try ShiftService(context: context).startShift(at: nine)
        activity.reconcile()
        #expect(presenter.startCount == 1)
        #expect(presenter.onlyContent?.workingDuration == 3600)

        try service(context, now: clock).correct(shift, start: at(-30))
        activity.reconcile()

        #expect(presenter.startCount == 1, "The same activity, not a second one")
        #expect(presenter.updateCount == 1, "The moved anchor is pushed at once")
        let content = try #require(presenter.onlyContent)
        #expect(content.workingDuration == 90 * 60)
        #expect(content.asOf.addingTimeInterval(-content.workingDuration) == at(-30))

        clock = at(61)
        activity.reconcile()
        #expect(presenter.updateCount == 1, "Time passing afterwards is still not a change")
    }

    // MARK: The end-only adapter

    @Test("The end-only service is the same write path and refuses a future end")
    func endOnlyAdapter() throws {
        let context = ModelContext(try makeContainer())
        let shift = try recordedShift(in: context)
        let ends = ShiftEndCorrectionService(context: context, now: { self.at(400) })

        #expect(ends.refusal(on: shift, to: at(401)) == .inFuture)
        #expect(throws: ShiftEndCorrectionError.invalidCorrection(.inFuture)) { try ends.correct(shift, to: at(401)) }
        try ends.correct(shift, to: at(200))
        #expect(shift.endedAt == at(200) && shift.startedAt == nine)
        #expect(try samples(of: shift, in: context).count == 20)
    }
}
