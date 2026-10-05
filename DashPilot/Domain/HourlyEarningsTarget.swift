import Foundation

/// How one completed shift's gross earnings per working hour compare with the
/// target that shift recorded when it started.
///
/// ## A personal benchmark, nothing more
///
/// The target is a figure the driver chose, such as `$25.00` a working hour.
/// It is not recorded earnings, not an expectation of what a shift will pay,
/// and not a claim about what anybody should earn. This compares one derived
/// rate with it and says which side it fell on, in words that judge neither
/// the shift nor the driver: above, near, below.
///
/// ## One rate, the existing one
///
/// The rate is ``ShiftMetrics/grossPerWorkingHour``: gross earnings over the
/// shift's working hours, the figure every screen already shows. No second
/// hourly calculation exists. It is compared **at the cent it is shown at**,
/// so a shift whose rate reads `$25.00` is never called below a `$25.00`
/// target because its unrounded value was `$24.996`.
///
/// ## The neutral band
///
/// Within ``nearBand`` of the target (2 %, inclusive, so `$24.50` to `$25.50`
/// for `$25.00`) a shift is **near** its target. A few cents either way is
/// noise in a figure built from a typed total and a clock, and a label that
/// flipped between above and below on it would read as a verdict the data
/// cannot support.
///
/// ## Missing is not zero
///
/// A shift with no target, or with no rate (no earnings recorded, no working
/// time), has no comparison: ``init(rate:target:)`` returns `nil`. A target of
/// zero is never recorded, so it cannot be compared against either.
nonisolated struct HourlyTargetComparison: Equatable, Sendable {
    /// Which side of the target the shift's rate fell on.
    nonisolated enum Standing: String, Equatable, Sendable, CaseIterable {
        case above
        case near
        case below

        /// Short, neutral, and never the only signal: a symbol and the figures
        /// say it too.
        var title: String {
            switch self {
            case .above: "Above target"
            case .near: "Near target"
            case .below: "Below target"
            }
        }

        /// Distinguishes the standing without relying on colour.
        var symbolName: String {
            switch self {
            case .above: "arrow.up.right"
            case .near: "equal"
            case .below: "arrow.down.right"
            }
        }
    }

    /// How close counts as near: 2 % of the target, inclusive.
    static let nearBand = Decimal(string: "0.02")!

    /// The shift's rate as shown, to the cent.
    let rate: Money
    /// The target the shift recorded.
    let target: Money
    let standing: Standing

    /// - Returns: `nil` when either the rate or the target is missing, or the
    ///   target is not positive.
    init?(rate: Money?, target: Money?) {
        guard let rate, let target, target.amount > .zero else { return nil }
        self.rate = rate.rounded()
        self.target = target.rounded()
        let band = (self.target.amount * Self.nearBand)
        let difference = self.rate.amount - self.target.amount
        if difference > band {
            standing = .above
        } else if difference < -band {
            standing = .below
        } else {
            standing = .near
        }
    }

    /// The rate less the target, to the cent. Negative below it.
    var difference: Money { rate - target }

    /// The rate as a whole percentage of the target, rounded half up.
    var percentOfTarget: Int {
        var ratio = rate.amount / target.amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// `$2.42/hr above your $25.00 target`, `87% of your $25.00 target`, or
    /// `Within 2% of your $25.00 target`: one line, under the rate it is about.
    func statement(locale: Locale = .autoupdatingCurrent) -> String {
        let targetText = target.formatted(locale: locale)
        switch standing {
        case .above:
            return "\(difference.formatted(locale: locale))/hr above your \(targetText) target"
        case .near:
            return "Within 2% of your \(targetText) target"
        case .below:
            return "\(percentOfTarget)% of your \(targetText) target"
        }
    }

    /// The same, said in full for VoiceOver.
    func spokenStatement(locale: Locale = .autoupdatingCurrent) -> String {
        let targetText = target.formatted(locale: locale)
        switch standing {
        case .above:
            return "\(standing.title). \(difference.formatted(locale: locale)) an hour above your target of \(targetText) a working hour"
        case .near:
            return "\(standing.title). Within 2 percent of your target of \(targetText) a working hour"
        case .below:
            return "\(standing.title). \(percentOfTarget) percent of your target of \(targetText) a working hour"
        }
    }
}

/// How the shifts of one period stood against the targets each recorded.
///
/// A count, not an average: each shift is compared with **its own** target,
/// which is the one it started with, so a period whose shifts carry different
/// targets is still answered truthfully. Averaging rates against an averaged
/// target would be a figure nobody chose.
///
/// Coverage is part of it. Shifts with no target, and shifts with a target but
/// no rate, are counted apart rather than read as missed.
nonisolated struct PeriodHourlyTargetSummary: Equatable, Sendable {
    /// Completed shifts in the period that recorded a target.
    let withTarget: Int
    /// Of those, the ones with a rate to compare.
    let compared: Int
    /// Of those, the ones above or near their own target.
    let atOrAbove: Int

    static let none = PeriodHourlyTargetSummary(withTarget: 0, compared: 0, atOrAbove: 0)

    /// Builds the count from each shift's rate and recorded target.
    init(pairs: [(rate: Money?, target: Money?)]) {
        let targeted = pairs.filter { $0.target.map { $0.amount > .zero } == true }
        let comparisons = targeted.compactMap { HourlyTargetComparison(rate: $0.rate, target: $0.target) }
        withTarget = targeted.count
        compared = comparisons.count
        atOrAbove = comparisons.filter { $0.standing != .below }.count
    }

    init(withTarget: Int, compared: Int, atOrAbove: Int) {
        self.withTarget = withTarget
        self.compared = compared
        self.atOrAbove = atOrAbove
    }

    /// Whether there is anything to say. A period with no targeted shift says
    /// nothing at all about targets.
    var hasTargets: Bool { withTarget > 0 }

    /// `At or near target on 8 of 12 shifts`, plus the shifts that had a target
    /// but no rate, or `nil` when no shift had a target.
    var statement: String? {
        guard hasTargets else { return nil }
        guard compared > 0 else {
            return withTarget == 1
                ? "1 shift had a target but no rate to compare"
                : "\(withTarget) shifts had a target but no rate to compare"
        }
        var line = "At or near target on \(atOrAbove) of \(compared) \(compared == 1 ? "shift" : "shifts")"
        let unrated = withTarget - compared
        if unrated > 0 {
            line += " · \(unrated) without a rate"
        }
        return line
    }

    /// The same for VoiceOver, with the coverage said as a sentence.
    var spokenStatement: String? {
        guard let statement else { return nil }
        return statement.replacingOccurrences(of: " · ", with: ". ")
            + ". Each shift is compared with the target it recorded when it started"
    }
}

extension Shift {
    /// This shift's gross earnings per working hour against the target it
    /// recorded when it started, or `nil` when either is missing.
    ///
    /// The rate is ``ShiftMetrics/grossPerWorkingHour`` over the distance the
    /// caller already measured, so there is one hourly calculation in the app.
    func hourlyTargetComparison(for recordedDistance: RouteDistance) -> HourlyTargetComparison? {
        guard let target = hourlyTarget else { return nil }
        return HourlyTargetComparison(rate: metrics(for: recordedDistance).grossPerWorkingHour.amount, target: target)
    }
}

