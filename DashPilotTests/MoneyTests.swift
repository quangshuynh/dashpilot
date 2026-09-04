import Foundation
import Testing
@testable import DashPilot

@Suite("Money")
struct MoneyTests {
    @Test("Addition is exact for values that binary floating point cannot represent")
    func exactAddition() throws {
        let tenCents = try #require(Money(exact: "0.10"))
        let twentyCents = try #require(Money(exact: "0.20"))
        let thirtyCents = try #require(Money(exact: "0.30"))

        #expect(tenCents + twentyCents == thirtyCents)
    }

    @Test("Repeated addition does not drift")
    func repeatedAdditionDoesNotDrift() throws {
        let fare = try #require(Money(exact: "4.35"))
        let total = (0..<100).reduce(Money.zero) { partial, _ in partial + fare }

        #expect(total == Money(exact: "435.00"))
    }

    @Test("Minor units initialiser matches the decimal string form")
    func minorUnits() {
        #expect(Money(minorUnits: 1250) == Money(exact: "12.50"))
        #expect(Money(minorUnits: -75) == Money(exact: "-0.75"))
        #expect(Money(minorUnits: 0) == Money.zero)
    }

    @Test("Rejects strings that are not decimal amounts")
    func rejectsInvalidStrings() {
        #expect(Money(exact: "") == nil)
        #expect(Money(exact: "abc") == nil)
    }

    @Test("Subtraction, negation and sign reporting")
    func subtractionAndSign() throws {
        let earnings = try #require(Money(exact: "18.40"))
        let expenses = try #require(Money(exact: "22.15"))
        let net = earnings - expenses

        #expect(net == Money(exact: "-3.75"))
        #expect(net.isNegative)
        #expect(-net == Money(exact: "3.75"))
        #expect(Money.zero.isZero)
    }

    @Test("Scaling by a count")
    func scaling() throws {
        let perDelivery = try #require(Money(exact: "7.25"))
        #expect(perDelivery * 4 == Money(exact: "29.00"))
    }

    @Test("Rounding is half away from zero at the requested scale")
    func rounding() throws {
        #expect(try #require(Money(exact: "1.005")).rounded() == Money(exact: "1.01"))
        #expect(try #require(Money(exact: "-1.005")).rounded() == Money(exact: "-1.01"))
        #expect(try #require(Money(exact: "1.004")).rounded() == Money(exact: "1.00"))
        #expect(try #require(Money(exact: "1.2345")).rounded(scale: 3) == Money(exact: "1.235"))
    }

    @Test("Division produces a rate at the requested scale")
    func division() throws {
        let earnings = try #require(Money(exact: "84.00"))
        let perHour = earnings.divided(by: 3.5, scale: 2)

        #expect(perHour == Money(exact: "24.00"))
    }

    @Test("Division by zero has no answer rather than a fabricated one")
    func divisionByZero() throws {
        let earnings = try #require(Money(exact: "84.00"))
        #expect(earnings.divided(by: 0) == nil)
    }

    @Test("Amounts are ordered by value")
    func ordering() throws {
        let low = try #require(Money(exact: "9.99"))
        let high = try #require(Money(exact: "10.00"))

        #expect(low < high)
        #expect(max(low, high) == high)
    }

    @Test("Formatting uses the supplied currency and locale")
    func formatting() throws {
        let amount = try #require(Money(exact: "12.5"))
        let formatted = amount.formatted(currencyCode: "USD", locale: Locale(identifier: "en_US"))

        #expect(formatted == "$12.50")
    }
}
