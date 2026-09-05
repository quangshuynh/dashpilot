import Foundation
import Testing
@testable import DashPilot

/// The words the detail screen and the history row put on a route.
///
/// Wording is tested rather than eyeballed because the failure mode is a claim,
/// not a crash: `12.4 mi` written as "total mileage" or "miles driven" would be
/// wrong about a foreground-only capture in a way no arithmetic test would ever
/// catch. A fixed locale is used throughout so the assertions describe the
/// wording rather than the reader's region.
@Suite("Route quality wording")
struct RouteQualityTests {
    private let locale = Locale(identifier: "en_US")

    /// One mile in metres, so a test can state a distance in the unit it reads in.
    private static let metresPerMile = 1609.344

    private func route(
        miles: Double,
        segmentCount: Int = 1,
        gapCount: Int = 0,
        usableSampleCount: Int = 40,
        usesInferredContinuity: Bool = false
    ) -> RouteQuality {
        RouteQuality(
            RouteDistance(
                metres: miles * Self.metresPerMile,
                segmentCount: segmentCount,
                gapCount: gapCount,
                usableSampleCount: usableSampleCount,
                usesInferredContinuity: usesInferredContinuity
            )
        )
    }

    // MARK: Recorded mileage

    @Test("A measured route says what it recorded, and says only that")
    func measuredRouteStatement() {
        let quality = route(miles: 4.5)

        #expect(quality.mileageStatement(locale: locale) == "4.5 mi recorded")
        #expect(quality.isMeasured)
    }

    @Test("Nothing in a route's wording claims the miles that were driven", arguments: [0.0, 4.5, 128.25])
    func neverClaimsDrivenMileage(miles: Double) {
        let quality = route(miles: miles, gapCount: 1)
        let forbidden = ["Total mileage", "Miles driven", "Trip mileage", "Coverage", "%"]

        let statements = [
            quality.mileageStatement(locale: locale),
            quality.spokenMileageStatement(locale: locale),
            quality.segmentStatement,
            quality.gapStatement,
            quality.partialMarker
        ].compactMap { $0 }

        for statement in statements {
            for phrase in forbidden {
                #expect(!statement.contains(phrase), "\(statement) claims more than the route can support")
            }
        }
    }

    @Test("A shift with no usable position says so instead of showing zero miles")
    func noRouteRecorded() {
        let quality = RouteQuality(.none)

        #expect(quality.mileageStatement(locale: locale) == "No route recorded")
        #expect(!quality.mileageStatement(locale: locale).contains("0"))
        #expect(quality.unmeasurableExplanation?.contains("no usable position") == true)
        #expect(!quality.isMeasured)
    }

    @Test("Positions that no continuous stretch joined are distinct from no route at all")
    func routeNotMeasurable() {
        let quality = route(miles: 0, segmentCount: 0, gapCount: 3, usableSampleCount: 4)

        #expect(quality.mileageStatement(locale: locale) == "Not enough route recorded to measure")
        #expect(quality.unmeasurableExplanation?.contains("captured continuously") == true)
    }

    @Test("An unmeasurable route reports no segments and no gaps rather than counting zeros")
    func unmeasurableRouteInventsNoCounts() {
        for quality in [RouteQuality(.none), route(miles: 0, segmentCount: 0, gapCount: 2, usableSampleCount: 3)] {
            #expect(quality.segmentStatement == nil)
            #expect(quality.gapStatement == nil)
        }
    }

    @Test("A measured route has no explanation for being unmeasurable")
    func measuredRouteHasNoUnmeasurableExplanation() {
        #expect(route(miles: 4.5).unmeasurableExplanation == nil)
    }

    // MARK: Segments and gaps

    @Test("Segments are counted in the singular and the plural")
    func segmentStatements() {
        #expect(route(miles: 4.5, segmentCount: 1).segmentStatement == "1 capture segment")
        #expect(route(miles: 4.5, segmentCount: 3).segmentStatement == "3 capture segments")
    }

