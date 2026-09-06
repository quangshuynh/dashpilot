import Foundation
import SwiftData

/// Version 1 of the persisted schema: shifts only.
///
/// The models are declared *inside* this enum rather than reused from file
/// scope, because the file-scope types have moved on. `DashPilotSchemaV1.Shift`
/// is a frozen copy of the shape a v1 store on a driver's device actually
/// contains, so the migration plan can describe where the store is coming from
/// as truthfully as where it is going. It is never used at runtime outside
/// migration.
enum DashPilotSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self] }

    /// The v1 shift: start and end timestamps, and nothing else.
    ///
    /// Deliberately behaviour-free. Its only job is to describe storage; the
    /// transitions and calculations live on the current ``DashPilot/Shift``.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }
}

/// Version 2 of the persisted schema: shifts gain a route.
///
/// The change from v1 is purely additive — a new `RouteSample` entity and a new
/// to-many relationship from `Shift` to it. No existing property is renamed,
/// retyped or removed, and the new relationship starts empty, so every v1 shift
/// carries over untouched.
///
/// Both models are frozen copies, for the same reason ``DashPilotSchemaV1``
/// freezes its shift: the file-scope `RouteSample` has since gained a capture
/// session, and reusing it here would make v2 claim a shape no store on a
/// device ever had.
enum DashPilotSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self] }

    /// The v2 shift: the v1 shift plus its route.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
        private(set) var routeSamples: [RouteSample] = []

        init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    /// The v2 route sample: a position and its accuracy, with no record of
    /// whether capture was interrupted around it.
    @Model
    nonisolated final class RouteSample {
        private(set) var timestamp: Date
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var horizontalAccuracy: Double
        private(set) var shift: Shift?

        init(shift: Shift, timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.shift = shift
        }
    }
}

/// Version 3 of the persisted schema: route samples record capture continuity.
///
/// `RouteSample` gains one optional attribute, `captureSessionID`. It is what
/// lets the mileage calculation tell an uninterrupted stretch of route from two
/// stretches with a gap between them, which timestamps alone cannot do.
///
/// Adding an optional attribute is additive, so v2 stores open under v3 with
/// every shift and every stored position intact. The migrated samples keep a
/// `nil` capture session: nothing in a v2 store records whether capture was
/// interrupted, and inventing an identifier would manufacture exactly the
/// continuity the attribute exists to prove.
///
/// Both models are frozen copies, for the same reason the earlier versions
/// freeze theirs: the file-scope `Shift` has since gained recorded earnings,
/// and reusing it here would make v3 claim a shape no store on a device ever
/// had.
enum DashPilotSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self] }

    /// The v3 shift: timestamps and a route, with nothing recorded about what
    /// the shift paid.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
        private(set) var routeSamples: [RouteSample] = []

        init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    /// The v3 route sample: a position, its accuracy and the capture session it
    /// was recorded in.
    @Model
    nonisolated final class RouteSample {
        private(set) var timestamp: Date
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var horizontalAccuracy: Double
        private(set) var captureSessionID: UUID?
        private(set) var shift: Shift?

        init(
            shift: Shift,
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            captureSessionID: UUID?
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.captureSessionID = captureSessionID
            self.shift = shift
        }
    }
}

/// Version 4 of the persisted schema: a shift can record what it paid.
///
/// `Shift` gains one optional attribute, `grossEarningsAmount`, a `Decimal`
/// holding gross earnings the driver typed. It is optional because earnings are
/// optional: a shift with no amount recorded is a complete, valid shift.
///
/// Nothing is backfilled, and that distinction is the point. A v3 store records
/// no earnings at all, which is not the same statement as "these shifts paid
/// nothing". Writing `0` into every existing shift would turn the absence of a
/// figure into a claim about every shift a driver has ever recorded. They keep
/// `nil`, and the interface offers to add an amount rather than showing one.
///
/// Both models are frozen copies, for the same reason the earlier versions
/// freeze theirs: the file-scope `Shift` has since gained a `deliveries`
/// relationship, and reusing it here would make v4 claim a shape no store on a
/// device ever had.
enum DashPilotSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self] }

    /// The v4 shift: timestamps, a route and an optional recorded amount, with
    /// nothing recorded about the deliveries performed during it.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
        private(set) var routeSamples: [RouteSample] = []

        private(set) var grossEarningsAmount: Decimal?

        init(
            id: UUID = UUID(),
            startedAt: Date,
            endedAt: Date? = nil,
            grossEarningsAmount: Decimal? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.grossEarningsAmount = grossEarningsAmount
        }
    }

    /// The v4 route sample, unchanged from v3.
    @Model
    nonisolated final class RouteSample {
        private(set) var timestamp: Date
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var horizontalAccuracy: Double
        private(set) var captureSessionID: UUID?
        private(set) var shift: Shift?

        init(
            shift: Shift,
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            captureSessionID: UUID?
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.captureSessionID = captureSessionID
            self.shift = shift
        }
    }
}

