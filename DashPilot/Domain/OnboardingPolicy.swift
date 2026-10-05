import Foundation

/// When DashPilot introduces itself.
///
/// ## Once, to a new driver
///
/// The welcome is shown on the first launch of an install that has never
/// finished it and holds no recorded shift. A driver who already has history
/// (everyone who used DashPilot before the welcome existed) knows the app, so
/// they are not stopped at the door by four screens about it; the policy
/// records the welcome as seen for them instead, so it never appears later
/// either. Anyone can open it again from Settings.
///
/// ## Versioned, so a later welcome can be shown once more
///
/// What is remembered is the version of the welcome that was finished. A
/// rewritten welcome can raise ``currentVersion`` and be shown once to a driver
/// who finished an older one, without a second flag.
nonisolated enum OnboardingPolicy {
    /// The welcome this build ships.
    static let currentVersion = 1

    /// What to do at launch.
    nonisolated enum Decision: Equatable, Sendable {
        /// Show the welcome.
        case present
        /// Record it as seen without showing it: a driver with history.
        case recordAsSeen
        /// Nothing to do.
        case none
    }

    static func decision(completedVersion: Int?, hasRecordedShifts: Bool) -> Decision {
        if let completedVersion, completedVersion >= currentVersion { return .none }
        // A driver with history skips a first welcome, never a newer one.
        if completedVersion == nil, hasRecordedShifts { return .recordAsSeen }
        return .present
    }
}
