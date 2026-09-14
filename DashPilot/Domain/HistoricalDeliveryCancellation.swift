import Foundation

/// Why a delivery recorded in a finished shift cannot have its completion
/// corrected to a cancellation.
///
/// Each case is a refusal rather than a problem to repair, for the reason
/// ``DeliveryRecoveryRefusal``'s are: the correction rewrites which terminal
/// event a delivery recorded, and a row whose remaining timestamps contradict
/// each other does not say which of its events is the wrong one. Guessing would
/// write a lifecycle the driver never recorded over one they can still see in
/// full.
nonisolated enum HistoricalCancellationRefusal: Error, CaseIterable, Equatable, Sendable {
    /// The delivery records no `deliveredAt`, so there is no completion to
    /// correct.
    ///
    /// Covers a delivery that is still being worked as well as one that never
    /// recorded a completion at all. Neither is what this corrects: it acts on
    /// a recorded `Delivered` and on nothing else.
    case notDelivered

    /// The delivery is already terminal by cancellation.
    ///
    /// **This is what a second invocation meets**, and it is what makes a
    /// double tap safe: the first correction succeeded, the row already says
    /// what the driver asked it to say, and nothing is written again. A
    /// delivery cancelled in the ordinary way during the shift meets it too,
    /// and equally has nothing here to correct.
    case alreadyCancelled

    /// The delivery records being picked up with no arrival at the pickup
    /// before it.
    ///
    /// A row the lifecycle cannot produce. It is refused rather than corrected
    /// because a correction is a claim about which of two terminal events
    /// happened, and a row the app could not have written does not support
    /// claims about it. The contradiction is left visible rather than half
    /// tidied.
    case pickedUpWithoutArrival

    /// Two of the delivery's recorded timestamps run backwards.
    ///
    /// Refused for the reason above and with the sharper consequence: the
    /// instant this correction reuses is the recorded completion, and reusing
    /// an instant from a chain that contradicts itself would put a cancellation
    /// before an event that is recorded as preceding it.
    case timestampsOutOfOrder
}

/// Correcting a delivery that a finished shift records as `Delivered`, and that
/// never actually completed, into the cancellation it was.
///
/// ## The one correction this expresses
///
/// A driver ends the shift, reads the history, and finds a delivery recorded as
/// delivered that fell through. The shift is over, so there is nothing left to
/// finish and nothing to reopen: the only truthful repair is to record the
/// terminal event that really happened. The delivery **stays terminal**, and
/// what changes is which ending it records.
///
/// | Before | After |
/// | --- | --- |
/// | Terminal as `delivered` | Terminal as `cancelled` |
/// | `deliveredAt` present | `deliveredAt` absent |
/// | `cancelledAt` absent | `cancelledAt` present, and equal to the former `deliveredAt` |
///
/// Everything earlier stays exactly as recorded: `acceptedAt`,
/// `arrivedAtPickupAt` and `pickedUpAt` are not read as candidates for anything
/// and are never written.
///
/// ## Why the recorded completion becomes the cancellation
///
/// ``cancelledAt`` reuses the delivery's own ``DeliveryLifecycleRecord/deliveredAt``,
/// and that is the whole of the timestamp decision. It is the **only recorded
/// instant that represents the driver saying this delivery stopped being
/// active**, which is exactly what a cancellation timestamp means, so reusing
/// it writes no time nobody produced:
///
/// - **Nothing is invented.** A driver is never asked to type a time, exactly as
///   they are never asked to during a reopening. There is no timestamp editor in
///   this app and this does not become one.
/// - **The delivery's active interval does not move.**
///   ``DeliveryActiveInterval`` ends at `deliveredAt ?? cancelledAt`, so the same
///   instant ends the same interval, and the shift's delivery active time,
///   which unions those intervals, is unchanged to the second.
/// - **The shift's chronology stays inside itself.** `.now` would place a
///   cancellation hours after the shift ended, outside the shift it belongs to
///   and outside the period that shift is reported in.
///
/// ## What it refuses
///
/// Everything else, through ``HistoricalCancellationRefusal``. The shift's own
/// rule — that this is a correction to **history**, so the shift must already
/// have ended — is not here: it is a fact about the shift rather than about the
/// delivery's timestamps, and it lives in `DeliveryService` beside the other
/// shift rules.
nonisolated struct HistoricalDeliveryCancellation: Equatable, Sendable {
    /// The instant the corrected delivery will record as its cancellation.
    ///
    /// Always the delivery's own recorded completion. It is carried on the value
    /// rather than re-read by the caller so that the rule has exactly one place
    /// to live and the screen can state the consequence before anything is
    /// written.
    let cancelledAt: Date

    /// Derives what correcting this record would write, or refuses it.
    ///
    /// - Throws: ``HistoricalCancellationRefusal``.
    init(correcting record: DeliveryLifecycleRecord) throws {
        guard record.cancelledAt == nil else { throw HistoricalCancellationRefusal.alreadyCancelled }
        guard let deliveredAt = record.deliveredAt else { throw HistoricalCancellationRefusal.notDelivered }
        guard !record.recordsPickupWithoutArrival else {
            throw HistoricalCancellationRefusal.pickedUpWithoutArrival
        }
        guard record.isChronological else { throw HistoricalCancellationRefusal.timestampsOutOfOrder }

        cancelledAt = deliveredAt
    }
}

/// What correcting one historical completion will do, in the words the driver is
/// asked to confirm.
///
/// It lives beside the rule rather than in a view body for the reason
/// ``DeliveryRecoveryPrompt`` does: the sentence a driver reads before agreeing
/// to a correction is the part of it that must be tested.
///
/// Every sentence says the **subject by name**, that the delivery stays
/// finished, that its recorded `Delivered` becomes `Cancelled`, that the time
/// already recorded is reused rather than replaced, and, where there is one,
/// that the money recorded against it stays. **Nothing here says `Edit`**, and
/// no timestamp, identifier or amount appears in any of it: local display names
/// only.
nonisolated struct HistoricalCancellationPrompt: Equatable {
    /// The question, naming the delivery.
    let title: String

    /// What will happen, in the order it happens.
    let detail: String

    /// The confirming button, which repeats the delivery rather than saying
    /// "OK": a button labelled only `Correct` asks the driver to remember which
    /// row they tapped.
    let confirmTitle: String

    /// The promise every correction of this kind makes about the rest of the
    /// record.
    static let unchangedStatement =
        "The pickup place and the times you recorded before it stay as they are, and your other deliveries are not affected."

    /// Correcting one delivery a finished shift records as delivered.
    ///
    /// - Parameters:
    ///   - delivery: the delivery being corrected, named as the screen names it.
    ///   - keepsRecordedEarnings: whether an amount is already recorded against
    ///     it. Stated only when there is one, because a sentence about money on
    ///     a delivery carrying none invites the driver to look for some.
    static func correct(_ delivery: NumberedDelivery, keepsRecordedEarnings: Bool) -> Self {
        Self(
            title: "Correct \(delivery.title) to Cancelled?",
            detail: [
                """
                \(delivery.title) stays a finished delivery. It will be recorded as cancelled \
                instead of delivered, and the time you recorded it as delivered becomes the time it \
                was cancelled, so nothing about this shift's times moves.
                """,
                keepsRecordedEarnings
                    ? "The gross earnings you recorded against it stay recorded."
                    : nil,
                unchangedStatement
            ]
            .compactMap { $0 }
            .joined(separator: " "),
            confirmTitle: "Correct \(delivery.title)"
        )
    }
}
