import Foundation
import OSLog
import SwiftData

/// Failures raised when a pickup place cannot be recorded against a delivery.
nonisolated enum PickupPlaceError: Error {
    /// The typed name broke one of ``PickupPlaceName``'s two rules.
    case invalidName(PickupPlaceNameError)
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension PickupPlaceError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidName(lhsError), .invalidName(rhsError)): lhsError == rhsError
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension PickupPlaceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidName(error):
            error.errorDescription
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the pickup place was not changed."
        }
    }
}

/// Naming where a delivery was picked up: resolving what the driver typed to a
/// place, reusing the one they already have, and attaching it to a delivery.
///
/// ## The one rule it exists to keep
///
/// **A name that normalises to an existing place reuses that place.** Every
/// write goes through ``resolvePlace(named:at:)``, which looks the normalised
/// key up before creating anything, so `McDonald's` typed on Monday and
/// `mcdonalds` typed on Friday are one row rather than two — which is what a
/// later question like "how long do I usually wait here" needs in order to have
/// a single answer.
///
/// Uniqueness is enforced here rather than by a `.unique` attribute on the
/// model. A unique constraint in SwiftData resolves a collision by *upserting* —
/// overwriting the existing row — where the whole point of this rule is to leave
/// the existing row alone, and it would freeze a normalisation policy that is
/// allowed to improve into the store's shape. A fetch-and-reuse is safe here for
/// a concrete reason rather than by hope: this type is `@MainActor` isolated
/// like every other service, its operations run to completion without
/// suspending, and DashPilot writes to one local store from one actor. There is
/// no second writer to race with.
///
/// ## Display spelling
///
/// **The first accepted spelling wins.** A later entry that matches an existing
/// place reuses it without rewriting what it is called. Renaming a place a
/// driver has been reading all week because tonight they typed it in lower case
/// is a surprise, and choosing which of two spellings is the "better" one is not
/// a judgement this app can make.
///
/// ## What it does not do
///
/// No fuzzy matching, no edit distance, no abbreviation rules, no chain
/// detection, no ranking and no learning. No network call of any kind: there is
/// no geocoding, no place search and no directory, so the catalogue contains
/// exactly the names the driver typed. And nothing derived — no visit count, no
/// wait statistics, no score — is calculated or stored here.
@MainActor
struct PickupPlaceService {
    /// How many recent places the interface offers by default.
    ///
    /// Small deliberately. The list exists to save typing at a kerb, and a
    /// scrolling catalogue of every place ever named would cost more attention
    /// than typing the name would.
    nonisolated static let recentPlaceLimit = 5

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Resolving

    /// The place `rawName` refers to, reusing an existing one or creating it.
    ///
    /// The returned place is saved. Creating a place is not a state worth
    /// leaving pending, and the assignment that normally follows saves again.
    ///
    /// - Throws: ``PickupPlaceError/invalidName(_:)`` if the text is not a usable
    ///   name, or ``PickupPlaceError/storeUnavailable(underlying:)``.
    @discardableResult
    func resolvePlace(named rawName: String, at date: Date = .now) throws -> PickupPlace {
        let name: PickupPlaceName
        do {
            name = try PickupPlaceName(rawName)
        } catch {
            // The rule that was broken, never the text that broke it.
            AppLog.pickupPlace.notice(
                "Refused a pickup place name: \(String(describing: error), privacy: .public)"
            )
            throw PickupPlaceError.invalidName(error)
        }

        if let existing = try place(matching: name.key) {
            AppLog.pickupPlace.info("Reused an existing pickup place")
            return existing
        }

        let place = PickupPlace(name: name, createdAt: date)
        context.insert(place)
        try save(describing: "a new pickup place")

        AppLog.pickupPlace.info("Created a new pickup place")
        return place
    }

