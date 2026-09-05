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

    /// Location permission, accuracy and services availability. Records what
    /// the app is allowed to do, never where the device is.
    static let location = Logger(subsystem: subsystem, category: "location")

    /// Manually recorded shift earnings: that an amount was added, changed or
    /// removed, and that a save failed. Never an amount — what a driver earned
    /// is exactly the kind of value this project keeps out of the logs.
    static let earnings = Logger(subsystem: subsystem, category: "earnings")

    /// Route sample capture: when it starts and stops, why it cannot run, how
    /// many samples were kept, and which rule rejected a candidate. Records the
    /// behaviour of the pipeline, never a coordinate that went through it.
    static let routeCapture = Logger(subsystem: subsystem, category: "route-capture")
}