/// Version 5 of the persisted schema: a shift can record its deliveries.
///
/// The change is additive in the same shape v1 to v2 was: a new `Delivery`
/// entity and a new to-many relationship from `Shift` to it. No existing
/// property is renamed, retyped or removed, so every v4 shift, route sample,
/// capture session identifier and recorded amount carries over untouched, and
/// the new relationship starts empty.
///
/// Empty is the truthful value. A store written before delivery recording
/// existed holds no evidence that any particular delivery happened, and
/// synthesising deliveries — one per hour, one per route segment, anything at
/// all — would put work into a driver's history that they never recorded and
/// that nothing could afterwards distinguish from work they did. Existing
/// shifts migrate with zero deliveries.
///
/// All three models are frozen copies, for the same reason the earlier versions
/// freeze theirs: the file-scope `Delivery` has since gained a pickup place, and
/// reusing it here would make v5 claim a shape no store on a device ever had.
enum DashPilotSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self, Delivery.self] }

    /// The v5 shift: timestamps, a route, an optional amount and its deliveries.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
        private(set) var routeSamples: [RouteSample] = []

        @Relationship(deleteRule: .cascade, inverse: \Delivery.shift)
        private(set) var deliveries: [Delivery] = []

        private(set) var grossEarningsAmount: Decimal?

        init(
            id: UUID = UUID(),
            startedAt: Date,
            endedAt: Date? = nil,
            grossEarningsAmount: Decimal? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.grossEarningsAmount = grossEarningsAmount
        }
    }

    /// The v5 route sample, unchanged from v3.
    @Model
    nonisolated final class RouteSample {
        private(set) var timestamp: Date
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var horizontalAccuracy: Double
        private(set) var captureSessionID: UUID?
        private(set) var shift: Shift?

        init(
            shift: Shift,
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            captureSessionID: UUID?
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.captureSessionID = captureSessionID
            self.shift = shift
        }
    }

    /// The v5 delivery: five lifecycle timestamps and its shift, with nothing
    /// recorded about where the order was collected from.
    @Model
    nonisolated final class Delivery {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var acceptedAt: Date
        private(set) var arrivedAtPickupAt: Date?
        private(set) var pickedUpAt: Date?
        private(set) var deliveredAt: Date?
        private(set) var cancelledAt: Date?
        private(set) var shift: Shift?

        init(
            id: UUID = UUID(),
            shift: Shift,
            acceptedAt: Date,
            arrivedAtPickupAt: Date? = nil,
            pickedUpAt: Date? = nil,
            deliveredAt: Date? = nil,
            cancelledAt: Date? = nil
        ) {
            self.id = id
            self.acceptedAt = acceptedAt
            self.arrivedAtPickupAt = arrivedAtPickupAt
            self.pickedUpAt = pickedUpAt
            self.deliveredAt = deliveredAt
            self.cancelledAt = cancelledAt
            self.shift = shift
        }
    }
}

