import Foundation

/// Why an amount a driver typed could not be recorded.
///
/// Each case is a different sentence the interface has to be able to say. A
/// single "invalid amount" would leave a driver who typed a negative number,
/// an amount in thousandths and a word looking at the same message with no idea
/// which rule they broke.
nonisolated enum MoneyInputError: Error, Equatable {
    /// Nothing was entered. Only a failure when a save was actually attempted:
    /// an empty field is the ordinary state of an editor that has just opened.
    case empty
    /// The text is not a number, or is a number written in a way this locale
    /// does not use.
    case notANumber
    /// More fraction digits than the currency has. Reported rather than rounded
    /// away, so the stored amount is never something the driver did not type.
    case excessiveScale
    /// A negative amount. Gross earnings are what a shift or a delivery paid;
    /// work that cost the driver money is an expense, which this app does not
    /// record yet.
    case negative
    /// Beyond ``MoneyInput/maximumAmount``.
    case tooLarge
}

/// What an amount is being typed for.
///
/// One parser, one set of rules, and two refusals that have to name the thing
/// being entered: a driver typing what a tank of fuel cost should not be told
/// that gross earnings cannot be negative, and an empty field means something
/// different where the amount is optional than where it is the record itself.
/// Everything else reads the same whatever is being typed.
nonisolated enum MoneyInputSubject: Sendable {
    /// An amount recorded against a shift or a delivery, which is optional and
    /// may be removed entirely.
    case grossEarnings
    /// What a recorded expense cost. Required: an expense with no amount is not
    /// a record of anything.
    case expense
}

nonisolated extension MoneyInputError {
    /// The rule this text broke, said in the terms of what was being typed.
    func message(for subject: MoneyInputSubject) -> String {
        switch self {
        case .empty:
            switch subject {
            case .grossEarnings: "Enter an amount, or cancel to leave no amount recorded."
            case .expense: "Enter what this expense cost, for example 42.10."
            }
        case .notANumber:
            "Enter an amount using numbers, for example 86.25."
        case .excessiveScale:
            "Enter an amount to the cent, for example 86.25."
        case .negative:
            switch subject {
            case .grossEarnings: "Gross earnings cannot be negative."
            case .expense: "An expense cannot be a negative amount. Enter what it cost."
            }
        case .tooLarge:
            "That is larger than any single amount DashPilot records."
        }
    }
}

nonisolated extension MoneyInputError: LocalizedError {
    /// The message for an amount recorded against a shift or a delivery, which
    /// is what an unqualified `MoneyInputError` has always described.
    var errorDescription: String? { message(for: .grossEarnings) }
}

