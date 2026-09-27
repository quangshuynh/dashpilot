import Foundation
import Testing
@testable import DashPilot

/// The period summary's section footers: shorter, and still carrying every
/// qualification whose removal would let a figure be read as something it is
/// not.
///
/// The qualifications that sit **beside** their figures (coverage, a rate's
/// paired subset, a partial route, the net's caution, the waits Park recorded)
/// are pinned by the suites of the statements that say them; this pins what
/// stays in the footers, and that the footers stay short.
@Suite("Period summary explanations")
struct PeriodSummaryExplanationTests {
    private var every: [String] {
        [
            PeriodSummaryExplanation.summary(periodNoun: "week"),
            PeriodSummaryExplanation.earnings(hasShiftsWithoutAmount: true, zero: "$0.00"),
            PeriodSummaryExplanation.expenses,
            PeriodSummaryExplanation.driving,
            PeriodSummaryExplanation.deliveries,
            PeriodSummaryExplanation.estimatedFuel,
            PeriodSummaryExplanation.export(periodNoun: "week")
        ]
    }

    private func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    @Test("Every footer is short enough not to bury the figures at large text sizes")
    func footersAreShort() {
        for footer in every {
            #expect(words(footer) <= 40, "\(words(footer)) words: \(footer)")
        }
        // The seven were 521 words together before they were audited.
        #expect(every.map(words).reduce(0, +) <= 220)
    }

    @Test("The summary says which shifts count, and that non-delivery time is not idle")
    func summaryQualifications() {
        let text = PeriodSummaryExplanation.summary(periodNoun: "week")
        #expect(text.contains("Completed shifts only"))
        #expect(text.contains("in the week it started"))
        #expect(text.contains("leaves out pauses"))
        #expect(text.contains("overlapping deliveries once"))
        #expect(text.contains("not idle time"))
    }

    @Test("Earnings are recorded and gross, delivery amounts are apart, and a missing amount is not zero")
    func earningsQualifications() {
        let partial = PeriodSummaryExplanation.earnings(hasShiftsWithoutAmount: true, zero: "$0.00")
        #expect(partial.contains("recorded"))
        #expect(partial.contains("before any cost"))
        #expect(partial.contains("not added in"))
        #expect(partial.contains("not counted as $0.00"))
        #expect(partial.contains("only shifts that recorded both of its parts"))

        let complete = PeriodSummaryExplanation.earnings(hasShiftsWithoutAmount: false, zero: "$0.00")
        #expect(!complete.contains("$0.00"), "No sentence about a gap the period does not have")
    }

    @Test("Expenses are what was entered, and anything not entered is missing rather than nothing")
    func expensesQualifications() {
        #expect(PeriodSummaryExplanation.expenses.contains("Only what you entered"))
        #expect(PeriodSummaryExplanation.expenses.contains("not counted as nothing"))
    }

    @Test("Miles are recorded, not driven, and no measured route is not zero miles")
    func drivingQualifications() {
        #expect(PeriodSummaryExplanation.driving.contains("not all the miles driven"))
        #expect(PeriodSummaryExplanation.driving.contains("no distance, not zero miles"))
    }

    @Test("Outcomes are apart, the wait predicts nothing, and two amounts are not a shortfall")
    func deliveriesQualifications() {
        let text = PeriodSummaryExplanation.deliveries
        #expect(text.contains("counted apart"))
        #expect(text.contains("predicts nothing"))
        #expect(text.contains("not a shortfall"))
    }

    @Test("The fuel figure is an estimate, never an expense, and may overlap one")
    func estimatedFuelQualifications() {
        let text = PeriodSummaryExplanation.estimatedFuel
        #expect(text.contains("An estimate, not a recorded cost"))
        #expect(text.contains("never added to your expenses"))
        #expect(text.contains("may be the same fuel"))
    }

    @Test("The export names what it holds and that positions are left out")
    func exportQualifications() {
        let text = PeriodSummaryExplanation.export(periodNoun: "day")
        #expect(text.contains("this day's"))
        #expect(text.contains("Recorded positions are not included"))
    }

    @Test("No footer uses an em dash")
    func noEmDashes() {
        for footer in every {
            #expect(!footer.contains("\u{2014}"), "\(footer)")
        }
    }
}
