#if DEBUG
import Foundation

/// A ``LocationTrackingProviding`` that drives a synthetic vehicle in a straight
/// line, for the journeys that have to watch a figure move.
///
/// ## Why it exists
///
/// A UI test cannot make a simulator record a route. Every other route-dependent
/// journey is written against seeded history, which works because a finished
/// shift's route is a fact that can be written down in advance. A **live**
/// mileage figure cannot be: what has to be asserted is that it grows while
/// positions are accepted, that it stops growing the moment the driver pauses,
/// and that resuming does not add the distance covered during the break. All
/// three are statements about capture running, and none of them can be reached
/// from a store fixture.
///
/// So this feeds the real pipeline. ``RouteSampleFilter``, ``LocationTrackingService``,
/// the capture sessions, the store writes and the measurement are all the
/// shipping ones; only the source of the positions is synthetic. Debug builds
/// only, behind a launch argument, like every other fixture in this app.
///
/// ## The one thing it does on purpose
///
/// **The vehicle keeps moving while updates are stopped.** Position is a
/// function of the wall clock and nothing else, so a shift paused for ten
/// seconds resumes four hundred metres further along, exactly as a driver who
/// takes a break somewhere and resumes somewhere else does. That distance is
/// what must not appear in the recorded mileage, and it is the whole point of
/// the fixture: a provider that froze while stopped could not tell a correct
/// app from one that bridges a pause.
///
/// ## The numbers, and why they are these numbers
///
/// The synthetic vehicle travels at 25 m/s and reports a position twice a
/// second, which puts 12.5 m between consecutive fixes. That clears
/// ``RouteSampleFilter/minimumDistance``, and the apparent speed the filter
/// computes across a pause of ten or twenty seconds stays well under
/// ``RouteSampleFilter/maximumSpeed``, so the first position after a resume is
/// accepted rather than rejected as a broken fix. It is fast for a delivery
/// driver, and deliberately so: it is a test fixture that has to move the first
/// decimal place of a mileage figure within the time a journey can wait, while
/// staying slow enough that the distance covered during a short pause is several
/// times what the next couple of seconds of recording adds.
///
/// The origin is the same round number the domain tests use. No real route,
/// address or location history appears in this repository.
@MainActor
final class SimulatedRouteLocationProvider: LocationTrackingProviding {
    private(set) var isUpdating = false

    /// The shipping declaration: this build carries the location background
    /// mode, so a running session continues off screen.
    let supportsBackgroundUpdates = true

    private(set) var allowsBackgroundUpdates = false

    var onSample: ((LocationSample) -> Void)?
    var onFailure: ((LocationTrackingFailure) -> Void)?

    /// Metres travelled per second of wall clock, whether or not anyone is
    /// listening.
    private let metresPerSecond: Double

    /// How often a position is reported while updates are running.
    private let reportingInterval: TimeInterval

    /// What the synthetic device claims its fixes are worth, in metres.
    private let horizontalAccuracy: Double

    /// When the synthetic vehicle set off. Fixed for the life of the process, so
    /// stopping and starting updates never rewinds it.
    private let departedAt: Date

    private let now: () -> Date

    private var timer: Timer?

    init(
        metresPerSecond: Double = 25,
        reportingInterval: TimeInterval = 0.5,
        horizontalAccuracy: Double = 5,
        now: @escaping () -> Date = { .now }
    ) {
        self.metresPerSecond = metresPerSecond
        self.reportingInterval = reportingInterval
        self.horizontalAccuracy = horizontalAccuracy
        self.now = now
        self.departedAt = now()
    }

    func startUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        allowsBackgroundUpdates = supportsBackgroundUpdates

        let timer = Timer.scheduledTimer(withTimeInterval: reportingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        // The run loop runs in a tracking mode while a list is being scrolled,
        // and a fixture that stopped feeding positions because someone touched
        // the screen would be a confusing thing to debug.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        allowsBackgroundUpdates = false
        timer?.invalidate()
        timer = nil
    }

    /// Where the synthetic vehicle is now, and when.
    private func report() {
        guard isUpdating else { return }
        let instant = now()
        let metres = max(0, instant.timeIntervalSince(departedAt)) * metresPerSecond
        onSample?(
            LocationSample(
                timestamp: instant,
                latitude: Self.originLatitude + metres / Self.metresPerDegreeLatitude,
                longitude: Self.originLongitude,
                horizontalAccuracy: horizontalAccuracy
            )
        )
    }

    /// A round number chosen for arithmetic, not a place anyone has driven.
    static let originLatitude = 40.0
    static let originLongitude = -75.0

    /// Close enough for offsets of a few kilometres, and the same constant the
    /// domain fixtures use.
    static let metresPerDegreeLatitude = 111_320.0
}
#endif
