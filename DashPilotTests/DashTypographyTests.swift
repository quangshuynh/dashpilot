import CoreText
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DashPilot

/// The bundled typeface is really registered, really tabular where it has to
/// be, and was added without disturbing anything else the app declares.
///
/// Font integration fails silently: a misspelled `UIAppFonts` entry or a
/// PostScript name that differs from the file name renders the system font
/// with no warning, and a hand-edited `Info.plist` can lose an unrelated key on
/// the way. These run in the app's own process, so they read the bundle and the
/// registration the app actually launches with.
@MainActor
@Suite("Dash typography")
struct DashTypographyTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test("Every bundled weight registers under the PostScript name the roles use")
    func everyWeightRegisters() {
        for weight in DashTypography.Weight.allCases {
            #expect(DashTypography.isAvailable(weight), "\(weight.postScriptName) did not register")
            #expect(UIFont(name: weight.postScriptName, size: 17)?.familyName == "Manrope")
        }
    }

    @Test("Every UIAppFonts entry is a file in the bundle, and only Manrope is declared")
    func declaredFontsExist() throws {
        let fonts = try #require(info["UIAppFonts"] as? [String])
        #expect(fonts.count == DashTypography.Weight.allCases.count)
        for file in fonts {
            #expect(file.hasPrefix("Manrope-") && file.hasSuffix(".ttf"), "Unexpected entry \(file)")
            let name = (file as NSString).deletingPathExtension
            #expect(Bundle.main.url(forResource: name, withExtension: "ttf") != nil, "\(file) is not in the bundle")
        }
    }

    @Test("Adding the fonts left the keys this plist exists for in place")
    func unrelatedKeysSurvive() {
        #expect(info["NSSupportsLiveActivities"] as? Bool == true)
        #expect(info["UIBackgroundModes"] as? [String] == ["location"])
    }

    /// A ticking clock must not move sideways, which needs the face's tabular
    /// figures rather than its proportional ones.
    @Test("Every weight has tabular figures, so a changing value keeps its width")
    func figuresAreTabularOnRequest() throws {
        for weight in DashTypography.Weight.allCases {
            let base = try #require(UIFont(name: weight.postScriptName, size: 34))
            let tabular = UIFont(
                descriptor: base.fontDescriptor.addingAttributes([
                    .featureSettings: [[
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                    ]]
                ]),
                size: 34
            )
            let widths = ["1", "4", "8"].map { ($0 as NSString).size(withAttributes: [.font: tabular]).width }
            #expect(Set(widths.map { ($0 * 100).rounded() }).count == 1, "\(weight.postScriptName) figures differ: \(widths)")

            let proportional = ["1", "8"].map { ($0 as NSString).size(withAttributes: [.font: base]).width }
            #expect(proportional[0] != proportional[1], "The default figures are proportional, so the request matters")
        }
    }

    @Test("Only the changing figures ask for tabular digits")
    func tabularIsForMetricsOnly() {
        let tabular = DashTypography.Role.allCases.filter(\.usesTabularFigures)
        #expect(tabular == [.metricHero, .metric])
    }

    @Test("Bold Text moves each role one weight heavier, and bold stays bold")
    func boldTextIsHeavier() {
        #expect(DashTypography.Weight.regular.heavier == .medium)
        #expect(DashTypography.Weight.medium.heavier == .semibold)
        #expect(DashTypography.Weight.semibold.heavier == .bold)
        #expect(DashTypography.Weight.bold.heavier == .bold)
    }

    @Test("Roles are anchored to text styles, so they scale with Dynamic Type")
    func rolesFollowTextStyles() {
        #expect(DashTypography.Role.metricHero.textStyle == .largeTitle)
        #expect(DashTypography.Role.supporting.textStyle == .caption)
        for role in DashTypography.Role.allCases {
            #expect(DashTypography.baseSize(of: role.textStyle) > 0)
        }
    }
}
