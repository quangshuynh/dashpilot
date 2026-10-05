import Foundation
import Testing
@testable import DashPilot

/// When the welcome is shown: once, to a new install; never to a driver who
/// already has history; never again once finished; and once more only if a
/// later build ships a newer welcome.
@Suite("Onboarding policy")
struct OnboardingPolicyTests {
    @Test("A new install with no history is welcomed")
    func newInstall() {
        #expect(OnboardingPolicy.decision(completedVersion: nil, hasRecordedShifts: false) == .present)
    }

    @Test("A driver who already has history is not stopped at the door, and it is recorded as seen")
    func existingDriver() {
        #expect(OnboardingPolicy.decision(completedVersion: nil, hasRecordedShifts: true) == .recordAsSeen)
    }

    @Test("Finished once, it is not shown again, with or without history")
    func finished() {
        for history in [false, true] {
            #expect(
                OnboardingPolicy.decision(completedVersion: OnboardingPolicy.currentVersion, hasRecordedShifts: history)
                    == .none
            )
        }
    }

    @Test("A newer welcome is shown once to a driver who finished an older one, history or not")
    func newerVersion() {
        for history in [false, true] {
            #expect(OnboardingPolicy.decision(completedVersion: 0, hasRecordedShifts: history) == .present)
        }
    }

    @Test("Every screen has words, and the last one disclaims every platform it names")
    func pages() throws {
        let pages = OnboardingPage.all
        #expect(pages.map(\.id) == ["welcome", "shift", "road", "local"])
        #expect(pages.allSatisfy { !$0.title.isEmpty && !$0.message.isEmpty })
        let local = try #require(pages.last)
        #expect(local.message.contains("does not connect to"))
        for platform in ["DoorDash", "Uber", "Amazon", "Walmart"] {
            #expect(local.message.contains(platform))
            #expect(!pages.dropLast().contains { $0.message.contains(platform) }, "Named only to disclaim")
        }
        // No figure that could be read as the driver's own data.
        for page in pages {
            #expect(!(page.title + page.message).contains("$"))
        }
    }
}
