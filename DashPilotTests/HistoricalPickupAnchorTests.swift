import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Whether a pickup's position can be read back out of what DashPilot already
/// stores.
///
/// **These are an investigation, not a specification.** Nothing they exercise
/// ships: there is no production anchor type, no schema change and no detector.
/// They exist so the finding on `investigate/historical-pickup-anchor` is
/// reproducible rather than asserted, and they are **off by default** for the
/// reason `RouteCaptureWritePerformanceTests` is off by default: a suite that
/// pins the behaviour of code the app does not run would be read, later, as a
/// contract the app has to keep.
///
/// Run them deliberately:
///
/// ```bash
/// TEST_RUNNER_DASHPILOT_ANCHOR_INVESTIGATION=1 xcodebuild test -scheme DashPilot \
///   -destination 'platform=iOS Simulator,name=iPhone 17' \
///   -parallel-testing-enabled NO \
///   -only-testing:DashPilotTests/HistoricalPickupAnchorDerivationTests \
///   -only-testing:DashPilotTests/HistoricalPickupAnchorWindowTests \
///   -only-testing:DashPilotTests/HistoricalPickupAnchorClusterTests \
///   -only-testing:DashPilotTests/HistoricalPickupAnchorProximityTests \
///   -only-testing:DashPilotTests/HistoricalPickupAnchorCostTests
/// find ~/Library/Developer/CoreSimulator/Devices -name 'dashpilot-historical-pickup-anchor.md'
/// ```
///
/// The same three details that trip up the capture profile apply here and each
/// of them fails silently: the `TEST_RUNNER_` prefix set as an **environment
/// variable of `xcodebuild`** rather than as a trailing build setting is what
/// carries the flag into the simulator; `-parallel-testing-enabled NO` keeps the
/// run off a clone that deletes its own report; and the tables land in that file
/// because a test's `print` never reaches the `xcodebuild` log.
enum HistoricalPickupAnchorInvestigation {
    /// Whether the investigation was asked for.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DASHPILOT_ANCHOR_INVESTIGATION"] == "1"
    }

    static let reportFileName = "dashpilot-historical-pickup-anchor.md"

    private static var reportURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(reportFileName)
    }

    /// Appends one line to the report, flushing as it goes so a run stopped
    /// part-way still leaves what it measured.
    static func report(_ line: String) {
        let text = ((try? String(contentsOf: reportURL, encoding: .utf8)) ?? "") + line + "\n"
        try? text.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    static func reportHeading(_ heading: String) {
        report("")
        report("## \(heading)")
        report("")
    }

    /// Metres, to the nearest metre, for a table.
    static func metresText(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    /// Milliseconds a `Duration` measured.
    ///
    /// `Duration.formatted()` renders whole seconds, which reports every figure
    /// in this investigation as `0:00:00` and hides the thing being measured.
    static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    static func millisecondsText(_ duration: Duration) -> String {
        String(format: "%.2f ms", milliseconds(duration))
    }

    static func microsecondsText(_ duration: Duration, over repetitions: Int) -> String {
        String(format: "%.2f µs", milliseconds(duration) * 1_000 / Double(repetitions))
    }
}

/// Reading the one branch of a derivation out of its result.
///
/// Test-target only. Both halves of these results are values the investigation
/// asserts on, and `if case` at every call site would bury the assertions.
extension Result {
    var derivedValue: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    var refusalValue: Failure? {
        if case .failure(let refusal) = self { return refusal }
        return nil
    }
}

// MARK: - Question 1 and 2: can an anchor be derived, and does the filter undermine it

/// Each synthetic approach, judged under each window, against where the driver
/// actually was.
@MainActor
@Suite(
    "Historical pickup anchor: derivation",
    .enabled(if: HistoricalPickupAnchorInvestigation.isEnabled)
)
struct HistoricalPickupAnchorDerivationTests {
    typealias Probe = HistoricalPickupAnchorProbe

    // MARK: The cases an anchor should exist for

    @Test("A normal drive in anchors within a few metres under every window")
    func normalDriveInAnchorsEverywhere() throws {
        let scenario = PickupApproachScenario.normalDriveIn()

        for (name, policy) in Probe.AnchorPolicy.allVariants {
            let anchor = try #require(
                PickupApproachScenario.anchor(in: scenario, under: policy).derivedValue,
                "\(name) should anchor an ordinary arrival"
            )
            #expect(scenario.error(of: anchor) < 5, "\(name) put the anchor where the driver stopped")
            #expect(anchor.lag == 10, "The last recorded movement was ten seconds before the tap")
            #expect(anchor.bracket == .proven, "Capture ran across the wait and recorded nothing")
        }
    }

    @Test("A red light before the pickup does not become the anchor")
    func redLightIsNotTheAnchor() throws {
        let scenario = PickupApproachScenario.redLightBeforePickup()

        for (name, policy) in Probe.AnchorPolicy.allVariants {
            let anchor = try #require(
                PickupApproachScenario.anchor(in: scenario, under: policy).derivedValue,
                "\(name) should still anchor"
            )
            // Moving off the light writes rows, so the light is never the newest
            // one. A stationary stretch mid-route is invisible and harmless.
            #expect(scenario.error(of: anchor) < 5, "\(name) anchored at the pickup, not 150 m back at the light")
        }
    }

    @Test("Circling a car park anchors at the space, not the entrance")
    func parkingCirculationAnchorsAtTheSpace() throws {
        let scenario = PickupApproachScenario.parkingLotCirculation()

        let anchor = try #require(PickupApproachScenario.anchor(in: scenario, under: .bracketed).derivedValue)
        #expect(scenario.error(of: anchor) < 5, "The last movement recorded was into the space")
        #expect(anchor.bracket == .proven)

        // And the entrance, 60 m out, is not what was picked.
        let entrance = PickupApproachScenario.position(
            at: scenario.arrivedAt,
            north: 0,
            east: -60,
            session: nil
        )
        #expect(Probe.metres(from: entrance, to: anchor.position) > 50)
    }

    @Test("Tapping Arrived five minutes after parking is the case only the bracket rescues")
    func lateTapNeedsTheBracket() throws {
        let scenario = PickupApproachScenario.tappedLongAfterParking()

        #expect(
            PickupApproachScenario.anchor(in: scenario, under: .tight).refusalValue == .outsideLookback,
            "A one-minute window cannot see a five-minute lag"
        )
        #expect(PickupApproachScenario.anchor(in: scenario, under: .moderate).refusalValue == .outsideLookback)

        let bracketed = try #require(PickupApproachScenario.anchor(in: scenario, under: .bracketed).derivedValue)
        #expect(bracketed.lag == 300, "Five minutes of lag")
        #expect(scenario.error(of: bracketed) < 5, "And no error at all, because none of it was movement")
        #expect(bracketed.bracket == .proven, "Which is exactly what the store can show")
    }

    // MARK: The cases no anchor should exist for

    @Test("A capture gap before the arrival is refused by the bracket and accepted by a wide window")
    func captureGapIsOnlyCaughtByTheBracket() throws {
        let scenario = PickupApproachScenario.captureGapBeforeArrival()

        #expect(PickupApproachScenario.anchor(in: scenario, under: .tight).refusalValue == .outsideLookback)
        #expect(PickupApproachScenario.anchor(in: scenario, under: .moderate).refusalValue == .outsideLookback)
        #expect(
            PickupApproachScenario.anchor(in: scenario, under: .bracketed).refusalValue == .unprovenStationarity,
            "Capture restarted in a new session, so the wait was not measured"
        )

        let wide = try #require(PickupApproachScenario.anchor(in: scenario, under: .wide).derivedValue)
        #expect(scenario.error(of: wide) > 3_000, "A ten-minute window with no bracket anchors four km away")
        #expect(wide.bracket == .broken, "It reports why it should not be trusted even as it is produced")
    }

    @Test("A pause around the arrival defeats every window except the bracket")
    func pauseAroundArrivalIsCaughtByTheBracket() throws {
        let scenario = PickupApproachScenario.pauseAndResumeNearArrival()

        #expect(PickupApproachScenario.anchor(in: scenario, under: .tight).refusalValue == .outsideLookback)
        #expect(
            PickupApproachScenario.anchor(in: scenario, under: .bracketed).refusalValue == .unprovenStationarity
        )

        let moderate = try #require(PickupApproachScenario.anchor(in: scenario, under: .moderate).derivedValue)
        #expect(
            scenario.error(of: moderate) > 800,
            "Two minutes of lookback is enough to reach back past a pause and anchor 900 m away"
        )
    }

    @Test("Poor-accuracy final fixes are rejected for their accuracy, not their age")
    func poorAccuracyIsRejectedByAccuracy() throws {
        let scenario = PickupApproachScenario.poorAccuracyFinalFixes()

        #expect(PickupApproachScenario.anchor(in: scenario, under: .tight).refusalValue == .poorAccuracy)
        #expect(PickupApproachScenario.anchor(in: scenario, under: .moderate).refusalValue == .poorAccuracy)
        #expect(PickupApproachScenario.anchor(in: scenario, under: .bracketed).refusalValue == .poorAccuracy)

        // The capture filter kept these rows because 92 m still says which road
        // a vehicle is on. It does not say which building it stopped at, and the
        // scenario places them 70 m off to show what that costs.
        let wide = try #require(PickupApproachScenario.anchor(in: scenario, under: .wide).derivedValue)
        #expect(scenario.error(of: wide) > 60)
    }

    @Test("An unrecordable final approach is caught by how far the departure is")
    func unrecordableApproachIsCaughtByDepartureDistance() throws {
        let scenario = PickupApproachScenario.unrecordableFinalApproach()

        // The worst case the session bracket alone cannot see: capture never
        // stopped, so the identifiers match on both sides of 1.5 km of driving
        // that was too imprecise to record.
        let sessionOnly = Probe.AnchorPolicy(
            lookback: 600,
            maximumHorizontalAccuracy: 50,
            requiresStationaryBracket: true,
            maximumDepartureDistance: .greatestFiniteMagnitude
        )
        let falseAnchor = try #require(PickupApproachScenario.anchor(in: scenario, under: sessionOnly).derivedValue)
        #expect(falseAnchor.bracket == .proven, "A session-only bracket calls this measured stillness")
        #expect(scenario.error(of: falseAnchor) > 1_400, "And it is 1.5 km wrong")

        // The departure is 1.5 km from the anchor, which no stationary vehicle
        // produces, so the shipped-shape policy refuses.
        #expect(
            PickupApproachScenario.anchor(in: scenario, under: .bracketed).refusalValue == .unprovenStationarity
        )
        let measured = Probe.bracket(
            after: try #require(scenario.route.last(where: { $0.timestamp <= scenario.arrivedAt })),
            in: scenario.route.filter { $0.timestamp > scenario.arrivedAt }[...],
            under: .bracketed
        )
        #expect(measured == .departed, "And it says which rule refused it")
    }

    @Test("No route capture yields no anchor under any window")
    func noRouteYieldsNoAnchor() {
        let scenario = PickupApproachScenario.noRouteCapture()

        for (name, policy) in Probe.AnchorPolicy.allVariants {
            #expect(
                PickupApproachScenario.anchor(in: scenario, under: policy).refusalValue == .noRouteBeforeArrival,
                "\(name) has nothing to read"
            )
        }
    }

    @Test("A route that begins after the arrival yields no anchor")
    func routeAfterArrivalYieldsNoAnchor() {
        let scenario = PickupApproachScenario.routeBeginsAfterArrival()

        for (name, policy) in Probe.AnchorPolicy.allVariants {
            #expect(
                PickupApproachScenario.anchor(in: scenario, under: policy).refusalValue == .noRouteBeforeArrival,
                "\(name) must not reach forwards for a position"
            )
        }
    }

    // MARK: Stacked deliveries

    @Test("Two stacked pickups read the same row and count as one visit")
    func stackedPickupsAreOneObservation() throws {
        let (scenario, secondArrival) = PickupApproachScenario.stackedPickups()
        let shiftID = UUID()

        let first = try #require(
            PickupApproachScenario.anchor(in: scenario, under: .bracketed, shiftID: shiftID).derivedValue
        )
        let second = try #require(
            PickupApproachScenario.anchor(
                in: scenario,
                at: secondArrival,
                under: .bracketed,
                shiftID: shiftID
            ).derivedValue
        )

        #expect(first.observedAt == second.observedAt, "Both taps fall inside one stationary stretch")
        #expect(Probe.metres(from: first.position, to: second.position) == 0)
        #expect(second.lag > first.lag, "The second tap is further from the last recorded movement")

        let independent = Probe.independentObservations(in: [first, second], under: .standard)
        #expect(independent.count == 1, "One stop seen twice is one observation, not two")
    }

    @Test("A pre-v3 row has unknown continuity and is refused")
    func legacyRowIsRefused() {
        let legacy = withoutCaptureSessions(PickupApproachScenario.normalDriveIn())

        #expect(
            PickupApproachScenario.anchor(in: legacy, under: .tight).refusalValue == .unknownContinuity,
            "A row written before schema v3 proves nothing about what surrounded it"
        )
    }

    /// The same route as it would have been stored before schema v3.
    private func withoutCaptureSessions(
        _ scenario: PickupApproachScenario.Scenario
    ) -> PickupApproachScenario.Scenario {
        var stripped = scenario
        stripped.route = scenario.route.map {
            var position = $0
            position.captureSessionID = nil
            return position
        }
        return stripped
    }
}

