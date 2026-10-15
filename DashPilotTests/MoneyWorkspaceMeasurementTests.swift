import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Money loading measurements", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["DASHPILOT_MONEY_PROFILE"] == "1"))
struct MoneyWorkspaceMeasurementTests {
    @Test func boundedHistoryAndMutations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("money-profile-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try ModelContainerFactory.makeContainer(at: directory.appendingPathComponent("history.store"))
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14)))
        let period = try #require(ReportingPeriod(unit: .week, containing: date, calendar: calendar))
        var rows = ["# Money loading profile", "", "iOS simulator, Debug build, on-disk synthetic store. Timings measure data readiness including saves where named, not rendered frames. No speedup claim.", "", "| Scenario | Milliseconds |", "| --- | ---: |"]
        let clock = ContinuousClock()
        func elapsed(_ name: String, from start: ContinuousClock.Instant) {
            let time = start.duration(to: clock.now)
            let ms = Double(time.components.seconds) * 1000 + Double(time.components.attoseconds) / 1e15
            rows.append("| \(name) | \(String(format: "%.3f", ms)) |")
        }
        let request = PeriodLoadRequest(period: period, includesExpenseRows: true)
        let begin = clock.now
        _ = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
        elapsed("Empty store", from: begin)
        for index in 0..<10000 {
            let date = period.start.addingTimeInterval(index < 35 ? Double(index) * 600 : -Double(index) * 3600)
            context.insert(try Expense(occurredAt: date, amount: Money(amount: 12), category: index.isMultiple(of: 2) ? .fuel : .supplies))
        }
        for index in 0..<3124 {
            let start = period.start.addingTimeInterval(index < 4 ? Double(index + 1) * 14400 : -Double(index) * 50000)
            let shift = Shift(startedAt: start)
            context.insert(shift)
            try shift.end(at: start.addingTimeInterval(10800))
            try shift.setGrossEarnings(Money(amount: 75))
        }
        try context.save()
        rows.insert("10,000 expenses and 3,124 shifts; 35 expenses and four completed shifts in selected week. No route reads for the default Money request.", at: 3)
        let store = PeriodLoadStore()
        for (name, revision) in [("Cold selected week", 0), ("Warm Money", 0), ("Return from Work unchanged", 0)] {
            let start = clock.now
            await store.load(key: .init(request: request, revision: revision)) { try PeriodDataLoader.load(request, in: container) }
            elapsed(name, from: start)
        }
        guard case .loaded(let snapshot) = store.state, let summary = snapshot.money else {
            Issue.record("Money did not load"); return
        }
        #expect(summary.rows.count == 35)
        let filterStart = clock.now
        #expect(summary.rows(in: .fuel).count == 18)
        #expect(summary.subtotal(in: .fuel) == Money(amount: 216))
        elapsed("Apply fuel filter and subtotal", from: filterStart)
        let previousRequest = PeriodLoadRequest(period: try #require(period.previous(using: calendar)), includesExpenseRows: true)
        let previousStart = clock.now
        _ = try await Task.detached { try PeriodDataLoader.load(previousRequest, in: container) }.value
        elapsed("Switch to previous week", from: previousStart)
        let service = ExpenseService(context: context)
        let addStart = clock.now
        let expense = try service.record(amount: Money(amount: 15), category: .fuel, occurredAt: period.start)
        _ = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
        elapsed("Add and refresh", from: addStart)
        let editStart = clock.now
        try service.update(expense, amount: Money(amount: 20), category: .other, occurredAt: period.start, noteText: "Synthetic edit")
        _ = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
        elapsed("Edit and refresh", from: editStart)
        let deleteStart = clock.now
        try service.delete(expense)
        _ = try await Task.detached { try PeriodDataLoader.load(request, in: container) }.value
        elapsed("Delete and refresh", from: deleteStart)
        try rows.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dashpilot-money-profile.md"), atomically: true, encoding: .utf8)
    }
}
