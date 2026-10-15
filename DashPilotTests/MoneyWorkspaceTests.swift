import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Money workspace integration")
struct MoneyWorkspaceTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar
    private let period: ReportingPeriod

    init() throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        cal.firstWeekday = 1
        calendar = cal
        period = try #require(ReportingPeriod(unit: .week,
            containing: cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!, calendar: cal))
    }

    private func load(_ selected: ReportingPeriod? = nil, fuel: Bool = false) async throws -> MoneyPeriodSummary {
        let request = PeriodLoadRequest(period: selected ?? period, includesExpenseRows: true, includesFuelEstimates: fuel)
        let container = container
        return try #require(await Task.detached { try PeriodDataLoader.load(request, in: container).money }.value)
    }

    @Test func missingZeroNegativeAndFilteredSubtotal() async throws {
        let empty = try await load()
        #expect(!empty.hasAnyExpense)
        #expect(empty.metrics.recordedGrossEarnings == nil)
        #expect(empty.metrics.expenses.recordedTotal == nil)
        let service = ExpenseService(context: context)
        try service.record(amount: Money(amount: 40), category: .fuel, occurredAt: period.start)
        try service.record(amount: Money(amount: 10), category: .supplies, occurredAt: period.start)
        let expenseOnly = try await load()
        #expect(expenseOnly.metrics.expenses.recordedTotal == Money(amount: 50))
        #expect(expenseOnly.metrics.netAfterRecordedExpenses.amount == nil)
        let shift = Shift(startedAt: period.start)
        context.insert(shift)
        try shift.end(at: period.start.addingTimeInterval(3600))
        try shift.setGrossEarnings(.zero)
        try context.save()
        let summary = try await load()
        #expect(summary.metrics.recordedGrossEarnings == .zero)
        #expect(summary.metrics.netAfterRecordedExpenses.amount == Money(amount: -50))
        #expect(summary.subtotal(in: .fuel) == Money(amount: 40))
        #expect(summary.rows(in: .fuel).count == 1)
        #expect(summary.subtotal(in: .maintenance) == nil)
        #expect(summary.rows(in: .maintenance).isEmpty)
        #expect(summary.metrics.expenses.recordedTotal == Money(amount: 50))
        #expect(summary.subtotal(in: nil) == Money(amount: 50))
    }

    @Test func editsMoveRowsAcrossWeeksAndCategoriesWithoutChangingIdentity() async throws {
        let service = ExpenseService(context: context)
        let expense = try service.record(amount: .zero, category: .fuel, occurredAt: period.start)
        let id = expense.id
        #expect(try await load().subtotal(in: .fuel) == .zero)
        let previous = try #require(period.previous(using: calendar))
        try service.update(expense, amount: Money(amount: 12), category: .other,
                           occurredAt: previous.lastInstant, noteText: "Synthetic correction")
        let current = try await load()
        #expect(current.rows.isEmpty)
        #expect(current.hasAnyExpense)
        #expect(current.metrics.expenses.recordedTotal == nil)
        let older = try await load(previous)
        #expect(older.rows.map(\.id) == [id])
        #expect(older.subtotal(in: .other) == Money(amount: 12))
        #expect(older.rows.first?.note == "Synthetic correction")
    }

    @Test func sundayAndMondayMembershipIncludesWholeOvernightShifts() async throws {
        let sunday = period.start.addingTimeInterval(-60)
        for (date, amount) in [(sunday, 11), (period.start, 12)] {
            let shift = Shift(startedAt: date)
            context.insert(shift)
            try shift.end(at: date.addingTimeInterval(3600))
            try shift.setGrossEarnings(Money(amount: Decimal(amount)))
            try ExpenseService(context: context).record(amount: Money(amount: Decimal(amount)), category: .fuel, occurredAt: date)
        }
        let previous = try #require(period.previous(using: calendar))
        #expect(try await load(previous).metrics.recordedGrossEarnings == Money(amount: 11))
        #expect(try await load(previous).metrics.expenses.recordedTotal == Money(amount: 11))
        #expect(try await load().metrics.recordedGrossEarnings == Money(amount: 12))
        #expect(try await load().metrics.expenses.recordedTotal == Money(amount: 12))
    }

    @Test func orderingUsesDateThenStableIdentity() async throws {
        let service = ExpenseService(context: context)
        for _ in 0..<12 { try service.record(amount: .zero, category: .other, occurredAt: period.start) }
        let newest = try service.record(amount: .zero, category: .other, occurredAt: period.start.addingTimeInterval(1))
        let loaded = try await load()
        #expect(loaded.rows.first?.id == newest.id)
        #expect(loaded.rows.map(\.id) == (try service.expenses(in: period)).map(\.id))
        #expect(Array(loaded.rows.dropFirst()).map(\.id) == loaded.rows.dropFirst().map(\.id).sorted())
        #expect(try await load().rows == loaded.rows)
    }

    @Test func cancelConfirmAndDuplicateConfirmationTargetOnlySelectedIdentity() async throws {
        let service = ExpenseService(context: context)
        let first = try service.record(amount: Money(amount: 10), category: .fuel, occurredAt: period.start)
        let second = try service.record(amount: Money(amount: 20), category: .other, occurredAt: period.start)
        let actions = ExpenseActions()
        actions.pendingDelete = first.presentation
        actions.pendingDelete = nil
        #expect(try await load().rows.count == 2)
        actions.pendingDelete = first.presentation
        actions.confirmDelete(in: context)
        actions.confirmDelete(in: context)
        #expect(try await load().rows.map(\.id) == [second.id])
        #expect(actions.failure == nil)
        let stale = second.presentation
        try service.delete(second)
        actions.pendingDelete = stale
        actions.confirmDelete(in: context)
        #expect(actions.failure != nil)
    }

    @Test func failedWritesPreservePersistedFactsAndTotals() async throws {
        struct Refused: Error {}
        let service = ExpenseService(context: context)
        let expense = try service.record(amount: Money(amount: 25), category: .fuel, occurredAt: period.start)
        let refused = ExpenseService(context: context, commit: { _ in throw Refused() })
        #expect(throws: ExpenseRecordingError.self) {
            try refused.update(expense, amount: Money(amount: 100), category: .other,
                               occurredAt: period.end, noteText: "Rejected")
        }
        #expect(!context.hasChanges)
        #expect(try await load().subtotal(in: .fuel) == Money(amount: 25))
        let freshContext = ModelContext(container)
        let stored = try #require(try freshContext.fetch(FetchDescriptor<Expense>()).first)
        #expect(throws: ExpenseRecordingError.self) {
            try ExpenseService(context: freshContext, commit: { _ in throw Refused() }).delete(stored)
        }
        #expect(try await load().rows.count == 1)
        #expect(throws: ExpenseRecordingError.self) {
            try refused.record(amount: Money(amount: 500), category: .supplies, occurredAt: period.start)
        }
        #expect(try await load().metrics.expenses.recordedTotal == Money(amount: 25))
    }

    @Test func weeklyExportKeepsV6ShapeAndExplicitHalfOpenBounds() throws {
        try ExpenseService(context: context).record(amount: Money(amount: 12), category: .fuel, occurredAt: period.start)
        try ExpenseService(context: context).record(amount: Money(amount: 99), category: .other, occurredAt: period.end)
        let document = try ShiftExportService(context: context, calendar: calendar)
            .document(for: .period(period), exportedAt: period.end)
        let data = try ExportDocumentEncoder().json(for: document)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["formatVersion"] as? Int == 6)
        let scope = try #require(json["scope"] as? [String: Any])
        #expect(scope["kind"] as? String == "week")
        #expect(scope["periodStart"] != nil)
        #expect(scope["periodEndExclusive"] != nil)
        #expect(document.expenses.map(\.amount.string) == ["12.00"])
        #expect(document.expenses.first?.occurredAt == period.start)
        #expect(ExportFormat.version == 6)
    }

    @Test func optionalFuelMatchesFullReportAndNeverChangesRecordedNet() async throws {
        let seeded = try PreviewSupport.seededPeriodSummaryContainer(now: period.start.addingTimeInterval(36 * 3600), calendar: calendar)
        let request = PeriodLoadRequest(period: period, includesRouteDetails: true, includesExpenseRows: true, includesFuelEstimates: true)
        let full = try await Task.detached { try PeriodDataLoader.load(request, in: seeded) }.value
        let moneyRequest = PeriodLoadRequest(period: period, includesExpenseRows: true, includesFuelEstimates: true)
        let money = try await Task.detached { try PeriodDataLoader.load(moneyRequest, in: seeded) }.value
        #expect(money.money?.metrics.fuel == full.current?.fuel)
        #expect(money.money?.metrics.netAfterRecordedExpenses == full.current?.netAfterRecordedExpenses)
        let basicRequest = PeriodLoadRequest(period: period, includesExpenseRows: true)
        let basic = try await Task.detached { try PeriodDataLoader.load(basicRequest, in: seeded) }.value
        #expect(basic.money?.metrics.netAfterRecordedExpenses == money.money?.metrics.netAfterRecordedExpenses)
        #expect(basic.current == nil)
        #expect(basic.money?.metrics.fuel.estimatedCost == nil)
    }
}
