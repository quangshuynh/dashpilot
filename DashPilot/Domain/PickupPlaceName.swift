import Foundation

/// Why a pickup-place name a driver typed cannot be recorded.
///
/// Two rules, and deliberately no more. A pickup place is a business name as the
/// driver writes it, and DashPilot has no dictionary, no directory and no
/// authority to say a name is wrong — only that a name has to *be* a name, and
/// that it has to be short enough to be one.
nonisolated enum PickupPlaceNameError: Error, Equatable {
    /// Nothing was entered, or nothing but whitespace was.
    case empty
    /// Longer than ``PickupPlaceName/maximumLength``.
    case tooLong(maximum: Int)
}

nonisolated extension PickupPlaceNameError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter the pickup place's name, or cancel to leave this delivery without one."
        case let .tooLong(maximum):
            "That name is longer than \(maximum) characters. Enter a shorter one."
        }
    }
}

/// A pickup place's name, in the two forms the app needs: the spelling the
/// driver reads, and the key two spellings are compared by.
///
/// ## Why two forms
///
/// A driver types `McDonald's` today, `mcdonalds` tomorrow and `  McDonald's  `
/// the day after. Those are one pickup place, and storing the raw text on each
/// delivery would make them three unrelated entries in a history that later
/// wants to group by place. So every name is reduced to a **comparison key**
/// that decides identity, while the **display** form keeps the driver's own
/// spelling for the screen.
///
/// The key is never shown, never spoken and never logged. It exists to answer
/// one question — is this the same place? — and answering it is all it is
/// allowed to do.
///
/// ## The policy, in full
///
/// Both forms start from the same conservative cleanup:
///
/// 1. **Unicode canonical composition** (NFC), so `é` typed as one code point
///    and `é` typed as `e` plus a combining accent are the same text rather than
///    two byte sequences that look identical on screen.
/// 2. **Whitespace collapse**: every run of whitespace or newlines becomes a
///    single space, and leading and trailing whitespace is removed. `  Kwik  \n
///    Mart ` is `Kwik Mart`.
///
/// That result is the display form. The key then adds:
///
/// 3. **Apostrophe unification**: the typographic apostrophe `’`, the modifier
///    letter apostrophe `ʼ`, the left single quote `‘`, the acute accent `´` and
///    the grave accent `` ` `` all fold to the ASCII `'`. iOS substitutes `’`
///    for `'` while the driver types, so the same name typed on two keyboards —
///    or typed once and pasted once — otherwise produces two places. No two
///    genuinely different businesses differ only by which apostrophe glyph
///    someone used.
/// 4. **Case folding**, locale-independent, so `MCDONALD'S` and `mcdonald's`
///    match.
///
/// ## What is deliberately *not* normalised
///
/// - **Punctuation is preserved.** `A&B Grill` keys as `a&b grill`, and
///   `McDonald's` and `McDonalds` remain two different places. Stripping
///   punctuation would collapse names that are genuinely distinct, and a driver
///   who ends up with two entries can pick the right one from their recent
///   places; a driver whose two restaurants silently merged has lost a
///   distinction the app cannot give back.
/// - **Diacritics are preserved.** `Cafe Rio` and `Café Rio` are two places.
///   That is a duplicate a driver can see and avoid, where folding accents away
///   is a collapse they cannot.
/// - **Nothing is abbreviated, expanded, spell-checked or matched fuzzily.**
///   There is no `St`/`Street` rule, no edit distance, no token overlap and no
///   model. Identity here is exact equality of the key, so it is explainable in
///   one sentence and testable without a corpus.
nonisolated struct PickupPlaceName: Equatable, Hashable, Sendable {
    /// The longest name accepted, in characters.
    ///
    /// A guard against pathological input — a pasted page of text, a stuck key —
    /// and not a judgement about how businesses are named. Long real names exist
    /// and fit comfortably inside this; nothing at this length is a name anyone
    /// typed on purpose. It is checked in exactly one place so it can be raised
    /// if it is ever wrong.
    static let maximumLength = 120

    /// The spelling shown to the driver: their own text, cleaned of stray
    /// whitespace and nothing else.
    let display: String

    /// The key identity is decided by. Never displayed, spoken or logged.
    let key: String

    /// Reads a name from text a driver typed.
    ///
    /// - Throws: ``PickupPlaceNameError`` describing the rule the text breaks.
    init(_ raw: String) throws(PickupPlaceNameError) {
        let cleaned = Self.collapsingWhitespace(in: raw.precomposedStringWithCanonicalMapping)
        guard !cleaned.isEmpty else { throw .empty }
        guard cleaned.count <= Self.maximumLength else { throw .tooLong(maximum: Self.maximumLength) }

        display = cleaned
        key = Self.comparisonKey(of: cleaned)
    }

    /// The key a stored display name would produce today.
    ///
    /// Used when resolving a typed name against the catalogue, so both sides of
    /// the comparison are built by the same rule.
    static func comparisonKey(of displayName: String) -> String {
        unifyingApostrophes(in: displayName)
            .folding(options: .caseInsensitive, locale: nil)
    }

    /// Every run of whitespace becomes one space, and the ends are trimmed.
    ///
    /// Splitting on `isWhitespace` covers newlines, tabs and the non-breaking
    /// and ideographic spaces a paste can carry, which a plain `" "` split would
    /// leave in the key.
    private static func collapsingWhitespace(in text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func unifyingApostrophes(in text: String) -> String {
        String(text.map { character in
            switch character {
            case "\u{2019}", "\u{02BC}", "\u{2018}", "\u{00B4}", "\u{0060}": "'"
            default: character
            }
        })
    }
}
