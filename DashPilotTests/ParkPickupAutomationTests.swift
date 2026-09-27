import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Park Vehicle with the pickup-when-parking setting: which delivery moves,
/// which never do, and that parking always stands.
@MainActor
@Suite("Park pickup automation")
struct ParkPickupAutomationTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    private struct Store {
        let context: ModelContext
        let shifts: ShiftService
        let deliveries: DeliveryService
        let settings: SettingsService
    }

    /// A running shift started at `start`, and the automation set as asked.
    private func makeStore(automation isEnabled: Bool?) throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let store = Store(
            context: context,
            shifts: ShiftService(context: context),
            deliveries: DeliveryService(context: context),
            settings: SettingsService(context: context)
        )
        try store.shifts.startShift(at: start)
        if let isEnabled {
            try store.settings.setRecordsPickupWhenParking(isEnabled)
        }
        return store
    }

    /// A delivery accepted at `acceptedAt` and advanced to `state`, one minute
    /// per step.
    @discardableResult
    private func delivery(
        in store: Store,
        acceptedAt: TimeInterval,
        advancedTo state: DeliveryState
    ) throws -> Delivery {
        let delivery = try store.deliveries.startDelivery(at: at(acceptedAt))
        let steps: [DeliveryState] = switch state {
        case .accepted: []
        case .arrivedAtPickup: [.arrivedAtPickup]
        case .pickedUp: [.arrivedAtPickup, .pickedUp]
        case .delivered: [.arrivedAtPickup, .pickedUp, .delivered]
        case .cancelled: [.arrivedAtPickup, .cancelled]
        }
        for (index, step) in steps.enumerated() {
            let date = at(acceptedAt + Double(index + 1) * 60)
            switch step {
            case .arrivedAtPickup: try store.deliveries.markArrivedAtPickup(delivery, at: date)
            case .pickedUp: try store.deliveries.markPickedUp(delivery, at: date)
            case .delivered: try store.deliveries.markDelivered(delivery, at: date)
            case .cancelled: try store.deliveries.cancelDelivery(delivery, at: date)
            case .accepted: break
            }
        }
        #expect(delivery.state == state)
        return delivery
    }

    // MARK: The selection rule

    @Test("Only a delivery at its pickup can receive the step")
    func onlyArrivedIsEligible() {
        let one = ParkPickupSelection.select(among: [DeliveryState.arrivedAtPickup], state: { $0 })
        guard case .one(.arrivedAtPickup) = one else {
            Issue.record("A lone delivery at its pickup is the one")
            return
        }

        for state in [DeliveryState.accepted, .pickedUp, .delivered, .cancelled] {
            guard case .none = ParkPickupSelection.select(among: [state], state: { $0 }) else {
                Issue.record("\(state) must never be advanced by parking")
                continue
            }
        }
    }

    @Test("Two at a pickup is ambiguous, and a delivery already in the car does not make it so")
    func ambiguityCountsOnlyTheEligible() {
        let two = ParkPickupSelection.select(
            among: [DeliveryState.arrivedAtPickup, .arrivedAtPickup, .pickedUp],
            state: { $0 }
        )
        guard case .several(count: 2) = two else {
            Issue.record("Two deliveries at pickups advance neither")
            return
        }

        let stacked = ParkPickupSelection.select(
            among: [(1, DeliveryState.pickedUp), (2, .arrivedAtPickup), (3, .accepted)],
            state: { $0.1 }
        )
        guard case let .one(chosen) = stacked else {
            Issue.record("One at a pickup among others that cannot receive the step is unambiguous")
            return
        }
        #expect(chosen.0 == 2)
    }

    @Test("Deliveries still on their way are counted, so the driver can be told why")
    func acceptedIsCountedAsAwaitingArrival() {
        let selection = ParkPickupSelection.select(
            among: [DeliveryState.accepted, .accepted, .pickedUp],
            state: { $0 }
        )
        guard case .none(awaitingArrival: 2) = selection else {
            Issue.record("Expected two awaiting arrival")
            return
        }
    }

    // MARK: Off

    @Test("With no settings row the automation is off, and parking creates none")
    func defaultsOff() throws {
        let store = try makeStore(automation: nil)
        let waiting = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.pickup == .notEnabled)
        #expect(result.shift.isRouteSuspended)
        #expect(waiting.state == .arrivedAtPickup)
        #expect(try store.context.fetch(FetchDescriptor<DriverSettings>()).isEmpty)
    }

    @Test("Off, parking does exactly what it did before the setting existed")
    func offParksOnly() throws {
        let store = try makeStore(automation: false)
        let waiting = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)
        let lastEvent = waiting.lastEventAt

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.pickup == .notEnabled)
        #expect(result.pickup.statement == nil, "Nothing is added to what the driver is told")
        #expect(result.shift.routeSuspensions.count == 1)
        #expect(result.shift.openRouteSuspension?.startedAt == at(600))
        #expect(result.shift.lifecycleState == .running)
        #expect(waiting.state == .arrivedAtPickup)
        #expect(waiting.pickedUpAt == nil)
        #expect(waiting.lastEventAt == lastEvent)
    }

    // MARK: On

    @Test("On, the one delivery at its pickup is picked up at the instant of parking")
    func onAdvancesTheOneEligible() throws {
        let store = try makeStore(automation: true)
        let waiting = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)
        let arrivedAt = waiting.arrivedAtPickupAt

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.shift.isRouteSuspended)
        #expect(result.pickup == .recorded(deliveryNumber: 1))
        #expect(waiting.state == .pickedUp)
        #expect(waiting.pickedUpAt == at(600), "The tap's own instant, as the card's button would record it")
        #expect(waiting.arrivedAtPickupAt == arrivedAt, "The arrival the driver recorded is untouched")
        #expect(waiting.acceptedAt == at(60))
        #expect(result.shift.openRouteSuspension?.startedAt == at(600))
    }

    @Test("On, the pickup instant follows the manual control's clamping rather than inventing an earlier one")
    func onClampsLikeTheManualControl() throws {
        let store = try makeStore(automation: true)
        let waiting = try delivery(in: store, acceptedAt: 600, advancedTo: .arrivedAtPickup)
        // A device clock that has moved behind the recorded arrival.
        let arrivedAt = try #require(waiting.arrivedAtPickupAt)

        _ = try ParkVehicleService(context: store.context).park(at: at(300))

        #expect(waiting.pickedUpAt == arrivedAt, "Clamped to the delivery's own last event, never before it")
    }

    @Test("On with nothing in progress parks only, and says nothing more")
    func onWithNoDeliveryParksOnly() throws {
        let store = try makeStore(automation: true)

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.shift.isRouteSuspended)
        #expect(result.pickup == .noneAtPickup(awaitingArrival: 0))
        #expect(result.pickup.statement == nil)
    }

    @Test("On, a delivery with no arrival recorded is not given one")
    func onDoesNotInventAnArrival() throws {
        let store = try makeStore(automation: true)
        let heading = try delivery(in: store, acceptedAt: 60, advancedTo: .accepted)

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.shift.isRouteSuspended)
        #expect(result.pickup == .noneAtPickup(awaitingArrival: 1))
        #expect(heading.state == .accepted)
        #expect(heading.arrivedAtPickupAt == nil, "Parking is not evidence of which place the vehicle stopped at")
        #expect(heading.pickedUpAt == nil)
        #expect(result.pickup.statement?.contains("Arrived at Pickup") == true)
    }

    @Test("On, a delivery already picked up is left exactly as it was")
    func onLeavesPickedUpAlone() throws {
        let store = try makeStore(automation: true)
        let carrying = try delivery(in: store, acceptedAt: 60, advancedTo: .pickedUp)
        let pickedUpAt = carrying.pickedUpAt

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.shift.isRouteSuspended)
        #expect(result.pickup == .noneAtPickup(awaitingArrival: 0))
        #expect(carrying.state == .pickedUp)
        #expect(carrying.pickedUpAt == pickedUpAt)
        #expect(carrying.deliveredAt == nil)
    }

    @Test("On, finished deliveries are never touched")
    func onLeavesTerminalAlone() throws {
        let store = try makeStore(automation: true)
        let delivered = try delivery(in: store, acceptedAt: 60, advancedTo: .delivered)
        let cancelled = try delivery(in: store, acceptedAt: 400, advancedTo: .cancelled)

        let result = try ParkVehicleService(context: store.context).park(at: at(900))

        #expect(result.shift.isRouteSuspended)
        #expect(result.pickup == .noneAtPickup(awaitingArrival: 0))
        #expect(delivered.state == .delivered)
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.pickedUpAt == nil, "A cancelled delivery is not given a pickup")
    }

    @Test("On, two deliveries at a pickup: the vehicle parks and neither moves")
    func onWithTwoEligibleAdvancesNeither() throws {
        let store = try makeStore(automation: true)
        let first = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)
        let second = try delivery(in: store, acceptedAt: 120, advancedTo: .arrivedAtPickup)

        let result = try ParkVehicleService(context: store.context).park(at: at(600))

        #expect(result.shift.isRouteSuspended, "Parking always stands")
        #expect(result.pickup == .severalAtPickup(count: 2))
        #expect(first.state == .arrivedAtPickup)
        #expect(second.state == .arrivedAtPickup)
        #expect(first.pickedUpAt == nil && second.pickedUpAt == nil)
        let statement = try #require(result.pickup.statement)
        #expect(statement.contains("not recorded"))
        #expect(statement.contains("2 deliveries"))
    }

    @Test("On, stacked: only the delivery at its pickup moves, and the one in the car does not")
    func onStackedAdvancesOnlyTheEligible() throws {
        let store = try makeStore(automation: true)
        let carrying = try delivery(in: store, acceptedAt: 60, advancedTo: .pickedUp)
        let carryingPickup = carrying.pickedUpAt
        let waiting = try delivery(in: store, acceptedAt: 300, advancedTo: .arrivedAtPickup)
        let heading = try delivery(in: store, acceptedAt: 500, advancedTo: .accepted)

        let result = try ParkVehicleService(context: store.context).park(at: at(900))

        #expect(result.pickup == .recorded(deliveryNumber: 2), "Named by the number its card shows")
        #expect(waiting.state == .pickedUp)
        #expect(waiting.pickedUpAt == at(900))
        #expect(carrying.state == .pickedUp)
        #expect(carrying.pickedUpAt == carryingPickup, "Delivery 1 is not modified")
        #expect(heading.state == .accepted)
        #expect(result.pickup.statement == "Delivery 2 marked Picked Up when you parked.")
    }

    // MARK: Failure

    @Test("A refused park attempts no pickup")
    func parkingFailureRunsNoAutomation() throws {
        let store = try makeStore(automation: true)
        try store.shifts.parkActiveShift(at: at(300))
        let waiting = try delivery(in: store, acceptedAt: 400, advancedTo: .arrivedAtPickup)

        #expect(throws: ShiftLifecycleError.shiftAlreadyParked(parkedAt: at(300))) {
            try ParkVehicleService(context: store.context).park(at: at(900))
        }
        #expect(waiting.state == .arrivedAtPickup, "No parking was recorded, so no pickup was either")
    }

    @Test("With no shift running, Park is refused and nothing is written")
    func noShiftRunsNoAutomation() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        try SettingsService(context: context).setRecordsPickupWhenParking(true)

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try ParkVehicleService(context: context).park(at: at(600))
        }
        #expect(try context.fetch(FetchDescriptor<RouteSuspension>()).isEmpty)
    }

    @Test("A pickup whose save fails leaves the vehicle parked and the delivery at its pickup")
    func pickupFailureDoesNotUndoParking() throws {
        let store = try makeStore(automation: true)
        try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)

        struct Refused: Error {}
        let result = try ParkVehicleService(
            context: store.context,
            deliveryCommit: { _ in throw Refused() }
        ).park(at: at(600))

        #expect(result.pickup == .notRecorded(deliveryNumber: 1))
        #expect(result.pickup.statement?.contains("not recorded") == true)
        #expect(!store.context.hasChanges, "The rollback left nothing pending")

        // Read through a fresh context, the convention every refused-save test
        // here follows: a rollback restores the store, and a model instance held
        // across it can still report the value that was discarded.
        let fresh = ModelContext(store.context.container)
        let shift = try #require(try fresh.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.isRouteSuspended, "Parking was saved first and stands")
        #expect(shift.openRouteSuspension?.startedAt == at(600))
        let stored = try #require(try fresh.fetch(FetchDescriptor<Delivery>()).first)
        #expect(stored.state == .arrivedAtPickup)
        #expect(stored.pickedUpAt == nil)
    }

    // MARK: Changing the setting

    @Test("Turning the setting off restores ordinary parking at the next press")
    func disablingRestoresOrdinaryParking() throws {
        let store = try makeStore(automation: true)
        let first = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)

        let parked = try ParkVehicleService(context: store.context).park(at: at(600))
        #expect(parked.pickup.recordedPickup)
        try store.shifts.resumeDrivingOnActiveShift(at: at(900))

        try store.settings.setRecordsPickupWhenParking(false)
        let second = try delivery(in: store, acceptedAt: 1_000, advancedTo: .arrivedAtPickup)
        let again = try ParkVehicleService(context: store.context).park(at: at(1_500))

        #expect(again.pickup == .notEnabled)
        #expect(second.state == .arrivedAtPickup)
        #expect(first.state == .pickedUp, "Turning it off rewrites nothing already recorded")
        #expect(first.pickedUpAt == at(600))
    }

    @Test("Parking with the automation writes no relationship between the suspension and a delivery")
    func noDeliveryJoinsTheSuspension() throws {
        let store = try makeStore(automation: true)
        _ = try delivery(in: store, acceptedAt: 60, advancedTo: .arrivedAtPickup)

        let result = try ParkVehicleService(context: store.context).park(at: at(600))
        let suspension = try #require(result.shift.openRouteSuspension)

        #expect(suspension.shift?.id == result.shift.id)
        #expect(try store.context.fetch(FetchDescriptor<RouteSuspension>()).count == 1)
    }

    // MARK: Wording

    @Test("No sentence claims DashPilot saw the order handed over")
    func wordingClaimsNoDetection() {
        let outcomes: [ParkPickupOutcome] = [
            .notEnabled, .recorded(deliveryNumber: 3), .recorded(deliveryNumber: nil),
            .severalAtPickup(count: 2), .noneAtPickup(awaitingArrival: 1),
            .noneAtPickup(awaitingArrival: 0), .notRecorded(deliveryNumber: 1)
        ]
        for outcome in outcomes {
            for sentence in [outcome.statement, outcome.spokenStatement].compactMap({ $0 }) {
                let lowered = sentence.lowercased()
                #expect(!lowered.contains("detect"), "\(sentence)")
                #expect(!lowered.contains("confirmed"), "\(sentence)")
            }
        }
        #expect(ParkPickupOutcome.recorded(deliveryNumber: 3).statement?.contains("Delivery 3") == true)
        #expect(
            ParkPickupOutcome.recorded(deliveryNumber: 3).spokenStatement?.contains("Pick up order when parking")
                == true,
            "A listener is told the event came from their setting"
        )
    }

    @Test("Success and refusal differ by symbol, not only by tint")
    func resultIsNotColourAlone() {
        #expect(
            ParkPickupOutcome.recorded(deliveryNumber: 1).symbolName
                != ParkPickupOutcome.severalAtPickup(count: 2).symbolName
        )
    }
}
