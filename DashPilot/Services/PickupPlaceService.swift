import Foundation
import OSLog
import SwiftData

/// The identifying facts of a pickup place, carried where the place itself
/// cannot go.
///
/// ``PickupPlaceError`` is thrown, and a thrown value crosses isolation
/// boundaries, so it may not hold a `PickupPlace` — a SwiftData model is not
/// `Sendable`, and a persistent object outliving the operation that produced it
/// is exactly the stale reference this service refuses elsewhere. A rename
/// collision needs to say *which* place it collided with, and this is the whole
/// of what saying that requires: the name to show the driver, and the identity
/// to match the place back up with if a screen ever needs to.
nonisolated struct PickupPlaceIdentity: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let displayName: String

    init(_ place: PickupPlace) {
        id = place.id
        displayName = place.displayName
    }

    init(id: UUID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Failures raised when a pickup place cannot be recorded against a delivery.
nonisolated enum PickupPlaceError: Error {
    /// The typed name broke one of ``PickupPlaceName``'s two rules.
    case invalidName(PickupPlaceNameError)
    /// A rename would give this place a name another place is already found by.
    ///
    /// Carries the place that holds the key, because the answer offered to the
    /// driver is to **merge** into it — and a refusal that cannot name what it
    /// collided with is a dead end.
    case placeAlreadyExists(existingPlace: PickupPlaceIdentity)
    /// A merge named one place as both its source and its destination.
    case cannotMergeIntoItself
    /// A place in the operation is not, or is no longer, a row the store holds.
    case placeNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension PickupPlaceError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidName(lhsError), .invalidName(rhsError)): lhsError == rhsError
        case let (.placeAlreadyExists(lhsPlace), .placeAlreadyExists(rhsPlace)): lhsPlace == rhsPlace
        case (.cannotMergeIntoItself, .cannotMergeIntoItself): true
        case (.placeNoLongerExists, .placeNoLongerExists): true
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
        case let .placeAlreadyExists(existingPlace):
            """
            You already have a pickup place called \(existingPlace.displayName). To put both places' \
            deliveries together under one name, merge this place into it instead.
            """
        case .cannotMergeIntoItself:
            "A pickup place cannot be merged into itself. Choose a different place to merge into."
        case .placeNoLongerExists:
            "That pickup place is no longer in DashPilot, so nothing was changed."
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
/// **The first accepted spelling wins, by matching.** A later entry that matches
/// an existing place reuses it without rewriting what it is called. Renaming a
/// place a driver has been reading all week because tonight they typed it in
/// lower case is a surprise, and choosing which of two spellings is the "better"
/// one is not a judgement this app can make.
///
/// ## Correcting a place the driver got wrong
///
/// The rule above is about what *typing* may do. It is not a claim that a place
/// is unchangeable, and two deliberate corrections live here:
///
/// - ``rename(_:to:)`` gives one place a new spelling and a new key, keeping
///   every delivery attached to it.
/// - ``merge(_:into:)`` moves every delivery off one place onto another and
///   removes the one left empty.
///
/// Both are explicit acts by the driver, on one named place, with the direction
/// stated. **Nothing merges automatically.** There is no similarity check, no
/// "did you mean", no background scan for near-duplicates, and no rule beyond the
/// exact normalised-key reuse above — a duplicate the driver can see is a
/// nuisance, and a merge they did not ask for is a distinction the app cannot
/// give back.
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

    /// How a change is handed to the store.
    ///
    /// `ModelContext.save()` everywhere in the app, and injectable for exactly
    /// one reason: ``merge(_:into:)`` claims to be atomic, and a claim about what
    /// happens when a save is refused is untestable while the save can only
    /// succeed. A test substitutes a commit that throws; the rollback it triggers
    /// is the real ``ModelContext/rollback()``, so what the test asserts is the
    /// store's own behaviour rather than a stand-in for it.
    ///
    /// Deliberately a closure and not a protocol: one function, one call site per
    /// operation, no second conformance to write and nothing for the app to
    /// configure.
    private let commit: (ModelContext) throws -> Void

    init(context: ModelContext, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.commit = commit
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

    // MARK: Correcting identity

    /// Gives `place` a new name, keeping every delivery attached to it.
    ///
    /// The name goes through ``PickupPlaceName`` — the same type, the same two
    /// rules and the same normalisation as creating a place, because a second
    /// policy here would be a second way for two spellings to disagree about
    /// whether they mean the same place.
    ///
    /// ## What a rename is, and is not
    ///
    /// It changes identity **text**: the spelling on screen and the key the
    /// catalogue is searched by. It moves no delivery, deletes nothing, and
    /// touches no lifecycle timestamp — so the place's delivery count, its
    /// recorded waits, their median and its position in the recent list are all
    /// exactly what they were. Afterwards the new spelling is authoritative:
    /// typing it again finds this place rather than creating another.
    ///
    /// ## Collisions are refused, never merged
    ///
    /// If the new name normalises to a key another place already holds,
    /// ``PickupPlaceError/placeAlreadyExists(existingPlace:)`` is thrown and
    /// **nothing is written**. Quietly folding this place into that one would be
    /// a merge, and a merge destroys a place — a driver correcting a typo has not
    /// asked for that. The refusal carries the place it collided with so the
    /// interface can offer ``merge(_:into:)`` as the deliberate next step.
    ///
    /// A rename to a name this place already matches — a capitalisation or
    /// spacing fix — is not a collision and is applied as the display change it
    /// is. A rename to exactly what is already stored writes nothing.
    ///
    /// - Throws: ``PickupPlaceError``.
    @discardableResult
    func rename(_ place: PickupPlace, to rawName: String) throws -> PickupPlace {
        guard isRecorded(place) else {
            AppLog.pickupPlace.notice("Refused a pickup place rename: the place is not in the store")
            throw PickupPlaceError.placeNoLongerExists
        }

        let name: PickupPlaceName
        do {
            name = try PickupPlaceName(rawName)
        } catch {
            // The rule that was broken, never the text that broke it.
            AppLog.pickupPlace.notice(
                "Refused a pickup place rename: \(String(describing: error), privacy: .public)"
            )
            throw PickupPlaceError.invalidName(error)
        }

        if let existing = try self.place(matching: name.key), existing.id != place.id {
            // Which rule refused it, never which name or which key.
            AppLog.pickupPlace.notice("Refused a pickup place rename: another place already holds that name")
            throw PickupPlaceError.placeAlreadyExists(existingPlace: PickupPlaceIdentity(existing))
        }

        guard place.displayName != name.display || place.normalizedName != name.key else { return place }

        place.rename(to: name)
        try save(describing: "a pickup place rename")

        AppLog.pickupPlace.info("Pickup place renamed")
        return place
    }

    /// The places `place` could be merged into, in the order they are offered.
    ///
    /// **Display name alphabetical**, compared the way a person reads a list —
    /// `localizedStandardCompare`, so case and accents do not scatter it — with
    /// the catalogue's own order breaking a tie. Deterministic, and the same on
    /// every read.
    ///
    /// Alphabetical rather than recent-first on purpose: a driver merging is
    /// looking for one particular name they already have in mind, and a list that
    /// reorders itself as work is recorded makes that name harder to find, not
    /// easier. There is no relevance ranking, no similarity score and no
    /// suggested destination — the app has no opinion about which of these places
    /// is the "right" one.
    ///
    /// - Throws: ``PickupPlaceError/storeUnavailable(underlying:)``.
    func mergeDestinations(for place: PickupPlace) throws -> [PickupPlace] {
        try allPlaces()
            .filter { $0.id != place.id }
            .sorted(by: PickupPlace.displayedBefore)
    }

    /// Moves every delivery recorded under `source` onto `destination`, then
    /// removes `source`.
    ///
    /// ## The destination wins, entirely
    ///
    /// `destination` keeps its `id`, its spelling, its key and the date it was
    /// first named. Nothing is combined, no alias is kept and no record of the
    /// merge is written: the source contributes its delivery relationships and
    /// nothing else. What survives is one of the two places the driver already
    /// had, chosen by them.
    ///
    /// ## What the deliveries keep
    ///
    /// All of it. A reassigned delivery keeps its acceptance, arrival, pickup,
    /// delivery and cancellation timestamps unchanged, so its recorded wait is
    /// the same interval it always was. Nothing is deleted: the deliveries move,
    /// and afterwards the destination's history is the two histories read
    /// together — recomputed from the relationship, because no figure was ever
    /// stored on a place to go stale. Recency follows for the same reason.
    ///
    /// ## One operation
    ///
    /// The reassignment and the deletion are committed **together**. Saving
    /// between them would make a refused second save the worst outcome available:
    /// deliveries already moved onto the destination and a source still standing
    /// beside it, with the driver's history split differently than before but
    /// still split. Instead a failure rolls the context back, and the store is
    /// exactly as it was — both places, every delivery where it started.
    ///
    /// - Throws: ``PickupPlaceError/cannotMergeIntoItself`` if the two are one
    ///   place, ``PickupPlaceError/placeNoLongerExists`` if either is not a row
    ///   the store holds, or
    ///   ``PickupPlaceError/storeUnavailable(underlying:)``.
    func merge(_ source: PickupPlace, into destination: PickupPlace) throws {
        guard source.id != destination.id else {
            AppLog.pickupPlace.notice("Refused a pickup place merge: a place cannot merge into itself")
            throw PickupPlaceError.cannotMergeIntoItself
        }
        guard isRecorded(source), isRecorded(destination) else {
            // Nothing has been mutated yet, which is the point of checking here:
            // a half-applied merge is worse than a refused one.
            AppLog.pickupPlace.notice("Refused a pickup place merge: a place is not in the store")
            throw PickupPlaceError.placeNoLongerExists
        }

        // Snapshotted before the loop: reassigning a delivery empties the
        // relationship being iterated, and a source with no deliveries left is a
        // perfectly ordinary merge rather than a special case.
        let reassigned = source.deliveries
        for delivery in reassigned {
            delivery.setPickupPlace(destination)
        }
        context.delete(source)

        try save(describing: "a pickup place merge")

        // That two places became one, and nothing about which two. Not a name,
        // not a key, and not how many deliveries moved — a count of a driver's
        // pickups at one place is the history this category exists to keep out of
        // the log.
        AppLog.pickupPlace.info("Pickup places merged")
    }

    /// Whether this place is still a row the store holds.
    ///
    /// A view can hold a place across a sheet dismissal, another screen's
    /// deletion or its own merge, so an object arriving here is not proof of a
    /// row. `modelContext` is `nil` for one that was never inserted, and
    /// `isDeleted` covers one already removed — both are refused before anything
    /// is mutated.
    private func isRecorded(_ place: PickupPlace) -> Bool {
        place.modelContext != nil && !place.isDeleted
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
            try commit(context)
        } catch {
            context.rollback()
            AppLog.pickupPlace.error("Failed to persist \(operation, privacy: .public): \(error)")
            throw PickupPlaceError.storeUnavailable(underlying: error)
        }
    }
}
