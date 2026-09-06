import AppIntents
import Foundation

/// Beginning a delivery by voice.
///
/// Safe to say however many orders are already in the car, because it names no
/// existing delivery: it adds one, exactly as `Start Delivery` on the running
/// shift does.
struct StartDeliveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Delivery"

    static let description = IntentDescription(
        """
        Records that you accepted a delivery on the shift in progress. \
        Deliveries already in progress are not changed.
        """,
        categoryName: "Delivery",
        searchKeywords: ["delivery", "order", "accept", "start"]
    )

    static let openAppWhenRun = false

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().startDelivery().dialog)
    }
}

/// Recording the next step of the delivery in progress.
///
/// One intent rather than one per event, because the driver saying it is
/// looking at the road rather than at a state machine: the delivery has exactly
/// one step available, ``DeliveryState/nextAction`` says which, and the spoken
/// confirmation names the event that was recorded so the driver hears which
/// one it was.
///
/// **It works only while exactly one delivery is in progress.** With two, the
/// sentence identifies no particular order, and DashPilot refuses rather than
/// choosing one — see ``IntentLifecycleError/severalDeliveriesInProgress(count:)``.
struct RecordDeliveryProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Delivery Progress"

    static let description = IntentDescription(
        """
        Records the next step of the delivery in progress: arrived at the pickup, picked up, \
        then delivered. If more than one delivery is in progress, nothing is recorded, \
        because the step could belong to either of them.
        """,
        categoryName: "Delivery",
        searchKeywords: ["delivery", "arrived", "picked up", "delivered", "progress"]
    )

    static let openAppWhenRun = false

    static let authenticationPolicy = IntentAuthenticationPolicy.alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: try IntentLifecycleService.forIntent().recordDeliveryProgress().dialog)
    }
}
