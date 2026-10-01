import Foundation

/// Which stop two or more deliveries of one offer were recorded as sharing.
///
/// ## Two kinds, because they are two facts
///
/// A platform offer sometimes holds two orders that belong together: one
/// customer, one door. Whether they are also **collected** together is a
/// different question with a different answer, because one customer can order
/// from two restaurants. So a shared drop-off and a shared pickup are recorded
/// separately, each only when the driver says so, and neither implies the
/// other.
///
/// The difference matters because of what reads them. The Park and Resume
/// pickup workflow records Arrived at Pickup and Picked Up, which are facts
/// about **a pickup**; it reads ``pickup`` and nothing else. Two deliveries
/// going to one customer from two restaurants must not both be marked arrived
/// because the driver parked at the first restaurant, and reading ``dropOff``
/// there is exactly how that would happen.
///
/// ## Never inferred
///
/// Nothing here is ever derived from two deliveries being accepted together,
/// naming the same pickup place, carrying consecutive numbers, being accepted a
/// second apart or following a similar route. Every one of those is also what
/// two unrelated orders look like, and DashPilot sees no platform screen that
/// could tell them apart. A shared stop exists because the driver said so, and
/// history recorded before it could be said has none.
///
/// ## Private by construction
///
/// It is an opaque identity on each delivery. No customer, no address, no name
/// and no coordinate is stored for it, and none is needed: two deliveries
/// holding the same value are one stop, and that is all the value says.
nonisolated enum SharedStopKind: String, CaseIterable, Hashable, Sendable {
    /// Collected at the same pickup, which is what the pickup workflow reads.
    case pickup
    /// Taken to the same drop-off: one customer, one door.
    case dropOff

    /// The words a driver chooses on screen: short enough to read while
    /// stopped, and naming the stop rather than anybody at it.
    var title: String {
        switch self {
        case .pickup: "Same pickup"
        case .dropOff: "Same drop-off"
        }
    }
}

/// Why a shared stop could not be recorded as described.
nonisolated enum SharedStopError: Error, Equatable {
    /// A delivery named for the shared stop is not part of the offer it was
    /// recorded in. A shared stop is a statement about deliveries accepted
    /// together, so a delivery from another offer cannot join one.
    case deliveryOutsideOffer
    /// Exactly one delivery was named. One delivery sharing a stop with nobody
    /// states nothing; naming none takes the statement back.
    case onlyOneDelivery
}

/// Which stops one delivery shares, and with which of its siblings, in words.
///
/// Presentation only: it reads the two identities the driver recorded and
/// names the other deliveries of the same offer holding the same one. It never
/// says which customer or which restaurant, because DashPilot does not know,
/// and it never says the deliveries *are* at one place: it says the driver
/// recorded them that way.
nonisolated struct SharedStopDescription: Equatable, Sendable {
    /// The other deliveries sharing this one's pickup, by name, in number order.
    let pickupSiblings: [String]
    /// The other deliveries sharing this one's drop-off, by name, in number
    /// order.
    let dropOffSiblings: [String]

    /// Nothing shared: the ordinary case.
    var isEmpty: Bool { pickupSiblings.isEmpty && dropOffSiblings.isEmpty }

    /// - Parameters:
    ///   - numbered: the delivery described.
    ///   - offer: every delivery of its offer, numbered as the shift numbers
    ///     them.
    init(of numbered: NumberedDelivery, among offer: [NumberedDelivery]) {
        func siblings(_ kind: SharedStopKind) -> [String] {
            guard let identity = numbered.delivery.sharedStopID(kind) else { return [] }
            return offer
                .filter { $0.id != numbered.id && $0.delivery.sharedStopID(kind) == identity }
                .sorted { $0.number < $1.number }
                .map(\.title)
        }
        pickupSiblings = siblings(.pickup)
        dropOffSiblings = siblings(.dropOff)
    }

    /// `Same pickup and drop-off as Delivery 4`, `Same drop-off as Delivery 4`,
    /// or `nil` when nothing is shared.
    ///
    /// One line, because it sits on a card a driver reads between steps. When
    /// both kinds name the same siblings they are said once; when they differ,
    /// each is said with its own names.
    var caption: String? {
        switch (pickupSiblings.isEmpty, dropOffSiblings.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return "\(SharedStopKind.pickup.title) as \(Self.list(pickupSiblings))"
        case (true, false):
            return "\(SharedStopKind.dropOff.title) as \(Self.list(dropOffSiblings))"
        case (false, false):
            guard pickupSiblings != dropOffSiblings else {
                return "Same pickup and drop-off as \(Self.list(pickupSiblings))"
            }
            return """
            \(SharedStopKind.pickup.title) as \(Self.list(pickupSiblings)) · \
            \(SharedStopKind.dropOff.title) as \(Self.list(dropOffSiblings))
            """
        }
    }

    /// The same statement as a sentence a listener can place: that the driver
    /// recorded it, rather than that DashPilot knows it.
    var spokenCaption: String? {
        guard let caption else { return nil }
        let clauses = caption.components(separatedBy: " · ").map { "the \($0.prefix(1).lowercased())\($0.dropFirst())" }
        return "You recorded it as \(clauses.joined(separator: ", and "))"
    }

    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and \(last)"
    }
}