    @Test("Gaps are counted, and none is stated as a detection rather than as a clean route")
    func gapStatements() {
        #expect(route(miles: 4.5, gapCount: 0).gapStatement == "No capture gaps detected")
        #expect(route(miles: 4.5, gapCount: 1).gapStatement == "1 capture gap")
        #expect(route(miles: 4.5, gapCount: 2).gapStatement == "2 capture gaps")
    }

    // MARK: Partiality

    @Test("A route with a gap is marked partial and explains what that costs")
    func partialRoute() {
        let quality = route(miles: 4.5, gapCount: 1)

        #expect(quality.partialMarker == "partial route")
        #expect(quality.partialExplanation?.hasPrefix("Partial route:") == true)
        #expect(quality.partialExplanation?.contains("more miles were driven than were recorded") == true)
    }

    @Test("A route with no detected gap is not marked partial")
    func completeRoute() {
        let quality = route(miles: 4.5, gapCount: 0)

        #expect(quality.partialMarker == nil)
        #expect(quality.partialExplanation == nil)
        #expect(quality.inferredContinuityExplanation == nil)
    }

    @Test("A legacy route whose continuity was only inferred is partial and says why")
    func inferredContinuity() {
        let quality = route(miles: 4.5, gapCount: 0, usesInferredContinuity: true)

        #expect(quality.partialMarker == "partial route")
        #expect(quality.inferredContinuityExplanation?.contains("timestamps") == true)
    }

    // MARK: What VoiceOver hears

    @Test("The spoken mileage says miles in full rather than an abbreviation")
    func spokenMileageIsNotAbbreviated() {
        let spoken = route(miles: 4.5).spokenMileageStatement(locale: locale)

        #expect(spoken == "4.5 miles recorded")
    }

    @Test("The spoken mileage carries partiality as a claim, not as a two-word marker")
    func spokenMileageStatesPartiality() {
        let spoken = route(miles: 4.5, gapCount: 2).spokenMileageStatement(locale: locale)

        #expect(spoken.hasPrefix("4.5 miles recorded."))
        #expect(spoken.contains("more miles were driven than were recorded"))
    }

    @Test("An unmeasurable route is spoken the same way it is written")
    func spokenUnmeasurableRoute() {
        let quality = RouteQuality(.none)

        #expect(quality.spokenMileageStatement(locale: locale) == quality.mileageStatement(locale: locale))
    }
}

/// The sentences a detail screen shows in place of a rate it cannot derive.
///
/// The rule they exist to keep is the same one ``ShiftMetricsCalculator`` keeps:
/// an absent rate is an absence, and nothing may present it as a zero or as a
/// value at all.
@Suite("Unavailable rate explanations")
struct ShiftRateUnavailabilityExplanationTests {
    private static let allReasons: [ShiftRateUnavailability] = [
        .shiftNotCompleted,
        .earningsNotRecorded,
        .noElapsedTime,
        .noRouteRecorded,
        .routeNotMeasurable,
        .zeroRecordedDistance
    ]

    @Test("Every reason has a sentence, and no two reasons share one")
    func everyReasonIsExplained() {
        let explanations = Self.allReasons.map(\.explanation)

        #expect(explanations.allSatisfy { !$0.isEmpty })
        #expect(Set(explanations).count == explanations.count)
    }

    @Test("No explanation presents the missing rate as a zero")
    func noExplanationImpliesZero() {
        for reason in Self.allReasons where reason != .zeroRecordedDistance {
            #expect(!reason.explanation.contains("0"), "\(reason) reads as a value of zero")
            #expect(!reason.explanation.contains("$"), "\(reason) reads as an amount")
        }
    }

    @Test("A missing amount is explained as something to add rather than as nothing earned")
    func missingEarningsAsksForAnAmount() {
        #expect(ShiftRateUnavailability.earningsNotRecorded.explanation == "Add what this shift paid to see this rate.")
    }

    @Test("A measured distance of zero is described as a measurement, not as an absence")
    func zeroDistanceIsAMeasurement() {
        let explanation = ShiftRateUnavailability.zeroRecordedDistance.explanation

        #expect(explanation.contains("did not move"))
        #expect(!explanation.contains("no distance"))
    }
}
