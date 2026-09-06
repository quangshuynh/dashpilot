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

    /// Manually recorded earnings, on a shift and on an individual delivery:
    /// that an amount was added, changed or removed, and that a save failed.
    /// Never an amount, and never the difference between two of them — what a
    /// driver earned is exactly the kind of value this project keeps out of the
    /// logs.
    static let earnings = Logger(subsystem: subsystem, category: "earnings")

    /// Operating costs the driver recorded: that an expense was added, changed
    /// or removed, which **category** it was, and whether a note exists. Never
    /// the amount, never the date the money was spent, and never a word of the
    /// note — a note is free text the driver typed, which is exactly the kind of
    /// value this project keeps out of the logs.
    static let expenses = Logger(subsystem: subsystem, category: "expenses")

    /// Delivery lifecycle transitions and the rules that reject them. Records
    /// that a delivery started, advanced or finished — never when, never where,
    /// and never what it paid. A driver's delivery timing is work history, and
    /// the log is not the place for it.
    static let delivery = Logger(subsystem: subsystem, category: "delivery")

    /// Actions performed from Siri, Shortcuts and other system surfaces:
    /// which action was asked for, and which rule refused it. Never a
    /// timestamp, because when a driver started work is work history, and never
    /// anything the driver said — the intents take no dictated value in the
    /// first place.
    static let intents = Logger(subsystem: subsystem, category: "intents")

    /// Pickup identity: that a place was assigned, changed or removed, and
    /// whether an existing place was reused or a new one created. **Never a
    /// place's name**, in any form — not the spelling the driver typed and not
    /// the normalised key derived from it. Where a driver picks up is work
    /// history and, for a driver who works a small area, close to a description
    /// of where they are.
    static let pickupPlace = Logger(subsystem: subsystem, category: "pickup-place")

    /// Local history export: that a file was written, for which scope and in
    /// which format, and how many shifts went into it; that an export was
    /// refused, by rule; and that a write failed. **Never the contents** — no
    /// date a driver worked, no amount, no place name, no distance — and never
    /// the path the file was written to, which names a location on the device
    /// and tells a reader of the log nothing they can act on.
    static let export = Logger(subsystem: subsystem, category: "export")

    /// Route sample capture: when it starts and stops, why it cannot run, how
    /// many samples were kept, and which rule rejected a candidate. Records the
    /// behaviour of the pipeline, never a coordinate that went through it.
    static let routeCapture = Logger(subsystem: subsystem, category: "route-capture")
}
