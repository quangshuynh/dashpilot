import Foundation
import OSLog

/// Central definition of the app's loggers.
///
/// Privacy rule for this project: log lifecycle, state transitions, counts and
/// error conditions — never coordinates, addresses, earnings amounts or any
/// other value that describes where a driver went or what they made.
nonisolated enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "DashPilot"

    /// Application lifecycle and top level scene state.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Store creation, migration and save behaviour.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Shift lifecycle transitions and the rules that reject them.
    static let shift = Logger(subsystem: subsystem, category: "shift")
}
