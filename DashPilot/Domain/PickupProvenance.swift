import Foundation

/// How a delivery's Picked Up event was recorded.
///
/// ## Why the app records it
///
/// Every other lifecycle event is written by a control the driver pressed for
/// that event. Picked Up has two writers, and they mean different instants:
///
/// - **``manual``**: the driver's own Picked Up step, from the delivery's card,
///   by voice or from the Lock Screen. It is recorded when the driver says the
///   order is in hand.
/// - **``resumeAutomation``**: Resume Driving, under the driver's `Pick up
///   orders with Park & Resume` setting, for the delivery Park recorded at its
///   pickup. It is recorded when the driver **drives off**, which is after they
///   have walked back to the vehicle, so the wait it closes ends after the order
///   was handed over.
/// - **``parkAutomation``**: Park, under the earlier `Pick up order when
///   parking` setting that the workflow above replaced. It was recorded when
///   the driver **parked**, usually before they walked in, so the wait it closes
///   ends before the handover. Nothing records it any more; it stays readable
///   because stores written while that setting existed hold it.
///
/// Measured through the app's own median, pickups of either automated kind can
/// move a place's typical wait by minutes, in opposite directions, and nothing
/// in the timestamps can tell any kind apart afterwards. So the kind is written
/// with the event, at the one moment it is known.
///
/// ## Unknown is a third answer, and it is not stored
///
/// A pickup recorded before the app kept this reads as **unknown**: the stored
/// column is `nil`. That includes pickups a build with the setting may have
/// recorded by parking, which is exactly why migration does not write
/// ``manual`` into them. Nothing infers the kind from timestamps, from a parked
/// stretch or from the current setting, then or later.
///
/// ## What it is not
///
/// It is not a second timestamp, a state or a correction marker. Correcting a
/// pickup's recorded time moves the instant and leaves this alone, and nothing
/// here says whether the recorded instant is right.
nonisolated enum PickupProvenance: String, CaseIterable, Sendable, Hashable, Codable {
    /// Recorded by the driver's Picked Up step, on any surface.
    case manual
    /// Recorded by Park, under the retired `Pick up order when parking`
    /// setting. Read, never written.
    case parkAutomation
    /// Recorded by Resume Driving, because the driver's pickup workflow asked
    /// for it.
    case resumeAutomation

    /// Whether a control the driver pressed for **another** reason recorded it.
    ///
    /// Such a pickup's instant is when the driver parked or drove off, not when
    /// they said the order was in hand, which is why no typical wait counts it.
    var isAutomated: Bool {
        switch self {
        case .manual: false
        case .parkAutomation, .resumeAutomation: true
        }
    }

    /// The stored value read back, or `nil` for a value this build does not
    /// know. A value it does not recognise is unknown, never guessed.
    static func stored(_ rawValue: String?) -> PickupProvenance? {
        rawValue.flatMap(PickupProvenance.init(rawValue:))
    }

    /// What a delivery's history calls a pickup recorded this way.
    ///
    /// Only an automated one is qualified: the event row is where a driver
    /// reviewing a shift sees why this delivery's wait is left out of their
    /// typical waits. It says who recorded the instant, not that the instant is
    /// wrong, because a corrected pickup keeps its provenance.
    static func pickedUpEventTitle(_ provenance: PickupProvenance?) -> String {
        switch provenance {
        case .parkAutomation: "Picked up (recorded by Park)"
        case .resumeAutomation: "Picked up (recorded by Resume Driving)"
        case .manual, nil: "Picked up"
        }
    }

    /// A structural description, safe for a log line: it names the kind of
    /// recording and nothing about the delivery, the place or the time.
    var logDescription: String {
        switch self {
        case .manual: "pickup recorded manually"
        case .parkAutomation: "pickup recorded by configured park automation"
        case .resumeAutomation: "pickup recorded by configured resume automation"
        }
    }
}
