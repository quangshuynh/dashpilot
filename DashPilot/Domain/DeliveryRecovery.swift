import Foundation

/// Why a delivery cannot be returned to the state it was in before it was
/// recorded as delivered.
///
/// Each case is a refusal rather than a problem to repair. Recovery removes one
/// timestamp and derives everything else from the ones that stay, so a store
/// whose remaining timestamps do not describe a state the lifecycle can produce
/// leaves nothing truthful to restore. Guessing between two readings of an
/// anomalous row would write a lifecycle the driver never recorded, which is
/// worse than leaving the row exactly as it is and saying so.
nonisolated enum DeliveryRecoveryRefusal: Error, CaseIterable, Equatable, Sendable {
    /// The delivery records no `deliveredAt`, so there is no accidental
    /// completion to take back.
    ///
    /// This is what a second invocation of a recovery that already succeeded
    /// meets. It writes nothing, which is what makes a double tap safe.
    case notDelivered

    /// The delivery is terminal by **cancellation**.
    ///
    /// Out of scope for this version, and refused rather than treated as the
    /// same correction. A cancellation is a different statement from a
    /// completion: it is available from every active state, so the state it
    /// would be taken back to is not the one a completion implies, and a
    /// delivery can be cancelled before it was ever picked up. Reopening one
    /// needs its own decisions about what the cancellation meant, and borrowing
    /// these would be assuming they transfer.
    case cancelled

    /// The delivery records being picked up with no arrival at the pickup
    /// before it.
    ///
    /// A row the lifecycle cannot produce: ``Delivery/markPickedUp(at:)``
    /// refuses a pickup with no arrival recorded. Restoring it would leave a
    /// delivery in a state no sequence of taps can reach, which is exactly what
    /// recovery must not create.
    case pickedUpWithoutArrival

    /// Two of the delivery's recorded timestamps run backwards.
    ///
    /// Contradictory rather than merely untidy, and the contradiction does not
    /// say which of the two events is the wrong one. Removing the delivered
    /// timestamp would silently bless one reading of a row the driver can still
    /// see in full, so nothing is removed.
    case timestampsOutOfOrder
}

/// The lifecycle timestamps one delivery recorded, read as plain values.
///
/// It exists so the rule below can be decided and tested without a store, in the
/// shape ``DeliveryActiveInterval`` already uses: the model owns the column, this
/// owns the reading, and the adapter between them is one initializer that holds
/// no rule of its own.
nonisolated struct DeliveryLifecycleRecord: Equatable, Sendable {
    let acceptedAt: Date
    let arrivedAtPickupAt: Date?
    let pickedUpAt: Date?
    let deliveredAt: Date?
    let cancelledAt: Date?

    init(
        acceptedAt: Date,
        arrivedAtPickupAt: Date? = nil,
        pickedUpAt: Date? = nil,
        deliveredAt: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        self.acceptedAt = acceptedAt
        self.arrivedAtPickupAt = arrivedAtPickupAt
        self.pickedUpAt = pickedUpAt
        self.deliveredAt = deliveredAt
        self.cancelledAt = cancelledAt
    }

    /// Whether the timestamps this row does record run in lifecycle order.
    ///
    /// The one definition of "these times contradict each other", asked by every
    /// correction that reads a recorded delivery rather than restated by each
    /// of them. A missing timestamp is skipped rather than treated as a break:
    /// a delivery cancelled before the driver reached the pickup records no
    /// arrival, and that is an ordinary row rather than a contradictory one.
    ///
    /// Nothing here repairs anything. A row that fails this is refused by its
    /// caller and left exactly as the store holds it, because two times running
    /// backwards do not say which of the two events is the wrong one.
    var isChronological: Bool {
        let recorded = [acceptedAt, arrivedAtPickupAt, pickedUpAt, deliveredAt, cancelledAt].compactMap { $0 }
        return zip(recorded, recorded.dropFirst()).allSatisfy { $0 <= $1 }
    }

    /// Whether the row records being picked up with no arrival at the pickup
    /// before it.
    ///
    /// A shape the lifecycle cannot produce: ``Delivery/markPickedUp(at:)``
    /// refuses a pickup with no arrival recorded. It is asked on its own rather
    /// than folded into ``isChronological`` because it is a **missing** event
    /// rather than a backwards one, and the two deserve different sentences.
    var recordsPickupWithoutArrival: Bool { pickedUpAt != nil && arrivedAtPickupAt == nil }
}

