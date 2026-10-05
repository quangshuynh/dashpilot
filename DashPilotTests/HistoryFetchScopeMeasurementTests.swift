import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Measures what History costs to present as a driver's store grows from one
/// week to five years.
///
/// These are measurements, not assertions about behaviour, so they are **off by
/// default**, exactly as `RouteCaptureWritePerformanceTests` is: the numbers
/// depend on the machine, and a number is not something to fail a build over.
///
/// ```bash
/// TEST_RUNNER_DASHPILOT_HISTORY_PROFILE=1 xcodebuild test -scheme DashPilot \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -parallel-testing-enabled NO \
///   -only-testing:DashPilotTests/HistoryFetchScopeMeasurementTests
/// find ~/Library/Developer/CoreSimulator/Devices -name 'dashpilot-history-fetch-profile.md'
/// ```
///
/// The same three details that trip up the capture profile apply here and each
/// fails silently: the `TEST_RUNNER_` prefix must be an environment variable of
/// `xcodebuild`, `-parallel-testing-enabled NO` keeps the report off a clone
/// that deletes it, and the numbers are in the file because a test's `print`
/// never reaches the `xcodebuild` log.
///
/// ## What is measured, and why these and not a screen
///
/// Wall-clock UI assertions are fragile on a shared host, so this measures the
/// work the two History screens ask the store and the domain for, through the
/// **same descriptors and the same partition** the screens use:
///
/// - how many `Shift` objects the root screen's query realises,
/// - what that fetch costs, cold and warm, on an on-disk store,
/// - what one `HistoryWeek.partition` costs over it, and how many times the
///   root screen's body evaluates it,
/// - what entering Older Weeks costs (the same fetch plus its own partitions),
/// - what the week-scoped alternative costs for the same screen.
///
/// Every synthetic shift carries an amount, fuel assumptions and deliveries, so
/// the store is the shape an active driver's is, not a table of bare rows.
@MainActor
@Suite(
    "History fetch scope measurement",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["DASHPILOT_HISTORY_PROFILE"] == "1")
)
struct HistoryFetchScopeMeasurementTests {
    /// Twelve shifts a week: two a day, six days, which is a full-time driver
    /// working a lunch and a dinner block.
    private static let shiftsPerWeek = 12

    /// Four deliveries a shift.
    private static let deliveriesPerShift = 4

