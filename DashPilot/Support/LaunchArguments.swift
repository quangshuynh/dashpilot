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

    static func isPresent(_ argument: String, in processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
    }
}
