import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Which control leads the Live Activity, and the exact set and order each
/// important state offers, built through the one path the app uses
/// (``ShiftLiveActivityService/content(for:recordedDistance:asOf:locale:context:)``).
///
/// Pinned exactly, so that a later feature adding a control to the card has to
/// say so here, and cannot push Resume Driving off the bottom of it unnoticed:
/// every list is also held to at most four controls, which is two rows, which is
/// what `ShiftActivityCardLayoutTests` measures to fit.
@MainActor
@Suite("Live Activity control priority")
struct ShiftActivityControlPriorityTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @MainActor
    private struct Store {
        let context: ModelContext
        let shift: Shift
        let deliveries: DeliveryService

        func controls(at date: Date) -> [ShiftActivityControl] {
            content(at: date).controls
        }

        func content(at date: Date) -> ShiftActivityAttributes.ContentState {
            ShiftLiveActivityService.content(
                for: shift, recordedDistance: .none, asOf: date, locale: Locale(identifier: "en_US"), context: context
            )
        }
    }

    private func makeStore(workflow: Bool, stacked: Bool = true) throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(workflow)
        try settings.setHandlesStackedOrdersInOrder(stacked)
        return Store(context: context, shift: shift, deliveries: DeliveryService(context: context))
    }

    // MARK: Workflow off: the card as it always was

    @Test("Workflow off: the delivery step leads, and Park follows Start Delivery")
    func workflowOffKeepsTheLifecycleFirst() throws {
        let store = try makeStore(workflow: false)
        #expect(store.controls(at: at(1)) == [.startDelivery, .park, .pause, .end])

        let delivery = try store.deliveries.startDelivery(at: at(2))
        #expect(store.controls(at: at(3)) == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(ShiftActivityControl.emphasised(in: store.controls(at: at(3))) == .deliveryStep(.arriveAtPickup))

        try store.deliveries.markArrivedAtPickup(delivery, at: at(4))
        #expect(store.controls(at: at(5)) == [.deliveryStep(.pickUp), .startDelivery, .park])

        _ = try ParkVehicleService(context: store.context).park(at: at(6))
        #expect(store.controls(at: at(7)) == [.resumeDriving, .deliveryStep(.pickUp), .startDelivery])
        #expect(ShiftActivityControl.emphasised(in: store.controls(at: at(7))) == .resumeDriving)
    }

    // MARK: Workflow on: Park or Resume Driving leads

    @Test("Workflow on: Park Vehicle leads a quiet shift and takes the emphasis")
    func workflowOnQuiet() throws {
        let store = try makeStore(workflow: true)
        let controls = store.controls(at: at(1))
        #expect(controls == [.park, .startDelivery, .pause, .end])
        #expect(ShiftActivityControl.emphasised(in: controls) == .park)
    }

    @Test("Workflow on: Park Vehicle leads one order at every step, and the step stays on the card")
    func workflowOnOneOrder() throws {
        let store = try makeStore(workflow: true)
        let delivery = try store.deliveries.startDelivery(at: at(1))
        #expect(store.controls(at: at(2)) == [.park, .deliveryStep(.arriveAtPickup), .startDelivery])

        try store.deliveries.markArrivedAtPickup(delivery, at: at(3))
        #expect(store.controls(at: at(4)) == [.park, .deliveryStep(.pickUp), .startDelivery])

        try store.deliveries.markPickedUp(delivery, at: at(5))
        let carrying = store.controls(at: at(6))
        #expect(carrying == [.park, .deliveryStep(.complete), .startDelivery], "Delivered is never hidden")
        #expect(ShiftActivityControl.emphasised(in: carrying) == .park)
    }

    @Test("Workflow on: after Park, Resume Driving leads, and after Resume, Park leads again")
    func workflowOnParkThenResume() throws {
        let store = try makeStore(workflow: true)
        _ = try store.deliveries.startDelivery(at: at(1))
        let parking = ParkVehicleService(context: store.context)

        _ = try parking.park(at: at(2))
        let parked = store.controls(at: at(3))
        #expect(parked == [.resumeDriving, .deliveryStep(.pickUp), .startDelivery])
        #expect(ShiftActivityControl.emphasised(in: parked) == .resumeDriving)
        #expect(!parked.contains(.park), "Never both of the pair")

        _ = try parking.resumeDriving(at: at(9))
        #expect(store.controls(at: at(10)) == [.park, .deliveryStep(.complete), .startDelivery])
    }

    @Test("Workflow on: stacked orders keep Park first beside Start Delivery, and parked keeps Resume first")
    func workflowOnStacked() throws {
        let store = try makeStore(workflow: true)
        _ = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1))
        #expect(store.controls(at: at(2)) == [.park, .startDelivery])

        _ = try ParkVehicleService(context: store.context).park(at: at(3))
        #expect(store.controls(at: at(4)) == [.resumeDriving, .startDelivery])
    }

    @Test("Workflow on: a paused shift offers Resume Shift and End, and neither of the parked pair")
    func workflowOnPaused() throws {
        let store = try makeStore(workflow: true)
        try ShiftService(context: store.context).pauseActiveShift(at: at(1))
        #expect(store.controls(at: at(2)) == [.resume, .end])
    }

    @Test("Turning the workflow off puts the delivery step back in front on the next snapshot")
    func followsTheSetting() throws {
        let store = try makeStore(workflow: true)
        _ = try store.deliveries.startDelivery(at: at(1))
        #expect(store.controls(at: at(2)).first == .park)

        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(false)
        #expect(store.controls(at: at(3)).first == .deliveryStep(.arriveAtPickup))
    }

    @Test("With no settings row the card is the ordinary one, and reading it creates no row")
    func noSettingsRow() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let controls = ShiftLiveActivityService.content(
            for: shift, recordedDistance: .none, asOf: at(1), locale: Locale(identifier: "en_US"), context: context
        ).controls
        #expect(controls == [.startDelivery, .park, .pause, .end])
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty)
    }

    // MARK: Nothing is ever pushed off

    @Test("Every state offers at most four controls, and a running shift always offers the parked pair's current half")
    func neverMoreThanTwoRows() throws {
        for workflow in [false, true] {
            let store = try makeStore(workflow: workflow)
            var moments: [[ShiftActivityControl]] = [store.controls(at: at(1))]
            let first = try store.deliveries.startDelivery(at: at(2))
            moments.append(store.controls(at: at(3)))
            _ = try store.deliveries.startDelivery(at: at(4))
            moments.append(store.controls(at: at(5)))
            _ = try ParkVehicleService(context: store.context).park(at: at(6))
            moments.append(store.controls(at: at(7)))
            _ = try ParkVehicleService(context: store.context).resumeDriving(at: at(8))
            try store.deliveries.cancelDelivery(first, at: at(9))
            moments.append(store.controls(at: at(10)))

            for controls in moments {
                #expect(controls.count <= 4, "\(controls)")
                #expect(controls.contains(.park) != controls.contains(.resumeDriving), "\(controls)")
            }
        }
    }

    // MARK: Shared stops on the card

    @Test("Deliveries marked as sharing a stop, in one state, are one row with one clock")
    func sharedStopIsOneRow() throws {
        let store = try makeStore(workflow: true)
        _ = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1))
        _ = try store.deliveries.startDelivery(at: at(2))

        let timers = store.content(at: at(3)).activeDeliveryTimers
        #expect(timers.map(\.title) == ["Deliveries 1 and 2", "Delivery 3"])
        #expect(timers[0].deliveryCount == 2)
        #expect(timers[0].startedAt == at(1))
        #expect(timers[0].spokenLabel == "Deliveries 1 and 2, to pickup. How long they have been active")
        #expect(timers[1].deliveryCount == nil)
    }

    @Test("Deliveries of one offer that share nothing keep a row each, however alike they are")
    func independentKeepTheirRows() throws {
        let store = try makeStore(workflow: true)
        _ = try store.deliveries.startOffer(deliveryCount: 2, at: at(1))
        #expect(store.content(at: at(2)).activeDeliveryTimers.map(\.title) == ["Delivery 1", "Delivery 2"])
    }

    @Test("A shared pair in different states is two rows again")
    func sharedPairSplitsWhenStatesDiffer() throws {
        let store = try makeStore(workflow: true)
        let pair = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(1)).deliveriesInOrder
        try store.deliveries.markArrivedAtPickup(pair[0], at: at(2))

        let timers = store.content(at: at(3)).activeDeliveryTimers
        #expect(timers.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(timers.map(\.stateLabel) == ["At pickup", "To pickup"])
    }

    @Test("A snapshot persisted before the row count existed still decodes, as one delivery")
    func oldTimerDecodes() throws {
        let json = #"{"title":"Delivery 1","stateLabel":"At pickup","startedAt":0}"#
        let decoded = try JSONDecoder().decode(ShiftActivityDeliveryTimer.self, from: Data(json.utf8))
        #expect(decoded.deliveryCount == nil)
        #expect(!decoded.isShared)
    }
}
