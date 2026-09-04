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

    /// Formats for display using the supplied currency code, defaulting to the device's currency.
    func formatted(currencyCode: String? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        let code = currencyCode ?? locale.currency?.identifier ?? "USD"
        return rounded().amount.formatted(.currency(code: code).locale(locale))
    }
}
