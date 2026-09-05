import Foundation
import Testing
@testable import DashPilot

/// The normalisation policy, on its own.
///
/// `PickupPlaceName` is a pure value type: no store, no service, no view. The
/// rule deciding whether two spellings are the same place is the whole basis of
/// pickup identity, so it is asserted here in isolation and everything above it
/// is free to assume it.
///
/// Every name below is invented. The repository names no real business.
@Suite("Pickup place name")
struct PickupPlaceNameTests {
    /// Two spellings that must resolve to one place.
    private func expectSameKey(_ lhs: String, _ rhs: String, _ comment: Comment) throws {
        let left = try PickupPlaceName(lhs)
        let right = try PickupPlaceName(rhs)
        #expect(left.key == right.key, comment)
    }

    /// Two spellings that must stay separate places.
    private func expectDifferentKeys(_ lhs: String, _ rhs: String, _ comment: Comment) throws {
        let left = try PickupPlaceName(lhs)
        let right = try PickupPlaceName(rhs)
        #expect(left.key != right.key, comment)
    }

    // MARK: Whitespace

    @Test("Leading and trailing whitespace is removed from both forms")
    func trimsSurroundingWhitespace() throws {
        let name = try PickupPlaceName("   Nowhere Noodles \n ")

        #expect(name.display == "Nowhere Noodles")
        #expect(name.key == "nowhere noodles")
    }

    @Test("A run of internal whitespace becomes one space")
    func collapsesInternalWhitespace() throws {
        let name = try PickupPlaceName("Nowhere    Noodles")

        #expect(name.display == "Nowhere Noodles", "The driver reads a single space, not the four they typed")
        try expectSameKey("Nowhere    Noodles", "Nowhere Noodles", "Repeated spaces are not a different place")
    }

    @Test("Tabs, newlines and exotic spaces are whitespace too")
    func collapsesEveryKindOfWhitespace() throws {
        // A non-breaking space and an ideographic space, both of which a paste
        // can carry and neither of which a plain " " split would catch.
        let name = try PickupPlaceName("Nowhere\tNoodles\u{00A0}Express\u{3000}Lane")

        #expect(name.display == "Nowhere Noodles Express Lane")
    }

    @Test("Whitespace differences alone never create a second place")
    func whitespaceIsNotIdentity() throws {
        try expectSameKey(" Example  Diner ", "Example Diner", "Padding and doubled spaces are the same name")
    }

    // MARK: Case

    @Test("Capitalisation does not decide identity", arguments: [
        "NOWHERE NOODLES",
        "nowhere noodles",
        "Nowhere noodles",
        "nOwHeRe NoOdLeS"
    ])
    func foldsCase(_ spelling: String) throws {
        try expectSameKey(spelling, "Nowhere Noodles", "Case is not what makes two pickups different places")
    }

    @Test("The display form keeps the driver's own capitalisation")
    func preservesDisplayCapitalisation() throws {
        #expect(try PickupPlaceName("nowhere noodles").display == "nowhere noodles")
        #expect(try PickupPlaceName("NOWHERE NOODLES").display == "NOWHERE NOODLES")
    }

    // MARK: Unicode

    @Test("A composed and a decomposed accent are the same text")
    func normalisesUnicodeComposition() throws {
        // "Café Rio": one precomposed é, then e followed by a combining acute.
        // They render identically and a driver cannot tell which they typed.
        try expectSameKey("Caf\u{00E9} Rio", "Cafe\u{0301} Rio", "Identical text must not be two places")
    }

    @Test("Composition is applied to the display form as well")
    func composesTheDisplayForm() throws {
        let decomposed = try PickupPlaceName("Cafe\u{0301} Rio")

        #expect(decomposed.display == "Caf\u{00E9} Rio")
        #expect(decomposed.display.count == 8, "Composed, so the accent is not counted as its own character")
    }

    @Test("Non-Latin names survive intact")
    func keepsNonLatinText() throws {
        let name = try PickupPlaceName("  だれもいない麺  ")

        #expect(name.display == "だれもいない麺", "Only whitespace was touched")
        #expect(!name.key.isEmpty)
    }

    @Test("Emoji in a name is text, not an error")
    func acceptsEmoji() throws {
        let name = try PickupPlaceName("Nowhere Noodles 🍜")

        #expect(name.display == "Nowhere Noodles 🍜")
    }

    // MARK: Apostrophes

    @Test("The apostrophe iOS substitutes matches the one a keyboard types", arguments: [
        "\u{2019}", // right single quotation mark, what iOS smart punctuation inserts
        "\u{02BC}", // modifier letter apostrophe
        "\u{2018}", // left single quotation mark
        "\u{00B4}", // acute accent
        "\u{0060}"  // grave accent
    ])
    func unifiesApostrophes(_ variant: String) throws {
        try expectSameKey(
            "Nobody\(variant)s Diner",
            "Nobody's Diner",
            "One name typed on two keyboards is one place"
        )
    }

