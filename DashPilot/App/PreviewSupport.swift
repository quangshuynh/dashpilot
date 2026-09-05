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
        // Previews cannot meaningfully recover from a container failure.
        try! seededHistoryContainer(referenceDate: referenceDate, includingActiveShift: includingActiveShift)
    }

    /// The same synthetic history, built through a throwing call so a UI test
    /// launch can report a store failure rather than trapping inside it.
    static func seededHistoryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000),
        includingActiveShift: Bool = true
    ) throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let completed = Shift(startedAt: referenceDate.addingTimeInterval(-4 * 3600))
        try? completed.end(at: referenceDate.addingTimeInterval(-3600))

        let earlier = Shift(startedAt: referenceDate.addingTimeInterval(-30 * 3600))
        try? earlier.end(at: referenceDate.addingTimeInterval(-25 * 3600))

        // One shift with an amount recorded and one without, so both the
        // recorded figure and the "Add Earnings" affordance are visible. The
        // amount is invented for the preview, like every other value here.
        try? completed.setGrossEarnings(Money(minorUnits: 8625))

        var shifts = [completed, earlier]
        if includingActiveShift {
            shifts.append(Shift(startedAt: referenceDate.addingTimeInterval(-1800)))
        }

        for shift in shifts {
            context.insert(shift)
        }

        // The most recent completed shift gets a short synthetic route in two
        // capture sessions, so the history row shows a measured, partial
        // distance. The older one keeps no route, so the "nothing to measure"
        // wording is visible too.
        for sample in syntheticRoute(from: completed.startedAt) {
            context.insert(sample.attached(to: completed))
        }

        try? context.save()

        return container
    }

    /// The shapes of completed shift a detail screen has to handle.
    enum DetailFixture {
        /// An amount recorded and a measured route with a gap in it, which is
        /// the ordinary case and the one where every figure exists.
        case withEarningsAndRoute
        /// Neither, which is the case where the screen has to explain absences
        /// rather than show numbers.
        case withoutEarningsOrRoute
    }

    /// A short made-up route: two capture sessions with a gap between them.
    ///
    /// The origin is a round number in open country chosen for arithmetic, not a
    /// place anyone has driven, and every position is an explicit offset north
    /// of it. No preview contains a real coordinate.
    private static func syntheticRoute(from start: Date) -> [PreviewRouteSample] {
        let firstSession = UUID()
        let secondSession = UUID()
        let metresPerDegreeLatitude = 111_320.0

        func sample(secondsIn: TimeInterval, northMetres: Double, session: UUID) -> PreviewRouteSample {
            PreviewRouteSample(
                timestamp: start.addingTimeInterval(secondsIn),
                latitude: 40.0 + northMetres / metresPerDegreeLatitude,
                longitude: -75.0,
                captureSessionID: session
            )
        }

        return (0..<12).map { step in
            sample(secondsIn: Double(step) * 20, northMetres: Double(step) * 400, session: firstSession)
        } + (0..<8).map { step in
            // Half an hour later and further along: the driver had DashPilot in
            // the background in between, and that distance is not recorded.
            sample(
                secondsIn: 1800 + Double(step) * 20,
                northMetres: 9_000 + Double(step) * 400,
                session: secondSession
            )
        }
    }

    /// A position waiting to be attached to a shift.
    private struct PreviewRouteSample {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let captureSessionID: UUID

        func attached(to shift: Shift) -> RouteSample {
            RouteSample(
                shift: shift,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: 8,
                captureSessionID: captureSessionID
            )
        }
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

    /// The completed shift detail screen over a synthetic shift.
    ///
    /// Wrapped in its own `NavigationStack` so the title and the destructive
    /// confirmation appear the way they do when a history row pushes it.
    @MainActor
    static func completedShiftDetail(_ fixture: DetailFixture) -> some View {
        let container = emptyContainer()
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(3 * 3600))

        if fixture == .withEarningsAndRoute {
            try? shift.setGrossEarnings(Money(minorUnits: 8625))
        }
        container.mainContext.insert(shift)
        if fixture == .withEarningsAndRoute {
            for sample in syntheticRoute(from: start) {
                container.mainContext.insert(sample.attached(to: shift))
            }
        }
        try? container.mainContext.save()

        return NavigationStack {
            CompletedShiftDetailView(shift: shift)
        }
        .modelContainer(container)
    }

    /// The earnings editor over a synthetic completed shift.
    @MainActor
    static func earningsEditor(withRecordedEarnings: Bool) -> some View {
        let container = emptyContainer()
        let shift = Shift(startedAt: Date(timeIntervalSince1970: 1_756_000_000))
        try? shift.end(at: Date(timeIntervalSince1970: 1_756_000_000 + 4 * 3600))
        if withRecordedEarnings {
            try? shift.setGrossEarnings(Money(minorUnits: 8625))
        }
        container.mainContext.insert(shift)

        return ShiftEarningsEditor(shift: shift).modelContainer(container)
    }
}
#endif
