import Foundation
import SwiftData

/// A place a driver picks orders up from, named by the driver and reused across
/// deliveries.
///
/// ## What this is
///
/// One row per pickup place the driver has named, holding the spelling they
/// chose and the key that decides whether a later spelling means the same place.
/// It is a local catalogue of *their* vocabulary, built entirely out of what
/// they typed.
///
/// ## What it is not
///
/// It is not a merchant record. There is no address, no coordinate, no phone
/// number, no store number, no chain, no category, no platform identifier and no
/// link to anything outside the device. DashPilot performs no geocoding, no
/// place search and no lookup of any kind, so nothing here was obtained from a
/// delivery platform or a directory, and nothing here would be recognised
/// outside this app.
///
/// ## Why an entity rather than a string on each delivery
///
/// `McDonald's`, `mcdonalds` and `McDonald's ` typed on three nights are one
/// place. Stored as free text on three deliveries they would be three unrelated
/// strings, and the history that later wants to ask "how long do I wait here"
/// would have no stable thing to group by. A shared row gives that question one
/// answer, decided once when the name is entered rather than guessed afterwards.
///
/// ## No counters
///
/// Nothing aggregated is stored here — no visit count, no last-used date, no
/// average wait, no score. Every one of those is derivable from the deliveries
/// that reference this place, and a stored copy is a second answer free to drift
/// away from the first. The same rule the rest of DashPilot follows for mileage,
/// rates and delivery state.
@Model
nonisolated final class PickupPlace {
    /// Stable identifier, used for cross-store references and future export.
    @Attribute(.unique) private(set) var id: UUID

    /// The spelling shown to the driver.
    ///
    /// The **first** accepted spelling wins and is never rewritten: a later
    /// `mcdonalds` reuses this place without changing what it is called. Silently
    /// restyling a name a driver has been reading all week is a surprise, and
    /// picking the "better" of two spellings is not a judgement this app is in a
    /// position to make.
    private(set) var displayName: String

    /// The key deliveries are matched by, from ``PickupPlaceName``.
    ///
    /// Not shown, not spoken and not logged. Persisted rather than derived on
    /// read so the catalogue can be searched by it with one fetch instead of
    /// loading and folding every row.
    ///
    /// Deliberately **not** a `.unique` attribute. A unique constraint in
    /// SwiftData turns a colliding insert into an upsert, which would silently
    /// overwrite an existing place rather than reuse it, and it would bind the
    /// store's shape to a normalisation policy that is allowed to be improved.
    /// Uniqueness is enforced where the rule lives instead — see
    /// ``PickupPlaceService``.
    private(set) var normalizedName: String

    /// When this place was first named on this device.
    ///
    /// Kept for ordering rather than for analysis: it is the tie-break that makes
    /// "recently used" total and repeatable when two places have equal claim, and
    /// it is what identifies the original row if a store somehow holds two with
    /// the same key.
    private(set) var createdAt: Date

    /// The deliveries that reference this place, in no guaranteed order.
    ///
    /// The delete rule is `.nullify`, and the distinction matters: a pickup place
    /// is shared, so deleting one must not take the deliveries with it. It is
    /// also why `Delivery.pickupPlace` is an ordinary optional reference —
    /// deleting a delivery, or the whole shift it belongs to, leaves the place
    /// standing for every other delivery that still names it.
    @Relationship(deleteRule: .nullify, inverse: \Delivery.pickupPlace)
    private(set) var deliveries: [Delivery] = []

    init(id: UUID = UUID(), name: PickupPlaceName, createdAt: Date) {
        self.id = id
        displayName = name.display
        normalizedName = name.key
        self.createdAt = createdAt
    }
}

extension PickupPlace {
    /// Deterministic order for the catalogue: earliest named first, with
    /// identity breaking a tie.
    ///
    /// Total and repeatable for the same reason ``Delivery/acceptedBefore(_:_:)``
    /// is: two rows created in the same instant must not be free to swap places
    /// between two reads.
    static func namedBefore(_ lhs: PickupPlace, _ rhs: PickupPlace) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The most recent acceptance among the deliveries naming this place, or
    /// `nil` if none do any more.
    ///
    /// Derived rather than stored, which is what keeps a "recently used" list
    /// honest: a place whose only delivery was deleted with its shift stops being
    /// recent, instead of keeping a `lastUsedAt` describing work the store no
    /// longer holds.
    var lastUsedAt: Date? {
        deliveries.map(\.acceptedAt).max()
    }
}
