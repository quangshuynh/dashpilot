import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Opt-in diagnostics, never timing thresholds. Measures the shipping loader and
/// warm-state reuse, not XCTest launch time or a claimed rendering speedup.
@MainActor
@Suite("Home period loading measurements", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["DASHPILOT_HOME_PROFILE"] == "1"))
struct PeriodDataLoaderMeasurementTests {
    @Test func largeHistoryPresentation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("home-profile-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the store until process exit, avoiding unlinking live SQLite handles.
        let container = try ModelContainerFactory.makeContainer(at: directory.appendingPathComponent("history.store"))
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15)))
        let period = try #require(ReportingPeriod(unit: .week, containing: now, calendar: calendar))
        for index in 0..<3124 {
            let start = period.start.addingTimeInterval(index < 4 ? Double(index + 1) * 14400 : -Double(index) * 50000)
            let shift = Shift(startedAt: start)
            context.insert(shift)
            try shift.end(at: start.addingTimeInterval(10800))
            try shift.setGrossEarnings(Money(amount: 75))
            if index < 4 {
                let session = UUID()
                for sample in 0..<3000 {
                    context.insert(RouteSample(shift: shift, timestamp: start.addingTimeInterval(Double(sample)),
                        latitude: 40 + Double(sample) * 0.00001, longitude: -74, horizontalAccuracy: 5,
                        captureSessionID: session))
                }
            }
        }
        try context.save()
        let request = PeriodLoadRequest(period: period)
        let store = PeriodLoadStore()
        let clock = ContinuousClock()
        var rows: [String] = ["# Home loading profile", "", "iOS simulator, on-disk synthetic store: 3,124 completed shifts; four current-week shifts with 3,000 route positions each. Home reads no route positions. Times are diagnostic loader intervals, not display-frame latency.", "", "| Scenario | milliseconds |", "| --- | ---: |"]
        for (name, revision) in [("Cold Home load", 0), ("Warm Home reuse", 0), ("Return from Work, unchanged", 0), ("After earnings correction", 1)] {
            if revision == 1 {
                let shift = try #require(context.fetch(PeriodDataLoader.shifts(in: period)).first)
                try shift.setGrossEarnings(Money(amount: 90))
                try context.save()
            }
            let begin = clock.now
            await store.load(key: .init(request: request, revision: revision)) {
                try PeriodDataLoader.load(request, in: container)
            }
            let elapsed = begin.duration(to: clock.now)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            rows.append("| \(name) | \(String(format: "%.3f", ms)) |")
            guard case .loaded(let result) = store.state else { Issue.record("Load failed"); return }
            #expect(result.overview.completedShiftCount == 4)
            #expect(result.overview.earnings == Money(amount: revision == 1 ? 315 : 300))
        }
        let selected = try context.fetch(PeriodDataLoader.recentShifts)
        #expect(selected.count == 3)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dashpilot-home-profile.md")
        try rows.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
