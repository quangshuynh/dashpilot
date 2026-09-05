import Foundation

/// Launch arguments the app recognises.
///
/// The UI test target cannot link the app target, so it repeats these string
/// values rather than importing them. Keep the two in step.
nonisolated enum LaunchArgument {
    /// Runs against a throwaway in-memory store.
    ///
    /// UI tests need a known empty starting state and must not write shifts
    /// into the store a real driver's data would live in. Debug builds only.
    static let inMemoryStore = "-dashpilot-in-memory-store"

    /// Runs against a throwaway store already holding synthetic completed
    /// shifts.
    ///
    /// Some of what the history row shows cannot be produced by tapping through
    /// the app: a UI test cannot drive a simulator into recording a route, so a
    /// measured, partial route and the rates derived from it would otherwise be
    /// untestable end to end. The data is the same synthetic fixture the
    /// previews use — invented amounts and coordinates in open country, never a
    /// real driver's history. Debug builds only, and in memory, so it can never
    /// touch a real store.
    static let seededHistory = "-dashpilot-seeded-history"

    static func isPresent(_ argument: String, in processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
    }
}
