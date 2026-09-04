import SwiftData
import SwiftUI

@main
struct DashPilotApp: App {
    /// Built once at launch. Store failure is a state the user is shown, not a crash.
    private let container: Result<ModelContainer, Error>

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
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}
