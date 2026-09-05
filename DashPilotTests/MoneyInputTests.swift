import Foundation
import Testing
@testable import DashPilot

@Suite("Money input")
struct MoneyInputTests {
    private let us = MoneyInput(locale: Locale(identifier: "en_US"))
    private let germany = MoneyInput(locale: Locale(identifier: "de_DE"))

    // MARK: Amounts a driver types

    @Test("A whole amount")
    func wholeAmount() throws {
        #expect(try us.amount(from: "125") == Money(exact: "125"))
    }

    @Test("One decimal place")
    func oneDecimalPlace() throws {
        #expect(try us.amount(from: "125.5") == Money(exact: "125.5"))
    }

    @Test("Two decimal places")
    func twoDecimalPlaces() throws {
        #expect(try us.amount(from: "125.50") == Money(exact: "125.50"))
    }

    @Test("Zero is a real amount, not an absence")
    func zero() throws {
        #expect(try us.amount(from: "0") == Money.zero)
        #expect(try us.amount(from: "0.00") == Money.zero)
    }

    @Test("The currency symbol may be typed or left out")
    func currencySymbol() throws {
        #expect(try us.amount(from: "$125.50") == Money(exact: "125.50"))
        #expect(try us.amount(from: "$0") == Money.zero)
    }

    @Test("Surrounding and embedded whitespace is ignored")
    func whitespace() throws {
        #expect(try us.amount(from: "  125.50  ") == Money(exact: "125.50"))
        #expect(try us.amount(from: "$ 125.50") == Money(exact: "125.50"))
        #expect(try us.amount(from: "\n125.50\t") == Money(exact: "125.50"))
    }

    @Test("Grouping separators are accepted where they belong")
    func groupingSeparators() throws {
        #expect(try us.amount(from: "1,234.50") == Money(exact: "1234.50"))
        #expect(try us.amount(from: "12,345") == Money(exact: "12345"))
    }

    @Test("A large but plausible amount")
    func largeAmount() throws {
        #expect(try us.amount(from: "999,999.99") == Money(exact: "999999.99"))
    }

    // MARK: Locale

    @Test("The decimal separator is the one this locale writes")
    func localeDecimalSeparator() throws {
        #expect(try germany.amount(from: "125,50") == Money(exact: "125.50"))
        #expect(try germany.amount(from: "1.234,50") == Money(exact: "1234.50"))
    }

    @Test("A symbol from either the locale or the displayed currency is accepted")
    func localeCurrencySymbol() throws {
        #expect(try germany.amount(from: "125,50 €") == Money(exact: "125.50"))
        // The app displays amounts in one currency, so the symbol on screen is
        // typeable whatever region the phone is set to.
        #expect(try germany.amount(from: "$125,50") == Money(exact: "125.50"))
    }

    @Test("A separator in a position this locale never writes is not reinterpreted")
    func doesNotReinterpretAcrossLocales() {
        // "125.50" in German is a grouping separator with two digits after it,
        // which no German number is written with. Stripping it anyway would
        // turn a hundred and twenty-five euros into twelve thousand.
        #expect(throws: MoneyInputError.notANumber) { try germany.amount(from: "125.50") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "1,2,3") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "1,23.45") }
    }

    // MARK: Rejection

    @Test("Nothing entered is reported as nothing entered")
    func empty() {
        #expect(throws: MoneyInputError.empty) { try us.amount(from: "") }
        #expect(throws: MoneyInputError.empty) { try us.amount(from: "   ") }
        #expect(throws: MoneyInputError.empty) { try us.amount(from: "$") }
    }

    @Test("Text is not silently read as the number in front of it")
    func nonNumericText() {
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "abc") }
        // `Decimal(string:)` alone would read these as 12 and 1.2.
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "12abc") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "1.2.3") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "12 34") }
    }

    @Test("Malformed decimals are rejected")
    func malformedDecimal() {
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "125.") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: ".") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: ".50") }
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "1..5") }
    }

    @Test("More precision than the currency has is refused rather than rounded away")
    func excessiveScale() {
        #expect(throws: MoneyInputError.excessiveScale) { try us.amount(from: "125.505") }
        #expect(throws: MoneyInputError.excessiveScale) { try us.amount(from: "0.001") }
    }

    @Test("A negative amount is refused, and said to be negative")
    func negative() {
        #expect(throws: MoneyInputError.negative) { try us.amount(from: "-125.50") }
        #expect(throws: MoneyInputError.negative) { try us.amount(from: "-0.01") }
        #expect(throws: MoneyInputError.negative) { try us.amount(from: "\u{2212}5") }
    }

    @Test("Malformed text that also carries a sign is reported as text")
    func negativeAndMalformed() {
        #expect(throws: MoneyInputError.notANumber) { try us.amount(from: "-abc") }
    }

    @Test("An amount beyond what a shift can hold is refused")
    func tooLarge() {
        #expect(throws: MoneyInputError.tooLarge) { try us.amount(from: "1000000.01") }
        #expect(throws: MoneyInputError.tooLarge) { try us.amount(from: String(repeating: "9", count: 60)) }
    }

    @Test("The bound itself is a valid amount")
    func maximumIsInclusive() throws {
        #expect(try us.amount(from: "1000000") == Money(amount: MoneyInput.maximumAmount))
    }

    @Test("Every rejection can be explained to the driver")
    func everyErrorHasAMessage() {
        let errors: [MoneyInputError] = [.empty, .notANumber, .excessiveScale, .negative, .tooLarge]
        #expect(errors.allSatisfy { ($0.errorDescription?.isEmpty == false) })
    }

    // MARK: Seeding an editor

    @Test("An existing amount is written back in a form this locale parses")
    func editableTextRoundTrips() throws {
        for input in ["125", "125.5", "125.50", "0", "1234.99"] {
            let money = try us.amount(from: input)
            #expect(try us.amount(from: us.text(for: money)) == money, "round trip of \(input)")
        }

        let german = try germany.amount(from: "1.234,50")
        #expect(germany.text(for: german) == "1234,5")
        #expect(try germany.amount(from: germany.text(for: german)) == german)
    }

    @Test("Seed text carries no currency symbol or grouping separator")
    func editableTextIsPlain() throws {
        let money = try us.amount(from: "1,234.50")
        #expect(us.text(for: money) == "1234.5")
    }
}