// MARK: - Question 1: what each window costs

/// The lookback windows compared against each other on the same eleven
/// scenarios, with the result written to the report.
@MainActor
@Suite(
    "Historical pickup anchor: windows",
    .enabled(if: HistoricalPickupAnchorInvestigation.isEnabled)
)
struct HistoricalPickupAnchorWindowTests {
    typealias Probe = HistoricalPickupAnchorProbe

    @Test("Every window judged on every scenario")
    func windowTradeoffs() {
        HistoricalPickupAnchorInvestigation.report("# Historical pickup anchor")
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "Investigation only. No production code, no schema change, no persisted anchor."
        )
        HistoricalPickupAnchorInvestigation.reportHeading("Windows against scenarios")
        HistoricalPickupAnchorInvestigation.report(
            "Each cell is the anchor's error in metres against where the driver actually was, "
                + "or the rule that refused it."
        )
        HistoricalPickupAnchorInvestigation.report("")

        let variants = Probe.AnchorPolicy.allVariants
        HistoricalPickupAnchorInvestigation.report(
            "| Scenario | " + variants.map(\.name).joined(separator: " | ") + " |"
        )
        HistoricalPickupAnchorInvestigation.report(
            "| --- | " + variants.map { _ in "---" }.joined(separator: " | ") + " |"
        )

