import Foundation

/// One recorded wait at a pickup: the stretch between arriving somewhere and
/// leaving it with the order.
///
/// ## What it measures
///
/// `pickedUpAt - arrivedAtPickupAt`, and nothing else. Both ends are lifecycle
/// events the driver tapped, so a sample is a record of something they marked
/// rather than an inference about where they were. Acceptance and delivery are
/// not consulted, and neither are route samples: standing still near a pickup is
/// not the same as waiting for an order, and DashPilot has no way to tell the
/// two apart.
///
/// ## When one exists
///
/// A delivery yields a sample only when it recorded **both** ends and they are
/// in order. That rule does the work of several special cases at once:
///
/// - A delivery still on its way to the pickup has no `pickedUpAt`, so it
///   contributes nothing rather than a wait that is still running.
/// - A delivery **cancelled before pickup** is missing the same end, so the time
///   between arriving and giving up is never counted as a wait. It may well have
///   been one, but the app was not told the order was ever collected, and a
///   cancellation is not a pickup.
/// - A delivery **cancelled after pickup** has both ends and does contribute.
///   Whatever went wrong afterwards, the wait at the pickup happened and was
///   recorded.
///
/// ## Order
///
/// A pickup recorded before the arrival it followed describes a store DashPilot
/// cannot have written — every transition checks the timestamp it is given
/// against the last event. Such a sample is **excluded** rather than clamped to
/// zero: a zero standing in for an impossible interval is a fabricated
/// observation, and this value exists to be counted.
nonisolated struct PickupWaitSample: Equatable, Sendable {
    /// How long the wait lasted, in seconds. Never negative.
    let duration: TimeInterval

    /// When the wait ended. Kept so history can be shown newest first and can
    /// say when it was last observed — never to order the median, which does not
    /// depend on time.
    let pickedUpAt: Date

    init(duration: TimeInterval, pickedUpAt: Date) {
        self.duration = duration
        self.pickedUpAt = pickedUpAt
    }
}

nonisolated extension PickupWaitSample {
    /// The wait a delivery recorded, or `nil` when its lifecycle does not
    /// describe one.
    ///
    /// The only place a delivery is turned into a sample. Views and services ask
    /// for this rather than subtracting timestamps themselves.
    init?(_ delivery: Delivery) {
        guard let duration = delivery.pickupWait, let pickedUpAt = delivery.pickedUpAt else { return nil }
        self.init(duration: duration, pickedUpAt: pickedUpAt)
    }

    /// Newest last, then by length, so a list of samples has one order whatever
    /// the store handed back.
    static func recordedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.pickedUpAt != rhs.pickedUpAt { return lhs.pickedUpAt < rhs.pickedUpAt }
        return lhs.duration < rhs.duration
    }
}
