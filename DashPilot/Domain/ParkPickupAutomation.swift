import Foundation

/// Which delivery, if any, a press of Park may also record as picked up.
///
/// ## The one transition it can truthfully support
///
/// **Arrived at Pickup to Picked Up, and nothing else.** A delivery's lifecycle
/// is `accepted`, `arrivedAtPickup`, `pickedUp`, then `delivered` or
/// `cancelled`, and ``Delivery/markPickedUp(at:)`` refuses a delivery with no
/// recorded arrival. So:
///
/// - **Arrived at Pickup** is eligible. The driver has already said they are at
///   the pickup; Park is the tap before they walk in, and the setting is their
///   instruction that this tap also means the order.
/// - **Accepted** is not. Reaching Picked Up would take two events, and the
///   arrival would be one DashPilot has no evidence for: the driver never said
///   it, and Park is not a statement about *which* place the vehicle stopped
///   at. Writing both at one instant would also record a pickup wait of exactly
///   zero, which is a sample of a wait that never happened entering the
///   per-place medians. It is counted as ``awaitingArrival`` so the driver can
///   be told why nothing was recorded.
/// - **Picked Up**, **Delivered** and **Cancelled** are not. The order is
///   already in the car, or the delivery is over.
///
/// ## Stacked deliveries
///
/// **Exactly one eligible delivery is advanced; two or more advance none.**
/// With two orders waiting at pickups, the oldest, the newest, the first card
/// and the nearest are each a guess about which order the driver is walking in
/// for, and the mistake would be written into a record they did not mean. It is
/// the principle ``UnambiguousDelivery`` holds for a step that names no
/// delivery, applied to the subset that could receive this step. A delivery
/// already picked up does not make the choice ambiguous, because it could not
/// receive the step at all.
///
/// Generic over the element, like ``UnambiguousDelivery``: the service resolves
/// a `Delivery`, and the tests resolve plain states.
nonisolated enum ParkPickupSelection<Element> {
    /// Exactly one delivery can receive the pickup step.
    case one(Element)
    /// Two or more could, so none is advanced.
    case several(count: Int)
    /// None could. `awaitingArrival` counts the deliveries still accepted, whose
    /// arrival was never recorded.
    case none(awaitingArrival: Int)

    /// The whole rule, over the deliveries in progress.
    static func select(among active: [Element], state: (Element) -> DeliveryState) -> Self {
        let eligible = active.filter { state($0) == .arrivedAtPickup }
        switch eligible.count {
        case 0:
            return .none(awaitingArrival: active.filter { state($0) == .accepted }.count)
        case 1:
            return .one(eligible[0])
        default:
            return .several(count: eligible.count)
        }
    }
}

/// What a press of Park did about a pickup, and the sentence that says so.
///
/// Parking has already been recorded by the time any of these exists: every
/// case describes a parked vehicle. The sentences say what was **recorded**
/// because of the driver's setting, and never that DashPilot saw an order
/// handed over, because it did not.
nonisolated enum ParkPickupOutcome: Equatable, Sendable {
    /// The setting is off. Parking did exactly what it always did.
    case notEnabled
    /// The one delivery waiting at a pickup was recorded as picked up.
    ///
    /// The number is optional for the reason every delivery number in a
    /// confirmation is: a delivery whose shift cannot be read is not given a
    /// name the app did not identify.
    case recorded(deliveryNumber: Int?)
    /// `count` deliveries were waiting at pickups, so none was advanced.
    case severalAtPickup(count: Int)
    /// No delivery was waiting at a pickup. `awaitingArrival` counts those still
    /// accepted.
    case noneAtPickup(awaitingArrival: Int)
    /// One delivery could have received the step, and the write was refused or
    /// failed. The vehicle is still parked.
    case notRecorded(deliveryNumber: Int?)

    /// Whether a delivery moved.
    var recordedPickup: Bool {
        if case .recorded = self { true } else { false }
    }

    /// The printed line beneath the parked notice, or `nil` when there is
    /// nothing to add to ordinary parking.
    ///
    /// Silent while the setting is off, and silent when nothing was waiting at a
    /// pickup and nothing was still on its way to one: a driver parking with
    /// every order in the car is parking, and the automation had no question to
    /// answer.
    var statement: String? {
        switch self {
        case .notEnabled:
            nil
        case let .recorded(number):
            "\(Self.name(number)) marked Picked Up when you parked."
        case let .severalAtPickup(count):
            """
            Pickup not recorded: \(count) deliveries are at a pickup, so DashPilot could not tell \
            which one you meant. Record it on the delivery's card.
            """
        case let .noneAtPickup(awaitingArrival):
            awaitingArrival > 0
                ? "Pickup not recorded: no delivery has Arrived at Pickup recorded."
                : nil
        case let .notRecorded(number):
            "\(Self.name(number)) pickup was not recorded. Record it on the delivery's card."
        }
    }

    /// What VoiceOver says for the line, naming the setting that caused it so a
    /// listener knows the event was their automation rather than a detection.
    var spokenStatement: String? {
        guard let statement else { return nil }
        switch self {
        case .recorded:
            return "\(statement) Recorded by your Pick up order when parking setting."
        default:
            return statement
        }
    }

    /// A symbol that says whether a pickup was recorded without relying on the
    /// tint it is drawn in.
    var symbolName: String {
        recordedPickup ? "shippingbox.fill" : "info.circle"
    }

    private static func name(_ number: Int?) -> String {
        guard let number else { return "Delivery" }
        return NumberedDelivery.title(number: number)
    }
}