        var falseAnchors: [String: Int] = [:]
        var accepted: [String: Int] = [:]

        for scenario in PickupApproachScenario.allScenarios() {
            var cells: [String] = []
            for (name, policy) in variants {
                let result = PickupApproachScenario.anchor(in: scenario, under: policy)
                switch result {
                case .success(let anchor):
                    let error = scenario.error(of: anchor)
                    accepted[name, default: 0] += 1
                    if error > 100 { falseAnchors[name, default: 0] += 1 }
                    cells.append("\(HistoricalPickupAnchorInvestigation.metresText(error)) m")
                case .failure(let refusal):
                    cells.append("_\(refusal.rawValue)_")
                }
            }
            HistoricalPickupAnchorInvestigation.report("| \(scenario.name) | " + cells.joined(separator: " | ") + " |")
        }

        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report("| Window | anchored | more than 100 m wrong |")
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- |")
        for (name, _) in variants {
            HistoricalPickupAnchorInvestigation.report(
                "| \(name) | \(accepted[name] ?? 0) | \(falseAnchors[name] ?? 0) |"
            )
        }

        // The finding the table exists to support: the bracketed window is the
        // only one that produces no anchor more than 100 m from the truth.
        #expect(falseAnchors["bracketed"] == nil, "A bracketed anchor was never badly wrong")
        #expect((falseAnchors["wide"] ?? 0) >= 3, "A wide window with no bracket is wrong on several scenarios")
        #expect((accepted["bracketed"] ?? 0) > (accepted["tight"] ?? 0), "And it refuses less than the tight one")
    }

    @Test("A lookback alone cannot be chosen safely, because the error it admits is a speed")
    func lookbackAloneIsASpeedBudget() {
        HistoricalPickupAnchorInvestigation.reportHeading("What a lookback alone admits")
        HistoricalPickupAnchorInvestigation.report("| Lookback | at 5 m/s | at 11 m/s | at 25 m/s |")
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- | --- |")
        for lookback in [30.0, 60, 120, 180, 300, 600] {
            let cells = [5.0, 11, 25].map { "\(Int((lookback * $0).rounded())) m" }
            HistoricalPickupAnchorInvestigation.report(
                "| \(Int(lookback)) s | " + cells.joined(separator: " | ") + " |"
            )
        }
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "A window short enough to bound the error at urban speed is too short for a driver who taps "
                + "Arrived after parking and walking in, which is the common case. That tension is what the "
                + "stationary bracket removes: with it, the lag stops being an error budget."
        )

        // Nothing to assert but the arithmetic the argument rests on.
        #expect(60.0 * 11 > 600, "A minute at city speed is already further than a car park is wide")
    }
}

