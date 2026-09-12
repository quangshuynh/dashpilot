import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Measures what recording a long shift's route costs.
///
/// These are measurements, not assertions about behaviour, so they are **off by
/// default**: they take minutes, their numbers depend on the machine, and a
/// number is not something to fail a build over. Run them deliberately:
///
/// ```bash
/// TEST_RUNNER_DASHPILOT_CAPTURE_PROFILE=1 xcodebuild test -scheme DashPilot \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -parallel-testing-enabled NO \
///   -only-testing:DashPilotTests/RouteCaptureWritePerformanceTests
/// find ~/Library/Developer/CoreSimulator/Devices -name 'dashpilot-capture-write-profile.md'
/// ```
///
/// Three details of that invocation are load-bearing, and each of them fails
/// silently:
///
/// - The `TEST_RUNNER_` prefix, **set as an environment variable of
///   `xcodebuild` rather than as a trailing build setting**, is what carries
///   the flag into the process inside the simulator. Without it every function
///   here is skipped and the run reports success having measured nothing.
/// - `-parallel-testing-enabled NO` keeps the run on the simulator itself. A
///   parallel run uses a clone, and the clone and the report it wrote are
///   deleted when it finishes.
/// - The numbers are in that file, not in the log: a test's `print` does not
///   reach `xcodebuild`'s output. Every bucket is flushed to it as it closes,
///   so a run that is stopped part-way still leaves the curve it measured.
///
/// The few checks these do make are the ones that would invalidate the numbers:
/// that every position was accepted and stored, so a run that quietly rejected
/// half its route cannot be read as a fast one.
@MainActor
@Suite(
    "Route capture write performance",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["DASHPILOT_CAPTURE_PROFILE"] == "1")
)
struct RouteCaptureWritePerformanceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// One accepted position a second, so a shift's length in positions is its
    /// length in seconds.
    private let shortShift = 1_800      // 30 minutes
    private let mediumShift = 7_200     // 2 hours
    private let longShift = 28_800      // 8 hours

    // MARK: The shipping path

    /// The headline measurement: how the cost of writing one position moves as
    /// the shift it belongs to gets longer.
    @Test("How write cost moves across an eight-hour shift")
    func costAcrossALongShift() async throws {
        let harness = try RouteCaptureWriteProbe.Harness(inMemory: false, start: start)
        defer { harness.tearDown() }

        let run = await RouteCaptureWriteProbe.capture(
            longShift,
            into: harness,
            from: start,
            label: "Eight-hour shift, on-disk store, the shipping write path",
            cadence: .perRunLoopTurn
        )

        #expect(run.storedRowCount == longShift, "Every position must have been accepted and stored")
    }

    /// Short, medium and long shifts each recorded into their own store through
    /// their own context, which is what a driver's three different days
    /// actually are.
    @Test("Short, medium and long shifts, each recorded from scratch")
    func shiftLengthComparison() async throws {
        for (name, positions) in [
            ("Thirty-minute shift", shortShift),
            ("Two-hour shift", mediumShift),
            ("Eight-hour shift", longShift)
        ] {
            let harness = try RouteCaptureWriteProbe.Harness(inMemory: false, start: start)
            defer { harness.tearDown() }

            let run = await RouteCaptureWriteProbe.capture(
                positions,
                into: harness,
                from: start,
                label: "\(name), on-disk store, recorded from an empty store",
                cadence: .perRunLoopTurn
            )
            #expect(run.storedRowCount == positions)
        }
    }

    // MARK: What the measurement is not explained by

    /// A tight loop against the same route length, to show whether the cost
    /// belongs to the burst the earlier seeding used or to the route.
    @Test("A burst and a run-loop turn cost the same at the same route length")
    func burstAgainstRunLoopTurn() async throws {
        for cadence in [RouteCaptureWriteProbe.Cadence.burst, .perRunLoopTurn] {
            let harness = try RouteCaptureWriteProbe.Harness(inMemory: false, start: start)
            defer { harness.tearDown() }

            let run = await RouteCaptureWriteProbe.capture(
                mediumShift,
                into: harness,
                from: start,
                label: "Two-hour shift, on-disk store, delivered as a \(cadence.description)",
                cadence: cadence
            )
            #expect(run.storedRowCount == mediumShift)
        }
    }

    /// The same route into an in-memory store, which is what the earlier
    /// benchmark used and what every other test here uses.
    @Test("The same route into an in-memory store")
    func inMemoryStore() async throws {
        let harness = try RouteCaptureWriteProbe.Harness(inMemory: true, start: start)
        defer { harness.tearDown() }

        let run = await RouteCaptureWriteProbe.capture(
            mediumShift,
            into: harness,
            from: start,
            label: "Two-hour shift, in-memory store, the shipping write path",
            cadence: .perRunLoopTurn
        )
        #expect(run.storedRowCount == mediumShift)
    }

    // MARK: Narrowing the cause

    /// Each variant differs from the shipping write in exactly one way; see
    /// ``RouteCaptureWriteIsolation``.
    @Test("Where a growing write cost comes from")
    func isolatesTheCause() async throws {
        for variant in RouteCaptureWriteIsolation.Variant.allCases {
            let run = try await RouteCaptureWriteIsolation.run(
                variant,
                positions: mediumShift,
                start: start
            )
            #expect(run.storedRowCount == mediumShift)
        }
    }

    /// What deleting a long route costs, now that no cascade carries it away.
    ///
    /// The other half of the acceptance measurement. Recording got cheaper by
    /// removing the collection; this is the check that the cost did not simply
    /// move to the one operation that used to walk it.
    @Test("What deleting an eight-hour route costs")
    func deletingALongRoute() async throws {
        let harness = try RouteCaptureWriteProbe.Harness(inMemory: false, start: start)
        defer { harness.tearDown() }

        let run = await RouteCaptureWriteProbe.capture(
            longShift,
            into: harness,
            from: start,
            label: "Eight-hour shift, recorded before deleting it",
            cadence: .perRunLoopTurn,
            bucketSize: 7_200
        )
        #expect(run.storedRowCount == longShift)

        harness.tracking.prepareForShiftEnd()
        try harness.shift.end(at: start.addingTimeInterval(Double(longShift) + 1))
        try harness.context.save()

        let deletion = RouteCaptureWriteProbe.time {
            try? ShiftService(context: harness.context).deleteCompletedShift(harness.shift)
        }
        let remaining = try harness.context.fetchCount(FetchDescriptor<RouteSample>())

        RouteCaptureWriteProbe.say("")
        RouteCaptureWriteProbe.say(
            "Deleting the \(longShift)-position shift took "
            + "**\(RouteCaptureWriteProbe.format(deletion * 1000, 0)) ms** on the main actor "
            + "and left **\(remaining)** coordinate-bearing rows."
        )

        #expect(remaining == 0)
    }

    /// What the cheapest stored shape actually is, measured on test-only
    /// models before anything is proposed for the app's own schema. See
    /// ``RouteCaptureWriteShapes``.
    @Test("What each candidate stored shape costs")
    func candidateShapes() async throws {
        for shape in RouteCaptureWriteShapes.Shape.allCases {
            let run = try await RouteCaptureWriteShapes.run(
                shape,
                positions: mediumShift,
                start: start
            )
            #expect(run.storedRowCount == mediumShift)
        }
    }

    // MARK: The one thing compression could hide

    /// Nothing on the write path reads the wall clock: the staleness rule is
    /// judged against the injected clock, and neither SwiftData nor SQLite
    /// cares how long ago the last write was. The compressed runs above should
    /// therefore describe a real shift exactly.
    ///
    /// This is the check on that claim, isolated from every other measurement
    /// and kept to two minutes: sixty positions a real second apart, near the
    /// start of a shift and again two hours in, against what the compressed run
    /// reports at the same depth.
    @Test("A position at a genuine one per second costs what the compressed run says")
    func realCadenceSpotCheck() async throws {
        let harness = try RouteCaptureWriteProbe.Harness(inMemory: false, start: start)
        defer { harness.tearDown() }

        let shallow = await RouteCaptureWriteProbe.capture(
            600,
            into: harness,
            from: start,
            label: "Warm-up to 600 positions",
            cadence: .perRunLoopTurn,
            bucketSize: 600
        )
        let shallowReal = await RouteCaptureWriteProbe.captureAtRealCadence(
            60,
            into: harness,
            from: start,
            offsetSeconds: 600
        )

        let deepening = await RouteCaptureWriteProbe.capture(
            6_540,
            into: harness,
            from: start,
            offset: 660,
            label: "Deepening to 7,200 positions",
            cadence: .perRunLoopTurn,
            bucketSize: 6_540
        )
        let deepReal = await RouteCaptureWriteProbe.captureAtRealCadence(
            60,
            into: harness,
            from: start,
            offsetSeconds: 7_200
        )

        RouteCaptureWriteProbe.say("")
        RouteCaptureWriteProbe.say("### One position per real second, against the compressed run at the same depth")
        RouteCaptureWriteProbe.say("")
        RouteCaptureWriteProbe.say(
            "| depth | compressed insert (µs) | real-cadence insert (µs) "
            + "| compressed save (ms) | real-cadence save (ms) |"
        )
        RouteCaptureWriteProbe.say("| --- | --- | --- | --- | --- |")
        for (depth, compressed, real) in [
            ("600", shallow.buckets[0], shallowReal),
            ("7,200", deepening.buckets[0], deepReal)
        ] {
            RouteCaptureWriteProbe.say(
                "| \(depth) "
                + "| \(RouteCaptureWriteProbe.format(compressed.insertMeanMicroseconds, 1)) "
                + "| \(RouteCaptureWriteProbe.format(real.insertMeanMicroseconds, 1)) "
                + "| \(RouteCaptureWriteProbe.format(compressed.flushMeanMilliseconds, 3)) "
                + "| \(RouteCaptureWriteProbe.format(real.flushMeanMilliseconds, 3)) |"
            )
        }

        #expect(harness.shift.routeSamples().count == 7_260)
    }
}