    @Test("The display form keeps the apostrophe the driver actually typed")
    func preservesTypedApostrophe() throws {
        #expect(try PickupPlaceName("Nobody\u{2019}s Diner").display == "Nobody\u{2019}s Diner")
        #expect(try PickupPlaceName("Nobody's Diner").display == "Nobody's Diner")
    }

    // MARK: Conservative punctuation

    @Test("Punctuation is preserved rather than stripped")
    func preservesPunctuation() throws {
        let name = try PickupPlaceName("A&B Grill")

        #expect(name.display == "A&B Grill")
        #expect(name.key == "a&b grill", "The ampersand survives into the key")
        try expectDifferentKeys("A&B Grill", "AB Grill", "Erasing punctuation would merge two different names")
    }

    @Test("An added or removed apostrophe is a different place")
    func apostrophePresenceIsIdentity() throws {
        try expectDifferentKeys(
            "Nobody's Diner",
            "Nobodys Diner",
            "Conservative: a duplicate the driver can see beats a merge they cannot undo"
        )
    }

    @Test("Diacritics are not folded away")
    func preservesDiacritics() throws {
        try expectDifferentKeys(
            "Caf\u{00E9} Rio",
            "Cafe Rio",
            "Accent folding would collapse names the driver may mean to keep apart"
        )
    }

    @Test("Nothing is abbreviated or expanded")
    func doesNotRewriteWords() throws {
        try expectDifferentKeys("Nowhere St Grill", "Nowhere Street Grill", "There is no abbreviation rule")
        try expectDifferentKeys("Nowhere Noodle", "Nowhere Noodles", "And no fuzzy match")
    }

    // MARK: Rejections

    @Test("Nothing entered is not a name")
    func rejectsEmptyInput() {
        #expect(throws: PickupPlaceNameError.empty) { try PickupPlaceName("") }
    }

    @Test("Whitespace alone is not a name", arguments: ["   ", "\n", "\t\t", " \u{00A0} "])
    func rejectsWhitespaceOnlyInput(_ text: String) {
        #expect(throws: PickupPlaceNameError.empty) { try PickupPlaceName(text) }
    }

    @Test("A name at the maximum length is accepted")
    func acceptsTheLongestAllowedName() throws {
        let name = try PickupPlaceName(String(repeating: "a", count: PickupPlaceName.maximumLength))

        #expect(name.display.count == PickupPlaceName.maximumLength)
    }

    @Test("A name beyond the maximum length is refused")
    func rejectsAnOversizedName() {
        let text = String(repeating: "a", count: PickupPlaceName.maximumLength + 1)

        #expect(throws: PickupPlaceNameError.tooLong(maximum: PickupPlaceName.maximumLength)) {
            try PickupPlaceName(text)
        }
    }

    @Test("Length is measured after whitespace is collapsed, not before")
    func measuresLengthAfterCleaning() throws {
        // Padding a valid name with spaces must not push it over the limit: the
        // padding is not part of the name that gets stored.
        let padded = "   " + String(repeating: "a", count: PickupPlaceName.maximumLength) + "   "

        #expect(try PickupPlaceName(padded).display.count == PickupPlaceName.maximumLength)
    }

    @Test("Every rejection says which rule was broken")
    func rejectionsAreExplained() throws {
        let messages = [
            PickupPlaceNameError.empty,
            PickupPlaceNameError.tooLong(maximum: PickupPlaceName.maximumLength)
        ].map { $0.errorDescription }

        for message in messages {
            let sentence = try #require(message)
            #expect(!sentence.isEmpty)
            #expect(sentence.hasSuffix("."), "Refusals are sentences: \(sentence)")
        }
    }

    // MARK: The key itself

    @Test("The stored display name rebuilds the same key it was created with")
    func keyIsRecomputableFromDisplay() throws {
        for spelling in ["Nowhere Noodles", "A&B Grill", "Nobody\u{2019}s Diner", "Caf\u{00E9} Rio"] {
            let name = try PickupPlaceName(spelling)
            #expect(
                PickupPlaceName.comparisonKey(of: name.display) == name.key,
                "Resolution compares a typed name against stored display names, so both sides must agree"
            )
        }
    }

    @Test("Building the same name twice produces the same value")
    func isDeterministic() throws {
        let first = try PickupPlaceName("  Nowhere   NOODLES ")
        let second = try PickupPlaceName("  Nowhere   NOODLES ")

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }
}
