import Foundation

/// Which stop two or more deliveries of one shift were recorded as sharing.
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
    /// A delivery named on the offer's own screen is not part of that offer.
    /// That screen restates one offer, so it names only that offer's
    /// deliveries; deliveries of different offers are joined from the running
    /// shift's stack instead.
    case deliveryOutsideOffer
    /// A delivery named is not part of the shift whose stops are being edited.
    /// A stop is shared among one shift's deliveries, never across shifts.
    case deliveryOutsideShift
    /// The running shift's stack editor named a delivery that has finished.
    /// That screen corrects the deliveries in progress; a finished one keeps
    /// its stops and is corrected from Correct Grouping.
    case deliveryNotInProgress
    /// Exactly one delivery was named. One delivery sharing a stop with nobody
    /// states nothing; naming none takes the statement back.
    case onlyOneDelivery
    /// Nothing was named.
    case noDeliveries
}

/// What the driver asks of some deliveries' shared stops, for one kind.
nonisolated enum SharedStopEdit: Equatable, Sendable {
    /// The named deliveries share this kind of stop.
    ///
    /// **Additive.** A stop is one place, so a delivery already sharing it with
    /// another keeps that statement: joining Delivery 2 to Delivery 3, when the
    /// driver had already said Delivery 2 and Delivery 1 share a pickup, is the
    /// statement that all three do. Taking a delivery out of a group is
    /// ``separate``, said explicitly.
    case join
    /// The named deliveries share this kind of stop with nobody. A group left
    /// with one delivery stops claiming anything.
    case separate
}

/// The shared-stop identities of one shift's deliveries after an edit, worked
/// out before anything is written.
///
/// ## Scope: one shift, by the driver's statement
///
/// A shared stop is a fact about **stops**, not about acceptance. Two orders a
/// platform offered separately, the second added while the driver waited at
/// the first one's counter, are collected at one pickup all the same, and
/// before this a driver who learned it mid-shift could only say so by
/// cancelling both and recording them again as one offer (October 3 2026).
/// So an identity may be held by any deliveries of one shift. It is still
/// written only when the driver says so: nothing here reads offers, acceptance
/// times, numbers, pickup places, states or positions.
///
/// ## What it never touches
///
/// Identities only. No lifecycle instant, number, offer, amount or route is an
/// input or an output, so an edit cannot move any of them. The plan covers
/// every delivery of the shift so that a group holding a finished delivery is
/// kept whole rather than silently split by a screen that only shows the
/// deliveries in progress.
nonisolated struct SharedStopRegrouping: Equatable, Sendable {
    /// Each delivery's identity after the edit; a delivery absent here shares
    /// nothing.
    let identities: [UUID: UUID]

    /// - Parameters:
    ///   - edit: what the driver asked.
    ///   - selected: the deliveries named.
    ///   - current: every delivery of the shift holding an identity for this
    ///     kind now.
    ///   - members: every delivery of the shift.
    ///   - eligible: the deliveries this screen lets the driver name; `nil` for
    ///     all of `members`.
    ///   - fresh: the identity a new group takes; injected so tests can name it.
    init(
        _ edit: SharedStopEdit,
        selecting selected: Set<UUID>,
        current: [UUID: UUID],
        members: Set<UUID>,
        eligible: Set<UUID>? = nil,
        fresh: UUID = UUID()
    ) throws(SharedStopError) {
        guard !selected.isEmpty else { throw .noDeliveries }
        guard selected.isSubset(of: members) else { throw .deliveryOutsideShift }
        if let eligible, !selected.isSubset(of: eligible) { throw .deliveryNotInProgress }

        var result = current.filter { members.contains($0.key) }
        switch edit {
        case .join:
            guard selected.count > 1 else { throw .onlyOneDelivery }
            let touched = Set(selected.compactMap { result[$0] })
            let group = selected.union(result.filter { touched.contains($0.value) }.keys)
            for delivery in group { result[delivery] = fresh }
        case .separate:
            for delivery in selected { result[delivery] = nil }
        }
        identities = Self.dissolvingSingletons(result)
    }

    /// The offer screen's restatement: exactly `selected` share this kind of
    /// stop among `scope` (one offer's deliveries), and nobody else in `scope`
    /// shares it. Deliveries outside `scope` keep their own statements, except
    /// that a group left holding one delivery stops claiming anything.
    init(
        restating selected: Set<UUID>,
        within scope: Set<UUID>,
        current: [UUID: UUID],
        members: Set<UUID>,
        fresh: UUID = UUID()
    ) throws(SharedStopError) {
        guard selected.isSubset(of: scope) else { throw .deliveryOutsideOffer }
        guard selected.count != 1 else { throw .onlyOneDelivery }
        var result = current.filter { members.contains($0.key) && !scope.contains($0.key) }
        for delivery in selected { result[delivery] = fresh }
        identities = Self.dissolvingSingletons(result)
    }

    /// The deliveries whose identity this plan changes, against `current`.
    func changes(from current: [UUID: UUID], members: Set<UUID>) -> Set<UUID> {
        Set(members.filter { identities[$0] != current[$0] })
    }

    /// An identity only states something when at least two deliveries hold it.
    static func dissolvingSingletons(_ identities: [UUID: UUID]) -> [UUID: UUID] {
        let counts = Dictionary(grouping: identities.values) { $0 }.mapValues(\.count)
        return identities.filter { counts[$0.value, default: 0] > 1 }
    }
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
    ///   - offer: the deliveries to name siblings from, numbered as the shift
    ///     numbers them: its shift's, or one offer's on the offer screen.
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

nonisolated extension NumberedDelivery {
    /// Which stops this delivery shares, naming the other deliveries **of its
    /// shift** that hold the same identity, numbered as the shift numbers them.
    ///
    /// The shift rather than the offer, because a stop may be shared by
    /// deliveries of different offers (see ``SharedStopRegrouping``); a caption
    /// that looked only inside the offer would say nothing about exactly the
    /// case the stack editor exists for.
    var sharedStops: SharedStopDescription {
        SharedStopDescription(of: self, among: delivery.shift?.numberedDeliveries ?? [self])
    }
}