/// Turns what a driver types into a ``Money``, and back again for editing.
///
/// The one parser behind every amount a driver types, on a shift and on a
/// delivery alike. Both editors read their text through it, so the locale rules,
/// the scale rule and the refusals below are the same wherever an amount is
/// entered.
///
/// This is the locale-aware layer `Money(exact:)` deliberately is not.
/// `Money(exact:)` reads one canonical form for fixtures and stored values; a
/// driver types whatever their keyboard offers — a comma for the decimal point
/// in most of the world, grouping separators, a currency symbol, stray spaces.
///
/// It is not an international currency subsystem. It reads a plain amount in
/// the conventions of one locale, and DashPilot presents amounts in a single
/// currency (``Money/displayCurrencyCode``); currency conversion, per-currency
/// scales and parsing an amount labelled with a currency other than the one on
/// screen are all deliberately absent.
///
/// Nothing here reinterprets input to make it work. `Foundation`'s
/// `Decimal(string:)` stops at the first character it cannot read, so `"12abc"`
/// would become `12` and `"1.2.3"` would become `1.2`; every candidate is
/// therefore validated in full before any number is built from it.
nonisolated struct MoneyInput {
    /// The largest amount that can be recorded in one entry.
    ///
    /// This is a guard against pathological input — a pasted page of digits, a
    /// stuck key — and not a judgement about what a driver can earn. `Decimal`
    /// holds 38 significant digits, so without a bound the store could hold an
    /// amount no arithmetic or formatting in the app is meaningful for. A
    /// million is five orders of magnitude above a delivery shift, and further
    /// still above one delivery, and it is checked in exactly one place so it
    /// can be raised if it is ever wrong.
    ///
    /// One bound for both subjects, deliberately. A tighter per-delivery limit
    /// would be a judgement about what a single order can pay, which is not a
    /// judgement this app is in a position to make.
    static let maximumAmount = Decimal(1_000_000)

    /// Fraction digits accepted, matching ``Money/displayScale``.
    ///
    /// DashPilot presents one currency, and it has cents. An amount typed to
    /// more places is rejected rather than rounded: rounding at the point of
    /// entry would store a number the driver did not type, and the project's
    /// rule is that rounding is a display decision.
    static let maximumFractionDigits = Money.displayScale

    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// Reads an amount from text a driver typed.
    ///
    /// - Throws: ``MoneyInputError`` describing the first rule the text breaks.
    func amount(from text: String) throws(MoneyInputError) -> Money {
        let scrubbed = scrubbed(text)
        guard !scrubbed.isEmpty else { throw .empty }

        var digits = Substring(scrubbed)
        let isNegative = digits.first == "-" || digits.first == "\u{2212}"
        if isNegative {
            digits = digits.dropFirst()
        }

        // Shape is checked before sign, so "-abc" is reported as text rather
        // than as a negative amount.
        let canonical = try canonicalDigits(digits)
        guard !isNegative else { throw .negative }

        // The canonical form is plain ASCII digits with at most one period, so
        // this cannot fail; `Decimal` still returns a NaN for a value it cannot
        // represent, which is what the length check below catches.
        guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else {
            throw .tooLarge
        }
        guard value <= Self.maximumAmount else { throw .tooLarge }

        return Money(amount: value)
    }

    /// The text an editor should start from when an amount already exists.
    ///
    /// Written in this locale's conventions so it parses back through
    /// ``amount(from:)`` unchanged, and without a currency symbol or grouping
    /// separators, because the field the driver is typing into holds a number.
    /// Trailing zeroes are dropped: `86.5` seeds `"86.5"`, not `"86.50"`.
    func text(for money: Money) -> String {
        money.rounded().amount.formatted(
            .number
                .precision(.fractionLength(0...Self.maximumFractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// A zero written to the full scale — `"0.00"`, or `"0,00"` where that is
    /// how the locale writes it.
    ///
    /// Used as an empty field's placeholder, so the field shows the *shape* of
    /// the answer rather than a fixed `0.00` that a comma locale would never
    /// accept back.
    var placeholder: String {
        Decimal.zero.formatted(
            .number
                .precision(.fractionLength(Self.maximumFractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }

    // MARK: Reading the text

    /// Removes what a driver may reasonably type around the number itself.
    ///
    /// A currency symbol — this locale's, and the `$` the app displays amounts
    /// with, so a driver whose phone is set to another region can still type
    /// the symbol they see on screen — and whitespace around the amount.
    ///
    /// Whitespace *inside* the number is not simply deleted. Several locales
    /// group thousands with a space (usually a non-breaking or narrow one, but
    /// a driver types the ordinary one), so it is rewritten as this locale's
    /// grouping separator and then has to survive the same grouping rules as
    /// any other separator. Deleting it instead would read `"125 50"` as twelve
    /// thousand five hundred and fifty.
    private func scrubbed(_ text: String) -> String {
        var scrubbed = text
        for symbol in currencySymbols where !symbol.isEmpty {
            scrubbed = scrubbed.replacingOccurrences(of: symbol, with: "")
        }
        scrubbed = scrubbed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let groupingSeparator = locale.groupingSeparator,
              !groupingSeparator.isEmpty,
              groupingSeparator != locale.decimalSeparator else {
            // No separator to rewrite it as; any space left inside will fail
            // the digit check, which is the right answer.
            return scrubbed
        }
        return scrubbed.reduce(into: "") { result, character in
            result += character.isWhitespace ? groupingSeparator : String(character)
        }
    }

    private var currencySymbols: [String] {
        var symbols = ["$"]
        if let localeSymbol = locale.currencySymbol {
            symbols.append(localeSymbol)
        }
        return symbols
    }

    /// Validates the unsigned part of the input and rewrites it as plain
    /// digits with a period, which is the only form ``Money`` parses.
    private func canonicalDigits(_ input: Substring) throws(MoneyInputError) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let components = input.components(separatedBy: decimalSeparator)
        guard components.count <= 2 else { throw .notANumber }

        let whole = try groupedDigits(components[0])

        guard components.count == 2 else { return whole }
        let fraction = components[1]
        guard !fraction.isEmpty, fraction.allSatisfy(\.isASCIIDigit) else { throw .notANumber }
        guard fraction.count <= Self.maximumFractionDigits else { throw .excessiveScale }

        return "\(whole).\(fraction)"
    }

    /// Validates the digits before the decimal separator, allowing this
    /// locale's grouping separator where it belongs.
    ///
    /// Groups have to be well formed — `1,234,567`, never `1,2,3` — because a
    /// separator in an impossible position means the input was not written in
    /// this locale's conventions, and stripping it anyway would turn text the
    /// driver got wrong into a number they never intended.
    private func groupedDigits(_ input: String) throws(MoneyInputError) -> String {
        guard !input.isEmpty else { throw .notANumber }
        if input.allSatisfy(\.isASCIIDigit) { return input }

        // A locale whose separators collide is read as decimal-only, which the
        // caller has already split on; anything left is not a number.
        guard let groupingSeparator = locale.groupingSeparator,
              !groupingSeparator.isEmpty,
              groupingSeparator != locale.decimalSeparator else {
            throw .notANumber
        }

        let groups = input.components(separatedBy: groupingSeparator)
        guard groups.count > 1 else { throw .notANumber }
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { throw .notANumber }
        guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { throw .notANumber }

        return groups.joined()
    }
}

nonisolated private extension Character {
    /// Deliberately ASCII: `Character.isNumber` is true for digits from every
    /// script and for characters such as `½`, none of which this parser can
    /// hand to `Decimal`.
    var isASCIIDigit: Bool { isASCII && isNumber }
}
