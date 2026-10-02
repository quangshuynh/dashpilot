import SwiftUI

/// The text roles every DashPilot screen is written in, set in the system face.
///
/// ## Why the system face
///
/// Manrope, bundled before, and the system face were set side by side on
/// DashPilot's own content (earnings, an hourly rate, a ticking clock, a
/// delivery's title and state, a Settings explanation, a week's summary line, a
/// delivery card at the largest accessibility size). The system face's tabular
/// figures are tighter (Manrope's tabular one leaves gaps around each `1` in a
/// clock), it follows Bold Text and Dynamic Type natively, it is the face the
/// Live Activity already uses, and its condensed width sets a figure about a
/// fifth narrower without bundling anything. See `docs/development/design-system.md`.
///
/// The app therefore bundles no font, and nothing here can fail to load.
///
/// ## Roles, not sizes
///
/// Each role is a system text style, a weight and, for figures, a width.
/// Nothing outside this file names a point size. Views write
/// `.dashFont(.metricHero)`.
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
        /// A short label above a group, such as `Next`.
        case eyebrow
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
        /// The title of a large action button.
        case control

        var textStyle: Font.TextStyle {
            switch self {
            case .metricHero: .largeTitle
            case .metric: .title3
            case .metricLabel: .footnote
            case .eyebrow: .footnote
            case .title: .title3
            case .status: .subheadline
            case .body: .subheadline
            case .emphasis: .subheadline
            case .supporting: .caption
            case .control: .headline
            }
        }

        var weight: Font.Weight {
            switch self {
            case .metricHero: .bold
            case .metric: .semibold
            case .metricLabel: .medium
            case .eyebrow: .semibold
            case .title: .bold
            case .status: .semibold
            case .body: .regular
            case .emphasis: .semibold
            case .supporting: .regular
            case .control: .semibold
            }
        }

        /// Figures are set condensed: denser, and read like an instrument.
        /// Words never are.
        var width: Font.Width {
            isFigure ? .condensed : .standard
        }

        /// Figures that change while a driver watches them.
        var usesTabularFigures: Bool { isFigure }

        private var isFigure: Bool {
            switch self {
            case .metricHero, .metric: true
            default: false
            }
        }
    }

    /// The font for a role. The system face follows the driver's Dynamic Type
    /// and Bold Text settings by itself.
    static func font(_ role: Role) -> Font {
        Font.system(role.textStyle).weight(role.weight).width(role.width)
    }
}

/// Applies a role, asking for tabular figures where the role holds a changing
/// number.
struct DashFontModifier: ViewModifier {
    let role: DashTypography.Role

    func body(content: Content) -> some View {
        let font = DashTypography.font(role)
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
