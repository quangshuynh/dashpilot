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
/// The change is purely additive — a new `RouteSample` entity and a new
/// to-many relationship from `Shift` to it. No existing property is renamed,
/// retyped or removed, and the new relationship starts empty, so every v1 shift
/// carries over untouched.
enum DashPilotSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self, RouteSample.self] }
}

/// Ordered history of schema versions and the migrations between them.
///
/// Every container the app, its tests and its previews build is opened through
/// this plan, so a version step is exercised by the ordinary test suite rather
/// than only on a device that happens to hold an old store.
enum DashPilotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DashPilotSchemaV1.self, DashPilotSchemaV2.self] }

    static var stages: [MigrationStage] { [v1ToV2] }

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
}
