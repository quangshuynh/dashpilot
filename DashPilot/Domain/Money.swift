import Foundation

/// A currency amount backed by `Decimal`.
///
/// Earnings, fees and tips are never routed through binary floating point in
/// DashPilot: `Double` cannot represent values such as `0.10` exactly, and the
/// error compounds across a shift's worth of deliveries. Every monetary
/// operation the app needs lives here so the rounding rules stay in one place.
///
/// Values are stored unrounded. Rounding happens when a caller explicitly asks
/// for it, so intermediate arithmetic does not accumulate rounding bias.
nonisolated struct Money: Hashable, Sendable, Codable, Comparable {
    /// Number of fraction digits used when presenting an amount.
    static let displayScale = 2

    /// The currency DashPilot presents amounts in.
    ///
    /// One code, deliberately. Nothing in the app converts between currencies
    /// or records which currency an amount was earned in, so taking the
    /// currency from the device's locale would relabel a US driver's earnings
    /// as euros the moment they set their phone to another region. Locale still
    /// decides how the amount is written — symbol placement, separators — it
    /// just does not decide what the money is.
    static let displayCurrencyCode = "USD"

    /// The exact, unrounded amount.
    let amount: Decimal

    static let zero = Money(amount: .zero)

    init(amount: Decimal) {
        self.amount = amount
    }

    /// Creates an amount from a whole number of minor units, e.g. `Money(minorUnits: 1250)` is `12.50`.
    init(minorUnits: Int, scale: Int = Money.displayScale) {
        self.amount = Decimal(minorUnits) / pow(10, scale)
    }

    /// Parses a canonical, locale-independent decimal string such as `"12.50"`.
    ///
    /// This is intended for fixtures, tests and stored values. Parsing what a
    /// driver types belongs in a locale-aware input layer, not here.
    init?(exact string: String) {
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self.amount = value
    }

    var isZero: Bool { amount.isZero }
    var isNegative: Bool { amount < .zero }

    static func + (lhs: Money, rhs: Money) -> Money {
        Money(amount: lhs.amount + rhs.amount)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        Money(amount: lhs.amount - rhs.amount)
    }

    static prefix func - (value: Money) -> Money {
        Money(amount: -value.amount)
    }

    /// Scales an amount, e.g. by a count of deliveries.
    static func * (lhs: Money, rhs: Decimal) -> Money {
        Money(amount: lhs.amount * rhs)
    }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    /// Divides the amount, returning `nil` when the divisor is zero.
    ///
    /// Rate calculations (per hour, per mile, per delivery) are the reason this
    /// exists, and a zero divisor is a normal state there: a shift can have no
    /// recorded distance or no elapsed time. Callers must handle the absent
    /// case rather than displaying a fabricated rate.
    func divided(by divisor: Decimal, scale: Int = 4, mode: NSDecimalNumber.RoundingMode = .plain) -> Money? {
        guard !divisor.isZero else { return nil }
        return Money(amount: amount / divisor).rounded(scale: scale, mode: mode)
    }

    /// Rounds to `scale` fraction digits, half away from zero by default.
    func rounded(scale: Int = Money.displayScale, mode: NSDecimalNumber.RoundingMode = .plain) -> Money {
        var source = amount
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return Money(amount: result)
    }

    /// Formats an amount for display.
    ///
    /// The single place a monetary string is built in DashPilot: no view
    /// assembles one from a symbol and a number, and no view configures a
    /// formatter. Rounding to ``displayScale`` happens here and only here, so
    /// presentation cannot change what is stored.
    func formatted(currencyCode: String = Money.displayCurrencyCode, locale: Locale = .autoupdatingCurrent) -> String {
        rounded().amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}
