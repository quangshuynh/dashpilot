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
        .dashFont(.status)
        // One element: a listener hears the state once, and nothing can
        // address the symbol apart from the words it belongs to.
        .accessibilityElement(children: .combine)
    }
}

/// One figure and what it is: the value above, its name under it, and an
/// optional qualifier under that.
///
/// The value is never a placeholder. Where a figure does not exist the caller
/// passes the sentence that says so, which is drawn in the quieter body role
/// rather than the metric one, so an absence never reads with the weight of a
/// number.
struct DashMetric: View {
    /// How much weight a figure carries: the one a surface leads with, or one
    /// of the figures under it.
    enum Emphasis {
        case hero
        case standard

        var role: DashTypography.Role {
            switch self {
            case .hero: .metricHero
            case .standard: .metric
            }
        }
    }

    let value: String
    let label: String
    var detail: String?
    /// `false` where ``value`` is a sentence standing in for a missing figure.
    var isFigure = true
    var emphasis: Emphasis = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            Text(value)
                .dashFont(isFigure ? emphasis.role : .body)
                .foregroundStyle(isFigure ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .dashFont(.metricLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One secondary figure: what it is beside what it says, and what is behind it
/// under both.
///
/// For the figures under a surface's headline, where a ``DashMetric`` would give
/// every line the same weight. The title and the value share a line where they
/// fit and stack where they do not, and always stack at accessibility sizes,
/// because a shortened title beside a shortened figure is worse than a second
/// line and the first thing a truncation takes is the word that makes a figure
/// honest. Nothing shrinks to fit.
///
/// Where the figure does not exist the caller passes the words that say so and
/// `isFigure: false`, which draws them in the quieter colour rather than with
/// the weight of a number.
struct DashValueRow: View {
    let title: String
    let value: String
    var detail: String?
    var isFigure = true
    /// Draws the value in the emphasis role: the result a group of lines
    /// arrives at, such as the net at the foot of a ledger.
    var isProminent = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                titleText
                valueText
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
                        titleText
                        Spacer(minLength: DashSpacing.md)
                        valueText.multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: DashSpacing.xs) {
                        titleText
                        valueText
                    }
                }
            }
            if let detail {
                Text(detail)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(title)
            .dashFont(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .dashFont(isProminent ? .emphasis : .body)
            .monospacedDigit()
            .foregroundStyle(isFigure ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What a surface says when it has nothing to show, or when a figure cannot
/// be worked out: a short title, an explanation, and nothing decorative.
///
/// One vocabulary for every empty, missing and unavailable state, so a driver
/// learns once what "nothing here" looks like and never mistakes it for a
/// figure. The title says what is absent, the message says why or what would
/// change it, and an action, where one is useful, is the caller's own control
/// placed after this rather than folded into it. No illustration and no asset:
/// the words are the state.
///
/// One accessibility element, so a listener hears the absence as one statement
/// rather than a heading and a caption that might belong to different things.
struct DashNotice: View {
    let title: String
    var message: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text(title)
                    .dashFont(.emphasis)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.map { "\(title). \($0)" } ?? title)
    }
}

/// Why what was typed could not be saved, said in words beside a warning
/// symbol.
///
/// The symbol is hidden from assistive technologies and the identifier is on
/// the sentence alone. A SwiftUI `Label` mirrors its identifier onto its icon,
/// whose own label is "Warning", and which of the two a query met first was
/// decided by the runtime's accessibility tree: that is how a journey read
/// "Warning" in CI and the sentence locally. Here there is one element to find,
/// and it is the sentence a listener hears. Red is the third signal after the
/// symbol and the words, never the only one.
struct DashValidationMessage: View {
    let message: String
    let identifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .dashFont(.body)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of figures that becomes a column when it cannot hold them.
///
/// At accessibility sizes it is always a column, because three figures at the
/// largest sizes truncate each other (`$2 7....` was the measured result). At
/// ordinary sizes it is a row where the row fits and a column where it does
/// not, so a long localized figure never squeezes its neighbours.
struct DashMetricRow<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DashSpacing.lg) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DashSpacing.lg) { content }
                VStack(alignment: .leading, spacing: DashSpacing.lg) { content }
            }
        }
    }
}
