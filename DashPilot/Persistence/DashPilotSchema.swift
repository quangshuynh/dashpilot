import Foundation
import SwiftData

/// Version 1 of the persisted schema.
///
/// The models are declared at file scope rather than nested inside this enum
/// while only one version exists. When a version 2 is introduced, V1's shapes
/// get copied into a versioned namespace and a ``MigrationStage`` is added to
/// ``DashPilotMigrationPlan`` — the plan is wired up from the start so that
/// step is a normal change rather than a store reset.
enum DashPilotSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [Shift.self] }
}

/// Ordered history of schema versions and the migrations between them.
enum DashPilotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DashPilotSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
