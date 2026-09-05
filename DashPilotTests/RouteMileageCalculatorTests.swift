import Foundation
import Testing
@testable import DashPilot

@MainActor
@Suite("Route mileage")
struct RouteMileageCalculatorTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let calculator = RouteMileageCalculator()

    /// One capture session, unless a test needs more than one.
    private let session = UUID()

    private func point(secondsIn: TimeInterval, northMetres: Double, session: UUID?) -> RoutePoint {
        SyntheticRoute.point(
            at: start.addingTimeInterval(secondsIn),
            northMetres: northMetres,
            captureSessionID: session
        )
    }

    /// A straight run of positions `metresApart`, one every `interval` seconds.
    private func run(
        from firstSecond: TimeInterval,
        startingAt northMetres: Double,
        count: Int,
        metresApart: Double = 100,
        interval: TimeInterval = 10,
        session: UUID?
    ) -> [RoutePoint] {
        (0..<count).map { step in
            point(
                secondsIn: firstSecond + Double(step) * interval,
                northMetres: northMetres + Double(step) * metresApart,
                session: session
            )
        }
    }

    // MARK: Nothing to measure

    @Test("A shift with no route reports nothing measured rather than zero miles")
    func measuresNothingWithoutSamples() {
        let result = calculator.distance(of: [])

        #expect(result == .none)
        #expect(!result.isMeasured)
        #expect(result.metres == 0)
        #expect(result.usableSampleCount == 0)
    }

    @Test("A single position is not a distance")
    func measuresNothingFromOnePosition() {
        let result = calculator.distance(of: [point(secondsIn: 0, northMetres: 0, session: session)])

        #expect(!result.isMeasured)
        #expect(result.metres == 0)
        #expect(result.segmentCount == 0)
        #expect(result.gapCount == 0)
        #expect(result.usableSampleCount == 1)
    }

    @Test("Two positions separated by a capture gap measure nothing at all")
    func measuresNothingAcrossASingleGap() {
        let result = calculator.distance(of: [
            point(secondsIn: 0, northMetres: 0, session: UUID()),
            point(secondsIn: 30, northMetres: 500, session: UUID())
        ])

        #expect(!result.isMeasured)
        #expect(result.metres == 0)
        #expect(result.gapCount == 1)
        #expect(result.isPartial)
    }

    // MARK: Measuring a continuous route

    @Test("Two positions in one capture session measure the distance between them")
    func measuresTwoPositions() {
        let result = calculator.distance(of: [
            point(secondsIn: 0, northMetres: 0, session: session),
            point(secondsIn: 10, northMetres: 500, session: session)
        ])

        #expect(result.isMeasured)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 500), "measured \(result.metres) m")
        #expect(result.segmentCount == 1)
        #expect(result.gapCount == 0)
        #expect(!result.isPartial)
        #expect(result.usableSampleCount == 2)
    }

    @Test("A run of positions measures the sum of its legs")
    func measuresConsecutiveLegs() {
        let result = calculator.distance(of: run(from: 0, startingAt: 0, count: 5, session: session))

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.segmentCount == 1)
        #expect(result.gapCount == 0)
    }

    @Test("A known synthetic offset measures the distance it describes")
    func measuresAKnownDistance() {
        let result = calculator.distance(of: [
            point(secondsIn: 0, northMetres: 0, session: session),
            point(secondsIn: 60, northMetres: 1_000, session: session)
        ])

        #expect(abs(result.metres - 1_000) < 5, "measured \(result.metres) m for a 1 km offset")
    }

    @Test("Legitimate movement of a few metres is measured, not discarded")
    func measuresShortMovement() {
        let result = calculator.distance(of: [
            point(secondsIn: 0, northMetres: 0, session: session),
            point(secondsIn: 2, northMetres: 6, session: session),
            point(secondsIn: 4, northMetres: 12, session: session)
        ])

        #expect(result.isMeasured)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 12), "measured \(result.metres) m")
    }

    @Test("Positions at the same place add no distance")
    func measuresNoDistanceBetweenIdenticalCoordinates() {
        let result = calculator.distance(of: [
            point(secondsIn: 0, northMetres: 250, session: session),
            point(secondsIn: 10, northMetres: 250, session: session),
            point(secondsIn: 20, northMetres: 250, session: session)
        ])

        // The route was measured — it simply describes a vehicle that did not
        // move, which is a different statement from "nothing could be measured".
        #expect(result.isMeasured)
        #expect(result.metres == 0)
        #expect(result.segmentCount == 1)
    }

    @Test("A larger route measures the whole of it")
    func measuresALargerRoute() {
        let result = calculator.distance(
            of: run(from: 0, startingAt: 0, count: 500, metresApart: 40, interval: 2, session: session)
        )

        #expect(result.usableSampleCount == 500)
        #expect(result.segmentCount == 1)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 499 * 40), "measured \(result.metres) m")
    }

    // MARK: Gaps

    @Test("Distance across a change of capture session is left out")
    func excludesDistanceAcrossACaptureGap() {
        let firstSession = UUID()
        let secondSession = UUID()
        // Two 400 m runs, 8 km apart. The straight line between them is the
        // distance a driver covered while DashPilot was not recording.
        let route = run(from: 0, startingAt: 0, count: 5, session: firstSession)
            + run(from: 60, startingAt: 8_000, count: 5, session: secondSession)

        let result = calculator.distance(of: route)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 800), "measured \(result.metres) m")
        #expect(result.segmentCount == 2)
        #expect(result.gapCount == 1)
        #expect(result.isPartial)
    }

    @Test("A gap that is only a pause in time is left out too")
    func excludesDistanceAcrossALongSilence() {
        // One capture session throughout: the app kept recording, but no
        // position arrived for an hour. Whether the vehicle was parked or the
        // signal was gone, a straight line across it is not a measurement.
        let route = run(from: 0, startingAt: 0, count: 3, session: session)
            + run(from: 3_600, startingAt: 20_000, count: 3, session: session)

        let result = calculator.distance(of: route)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.gapCount == 1)
        #expect(result.segmentCount == 2)
    }

    @Test("Ordinary driving cadence does not fragment a route")
    func doesNotFragmentOrdinaryDriving() {
        let result = calculator.distance(
            of: run(from: 0, startingAt: 0, count: 40, metresApart: 25, interval: 3, session: session)
        )

        #expect(result.segmentCount == 1)
        #expect(result.gapCount == 0)
        #expect(!result.isPartial)
    }

    @Test("A pause shorter than the gap threshold stays one segment")
    func toleratesAShortPause() {
        let route = run(from: 0, startingAt: 0, count: 3, session: session)
            + run(from: 90, startingAt: 300, count: 3, session: session)

        let result = calculator.distance(of: route)

        #expect(result.segmentCount == 1)
        #expect(result.gapCount == 0)
    }

    @Test("Every segment of a fragmented route contributes")
    func sumsSeveralSegments() {
        let route = run(from: 0, startingAt: 0, count: 3, session: UUID())
            + run(from: 600, startingAt: 5_000, count: 3, session: UUID())
            + run(from: 1_200, startingAt: 9_000, count: 3, session: UUID())

        let result = calculator.distance(of: route)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 600), "measured \(result.metres) m")
        #expect(result.segmentCount == 3)
        #expect(result.gapCount == 2)
    }

    @Test("The gap policy is a documented value rather than a hidden constant")
    func gapPolicyIsConfigurable() {
        let permissive = RouteMileageCalculator(maximumSampleInterval: 7_200)
        let route = run(from: 0, startingAt: 0, count: 2, session: session)
            + run(from: 3_600, startingAt: 5_000, count: 2, session: session)

        #expect(calculator.maximumSampleInterval == 120)
        #expect(calculator.distance(of: route).gapCount == 1)
        #expect(permissive.distance(of: route).gapCount == 0)
    }

    // MARK: The shift window

    @Test("A route that stops long before the shift ends is partial")
    func reportsARouteThatEndsEarly() {
        let route = run(from: 0, startingAt: 0, count: 5, session: session)
        let window = start...start.addingTimeInterval(3_600)

        let result = calculator.distance(of: route, covering: window)

        #expect(result.isMeasured)
        #expect(result.gapCount == 1)
        #expect(result.isPartial)
    }

    @Test("A route that starts long after the shift did is partial")
    func reportsARouteThatStartsLate() {
        let route = run(from: 1_800, startingAt: 0, count: 5, session: session)
        let window = start...start.addingTimeInterval(1_900)

        let result = calculator.distance(of: route, covering: window)

        #expect(result.gapCount == 1)
        #expect(result.isPartial)
    }

    @Test("A route covering its whole shift is not reported as partial")
    func reportsACompleteRoute() {
        let route = run(from: 5, startingAt: 0, count: 10, session: session)
        let window = start...start.addingTimeInterval(120)

        let result = calculator.distance(of: route, covering: window)

        #expect(result.gapCount == 0)
        #expect(!result.isPartial)
    }

    @Test("A shift with no route at all is one uncovered stretch")
    func reportsAShiftWithNoRoute() {
        let result = calculator.distance(of: [], covering: start...start.addingTimeInterval(3_600))

        #expect(!result.isMeasured)
        #expect(result.gapCount == 1)
        #expect(result.isPartial)
    }

    @Test("A shift too short to record anything is not called partial")
    func ignoresAnEmptyRouteInAShortShift() {
        let result = calculator.distance(of: [], covering: start...start.addingTimeInterval(20))

        #expect(result.gapCount == 0)
        #expect(!result.isPartial)
    }

    // MARK: Imperfect stored data

    @Test("Positions stored out of order are measured in time order")
    func ordersPositionsByTimestamp() {
        let ordered = run(from: 0, startingAt: 0, count: 5, session: session)
        let shuffled = [ordered[3], ordered[0], ordered[4], ordered[2], ordered[1]]

        let result = calculator.distance(of: shuffled)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.segmentCount == 1)
        #expect(result.gapCount == 0)
    }

    @Test("Two positions at the same instant are not measured as movement")
    func collapsesDuplicateTimestamps() {
        let route = [
            point(secondsIn: 0, northMetres: 0, session: session),
            point(secondsIn: 10, northMetres: 100, session: session),
            // Contradicts the position above: the same instant, somewhere else.
            point(secondsIn: 10, northMetres: 900, session: session),
            point(secondsIn: 20, northMetres: 200, session: session)
        ]

        let result = calculator.distance(of: route)

        #expect(result.usableSampleCount == 3)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 200), "measured \(result.metres) m")
    }

    @Test("An identical row stored twice does not double-count")
    func ignoresAnExactDuplicate() {
        let first = point(secondsIn: 0, northMetres: 0, session: session)
        let second = point(secondsIn: 10, northMetres: 300, session: session)

        let result = calculator.distance(of: [first, second, second, first])

        #expect(result.usableSampleCount == 2)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 300), "measured \(result.metres) m")
    }

    @Test("The same route measures the same distance whatever order it is stored in")
    func isDeterministic() {
        let route = run(from: 0, startingAt: 0, count: 6, session: session)
            + run(from: 600, startingAt: 4_000, count: 6, session: UUID())

        let forwards = calculator.distance(of: route)
        let backwards = calculator.distance(of: Array(route.reversed()))

        #expect(forwards == backwards)
    }

    @Test("A position that describes nowhere on Earth is ignored", arguments: [
        RoutePoint(timestamp: Date(timeIntervalSince1970: 1_756_000_005), latitude: 91, longitude: -75, captureSessionID: nil),
        RoutePoint(timestamp: Date(timeIntervalSince1970: 1_756_000_005), latitude: 40, longitude: 181, captureSessionID: nil),
        RoutePoint(timestamp: Date(timeIntervalSince1970: 1_756_000_005), latitude: .nan, longitude: -75, captureSessionID: nil),
        RoutePoint(timestamp: Date(timeIntervalSince1970: 1_756_000_005), latitude: .infinity, longitude: -75, captureSessionID: nil),
        RoutePoint(timestamp: Date(timeIntervalSince1970: 1_756_000_005), latitude: 0, longitude: 0, captureSessionID: nil)
    ])
    func ignoresMalformedPositions(malformed: RoutePoint) {
        let route = [
            point(secondsIn: 0, northMetres: 0, session: session),
            malformed,
            point(secondsIn: 10, northMetres: 400, session: session)
        ]

        let result = calculator.distance(of: route)

        #expect(result.usableSampleCount == 2)
        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
    }

    @Test("A route of nothing but malformed positions measures nothing")
    func survivesARouteOfNonsense() {
        let route = [
            RoutePoint(timestamp: start, latitude: .nan, longitude: .nan, captureSessionID: nil),
            RoutePoint(timestamp: start.addingTimeInterval(10), latitude: 0, longitude: 0, captureSessionID: nil)
        ]

        let result = calculator.distance(of: route)

        #expect(result == .none)
    }

    // MARK: Positions stored before continuity was recorded

    @Test("A legacy route is measured, and says its continuity was inferred")
    func measuresALegacyRoute() {
        let result = calculator.distance(of: run(from: 0, startingAt: 0, count: 5, session: nil))

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.usesInferredContinuity)
        // Its gaps cannot be seen, so it is reported as partial even though no
        // gap was found in it.
        #expect(result.isPartial)
        #expect(result.gapCount == 0)
    }

    @Test("A long silence in a legacy route is still a gap")
    func excludesLongSilencesInALegacyRoute() {
        let route = run(from: 0, startingAt: 0, count: 3, session: nil)
            + run(from: 3_600, startingAt: 20_000, count: 3, session: nil)

        let result = calculator.distance(of: route)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.gapCount == 1)
    }

    @Test("Where a legacy route meets a recorded one, nothing is measured across")
    func breaksBetweenLegacyAndRecordedPositions() {
        let route = run(from: 0, startingAt: 0, count: 3, session: nil)
            + run(from: 30, startingAt: 300, count: 3, session: session)

        let result = calculator.distance(of: route)

        #expect(SyntheticRoute.isCloseEnough(result.metres, to: 400), "measured \(result.metres) m")
        #expect(result.gapCount == 1)
        #expect(result.segmentCount == 2)
    }

    @Test("A route recorded with continuity does not claim to be inferred")
    func doesNotClaimInferenceForARecordedRoute() {
        let result = calculator.distance(of: run(from: 0, startingAt: 0, count: 5, session: session))

        #expect(!result.usesInferredContinuity)
    }

    // MARK: Units

    @Test("Distance is held in metres and presented in miles")
    func convertsToMiles() {
        let distance = RouteDistance(
            metres: 1_609.344 * 12.4,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 2,
            usesInferredContinuity: false
        )

        #expect(abs(distance.measurement.value - distance.metres) < 0.000_1)
        #expect(distance.measurement.unit == .meters)
        #expect(distance.formattedMiles(locale: Locale(identifier: "en_US")) == "12.4 mi")
    }

    @Test("Miles are rounded to a tenth, not to a precision the route lacks")
    func roundsMilesForDisplay() {
        let distance = RouteDistance(
            metres: 1_609.344 * 3.456,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 2,
            usesInferredContinuity: false
        )

        #expect(distance.formattedMiles(locale: Locale(identifier: "en_US")) == "3.5 mi")
    }
}