    /// How many times each timing is repeated on a fresh context. The first run
    /// is reported separately as the cold one.
    private static let repeats = 5

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Wednesday 23 September 2026, 15:00 New York: two days into its week, so
    /// the current week holds Monday's and Tuesday's shifts.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15))!
    }

    @Test("History presentation cost from one week to five years")
    func presentationCostAcrossHistoryLengths() throws {
        Report.reset()
        Report.line("# History fetch scope profile")
        Report.line("")
        Report.line("\(Self.shiftsPerWeek) shifts a week, \(Self.deliveriesPerShift) deliveries a shift, on-disk store, "
            + "median of \(Self.repeats) fresh contexts unless marked cold.")
        Report.line("")
        Report.line(
            "| History | shifts | before: root realises | before: fetch cold ms | before: fetch ms | partition ms "
                + "| before: root refresh ms (fetch + 7 partitions) | after: root realises | after: week fetch ms "
                + "| after: other-shift count ms | after: root refresh ms | after: week count ms (off main) "
                + "| before: Older Weeks entry ms (fetch + 2 partitions) | after: Older Weeks entry ms (fetch + 1 partition) |"
        )
        Report.line("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")

        for (name, weeks) in [("1 week", 1), ("3 months", 13), ("1 year", 52), ("3 years", 156), ("5 years", 261)] {
            let store = try SeededStore(weeks: weeks, now: now, calendar: calendar)
            defer { store.tearDown() }
            let row = try measure(store)

            // The current week holds its Monday and Tuesday; every other week
            // holds a full twelve.
            let total = (weeks - 1) * Self.shiftsPerWeek + 4
            #expect(row.rootRealised == total, "Every seeded shift is completed and fetched")
            #expect(row.weekScopedRealised == 4, "The week-scoped fetch holds this week and nothing else")
            #expect(row.otherShiftCount == total - 4, "The count is every shift outside the week")

            Report.line(
                "| \(name) | \(total) | \(row.rootRealised) | \(ms(row.rootFetchCold)) "
                    + "| \(ms(row.rootFetch)) | \(ms(row.partition)) | \(ms(row.rootFetch + row.partition * 7)) "
                    + "| \(row.weekScopedRealised) | \(ms(row.weekScopedFetch)) | \(ms(row.otherShiftCountTime)) "
                    + "| \(ms(row.weekScopedFetch + row.otherShiftCountTime)) | \(ms(row.otherWeeksSummary)) "
                    + "| \(ms(row.rootFetch + row.partition * 2)) | \(ms(row.olderFetch + row.olderPartition)) |"
            )
        }
    }

    @Test("What one older week's summary costs to derive, with routes")
    func weekSummaryCostWithRoutes() throws {
        let store = try SeededStore(weeks: 2, now: now, calendar: calendar, positionsPerShift: 3_000)
        defer { store.tearDown() }

        let context = ModelContext(store.container)
        let shifts = try context.fetch(Self.completedDescriptor)
        let partition = try #require(HistoryWeek.partition(shifts, by: \.startedAt, asOf: now, calendar: calendar))
        let lastWeek = try #require(partition.otherWeeks.first)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = HistoryWeekSummary(
                week: lastWeek.week,
                records: lastWeek.elements.map { $0.periodRecord(for: $0.recordedDistance()) }
            )
        }
        #expect(lastWeek.elements.count == Self.shiftsPerWeek)

        // The shipping path: identifiers handed to a context of its own, which
        // Older Weeks runs off the main actor. The main actor pays only for
        // collecting the identifiers.
        var ids: [UUID] = []
        let collecting = clock.measure { ids = lastWeek.elements.map(\.id) }
        var offMain: HistoryWeekSummary?
        let background = clock.measure {
            offMain = HistoryFetchScope.weekSummary(of: lastWeek.week, shiftIDs: ids, in: store.container)
        }
        let direct = HistoryWeekSummary(
            week: lastWeek.week,
            records: lastWeek.elements.map { $0.periodRecord(for: $0.recordedDistance()) }
        )
        #expect(offMain == direct, "The context of its own derives the same figures")

        Report.line("")
        Report.line(
            "One older week's summary, \(Self.shiftsPerWeek) shifts of 3,000 positions each. "
                + "Before, on the main actor as the section appeared: \(ms(elapsed)) ms. "
                + "After: \(ms(collecting)) ms on the main actor to collect identifiers, and "
                + "\(ms(background)) ms on a context of its own, which Older Weeks runs off the main actor."
        )
    }

    /// What Older Weeks costs, phase by phase, with routes the size a real
    /// shift records, as a store grows.
    ///
    /// Written after a driver reported, on October 3 2026, that Older Weeks
    /// became very laggy as weeks accumulated. The screen's work is reproduced
    /// on the actor the screen does it on. Before the change each row measured
    /// its own route on the main actor as it appeared (one row's route on main,
    /// below, is that cost); after it, a week's routes are measured once, off
    /// the main actor, by ``HistoryFetchScope/weekPresentation(of:shiftIDs:in:)``,
    /// and the main actor pays for the entry fetch and each visible week's
    /// revision hash. A screenful is about eight rows and three week sections.
    ///
    /// Measured before (row route on main, `shift.id` predicate) on the iPhone 17
    /// simulator: 39, 69 and 121 ms a row at one, three and six months, so a
    /// first screen cost 335, 582 and 1,004 ms of main actor and scrolling every
    /// row once 1.9, 10.0 and 36.2 s.
    @Test("Older Weeks cost by phase, with routes")
    func olderWeeksCostByPhase() throws {
        let positions = Self.realisticPositionsPerShift
        Report.line("")
        Report.line("## Older Weeks by phase, \(positions) positions a shift, on-disk store")
        Report.line("")
        Report.line(
            "| History | older shifts | entry: fetch + partition ms | one week's revision on main ms "
                + "| one route if measured on main ms | one week's routes and summary, off main ms "
                + "| main-actor work, first screen (entry + 3 revisions) ms "
                + "| main-actor work, scrolling every week once ms |"
        )
        Report.line("| --- | --- | --- | --- | --- | --- | --- | --- |")

        for (name, weeks) in [("1 month", 5), ("3 months", 13), ("6 months", 26)] {
            let store = try SeededStore(weeks: weeks, now: now, calendar: calendar, positionsPerShift: positions)
            defer { store.tearDown() }
            let row = try measureOlderWeeks(store)
            let weekCount = max(1, row.shifts / Self.shiftsPerWeek)
            Report.line(
                "| \(name) | \(row.shifts) | \(ms(row.entry)) | \(ms(row.revision)) | \(ms(row.rowRoute)) "
                    + "| \(ms(row.weekSummary)) | \(ms(row.entry + row.revision * 3)) "
                    + "| \(ms(row.entry + row.revision * weekCount)) |"
            )
        }
    }

    /// Where one row's route time goes, and whether it grows with the store
    /// because of the fetch or because of the walk.
    @Test("One shift's route: fetch by the shift's id, by its key, and the walk")
    func routeFetchProbe() throws {
        Report.line("")
        Report.line("## One shift's route, \(Self.realisticPositionsPerShift) positions, by store size")
        Report.line("")
        Report.line("| History | stored positions | fetch by shift.id ms | fetch by relationship key ms | walk ms |")
        Report.line("| --- | --- | --- | --- | --- |")
        for (name, weeks) in [("1 month", 5), ("6 months", 26)] {
            let store = try SeededStore(weeks: weeks, now: now, calendar: calendar, positionsPerShift: Self.realisticPositionsPerShift)
            defer { store.tearDown() }
            let clock = ContinuousClock()
            var byID: [Duration] = [], byKey: [Duration] = [], walks: [Duration] = []
            var total = 0
            for _ in 0..<Self.repeats {
                let context = ModelContext(store.container)
                total = try context.fetchCount(FetchDescriptor<RouteSample>())
                let shift = try #require(try context.fetch(HistoryFetchScope.otherWeeks(HistoryWeek(containing: now, calendar: calendar))).first)
                let shiftID = shift.id
                var samples: [RouteSample] = []
                byID.append(try clock.measure {
                    samples = try context.fetch(FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == shiftID }))
                })
                let fresh = ModelContext(store.container)
                let key = shift.persistentModelID
                var keyed: [RouteSample] = []
                byKey.append(try clock.measure {
                    keyed = try fresh.fetch(FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.persistentModelID == key }))
                })
                #expect(keyed.count == samples.count)
                let points = samples.map(\.routePoint)
                walks.append(clock.measure { _ = RouteMileageCalculator().distance(of: points, covering: shift.completedWindow) })
            }
            Report.line("| \(name) | \(total) | \(ms(median(byID))) | \(ms(median(byKey))) | \(ms(median(walks))) |")
        }
    }

    /// A four-hour shift with a position accepted about every ten seconds:
    /// what the filter keeps from a phone in a cradle at city speeds.
    static let realisticPositionsPerShift = 1_500

    private struct OlderWeeksRow {
        var shifts = 0
        var entry: Duration = .zero
        var rowRoute: Duration = .zero
        var revision: Duration = .zero
        var weekSummary: Duration = .zero
    }

    private func measureOlderWeeks(_ store: SeededStore) throws -> OlderWeeksRow {
        let clock = ContinuousClock()
        var row = OlderWeeksRow()
        var entries: [Duration] = [], routes: [Duration] = [], revisions: [Duration] = [], summaries: [Duration] = []
        let week = try #require(HistoryWeek(containing: now, calendar: calendar))

        for _ in 0..<Self.repeats {
            let context = ModelContext(store.container)
            var groups: [HistoryWeekGroup<Shift>] = []
            entries.append(try clock.measure {
                let others = try context.fetch(HistoryFetchScope.otherWeeks(week))
                groups = HistoryWeek.partition(others, by: \.startedAt, asOf: now, calendar: calendar)?.otherWeeks ?? []
            })
            row.shifts = groups.reduce(0) { $0 + $1.elements.count }
            let first = try #require(groups.first)
            let shift = try #require(first.elements.first)
            routes.append(clock.measure { _ = shift.recordedDistance() })
            revisions.append(clock.measure { _ = HistoryWeekRevision(first.elements) })
            let ids = first.elements.map(\.id)
            summaries.append(clock.measure {
                _ = HistoryFetchScope.weekPresentation(of: first.week, shiftIDs: ids, in: store.container)
            })
        }
        row.entry = median(entries)
        row.rowRoute = median(routes)
        row.revision = median(revisions)
        row.weekSummary = median(summaries)
        return row
    }

    // MARK: Measuring

    private struct Row {
        var rootRealised = 0
        var rootFetchCold: Duration = .zero
        var rootFetch: Duration = .zero
        var partition: Duration = .zero
        var weekScopedRealised = 0
        var weekScopedFetch: Duration = .zero
        var otherShiftCount = 0
        var otherShiftCountTime: Duration = .zero
        var otherWeeksSummary: Duration = .zero
        var olderFetch: Duration = .zero
        var olderPartition: Duration = .zero
    }

    /// The root screen's query before this interval: every completed shift,
    /// newest first.
    private static var completedDescriptor: FetchDescriptor<Shift> { HistoryFetchScope.allCompleted }

    private func measure(_ store: SeededStore) throws -> Row {
        let clock = ContinuousClock()
        var row = Row()
        var samples: [String: [Duration]] = [:]
        func record(_ key: String, _ duration: Duration) { samples[key, default: []].append(duration) }

        let week = try #require(HistoryWeek(containing: now, calendar: calendar))

        for attempt in 0..<Self.repeats {
            // A fresh context each time, so no identity map carries objects
            // realised by the previous attempt.
            let context = ModelContext(store.container)
            var shifts: [Shift] = []
            let fetch = try clock.measure { shifts = try context.fetch(Self.completedDescriptor) }
            if attempt == 0 { row.rootFetchCold = fetch } else { record("rootFetch", fetch) }
            row.rootRealised = shifts.count
            record("partition", clock.measure {
                _ = HistoryWeek.partition(shifts, by: \.startedAt, asOf: now, calendar: calendar)
            })

            // The root screen after this interval: the week, and a count.
            let scopedContext = ModelContext(store.container)
            var weekShifts: [Shift] = []
            record("weekScoped", try clock.measure {
                weekShifts = try scopedContext.fetch(HistoryFetchScope.currentWeek(week))
            })
            row.weekScopedRealised = weekShifts.count
            record("otherCount", try clock.measure {
                row.otherShiftCount = try HistoryFetchScope.otherWeekShiftCount(outside: week, in: scopedContext)
            })
            record("otherSummary", try clock.measure {
                _ = try HistoryFetchScope.otherWeeksSummary(outside: week, in: store.container, calendar: calendar)
            })

            // Older Weeks after this interval: the other weeks, grouped once.
            let olderContext = ModelContext(store.container)
            var others: [Shift] = []
            record("olderFetch", try clock.measure {
                others = try olderContext.fetch(HistoryFetchScope.otherWeeks(week))
            })
            record("olderPartition", clock.measure {
                _ = HistoryWeek.partition(others, by: \.startedAt, asOf: now, calendar: calendar)
            })
        }

        row.rootFetch = median(samples["rootFetch"] ?? [])
        row.partition = median(samples["partition"] ?? [])
        row.weekScopedFetch = median(samples["weekScoped"] ?? [])
        row.otherShiftCountTime = median(samples["otherCount"] ?? [])
        row.otherWeeksSummary = median(samples["otherSummary"] ?? [])
        row.olderFetch = median(samples["olderFetch"] ?? [])
        row.olderPartition = median(samples["olderPartition"] ?? [])
        return row
    }

    private func median(_ durations: [Duration]) -> Duration {
        let sorted = durations.sorted()
        return sorted.isEmpty ? .zero : sorted[sorted.count / 2]
    }

    private func ms(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f", seconds * 1_000)
    }

    // MARK: The store

    /// An on-disk store holding `weeks` weeks of synthetic completed shifts,
    /// ending with the current week's Monday and Tuesday.
    @MainActor
    private final class SeededStore {
        let container: ModelContainer
        private let url: URL

        init(weeks: Int, now: Date, calendar: Calendar, positionsPerShift: Int = 0) throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("history-profile-\(UUID().uuidString).store")
            container = try ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)

            let mondayFirst = HistoryWeek.mondayFirst(calendar)
            guard let thisWeek = HistoryWeek(containing: now, calendar: calendar) else { return }

            for weeksAgo in 0..<weeks {
                guard let weekStart = mondayFirst.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek.start)
                else { continue }
                // The current week holds Monday and Tuesday only, so nothing
                // is dated after `now`.
                let days = weeksAgo == 0 ? 2 : 6
                for day in 0..<days {
                    for hour in [11, 17] {
                        guard let start = mondayFirst.date(
                            byAdding: DateComponents(day: day, hour: hour),
                            to: weekStart
                        ) else { continue }
                        try Self.seedShift(startingAt: start, positions: positionsPerShift, in: context)
                    }
                }
                if weeksAgo % 26 == 0 { try context.save() }
            }
            try context.save()
        }

        private static func seedShift(startingAt start: Date, positions: Int, in context: ModelContext) throws {
            let shift = Shift(startedAt: start)
            context.insert(shift)
            for index in 0..<HistoryFetchScopeMeasurementTests.deliveriesPerShift {
                let accepted = start.addingTimeInterval(Double(index) * 1_500 + 300)
                let offer = Offer(shift: shift, acceptedAt: accepted)
                context.insert(offer)
                let delivery = Delivery(shift: shift, offer: offer, acceptedAt: accepted)
                context.insert(delivery)
                try delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(300))
                try delivery.markPickedUp(at: accepted.addingTimeInterval(600))
                try delivery.markDelivered(at: accepted.addingTimeInterval(1_200))
            }
            let session = UUID()
            for index in 0..<positions {
                context.insert(
                    RouteSample(
                        shift: shift,
                        timestamp: start.addingTimeInterval(Double(index) * 4),
                        latitude: 40.0 + Double(index) * 0.0001,
                        longitude: -74.0,
                        horizontalAccuracy: 10,
                        captureSessionID: session
                    )
                )
            }
            try shift.end(at: start.addingTimeInterval(4 * 3_600))
            try shift.setGrossEarnings(Money(minorUnits: 8_000))
            try shift.setFuelAssumptions(
                milesPerGallon: 34,
                gasPricePerGallon: Money(minorUnits: 329),
                vehicleName: "Synthetic Hatchback"
            )
        }

        func tearDown() {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
    }

    // MARK: The report

    /// The report is a file rather than the log because a test's `print` does
    /// not reach `xcodebuild`'s output.
    private enum Report {
        static let fileName = "dashpilot-history-fetch-profile.md"

        private static var url: URL {
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        }

        static func reset() { try? FileManager.default.removeItem(at: url) }

        static func line(_ line: String) {
            let text = ((try? String(contentsOf: url, encoding: .utf8)) ?? "") + line + "\n"
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
