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

    /// The shift's Live Activity, over the same container and the same main
    /// context. `nil` for the same reason capture is: with no store there is no
    /// shift to describe.
    ///
    /// Taken from ``AppShiftLiveActivity`` rather than built here, because an
    /// App Intent performed with no scene has to reach the same coordinator this
    /// scene does. Two over one activity would race each other into two cards.
    @State private var liveActivity: ShiftLiveActivityService?

    init() {
        // Opened through `AppModelContainer` rather than here, so that the App
        // Intents perform against the same container this scene reads. Either
        // side may be the first to touch it: iOS can launch the process to run
        // an intent with no scene at all.
        let container = AppModelContainer.shared
        let locationAuthorization = Self.makeAuthorizationService()

        let liveActivity = AppShiftLiveActivity.shared
        let routeCapture = (try? container.get()).map { container in
            Self.makeTrackingService(
                context: container.mainContext,
                authorization: locationAuthorization
            )
        }

        // Route capture is the only thing that knows a shift's recorded mileage
        // has moved while the app is off screen, which is where most of a shift
        // is recorded. The activity is asked to *reconcile*, never told what
        // changed: it reads the store itself.
        routeCapture?.onRoutePersisted = { [weak liveActivity] in
            liveActivity?.reconcile()
        }

        self.container = container
        _locationAuthorization = State(initialValue: locationAuthorization)
        _routeCapture = State(initialValue: routeCapture)
        _liveActivity = State(initialValue: liveActivity)
    }

    /// Core Location, or the stub a UI test asked for.
    ///
    /// The seam is here rather than inside the services because it is the same
    /// decision the store fixtures make in ``AppModelContainer``: which
    /// dependency this launch is built over. Debug builds only, so a release
    /// has one path and no way to reach another.
    private static func makeAuthorizationService() -> LocationAuthorizationService {
        #if DEBUG
        // The simulated route implies the permission stub: a fed route with no
        // grant would be refused before the filter ever saw it.
        if LaunchArgument.isPresent(LaunchArgument.stubbedLocation)
            || LaunchArgument.isPresent(LaunchArgument.simulatedRoute) {
            return LocationAuthorizationService(
                provider: StubLocationAuthorizationProvider(status: .authorizedWhenInUse)
            )
        }
        #endif
        return LocationAuthorizationService()
    }

    private static func makeTrackingService(
        context: ModelContext,
        authorization: LocationAuthorizationService
    ) -> LocationTrackingService {
        #if DEBUG
        if LaunchArgument.isPresent(LaunchArgument.simulatedRoute) {
            return LocationTrackingService(
                context: context,
                authorization: authorization,
                provider: SimulatedRouteLocationProvider()
            )
        }
        if LaunchArgument.isPresent(LaunchArgument.stubbedLocation) {
            return LocationTrackingService(
                context: context,
                authorization: authorization,
                provider: StubLocationTrackingProvider()
            )
        }
        #endif
        return LocationTrackingService(context: context, authorization: authorization)
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                if let routeCapture, let liveActivity {
                    RootView()
                        .modelContainer(container)
                        .environment(locationAuthorization)
                        .environment(routeCapture)
                        .environment(liveActivity)
                }
            case .failure(let error):
                PersistenceUnavailableView(error: error)
            }
        }
    }
}
