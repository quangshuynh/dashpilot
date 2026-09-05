import Foundation

/// What a shift's recorded route can honestly be said to show, in words.
///
/// ``RouteDistance`` is the measurement; this is the vocabulary for it. The two
/// are separate because the wording is the part that is easy to get wrong: a
/// route measured from foreground-only capture is a *floor* on the distance
/// driven, and almost every natural phrase for it — total mileage, miles driven,
/// trip distance, coverage — claims more than that. Keeping the phrasing in one
/// tested type means the history row and the detail screen cannot drift into
/// saying different things about the same route, and a claim can be checked by a
/// test rather than by reading a view.
///
/// ## What is deliberately not here
///
/// There is **no coverage percentage**. A percentage needs a denominator, and
/// the denominator would have to be the distance actually driven, which is
/// exactly the number DashPilot does not have. Segments and gaps are counts of
/// what capture did; they are facts. A percentage derived from them would be an
/// invention.
///
/// Nothing here describes a route as complete, either. `gapCount == 0` means no
/// gap was *detected*, which is a statement about the detection and not about
/// the drive: capture stops when the app leaves the foreground, and a stretch
/// with no positions in it cannot be told apart from a parked vehicle.
nonisolated struct RouteQuality: Equatable, Sendable {
    let distance: RouteDistance

    init(_ distance: RouteDistance) {
        self.distance = distance
    }

    /// Whether a distance was measured at all.
    var isMeasured: Bool { distance.isMeasured }

    /// The mileage, as the interface writes it: `"4.5 mi recorded"`.
    ///
    /// A route with nothing measurable says so rather than showing `0.0 mi`,
    /// which a driver would read as "you did not move" instead of "no distance
    /// could be measured". The two unmeasurable cases stay apart, because
    /// "nothing was recorded" and "positions were recorded but none of them
    /// join up" are different things to have happened.
    func mileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard distance.isMeasured else {
            return distance.usableSampleCount == 0
                ? "No route recorded"
                : "Not enough route recorded to measure"
        }
        return "\(distance.formattedMiles(locale: locale)) recorded"
    }

    /// The mileage as VoiceOver should hear it.
    ///
    /// `mi` reads well and hears badly, and the fact that makes the figure
    /// honest — that it is what was *recorded* — has to survive being spoken, so
    /// partiality is a sentence here rather than the two-word marker the eye
    /// gets.
    func spokenMileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        guard distance.isMeasured else { return mileageStatement(locale: locale) }
        var sentences = ["\(distance.formattedMiles(width: .wide, locale: locale)) recorded"]
        if distance.isPartial { sentences.append(partialSentence) }
        return sentences.joined(separator: ". ")
    }

    /// The two-word marker shown beside the mileage when the route is known to
    /// cover less than the shift, or `nil` when no gap was detected.
    var partialMarker: String? {
        distance.isPartial ? "partial route" : nil
    }

    /// How many unbroken stretches of capture contributed distance, or `nil`
    /// when none did.
    var segmentStatement: String? {
        guard distance.isMeasured else { return nil }
        return distance.segmentCount == 1
            ? "1 capture segment"
            : "\(distance.segmentCount) capture segments"
    }

    /// How many stretches of the shift the route does not account for.
    ///
    /// Always present for a shift whose route was measured, including when the
    /// answer is none: "no capture gaps detected" is a useful thing to be told,
    /// and it is a weaker claim than "the whole shift was recorded".
    var gapStatement: String? {
        guard distance.isMeasured else { return nil }
        switch distance.gapCount {
        case 0: return "No capture gaps detected"
        case 1: return "1 capture gap"
        default: return "\(distance.gapCount) capture gaps"
        }
    }

    /// The sentence that explains what a partial route means for the numbers
    /// derived from it, or `nil` when no gap was detected.
    var partialExplanation: String? {
        distance.isPartial ? partialSentence : nil
    }

    /// The sentence for a route stored before capture continuity was recorded,
    /// or `nil` for a route that carries its own.
    ///
    /// Such a route's gaps are invisible: nothing in it says whether capture
    /// stopped between two positions, so its total is a floor with unknown gaps
    /// in it. That is worth stating plainly rather than leaving the driver to
    /// read a gap count of zero as a clean route.
    var inferredContinuityExplanation: String? {
        guard distance.usesInferredContinuity else { return nil }
        return """
            This route was recorded before DashPilot tracked capture continuity, \
            so breaks in it were worked out from timestamps and short ones cannot be detected.
            """
    }

    /// Why there is no distance, or `nil` when there is one.
    var unmeasurableExplanation: String? {
        guard !distance.isMeasured else { return nil }
        return distance.usableSampleCount == 0
            ? "DashPilot recorded no usable position during this shift, so there is no distance to report."
            : """
                Positions were recorded, but no two of them were captured continuously, \
                so there is no stretch of route to measure along.
                """
    }

    /// The two words the eye needs, and then the reason, so that a listener and
    /// a reader of the detail screen get the same claim the compact marker makes.
    private var partialSentence: String {
        """
        Partial route: DashPilot was not recording for part of this shift, \
        so more miles were driven than were recorded.
        """
    }
}
