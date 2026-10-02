import CoreText
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DashPilot

/// The text roles: figures condensed and tabular, words standard and
/// proportional, every role anchored to a Dynamic Type style.
///
/// The roles are set in the system face, so there is no registration to
/// check. What can still go wrong silently is a figure role losing its tabular
/// digits (a ticking clock then moves sideways) or a word role gaining the
/// condensed width meant for figures, and those are what these pin.
@MainActor
@Suite("Dash typography")
struct DashTypographyTests {
    @Test("Only the changing figures ask for tabular digits")
    func tabularIsForMetricsOnly() {
        let tabular = DashTypography.Role.allCases.filter(\.usesTabularFigures)
        #expect(tabular == [.metricHero, .metric])
    }

    @Test("Figures are condensed and words are not")
    func onlyFiguresAreCondensed() {
        for role in DashTypography.Role.allCases {
            #expect((role.width == .condensed) == role.usesTabularFigures, "\(role)")
        }
    }

    /// The condensed system face, asked for its tabular figures, gives every
    /// digit one width, which is what keeps `1:11:11` and `8:08:08` the same
    /// length while the working clock ticks.
    @Test("The condensed figures are tabular on request, so a changing value keeps its width")
    func condensedFiguresAreTabularOnRequest() {
        for weight in [UIFont.Weight.bold, .semibold] {
            let base = UIFont.systemFont(ofSize: 34, weight: weight, width: .condensed)
            let tabular = UIFont(
                descriptor: base.fontDescriptor.addingAttributes([
                    .featureSettings: [[
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                    ]]
                ]),
                size: 34
            )
            let widths = (0...9).map { ("\($0)" as NSString).size(withAttributes: [.font: tabular]).width }
            #expect(Set(widths.map { ($0 * 100).rounded() }).count == 1, "Digits differ: \(widths)")

            let clocks = ["1:11:11", "8:08:08"].map { ($0 as NSString).size(withAttributes: [.font: tabular]).width }
            #expect(abs(clocks[0] - clocks[1]) < 0.01, "A ticking clock would move: \(clocks)")
        }
    }

    /// Measured on DashPilot's own figures: the condensed width is the reason
    /// for choosing it, so it must stay narrower than the standard one.
    @Test("A condensed figure is narrower than the same figure set standard")
    func condensedFiguresAreNarrower() {
        for figure in ["$127.43", "$24.61/hr", "3h 48m", "1:30:04"] {
            let standard = (figure as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold)])
            let condensed = (figure as NSString).size(
                withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold, width: .condensed)]
            )
            #expect(condensed.width < standard.width * 0.9, "\(figure): \(condensed.width) vs \(standard.width)")
        }
    }

    @Test("Roles are anchored to text styles, so they scale with Dynamic Type")
    func rolesFollowTextStyles() {
        #expect(DashTypography.Role.metricHero.textStyle == .largeTitle)
        #expect(DashTypography.Role.metricLabel.textStyle == .footnote)
        #expect(DashTypography.Role.supporting.textStyle == .caption)
        #expect(DashTypography.Role.control.textStyle == .headline)
    }

    /// A figure is heavier than the label under it, and a label is never the
    /// thinnest weight: the small label has to stay legible beside a heavy
    /// figure.
    @Test("A figure outweighs its label, and labels are medium")
    func figuresOutweighLabels() {
        #expect(DashTypography.Role.metricHero.weight == .bold)
        #expect(DashTypography.Role.metric.weight == .semibold)
        #expect(DashTypography.Role.metricLabel.weight == .medium)
    }
}
