import Foundation

/// The external contract DashPilot's exported files are written to.
///
/// ## Why this is not the schema version
///
/// The store is at schema v11 and will move on. That number describes how
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
/// ### Still 3: what a delivery was expected to pay
///
/// A driver can now record what they expect a delivery in progress to pay, and
/// that figure survives the delivery finishing. JSON gains one field for it,
/// `shifts[].deliveries[].expectedEarnings`. The version was **evaluated and
/// deliberately not bumped**, by the rule above:
///
/// - **Nothing existing changed meaning.** `deliveries[].grossEarnings` is the
///   same finalized recorded gross it has always been, and every figure derived
///   from it (the delivery's own rate, the shift's rates, every period total,
///   the whole `summary` block) is derived from exactly what it was derived
///   from before. Not one previously exported value would differ.
/// - **No field was removed or renamed**, and no enumeration gained a value.
/// - **The new field is always present**, as an explicit `null` where no
///   expectation was recorded, so a reader never has to tell "none recorded"
///   from "an older build". A reader that ignores unknown keys is unaffected,
///   which is the whole of what this number promises.
///
/// **It is in the file because an export is the only way anything leaves
/// DashPilot.** There is no import, no backup and no sync, so a fact the driver
/// typed and can see on screen would otherwise be unreachable from outside the
/// app. The format's own argument applies: a file is exactly where distinctions
/// get flattened, and the answer to that is to carry the distinction, not to
/// drop the value.
///
/// **It is in JSON only, and the CSV form is unchanged at 35 columns.** That is
/// a decision rather than an oversight, and it is the same one that keeps
/// expenses out of the CSV. A spreadsheet column is a thing people sum. An
/// amount that is explicitly *not* earnings, sitting one column away from one
/// that is, in a table whose whole purpose is to be totalled, is the single most
/// likely way a driver ends up reporting money nobody paid them. The JSON form
/// can carry the field with the paragraph that says what it is not; a column
/// heading cannot. Adding a column would also have bumped this version on its
/// own, by breaking positional readers.
///
/// ### 3: shift pause and resume
///
/// A driver can now pause a shift and resume it later, and a shift's **working
/// duration**, which is elapsed time less the stretches it was paused, became
/// the denominator of every hourly figure. Evaluated against the rule above and
/// bumped, because two of its three parts are exactly what the rule bumps for:
///
/// - **A field was renamed.** `shifts[].grossPerElapsedHour` is now
///   `shifts[].grossPerWorkingHour`, and `summary.grossPerElapsedHour` is now
///   `summary.grossPerWorkingHour`. A rename is a removal to a reader looking
///   for the old key. It is a rename rather than a silent redefinition on
///   purpose: leaving the name and changing the denominator underneath it would
///   hand a reader a figure that no longer means what its name says, and no
///   reader could detect that.
/// - **`summary.elapsed` became `summary.working`**, for the same reason and
///   with the same effect on a reader.
/// - **`shifts[].nonDeliverySeconds` changed meaning.** It is now the working
///   time no recorded delivery was open for, where it was the elapsed time.
///   The two are the same number for every shift that was never paused, so no
///   previously exported file would have differed. The field's definition did
///   change, though, and a version number that only moved when values changed
///   would be describing this build rather than the contract.
///
/// Three fields were **added**, which on their own would not have bumped it:
/// `shifts[].pausedSeconds`, `shifts[].workingSeconds` and
/// `shifts[].pauseCount`. `shifts[].elapsedSeconds` keeps exactly the meaning it
/// had, the wall-clock length of the shift with pauses included, and is not
/// redefined.
///
/// **The CSV form moves with it**, from 32 columns to 34:
/// `shiftPausedSeconds`, `shiftWorkingSeconds` and `shiftPauseCount` are added,
/// and `shiftGrossPerElapsedHour` becomes `shiftGrossPerWorkingHour`. A
/// spreadsheet reading by column position is broken by an insertion wherever it
/// happens, which is the other half of why this is a version rather than an
/// addition.
///
/// Nothing about a shift recorded before this build changes value. Such a shift
/// has no pauses, so its paused seconds are `0`, its working seconds equal its
/// elapsed seconds, and every rate derived from it is the figure it always was.
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
/// The CSV form was unchanged by that version, and its columns were the same 32
/// until version 3 above. Expenses are still not in it: see
/// ``ExportFileFormat/explanation``.
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
    /// Not the store's schema version, which is unrelated and currently 11.
    static let version = 3

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
            a spreadsheet. Three things are not included. The period summary: each of its figures is \
            paired with the number of shifts behind it, and a single flat table cannot keep that \
            pairing. Your recorded expenses: an expense belongs to a date rather than to a shift or a \
            delivery, so it has no row in a table of deliveries and DashPilot will not invent one. \
            What you expected a delivery to pay: it is not earnings, and a column of it beside one \
            that is would be summed as though it were. Export JSON for all three.
            """
        }
    }
}
