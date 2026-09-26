import SwiftUI
import UIKit

/// The text roles DashPilot's shift screens are written in, set in Manrope.
///
/// ## Why Manrope, and only Manrope
///
/// Four families were set side by side on the running shift's own content
/// (the working clock, a row of figures, a delivery's state line, a vehicle
/// line) at the default size and the largest accessibility size. Manrope's
/// tabular figures hold a ticking clock still, its five weights give a figure
/// and its caption enough contrast without a second family, and it stays
/// readable at caption size. Space Grotesk was tried for the large figures and
/// its tabular one, flagged and heavy, made the clock read oddly; DM Sans's
/// figures are proportional, so a live value would shuffle sideways; IBM Plex
/// Sans reads best at small sizes but runs wide enough to crowd a row of
/// figures. One family is the whole system.
///
/// ## Roles, not sizes
///
/// Each role is a system text style and a weight. The face is sized with
/// `relativeTo:` that style, so it scales with the driver's Dynamic Type
/// setting exactly as the system font would, and nothing outside this file
/// names a point size. Views write `.dashFont(.metricHero)`.
///
/// ## When the face is missing, and when the driver asks for bold
///
/// A face that failed to register (a renamed file, a stripped bundle) falls
/// back to the system font in the same text style and weight, so the screen
/// degrades to what it was rather than rendering a missing glyph. And because a
/// custom face does not follow the system's Bold Text setting by itself, the
/// modifier reads `legibilityWeight` and moves each role one weight heavier.
///
/// ## Numbers
///
/// The metric roles are for figures that change while a driver watches them.
/// ``DashFontModifier`` asks for tabular figures on those roles only, so a
/// ticking value does not move sideways while ordinary text stays proportional.
enum DashTypography {
    enum Role: CaseIterable {
        /// The one figure a panel leads with.
        case metricHero
        /// A figure in a row of figures under the hero.
        case metric
        /// What a figure is, under it.
        case metricLabel
        /// A panel's heading line.
        case title
        /// The state a shift or a delivery is in.
        case status
        /// An ordinary line of a panel.
        case body
        /// An ordinary line that has to stand out from its neighbours.
        case emphasis
        /// A quieter line under it.
        case supporting

        var textStyle: Font.TextStyle {
            switch self {
            case .metricHero: .largeTitle
            case .metric: .title3
            case .metricLabel: .caption
            case .title: .title3
            case .status: .subheadline
            case .body: .subheadline
            case .emphasis: .subheadline
            case .supporting: .caption
            }
        }

        var weight: Weight {
            switch self {
            case .metricHero: .bold
            case .metric: .bold
            case .metricLabel: .medium
            case .title: .bold
            case .status: .semibold
            case .body: .regular
            case .emphasis: .semibold
            case .supporting: .regular
            }
        }

        /// Figures that change while a driver watches them.
        var usesTabularFigures: Bool {
            switch self {
            case .metricHero, .metric: true
            default: false
            }
        }
    }

    /// The weights bundled, and the PostScript name of each.
    enum Weight: Int, CaseIterable, Comparable {
        case regular, medium, semibold, bold

        var postScriptName: String {
            switch self {
            case .regular: "Manrope-Regular"
            case .medium: "Manrope-Medium"
            case .semibold: "Manrope-SemiBold"
            case .bold: "Manrope-Bold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }

        /// One step heavier, for the Bold Text setting. Bold is the heaviest
        /// face bundled, so it stays bold.
        var heavier: Weight { Weight(rawValue: rawValue + 1) ?? .bold }

        static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The size each text style has at the default content size. The face is
    /// scaled from here by `relativeTo:`, so these are anchors, not sizes.
    static func baseSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    /// Whether a bundled face registered under its PostScript name.
    static func isAvailable(_ weight: Weight) -> Bool {
        UIFont(name: weight.postScriptName, size: 12) != nil
    }

    /// The font for a role, Manrope where it loaded and the system face in the
    /// same style and weight where it did not.
    static func font(_ role: Role, bold: Bool = false) -> Font {
        let weight = bold ? role.weight.heavier : role.weight
        let style = role.textStyle
        guard isAvailable(weight) else {
            return Font.system(style).weight(weight.systemWeight)
        }
        return Font.custom(weight.postScriptName, size: baseSize(of: style), relativeTo: style)
    }
}

/// Applies a role, following the Bold Text setting and asking for tabular
/// figures where the role holds a changing number.
struct DashFontModifier: ViewModifier {
    let role: DashTypography.Role

    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        let font = DashTypography.font(role, bold: legibilityWeight == .bold)
        if role.usesTabularFigures {
            content.font(font).monospacedDigit()
        } else {
            content.font(font)
        }
    }
}

extension View {
    /// Sets this view's text in one of DashPilot's roles.
    func dashFont(_ role: DashTypography.Role) -> some View {
        modifier(DashFontModifier(role: role))
    }
}
