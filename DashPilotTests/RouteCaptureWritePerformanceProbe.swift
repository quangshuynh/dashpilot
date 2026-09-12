import Darwin
import Foundation
import SwiftData
@testable import DashPilot

/// The instrument the route-capture write investigation is measured with.
///
/// It is a *probe*, not an assertion: it drives the shipping capture pipeline
/// and reports what each write cost, so a claim about long-shift write
/// performance can be made from numbers rather than from a hunch. Nothing here
/// runs in the ordinary suite; see `RouteCaptureWritePerformanceTests` for the
/// gate.
///
/// ## Fidelity
///
/// Everything on the write path is the shipping type: the same `ModelContext`
/// from the same container factory, **one context and one shift for the length
/// of the run**, the real `LocationTrackingService`, the real
/// `RouteSampleFilter`, the real `RouteSample` model with its real inverse
/// relationship to `Shift`, the real capture session, and the real batch size
/// of ten. Only the source of the positions and the clock are synthetic,
/// exactly as they are in the capture tests.
///
/// ## Time is compressed, and only time
///
/// Timestamps advance one second per position, so the filter, the route and the
/// stored history are those of a shift recorded at capture cadence. The
/// *inserts* happen as fast as the machine manages. Nothing on this path reads
/// the wall clock: the staleness rule is judged against the injected clock,
/// and SwiftData and SQLite do not care how long ago the previous write was. An
/// eight-hour shift is therefore measured in benchmark time, and the time a run
/// takes is the cost being measured rather than a wait.
///
/// Coordinates come from ``SyntheticRoute``, so no real location history is
/// involved, and nothing here records a coordinate.
@MainActor
enum RouteCaptureWriteProbe {
    /// How the positions are delivered.
    enum Cadence {
        /// A tight loop, which is what the seeding that first raised the
        /// question did.
        case burst
        /// One position per turn of the run loop, each inside its own
        /// autorelease pool. This reproduces every structural difference
        /// between capture and a seeding loop except the wall-clock spacing:
        /// the callback returns, temporaries are released, and the main actor
        /// goes idle between positions.
        case perRunLoopTurn

        var description: String {
            switch self {
            case .burst: "burst"
            case .perRunLoopTurn: "one position per run-loop turn"
            }
        }
    }

    /// What one stretch of capture cost.
    struct Bucket {
        var range: Range<Int>
        /// Positions that were only inserted, never flushed.
        var insertSamples: [Double] = []
        /// Positions whose delivery also carried the batch save.
        var flushSamples: [Double] = []
        /// Process footprint, in bytes, at the end of the bucket.
        var footprint: UInt64 = 0

        var insertMeanMicroseconds: Double { Self.mean(insertSamples) * 1e6 }
        var flushMeanMilliseconds: Double { Self.mean(flushSamples) * 1e3 }
        var totalSeconds: Double { insertSamples.reduce(0, +) + flushSamples.reduce(0, +) }

        /// Mean of the middle of the distribution, so one scheduling hiccup
        /// does not describe a thousand positions.
        static func mean(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let drop = sorted.count / 20
            let trimmed = sorted.dropFirst(drop).dropLast(drop)
            guard !trimmed.isEmpty else { return sorted.reduce(0, +) / Double(sorted.count) }
            return trimmed.reduce(0, +) / Double(trimmed.count)
        }
    }

    /// One complete run of the probe.
    struct Run {
        var label: String
        var buckets: [Bucket]
        var startFootprint: UInt64
        var wallClockSeconds: Double
        var storedRowCount: Int

        var totalMainActorSeconds: Double { buckets.reduce(0) { $0 + $1.totalSeconds } }
        var footprintGrowthMegabytes: Double {
            let end = Double(buckets.last?.footprint ?? startFootprint)
            return (end - Double(startFootprint)) / 1_048_576
        }
    }

    // MARK: Harness

    /// The app's wiring with Core Location replaced, and nothing else replaced.
    @MainActor
    final class Harness {
        let container: ModelContainer
        let context: ModelContext
        let provider: StubLocationTrackingProvider
        let tracking: LocationTrackingService
        let shift: Shift
        private let storeURL: URL?
        private let clock: ClockBox

