import Foundation
import SwiftData

/// The one SwiftData container this process opens.
///
/// The app's scene is no longer the only thing that needs a store: an App
/// Intent can run with no interface on screen, and iOS may launch the process
/// solely to perform one. Both have to reach the *same* container object rather
/// than two containers over the same file. Two would show as a screen that
/// still offers "End Shift" after a shift was ended by voice, because the
/// `@Query` behind it observes its own container and never heard about the
/// other's write.
///
/// Built once, lazily, on first use. That is what makes a background launch
/// ordinary: when no scene has been created, nothing has opened the store, and
/// the intent's first access opens it.
///
/// Failure is carried rather than trapped, exactly as ``ModelContainerFactory``
/// leaves it. The app turns it into ``PersistenceUnavailableView``; an intent
/// turns it into a sentence saying that nothing was recorded. Deleting the
/// store to recover is not an option either of them has.
@MainActor
enum AppModelContainer {
    /// The process's container, or the failure that prevented it opening.
    static let shared: Result<ModelContainer, any Error> = Result { try makeContainer() }

    private static func makeContainer() throws -> ModelContainer {
        #if DEBUG
        // The UI test fixtures, which must never touch a real driver's store.
        // Debug builds only, and every one of them is in memory.
        if LaunchArgument.isPresent(LaunchArgument.seededActiveDelivery) {
            return try PreviewSupport.seededActiveDeliveryContainer()
        }
        if LaunchArgument.isPresent(LaunchArgument.seededPeriodSummary) {
            return try PreviewSupport.seededPeriodSummaryContainer()
        }
        if LaunchArgument.isPresent(LaunchArgument.seededPickupHistory) {
            return try PreviewSupport.seededPickupHistoryContainer()
        }
        if LaunchArgument.isPresent(LaunchArgument.seededHistory) {
            return try PreviewSupport.seededHistoryContainer(includingActiveShift: false)
        }
        if LaunchArgument.isPresent(LaunchArgument.inMemoryStore) {
            return try ModelContainerFactory.makeInMemoryContainer()
        }
        #endif
        return try ModelContainerFactory.makeAppContainer()
    }
}
