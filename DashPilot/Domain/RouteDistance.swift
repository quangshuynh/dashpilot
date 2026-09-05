import Foundation

/// What DashPilot can honestly say about the distance a shift recorded.
///
/// A bare `Double` would be a claim the data does not support. Foreground-only
/// capture means a route is a set of stretches with gaps between them, and a
/// number on its own cannot say whether it covers the whole shift, part of it,
/// or nothing measurable at all. Every field here exists because the interface
/// has to be able to say something different because of it.
///
/// The distance is held in metres. Miles are a presentation choice for the
/// drivers this app is for, and the conversion happens in one place —
/// ``measurement``, ``miles`` and ``formattedMiles(locale:)`` — rather than as a
/// constant copied into views or into a calculation that divides by mileage.
nonisolated struct RouteDistance: Equatable, Sendable {
    /// Distance recorded within continuous capture, in metres.
    ///
    /// Never includes the straight line across a gap: what was driven while
    /// capture was stopped is unknown, and a straight line is a guess.
    let metres: Double

    /// Unbroken stretches of two or more positions that contributed distance.
    let segmentCount: Int

    /// Stretches of the shift the route does not account for.
    ///
    /// A break between two retained positions, and — when the shift's own window
    /// was supplied — a route that starts long after the shift did or stops long
    /// before it ended. Each is a stretch that was driven but not recorded, or
    /// one where the vehicle was parked; the route cannot tell which, so the
    /// distance across it is left out either way.
    let gapCount: Int

    /// Stored positions the calculation could use, after malformed ones were
    /// discarded and positions sharing a timestamp were collapsed.
    let usableSampleCount: Int

    /// Whether any distance was counted between positions whose continuity was
    /// inferred from their timestamps rather than recorded.
    ///
    /// True only for routes stored before schema v3, which carry no capture
    /// session. Gaps shorter than the calculation's threshold are invisible in
    /// such a route, so its total is a floor with unknown gaps in it.
    let usesInferredContinuity: Bool

    /// A shift with nothing measurable in its route.
    static let none = RouteDistance(
        metres: 0,
        segmentCount: 0,
        gapCount: 0,
        usableSampleCount: 0,
        usesInferredContinuity: false
    )

    /// Whether a distance was measured at all.
    ///
    /// False when the route holds no two positions that were recorded
    /// continuously — an empty route, a single position, or positions that are
    /// all separated by gaps. Distance is `0` in that case because nothing was
    /// measured, which is not the same statement as "the vehicle did not move",
    /// and the interface must not present it as one.
    var isMeasured: Bool { segmentCount > 0 }

    /// Whether the distance is known to be less than the distance driven.
    ///
    /// True when capture stopped at least once during the shift, and true for a
    /// legacy route whose gaps cannot be seen. Foreground-only capture makes
    /// this the ordinary case rather than an exception: a driver who switches to
    /// another app has left DashPilot, and the route stops there.
    var isPartial: Bool { gapCount > 0 || usesInferredContinuity }

    /// The distance as a unit-carrying value, for conversion and formatting.
    var measurement: Measurement<UnitLength> { Measurement(value: metres, unit: .meters) }

    /// The distance in miles.
    ///
    /// The one conversion, shared by the formatted string and by any
    /// calculation that divides by mileage, so nothing re-derives a
    /// metres-to-miles constant of its own and no two parts of the app can
    /// disagree about what a mile is.
    var miles: Double { measurement.converted(to: .miles).value }

    /// The distance in miles, rendered to one decimal place, e.g. `"12.4 mi"`.
    ///
    /// One decimal is what the measurement supports: positions carry error
    /// radii of up to 100 m and a shift's gaps are unmeasured, so a second
    /// decimal would be describing precision the number does not have.
    ///
    /// `width` exists for VoiceOver: `mi` reads well and hears badly, so a
    /// spoken description asks for `.wide` and gets `"12.4 miles"` from the same
    /// conversion and the same rounding rule. Nothing rewrites the abbreviated
    /// string into words.
    func formattedMiles(
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        measurement.converted(to: .miles).formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1))
            )
            .locale(locale)
        )
    }
}
