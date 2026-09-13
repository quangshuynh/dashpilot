import Foundation
@testable import DashPilot

/// Synthetic approaches to a pickup, built so the anchor derivation can be
/// judged against a route whose truth is known.
///
/// Every position is an explicit offset in metres from one round origin, which
/// is the same rule `SyntheticRoute` follows and for the same reason: no real
/// route, address or location history appears in this repository. The origin is
/// a point in open farmland chosen for arithmetic. The "restaurant" is the
/// origin itself, and the driver's true stopping position is stated by each
/// scenario so a derived anchor can be measured against it.
///
/// Each scenario is a whole shift's route around one arrival, at the density the
/// capture pipeline actually produces: a row only where the vehicle moved at
/// least `RouteSampleFilter.minimumDistance` since the last row, and **nothing
/// at all** while it is standing still.
@MainActor
enum PickupApproachScenario {
    static let originLatitude = SyntheticRoute.originLatitude
    static let originLongitude = SyntheticRoute.originLongitude
    static let metresPerDegreeLatitude = SyntheticRoute.metresPerDegreeLatitude

    /// Metres per degree of longitude at the origin's latitude.
    ///
    /// A degree of longitude is a different distance at every latitude, which is
    /// why `GeographicDistance` is spherical and why offsets east cannot reuse
    /// the latitude constant.
    static let metresPerDegreeLongitude = metresPerDegreeLatitude * cos(originLatitude * .pi / 180)

    typealias Position = HistoricalPickupAnchorProbe.CapturedPosition

    /// A position `north` metres north and `east` metres east of the origin.
    static func position(
        at timestamp: Date,
        north: Double = 0,
        east: Double = 0,
        accuracy: Double = 8,
        session: UUID?
    ) -> Position {
        Position(
            timestamp: timestamp,
            latitude: originLatitude + north / metresPerDegreeLatitude,
            longitude: originLongitude + east / metresPerDegreeLongitude,
            horizontalAccuracy: accuracy,
            captureSessionID: session
        )
    }

    /// A straight approach from `fromEast` to `toEast` metres east of the
    /// origin, arriving at `arrivingAt`, one row every `interval` seconds at
    /// `speed` metres a second.
    ///
    /// Rows are spaced by distance the way capture spaces them, so a slow
    /// approach produces fewer rows rather than closer ones.
    static func approach(
        arrivingAt: Date,
        fromEast: Double,
        toEast: Double = 0,
        north: Double = 0,
        speed: Double = 11,
        interval: TimeInterval = 4,
        accuracy: Double = 8,
        session: UUID
    ) -> [Position] {
        let span = abs(toEast - fromEast)
        let direction: Double = toEast >= fromEast ? 1 : -1
        let step = speed * interval
        guard step > 0, span > 0 else { return [] }

        // Index counts backwards from the arrival: index 0 is the newest row and
        // sits at `toEast`, and each earlier one is one step further back along
        // the road.
        let count = Int((span / step).rounded(.down))
        return (0...count).map { index in
            let travelled = Double(index) * step
            return position(
                at: arrivingAt.addingTimeInterval(-Double(index) * interval),
                north: north,
                east: toEast - direction * travelled,
                accuracy: accuracy,
                session: session
            )
        }
        .sorted(by: Position.recordedBefore)
    }

    /// One scenario: a route, the moment the driver tapped Arrived, and where
    /// they actually were when they tapped it.
    @MainActor
    struct Scenario {
        var name: String
        var route: [Position]
        var arrivedAt: Date
        /// Where the driver truly was at ``arrivedAt``, as metres north and east
        /// of the origin. What a derived anchor is scored against.
        var trueNorth: Double
        var trueEast: Double
        /// What the scenario is, in one line, for the report.
        var note: String

        var truePosition: Position {
            PickupApproachScenario.position(at: arrivedAt, north: trueNorth, east: trueEast, session: nil)
        }

        /// Metres between a derived anchor and where the driver actually was.
        func error(of anchor: HistoricalPickupAnchorProbe.DerivedAnchor) -> Double {
            HistoricalPickupAnchorProbe.metres(from: truePosition, to: anchor.position)
        }
    }

    // MARK: The arrival every scenario is built around

    static let shiftStart = Date(timeIntervalSince1970: 1_756_000_000)
    static let arrival = shiftStart.addingTimeInterval(1_800)

    private static func at(_ seconds: TimeInterval) -> Date { arrival.addingTimeInterval(seconds) }

    // MARK: The scenarios

