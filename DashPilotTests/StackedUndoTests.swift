import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The one Undo after an automatic resume, with stacked deliveries.
///
/// ``ParkedProgressTests`` pins Undo for one delivery. Here the stop holds two,
/// delivered in order: the first leaves the vehicle parked and offers no Undo
/// of driving, the second resumes driving and offers one Undo for its step and
/// the driving together. Taking it back must restore the parked stretch, drop
/// the positions recorded since, leave the earlier sibling delivered, and leave
/// the next resume minting a new capture session.
@MainActor
@Suite("Stacked Undo")
struct StackedUndoTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @MainActor
    private struct Harness {
        /// Held so the store outlives `makeHarness()`: a main context does not
        /// keep its container alive.
        let container: ModelContainer
        let context: ModelContext
        let tracking: LocationTrackingService
        let provider: StubLocationTrackingProvider
        let clock: Clock

        final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

        var shift: Shift { get throws { try #require(try ShiftService(context: context).activeShift()) } }
        var deliveries: DeliveryService { DeliveryService(context: context) }
        var progress: DeliveryProgressService { DeliveryProgressService(context: context) }

        @MainActor
        func emit(_ date: Date, north: Double) {
            clock.now = date
            provider.emit(SyntheticRoute.sample(at: date, northMetres: north))
        }

        func stored(_ delivery: Delivery) throws -> Delivery {
            let id = delivery.id
            let fresh = ModelContext(context.container)
            return try #require(try fresh.fetch(FetchDescriptor<Delivery>(predicate: #Predicate { $0.id == id })).first)
        }
    }

    private func makeHarness() throws -> Harness {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let provider = StubLocationTrackingProvider()
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(servicesEnabled: true, status: .authorizedWhenInUse, accuracy: .full)
        )
        let clock = Harness.Clock(start)
        let tracking = LocationTrackingService(
            context: context, authorization: authorization, provider: provider, saveBatchSize: 1, now: { clock.now }
        )
        try ShiftService(context: context).startShift(at: start)
        try SettingsService(context: context).setResumesDrivingAfterDeliveryProgress(true)
        tracking.synchronize()
        return Harness(container: container, context: context, tracking: tracking, provider: provider, clock: clock)
    }

    /// Two picked up, driven to the drop-off, parked, then delivered in order.
    private func deliverPairWhileParked(
        _ harness: Harness, sharing: Set<SharedStopKind>
    ) throws -> (pair: [Delivery], last: DeliveryProgressResult) {
        let pair = try harness.deliveries.startOffer(deliveryCount: 2, sharing: sharing, at: at(1)).deliveriesInOrder
        for delivery in pair {
            try harness.deliveries.markArrivedAtPickup(delivery, at: at(2))
            try harness.deliveries.markPickedUp(delivery, at: at(3))
        }
        for step in 1...5 { harness.emit(at(4).addingTimeInterval(Double(step) * 5), north: Double(step) * 100) }

        harness.tracking.prepareForRouteSuspension()
        try ParkVehicleService(context: harness.context).park(at: at(6))
        harness.tracking.synchronize()

        let first = try harness.progress.record(.delivered, of: pair[0], at: at(8))
        #expect(first.undoableAction == nil, "The first leaves the vehicle parked: no driving to take back")
        #expect(try harness.shift.isRouteSuspended)

        harness.clock.now = at(9)
        let last = try harness.progress.record(.delivered, of: pair[1], at: at(9))
        harness.tracking.synchronize()
        for step in 1...5 { harness.emit(at(10).addingTimeInterval(Double(step) * 5), north: 5_000 + Double(step) * 100) }
        return (pair, last)
    }

    @Test("Unmarked pair: one Undo takes back the second Delivered and the driving, and the first stays delivered")
    func unmarkedPair() throws {
        let harness = try makeHarness()
        let (pair, last) = try deliverPairWhileParked(harness, sharing: [])
        #expect(last.parked == .resumed(step: .delivered, deliveryNumbers: [2]))
        let action = try #require(last.undoableAction)
        #expect(action.deliveryID == pair[1].id, "The Undo names the delivery whose step resumed driving")

        harness.tracking.prepareForRouteSuspension()
        try harness.progress.undo(action)
        harness.tracking.synchronize()

        #expect(try harness.stored(pair[0]).state == .delivered, "The sibling is not reverted")
        #expect(try harness.stored(pair[1]).state == .pickedUp)
        #expect(try harness.shift.isRouteSuspended, "Parked again, in the same stretch")
        #expect(try harness.shift.routeSuspensions.count == 1)
        #expect(harness.tracking.state == .routeSuspended)
        #expect(try harness.shift.routeSamples().allSatisfy { $0.timestamp < at(9) }, "No position survives the restored stretch")
        #expect(try harness.shift.routeSamples().count == 5)
    }

    @Test("Same drop-off pair: Undo takes back only the member whose step resumed, and the group holds the stop open again")
    func sameDropOffPair() throws {
        let harness = try makeHarness()
        let (pair, last) = try deliverPairWhileParked(harness, sharing: [.dropOff])
        #expect(last.parked == .resumed(step: .delivered, deliveryNumbers: [1, 2]))

        harness.tracking.prepareForRouteSuspension()
        try harness.progress.undo(try #require(last.undoableAction))
        harness.tracking.synchronize()

        #expect(try harness.stored(pair[0]).state == .delivered)
        #expect(try harness.stored(pair[1]).state == .pickedUp)
        #expect(try harness.shift.isRouteSuspended)

        // Recorded again, from Siri: the same rule chooses the same delivery and
        // resumes driving again, so the state Undo left is one the rule accepts.
        harness.clock.now = at(12)
        let again = try IntentLifecycleService(context: harness.context).recordDelivered(at: at(12))
        #expect(again == .deliveryEventRecorded(
            number: 2, state: .delivered, parked: .resumed(step: .delivered, deliveryNumbers: [1, 2])
        ))
        #expect(try !harness.shift.isRouteSuspended)
    }

    @Test("After Undo, driving again mints a new capture session and nothing is measured across the stretch")
    func noBridgeAfterUndo() throws {
        let harness = try makeHarness()
        let (_, last) = try deliverPairWhileParked(harness, sharing: [])

        harness.tracking.prepareForRouteSuspension()
        try harness.progress.undo(try #require(last.undoableAction))
        harness.tracking.synchronize()

        harness.clock.now = at(15)
        _ = try ParkVehicleService(context: harness.context).resumeDriving(at: at(15))
        harness.tracking.synchronize()
        for step in 1...5 { harness.emit(at(16).addingTimeInterval(Double(step) * 5), north: 9_000 + Double(step) * 100) }

        let shift = try harness.shift
        let samples = shift.routeSamples()
        #expect(Set(samples.map(\.captureSessionID)).count == 2, "Before the stretch, and after the real resume")
        #expect(!samples.contains { $0.timestamp >= at(9) && $0.timestamp < at(15) }, "Nothing from the undone resume")
        let distance = shift.recordedDistance()
        #expect(distance.metres < 1_000, "No line across the restored stretch: \(distance.metres)")
        #expect(shift.routeSuspensions.first?.endedAt == at(15))
    }

    @Test("Undo is refused whole once the vehicle is parked again, and nothing moves")
    func refusedAfterParkingAgain() throws {
        let harness = try makeHarness()
        let (pair, last) = try deliverPairWhileParked(harness, sharing: [])
        harness.tracking.prepareForRouteSuspension()
        try ParkVehicleService(context: harness.context).park(at: at(12))

        #expect(throws: DeliveryLifecycleError.self) { try harness.progress.undo(try #require(last.undoableAction)) }
        #expect(try harness.stored(pair[1]).state == .delivered)
        #expect(try harness.shift.routeSuspensions.count == 2)
        #expect(try harness.shift.routeSamples().count == 10, "The positions recorded between the stretches stay")
    }
}
