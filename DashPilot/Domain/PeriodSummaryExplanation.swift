import Foundation

/// The explanation under each section of a period summary.
///
/// ## Why it lives here, and why it is short
///
/// At the largest text sizes a section footer is several screens of prose, and
/// on a period summary every section has one, so the figures a driver opened
/// the screen for sat under a manual. Measured at the largest accessibility
/// size by `testThePeriodSummarySurvivesTheLargestTextSize`, the pickup wait
/// took 16 swipes to reach and the estimated fuel 20; with these footers and
/// the two shortened sentences beside the net and the partial route, 11 and 14.
///
/// Each footer was audited sentence by sentence and every sentence kept one of
/// three places:
///
/// 1. **Beside its figure**, where a qualification would make the figure
///    misleading if it were missing: partial coverage, a rate's paired subset,
///    a partial route, the net's caution, the waits Park recorded, an estimate
///    being an estimate. Those are in each row's own detail and spoken label
///    already, and are not repeated here.
/// 2. **Here, shorter**: what a figure means and what it is not, in the fewest
///    words that keep the meaning. Every sentence the tests below pin is one
///    whose removal would let a figure be read as something it is not.
/// 3. **In the documentation only**: methodology such as how an overnight shift
///    is assigned in detail, how gaps are detected, and how the export is laid
///    out, which `docs/product/period-summaries.md` already describes.
///
/// Wording lives beside the metrics rather than in the view for the reason
/// ``PickupWaitMetrics``' does: the failure mode is a claim, not a crash.
nonisolated enum PeriodSummaryExplanation {
    /// Under the shift count and the three durations.
    static func summary(periodNoun: String) -> String {
        """
        Completed shifts only, each in the \(periodNoun) it started. Working time leaves out pauses. \
        Delivery active time counts overlapping deliveries once. Non-delivery time is the rest, and \
        is not idle time.
        """
    }

    /// Under the earnings headline and its two rates.
    ///
    /// The sentence about a shift with no amount appears only when the period
    /// has one, because it describes a gap this period actually has.
    static func earnings(hasShiftsWithoutAmount: Bool, zero: String) -> String {
        var sentences = [
            """
            Amounts you recorded on these shifts, before any cost. Delivery amounts are separate and \
            not added in.
            """
        ]
        if hasShiftsWithoutAmount {
            sentences.append("A shift with no amount is left out, not counted as \(zero).")
        }
        sentences.append("Each rate uses only shifts that recorded both of its parts.")
        return sentences.joined(separator: " ")
    }

    /// Under the recorded expenses and the net after them. The net's own
    /// caution (not profit, not a tax figure) is beside the net, not here.
    static let expenses = """
        Only what you entered, by its own date and tied to no shift. Anything not entered is \
        missing, not counted as nothing.
        """

    /// Under the recorded miles. A partial route's consequence is beside the
    /// miles whenever the period has one.
    static let driving = """
        Recorded miles are what the routes measured, not all the miles driven. A shift with no \
        measured route adds no distance, not zero miles.
        """

    /// Under the delivery counts, the pickup wait and the delivery amounts.
    static let deliveries = """
        Delivered and cancelled are counted apart. The wait is the median of this period's pickups \
        and predicts nothing. Delivery amounts are separate from shift amounts, and a difference \
        between them is not a shortfall.
        """

    /// Under the estimated fuel and the estimated net.
    static let estimatedFuel = """
        Each shift's recorded miles over its recorded miles per gallon, at its recorded gas price. \
        An estimate, not a recorded cost: never added to your expenses, and a fuel purchase entered \
        there may be the same fuel.
        """

    /// Under the export control.
    static func export(periodNoun: String) -> String {
        """
        Saves this \(periodNoun)'s shifts, deliveries, expenses and summary, with the count behind \
        each figure. The CSV has shifts and deliveries only. Recorded positions are not included.
        """
    }
}