    /// Drive in, park, tap Arrived, wait, drive off. The case the hypothesis was
    /// written about.
    static func normalDriveIn() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-10), fromEast: -700, session: session)
        route.append(position(at: at(900), north: 0, east: 35, session: session))
        return Scenario(
            name: "Normal drive in, then a stationary wait",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Last row ten seconds before the tap, then eleven minutes of nothing, then the departure"
        )
    }

    /// A red light 150 m short of the pickup. The vehicle is stationary there,
    /// so it writes nothing, and then it moves again, which does.
    static func redLightBeforePickup() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-70), fromEast: -700, toEast: -150, session: session)
        // Fifty seconds at the light: no rows at all.
        route += approach(arrivingAt: at(-8), fromEast: -150, toEast: 0, speed: 8, interval: 3, session: session)
        route.append(position(at: at(880), north: 0, east: 35, session: session))
        return Scenario(
            name: "A red light before the pickup",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Stationary at a light 150 m out, then moving again, which writes rows past it"
        )
    }

    /// Into the car park, round it looking for a space, then parked.
    static func parkingLotCirculation() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-64), fromEast: -700, toEast: -60, session: session)
        let circuit: [(north: Double, east: Double, offset: TimeInterval)] = [
            (12, -44, -52), (28, -22, -42), (34, 4, -33), (22, 20, -25), (8, 16, -18), (5, 9, -12)
        ]
        route += circuit.map { position(at: at($0.offset), north: $0.north, east: $0.east, session: session) }
        route.append(position(at: at(760), north: 18, east: -30, session: session))
        return Scenario(
            name: "Circling a car park before tapping Arrived",
            route: route,
            arrivedAt: arrival,
            trueNorth: 5,
            trueEast: 9,
            note: "The anchor is the parking space, and across visits the spread is the size of the car park"
        )
    }

    /// Parked, walked in, queued, and only then tapped Arrived.
    static func tappedLongAfterParking() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-300), fromEast: -700, session: session)
        route.append(position(at: at(600), north: 0, east: 28, session: session))
        return Scenario(
            name: "Arrived tapped five minutes after parking",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "A five-minute lag with no movement in it: the anchor is right and only the bracket knows that"
        )
    }

    /// The process was replaced, or permission lapsed, several minutes before the
    /// arrival. Capture restarts afterwards in a new session.
    static func captureGapBeforeArrival() -> Scenario {
        let before = UUID()
        let after = UUID()
        var route = approach(arrivingAt: at(-400), fromEast: -5_000, toEast: -4_000, session: before)
        route.append(position(at: at(200), north: 0, east: 30, session: after))
        return Scenario(
            name: "A capture gap before the arrival",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "The newest row is 400 s old and four kilometres away; capture restarted in a new session"
        )
    }

    /// The driver paused the shift two minutes out, took a break, and resumed
    /// after arriving.
    static func pauseAndResumeNearArrival() -> Scenario {
        let before = UUID()
        let after = UUID()
        var route = approach(arrivingAt: at(-120), fromEast: -1_600, toEast: -900, session: before)
        route.append(position(at: at(65), north: 0, east: 22, session: after))
        return Scenario(
            name: "A pause and resume around the arrival",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "The newest row is 900 m away in the session the pause closed"
        )
    }

    /// The final approach is recorded, but with fixes barely good enough for the
    /// capture filter and nowhere near good enough to name a building.
    static func poorAccuracyFinalFixes() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-260), fromEast: -1_400, toEast: -700, session: session)
        // Displaced north by the sort of error a 92 m radius actually carries,
        // rather than being exact and merely *labelled* imprecise. A synthetic
        // position that is perfect cannot score an accuracy rule.
        route += approach(
            arrivingAt: at(-18),
            fromEast: -700,
            toEast: -12,
            north: 70,
            speed: 9,
            interval: 5,
            accuracy: 92,
            session: session
        )
        route.append(position(at: at(700), north: 0, east: 30, accuracy: 12, session: session))
        return Scenario(
            name: "Poor-accuracy final fixes",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Rows right up to the tap, each carrying a 92 m radius and sitting 70 m off"
        )
    }

    /// Worse than the last one: accuracy is so poor through the final approach
    /// and the whole wait that the capture filter keeps nothing, and capture
    /// never stops, so the session identifiers say the wait was measured.
    ///
    /// The one case where a session-only bracket asserts stillness that did not
    /// happen. It is here because it is the investigation's own worst case.
    static func unrecordableFinalApproach() -> Scenario {
        let session = UUID()
        var route = approach(arrivingAt: at(-540), fromEast: -2_400, toEast: -1_500, session: session)
        // Nothing between: every fix reported more than 100 m and was rejected.
        route.append(position(at: at(840), north: 0, east: 25, session: session))
        return Scenario(
            name: "An unrecordable final approach",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "1.5 km of driving and a whole wait inside one capture session, with nothing written"
        )
    }

    /// The shift recorded no route at all.
    static func noRouteCapture() -> Scenario {
        Scenario(
            name: "No route capture",
            route: [],
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Permission refused, or the app never reached the foreground"
        )
    }

    /// The shift was started by voice and the app only reached the foreground
    /// after the pickup, so the route begins later than the arrival.
    static func routeBeginsAfterArrival() -> Scenario {
        let session = UUID()
        let route = approach(arrivingAt: at(600), fromEast: 0, toEast: 900, session: session)
        return Scenario(
            name: "A route that begins after the arrival",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Every row is later than the tap"
        )
    }

    /// Two orders collected on one stop, tapped four minutes apart.
    ///
    /// Returns the shared route and both arrivals, because the point of the case
    /// is that they are one visit and not two.
    static func stackedPickups() -> (scenario: Scenario, secondArrival: Date) {
        let session = UUID()
        var route = approach(arrivingAt: at(-14), fromEast: -700, session: session)
        route.append(position(at: at(820), north: 0, east: 30, session: session))
        let scenario = Scenario(
            name: "Two stacked pickups on one stop",
            route: route,
            arrivedAt: arrival,
            trueNorth: 0,
            trueEast: 0,
            note: "Both taps fall inside one stationary stretch, so both read the same row"
        )
        return (scenario, at(240))
    }

    /// Every single-arrival scenario, in report order.
    static func allScenarios() -> [Scenario] {
        [
            normalDriveIn(),
            redLightBeforePickup(),
            parkingLotCirculation(),
            tappedLongAfterParking(),
            captureGapBeforeArrival(),
            pauseAndResumeNearArrival(),
            poorAccuracyFinalFixes(),
            unrecordableFinalApproach(),
            noRouteCapture(),
            routeBeginsAfterArrival(),
            stackedPickups().scenario
        ]
    }

    /// Derives a scenario's anchor under one policy, with synthetic identities.
    static func anchor(
        in scenario: Scenario,
        at arrivedAt: Date? = nil,
        under policy: HistoricalPickupAnchorProbe.AnchorPolicy,
        shiftID: UUID = UUID(),
        deliveryID: UUID = UUID()
    ) -> Result<HistoricalPickupAnchorProbe.DerivedAnchor, HistoricalPickupAnchorProbe.AnchorRefusal> {
        HistoricalPickupAnchorProbe.anchor(
            forArrivalAt: arrivedAt ?? scenario.arrivedAt,
            deliveryID: deliveryID,
            shiftID: shiftID,
            in: scenario.route,
            under: policy
        )
    }
}

