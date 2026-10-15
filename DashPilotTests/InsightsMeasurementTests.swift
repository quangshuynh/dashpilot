import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Insights loading measurements", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["DASHPILOT_INSIGHTS_PROFILE"] == "1"))
struct InsightsMeasurementTests {
    @Test func boundedLongHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insights-profile-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try ModelContainerFactory.makeContainer(at: directory.appendingPathComponent("history.store"))
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        let window = try #require(InsightsWindow(endingAt: now, calendar: calendar))
        let latest = try #require(window.weeks.last)
        for index in 0..<3124 {
            let start = latest.start.addingTimeInterval(-Double(index) * 50000)
            let shift = Shift(startedAt: start); context.insert(shift)
            try shift.end(at: start.addingTimeInterval(10800))
            if !index.isMultiple(of: 3) { try shift.setGrossEarnings(Money(amount: 75)) }
        }
        for index in 0..<10000 {
            context.insert(try Expense(occurredAt: latest.start.addingTimeInterval(-Double(index) * 15000),
                                      amount: Money(amount: 12), category: .fuel))
        }
        try context.save()
        let request = PeriodLoadRequest(period: window.fetchPeriod, insightsWindow: window)
        let store = PeriodLoadStore()
        let clock = ContinuousClock()
        var rows = ["# Insights profile", "", "Debug iOS simulator; on-disk synthetic 3,124 shifts and 10,000 expenses spanning almost five years. Sparse earnings. Loader measurements, not chart frame performance.", "", "| Scenario | ms |", "| --- | ---: |"]
        func elapsed(_ name: String, _ start: ContinuousClock.Instant) {
            let value = start.duration(to: clock.now).components
            rows.append("| \(name) | \(String(format: "%.3f", Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15)) |")
        }
        for (name, revision) in [("Cold Insights", 0), ("Warm reuse", 0), ("Return from another tab unchanged", 0), ("Earnings correction refresh", 1), ("Expense correction refresh", 2)] {
            if revision == 1 {
                let shift = try #require(context.fetch(PeriodDataLoader.shifts(in: latest)).first)
                try shift.setGrossEarnings(Money(amount: 90)); try context.save()
            } else if revision == 2 {
                let expense = try #require(context.fetch(PeriodDataLoader.expenses(in: latest)).first)
                try ExpenseService(context: context).update(expense, amount: Money(amount: 20), category: .other, occurredAt: latest.start, noteText: "Synthetic")
            }
            let start = clock.now
            await store.load(key: .init(request: request, revision: revision)) { try PeriodDataLoader.load(request, in: container) }
            elapsed(name, start)
        }
        guard case .loaded(let snapshot) = store.state, let series = snapshot.insights else { Issue.record("Insights failed"); return }
        let selectedStart = clock.now
        for point in series.weeks {
            #expect(point.comparison(asOf: now, calendar: calendar) != nil)
            _ = point.rankedExpenses
        }
        elapsed("Select all eight weeks, comparisons and categories only", selectedStart)
        let next = try #require(InsightsWindow(endingAt: window.precedingWeek.start, calendar: calendar))
        let nextRequest = PeriodLoadRequest(period: next.fetchPeriod, insightsWindow: next)
        let pageStart = clock.now
        _ = try await Task.detached { try PeriodDataLoader.load(nextRequest, in: container) }.value
        elapsed("Earlier eight weeks", pageStart)
        rows.append("\nBounded fetch: \(try context.fetchCount(PeriodDataLoader.shifts(in: window.fetchPeriod))) shifts and \(try context.fetchCount(PeriodDataLoader.expenses(in: window.fetchPeriod))) expenses. No routes or deliveries requested.")
        try rows.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dashpilot-insights-profile.md"), atomically: true, encoding: .utf8)
    }
}