// MARK: - Question 3: do repeated pickups agree

/// Whether several visits to one place produce something a place can be
/// described by.
@MainActor
@Suite(
    "Historical pickup anchor: clustering",
    .enabled(if: HistoricalPickupAnchorInvestigation.isEnabled)
)
struct HistoricalPickupAnchorClusterTests {
    typealias Probe = HistoricalPickupAnchorProbe

    /// Street parking outside a small restaurant: the same few metres every
    /// time.
    private let kerbside: [(north: Double, east: Double)] = [
        (0, 0), (3, -6), (-4, 5), (7, 2), (1, -9)
    ]

    /// A shared car park: the same place, but the driver stops anywhere in it.
    private let carPark: [(north: Double, east: Double)] = [
        (0, 0), (40, 25), (-35, 20), (15, -45), (-20, -30)
    ]

    @Test("Kerbside visits agree, and the representative is one of them")
    func kerbsideVisitsCluster() throws {
        let cluster = try #require(PickupApproachScenario.cluster(parkingAt: kerbside).derivedValue)

        #expect(cluster.agreeingCount == 5)
        #expect(cluster.consideredCount == 5)
        #expect(cluster.agreementRadius < 15, "Every visit is within fifteen metres of the medoid")
        #expect(cluster.spread < 20)

        // The representative is an observation, not an average of them.
        let observations = PickupApproachScenario.visits(parkingAt: kerbside)
        #expect(
            observations.contains { Probe.metres(from: $0.position, to: cluster.representative.position) == 0 },
            "The medoid is a position the driver actually stopped at"
        )
    }

    @Test("A car park still clusters, and reports how wide it is")
    func carParkClustersWithAWideRadius() throws {
        let cluster = try #require(PickupApproachScenario.cluster(parkingAt: carPark).derivedValue)

        #expect(cluster.agreeingCount == 5)
        #expect(cluster.agreementRadius > 35, "The place is as wide as the car park, and says so")
        #expect(cluster.spread > 70)

        HistoricalPickupAnchorInvestigation.reportHeading("How tightly repeated pickups cluster")
        HistoricalPickupAnchorInvestigation.report("| History | observations | agreeing | radius | spread |")
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- | --- | --- |")
        for (name, offsets) in [("Kerbside", kerbside), ("Shared car park", carPark)] {
            guard let measured = PickupApproachScenario.cluster(parkingAt: offsets).derivedValue else { continue }
            HistoricalPickupAnchorInvestigation.report(
                "| \(name) | \(measured.consideredCount) | \(measured.agreeingCount) | "
                    + "\(HistoricalPickupAnchorInvestigation.metresText(measured.agreementRadius)) m | "
                    + "\(HistoricalPickupAnchorInvestigation.metresText(measured.spread)) m |"
            )
        }
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "The radius is the finding that bounds everything downstream: a place observed through its car "
                + "park is tens of metres wide before any GPS error is added, so a proximity radius small "
                + "enough to separate neighbouring businesses is smaller than the place itself."
        )
    }

    @Test("One wild observation among five good ones is dropped, not averaged in")
    func oneWildObservationIsDropped() throws {
        var offsets = kerbside
        offsets.append((0, 1_200))

        let cluster = try #require(PickupApproachScenario.cluster(parkingAt: offsets).derivedValue)
        #expect(cluster.consideredCount == 6)
        #expect(cluster.agreeingCount == 5, "The outlier disagrees and is excluded")
        #expect(cluster.agreementRadius < 15, "And it does not widen the place by 1.2 km")
    }

    @Test("Observations that genuinely disagree get no representative at all")
    func disagreeingObservationsAreRefused() {
        // Two buildings under one name: a driver's own shorthand covering two
        // branches, or a merge they made. Four visits to one, three to the
        // other.
        let split: [(north: Double, east: Double)] = [
            (0, 0), (5, 4), (-3, 6), (2, -5),
            (0, 800), (6, 805), (-4, 796)
        ]

        #expect(
            PickupApproachScenario.cluster(parkingAt: split).refusalValue == .observationsDisagree,
            "Neither half is a majority large enough to speak for the place"
        )
    }

    @Test("Too little history is refused rather than answered weakly")
    func tooLittleHistoryIsRefused() {
        #expect(PickupApproachScenario.cluster(parkingAt: []).refusalValue == .insufficientHistory)
        #expect(PickupApproachScenario.cluster(parkingAt: [(0, 0)]).refusalValue == .insufficientHistory)
        #expect(PickupApproachScenario.cluster(parkingAt: [(0, 0), (4, 3)]).refusalValue == .insufficientHistory)
    }

    @Test("Stacked pickups in one shift cannot make a quorum on their own")
    func stackedPickupsCannotMakeAQuorum() throws {
        let shiftID = UUID()
        let base = PickupApproachScenario.visits(parkingAt: [(0, 0), (2, 3), (-1, 4)])
        let stacked = base.enumerated().map { index, anchor -> Probe.DerivedAnchor in
            var copy = anchor
            copy.shiftID = shiftID
            copy.arrivedAt = PickupApproachScenario.arrival.addingTimeInterval(Double(index) * 240)
            return copy
        }

        #expect(
            Probe.cluster(stacked, under: .standard).refusalValue == .insufficientHistory,
            "Three orders collected on one stop are one observation of that stop"
        )
    }

    @Test("The medoid does not move when the observations are given in another order")
    func medoidIsOrderIndependent() throws {
        let observations = PickupApproachScenario.visits(parkingAt: carPark)
        let forward = try #require(Probe.cluster(observations, under: .standard).derivedValue)
        let backward = try #require(Probe.cluster(observations.reversed(), under: .standard).derivedValue)

        #expect(forward.representative == backward.representative)
        #expect(forward.agreementRadius == backward.agreementRadius)
    }
}

