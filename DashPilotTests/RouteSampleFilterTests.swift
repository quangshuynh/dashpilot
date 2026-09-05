import Foundation
import Testing
@testable import DashPilot

@MainActor
@Suite("Route sample filter")
struct RouteSampleFilterTests {
    private let filter = RouteSampleFilter()
    private let shiftStart = Date(timeIntervalSince1970: 1_756_000_000)

    /// A running shift with no route recorded yet, judged at `now`.
    private func context(
        end: Date? = nil,
        last: LocationSample? = nil,
        secondsAfterStart: TimeInterval = 60
    ) -> RouteSampleFilter.Context {
        RouteSampleFilter.Context(
            shiftStart: shiftStart,
            shiftEnd: end,
            lastAccepted: last,
            now: shiftStart.addingTimeInterval(secondsAfterStart)
        )
    }

    private func sample(
        secondsAfterStart: TimeInterval,
        northMetres: Double = 0,
        accuracy: Double = 8
    ) -> LocationSample {
        SyntheticRoute.sample(
            at: shiftStart.addingTimeInterval(secondsAfterStart),
            northMetres: northMetres,
            horizontalAccuracy: accuracy
        )
    }

    // MARK: The accepting case

    @Test("A good fix during a running shift is accepted")
    func acceptsAValidSample() {
        #expect(filter.evaluate(sample(secondsAfterStart: 60), in: context()) == .accept)
    }

    @Test("Ordinary driving between consecutive fixes is accepted")
    func acceptsLegitimateMovement() {
        // 60 m in two seconds is 30 m/s, about 67 mph.
        let first = sample(secondsAfterStart: 58)
        let second = sample(secondsAfterStart: 60, northMetres: 60)

        #expect(filter.evaluate(second, in: context(last: first)) == .accept)
    }

    @Test("A run of consecutive fixes is accepted the whole way")
    func acceptsAWholeRun() {
        var last: LocationSample?
        for step in 0..<10 {
            let candidate = sample(
                secondsAfterStart: TimeInterval(step) + 1,
                northMetres: Double(step) * 20
            )
            let decision = filter.evaluate(
                candidate,
                in: context(last: last, secondsAfterStart: TimeInterval(step) + 1)
            )
            #expect(decision == .accept, "Step \(step) should be accepted")
            if decision.isAccepted { last = candidate }
        }
    }

    // MARK: Coordinate validity

    @Test(
        "A coordinate the Earth does not have is rejected",
        arguments: [
            (Double.nan, -75.0),
            (40.0, Double.nan),
            (Double.infinity, -75.0),
            (91.0, -75.0),
            (-91.0, -75.0),
            (40.0, 181.0),
            (40.0, -181.0),
            // The value a zeroed coordinate takes.
            (0.0, 0.0)
        ]
    )
    func rejectsInvalidCoordinates(latitude: Double, longitude: Double) {
        let candidate = LocationSample(
            timestamp: shiftStart.addingTimeInterval(60),
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: 8
        )

        #expect(filter.evaluate(candidate, in: context()) == .reject(.invalidCoordinate))
    }

    @Test("A coordinate at the very edge of the valid range is still valid")
    func acceptsBoundaryCoordinates() {
        let candidate = LocationSample(
            timestamp: shiftStart.addingTimeInterval(60),
            latitude: 90,
            longitude: 180,
            horizontalAccuracy: 8
        )

        #expect(filter.evaluate(candidate, in: context()) == .accept)
    }

    // MARK: Accuracy

