import Foundation
import OSLog
import SwiftData

/// What one press of Park recorded.
struct ParkVehicleResult {
    /// The shift, now recorded as parked.
    let shift: Shift
    /// What the pickup automation did, including that it was not enabled.
    let pickup: ParkPickupOutcome
}

/// Park Vehicle, from every surface, in one place.
///
/// ## The one operation behind three surfaces
///
/// The app's button, ``ParkVehicleIntent`` and ``ParkVehicleFromActivityIntent``
/// all reach ``park(at:)``: the button directly, the two intents through
/// ``IntentLifecycleService/parkVehicle(at:)``. So the driver's setting applies
/// the same way whichever surface they pressed, and there is no second place
/// the automation could drift from.
///
/// ## It owns no lifecycle logic
///
/// It **composes** two writes that already exist and adds only the decision
/// between them:
///
/// 1. ``ShiftService/parkActiveShift(at:)``, unchanged. It is still the only
///    thing that opens a ``RouteSuspension``, and the suspension still belongs
///    to the shift and to no delivery. If it refuses, this throws its refusal
///    and nothing else is attempted.
/// 2. Only if that succeeded **and** the driver turned the setting on,
///    ``DeliveryService/markPickedUp(_:at:)``, the same operation the Picked Up
///    button on a delivery's card calls, for the one delivery
///    ``ParkPickupSelection`` names. Same validation, same clamping to the
///    delivery's own last event, same save and rollback. The one difference is
///    that it records the pickup as ``PickupProvenance/parkAutomation``, so the
///    wait it closes can be told apart from one the driver closed themselves.
///
/// ## Two saves, in that order, on purpose
///
/// Parking is saved before the pickup is attempted, so **a pickup that is
/// refused or fails can never undo the parking**. That is the ordering the
/// driver needs: Park must always be able to stop the route, and a pickup
/// that did not record is one they can still record from the card. The reverse
/// failure cannot happen, because the pickup is never attempted without a
/// saved suspension.
///
/// ## Timestamps
///
/// The pickup is recorded at the instant passed to Park, which is when the
/// driver pressed it, through the manual control's own clamping. Nothing
/// earlier is manufactured and nothing later is guessed at: DashPilot does not
/// know when the order was handed over, and the event records what the driver
/// said by pressing Park.
@MainActor
struct ParkVehicleService {
    private let context: ModelContext

    /// How the pickup is handed to the store. The delivery service's own seam,
    /// passed through so a test can refuse the pickup's save after parking has
    /// already been saved.
    private let deliveryCommit: (ModelContext) throws -> Void

    init(context: ModelContext, deliveryCommit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.deliveryCommit = deliveryCommit
    }

    /// Records the vehicle as parked and, when the driver has asked for it and
    /// exactly one delivery is waiting at a pickup, records that delivery's
    /// pickup too.
    ///
    /// - Throws: whatever ``ShiftService/parkActiveShift(at:)`` throws. A
    ///   refused or failed pickup is **not** thrown: parking has succeeded, and
    ///   the outcome says what happened to the pickup.
    @discardableResult
    func park(at date: Date = .now) throws -> ParkVehicleResult {
        let shift = try ShiftService(context: context).parkActiveShift(at: date)
        return ParkVehicleResult(shift: shift, pickup: recordPickupIfEnabled(on: shift, at: date))
    }

    private func recordPickupIfEnabled(on shift: Shift, at date: Date) -> ParkPickupOutcome {
        guard SettingsService(context: context).recordsPickupWhenParking() else { return .notEnabled }

        let deliveries = DeliveryService(context: context, commit: deliveryCommit)
        let active: [Delivery]
        do {
            active = try deliveries.activeDeliveries(for: shift)
        } catch {
            AppLog.delivery.error("Park pickup automation could not read the deliveries in progress")
            return .notRecorded(deliveryNumber: nil)
        }

        switch ParkPickupSelection.select(among: active, state: \.state) {
        case let .none(awaitingArrival):
            AppLog.delivery.info("Park pickup automation found no delivery at a pickup")
            return .noneAtPickup(awaitingArrival: awaitingArrival)

        case let .several(count):
            // A count is structural. Which deliveries, never.
            AppLog.delivery.notice(
                "Park pickup automation skipped: \(count, privacy: .public) deliveries at a pickup"
            )
            return .severalAtPickup(count: count)

        case let .one(delivery):
            let number = shift.numberedDeliveries.first { $0.id == delivery.id }?.number
            do {
                try deliveries.markPickedUp(delivery, at: date, recordedBy: .parkAutomation)
            } catch {
                // The service has already rolled back its own pending
                // timestamp. The suspension was saved before this was tried, so
                // the vehicle stays parked.
                AppLog.delivery.notice("Park pickup automation not applied; the vehicle stays parked")
                return .notRecorded(deliveryNumber: number)
            }
            AppLog.delivery.info("Park pickup automation applied")
            return .recorded(deliveryNumber: number)
        }
    }
}
