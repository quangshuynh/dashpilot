import Foundation

/// Whether this install has finished the welcome, kept in `UserDefaults`.
///
/// ## Why not in the store
///
/// Every other preference is a row in the store, because it travels with the
/// driver's history and can change what is recorded. This does neither: it is
/// a fact about **this install's screens**, not about anybody's work, it is
/// never exported, and it has to be answerable when the store cannot be opened
/// at all. Putting it in the store would also make it a schema migration for a
/// flag no recorded figure reads.
///
/// ## Launch arguments, debug builds only
///
/// A throwaway-store launch (every UI journey's) never sees the welcome, so
/// existing journeys are unchanged. ``fresh`` forgets it was finished and lets
/// it show over a throwaway store; ``observe`` lets it show over a throwaway
/// store without forgetting, which is how a journey proves completion
/// persists across a relaunch; ``completed`` treats it as finished, which is
/// how a journey over the real store reaches the shift screen.
@MainActor
enum OnboardingRecord {
    static let completedVersionKey = "onboarding.completedVersion"

    #if DEBUG
    static let fresh = "-dashpilot-onboarding-fresh"
    static let observe = "-dashpilot-onboarding-observe"
    static let completed = "-dashpilot-onboarding-completed"
    #endif

    static var completedVersion: Int? {
        #if DEBUG
        if LaunchArgument.isPresent(completed) { return OnboardingPolicy.currentVersion }
        #endif
        let value = UserDefaults.standard.integer(forKey: completedVersionKey)
        return value > 0 ? value : nil
    }

    static func markCompleted() {
        UserDefaults.standard.set(OnboardingPolicy.currentVersion, forKey: completedVersionKey)
    }

    /// What this launch should do, applying the debug arguments first.
    static func launchDecision(hasRecordedShifts: Bool) -> OnboardingPolicy.Decision {
        #if DEBUG
        if LaunchArgument.isPresent(fresh) {
            UserDefaults.standard.removeObject(forKey: completedVersionKey)
        } else if LaunchArgument.isUsingThrowawayStore(), !LaunchArgument.isPresent(observe) {
            return .none
        }
        #endif
        return OnboardingPolicy.decision(completedVersion: completedVersion, hasRecordedShifts: hasRecordedShifts)
    }
}
