import Foundation

/// How much history a pickup place has, and therefore what may be said about it.
///
/// The threshold exists because a median of one number is that number, and
/// presenting it as a *typical* wait would dress a single evening up as a
/// pattern. Two is the smallest count at which the median is a midpoint between
/// distinct observations rather than a rename of one of them; it is not a claim
/// that two pickups are enough to predict a third, which is why the sample count
/// is shown alongside the figure at every count.
nonisolated enum PickupWaitAvailability: Equatable, Sendable {
    /// No delivery at this place recorded both an arrival and a pickup.
    case noRecordedWaits
    /// At least one wait was recorded, but too few for a typical value.
    case insufficientHistory
    /// Enough recorded waits for a median to be offered as the typical one.
    case available
}

/// What a place's recorded pickup waits add up to.
///
/// ## Derived, never stored
///
/// Nothing here is written to the store. Every figure comes from the lifecycle
/// timestamps on the deliveries that reference the place, recomputed when asked,
/// so no aggregate can drift away from the events it describes. That is the same
/// rule mileage, rates and delivery state already follow, and it is why
/// ``PickupPlace`` carries no counters.
///
/// ## Median, not mean
///
/// One 40-minute wait among five ordinary ones drags a mean somewhere no evening
/// actually was. The median stays where most of the pickups were, which is the
/// question a driver is asking. The long wait is **not** discarded to protect
/// the average — see ``longestDuration`` — because a place that occasionally
/// costs 40 minutes is exactly the fact worth knowing.
///
/// ## What it is not
///
/// It is not a prediction, a score, a ranking or a grade. It describes pickups
/// that already happened at a place the driver named themselves, and the next
/// one is free to be nothing like them.
nonisolated struct PickupWaitMetrics: Equatable, Sendable {
    /// How many recorded waits went into these figures.
    ///
    /// Always shown next to any duration derived from them. A median with no
    /// count attached reads as a settled fact about a place rather than as a
    /// summary of however few pickups happen to be behind it.
    let sampleCount: Int

    /// The middle of the recorded waits, or `nil` when there are none.
    ///
    /// Present at **any** non-zero count, because the median of one wait is a
    /// true statement about that wait. Whether it may be called *typical* is a
    /// separate question, answered by ``typicalDuration``.
    let medianDuration: TimeInterval?

    /// The shortest and longest waits recorded, or `nil` when there are none.
    ///
    /// The spread is the honest companion to the median: it shows what the
    /// middle value is the middle *of*, and it is where a retained long wait
    /// becomes visible rather than being quietly averaged away.
    let shortestDuration: TimeInterval?
    let longestDuration: TimeInterval?

    /// When the most recent recorded wait ended, or `nil` when there are none.
    let mostRecentSampleAt: Date?

    /// The count at or above which a median is offered as a typical wait.
    static let minimumSampleCount = 2

    /// A place nothing has been recorded at.
    static let none = PickupWaitMetrics(
        sampleCount: 0,
        medianDuration: nil,
        shortestDuration: nil,
        longestDuration: nil,
        mostRecentSampleAt: nil
    )

    var availability: PickupWaitAvailability {
        if sampleCount == 0 { return .noRecordedWaits }
        return sampleCount >= Self.minimumSampleCount ? .available : .insufficientHistory
    }

    /// The median, but only where there is enough history to call it typical.
    ///
    /// Screens that want to write the word "typical" ask for this one, so the
    /// threshold cannot be forgotten at a call site.
    var typicalDuration: TimeInterval? {
        availability == .available ? medianDuration : nil
    }

    /// True when the recorded waits were not all the same length.
    var hasSpread: Bool {
        guard let shortestDuration, let longestDuration else { return false }
        return shortestDuration != longestDuration
    }
}

// MARK: Wording

/// The words a place's history is written and spoken in.
///
/// Wording lives here rather than in a view for the reason ``RouteQuality``'s
/// does: the failure mode is a claim, not a crash. "Average wait 11 min" over
/// two pickups would be wrong in a way no arithmetic test would catch, so what
/// may be said at each count is decided next to the rule that decides it.
nonisolated extension PickupWaitMetrics {
    /// What the headline figure is called. Defined as the median, and said so
    /// wherever it appears.
    static let typicalTitle = "Typical recorded wait"

    /// What the count of recorded waits is, on screen.
    ///
    /// At or above the threshold this also names the statistic, so `11 min`
    /// never appears with only a bare count under it.
    var basisStatement: String {
        switch availability {
        case .noRecordedWaits:
            "No recorded pickup waits"
        case .insufficientHistory:
            "\(sampleCount) recorded \(Self.pickupNoun(sampleCount))"
        case .available:
            "Median of \(sampleCount) recorded \(Self.pickupNoun(sampleCount))"
        }
    }

    /// Why a place with too little history shows no typical wait, or `nil` once
    /// it has enough.
    ///
    /// Deliberately says *not enough history*, not *unreliable* or *inaccurate*:
    /// the recorded waits are exact, there are simply too few of them to call
    /// one of them typical.
    var insufficientHistoryExplanation: String? {
        switch availability {
        case .noRecordedWaits:
            """
            A wait is measured between a recorded arrival and a recorded pickup. \
            No delivery here recorded both.
            """
        case .insufficientHistory:
            "Not enough history for a typical wait."
        case .available:
            nil
        }
    }

    /// The whole history as one spoken claim.
    ///
    /// VoiceOver hears a sentence rather than a duration floating next to a
    /// count, because a figure read without what it is the middle of is exactly
    /// the overclaim this screen exists to avoid.
    var spokenStatement: String {
        var sentences: [String] = []
        switch availability {
        case .noRecordedWaits:
            sentences.append("No recorded pickup waits")
        case .insufficientHistory:
            if let medianDuration {
                sentences.append("\(sampleCount) recorded \(Self.pickupNoun(sampleCount)), \(DurationText.spoken(medianDuration))")
            } else {
                sentences.append(basisStatement)
            }
        case .available:
            if let typical = typicalDuration {
                sentences.append("Typical recorded pickup wait, \(DurationText.spoken(typical))")
                sentences.append("median of \(sampleCount) recorded \(Self.pickupNoun(sampleCount))")
            } else {
                sentences.append(basisStatement)
            }
        }
        var statement = sentences.joined(separator: ", ") + "."
        if let explanation = insufficientHistoryExplanation {
            statement += " " + explanation
        }
        return statement
    }

    /// The shortest and longest recorded waits, or `nil` when there is nothing
    /// to contrast — no history at all, or every wait the same length.
    var spreadStatement: String? {
        guard hasSpread, let shortestDuration, let longestDuration else { return nil }
        return "Shortest \(DurationText.short(shortestDuration)) · Longest \(DurationText.short(longestDuration))"
    }

    var spokenSpreadStatement: String? {
        guard hasSpread, let shortestDuration, let longestDuration else { return nil }
        return "Shortest recorded wait \(DurationText.spoken(shortestDuration)), "
            + "longest \(DurationText.spoken(longestDuration))."
    }

    private static func pickupNoun(_ count: Int) -> String {
        count == 1 ? "pickup" : "pickups"
    }
}