    @Test("A negative or non-finite radius of uncertainty is rejected", arguments: [-1.0, -70.0, Double.nan])
    func rejectsInvalidAccuracy(accuracy: Double) {
        #expect(
            filter.evaluate(sample(secondsAfterStart: 60, accuracy: accuracy), in: context())
                == .reject(.invalidAccuracy)
        )
    }

    @Test("A fix too imprecise to place the vehicle is rejected")
    func rejectsPoorAccuracy() {
        #expect(
            filter.evaluate(sample(secondsAfterStart: 60, accuracy: 100.1), in: context())
                == .reject(.poorAccuracy)
        )
        // Approximate authorization typically reports kilometres.
        #expect(
            filter.evaluate(sample(secondsAfterStart: 60, accuracy: 3000), in: context())
                == .reject(.poorAccuracy)
        )
    }

    @Test("Accuracy is judged by the value reported, not by the authorization scope")
    func acceptsMerelyImperfectAccuracy() {
        // A sample delivered under approximate authorization is not rejected as
        // a category: if the reported accuracy is within the threshold it is
        // kept, exactly like any other sample.
        #expect(filter.evaluate(sample(secondsAfterStart: 60, accuracy: 90), in: context()) == .accept)
        #expect(filter.evaluate(sample(secondsAfterStart: 60, accuracy: 100), in: context()) == .accept)
    }

    // MARK: The shift window

    @Test("Nothing is accepted for a shift that has ended")
    func rejectsSamplesForACompletedShift() {
        let end = shiftStart.addingTimeInterval(3600)
        // Even a perfect fix from the middle of the shift.
        let candidate = sample(secondsAfterStart: 1800)

        #expect(
            filter.evaluate(candidate, in: context(end: end, secondsAfterStart: 1800))
                == .reject(.shiftEnded)
        )
    }

    @Test("A fix from before the shift started is rejected")
    func rejectsSamplesBeforeTheShiftStart() {
        let candidate = SyntheticRoute.sample(at: shiftStart.addingTimeInterval(-1))

        #expect(filter.evaluate(candidate, in: context()) == .reject(.beforeShiftStart))
    }

    @Test("A fix taken exactly at the shift start is inside the window")
    func acceptsSamplesAtTheShiftStart() {
        let candidate = SyntheticRoute.sample(at: shiftStart)

        #expect(filter.evaluate(candidate, in: context(secondsAfterStart: 1)) == .accept)
    }

    @Test("A cached fix older than the age limit is rejected")
    func rejectsStaleSamples() {
        // Core Location hands back its last known position when updates start,
        // which can be from somewhere else entirely.
        let candidate = sample(secondsAfterStart: 60)

        #expect(
            filter.evaluate(candidate, in: context(secondsAfterStart: 60 + 31))
                == .reject(.stale)
        )
        #expect(filter.evaluate(candidate, in: context(secondsAfterStart: 60 + 30)) == .accept)
    }

    // MARK: Ordering and duplicates

    @Test("A repeat of the last accepted timestamp is rejected")
    func rejectsDuplicateTimestamps() {
        let first = sample(secondsAfterStart: 60)
        let repeated = sample(secondsAfterStart: 60, northMetres: 500)

        #expect(
            filter.evaluate(repeated, in: context(last: first)) == .reject(.duplicateTimestamp)
        )
    }

    @Test("A fix older than the last accepted one is rejected rather than reordered")
    func rejectsOutOfOrderSamples() {
        let first = sample(secondsAfterStart: 60, northMetres: 500)
        let earlier = sample(secondsAfterStart: 55)

        // Retaining it would make the stored route double back in time, and
        // every later rule judges against the newest sample.
        #expect(filter.evaluate(earlier, in: context(last: first)) == .reject(.outOfOrder))
    }

    @Test("A fix that has barely moved is rejected as noise")
    func rejectsNegligibleMovement() {
        let first = sample(secondsAfterStart: 60)
        let barelyMoved = sample(secondsAfterStart: 62, northMetres: 4.9)

        #expect(
            filter.evaluate(barelyMoved, in: context(last: first, secondsAfterStart: 62))
                == .reject(.negligibleMovement)
        )
    }

    @Test("Real movement just above the threshold is not mistaken for noise")
    func acceptsSmallButRealMovement() {
        let first = sample(secondsAfterStart: 60)
        let moved = sample(secondsAfterStart: 62, northMetres: 5.5)

        #expect(filter.evaluate(moved, in: context(last: first, secondsAfterStart: 62)) == .accept)
    }

    @Test("An identical repeated callback is rejected even with a fresh timestamp")
    func rejectsRepeatedIdenticalPositions() {
        let first = sample(secondsAfterStart: 60)
        var repeated = first
        repeated.timestamp = shiftStart.addingTimeInterval(61)

        #expect(
            filter.evaluate(repeated, in: context(last: first, secondsAfterStart: 61))
                == .reject(.negligibleMovement)
        )
    }

    // MARK: Implausible movement

    @Test("A jump no vehicle could have made is rejected")
    func rejectsImplausibleJumps() {
        let first = sample(secondsAfterStart: 60)
        // 10 km in five seconds.
        let jumped = sample(secondsAfterStart: 65, northMetres: 10_000)

        #expect(
            filter.evaluate(jumped, in: context(last: first, secondsAfterStart: 65))
                == .reject(.implausibleSpeed)
        )
    }

    @Test("Re-acquiring a fix after a long gap is not treated as a jump")
    func acceptsMovementAfterALongGap() {
        // Two minutes in a tunnel and 3 km further on is 25 m/s: fast, but a
        // road speed. The rule must not punish the gap itself.
        let first = sample(secondsAfterStart: 60)
        let reacquired = sample(secondsAfterStart: 180, northMetres: 3_000)

        #expect(filter.evaluate(reacquired, in: context(last: first, secondsAfterStart: 180)) == .accept)
    }

    @Test("Noise between two uncertain fixes is not treated as a jump")
    func toleratesNoiseBetweenUncertainFixes() {
        // 60 m apart, but each fix is only good to 50 m, so nothing about the
        // separation needs explaining.
        let first = sample(secondsAfterStart: 60, accuracy: 50)
        let noisy = sample(secondsAfterStart: 60.4, northMetres: 60, accuracy: 50)

        #expect(filter.evaluate(noisy, in: context(last: first, secondsAfterStart: 61)) == .accept)
    }

    @Test("Two precise fixes a fraction of a second apart still reject a real jump")
    func rejectsFastJumpsBetweenPreciseFixes() {
        // Half a second apart, so the speed check uses its one second floor;
        // 500 m in that second is still far beyond any vehicle.
        let first = sample(secondsAfterStart: 60, accuracy: 5)
        let jumped = sample(secondsAfterStart: 60.5, northMetres: 500, accuracy: 5)

        #expect(
            filter.evaluate(jumped, in: context(last: first, secondsAfterStart: 61))
                == .reject(.implausibleSpeed)
        )
    }

    // MARK: Rule precedence

    @Test("A sample breaking several rules is reported by the most fundamental one")
    func reportsTheFirstRuleBroken() {
        // Invalid coordinate and unusable accuracy at once.
        let candidate = LocationSample(
            timestamp: shiftStart.addingTimeInterval(-500),
            latitude: .nan,
            longitude: .nan,
            horizontalAccuracy: -1
        )

        #expect(filter.evaluate(candidate, in: context()) == .reject(.invalidCoordinate))
    }

    @Test("Every rejection reason has a log-safe name")
    func rejectionReasonsAreLoggable() {
        for reason in RouteSampleRejection.allCases {
            #expect(!reason.rawValue.isEmpty)
            // The reason names the rule, never the sample. Nothing that could
            // describe a position may appear here.
            #expect(!reason.rawValue.contains("."))
        }
    }

    // MARK: Geometry

    @Test("Distance between samples is measured in metres")
    func measuresDistance() {
        let origin = SyntheticRoute.sample(at: shiftStart)
        let north = SyntheticRoute.sample(at: shiftStart, northMetres: 1_000)

        let distance = RouteSampleFilter.distance(from: origin, to: north)

        #expect(abs(distance - 1_000) < 5)
        #expect(RouteSampleFilter.distance(from: origin, to: origin) == 0)
    }

    // MARK: Tuning

    @Test("Thresholds are configurable rather than baked into the rules")
    func thresholdsAreTunable() {
        var strict = RouteSampleFilter()
        strict.maximumHorizontalAccuracy = 20

        let candidate = sample(secondsAfterStart: 60, accuracy: 50)

        #expect(filter.evaluate(candidate, in: context()) == .accept)
        #expect(strict.evaluate(candidate, in: context()) == .reject(.poorAccuracy))
    }
}