    /// The place already holding this normalised key, if the catalogue has one.
    ///
    /// A store holding two rows with the same key is data this service cannot
    /// produce. It is reported and the **earliest** one is used, so the choice is
    /// deterministic and later deliveries keep joining the row the earlier ones
    /// already point at. Nothing is merged or deleted to tidy it up: merging
    /// would rewrite deliveries the driver did not ask to change.
    private func place(matching key: String) throws -> PickupPlace? {
        let descriptor = FetchDescriptor<PickupPlace>(predicate: #Predicate { $0.normalizedName == key })

        let matches: [PickupPlace]
        do {
            matches = try context.fetch(descriptor)
        } catch {
            AppLog.pickupPlace.error("Failed to read the pickup place catalogue: \(error)")
            throw PickupPlaceError.storeUnavailable(underlying: error)
        }

        if matches.count > 1 {
            AppLog.pickupPlace.fault(
                "Store holds \(matches.count, privacy: .public) pickup places sharing one normalised name"
            )
        }
        return matches.min(by: PickupPlace.namedBefore)
    }

    // MARK: Assigning

    /// Records that `delivery` was picked up from the place `rawName` names,
    /// replacing any place already recorded on it.
    ///
    /// - Throws: ``PickupPlaceError``.
    @discardableResult
    func assignPlace(named rawName: String, to delivery: Delivery, at date: Date = .now) throws -> PickupPlace {
        let place = try resolvePlace(named: rawName, at: date)
        try assign(place, to: delivery)
        return place
    }

    /// Records that `delivery` was picked up from a place already in the
    /// catalogue — what tapping a recent place does.
    ///
    /// - Throws: ``PickupPlaceError/storeUnavailable(underlying:)``.
    func assign(_ place: PickupPlace, to delivery: Delivery) throws {
        let isChange = delivery.pickupPlace != nil && delivery.pickupPlace?.id != place.id
        delivery.setPickupPlace(place)
        try save(describing: "a pickup place assignment")

        // Which operation happened, and nothing about where. Not the name, not
        // the key, not the delivery, not the time it was picked up. Two literals
        // rather than one interpolated word, so no value can ever reach the log
        // through this line.
        if isChange {
            AppLog.pickupPlace.info("Pickup place changed")
        } else {
            AppLog.pickupPlace.info("Pickup place assigned")
        }
    }

    /// Removes the place recorded on `delivery`, leaving the delivery itself
    /// untouched.
    ///
    /// The place stays in the catalogue. It may still be named by other
    /// deliveries, and even when it is not, a driver who removes a mis-tapped
    /// place from one delivery has not said the place should stop existing — see
    /// the note on unreferenced places in
    /// ``recentPlaces(limit:)``.
    ///
    /// - Throws: ``PickupPlaceError/storeUnavailable(underlying:)``.
    func removePlace(from delivery: Delivery) throws {
        guard delivery.pickupPlace != nil else { return }
        delivery.setPickupPlace(nil)
        try save(describing: "a pickup place removal")

        AppLog.pickupPlace.info("Pickup place removed")
    }

    // MARK: Reading

    /// The places most recently used, newest first.
    ///
    /// Recency is **derived from the deliveries that reference each place**
    /// rather than stored on it: a `lastUsedAt` column would be a second answer
    /// to a question the deliveries already answer, and it would keep describing
    /// work that had since been deleted with its shift.
    ///
    /// A place no delivery references any more is not recent and does not
    /// appear. It is deliberately **not deleted** either: it costs one row, it is
    /// still the driver's own vocabulary, and collecting it would mean deleting
    /// data as a side effect of deleting a shift — a blast radius this project
    /// keeps deliberately small. Typing the name again simply finds it.
    ///
    /// The order is total and repeatable: latest acceptance descending, then the
    /// catalogue's own order, so equal claims cannot swap between two reads.
    /// There is no frequency ranking and no notion of a favourite.
    ///
    /// - Throws: ``PickupPlaceError/storeUnavailable(underlying:)``.
    func recentPlaces(limit: Int = recentPlaceLimit) throws -> [PickupPlace] {
        guard limit > 0 else { return [] }

        let places: [PickupPlace]
        do {
            places = try context.fetch(FetchDescriptor<PickupPlace>())
        } catch {
            AppLog.pickupPlace.error("Failed to read the pickup place catalogue: \(error)")
            throw PickupPlaceError.storeUnavailable(underlying: error)
        }

        let used = places.compactMap { place in place.lastUsedAt.map { (place: place, usedAt: $0) } }
        return used
            .sorted { lhs, rhs in
                if lhs.usedAt != rhs.usedAt { return lhs.usedAt > rhs.usedAt }
                return PickupPlace.namedBefore(rhs.place, lhs.place)
            }
            .prefix(limit)
            .map(\.place)
    }

    /// Every place in the local catalogue, in the order it was built.
    ///
    /// A catalogue read for tests and for future screens that need the whole
    /// list. Nothing in the running interface uses it: the driver is offered
    /// recent places, not an index.
    ///
    /// - Throws: ``PickupPlaceError/storeUnavailable(underlying:)``.
    func allPlaces() throws -> [PickupPlace] {
        do {
            return try context.fetch(FetchDescriptor<PickupPlace>()).sorted(by: PickupPlace.namedBefore)
        } catch {
            AppLog.pickupPlace.error("Failed to read the pickup place catalogue: \(error)")
            throw PickupPlaceError.storeUnavailable(underlying: error)
        }
    }

    /// Saves, and rolls back if the store refuses, with the same rule the other
    /// services apply: nothing stays in memory that the store did not accept.
    ///
    /// `operation` is a fixed phrase naming what was attempted, chosen in code
    /// and typed as a `StaticString` so a place's name cannot become the value.
    private func save(describing operation: StaticString) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.pickupPlace.error("Failed to persist \(operation, privacy: .public): \(error)")
            throw PickupPlaceError.storeUnavailable(underlying: error)
        }
    }
}
