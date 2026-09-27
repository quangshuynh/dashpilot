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

    /// How the pickup that ends this wait was recorded, or `nil` when the store
    /// does not know (a pickup recorded before DashPilot kept this).
    ///
    /// It never changes ``duration``: a wait closed by Park or by Resume
    /// Driving is exactly as long as its two recorded instants say. It decides only whether the wait
    /// counts toward a typical wait. See ``countsTowardTypicalWait``.
    let provenance: PickupProvenance?

    /// - Parameter provenance: defaults to unknown, which is what a sample
    ///   built from bare numbers is.
    init(duration: TimeInterval, pickedUpAt: Date, provenance: PickupProvenance? = nil) {
        self.duration = duration
        self.pickedUpAt = pickedUpAt
        self.provenance = provenance
    }

    /// Whether this wait enters a median, a spread or a count of recorded waits.
    ///
    /// **The one rule**, read by ``PickupWaitCalculator`` and by every screen
    /// that lists waits beside the figures, so the list and the median are
    /// always drawn from the same waits.
    ///
    /// A wait whose pickup was **recorded automatically** does not count, by
    /// either control:
    ///
    /// - **Resume Driving**, under the Park and Resume workflow, ends the wait
    ///   when the driver drives off, after walking back and however long they
    ///   sat in the car, so it runs from parking to pulling away rather than to
    ///   the handover, and is long by that much.
    /// - **Park**, under the setting that workflow replaced, ended it when the
    ///   driver parked, usually before they walked in, so it is short.
    ///
    /// Measured through this calculator (`PickupWaitResumeMeasurementTests`,
    /// `PickupWaitProvenanceMeasurementTests`), a few of either move a place's
    /// median by minutes, and the median then follows how often the driver uses
    /// the workflow rather than the place. Neither is discarded: each is counted
    /// separately, and every figure it is left out of says how many were left
    /// out.
    ///
    /// A wait whose provenance is **unknown** counts, as it did before the app
    /// recorded provenance. Nothing can say what it was, and treating every
    /// pickup recorded before v18 as suspect would empty the history of every
    /// place for the sake of the few pickups a short-lived earlier build may
    /// have recorded by parking.
    var countsTowardTypicalWait: Bool { !(provenance?.isAutomated ?? false) }
}

nonisolated extension PickupWaitSample {
    /// The wait a delivery recorded, or `nil` when its lifecycle does not
    /// describe one.
    ///
    /// The only place a delivery is turned into a sample. Views and services ask
    /// for this rather than subtracting timestamps themselves.
    init?(_ delivery: Delivery) {
        guard let duration = delivery.pickupWait, let pickedUpAt = delivery.pickedUpAt else { return nil }
        self.init(duration: duration, pickedUpAt: pickedUpAt, provenance: delivery.pickupProvenance)
    }

    /// Newest last, then by length, so a list of samples has one order whatever
    /// the store handed back.
    static func recordedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.pickedUpAt != rhs.pickedUpAt { return lhs.pickedUpAt < rhs.pickedUpAt }
        return lhs.duration < rhs.duration
    }
}