/// Version 6 of the persisted schema: a delivery can name where it was picked up.
///
/// Two additions, both optional in the sense that matters: a new `PickupPlace`
/// entity, and a new optional `Delivery.pickupPlace` reference to it with an
/// empty `PickupPlace.deliveries` inverse. No existing property is renamed,
/// retyped or removed, so every v5 shift, route sample, capture session
/// identifier, recorded amount and delivery timestamp carries over untouched.
///
/// **Nothing is backfilled, and nothing could honestly be.** A store written
/// before pickup identity existed holds no record of which business any past
/// delivery came from — DashPilot observes no delivery platform, performs no
/// lookup, and keeps no address or coordinate that names a merchant. Guessing a
/// place from a route position, a timestamp or a repeated pattern would put a
/// business's name against work the driver never attributed to it, and nothing
/// afterwards could tell an inferred place from one they typed. Existing
/// deliveries migrate with no pickup place, which is the truthful value.
///
/// All four models are frozen copies, for the same reason the earlier versions
/// freeze theirs: the file-scope `Delivery` has since gained a recorded amount
/// of its own, and reusing it here would make v6 claim a shape no store on a
/// device ever had.
enum DashPilotSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Shift.self, RouteSample.self, Delivery.self, PickupPlace.self]
    }

    /// The v6 shift, unchanged from v5.
    @Model
    nonisolated final class Shift {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var startedAt: Date
        private(set) var endedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
        private(set) var routeSamples: [RouteSample] = []

        @Relationship(deleteRule: .cascade, inverse: \Delivery.shift)
        private(set) var deliveries: [Delivery] = []

        private(set) var grossEarningsAmount: Decimal?

        init(
            id: UUID = UUID(),
            startedAt: Date,
            endedAt: Date? = nil,
            grossEarningsAmount: Decimal? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.grossEarningsAmount = grossEarningsAmount
        }
    }

    /// The v6 route sample, unchanged from v3.
    @Model
    nonisolated final class RouteSample {
        private(set) var timestamp: Date
        private(set) var latitude: Double
        private(set) var longitude: Double
        private(set) var horizontalAccuracy: Double
        private(set) var captureSessionID: UUID?
        private(set) var shift: Shift?

        init(
            shift: Shift,
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            captureSessionID: UUID?
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.captureSessionID = captureSessionID
            self.shift = shift
        }
    }

    /// The v6 delivery: the v5 lifecycle plus an optional pickup place, and
    /// nothing recorded about what the delivery itself paid.
    @Model
    nonisolated final class Delivery {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var acceptedAt: Date
        private(set) var arrivedAtPickupAt: Date?
        private(set) var pickedUpAt: Date?
        private(set) var deliveredAt: Date?
        private(set) var cancelledAt: Date?
        private(set) var shift: Shift?
        private(set) var pickupPlace: PickupPlace?

        init(
            id: UUID = UUID(),
            shift: Shift,
            acceptedAt: Date,
            arrivedAtPickupAt: Date? = nil,
            pickedUpAt: Date? = nil,
            deliveredAt: Date? = nil,
            cancelledAt: Date? = nil,
            pickupPlace: PickupPlace? = nil
        ) {
            self.id = id
            self.acceptedAt = acceptedAt
            self.arrivedAtPickupAt = arrivedAtPickupAt
            self.pickedUpAt = pickedUpAt
            self.deliveredAt = deliveredAt
            self.cancelledAt = cancelledAt
            self.shift = shift
            self.pickupPlace = pickupPlace
        }
    }

    /// The v6 pickup place: the spelling the driver chose and the key it is
    /// matched by.
    ///
    /// Takes both forms of the name as plain strings rather than a
    /// `PickupPlaceName`. The frozen models describe storage and hold no
    /// behaviour, and normalisation is a rule that is allowed to improve — a
    /// frozen copy that called into it would describe the store as today's rule
    /// would write it rather than as an older build actually did.
    @Model
    nonisolated final class PickupPlace {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var displayName: String
        private(set) var normalizedName: String
        private(set) var createdAt: Date

        @Relationship(deleteRule: .nullify, inverse: \Delivery.pickupPlace)
        private(set) var deliveries: [Delivery] = []

        init(id: UUID = UUID(), displayName: String, normalizedName: String, createdAt: Date) {
            self.id = id
            self.displayName = displayName
            self.normalizedName = normalizedName
            self.createdAt = createdAt
        }
    }
}

/// Version 7 of the persisted schema: a delivery can record what it paid.
///
/// `Delivery` gains one optional attribute, `grossEarningsAmount`, a `Decimal`
/// holding gross earnings the driver typed for that delivery. The shape of the
/// change is exactly v3 → v4, one entity along: an optional amount on a record
/// that previously had none.
///
/// **Nothing is backfilled, and one particular thing is deliberately not
/// derived.** A v6 store may hold a shift with a recorded amount and several
/// deliveries; dividing that amount among them — evenly, by duration, by
/// distance or by anything else — would write figures into a driver's history
/// that they never typed and that nothing afterwards could tell from figures
/// they did. The shift amount and a delivery amount are two independent facts
/// the driver enters separately, and DashPilot never manufactures one from the
/// other. Every migrated delivery keeps `nil`, which the app reads as "not
/// recorded" and never as `0.00`.
///
/// This version reuses the file-scope models rather than freezing copies,
/// because it *is* the current shape. It gets frozen copies of its own the first
/// time v8 moves them on, exactly as v6 did here.
enum DashPilotSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Shift.self, RouteSample.self, Delivery.self, PickupPlace.self]
    }
}

