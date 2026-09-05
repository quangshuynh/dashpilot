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
/// This version reuses the file-scope models rather than freezing copies,
/// because it *is* the current shape. It gets frozen copies of its own the
/// first time v6 moves them on, exactly as v4 did here.
enum DashPilotSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self, Delivery.self] }
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
            DashPilotSchemaV5.self
        ]
    }

    static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5] }

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
}
