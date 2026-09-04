import Foundation
import OSLog
import SwiftData

/// Builds the app's SwiftData containers.
///
/// Container creation can fail (an unreadable store, a migration that cannot
/// be applied), so it throws rather than trapping. Callers are expected to show
/// that failure to the user; deleting the store to recover is not an acceptable
/// default because the store holds work the driver cannot re-enter.
nonisolated enum ModelContainerFactory {
    static var currentSchema: Schema {
        Schema(versionedSchema: DashPilotSchemaV1.self)
    }

    /// The on-disk container backing the running app.
    static func makeAppContainer() throws -> ModelContainer {
        try makeContainer(inMemory: false)
    }

    /// A throwaway container for tests and previews.
    static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(inMemory: true)
    }

    /// A container backed by a store at an explicit location.
    ///
    /// Tests use this to close a store and reopen it, which is the only way to
    /// demonstrate that state survives app termination: an in-memory store
    /// disappears with the container that owns it.
    static func makeContainer(at url: URL) throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(schema: currentSchema, url: url))
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        try makeContainer(
            configuration: ModelConfiguration(schema: currentSchema, isStoredInMemoryOnly: inMemory),
            inMemory: inMemory
        )
    }

    private static func makeContainer(configuration: ModelConfiguration, inMemory: Bool = false) throws -> ModelContainer {
        do {
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: DashPilotMigrationPlan.self,
                configurations: configuration
            )
            AppLog.persistence.info(
                "Opened store (inMemory: \(inMemory, privacy: .public), schema: \(DashPilotSchemaV1.versionIdentifier.description, privacy: .public))"
            )
            return container
        } catch {
            AppLog.persistence.error("Failed to open store (inMemory: \(inMemory, privacy: .public)): \(error)")
            throw error
        }
    }
}
