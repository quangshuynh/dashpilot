import Foundation
import Observation
import SwiftData

/// A bounded read request. Home deliberately requests no routes or deliveries.
nonisolated struct PeriodLoadRequest: Equatable, Sendable {
    let period: ReportingPeriod
    var previous: ReportingPeriod?
    var includesRouteDetails = false
    var includesExpenseRows = false
    var includesFuelEstimates = false
    var insightsWindow: InsightsWindow?
}

/// Only the facts Home requested. Unread routes cannot become missing-mileage claims.
nonisolated struct HomePeriodSummary: Equatable, Sendable {
    let period: ReportingPeriod
    let completedShiftCount: Int
    let earnings: Money?
    let earningsCoverage: MetricCoverage
    let workingDuration: TimeInterval?
    let workingCoverage: MetricCoverage
    let hourlyRate: PeriodRate
    let target: PeriodHourlyTargetSummary
    let expenseCount: Int

    init(_ metrics: PeriodMetrics) {
        period = metrics.period
        completedShiftCount = metrics.completedShiftCount
        earnings = metrics.recordedGrossEarnings
        earningsCoverage = metrics.earningsCoverage
        workingDuration = metrics.workingDuration
        workingCoverage = metrics.workingCoverage
        hourlyRate = metrics.grossPerWorkingHour
        target = metrics.hourlyTarget
        expenseCount = metrics.expenses.recordCount
    }
}

nonisolated struct PeriodDataSnapshot: Equatable, Sendable {
    let overview: HomePeriodSummary
    let current: PeriodMetrics?
    let previous: PeriodMetrics?
    let money: MoneyPeriodSummary?
    let insights: InsightsSeries?

    init(overview: HomePeriodSummary, current: PeriodMetrics?, previous: PeriodMetrics?,
         money: MoneyPeriodSummary?, insights: InsightsSeries? = nil) {
        self.overview = overview
        self.current = current
        self.previous = previous
        self.money = money
        self.insights = insights
    }
}

