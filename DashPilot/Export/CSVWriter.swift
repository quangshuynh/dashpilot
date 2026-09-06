import Foundation

/// Builds RFC 4180 CSV text, one field at a time.
///
/// ## Why this exists rather than `joined(separator: ",")`
///
/// A pickup place is a name a driver typed. It can hold a comma
/// (`Nowhere Noodles, Downtown`), a quotation mark, a line break pasted in by
/// accident, or an emoji — and any one of those turns naïve joining into a file
/// that is silently misaligned rather than obviously broken. A misaligned CSV is
/// worse than no CSV: a driver opens it in a spreadsheet, sees plausible
/// columns, and never learns that one row's earnings landed under another row's
/// mileage.
///
/// It is a pure value with no knowledge of shifts, deliveries or files, so every
/// rule below is testable on its own.
///
/// ## Quoting
///
/// A field is quoted when it contains a comma, a quotation mark, a carriage
/// return or a line feed, when it has leading or trailing whitespace that would
/// otherwise be lost, or when it had to be made safe for a spreadsheet. Inside
/// quotes, `"` is doubled. Everything else is written bare, which keeps the file
/// readable by eye.
///
/// ## Line endings
///
/// `\r\n` between records, which is what RFC 4180 specifies and what Excel on
/// both platforms expects. A field's *own* line breaks are preserved inside its
/// quotes and are not rewritten — the text a driver typed is the text that comes
/// out.
///
/// ## Unicode
///
/// The text is Swift `String` throughout and is written as UTF-8. Nothing is
/// transliterated, folded or stripped.
nonisolated struct CSVWriter: Equatable, Sendable {
    /// The record separator, per RFC 4180.
    static let lineTerminator = "\r\n"

    private static let fieldSeparator = ","
    private static let quote = "\""

    /// Characters that make a spreadsheet treat a cell as a formula rather than
    /// as text.
    ///
    /// `=` and `+` start a formula in every major spreadsheet; `-` does too,
    /// because a leading minus begins a numeric expression; `@` begins a
    /// function call in Excel. The two control characters are here because
    /// Excel strips a leading tab or carriage return and then reads whatever
    /// followed it, so a cell beginning `\t=` is a formula with one character of
    /// disguise.
    /// Compared as Unicode scalars rather than as `Character`s, because Swift
    /// treats `\r\n` as **one** grapheme cluster: a field beginning with a
    /// Windows line break has a first `Character` equal to neither `"\r"` nor
    /// `"\n"`, and a rule written in `Character`s silently misses it.
    private static let formulaLeaders: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    /// The scalars that force a field to be quoted, for the same reason.
    private static let quotingTriggers: Set<Unicode.Scalar> = [",", "\"", "\r", "\n"]

    /// What is put in front of a field that would otherwise be read as a
    /// formula.
    ///
    /// A single apostrophe, which every major spreadsheet reads as "the rest of
    /// this cell is text" and does not display. It is a **visible change to the
    /// bytes**, and that is stated in the documentation rather than hidden: the
    /// alternative — relying on quoting alone — does not work, because RFC 4180
    /// quotes are stripped by the parser long before the cell reaches the
    /// formula engine.
    private static let formulaGuard = "'"

    private var lines: [String] = []

    init() {}

    /// Appends one record.
    mutating func appendRow(_ fields: [String]) {
        lines.append(fields.map(Self.field).joined(separator: Self.fieldSeparator))
    }

    /// The whole file, with a trailing line terminator so the last record is
    /// terminated like every other one.
    var text: String {
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: Self.lineTerminator) + Self.lineTerminator
    }

    /// One field, made safe.
    ///
    /// The order matters: the formula guard goes on first, and the decision to
    /// quote is then made about the guarded text — a guarded field is always
    /// quoted, so the apostrophe cannot be mistaken for the start of some
    /// dialect's own quoting.
    static func field(_ value: String) -> String {
        let guarded = formulaSafe(value)
        guard needsQuoting(guarded, wasGuarded: guarded != value) else { return guarded }
        return quote + guarded.replacingOccurrences(of: quote, with: quote + quote) + quote
    }

    /// The field with a formula guard in front of it, if it needed one.
    ///
    /// Applied to **every** field rather than only to the ones a driver typed.
    /// Nothing DashPilot generates begins with one of these characters — a
    /// timestamp begins with a digit, an amount is never negative, a state is a
    /// word — so the rule costs nothing on generated fields and cannot be
    /// forgotten on the one field that is user text.
    static func formulaSafe(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, formulaLeaders.contains(first) else { return value }
        return formulaGuard + value
    }

    private static func needsQuoting(_ value: String, wasGuarded: Bool) -> Bool {
        if wasGuarded { return true }
        if value.unicodeScalars.contains(where: quotingTriggers.contains) { return true }
        // Leading or trailing whitespace survives only inside quotes; a reader
        // that trims unquoted fields would otherwise change the name.
        if value.first?.isWhitespace == true || value.last?.isWhitespace == true { return true }
        return false
    }
}
