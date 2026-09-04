import SwiftData
import SwiftUI

@main
struct DashPilotApp: App {
    /// Built once at launch. Store failure is a state the user is shown, not a crash.
    private let container: Result<ModelContainer, Error>

    /// Owned by the app rather than the root view so that one location manager
    /// exists for the process. It reads permission only; nothing here starts
    /// location updates or prompts the driver at launch.
    @State private var locationAuthorization = LocationAuthorizationService()

    init() {
        container = Result<ModelContainer, Error> {
            #if DEBUG
            if LaunchArgument.isPresent(LaunchArgument.inMemoryStore) {
                return try ModelContainerFactory.makeInMemoryContainer()
            }
            #endif
            return try ModelContainerFactory.makeAppContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                RootView()
                    .modelContainer(container)
                    .environment(locationAuthorization)
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}
