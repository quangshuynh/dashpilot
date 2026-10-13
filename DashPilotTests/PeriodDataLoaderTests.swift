import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Shared period loading")
struct PeriodDataLoaderTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let period: ReportingPeriod

    init() throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        period = try #require(ReportingPeriod(unit: .week, containing: date, calendar: calendar))
    }

    @discardableResult
    private func shift(offset: Double = 3600, duration: Double = 3600, earnings: Int? = nil, target: Int? = nil) throws -> Shift {
        let shift = Shift(startedAt: period.start.addingTimeInterval(offset))
        context.insert(shift)
        if let target { try shift.recordStartingHourlyTarget(Money(amount: Decimal(target))) }
        try shift.end(at: shift.startedAt.addingTimeInterval(duration))
        if let earnings { try shift.setGrossEarnings(Money(amount: Decimal(earnings))) }
        return shift
    }

    private func load(details: Bool = false) async throws -> PeriodDataSnapshot {
        let container = container
        let request = PeriodLoadRequest(period: period, includesRouteDetails: details)
        return try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
    }

    @Test func emptyAndExpenseOnlyRemainDifferentFromZeroEarnings() async throws {
        let empty = try await load()
        #expect(empty.overview.completedShiftCount == 0)
        #expect(empty.overview.earnings == nil)
        #expect(empty.overview.workingDuration == nil)
        context.insert(try Expense(occurredAt: period.start, amount: Money(amount: 12), category: .fuel))
        try context.save()
        let withExpense = try await load()
        #expect(withExpense.overview.completedShiftCount == 0)
        #expect(withExpense.overview.expenseCount == 1)
        #expect(withExpense.overview.earnings == nil)
    }

    @Test func overviewMatchesAuthoritativeFullSummaryWithPartialCoverageAndTargets() async throws {
        try shift(earnings: 60, target: 25)
        try shift(offset: 7200, duration: 7200, earnings: 0, target: 20)
        try shift(offset: 18000, earnings: nil, target: 30)
        try shift(offset: 24000, duration: 0, earnings: 500)
        try context.save()
        let overview = try await load()
        let full = try await load(details: true)
        #expect(overview.overview == full.overview)
        #expect(overview.current == nil)
        #expect(full.current != nil)
        #expect(overview.overview.earnings == Money(amount: 560))
        #expect(overview.overview.earningsCoverage == MetricCoverage(contributingCount: 3, eligibleCount: 4))
        #expect(overview.overview.workingDuration == 14400)
        #expect(overview.overview.hourlyRate.amount == Money(amount: 20))
        #expect(overview.overview.hourlyRate.coverage == MetricCoverage(contributingCount: 2, eligibleCount: 4))
        #expect(overview.overview.target == PeriodHourlyTargetSummary(withTarget: 3, compared: 2, atOrAbove: 1))
    }

    @Test func calendarDSTBoundariesAndRunningExclusion() async throws {
        #expect(period.end.timeIntervalSince(period.start) == 167 * 3600)
        try shift(offset: -1, duration: 7200, earnings: 900)
        try shift(offset: 0, earnings: 10)
        try shift(offset: period.end.timeIntervalSince(period.start) - 1, duration: 7200, earnings: 20)
        try shift(offset: period.end.timeIntervalSince(period.start), earnings: 800)
        context.insert(Shift(startedAt: period.start.addingTimeInterval(500)))
        try context.save()
        let result = try await load()
        #expect(result.overview.completedShiftCount == 2)
        #expect(result.overview.earnings == Money(amount: 30))
    }

    @Test func oneShiftCorrectionsEndingAndDeletionReachFreshContext() async throws {
        let completed = try shift(earnings: 30)
        let running = Shift(startedAt: period.start.addingTimeInterval(18000))
        context.insert(running)
        try context.save()
        #expect(try await load().overview.hourlyRate.amount == Money(amount: 30))
        try completed.setGrossEarnings(Money(amount: 42))
        try running.end(at: running.startedAt.addingTimeInterval(3600))
        try context.save()
        let corrected = try await load()
        #expect(corrected.overview.earnings == Money(amount: 42))
        #expect(corrected.overview.completedShiftCount == 2)
        context.delete(completed)
        try context.save()
        #expect(try await load().overview.earnings == nil)
    }

    @Test func recentFetchIsLimitedAndStable() throws {
        for offset in 0..<8 { try shift(offset: Double(offset * 3600)) }
        context.insert(Shift(startedAt: period.end))
        try context.save()
        let fetched = try context.fetch(PeriodDataLoader.recentShifts)
        #expect(fetched.count == 3)
        #expect(fetched.map(\.startedAt) == [7, 6, 5].map { period.start.addingTimeInterval(Double($0 * 3600)) })
    }

    @Test func missingAndExplicitZeroWithNoWorkingTime() async throws {
        let completed = try shift(duration: 0)
        try context.save()
        #expect(try await load().overview.earnings == nil)
        try completed.setGrossEarnings(.zero)
        try context.save()
        let zero = try await load().overview
        #expect(zero.earnings == .zero)
        #expect(zero.earningsCoverage.isComplete)
        #expect(zero.workingDuration == 0)
        #expect(zero.hourlyRate.amount == nil)
    }

    @Test func failedLoadIsDistinctAndCanRetry() async throws {
        let store = PeriodLoadStore()
        let key = PeriodLoadStore.Key(request: .init(period: period))
        await store.load(key: key) { throw SyntheticFailure.read }
        #expect(store.state == .failed)
        let snapshot = try await load()
        await store.load(key: key) {
            #expect(!loaderIsOnMainThread(), "Aggregation runs off the main thread")
            return snapshot
        }
        #expect(store.state == .loaded(snapshot))
        // Same successful key is reused on warm presentation.
        await store.load(key: key) { throw SyntheticFailure.read }
        #expect(store.state == .loaded(snapshot))
    }

    @Test func cancelledAndOlderResultsCannotOverwriteNewerLoad() async throws {
        let old = try await load()
        try shift(earnings: 50)
        try context.save()
        let new = try await load()
        let store = PeriodLoadStore()
        let gate = LoadGate()
        let key = PeriodLoadStore.Key(request: .init(period: period))
        let first = Task { await store.load(key: key) { await gate.wait(); return old } }
        await gate.awaitStarted()
        await store.load(key: .init(request: key.request, revision: 1)) { new }
        await gate.release()
        await first.value
        #expect(store.state == .loaded(new))
        let secondGate = LoadGate()
        let cancelled = Task { await store.load(key: .init(request: key.request, revision: 2)) { await secondGate.wait(); return old } }
        await secondGate.awaitStarted()
        cancelled.cancel()
        await secondGate.release()
        await cancelled.value
        #expect(store.state == .loading)
        await store.load(key: .init(request: key.request, revision: 3)) { new }
        #expect(store.state == .loaded(new))
    }

    @Test func pausesAndPartialRoutesKeepTheSameFinancialFacts() async throws {
        let completed = try shift(duration: 7200, earnings: 60, target: 25)
        try context.save()
        try ShiftPauseCorrectionService(context: context).addMissedPause(on: completed,
            from: completed.startedAt.addingTimeInterval(1800), to: completed.startedAt.addingTimeInterval(5400))
        for index in 0..<4 {
            context.insert(RouteSample(shift: completed,
                timestamp: completed.startedAt.addingTimeInterval(Double(index * 10)),
                latitude: 40 + Double(index) * 0.0001, longitude: -74,
                horizontalAccuracy: 5, captureSessionID: nil))
        }
        try context.save()
        let overview = try await load()
        let full = try await load(details: true)
        #expect(overview.overview == full.overview)
        #expect(overview.overview.workingDuration == 3600)
        #expect(overview.overview.hourlyRate.amount == Money(amount: 60))
        #expect(full.current?.routeCoverage.partialShiftCount == 1)
    }

    @Test func previousPeriodIsIndependentlyBounded() async throws {
        let previous = try #require(period.precedingEquivalent(using: Calendar(identifier: .gregorian)))
        try shift(earnings: 30)
        let earlier = Shift(startedAt: previous.start)
        context.insert(earlier)
        try earlier.end(at: previous.start.addingTimeInterval(3600))
        try earlier.setGrossEarnings(Money(amount: 15))
        try context.save()
        let request = PeriodLoadRequest(period: period, previous: previous, includesRouteDetails: true)
        let container = container
        let result = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
        #expect(result.current?.recordedGrossEarnings == Money(amount: 30))
        #expect(result.previous?.recordedGrossEarnings == Money(amount: 15))
    }

    @Test func returningToEarlierSelectionAfterCancellationCanReload() async throws {
        let snapshot = try await load()
        let store = PeriodLoadStore()
        let key = PeriodLoadStore.Key(request: .init(period: period))
        await store.load(key: key) { snapshot }
        let gate = LoadGate()
        let task = Task { await store.load(key: .init(request: key.request, revision: 1)) { await gate.wait(); return snapshot } }
        await gate.awaitStarted()
        task.cancel()
        await gate.release()
        await task.value
        await store.load(key: key) { snapshot }
        #expect(store.state == .loaded(snapshot))
    }

    @Test func actualSaveNotificationsRecognizeRouteOnlyAndFinancialWrites() throws {
        let capture = SaveCapture()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            capture.record(PeriodSaveInvalidation.affectsPeriods($0))
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let running = Shift(startedAt: period.start)
        context.insert(running)
        try context.save()
        #expect(capture.last == true)
        context.insert(RouteSample(shift: running, timestamp: period.start,
            latitude: 40, longitude: -74, horizontalAccuracy: 5, captureSessionID: UUID()))
        try context.save()
        #expect(capture.last == false)
        try running.end(at: period.start.addingTimeInterval(3600))
        try context.save()
        #expect(capture.last == true)
    }

    @Test func routeOnlySavesDoNotInvalidateFinancialReads() {
        #expect(!PeriodSaveInvalidation.affectsPeriods(entityName: "RouteSample"))
        #expect(PeriodSaveInvalidation.affectsPeriods(entityName: "Shift"))
        #expect(PeriodSaveInvalidation.affectsPeriods(entityName: "ShiftPause"))
        #expect(PeriodSaveInvalidation.affectsPeriods(entityName: "Expense"))
        #expect(PeriodSaveInvalidation.affectsPeriods(entityName: "DeliveryTip"))
    }
}

private enum SyntheticFailure: Error { case read }

private actor LoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func awaitStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class SaveCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    var last: Bool? { lock.withLock { value } }
    func record(_ newValue: Bool) { lock.withLock { value = newValue } }
}

private nonisolated func loaderIsOnMainThread() -> Bool { Thread.isMainThread }
