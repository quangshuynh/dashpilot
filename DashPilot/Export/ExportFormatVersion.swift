import Foundation

/// The external contract DashPilot's exported files are written to.
///
/// ## Why this is not the schema version
///
/// The store is at schema v7 and will move on. That number describes how
/// SwiftData lays out a database on one device, and nothing outside the app has
/// ever seen it. This one describes a **file a driver has already taken
/// somewhere else** — a spreadsheet, a folder, an accountant's inbox — and the
/// two must be free to move independently. An internal schema change that adds
/// a column nothing exports must not renumber the file format, and a change to
/// what the file says must not pretend the store changed.
///
/// So an export never calls itself "v7", and the version below is bumped only
/// when the meaning of an existing field changes or a field is removed. Adding
/// a field is additive and does not bump it: a reader that ignores unknown keys
/// keeps working.
nonisolated enum ExportFormat {
    /// The current format version, written into every export.
    static let version = 1

    /// What produced the file. A product name and nothing more — no build, no
    /// device, no identifier of any kind.
    static let producer = "DashPilot"
}

/// The two shapes an export can be written in.
///
/// Two, deliberately. JSON is the canonical machine-readable form and holds
/// everything the export contract defines, including the coverage counts that
/// keep a period figure honest. CSV is the flat view a spreadsheet opens, one
/// row per delivery.
nonisolated enum ExportFileFormat: String, CaseIterable, Sendable, Hashable, Identifiable {
    case json
    case csv

    var id: String { rawValue }

    /// The label on the control that chooses this format.
    var title: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        }
    }

    /// What VoiceOver hears on the control that shares a file of this format.
    var spokenShareLabel: String {
        switch self {
        case .json: "Share JSON export"
        case .csv: "Share CSV export"
        }
    }

    /// What this format does and does not carry, said on the sheet.
    ///
    /// The CSV sentence is the one that matters: its absence of a period
    /// summary is a deliberate decision rather than an omission, and a driver
    /// choosing a format should be told before they share the file.
    var explanation: String {
        switch self {
        case .json:
            """
            The complete record: every shift, every delivery recorded during it, and — for a day or a \
            week — the summary with the counts each figure was worked out from.
            """
        case .csv:
            """
            One row per recorded delivery, with its shift's own figures repeated on it, for opening in \
            a spreadsheet. A day or week summary is not included: each of its figures is paired with \
            the number of shifts behind it, and a single flat table cannot keep that pairing. Export \
            JSON for the summary.
            """
        }
    }
}
