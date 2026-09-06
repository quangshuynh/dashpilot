import Foundation

/// Why a note a driver typed on an expense could not be recorded.
nonisolated enum ExpenseNoteError: Error, Equatable {
    /// Longer than ``ExpenseNote/maximumLength``.
    case tooLong(maximumLength: Int)
}

nonisolated extension ExpenseNoteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .tooLong(maximumLength):
            "Keep the note to \(maximumLength) characters or fewer. It is a reminder, not a record of the purchase."
        }
    }
}

/// The rule for the optional note on a recorded expense.
///
/// ## What a note is for
///
/// One short reminder of which purchase an amount was — *"top-up before the
/// evening"*, *"front tyres"* — so a driver reading a month of figures can tell
/// two amounts apart. It is deliberately not a description of the transaction:
/// there is no merchant field, no payment method, no card, no receipt and no
/// address anywhere in DashPilot, and the length limit is what keeps a note from
/// quietly becoming one.
///
/// ## Empty is absent
///
/// Whitespace and an empty field both mean *no note*, and are stored as `nil`.
/// An empty string would be a second way of saying the same thing, and two
/// representations of one fact is how a `""` eventually reaches a screen as a
/// blank line the driver did not write.
///
/// ## Privacy
///
/// A note is free text the driver typed, so it is treated exactly as a pickup
/// place name is: it stays on the device, it is never logged, and it leaves only
/// through an export the driver started. The editor says so before they type.
nonisolated enum ExpenseNote {
    /// The longest note that can be recorded.
    ///
    /// Enough for a phrase, not enough for a paragraph. The bound exists so a
    /// note stays a reminder and so a pasted page of text cannot become part of
    /// a record every export then carries.
    static let maximumLength = 120

    /// The note to store for what the driver typed, or `nil` when they typed
    /// nothing worth storing.
    ///
    /// Leading and trailing whitespace is trimmed — it is invisible on screen
    /// and would otherwise make two identical-looking notes different strings —
    /// and the length is measured on the trimmed text, after normalising the
    /// line breaks a paste can bring in.
    ///
    /// - Throws: ``ExpenseNoteError/tooLong(maximumLength:)``.
    static func note(from text: String) throws -> String? {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Counted in `Character`s, which is what a driver sees: an emoji or an
        // accented letter is one character here, as it is on screen.
        guard trimmed.count <= maximumLength else { throw ExpenseNoteError.tooLong(maximumLength: maximumLength) }
        return trimmed
    }
}
