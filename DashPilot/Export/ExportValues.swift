import Foundation

/// How a monetary amount is written into an exported file.
///
/// **A decimal string, never a JSON number.** A `Decimal` encoded as a JSON
/// number is re-read by most parsers as an IEEE double, so `86.25` survives and
/// a great many other amounts do not — and the loss happens outside DashPilot,
/// after the file has left, where nothing can notice it. A string crosses every
/// parser unchanged and is what a spreadsheet reads as a number anyway.
///
/// The amount is written at ``Money/displayScale`` fraction digits, which is
/// lossless for everything the app can hold: the input layer rejects anything
/// finer than a cent, so a recorded amount is already exact at two places. A
/// derived rate is kept internally at six and is rounded here to the two the
/// app displays, so an exported rate matches the figure on screen rather than
/// carrying digits no interface ever showed.
///
/// No currency symbol, no grouping separator and no locale. Which currency the
/// amounts are in is stated once per shift, as ``Money/displayCurrencyCode``.
nonisolated struct ExportAmount: Equatable, Sendable, Codable {
    /// The amount **as the file states it**, already at ``Money/displayScale``.
    ///
    /// Rounded on the way in rather than on the way out, so this value and
    /// ``string`` cannot disagree and a file read back gives exactly what was
    /// written. For a recorded amount the rounding changes nothing — the input
    /// layer rejects anything finer than a cent — and for a derived rate it is
    /// the same rounding the screen applies.
    let money: Money

    init(_ money: Money) {
        self.money = money.rounded(scale: Money.displayScale)
    }

    /// The canonical string, e.g. `"86.25"`, `"0.00"`.
    var string: String {
        money.amount.formatted(
            .number
                .precision(.fractionLength(Money.displayScale))
                .grouping(.never)
                .locale(Self.canonicalLocale)
        )
    }

    /// `en_US_POSIX`, so the separator is a full stop wherever the device is
    /// set. An exported file is a data interchange, not a screen.
    private static let canonicalLocale = Locale(identifier: "en_US_POSIX")

    init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let money = Money(exact: string) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a canonical decimal amount such as \"86.25\"."
                )
            )
        }
        self.money = money
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

nonisolated extension ExportAmount {
    /// The amount for a recorded figure, or `nil` when none was recorded.
    ///
    /// The whole point of the optional: a shift or a delivery with no amount
    /// exports an absence, never `"0.00"`.
    static func recorded(_ money: Money?) -> ExportAmount? {
        money.map(ExportAmount.init)
    }
}

/// How a moment is written into an exported file.
///
/// One format everywhere, in both JSON and CSV: ISO 8601 in UTC, to the second,
/// e.g. `2026-09-05T13:04:05Z`. It is unambiguous, it sorts lexicographically,
/// and it is the same string whatever the device's locale, region or calendar
/// happens to be — which a formatted display date is not.
///
/// The device's time zone is deliberately **not** exported. An instant in UTC
/// says exactly when something happened; the driver's own zone would say
/// roughly where they live, and no figure in this file needs it.
nonisolated enum ExportTimestamp {
    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(_ string: String) -> Date? {
        formatter.date(from: string)
    }

    /// One formatter, shared by the JSON encoder's strategy and by the CSV
    /// writer, so the two files cannot disagree about what a timestamp looks
    /// like. `ISO8601DateFormatter` is documented as thread-safe once
    /// configured.
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

/// How a duration is written into an exported file.
///
/// **Whole seconds**, and the field names say so — `elapsedSeconds`,
/// `pickupWaitSeconds`. A base unit is what a consumer can divide, sum and
/// convert; a formatted string such as `1 hr 12 min` is a reading of one, and
/// it is locale-dependent. Nothing in an export is written as a formatted
/// duration.
///
/// Sub-second precision is dropped rather than carried: every duration in
/// DashPilot is the difference between two `Date`s a driver produced by
/// tapping, and a millisecond of that is noise.
nonisolated enum ExportDuration {
    /// A duration in whole seconds, or `nil` when there is none to report.
    ///
    /// `nil` in, `nil` out — an absent duration is never a zero. A value that
    /// is not a usable measurement (not finite, negative, or too large to be a
    /// count of seconds) is also `nil`, because a stored row the app cannot
    /// have written must not be exported as a real duration.
    static func seconds(_ duration: TimeInterval?) -> Int? {
        guard let duration, duration.isFinite, duration >= 0 else { return nil }
        return Int(exactly: duration.rounded())
    }
}

/// How a distance is written into an exported file.
///
/// **Metres are authoritative**, and miles are included beside them as a
/// convenience derived from the same measurement — never as a second source.
/// The field names carry the word the app carries everywhere else:
/// `recordedDistanceMetres`, not `totalDistance`, and never `milesDriven`.
/// Recorded mileage is a floor on the mileage driven, and the route fields
/// exported alongside it are what say by how much it may be short.
nonisolated enum ExportDistance {
    /// Fraction digits kept on metres. A tenth of a metre is already far finer
    /// than positions carrying error radii of up to 100 m.
    static let metresScale = 1

    /// Fraction digits kept on miles, so the derived figure does not lose
    /// precision the metres still hold.
    static let milesScale = 4

    /// The distance a route measured, or `nil` when it measured none.
    ///
    /// A route with nothing measurable exports `null`, never `0`. "No distance
    /// could be measured" and "the vehicle did not move" are different facts,
    /// and a zero in a spreadsheet column is read as the second.
    static func metres(of distance: RouteDistance) -> Double? {
        guard distance.isMeasured else { return nil }
        return rounded(distance.metres, scale: metresScale)
    }

    /// The same measurement in miles, from ``RouteDistance/miles`` so nothing
    /// re-derives a conversion constant of its own.
    static func miles(of distance: RouteDistance) -> Double? {
        guard distance.isMeasured else { return nil }
        return rounded(distance.miles, scale: milesScale)
    }

    private static func rounded(_ value: Double, scale: Int) -> Double? {
        guard value.isFinite else { return nil }
        let factor = pow(10.0, Double(scale))
        let scaled = (value * factor).rounded()
        guard scaled.isFinite else { return nil }
        return scaled / factor
    }
}
