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
/// - **``parkAutomation``**: Park, under the driver's `Pick up order when
///   parking` setting. It is recorded when the driver **parks**, which is
///   usually before they walk in, so the pickup wait it closes ends before the
///   order was handed over.
///
/// Measured through the app's own median, pickups of the second kind can move
/// a place's typical wait by minutes, and nothing in the timestamps can tell
/// the two apart afterwards. So the kind is written with the event, at the one
/// moment it is known.
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
    /// Recorded by Park, because the driver's setting asked for it.
    case parkAutomation

    /// The stored value read back, or `nil` for a value this build does not
    /// know. A value it does not recognise is unknown, never guessed.
    static func stored(_ rawValue: String?) -> PickupProvenance? {
        rawValue.flatMap(PickupProvenance.init(rawValue:))
    }

    /// A structural description, safe for a log line: it names the kind of
    /// recording and nothing about the delivery, the place or the time.
    var logDescription: String {
        switch self {
        case .manual: "pickup recorded manually"
        case .parkAutomation: "pickup recorded by configured park automation"
        }
    }
}