nonisolated enum PeriodDataLoader {
    static func shifts(in period: ReportingPeriod) -> FetchDescriptor<Shift> {
        let start = period.start
        let end = period.end
        return FetchDescriptor(predicate: #Predicate {
            $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end
        }, sortBy: [SortDescriptor(\Shift.startedAt, order: .reverse), SortDescriptor(\Shift.id)])
    }

    static func expenses(in period: ReportingPeriod) -> FetchDescriptor<Expense> {
        let start = period.start
        let end = period.end
        return FetchDescriptor(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end },
                               sortBy: [SortDescriptor(\Expense.occurredAt, order: .reverse), SortDescriptor(\Expense.id)])
    }

    static var recentShifts: FetchDescriptor<Shift> {
        var descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\Shift.startedAt, order: .reverse), SortDescriptor(\Shift.id)])
        descriptor.fetchLimit = 3
        return descriptor
    }

    /// Called off main. Models live and die inside this separate read context.
    static func load(_ request: PeriodLoadRequest, in container: ModelContainer) throws -> PeriodDataSnapshot {
        try Task.checkCancellation()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let window = request.insightsWindow {
            let shifts = try context.fetch(shifts(in: window.fetchPeriod))
            var records: [PeriodShiftRecord] = []
            for shift in shifts {
                try Task.checkCancellation()
                records.append(financialRecord(shift, fuel: false))
            }
            let expenses = try context.fetch(expenses(in: window.fetchPeriod))
            let series = try InsightsSeriesBuilder.build(shifts: records, expenses: expenses.map(\.expenseRecord), window: window)
            try Task.checkCancellation()
            guard let latest = series.weeks.last else { throw CancellationError() }
            return PeriodDataSnapshot(overview: HomePeriodSummary(latest.metrics), current: nil,
                                      previous: nil, money: nil, insights: series)
        }
        let currentExpenses = try context.fetch(expenses(in: request.period))
        let current = try metrics(in: request.period, details: request.includesRouteDetails,
                                  fuel: request.includesFuelEstimates, expenses: currentExpenses, context: context)
        let previous = try request.previous.map { try metrics(in: $0, details: request.includesRouteDetails, fuel: false,
                                                       expenses: context.fetch(expenses(in: $0)), context: context) }
        try Task.checkCancellation()
        var money: MoneyPeriodSummary?
        if request.includesExpenseRows {
            var anyExpense = FetchDescriptor<Expense>()
            anyExpense.fetchLimit = 1
            let hasAnyExpense = try !currentExpenses.isEmpty || !context.fetch(anyExpense).isEmpty
            money = MoneyPeriodSummary(metrics: current, rows: currentExpenses.map(\.presentation), hasAnyExpense: hasAnyExpense,
                                       includesFuelEstimates: request.includesFuelEstimates || request.includesRouteDetails)
        }
        try Task.checkCancellation()
        return PeriodDataSnapshot(overview: HomePeriodSummary(current),
                                  current: request.includesRouteDetails ? current : nil,
                                  previous: request.includesRouteDetails ? previous : nil, money: money)
    }

    private static func metrics(in period: ReportingPeriod, details: Bool, fuel: Bool, expenses: [Expense], context: ModelContext) throws -> PeriodMetrics {
        try Task.checkCancellation()
        let shifts = try context.fetch(shifts(in: period))
        var records: [PeriodShiftRecord] = []
        for shift in shifts {
            try Task.checkCancellation()
            if details {
                records.append(shift.periodRecord(for: shift.recordedDistance()))
            } else {
                records.append(financialRecord(shift, fuel: fuel))
            }
        }
        return PeriodMetricsCalculator().metrics(of: records, expenses: expenses.map(\.expenseRecord), in: period)
    }

    /// The shared financial path never realizes deliveries and reads routes only
    /// for an explicit fuel request. Working time retains pause subtraction.
    private static func financialRecord(_ shift: Shift, fuel: Bool) -> PeriodShiftRecord {
        let duration = shift.completedWorkingDuration
        let distance = fuel ? shift.recordedDistance() : RouteDistance.none
        return PeriodShiftRecord(
            startedAt: shift.startedAt, workingDuration: duration,
            grossEarnings: shift.grossEarnings, recordedDistance: distance,
            fuelEstimate: fuel ? shift.fuelEstimate(for: distance) : .unavailable(.milesPerGallonNotRecorded),
            hasHourlyTarget: shift.hourlyTarget != nil,
            hourlyTargetComparison: HourlyTargetComparison(
                rate: duration.flatMap { duration in
                    shift.grossEarnings.flatMap { ShiftMetricsCalculator.grossPerHour(of: $0, over: duration) }
                }, target: shift.hourlyTarget)
        )
    }
}

/// Scene-local state, with no persistence or global cache. A cancelled or superseded
/// request cannot publish, including when its underlying operation ignores cancellation.
@MainActor @Observable
final class PeriodLoadStore {
    enum State: Equatable {
        case loading
        case loaded(PeriodDataSnapshot)
        case failed
    }

    private(set) var state: State = .loading
    private var generation = 0
    private var completedKey: Key?

    struct Key: Equatable {
        let request: PeriodLoadRequest?
        var revision = 0
    }

    func load(key: Key, operation: @escaping @Sendable () async throws -> PeriodDataSnapshot) async {
        guard completedKey != key else { return }
        completedKey = nil
        generation += 1
        let ticket = generation
        state = .loading
        let worker = Task.detached(priority: .userInitiated) { try await operation() }
        let result = await withTaskCancellationHandler {
            await worker.result
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, ticket == generation else { return }
        switch result {
        case .success(let snapshot):
            state = .loaded(snapshot)
            completedKey = key
        case .failure:
            state = .failed
        }
    }
}

/// Route capture saves must not recalculate completed financial history. Other
/// persisted edits invalidate bounded reads, including writes through App Intents.
nonisolated enum PeriodSaveInvalidation {
    static func affectsPeriods(_ notification: Notification) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        let identifiers = keys.flatMap { (notification.userInfo?[$0] ?? notification.userInfo?[$0.rawValue]) as? [PersistentIdentifier] ?? [] }
        // An SDK without identifiers gets a conservative refresh, never silently stale data.
        guard !identifiers.isEmpty else { return true }
        return identifiers.contains { affectsPeriods(entityName: $0.entityName) }
    }

    static func affectsPeriods(entityName: String) -> Bool {
        !["RouteSample", "DriverSettings", "VehicleProfile"].contains(entityName)
    }
}
