import SwiftData
import SwiftUI

@main
struct DashPilotApp: App {
    /// Built once at launch. Store failure is a state the user is shown, not a crash.
    private let container: Result<ModelContainer, Error>

    /// Owned by the app rather than the root view so that one location manager
    /// exists for the process. It reads permission only; nothing here starts
    /// location updates or prompts the driver at launch.
    @State private var locationAuthorization: LocationAuthorizationService

    /// Route capture, over the same main context the views and ``ShiftService``
    /// use, so the store stays the single authority on whether a shift is
    /// running. `nil` when the store could not be opened: there is nowhere to
    /// put samples, and that failure is already the whole screen.
    @State private var routeCapture: LocationTrackingService?

    init() {
        let container = Result<ModelContainer, Error> {
            #if DEBUG
            if LaunchArgument.isPresent(LaunchArgument.seededActiveDelivery) {
                return try PreviewSupport.seededActiveDeliveryContainer()
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
        let locationAuthorization = LocationAuthorizationService()

        self.container = container
        _locationAuthorization = State(initialValue: locationAuthorization)
        _routeCapture = State(
            initialValue: (try? container.get()).map { container in
                LocationTrackingService(
                    context: container.mainContext,
                    authorization: locationAuthorization
                )
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                if let routeCapture {
                    RootView()
                        .modelContainer(container)
                        .environment(locationAuthorization)
                        .environment(routeCapture)
                }
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}