// MARK: - Repeated visits to one place

extension PickupApproachScenario {
    /// A set of visits to one pickup place, each a normal drive in that parked
    /// at a stated offset.
    ///
    /// The offsets are the whole point: they are where the driver actually
    /// parked on each visit, so a cluster built from them can be measured
    /// against a car park of a known size rather than against an assumption.
    static func visits(
        parkingAt offsets: [(north: Double, east: Double)],
        daysApart: TimeInterval = 86_400,
        accuracy: Double = 10
    ) -> [HistoricalPickupAnchorProbe.DerivedAnchor] {
        offsets.enumerated().map { index, offset in
            let arrivedAt = arrival.addingTimeInterval(Double(index) * daysApart)
            let spot = position(
                at: arrivedAt.addingTimeInterval(-12),
                north: offset.north,
                east: offset.east,
                accuracy: accuracy,
                session: nil
            )
            return HistoricalPickupAnchorProbe.DerivedAnchor(
                latitude: spot.latitude,
                longitude: spot.longitude,
                horizontalAccuracy: accuracy,
                observedAt: spot.timestamp,
                arrivedAt: arrivedAt,
                shiftID: UUID(),
                deliveryID: UUID(),
                bracket: .proven
            )
        }
    }

    /// A cluster built from parking offsets, or the refusal it earned.
    static func cluster(
        parkingAt offsets: [(north: Double, east: Double)],
        under policy: HistoricalPickupAnchorProbe.ClusterPolicy = .standard,
        accuracy: Double = 10
    ) -> Result<HistoricalPickupAnchorProbe.AnchorCluster, HistoricalPickupAnchorProbe.ClusterRefusal> {
        HistoricalPickupAnchorProbe.cluster(visits(parkingAt: offsets, accuracy: accuracy), under: policy)
    }
}
