import SwiftUI

/// DashPilot's visual rules, in the handful of places they are stable enough to
/// name.
///
/// ## What this is, and what it deliberately is not
///
/// A small vocabulary, not a framework. The app is built from ordinary SwiftUI:
/// `List` sections are its surfaces, system button styles are its controls, and
/// semantic colours carry light and dark mode. What had drifted was the numbers
/// between them (padding of 10 in one card and 12 in the next, radii of 10 and
/// 12, spacings picked per view), and the one question every screen has to
/// answer the same way: which figure is the headline, and what is quieter.
///
/// So this holds a spacing scale, one radius, one inset-surface treatment, and a
/// status vocabulary that never relies on colour alone. Typography lives beside
/// it in ``DashTypography``. Nothing here hides composition: a view still reads
/// as a `VStack` of `Text`s with modifiers on them.
///
/// ## Colour
///
/// Deliberately **not** a brand palette. The accent is the system's, so the app
/// follows the driver's settings and keeps its contrast in both modes; the only
/// hues named here are the semantic ones a state already had (recording, paused,
/// parked, destructive), and each of them travels with a symbol and a word.
enum DashSpacing {
    /// Between a figure and the caption that qualifies it.
    static let xs: CGFloat = 2
    /// Between lines of one group.
    static let sm: CGFloat = 4
    /// Between groups inside one surface.
    static let md: CGFloat = 8
    /// Between blocks of a panel.
    static let lg: CGFloat = 12
    /// Between the major regions of a panel.
    static let xl: CGFloat = 16
}

enum DashRadius {
    /// The one corner radius for an inset surface inside a list row.
    static let surface: CGFloat = 12
}

extension View {
    /// An inset surface inside a list row: the undo offer, a reminder.
    ///
    /// Used sparingly, and never nested. A list section is already a surface,
    /// so this is for the one thing inside it that has to read as set apart,
    /// not for every group of lines.
    func dashInsetSurface() -> some View {
        padding(DashSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: DashRadius.surface))
    }
}

/// The state a thing is in, said with a symbol, a word and a tint, in that
/// order of importance.
///
/// A tint alone is unreadable in bright sun and to a driver who does not see
/// it, so every state here has its own symbol and its own title. The tint is
/// the third signal, never the first.
struct DashStatusLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .font(DashTypography.status)
    }
}
