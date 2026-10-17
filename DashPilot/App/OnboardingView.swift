import SwiftUI

/// DashPilot's welcome: four short screens a new driver reads once, and anyone
/// can reopen from Settings.
///
/// ## What it says, and what it does not do
///
/// What DashPilot records, what that adds up to, how it keeps out of the way
/// while driving, and that the record stays on the phone. It asks for nothing:
/// no permission prompt is raised here, because each one is asked for where the
/// capability is used (location when a shift is started from the panel that
/// explains it). Finishing writes one flag, ``OnboardingRecord``, and nothing
/// in the store.
///
/// ## Accessibility
///
/// The words carry everything; each illustration is decorative and hidden from
/// VoiceOver, and shrinks at accessibility sizes so the text keeps the room.
/// Every page scrolls, so nothing is clipped at any size. The step is said in
/// words (`Step 2 of 4`), not only by dots. Controls are at least 44 points,
/// the primary one 50. A page change moves VoiceOver to the new title, and
/// happens without animation under Reduce Motion.
struct OnboardingView: View {
    /// Where the welcome was opened from, which decides only the last button's
    /// words.
    enum Context {
        /// The first launch.
        case firstLaunch
        /// Reopened from Settings.
        case revisit
    }

    let context: Context
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var page = 0
    @AccessibilityFocusState private var focusedTitle: Int?

    private let pages = OnboardingPage.all

    var body: some View {
        TabView(selection: $page) {
            ForEach(pages.indices, id: \.self) { index in
                pageView(pages[index], index: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(OnboardingPalette.background.ignoresSafeArea())
        // Its own row rather than a navigation bar item, whose control is
        // drawn 36 points tall: this one is a full 44.
        .safeAreaInset(edge: .top) { topRow }
        .safeAreaInset(edge: .bottom) { controls }
        .onChange(of: page) { _, newPage in focusedTitle = newPage }
    }

    /// Skip (or Close, when reopened), on every screen but the last, which
    /// has its own way out.
    private var topRow: some View {
        HStack {
            Spacer()
            if page < pages.count - 1 {
                Button(context == .firstLaunch ? "Skip" : "Close", action: finish)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityHint("Closes the welcome. It can be opened again from Settings.")
                    .accessibilityIdentifier("skipOnboardingButton")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, DashSpacing.lg)
        .background(OnboardingPalette.background)
    }

    private func pageView(_ content: OnboardingPage, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashSpacing.xxl) {
                Image(content.artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: dynamicTypeSize.isAccessibilitySize ? 120 : 220)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DashSpacing.lg) {
                    Text(content.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedTitle, equals: index)
                        .accessibilityIdentifier("onboardingTitle")
                    Text(content.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !content.points.isEmpty {
                    VStack(alignment: .leading, spacing: DashSpacing.lg) {
                        ForEach(content.points) { point in
                            Label {
                                Text(point.text)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: point.symbol)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(minWidth: 28)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DashSpacing.xxl)
            .padding(.top, DashSpacing.md)
            .padding(.bottom, DashSpacing.xxl)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// The step in words, the step as dots, then Back and the primary action.
    private var controls: some View {
        VStack(spacing: DashSpacing.lg) {
            HStack(spacing: DashSpacing.md) {
                Text("Step \(page + 1) of \(pages.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboardingStep")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DashSpacing.sm) {
                    primaryButton
                    backButton
                }
            } else {
                HStack(spacing: DashSpacing.lg) {
                    backButton
                    primaryButton
                }
            }
        }
        .padding(.horizontal, DashSpacing.xxl)
        .padding(.vertical, DashSpacing.lg)
        .background(OnboardingPalette.background)
    }

    @ViewBuilder
    private var backButton: some View {
        if page > 0 {
            Button("Back") { move(to: page - 1) }
                .font(.body.weight(.semibold))
                .frame(minWidth: 64, minHeight: 50)
                .accessibilityIdentifier("onboardingBackButton")
        }
    }

    private var primaryButton: some View {
        let isLast = page == pages.count - 1
        let title = page == 0 ? "Get Started" : isLast ? (context == .firstLaunch ? "Start Using DashPilot" : "Done") : "Next"
        return Button {
            if isLast { finish() } else { move(to: page + 1) }
        } label: {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .dashPrimaryAction()
        .buttonBorderShape(.roundedRectangle(radius: DashRadius.surface))
        .accessibilityIdentifier(isLast ? "finishOnboardingButton" : "nextOnboardingButton")
    }

    private func move(to index: Int) {
        if reduceMotion {
            page = index
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { page = index }
        }
    }
}

/// One screen of the welcome.
nonisolated struct OnboardingPage: Identifiable, Sendable {
    nonisolated struct Point: Identifiable, Sendable {
        let symbol: String
        let text: String
        var id: String { text }
    }

    let id: String
    let artwork: String
    let title: String
    let message: String
    var points: [Point] = []

    /// The four screens, in order. Each figure in an illustration is drawn as
    /// bars and lines without digits, so nothing on these pages can be read as
    /// a driver's own data.
    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            artwork: "onboarding-welcome",
            title: "Make every hour count.",
            message: "Your delivery work, in one place. DashPilot helps you record your shifts, understand your money and look back on what worked.",
            points: [
                Point(symbol: "house", text: "Home shows this week's completed work. Start Shift when you're ready."),
                Point(symbol: "gearshape", text: "No setup required. You can revisit this welcome in Settings anytime.")
            ]
        ),
        OnboardingPage(
            id: "shift",
            artwork: "onboarding-road",
            title: "Track your work.",
            message: "Work keeps your shift and delivery controls together. Record each step when it is safe to stop.",
            points: [
                Point(symbol: "list.number", text: "Add a delivery or stacked offer, then record arrival, pickup and delivery."),
                Point(symbol: "parkingsign.circle", text: "Park stops route recording while working time continues. Pause stops both for a break."),
                Point(symbol: "point.topleft.down.to.point.bottomright.curvepath", text: "Recorded mileage covers the route captured. Gaps stay gaps.")
            ]
        ),
        OnboardingPage(
            id: "road",
            artwork: "onboarding-shift",
            title: "Understand your money.",
            message: "Record shift earnings after you finish. Money brings weekly earnings, recorded expenses and historical Insights together.",
            points: [
                Point(symbol: "dollarsign.circle", text: "Shift and delivery earnings are separate records. Missing amounts are never zero."),
                Point(symbol: "chart.bar", text: "Insights shows completed work and its coverage. Fuel estimates stay separate from recorded expenses."),
                Point(symbol: "target", text: "Want a benchmark? Set an optional hourly earnings target in Settings for future shifts. Amounts use USD.")
            ]
        ),
        OnboardingPage(
            id: "local",
            artwork: "onboarding-local",
            title: "Your data stays yours.",
            message: "DashPilot stores your records on this device, with no account or automatic uploads. It does not connect to DoorDash, Uber, Amazon, Walmart or any other delivery app.",
            points: [
                Point(symbol: "location", text: "Location access is explained and requested where you enable route recording, never in this welcome."),
                Point(symbol: "square.and.arrow.up", text: "Export your history only when you choose. No platform data is imported."),
                Point(symbol: "play.circle", text: "Start on Home. Your shift controls will open in Work.")
            ]
        )
    ]
}

/// The welcome shares the quiet canvas used by the main app in both appearances.
enum OnboardingPalette {
    static let background = ShiftActivityPalette.canvas
}

#if DEBUG
#Preview("Welcome") {
    OnboardingView(context: .firstLaunch) {}
}

#Preview("Welcome, dark, large text") {
    OnboardingView(context: .firstLaunch) {}
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
#endif
