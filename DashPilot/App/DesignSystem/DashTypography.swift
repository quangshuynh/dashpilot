import SwiftUI

/// The text roles DashPilot's shift screens are written in.
///
/// ## Roles, not sizes
///
/// Each role is a system text style plus a weight, so every one of them scales
/// with the driver's Dynamic Type setting and nothing here names a point size.
/// A view asks for `metricHero` or `supporting`, never for "34 point semibold",
/// which is what lets the whole app move together when a role changes.
///
/// ## Numbers
///
/// The metric roles are for figures that change while a driver watches them:
/// working time, mileage, a delivery's clock. Apply `.monospacedDigit()` beside
/// them, which asks for tabular figures so a changing value does not shuffle
/// sideways. Ordinary text stays proportional.
enum DashTypography {
    /// The one figure a panel leads with.
    static let metricHero = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    /// A figure in a row of figures under the hero.
    static let metric = Font.system(.title3, design: .rounded, weight: .semibold)
    /// What a figure is, under it.
    static let metricLabel = Font.caption
    /// A panel's heading line.
    static let title = Font.title3.weight(.semibold)
    /// The state a shift or a delivery is in.
    static let status = Font.subheadline.weight(.semibold)
    /// An ordinary line of a panel.
    static let body = Font.subheadline
    /// A quieter line under it.
    static let supporting = Font.caption
}
