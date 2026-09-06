import SwiftData
import SwiftUI

@main
struct DashPilotApp: App {
    /// The process's store, opened once and shared with the App Intents.
    /// Failure is a state the user is shown, not a crash.
    private let container: Result<ModelContainer, any Error>

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
        // Opened through `AppModelContainer` rather than here, so that the App
        // Intents perform against the same container this scene reads. Either
        // side may be the first to touch it: iOS can launch the process to run
        // an intent with no scene at all.
        let container = AppModelContainer.shared
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
