#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Synthetic data and services for SwiftUI previews. Never contains real driver
/// history, and never a real coordinate.
enum PreviewSupport {
    static func emptyContainer() -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! ModelContainerFactory.makeInMemoryContainer()
    }

    static func populatedContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000),
        includingActiveShift: Bool = true
    ) -> ModelContainer {
        let container = emptyContainer()
        let context = ModelContext(container)

        let completed = Shift(startedAt: referenceDate.addingTimeInterval(-4 * 3600))
        try? completed.end(at: referenceDate.addingTimeInterval(-3600))

        let earlier = Shift(startedAt: referenceDate.addingTimeInterval(-30 * 3600))
        try? earlier.end(at: referenceDate.addingTimeInterval(-25 * 3600))

        var shifts = [completed, earlier]
        if includingActiveShift {
            shifts.append(Shift(startedAt: referenceDate.addingTimeInterval(-1800)))
        }

        for shift in shifts {
            context.insert(shift)
        }
        try? context.save()

        return container
    }

    /// The root screen with both location services stubbed.
    ///
    /// Previews get the stub tracking provider, so no preview ever starts a
    /// `CLLocationManager` or reads a position.
    @MainActor
    static func rootView(
        container: ModelContainer,
        status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> some View {
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(status: status)
        )
        let routeCapture = LocationTrackingService(
            context: container.mainContext,
            authorization: authorization,
            provider: StubLocationTrackingProvider()
        )
        return RootView()
            .modelContainer(container)
            .environment(authorization)
            .environment(routeCapture)
    }
}
#endif