        @MainActor
        final class ClockBox {
            var date: Date
            init(_ date: Date) { self.date = date }
        }

        init(inMemory: Bool, start: Date, saveBatchSize: Int = 10) throws {
            if inMemory {
                container = try ModelContainerFactory.makeInMemoryContainer()
                storeURL = nil
            } else {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("capture-probe-\(UUID().uuidString).store")
                container = try ModelContainerFactory.makeContainer(at: url)
                storeURL = url
            }
            context = container.mainContext
            provider = StubLocationTrackingProvider()
            let authorization = LocationAuthorizationService(
                provider: StubLocationAuthorizationProvider(
                    servicesEnabled: true,
                    status: .authorizedWhenInUse,
                    accuracy: .full
                )
            )
            let clock = ClockBox(start)
            self.clock = clock
            tracking = LocationTrackingService(
                context: context,
                authorization: authorization,
                provider: provider,
                saveBatchSize: saveBatchSize,
                now: { clock.date }
            )
            shift = try ShiftService(context: context).startShift(at: start)
            tracking.synchronize()
        }

        /// Advances the synthetic clock to the instant a position was fixed, so
        /// the staleness rule judges a fresh fix however long the run takes.
        func setClock(to date: Date) { clock.date = date }

        func tearDown() {
            tracking.prepareForShiftEnd()
            if let storeURL {
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(
                        at: URL(fileURLWithPath: storeURL.path + suffix)
                    )
                }
            }
        }
    }

    // MARK: Driving

    /// Feeds `count` accepted positions through the shipping pipeline, one per
    /// synthetic second, and reports what each cost.
    ///
    /// Every bucket is written to the report file as soon as it closes, so a
    /// run that is interrupted still leaves the curve it had measured.
    ///
    /// - Parameters:
    ///   - bucketSize: how many positions each reported row covers.
    ///   - metresPerSecond: separation between consecutive positions. Twenty
    ///     metres is about 45 mph, clears the movement threshold and stays far
    ///     under the implausible-speed rule, so every position is accepted.
    static func capture(
        _ count: Int,
        into harness: Harness,
        from start: Date,
        offset: Int = 0,
        label: String,
        cadence: Cadence,
        bucketSize: Int = 900,
        metresPerSecond: Double = 20
    ) async -> Run {
        openTable(label: label, cadence: cadence)

        var buckets: [Bucket] = []
        let startFootprint = footprint()
        let wallClockStart = DispatchTime.now().uptimeNanoseconds

        var index = 0
        while index < count {
            let upper = min(index + bucketSize, count)
            var bucket = Bucket(range: (offset + index)..<(offset + upper))

            for step in (offset + index)..<(offset + upper) {
                let timestamp = start.addingTimeInterval(Double(step) + 1)
                harness.setClock(to: timestamp)
                let sample = SyntheticRoute.sample(
                    at: timestamp,
                    northMetres: Double(step + 1) * metresPerSecond
                )

                let elapsed: Double
                switch cadence {
                case .burst:
                    elapsed = time { harness.provider.emit(sample) }
                case .perRunLoopTurn:
                    elapsed = autoreleasepool { time { harness.provider.emit(sample) } }
                    await Task.yield()
                }

                // The batch save rides on the position that fills the batch, so
                // the two costs are told apart by which position it was.
                if (step + 1).isMultiple(of: 10) {
                    bucket.flushSamples.append(elapsed)
                } else {
                    bucket.insertSamples.append(elapsed)
                }
            }

            bucket.footprint = footprint()
            buckets.append(bucket)
            emit(bucket)
            index = upper
        }

        let wallClock = Double(DispatchTime.now().uptimeNanoseconds - wallClockStart) / 1e9
        let stored = (try? harness.context.fetchCount(FetchDescriptor<RouteSample>())) ?? -1
        let run = Run(
            label: label,
            buckets: buckets,
            startFootprint: startFootprint,
            wallClockSeconds: wallClock,
            storedRowCount: stored
        )
        closeTable(run)
        return run
    }

    /// Feeds `count` positions at a genuine one per second of wall clock.
    ///
    /// Isolated deliberately, and kept to a minute: nothing on the write path
    /// reads the wall clock, so the compressed runs above should describe a
    /// real shift exactly. This is the check on that claim rather than the way
    /// the shift lengths are measured, and it is the only function here that
    /// waits for anything.
    static func captureAtRealCadence(
        _ count: Int,
        into harness: Harness,
        from start: Date,
        offsetSeconds: Int,
        metresPerSecond: Double = 20
    ) async -> Bucket {
        var bucket = Bucket(range: offsetSeconds..<(offsetSeconds + count))
        for step in offsetSeconds..<(offsetSeconds + count) {
            let timestamp = start.addingTimeInterval(Double(step) + 1)
            harness.setClock(to: timestamp)
            let sample = SyntheticRoute.sample(
                at: timestamp,
                northMetres: Double(step + 1) * metresPerSecond
            )
            let elapsed = autoreleasepool { time { harness.provider.emit(sample) } }
            if (step + 1).isMultiple(of: 10) {
                bucket.flushSamples.append(elapsed)
            } else {
                bucket.insertSamples.append(elapsed)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        bucket.footprint = footprint()
        return bucket
    }

    // MARK: Reporting

    /// The report is a file rather than the log because a test's `print` does
    /// not reach `xcodebuild`'s output, and it is flushed after every bucket
    /// because a long run may be stopped before it ends.
    static let reportFileName = "dashpilot-capture-write-profile.md"

    private static var reportURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(reportFileName)
    }

    static func say(_ line: String) {
        print(line)
        let text = ((try? String(contentsOf: reportURL, encoding: .utf8)) ?? "") + line + "\n"
        try? text.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    static func openTable(label: String, cadence: Cadence) {
        say("")
        say("### \(label)")
        say("")
        say("Delivery: \(cadence.description). Timestamps one second apart.")
        say("")
        say("| positions | insert mean (µs) | batch save mean (ms) | bucket total (s) | footprint (MB) |")
        say("| --- | --- | --- | --- | --- |")
    }

    static func emit(_ bucket: Bucket) {
        say(
            "| \(bucket.range.lowerBound)-\(bucket.range.upperBound) "
            + "| \(format(bucket.insertMeanMicroseconds, 1)) "
            + "| \(format(bucket.flushMeanMilliseconds, 3)) "
            + "| \(format(bucket.totalSeconds, 2)) "
            + "| \(format(megabytes(bucket.footprint), 1)) |"
        )
    }

    static func closeTable(_ run: Run) {
        say("")
        say(
            "\(run.storedRowCount) stored positions. "
            + "Main-actor time in capture writes: \(format(run.totalMainActorSeconds, 1)) s. "
            + "Wall clock: \(format(run.wallClockSeconds, 1)) s. "
            + "Footprint grew \(format(run.footprintGrowthMegabytes, 1)) MB."
        )
    }

    static func format(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    static func megabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }

    // MARK: Instruments

    static func time(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    /// The process footprint iOS itself accounts against the app.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}

/// Narrows *where* a growing write cost comes from, once the shipping run has
/// shown that there is one.
///
/// Each variant writes the same rows, through the same model and the same
/// relationship, and differs from the shipping shape in exactly one way. None
/// of them is a proposal; they are there to tell two candidate causes apart.
///
/// - `shipping` writes the way the capture service does: one context and one
///   shift for the length of the run.
/// - `freshContextPeriodically` discards the context and re-fetches the shift
///   every `resetEvery` positions, so the number of objects one context has
///   registered stops growing while the stored route keeps growing.
/// - `shortRelationships` keeps the one context and starts a **new shift**
///   every `resetEvery` positions, so the context keeps accumulating while no
///   single `Shift.routeSamples` gets long.
///
/// If cost is flat in the second but not the third, the context's registered
/// objects are the cause. If it is flat in the third but not the second, the
/// length of the relationship is.
@MainActor
enum RouteCaptureWriteIsolation {
    enum Variant: String, CaseIterable {
        case shipping
        case fetchedShift
        case freshContextPeriodically
        case shortRelationships

        var label: String {
            switch self {
            case .shipping: "One context, one shift (the shipping shape)"
            case .fetchedShift: "One context for the run, the shift fetched into it rather than created in it"
            case .freshContextPeriodically: "Fresh context every 900 positions"
            case .shortRelationships: "One context, a new shift every 900 positions"
            }
        }
    }

    static func run(
        _ variant: Variant,
        positions: Int,
        start: Date,
        bucketSize: Int = 900,
        resetEvery: Int = 900,
        metresPerSecond: Double = 20
    ) async throws -> RouteCaptureWriteProbe.Run {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-isolation-\(UUID().uuidString).store")
        let container = try ModelContainerFactory.makeContainer(at: url)
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        RouteCaptureWriteProbe.openTable(label: variant.label, cadence: .perRunLoopTurn)

        var context = ModelContext(container)
        var shift = Shift(startedAt: start)
        context.insert(shift)
        try context.save()
        var shiftID = shift.id

        // A shift the app started in this process is an object the context
        // created, and its `routeSamples` is a real array from the moment it
        // exists. A shift recovered after a relaunch is an object the context
        // fetched, and the same relationship is a fault until something reads
        // it. Capture cannot tell the two apart, and this is where the
        // difference is measured.
        if variant == .fetchedShift {
            context = ModelContext(container)
            let wanted = shiftID
            var descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.id == wanted })
            descriptor.fetchLimit = 1
            shift = try context.fetch(descriptor)[0]
        }

        let session = UUID()
        let startFootprint = RouteCaptureWriteProbe.footprint()
        let wallClockStart = DispatchTime.now().uptimeNanoseconds
        var buckets: [RouteCaptureWriteProbe.Bucket] = []
        var index = 0

        while index < positions {
            let upper = min(index + bucketSize, positions)
            var bucket = RouteCaptureWriteProbe.Bucket(range: index..<upper)

            for step in index..<upper {
                if step > 0, step.isMultiple(of: resetEvery) {
                    switch variant {
                    case .shipping, .fetchedShift:
                        break
                    case .freshContextPeriodically:
                        try context.save()
                        context = ModelContext(container)
                        let wanted = shiftID
                        var descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.id == wanted })
                        descriptor.fetchLimit = 1
                        shift = try context.fetch(descriptor)[0]
                    case .shortRelationships:
                        shift = Shift(startedAt: start.addingTimeInterval(Double(step)))
                        context.insert(shift)
                        try context.save()
                        shiftID = shift.id
                    }
                }

                let timestamp = start.addingTimeInterval(Double(step) + 1)
                let sample = SyntheticRoute.sample(
                    at: timestamp,
                    northMetres: Double(step + 1) * metresPerSecond
                )
                let target = shift
                let writingContext = context

                let elapsed = autoreleasepool {
                    RouteCaptureWriteProbe.time {
                        writingContext.insert(
                            RouteSample(shift: target, sample: sample, captureSessionID: session)
                        )
                        if (step + 1).isMultiple(of: 10) {
                            try? writingContext.save()
                        }
                    }
                }
                await Task.yield()

                if (step + 1).isMultiple(of: 10) {
                    bucket.flushSamples.append(elapsed)
                } else {
                    bucket.insertSamples.append(elapsed)
                }
            }

            bucket.footprint = RouteCaptureWriteProbe.footprint()
            buckets.append(bucket)
            RouteCaptureWriteProbe.emit(bucket)
            index = upper
        }

        try context.save()
        let wallClock = Double(DispatchTime.now().uptimeNanoseconds - wallClockStart) / 1e9
        let stored = try ModelContext(container).fetchCount(FetchDescriptor<RouteSample>())
        let run = RouteCaptureWriteProbe.Run(
            label: variant.label,
            buckets: buckets,
            startFootprint: startFootprint,
            wallClockSeconds: wallClock,
            storedRowCount: stored
        )
        RouteCaptureWriteProbe.closeTable(run)
        return run
    }
}
