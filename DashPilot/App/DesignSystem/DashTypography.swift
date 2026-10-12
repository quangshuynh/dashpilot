import SwiftUI

/// Semantic SF Pro roles shared by the existing screens. Operational figures
/// use condensed tabular digits; financial headlines use open-width tabular
/// digits. Words stay proportional. Every role follows Dynamic Type without
/// a bundled font or fixed point size.
enum DashTypography {
    enum Role: CaseIterable {
        /// The one figure a panel leads with.
        case metricHero
        /// A recorded financial headline: open width, precise tabular figures.
        case financialHero
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
            case .metricHero, .financialHero: .largeTitle
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
            case .financialHero: .semibold
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

        /// Only operational figures use the compact instrument width.
        var width: Font.Width {
            self == .metricHero || self == .metric ? .condensed : .standard
        }

        /// Keep monetary columns and changing timers aligned.
        var usesTabularFigures: Bool { isFigure }

        private var isFigure: Bool {
            switch self {
            case .metricHero, .financialHero, .metric: true
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