// MARK: - Question 4: the one question a detector would ask

/// "Is this stationary position a place this driver has picked up from before?"
/// asked of derived clusters and nothing else.
@MainActor
@Suite(
    "Historical pickup anchor: proximity",
    .enabled(if: HistoricalPickupAnchorInvestigation.isEnabled)
)
struct HistoricalPickupAnchorProximityTests {
    typealias Probe = HistoricalPickupAnchorProbe

    private let placeA = UUID()
    private let placeB = UUID()

    private func cluster(around east: Double, north: Double = 0) -> Probe.AnchorCluster {
        let offsets = [(north, east), (north + 3, east - 6), (north - 4, east + 5), (north + 7, east + 2)]
        guard let cluster = PickupApproachScenario.cluster(parkingAt: offsets).derivedValue else {
            preconditionFailure("A four-visit kerbside history must cluster")
        }
        return cluster
    }

    private func current(north: Double, east: Double, accuracy: Double = 12) -> Probe.CapturedPosition {
        PickupApproachScenario.position(
            at: PickupApproachScenario.arrival,
            north: north,
            east: east,
            accuracy: accuracy,
            session: UUID()
        )
    }

    @Test("A genuine repeat pickup matches")
    func genuineRepeatMatches() {
        let clusters = [placeA: cluster(around: 0), placeB: cluster(around: 900)]
        let answer = Probe.place(at: current(north: 6, east: 4), among: clusters, under: .standard)

        guard case .match(let placeID, let metres) = answer else {
            Issue.record("Expected a match, got \(answer)")
            return
        }
        #expect(placeID == placeA)
        #expect(metres < 60)
    }