/// Ordered history of schema versions and the migrations between them.
///
/// Every container the app, its tests and its previews build is opened through
/// this plan, so a version step is exercised by the ordinary test suite rather
/// than only on a device that happens to hold an old store.
enum DashPilotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            DashPilotSchemaV1.self,
            DashPilotSchemaV2.self,
            DashPilotSchemaV3.self,
            DashPilotSchemaV4.self,
            DashPilotSchemaV5.self,
            DashPilotSchemaV6.self,
            DashPilotSchemaV7.self
        ]
    }

    static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7] }

    /// V1 → V2 is lightweight.
    ///
    /// SwiftData can add an entity and an empty relationship without being told
    /// how, and there is no value to derive, backfill or reinterpret: a shift
    /// recorded before route capture existed genuinely has no route. A custom
    /// stage would be code with nothing to do, and a `willMigrate`/`didMigrate`
    /// pair that touches every shift for no reason is a way to lose data, not a
    /// way to protect it. It becomes a custom stage the first time a version
    /// step actually has to transform something.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV1.self,
        toVersion: DashPilotSchemaV2.self
    )

    /// V2 → V3 is lightweight.
    ///
    /// One new optional attribute on an existing entity, which SwiftData can add
    /// without being told how. There is deliberately nothing to backfill: a
    /// capture session identifier states that two samples were recorded without
    /// an interruption, and a v2 store holds no evidence of that either way.
    /// Grouping legacy samples into invented sessions would be the one thing
    /// this attribute exists to prevent — a gap silently presented as a
    /// continuous stretch of driving. They keep `nil`, and the mileage
    /// calculation treats their continuity as unproven.
    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV2.self,
        toVersion: DashPilotSchemaV3.self
    )

    /// V3 → V4 is lightweight.
    ///
    /// One new optional attribute on an existing entity, which SwiftData can add
    /// without being told how, and nothing to derive: a shift recorded before
    /// earnings entry existed has no amount because none was ever entered. It
    /// keeps `nil`, which the app reads as "not recorded" and never as `0.00`.
    /// Fabricating a zero would be the one mistake this stage can make — it
    /// would put a figure a driver never typed into their history, and there
    /// would be no way afterwards to tell it from one they did.
    static let v3ToV4 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV3.self,
        toVersion: DashPilotSchemaV4.self
    )

    /// V4 → V5 is lightweight.
    ///
    /// A new entity and a new empty relationship, which SwiftData can add
    /// without being told how — the same shape as v1 → v2, and with the same
    /// nothing to derive. A shift recorded before delivery recording existed
    /// genuinely has no deliveries: DashPilot observes no delivery platform, so
    /// there is no source anywhere in the store from which a past delivery
    /// could be reconstructed. Inventing one per hour, per route segment or per
    /// anything else would write work into a driver's history that they never
    /// recorded, and nothing afterwards could tell it from work they did.
    static let v4ToV5 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV4.self,
        toVersion: DashPilotSchemaV5.self
    )

    /// V5 → V6 is lightweight.
    ///
    /// A new entity and a new optional reference to it, which SwiftData can add
    /// without being told how. Every existing delivery migrates with no pickup
    /// place, and the catalogue of places starts empty.
    ///
    /// That emptiness is the substantive decision. A v5 store records nothing
    /// about which business any delivery came from, and DashPilot has no source
    /// from which to recover one: it reads no delivery platform, resolves no
    /// address, and holds no merchant data of any kind. Attributing a past
    /// delivery to a place by its route, its timing or its resemblance to
    /// another would write a business's name into a driver's history on the
    /// app's authority rather than theirs, and no later screen could
    /// distinguish that from a place they named themselves.
    static let v5ToV6 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV5.self,
        toVersion: DashPilotSchemaV6.self
    )

    /// V6 → V7 is lightweight.
    ///
    /// One new optional attribute on an existing entity, which SwiftData can add
    /// without being told how. Every existing delivery migrates with no amount
    /// recorded against it.
    ///
    /// The temptation this stage refuses is the one thing it could plausibly do:
    /// a v6 store often holds a completed shift with a recorded amount *and* the
    /// deliveries performed during it, so a total and a set of rows to spread it
    /// over are both sitting right there. Spreading it — evenly, by duration, by
    /// pickup wait, by anything — would put a figure against each delivery that
    /// the driver never typed, and no later screen, export or calculation could
    /// tell it from one they did. The two amounts are independent facts entered
    /// separately, and neither is evidence for the other: deliveries go
    /// unrecorded, stacked orders are paid together, and adjustments post at
    /// shift level. Every migrated delivery keeps `nil`, which the app reads as
    /// "not recorded" and never as `0.00`.
    static let v6ToV7 = MigrationStage.lightweight(
        fromVersion: DashPilotSchemaV6.self,
        toVersion: DashPilotSchemaV7.self
    )
}
