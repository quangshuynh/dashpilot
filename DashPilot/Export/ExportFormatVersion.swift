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
///
/// ## Version history
///
/// ### Still 2 — recorded expenses
///
/// Recorded operating costs added a top-level `expenses` array, a
/// `summary.expenses` block and a `summary.netAfterRecordedExpenses` block. The
/// version was **evaluated and deliberately not bumped**, by the rule above:
///
/// - **Nothing existing changed meaning.** `shiftCount` still counts shifts,
///   `shifts[]` still holds the same records, and no earnings, mileage,
///   duration or rate field is derived any differently. In particular nothing
///   subtracts an expense from an earnings figure that already existed: the net
///   is a new field beside them, never a redefinition of one.
/// - **No field was removed or renamed**, which is what forced version 2.
/// - **No enumeration gained a value.** `scope.kind` is the same closed set of
///   six. `expenses[].category` is a new field, so its set is new rather than
///   widened, and a version-1 or version-2 reader that has never seen the key
///   cannot be broken by what is in it.
/// - **The new arrays are always present.** A scope with no expenses writes
///   `[]`, so a reader never has to distinguish "no expenses" from "an older
///   build" — the same reason every optional in this format is an explicit
///   `null`.
///
/// A reader that ignores unknown keys therefore keeps working unchanged, which
/// is the whole of what the version number promises. A reader written against a
/// file produced *before* expenses existed will find the keys absent, which is
/// how it can tell that build had no such field.
///
/// The CSV form is unchanged, and its columns are the same 32. Expenses are not
/// in it: see ``ExportFileFormat/explanation``.
///
/// ### 2 — month and custom reporting periods
///
/// Two changes, both of which a version-1 reader can be broken by, which is why
/// this is a bump rather than an addition:
///
/// - **`scope.kind` gained the values `month` and `custom`.** Version 1
///   documented a closed set — `shift`, `day`, `week`, `allHistory` — and a
///   reader that switched exhaustively over those four now meets a fifth or a
///   sixth. The field's *type* did not change, but the set of things it can say
///   did, and a scope a reader cannot name is a file it cannot interpret.
/// - **`scope.periodEnd` was renamed to `scope.periodEndExclusive`.** A removed
///   key, and deliberate. The instant was always exclusive, and with only whole
///   calendar days and weeks in the format that was easy to overlook; with a
///   range the driver chose by two inclusive dates it is not. Someone selecting
///   *September 1 through 7* now gets a file saying the range ends at
///   `2026-09-08T00:00:00Z`, and the key has to say why.
///
/// ### 1 — the first export format
///
/// Shift, day, week and all-history scopes, in JSON and CSV.
nonisolated enum ExportFormat {
    /// The current format version, written into every export.
    ///
    /// Not the store's schema version, which is unrelated and currently 7.
    static let version = 2

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
            The complete record: every shift, every delivery recorded during it, the expenses you \
            recorded, and — for a day, week, month or range — the summary with the counts each \
            figure was worked out from.
            """
        case .csv:
            """
            One row per recorded delivery, with its shift's own figures repeated on it, for opening in \
            a spreadsheet. Two things are not included. The period summary: each of its figures is \
            paired with the number of shifts behind it, and a single flat table cannot keep that \
            pairing. Your recorded expenses: an expense belongs to a date rather than to a shift or a \
            delivery, so it has no row in a table of deliveries and DashPilot will not invent one. \
            Export JSON for both.
            """
        }
    }
}