    @Test("Waiting for an offer somewhere else matches nothing")
    func waitingElsewhereDoesNotMatch() {
        let clusters = [placeA: cluster(around: 0), placeB: cluster(around: 900)]

        #expect(Probe.place(at: current(north: 0, east: 420), among: clusters, under: .standard) == .noMatch)
    }

    @Test("Two nearby businesses are refused rather than guessed between")
    func twoNearbyBusinessesAreAmbiguous() {
        let clusters = [placeA: cluster(around: 0), placeB: cluster(around: 55)]
        let answer = Probe.place(at: current(north: 0, east: 22), among: clusters, under: .standard)

        guard case .ambiguous(let placeIDs) = answer else {
            Issue.record("Expected ambiguity, got \(answer)")
            return
        }
        #expect(Set(placeIDs) == Set([placeA, placeB]))
    }

    @Test("Two units of one shopping plaza are refused")
    func sharedPlazaIsAmbiguous() {
        // Both places are observed through the same car park, so their
        // representatives are metres apart and no radius separates them.
        let clusters = [placeA: cluster(around: 0), placeB: cluster(around: 18, north: 10)]
        let answer = Probe.place(at: current(north: 4, east: 8), among: clusters, under: .standard)

        guard case .ambiguous = answer else {
            Issue.record("Expected ambiguity, got \(answer)")
            return
        }
    }

    @Test("A place just outside the radius still withholds the answer")
    func aCloseRunnerUpOutsideTheRadiusStillWithholds() {
        let clusters = [placeA: cluster(around: 45), placeB: cluster(around: -75)]
        let answer = Probe.place(at: current(north: 0, east: 0), among: clusters, under: .standard)

        guard case .ambiguous = answer else {
            Issue.record("The radius is not a wall the driver parked against; expected ambiguity, got \(answer)")
            return
        }
    }

    @Test("A noisy fix is not asked the question")
    func noisyFixIsRefused() {
        let clusters = [placeA: cluster(around: 0)]

        #expect(
            Probe.place(at: current(north: 6, east: 4, accuracy: 45), among: clusters, under: .standard)
                == .positionTooImprecise
        )
    }

    @Test("No usable history answers with no history, not with no match")
    func noHistoryIsItsOwnAnswer() {
        #expect(Probe.place(at: current(north: 0, east: 0), among: [:], under: .standard) == .insufficientHistory)
    }

    @Test("A place whose history conflicts never reaches the question")
    func conflictingHistoryNeverReachesTheQuestion() {
        let split: [(north: Double, east: Double)] = [
            (0, 0), (5, 4), (-3, 6), (2, -5), (0, 800), (6, 805), (-4, 796)
        ]
        var clusters: [UUID: Probe.AnchorCluster] = [:]
        if let cluster = PickupApproachScenario.cluster(parkingAt: split).derivedValue {
            clusters[placeA] = cluster
        }

        #expect(clusters.isEmpty, "Clustering refused it, so nothing describes the place")
        #expect(Probe.place(at: current(north: 0, east: 0), among: clusters, under: .standard) == .insufficientHistory)
    }

    private func answerText(_ answer: Probe.ProximityAnswer) -> String {
        switch answer {
        case .match: "match"
        case .noMatch: "no match"
        case .ambiguous: "ambiguous"
        case .insufficientHistory: "no history"
        case .positionTooImprecise: "imprecise"
        }
    }

    @Test("How the radius trades recall inside a car park against a neighbouring business")
    func radiusTradeoff() {
        HistoricalPickupAnchorInvestigation.reportHeading("What the proximity radius buys and costs")
        HistoricalPickupAnchorInvestigation.report(
            "One place, and the driver standing that far from its representative. The distances are the "
                + "ones a car park produces: the `Shared car park` history above has a 47 m radius, so a "
                + "driver legitimately at that place is routinely tens of metres from its medoid."
        )
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report("| Radius | driver at 5 m | at 30 m | at 60 m | at 100 m |")
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- | --- | --- |")
        for radius in [30.0, 45, 60, 90] {
            let policy = Probe.ProximityPolicy(matchRadius: radius)
            let clusters = [placeA: cluster(around: 0)]
            let cells = [5.0, 30, 60, 100].map { offset in
                answerText(Probe.place(at: current(north: 0, east: offset), among: clusters, under: policy))
            }
            HistoricalPickupAnchorInvestigation.report(
                "| \(Int(radius)) m | " + cells.joined(separator: " | ") + " |"
            )
        }

        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "And the same radii with a second place `separation` metres away, the driver standing at the "
                + "first."
        )
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "| Radius | neighbour at 25 m | at 50 m | at 90 m | at 400 m |"
        )
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- | --- | --- |")
        for radius in [30.0, 45, 60, 90] {
            let policy = Probe.ProximityPolicy(matchRadius: radius)
            let cells = [25.0, 50, 90, 400].map { separation -> String in
                let clusters = [placeA: cluster(around: 0), placeB: cluster(around: separation)]
                return answerText(Probe.place(at: current(north: 2, east: 1), among: clusters, under: policy))
            }
            HistoricalPickupAnchorInvestigation.report(
                "| \(Int(radius)) m | " + cells.joined(separator: " | ") + " |"
            )
        }
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "The radius alone does not separate the two problems: one wide enough to recognise a driver "
                + "sixty metres into a car park also reaches a business fifty metres away. What separates "
                + "them is *where the driver is standing*, which the ambiguity margin reads. Standing on "
                + "one place's own observations it names that place; standing between two it refuses. "
                + "Both are the intended answer, and the second is the common one in a retail strip."
        )

        // The finding, asserted rather than only tabulated.
        let wide = Probe.ProximityPolicy(matchRadius: 90)
        let onlyPlace = [placeA: cluster(around: 0)]
        #expect(
            answerText(Probe.place(at: current(north: 0, east: 60), among: onlyPlace, under: wide)) == "match",
            "A radius sized for a car park recognises a driver parked across it"
        )

        let withNeighbour = [placeA: cluster(around: 0), placeB: cluster(around: 50)]
        #expect(
            answerText(Probe.place(at: current(north: 2, east: 1), among: withNeighbour, under: wide)) == "match",
            "Standing on one place's own observations still names it, even with a neighbour fifty metres off"
        )
        #expect(
            answerText(Probe.place(at: current(north: 0, east: 28), among: withNeighbour, under: wide))
                == "ambiguous",
            "But parked between the two, which is what a shared car park means, it refuses"
        )
    }
}

