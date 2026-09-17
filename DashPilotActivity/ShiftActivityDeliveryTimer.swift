import Foundation

/// How long one delivery in progress has been active, as an anchor rather than
/// as a figure.
///
/// ## It carries a start, not a duration
///
/// The whole point of the type. A duration written into a snapshot is wrong a
/// second later, and keeping it right would mean pushing a new snapshot every
/// second for every open order. An acceptance instant is correct for as long as
/// the delivery is open, so the system draws the clock from it and the app
/// pushes nothing. That is exactly what
/// ``ShiftActivityAttributes/ContentState/workingTimerAnchor`` does for the
/// shift's own clock, and for the same reason.
///
/// ## The instant is the delivery's own
///
/// ``startedAt`` is the delivery's `acceptedAt`: the same instant
/// `DeliveryActiveInterval` starts at, the same one `completedDuration`
/// measures from once the delivery finishes, and the same one the shift's
/// delivery active time unions. **No second definition of when a delivery began
/// exists**, and nothing here is persisted.
///
/// It is **not** pause-adjusted, because a delivery's own elapsed lifecycle
/// never has been: a shift cannot be paused while a delivery is open, and the
/// duration this counts towards is the one a finished delivery reports.
///
/// ## Why the title is a finished string
///
/// `NumberedDelivery.title(number:)` is the one place in the project that
/// decides a delivery is called `Delivery 2`, and it lives in the app. The
/// extension renders what the app derived, exactly as it does for the mileage
/// sentence and the delivery status, so the Lock Screen cannot drift into
/// calling a delivery something the app does not.
nonisolated struct ShiftActivityDeliveryTimer: Codable, Hashable, Sendable {
    /// What the app calls this delivery: `"Delivery 2"`.
    ///
    /// A count within the shift, and nothing else. Not a platform order number,
    /// not a place, not an address: those are either facts DashPilot does not
    /// hold or facts this surface must not print.
    let title: String

    /// The delivery's own `acceptedAt`.
    let startedAt: Date

    init(title: String, startedAt: Date) {
        self.title = title
        self.startedAt = startedAt
    }
}

nonisolated extension ShiftActivityDeliveryTimer {
    /// The range a counting-up timer is drawn over.
    ///
    /// Open ended, for the reason the shift's clock is: any horizon short
    /// enough to write down is one a long delivery can outlive, and a clock
    /// that silently stops is worse than one that keeps counting.
    var timerRange: ClosedRange<Date> { startedAt...Date.distantFuture }

    /// What VoiceOver hears **beside** the live figure, never instead of it.
    ///
    /// The figure itself is the system's, drawn and spoken from the anchor, so
    /// labelling that element would replace a live duration with whatever this
    /// snapshot happened to be built at. The label therefore sits on its own
    /// element ahead of it, which is the same arrangement the shift's clock
    /// uses, and it says what the number that follows measures rather than
    /// leaving a bare duration to be guessed at.
    var spokenLabel: String { "How long \(title) has been active" }

    /// How long the delivery had been active when the snapshot was built.
    ///
    /// The inverse of ``timerRange``, and the only place a duration is derived
    /// from the anchor. It exists for the one surface that has no live element
    /// to read: the Dynamic Island's minimal presentation, whose whole spoken
    /// value is a single frozen sentence. Clamped for the reason every other
    /// duration in the project is clamped: a store holding an anomalous row
    /// must not produce a negative one.
    func elapsed(asOf: Date) -> TimeInterval { max(0, asOf.timeIntervalSince(startedAt)) }

    /// The same fact as one spoken sentence, frozen at `asOf`.
    ///
    /// Spelled-out units rather than a clock string, because a colon is heard
    /// as punctuation. The wording says *active for*, which is what the
    /// lifecycle measures, and deliberately not *worked*, *driven* or *spent*:
    /// DashPilot knows the delivery had not finished, and nothing more.
    func spokenElapsed(asOf: Date) -> String {
        let figure = Duration.seconds(elapsed(asOf: asOf))
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return "\(title) active for \(figure)"
    }
}
