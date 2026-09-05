import Foundation

/// Launch arguments the app recognises.
///
/// The UI test target cannot link the app target, so it repeats these string
/// values rather than importing them. Keep the two in step.
nonisolated enum LaunchArgument {
    /// Runs against a throwaway in-memory store.
    ///
    /// UI tests need a known empty starting state and must not write shifts
    /// into the store a real driver's data would live in. Debug builds only.
    static let inMemoryStore = "-dashpilot-in-memory-store"

    /// Runs against a throwaway store already holding synthetic completed
    /// shifts.
    ///
    /// Some of what the history row shows cannot be produced by tapping through
    /// the app: a UI test cannot drive a simulator into recording a route, so a
    /// measured, partial route and the rates derived from it would otherwise be
    /// untestable end to end. The data is the same synthetic fixture the
    /// previews use — invented amounts and coordinates in open country, never a
    /// real driver's history. Debug builds only, and in memory, so it can never
    /// touch a real store.
    static let seededHistory = "-dashpilot-seeded-history"

    /// Runs against a throwaway store already holding a running shift with two
    /// deliveries in progress at different points in their lifecycles.
    ///
    /// A UI test cannot terminate and relaunch the app into a store it wrote
    /// earlier — the in-memory store the other journeys use disappears with the
    /// process. Seeding stacked active deliveries at launch reproduces the state
    /// a relaunch recovers into, which is the only way to assert end to end that
    /// the interface restores *every* running delivery with its own next step
    /// rather than collapsing them into one. That recovery is proved against a
    /// real reopened store in `DeliveryPersistenceTests`. Debug builds only, and
    /// in memory, so it can never touch a real store.
    static let seededActiveDelivery = "-dashpilot-seeded-active-delivery"

    /// Runs against a throwaway store already holding one completed shift whose
    /// deliveries give two pickup places different amounts of recorded history.
    ///
    /// The general seeded-history fixture is pinned by the journeys that assert
    /// exact active-time and rate figures over its three deliveries, so it
    /// cannot also be the place a median, a sample count and the
    /// insufficient-history wording are reached from. Debug builds only, and in
    /// memory, so it can never touch a real store.
    static let seededPickupHistory = "-dashpilot-seeded-pickup-history"

    static func isPresent(_ argument: String, in processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
    }
}
