import AppIntents
import Foundation

/// Why an action asked for from a system surface was not recorded.
///
/// Two of these are refusals that only exist outside the app. The rest are the
/// service layer's own refusals, carried through unchanged so that a driver
/// hears the same sentence Siri that they would read on screen: there is one
/// definition of why a shift cannot start twice, and it is not repeated here.
nonisolated enum IntentLifecycleError: Error {
    /// A shift transition the service refused.
    case shift(ShiftLifecycleError)
    /// A delivery transition the service refused.
    case delivery(DeliveryLifecycleError)
    /// A delivery event was asked for with nothing running to record it against.
    case noDeliveryInProgress
    /// A delivery event was asked for while several deliveries were running.
    ///
    /// **This is the interval's central refusal.** With two orders in the car,
    /// "record the next step" names no particular record, and every way of
    /// choosing one (the newest, the oldest, the one furthest along) would
    /// write a driver's spoken sentence into a delivery they did not mean.
    /// Nothing is recorded and the driver is told which screen can say it
    /// unambiguously.
    case severalDeliveriesInProgress(count: Int)
    /// The local store could not be opened at all, so no service could run.
    case storeUnavailable
}

nonisolated extension IntentLifecycleError: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.shift(lhsError), .shift(rhsError)): lhsError == rhsError
        case let (.delivery(lhsError), .delivery(rhsError)): lhsError == rhsError
        case (.noDeliveryInProgress, .noDeliveryInProgress): true
        case let (.severalDeliveriesInProgress(lhsCount), .severalDeliveriesInProgress(rhsCount)):
            lhsCount == rhsCount
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension IntentLifecycleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .shift(error):
            error.errorDescription
        case let .delivery(error):
            error.errorDescription
        case .noDeliveryInProgress:
            "No delivery is in progress. Start one before recording its next step."
        case let .severalDeliveriesInProgress(count):
            // The count is named, because "several" leaves the driver guessing
            // what DashPilot thinks it is holding.
            """
            \(count) deliveries are in progress, so DashPilot cannot tell which one you mean. \
            Open DashPilot and record the step on that delivery.
            """
        case .storeUnavailable:
            "DashPilot could not open its local data store, so nothing was recorded."
        }
    }
}

/// How the refusal reaches a system surface.
///
/// App Intents shows the error a `perform()` throws when it can describe
/// itself, which is what puts the service layer's own sentences in front of a
/// driver who is not looking at the app.
nonisolated extension IntentLifecycleError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "DashPilot did not record that.")
    }
}
