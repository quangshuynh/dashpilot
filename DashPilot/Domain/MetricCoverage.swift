import Foundation

/// How many of the records a period figure *could* have used actually went into
/// it.
///
/// ## Why this travels with the number
///
/// An aggregate is the place a missing value turns into a lie. Four completed
/// shifts with an amount recorded on three of them produce a real subtotal, and
/// presenting that subtotal on its own says the driver earned it across all
/// four. The fix is not a footnote on the screen — a caller can forget a
/// footnote — it is that the figure and the count it was derived from are one
/// value that cannot be separated.
///
/// So every aggregate that can be short of its sources carries one of these, and
/// **the missing records are never counted as zero**. Three shifts totalling
/// `$284.50` are `$284.50 recorded` across `3 of 4 shifts`, never `$284.50` as
/// the week's earnings and never `$284.50` averaged over four.
///
/// ## What it is not
///
/// It is not a confidence, a quality score or a percentage. It is two counts.
/// A percentage would invite comparison between metrics whose denominators mean
/// different things, and the counts are what a driver can actually check against
/// their own memory of the week.
nonisolated struct MetricCoverage: Equatable, Sendable, Hashable {
    /// Records that contributed to the figure.
    let contributingCount: Int

    /// Records that could have contributed — the ones the figure claims to
    /// describe.
    let eligibleCount: Int

    /// Nothing eligible and nothing contributing: an empty period.
    static let none = MetricCoverage(contributingCount: 0, eligibleCount: 0)

    init(contributingCount: Int, eligibleCount: Int) {
        self.contributingCount = contributingCount
        self.eligibleCount = eligibleCount
    }

    /// Whether every eligible record contributed.
    ///
    /// False for an empty period: there is nothing to be complete *about*, and a
    /// caller reading "complete" over no records would be reading a claim about
    /// data that does not exist.
    var isComplete: Bool { eligibleCount > 0 && contributingCount >= eligibleCount }

    /// Whether anything contributed at all. When false there is no figure to
    /// show, only the absence.
    var hasContributors: Bool { contributingCount > 0 }

    /// Records that could have contributed and did not.
    var missingCount: Int { max(0, eligibleCount - contributingCount) }
}

// MARK: Wording

nonisolated extension MetricCoverage {
    /// The counts as the interface writes them: `"3 of 4 shifts"`.
    ///
    /// Written even when coverage is complete — `"4 of 4 shifts"` — rather than
    /// collapsing to `"4 shifts"`. The shape stays the same wherever a driver
    /// sees it, so reading it is one habit instead of two, and a complete period
    /// is stated as complete rather than being the case where the caveat quietly
    /// disappears.
    ///
    /// `noun` is supplied by the call site because the records being counted
    /// differ — shifts under a total, deliveries under a delivery subtotal, and a
    /// rate counts the shifts that had *both* of the things it divides.
    func statement(noun: String = "shift", pluralNoun: String? = nil) -> String {
        "\(contributingCount) of \(eligibleCount) \(name(for: eligibleCount, noun: noun, pluralNoun: pluralNoun))"
    }

    /// The same counts as a phrase that can be dropped into a spoken sentence:
    /// `"across 3 of 4 completed shifts"`.
    ///
    /// VoiceOver must not have to infer a denominator from a caption sitting
    /// next to the figure, so every spoken aggregate ends with one of these.
    func spokenStatement(
        preposition: String = "across",
        noun: String = "completed shift",
        pluralNoun: String? = nil
    ) -> String {
        "\(preposition) \(statement(noun: noun, pluralNoun: pluralNoun))"
    }

    private func name(for count: Int, noun: String, pluralNoun: String?) -> String {
        count == 1 ? noun : (pluralNoun ?? noun + "s")
    }
}
