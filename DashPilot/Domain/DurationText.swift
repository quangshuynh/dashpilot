import Foundation

/// How DashPilot writes and speaks a recorded duration.
///
/// One rule, in one place, because the same duration is written on a shift, on a
/// delivery and on a pickup place's history, and three copies of the unit choice
/// would drift apart. Presentation rounds; nothing here is used to calculate.
///
/// Durations under a minute read in minutes and seconds, so a shift ended
/// moments after it started reads as `12 sec` rather than as `0 min`. Everything
/// longer reads in hours and minutes: `8 min`, `1 hr 12 min`. Fractional seconds
/// are never shown — a median of two waits may land on a half second, and a
/// driver has no use for it.
///
/// ``spoken(_:)`` exists for VoiceOver, for the reason ``RouteDistance`` takes a
/// width: `hr` reads well and hears badly, so a spoken description asks for the
/// wide units and gets "1 hour, 12 minutes" from the same rule. Nothing rewrites
/// the abbreviated string into words.
nonisolated enum DurationText {
    /// The short form, for the screen.
    static func short(_ duration: TimeInterval) -> String {
        text(duration, width: .abbreviated)
    }

    /// The spoken form, for VoiceOver.
    static func spoken(_ duration: TimeInterval) -> String {
        text(duration, width: .wide)
    }

    static func text(_ duration: TimeInterval, width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = duration < 60
            ? [.minutes, .seconds]
            : [.hours, .minutes]
        return Duration.seconds(duration).formatted(.units(allowed: units, width: width))
    }
}