/// What taking back an accidental `Delivered` leaves behind.
///
/// ## The one correction this expresses
///
/// A driver tapped `Delivered` on the wrong card, or a moment too early. The
/// delivery is not delivered yet, and the store says it is. Recovery removes
/// **the delivered timestamp and nothing else**, and the delivery goes back to
/// whatever state its remaining timestamps already describe.
///
/// ## Nothing is chosen, and nothing is invented
///
/// There is no destination to pick, because the timestamps that stay are the
/// answer. A delivery that recorded a pickup goes back to heading to the
/// customer; one that recorded only an arrival goes back to waiting at the
/// pickup; one that recorded neither goes back to heading to the pickup. No
/// timestamp is written, moved or fabricated by any of it, and a driver is never
/// asked to type a time they do not have. That is the whole rule, and it is why
/// this is a recovery rather than a lifecycle editor.
///
/// The last two cases are unreachable through the app, which refuses a
/// completion before a pickup. They are derived rather than refused because they
/// are states the lifecycle genuinely supports and can produce by ordinary
/// means, so a store holding one is restored to something a driver could have
/// been looking at rather than left terminal by an accident of how it got there.
///
/// ## What it refuses
///
/// Everything else, through ``DeliveryRecoveryRefusal``: a delivery that is not
/// delivered, one that is terminal by cancellation, and any remaining chain that
/// does not describe a state the lifecycle can produce. The test is applied to
/// what would be **left behind**, not to how the delivered timestamp came to be
/// there, which is why a completion recorded straight from an arrival can be
/// taken back while a pickup with no arrival before it cannot.
nonisolated struct DeliveryRecovery: Equatable, Sendable {
    /// The state the delivery is in once its delivered timestamp is removed.
    ///
    /// Always one of the three active states. A recovery that would leave a
    /// delivery terminal is a refusal instead.
    let restoredState: DeliveryState

    /// Derives what reopening this record would leave, or refuses it.
    ///
    /// - Throws: ``DeliveryRecoveryRefusal``.
    init(reopening record: DeliveryLifecycleRecord) throws {
        guard record.cancelledAt == nil else { throw DeliveryRecoveryRefusal.cancelled }
        guard record.deliveredAt != nil else { throw DeliveryRecoveryRefusal.notDelivered }
        guard !record.recordsPickupWithoutArrival else { throw DeliveryRecoveryRefusal.pickedUpWithoutArrival }
        guard record.isChronological else { throw DeliveryRecoveryRefusal.timestampsOutOfOrder }

        if record.pickedUpAt != nil {
            restoredState = .pickedUp
        } else if record.arrivedAtPickupAt != nil {
            restoredState = .arrivedAtPickup
        } else {
            restoredState = .accepted
        }
    }
}

/// What reopening one delivery will do, in the words the driver is asked to
/// confirm.
///
/// It lives beside the rule rather than in a view body for the reason
/// ``OfferCorrectionPlan`` does: the sentence a driver reads before agreeing to
/// a correction is the part of it that must be tested, and two screens must not
/// describe the same operation differently.
///
/// Every one of them says the **subject by name**, that the delivery becomes
/// **active again** and which state it goes back to, that only the delivered
/// time is removed, and, where there is one, that the money already recorded
/// against it stays. Local display names only: no identifier, no timestamp and
/// no amount appears in any of it.
nonisolated struct DeliveryRecoveryPrompt: Equatable {
    /// The question, naming the delivery.
    let title: String

    /// What will happen, in the order it happens.
    let detail: String

    /// The confirming button, which repeats the delivery rather than saying
    /// "OK": a button labelled only `Reopen` asks the driver to remember which
    /// row they tapped.
    let confirmTitle: String

    /// The promise every recovery makes about the times already recorded.
    static let unchangedStatement =
        "The times you recorded before it are kept, and your other deliveries are not affected."

    /// Taking back a delivered event on one delivery.
    ///
    /// - Parameters:
    ///   - delivery: the delivery being reopened, named as the screen names it.
    ///   - restored: the state it returns to, derived by ``DeliveryRecovery``
    ///     rather than chosen here.
    ///   - keepsRecordedEarnings: whether an amount is already recorded against
    ///     it. Stated only when there is one, because a sentence about money on
    ///     a delivery carrying none invites the driver to look for some.
    static func reopen(
        _ delivery: NumberedDelivery,
        restoredTo restored: DeliveryState,
        keepsRecordedEarnings: Bool
    ) -> Self {
        Self(
            title: "Reopen \(delivery.title)?",
            detail: [
                """
                \(delivery.title) becomes active again, \(restored.statusDescription.lowercased()), \
                and only the delivered time is removed.
                """,
                keepsRecordedEarnings
                    ? "The gross earnings you recorded against it stay recorded."
                    : nil,
                unchangedStatement
            ]
            .compactMap { $0 }
            .joined(separator: " "),
            confirmTitle: "Reopen \(delivery.title)"
        )
    }
}

nonisolated extension DeliveryLifecycleRecord {
    /// The timestamps a recorded delivery holds.
    ///
    /// The adapter between the persisted model and the rule above, holding no
    /// rule of its own, exactly as ``DeliveryActiveInterval/init(_:)`` does.
    init(_ delivery: Delivery) {
        self.init(
            acceptedAt: delivery.acceptedAt,
            arrivedAtPickupAt: delivery.arrivedAtPickupAt,
            pickedUpAt: delivery.pickedUpAt,
            deliveredAt: delivery.deliveredAt,
            cancelledAt: delivery.cancelledAt
        )
    }
}
