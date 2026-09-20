import Foundation

/// Why a fuel economy a driver typed could not be recorded.
///
/// The same shape as ``MoneyInputError`` and for the same reason: a driver who
/// typed a word, a negative number and a zero should not be shown one message
/// between them.
nonisolated enum MilesPerGallonInputError: Error, Equatable {
    /// Nothing was entered.
    case empty
    /// The text is not a number, or is a number written in a way this locale
    /// does not use.
    case notANumber
    /// More fraction digits than a fuel economy is entered to.
    case excessiveScale
    /// Zero, or a negative figure.
    ///
    /// **The one rule that is this type's own.** Miles per gallon is the
    /// *divisor* of a fuel estimate: zero cannot be divided by, and a vehicle
    /// that covers a negative distance on a gallon is not a thing that happened.
    /// Unlike money, where zero is a meaningful recorded fact, there is no
    /// truthful reading of a fuel economy of nothing.
    case notPositive
    /// Beyond ``MoneyInput/maximumAmount``, which is the app's one guard against
    /// pathological input.
    case tooLarge
}

nonisolated extension MilesPerGallonInputError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter your vehicle's miles per gallon, for example 28.5."
        case .notANumber:
            "Enter miles per gallon using numbers, for example 28.5."
        case .excessiveScale:
            "Enter miles per gallon to two decimal places at most, for example 28.5."
        case .notPositive:
            "Miles per gallon has to be more than zero. It is what DashPilot divides the recorded miles by."
        case .tooLarge:
            "That is larger than any figure DashPilot records."
        }
    }
}

/// Turns what a driver types for a vehicle's fuel economy into a `Decimal`, and
/// back again for editing.
///
/// ## Why it is not ``MoneyInput``, and why it is not a second parser either
///
/// Miles per gallon is **not money**. It has no currency, no symbol to strip, no
/// cents, and its zero is refused rather than recorded. Routing it through
/// ``MoneyInput`` directly would give a driver typing a fuel economy the
/// sentence "Gross earnings cannot be negative", and would let a `Money` — the
/// type this project reserves for currency — stand for a ratio.
///
/// What it *does* share is the locale-aware reading of a decimal number, through
/// ``MoneyInput/decimal(from:)``. Which character is the decimal separator,
/// where a grouping separator may fall, and that a space inside a number is a
/// separator rather than something to delete are properties of the driver's
/// locale, not of what the number means. A second copy of those rules is how two
/// fields on the same phone come to disagree about what `"1 234,5"` is.
///
/// So: one reading, two meanings. This type owns the meaning.
///
/// ## What is deliberately absent
///
/// There is **no upper bound of its own**. ``MoneyInput/maximumAmount`` already
/// guards against a pasted page of digits, and a tighter limit would be a
/// judgement about what a vehicle can do — the same judgement the money parser
/// declines to make about what a delivery can pay. A driver with an unusual
/// vehicle is not somebody this app should argue with.
nonisolated struct MilesPerGallonInput {
    /// Fraction digits accepted.
    ///
    /// Two. A fuel economy is a figure a driver reads off a trip computer or a
    /// spec sheet, and neither states a third.
    static let maximumFractionDigits = 2

    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// Reads a fuel economy from text a driver typed.
    ///
    /// - Throws: ``MilesPerGallonInputError`` describing the first rule the text
    ///   breaks.
    func milesPerGallon(from text: String) throws(MilesPerGallonInputError) -> Decimal {
        let value: Decimal
        do {
            value = try MoneyInput(locale: locale).decimal(from: text)
        } catch {
            throw Self.translating(error)
        }
        // The shared reader accepts zero and refuses negatives, which is the
        // money rule. A fuel economy of zero is refused here, where the rule
        // belongs, so both non-positive cases read as one sentence.
        guard value > 0 else { throw .notPositive }
        return value
    }

    /// The text an editor should start from when a fuel economy already exists.
    ///
    /// Written in this locale's conventions so it parses back through
    /// ``milesPerGallon(from:)`` unchanged, and without grouping separators,
    /// because the field the driver is typing into holds a number. Trailing
    /// zeroes are dropped: `28.50` seeds `"28.5"`.
    func text(for milesPerGallon: Decimal) -> String {
        milesPerGallon.formatted(
            .number
                .precision(.fractionLength(0...Self.maximumFractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// What an empty field shows: the shape of the answer in this locale's
    /// conventions, rather than a fixed example a comma locale would never
    /// accept back.
    var placeholder: String {
        Decimal(string: "28.5", locale: Locale(identifier: "en_US_POSIX"))?.formatted(
            .number
                .precision(.fractionLength(0...Self.maximumFractionDigits))
                .grouping(.never)
                .locale(locale)
        ) ?? "28.5"
    }

    /// The same failure, said in this type's vocabulary.
    ///
    /// ``MoneyInputError/negative`` becomes ``MilesPerGallonInputError/notPositive``
    /// so that a negative figure and a zero produce one sentence, which is the
    /// sentence that explains the actual rule.
    private static func translating(_ error: MoneyInputError) -> MilesPerGallonInputError {
        switch error {
        case .empty: .empty
        case .notANumber: .notANumber
        case .excessiveScale: .excessiveScale
        case .negative: .notPositive
        case .tooLarge: .tooLarge
        }
    }
}
