import Foundation
import SwiftData

/// Errors raised when a shift transition would violate the model's invariants.
nonisolated enum ShiftError: Error, Equatable {
    /// The shift already has an end timestamp.
    case alreadyEnded
    /// The proposed end timestamp is earlier than the start timestamp.
    case endPrecedesStart
    /// Earnings were recorded against a shift that is still running.
    case shiftNotCompleted
    /// A negative amount was recorded as gross earnings.
    case negativeEarnings
}

/// A single period of delivery work.
///
/// A shift is the unit every later measurement hangs from: route samples,
/// mileage, deliveries and earnings are all scoped to one shift. It is
/// deliberately narrow at this stage — distance is derived from the route
/// rather than stored, and the one earnings figure it holds is the one the
/// driver typed.
///
/// Route samples are the first thing to attach to it. They are collected only
/// while the shift is running; `endedAt` being set is what stops that, and
/// nothing appends to a shift that has ended.
@Model
nonisolated final class Shift {
    /// Stable identifier, used for cross-store references and future export.
    @Attribute(.unique) private(set) var id: UUID

    private(set) var startedAt: Date

    /// `nil` while the shift is still running.
    private(set) var endedAt: Date?

    /// Positions retained while this shift was running, in no guaranteed order.
    ///
    /// The delete rule is `.cascade`: a shift's route describes that shift and
    /// nothing else, so deleting the shift must take the samples with it rather
    /// than leaving a table of coordinates belonging to a shift that no longer
    /// exists. That matters more than usual here — the orphans would be exactly
    /// the sensitive data the app promises to keep accountable to a shift.
    @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
    private(set) var routeSamples: [RouteSample] = []

    /// Deliveries recorded during this shift, in no guaranteed order.
    ///
    /// The delete rule is `.cascade`, for the same reason the route's is: a
    /// delivery is a record of work done *within* one shift and means nothing
    /// apart from it, so deleting the shift must take its deliveries rather
    /// than leaving a table of timestamps belonging to a shift that no longer
    /// exists. Orphaned deliveries would also be exactly the sensitive
    /// work-history rows the app promises to keep accountable to a shift.
    @Relationship(deleteRule: .cascade, inverse: \Delivery.shift)
    private(set) var deliveries: [Delivery] = []

    /// Gross earnings for this shift, exactly as entered, or `nil` if none were.
    ///
    /// Stored as a `Decimal` rather than as a ``Money``: SwiftData persists a
    /// `Decimal` as a decimal attribute, so the exact amount survives a round
    /// trip with no binary floating point anywhere in the store and no second
    /// monetary type in the app. The conversion is centralised in
    /// ``grossEarnings`` and ``setGrossEarnings(_:)``; nothing else reads this
    /// property, so the rest of the app only ever handles a `Money`.
    ///
    /// **`nil` and zero are different facts.** `nil` means the driver has not
    /// recorded what this shift paid; `0` means they recorded that it paid
    /// nothing. Migration never fabricates the second from the first.
    private var grossEarningsAmount: Decimal?

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
    }

    var isActive: Bool { endedAt == nil }

    /// Duration of a finished shift, or `nil` while it is still running.
    var completedDuration: TimeInterval? {
        endedAt.map { clampedInterval(from: startedAt, to: $0) }
    }

    /// Time covered by the shift so far, measured against `referenceDate` while running.
    func elapsed(asOf referenceDate: Date) -> TimeInterval {
        clampedInterval(from: startedAt, to: endedAt ?? referenceDate)
    }

    /// Marks the shift finished.
    ///
    /// - Throws: ``ShiftError/alreadyEnded`` if the shift is not running, or
    ///   ``ShiftError/endPrecedesStart`` if `date` is before the start.
    func end(at date: Date) throws {
        guard endedAt == nil else { throw ShiftError.alreadyEnded }
        guard date >= startedAt else { throw ShiftError.endPrecedesStart }
        endedAt = date
    }

    /// The device clock can move backwards (manual changes, NTP corrections),
    /// so a negative interval is treated as zero rather than surfaced as a
    /// negative duration in metrics.
    private func clampedInterval(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

extension Shift {
    /// Distance recorded for this shift, measured from its retained route.
    ///
    /// Derived on demand and never stored. A shift's mileage is a *reading* of
    /// its route, not a second fact about the shift that could drift away from
    /// it: caching the total would mean an improvement to the calculation left
    /// every historical shift showing the old number, and a store holding two
    /// answers to the same question. If measuring a long route ever proves too
    /// slow to do on demand, caching is a deliberate change to make then.
    ///
    /// Only this shift's samples are measured. Distance across a gap in capture
    /// is excluded rather than guessed, so the result is what the route can
    /// support and usually less than the miles actually driven — see
    /// ``RouteDistance``.
    func recordedDistance(
        using calculator: RouteMileageCalculator = RouteMileageCalculator()
    ) -> RouteDistance {
        calculator.distance(
            of: routeSamples.map(\.routePoint),
            // A finished shift has a window the route can be checked against. A
            // running one does not: the route is still being recorded, and
            // measuring it against "now" would report a gap for every red light.
            covering: endedAt.map { startedAt...$0 }
        )
    }
}

extension Shift {
    /// Gross earnings recorded for this shift, or `nil` if none were.
    ///
    /// "Gross" is the whole claim. It is the figure the driver chose to
    /// associate with the shift and nothing more: DashPilot does not know
    /// whether it includes tips, bonuses, promotions, adjustments or
    /// reimbursements, and it is not profit, take-home pay or a taxable amount.
    /// Nothing is imported from a delivery platform.
    var grossEarnings: Money? {
        grossEarningsAmount.map(Money.init(amount:))
    }

    /// Records what this shift paid, replacing any amount already recorded.
    ///
    /// Two invariants, kept on the model rather than in a view so that no
    /// screen, test or future caller can set an amount the app would refuse to
    /// display:
    ///
    /// - Only a **completed** shift can carry earnings. A running shift has not
    ///   finished paying, and asking a driver to type an amount mid-shift is
    ///   asking them to type while driving.
    /// - The amount may not be **negative**. Zero is allowed and meaningful — a
    ///   shift really can pay nothing — but a shift that cost money is an
    ///   expense, and expenses are not recorded anywhere yet.
    ///
    /// The amount is stored exactly as given. Rounding is a display decision
    /// (``Money/formatted(currencyCode:locale:)``), and the input layer rejects
    /// anything finer than a cent rather than quietly rounding it here.
    ///
    /// - Throws: ``ShiftError/shiftNotCompleted`` or ``ShiftError/negativeEarnings``.
    func setGrossEarnings(_ earnings: Money) throws {
        guard endedAt != nil else { throw ShiftError.shiftNotCompleted }
        guard !earnings.isNegative else { throw ShiftError.negativeEarnings }
        grossEarningsAmount = earnings.amount
    }

    /// Removes the recorded amount, returning the shift to having no earnings.
    ///
    /// Deliberately distinct from recording `0`. A driver who deletes an amount
    /// they entered by mistake is saying "I have not recorded this", not "this
    /// shift paid nothing", and the two must not collapse into one state.
    ///
    /// It does not throw: a shift with no earnings to remove is already in the
    /// state the caller asked for.
    func clearGrossEarnings() {
        grossEarningsAmount = nil
    }
}

extension Shift {
    /// The deliveries still in progress in this shift, in accepted order.
    ///
    /// A list rather than a single delivery, because a driver can be working
    /// several orders at once. Each one owns its own state; there is no
    /// aggregate "the delivery in progress" to read, and nothing here decides
    /// which of them is the important one.
    ///
    /// Read from the store's own rows rather than from a flag: a shift's
    /// deliveries are the authority on what is running, and the rule that a
    /// shift cannot end while any of them are depends on that being true after
    /// a relaunch as much as during a session.
    var activeDeliveries: [Delivery] {
        deliveriesInOrder.filter(\.isActive)
    }

    /// This shift's deliveries in the order they were accepted.
    ///
    /// With stacked deliveries this is an ordering, not a sequence of events:
    /// two deliveries can overlap completely, and the second one accepted may
    /// well be the first one delivered.
    var deliveriesInOrder: [Delivery] {
        deliveries.sorted(by: Delivery.acceptedBefore)
    }

    /// This shift's deliveries with the numbers the interface labels them with.
    ///
    /// Numbering runs over *every* delivery in the shift rather than only the
    /// active ones, so a delivery keeps the same label from the moment it starts
    /// until it appears in the shift's history — finishing one does not renumber
    /// the others on screen.
    var numberedDeliveries: [NumberedDelivery] {
        NumberedDelivery.numbering(deliveries)
    }

    /// The active deliveries, carrying the same numbers they have everywhere
    /// else in this shift.
    var numberedActiveDeliveries: [NumberedDelivery] {
        numberedDeliveries.filter(\.delivery.isActive)
    }

    /// How many deliveries this shift recorded, and how they ended.
    var deliverySummary: DeliverySummary {
        DeliverySummary(states: deliveries.map(\.state))
    }
}
