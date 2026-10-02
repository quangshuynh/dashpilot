import Foundation

/// Which delivery an explicit **Delivered** that names no delivery records: the
/// lowest-numbered delivery in progress that is picked up.
///
/// ## Why this is not ``UnambiguousDelivery``
///
/// ``UnambiguousDelivery`` answers "record the next step", which names neither
/// a delivery nor a step. With two orders open the step itself differs between
/// them, so any choice would write an event the driver did not say. That rule is
/// unchanged and still governs every surface that records "the next step".
///
/// A Delivered press names the step. Only a picked-up delivery can take it, so
/// it can never land on an order still to collect, at a pickup, or already
/// finished. What is left to decide is **which picked-up order**, and the
/// answer is the shift's own delivery number, the order Park's stacked pickup
/// selection already uses. Pressing it again records the next one.
///
/// ## What it does not read
///
/// - **Same drop-off.** One press records one delivery, as the driver's own
///   Picked Up and Delivered do on the in-app card. Same drop-off is read only
///   by ``ParkedStopCompletion``, to keep the vehicle parked until every member
///   of the stop is delivered.
/// - **Location.** Nothing here guesses which customer the driver is at.
///
/// Generic over the element, like ``UnambiguousDelivery``: the intent layer
/// resolves a `Delivery` and the Live Activity a `NumberedDelivery`.
nonisolated enum OrderedDeliveryCompletion {
    /// The delivery a Delivered that names none records, or `nil` when no
    /// delivery in `active` is picked up.
    ///
    /// Deterministic whatever order `active` arrives in: delivery numbers are
    /// unique within a shift.
    static func target<Element>(
        among active: [Element],
        number: (Element) -> Int,
        state: (Element) -> DeliveryState
    ) -> Element? {
        active
            .filter { state($0).nextAction == .complete }
            .min { number($0) < number($1) }
    }
}