// MARK: - Question 6: what deriving anchors costs

/// Deriving a place's anchors out of a store that holds a realistic amount of
/// route, with timestamp-bounded fetches rather than a scan.
@MainActor
@Suite(
    "Historical pickup anchor: cost",
    .serialized,
    .enabled(if: HistoricalPickupAnchorInvestigation.isEnabled)
)
struct HistoricalPickupAnchorCostTests {
    typealias Probe = HistoricalPickupAnchorProbe

    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// Shifts in the store, and how much route each holds.
    ///
    /// A row every three seconds for two hours is 2,400 rows a shift, which is
    /// the density a shift with the app in the foreground actually produces. At
    /// twenty shifts the store holds 48,000 positions, which is a few weeks of
    /// part-time work.
    private let shiftCount = 20
    private let rowsPerShift = 2_400
    private let rowInterval: TimeInterval = 3

    /// How many of those shifts include a delivery from the place under test.
    private let visitCount = 12

    private struct Store {
        var url: URL
        var context: ModelContext
        var place: PickupPlace
        var cleanUp: () -> Void
    }

    private func makeStore() throws -> Store {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotAnchorCost-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "DashPilot.store")
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))

        let place = PickupPlace(name: try PickupPlaceName("Example Diner"), createdAt: start)
        context.insert(place)

        for index in 0..<shiftCount {
            let shiftStart = start.addingTimeInterval(Double(index) * 86_400)
            let shift = Shift(startedAt: shiftStart)
            context.insert(shift)
            let session = UUID()

            for row in 0..<rowsPerShift {
                let timestamp = shiftStart.addingTimeInterval(Double(row) * rowInterval)
                context.insert(
                    RouteSample(
                        shift: shift,
                        timestamp: timestamp,
                        latitude: PickupApproachScenario.originLatitude
                            + Double(row) * 30 / PickupApproachScenario.metresPerDegreeLatitude,
                        longitude: PickupApproachScenario.originLongitude,
                        horizontalAccuracy: 8,
                        captureSessionID: session
                    )
                )
                if row % 500 == 0 { try context.save() }
            }

            if index < visitCount {
                // The arrival lands on a row boundary partway through the shift,
                // so the derivation has something to find and something to skip
                // past.
                let arrival = shiftStart.addingTimeInterval(Double(rowsPerShift / 2) * rowInterval + 7)
                let delivery = Delivery(shift: shift, acceptedAt: arrival.addingTimeInterval(-600))
                context.insert(delivery)
                try delivery.markArrivedAtPickup(at: arrival)
                try delivery.markPickedUp(at: arrival.addingTimeInterval(660))
                try delivery.markDelivered(at: arrival.addingTimeInterval(1_500))
                delivery.setPickupPlace(place)
            }
            try context.save()
        }
        try context.save()

        return Store(
            url: url,
            context: context,
            place: place,
            cleanUp: {
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
                }
                try? FileManager.default.removeItem(at: directory)
            }
        )
    }

    @Test("Bounded fetches against a scan of the same history")
    func boundedDerivationAgainstAScan() throws {
        let store = try makeStore()
        defer { store.cleanUp() }

        let totalRows = try store.context.fetchCount(FetchDescriptor<RouteSample>())
        #expect(totalRows == shiftCount * rowsPerShift, "The store holds what the measurement claims")

        // Bounded: at most two limited fetches a delivery.
        var cost = Probe.DerivationCost()
        let boundedStart = ContinuousClock.now
        let anchors = Probe.anchors(for: store.place, in: store.context, under: .bracketed, cost: &cost)
        let boundedElapsed = ContinuousClock.now - boundedStart

        #expect(anchors.count == visitCount, "Every visit anchored")
        #expect(cost.routeFetchCount <= 2 * visitCount, "Two fetches a delivery and no more")
        #expect(cost.fetchedRowCount <= 2 * visitCount, "Each of them limited to one row")

        // Naive: read each visited shift's whole route the way every other
        // reader in the app does, and walk it.
        let naiveStart = ContinuousClock.now
        var naiveRows = 0
        var naiveAnchors = 0
        for delivery in store.place.deliveries {
            guard let arrivedAt = delivery.arrivedAtPickupAt,
                  let shift = delivery.shift
            else { continue }
            let route = shift.routeSamples().map(Probe.CapturedPosition.init)
            naiveRows += route.count
            let result = Probe.anchor(
                forArrivalAt: arrivedAt,
                deliveryID: delivery.id,
                shiftID: shift.id,
                in: route,
                under: .bracketed
            )
            if result.derivedValue != nil { naiveAnchors += 1 }
        }
        let naiveElapsed = ContinuousClock.now - naiveStart

        #expect(naiveAnchors == anchors.count, "The bounded read finds exactly what the whole-route read finds")

        HistoricalPickupAnchorInvestigation.reportHeading("What deriving a place's anchors costs")
        HistoricalPickupAnchorInvestigation.report(
            "Store: \(shiftCount) shifts, \(totalRows) route rows, \(visitCount) visits to one place."
        )
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report("| Strategy | fetches | rows read | elapsed |")
        HistoricalPickupAnchorInvestigation.report("| --- | --- | --- | --- |")
        HistoricalPickupAnchorInvestigation.report(
            "| Timestamp-bounded, limit 1 | \(cost.routeFetchCount) | \(cost.fetchedRowCount) | "
                + "\(HistoricalPickupAnchorInvestigation.millisecondsText(boundedElapsed)) |"
        )
        HistoricalPickupAnchorInvestigation.report(
            "| Whole route per visited shift | \(visitCount) | \(naiveRows) | "
                + "\(HistoricalPickupAnchorInvestigation.millisecondsText(naiveElapsed)) |"
        )
        HistoricalPickupAnchorInvestigation.report(
            "| Whole store | 1 | \(totalRows) | not attempted per fix |"
        )
    }

    @Test("The derivation is never repeated per location fix")
    func derivationIsNotPerFix() throws {
        let store = try makeStore()
        defer { store.cleanUp() }

        // A detector would ask the proximity question on every accepted fix, so
        // the derivation has to sit outside that loop. Measured here as the two
        // separable costs: deriving once, then answering many times from what was
        // derived.
        var cost = Probe.DerivationCost()
        let deriveStart = ContinuousClock.now
        let anchors = Probe.anchors(for: store.place, in: store.context, under: .bracketed, cost: &cost)
        let cluster = try #require(Probe.cluster(anchors, under: .standard).derivedValue)
        let deriveElapsed = ContinuousClock.now - deriveStart

        let placeID = store.place.id
        let clusters = [placeID: cluster]
        let question = PickupApproachScenario.position(
            at: start,
            north: 0,
            east: 0,
            accuracy: 10,
            session: UUID()
        )

        let askStart = ContinuousClock.now
        let repetitions = 10_000
        for _ in 0..<repetitions {
            _ = Probe.place(at: question, among: clusters, under: .standard)
        }
        let askElapsed = ContinuousClock.now - askStart

        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "Deriving one place once, anchors and cluster together: "
                + "\(HistoricalPickupAnchorInvestigation.millisecondsText(deriveElapsed)). "
                + "Answering the proximity question: "
                + "\(HistoricalPickupAnchorInvestigation.microsecondsText(askElapsed, over: repetitions)) a call, "
                + "over \(repetitions) calls."
        )
        HistoricalPickupAnchorInvestigation.report("")
        HistoricalPickupAnchorInvestigation.report(
            "The second figure is what a location fix would pay. The first is what opening a shift would "
                + "pay, once, and it touches no row outside the windows the arrivals define."
        )

        #expect(!clusters.isEmpty)
    }
}
