import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Synthetic shifts for the export suites.
///
/// Every amount, offset, coordinate and place name here is invented. The origin
/// is the same round number `SyntheticRoute` uses — chosen for arithmetic, not a
/// place anyone has driven — and it exists in these tests only so the privacy
/// suite can prove the coordinates are *absent* from what is written out.
@MainActor
struct ExportFixture {
    let container: ModelContainer
    let context: ModelContext

    /// Wednesday, 17 June 2026, midnight UTC. Fixed, so every assertion about a
    /// timestamp is an assertion about a literal.
    static let start = Date(timeIntervalSince1970: 1_781_654_400)

    /// A calendar pinned to UTC, so a file name's date is the date the test
    /// wrote rather than the one the machine happens to be in.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }()

    init() throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = ModelContext(container)
    }

    func at(_ hours: Double) -> Date { Self.start.addingTimeInterval(hours * 3600) }

    func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    // MARK: Shifts

    /// A completed shift, inserted and returned.
    @discardableResult
    func completedShift(
        startedAfter hours: Double = 9,
        lasting duration: Double = 3,
        earnings: String? = nil
    ) throws -> Shift {
        let shift = Shift(startedAt: at(hours))
        try shift.end(at: at(hours + duration))
        if let earnings { try shift.setGrossEarnings(try money(earnings)) }
        context.insert(shift)
        return shift
    }

    /// A shift that is still running. Never exportable.
    @discardableResult
    func runningShift(startedAfter hours: Double = 9) -> Shift {
        let shift = Shift(startedAt: at(hours))
        context.insert(shift)
        return shift
    }

    // MARK: Routes

    /// A route in `sessions` unbroken stretches, each 11 legs of 400 m.
    ///
    /// Two sessions leave a gap between them, which is what a partial route is.
    /// One session leaves none detected.
    func attachRoute(to shift: Shift, sessions: Int = 1) {
        let start = shift.startedAt
        for session in 0..<sessions {
            let id = UUID()
            let sessionStart = Double(session) * 1800
            for step in 0..<12 {
                let point = SyntheticRoute.point(
                    at: start.addingTimeInterval(sessionStart + Double(step) * 20),
                    northMetres: Double(session) * 9_000 + Double(step) * 400,
                    captureSessionID: id
                )
                context.insert(
                    RouteSample(
                        shift: shift,
                        timestamp: point.timestamp,
                        latitude: point.latitude,
                        longitude: point.longitude,
                        horizontalAccuracy: 8,
                        captureSessionID: id
                    )
                )
            }
        }
    }

    /// Positions that cannot be measured: each one in a session of its own, so
    /// no two are continuous.
    func attachUnmeasurableRoute(to shift: Shift, samples: Int = 3) {
        for step in 0..<samples {
            let point = SyntheticRoute.point(
                at: shift.startedAt.addingTimeInterval(Double(step) * 600),
                northMetres: Double(step) * 400,
                captureSessionID: UUID()
            )
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: point.timestamp,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    horizontalAccuracy: 8,
                    captureSessionID: UUID()
                )
            )
        }
    }

    // MARK: Deliveries

    /// A delivered delivery, with an optional recorded wait, place and amount.
    ///
    /// Offsets are seconds from the shift's start.
    @discardableResult
    func delivered(
        in shift: Shift,
        acceptedAfter accepted: TimeInterval,
        waitSeconds: TimeInterval? = 600,
        deliveredAfterPickup: TimeInterval = 900,
        place: PickupPlace? = nil,
        earnings: String? = nil,
        expected: String? = nil
    ) throws -> Delivery {
        let start = shift.startedAt
        let delivery = inOwnOffer(in: shift, acceptedAt: start.addingTimeInterval(accepted))
        // Before the lifecycle runs, because the model refuses an expectation on
        // a delivery that has finished. That refusal is the rule, not a detail
        // of this helper.
        if let expected { try delivery.setExpectedEarnings(try money(expected)) }
        if let waitSeconds {
            try delivery.markArrivedAtPickup(at: start.addingTimeInterval(accepted + 180))
            try delivery.markPickedUp(at: start.addingTimeInterval(accepted + 180 + waitSeconds))
            try delivery.markDelivered(
                at: start.addingTimeInterval(accepted + 180 + waitSeconds + deliveredAfterPickup)
            )
        } else {
            try delivery.markArrivedAtPickup(at: start.addingTimeInterval(accepted + 180))
            try delivery.markPickedUp(at: start.addingTimeInterval(accepted + 360))
            try delivery.markDelivered(at: start.addingTimeInterval(accepted + 360 + deliveredAfterPickup))
        }
        delivery.setPickupPlace(place)
        if let earnings { try delivery.setGrossEarnings(try money(earnings)) }
        context.insert(delivery)
        return delivery
    }

    /// A delivery cancelled after arriving and before any pickup, so it records
    /// no wait.
    @discardableResult
    func cancelled(
        in shift: Shift,
        acceptedAfter accepted: TimeInterval,
        place: PickupPlace? = nil,
        earnings: String? = nil,
        expected: String? = nil
    ) throws -> Delivery {
        let start = shift.startedAt
        let delivery = inOwnOffer(in: shift, acceptedAt: start.addingTimeInterval(accepted))
        if let expected { try delivery.setExpectedEarnings(try money(expected)) }
        try delivery.markArrivedAtPickup(at: start.addingTimeInterval(accepted + 180))
        try delivery.cancel(at: start.addingTimeInterval(accepted + 900))
        delivery.setPickupPlace(place)
        if let earnings { try delivery.setGrossEarnings(try money(earnings)) }
        context.insert(delivery)
        return delivery
    }

    /// A delivery in a one-delivery offer of its own, which is what one tap
    /// records.
    ///
    /// Built directly rather than through ``Shift/beginOffer(deliveryCount:at:)``
    /// because the shifts here are **already finished** when their deliveries
    /// are attached: this fixture assembles the stored state of a shift that
    /// happened, rather than replaying one as it runs, which is why the helpers
    /// above construct a `Delivery` directly too. The one thing that matters is
    /// kept: an offer and its delivery are made together, sharing the shift and
    /// the instant, so no fixture here holds a delivery outside an offer.
    ///
    /// The offer is inserted here; the delivery is returned for the caller to
    /// insert, which is the shape the helpers above already have.
    private func inOwnOffer(in shift: Shift, acceptedAt: Date) -> Delivery {
        let offer = Offer(shift: shift, acceptedAt: acceptedAt)
        context.insert(offer)
        return Delivery(shift: shift, offer: offer, acceptedAt: acceptedAt)
    }

    /// One accepted offer holding several deliveries, every one of them
    /// delivered.
    ///
    /// The deliveries share the offer's acceptance instant, because they were
    /// accepted in one act, and are returned in the order the shift numbers
    /// them. They are given **different** pickup and delivery times, so a test
    /// can tell them apart by more than their identity.
    @discardableResult
    func deliveredOffer(
        in shift: Shift,
        deliveryCount: Int,
        acceptedAfter accepted: TimeInterval,
        earnings: [String?] = []
    ) throws -> Offer {
        let start = shift.startedAt
        let acceptedAt = start.addingTimeInterval(accepted)
        let offer = Offer(shift: shift, acceptedAt: acceptedAt)
        context.insert(offer)
        let recorded = (0..<deliveryCount).map { _ in
            Delivery(shift: shift, offer: offer, acceptedAt: acceptedAt)
        }

        for (index, delivery) in recorded.sorted(by: Delivery.acceptedBefore).enumerated() {
            let step = Double(index) * 300
            try delivery.markArrivedAtPickup(at: start.addingTimeInterval(accepted + 180 + step))
            try delivery.markPickedUp(at: start.addingTimeInterval(accepted + 780 + step))
            try delivery.markDelivered(at: start.addingTimeInterval(accepted + 1_680 + step))
            if index < earnings.count, let amount = earnings[index] {
                try delivery.setGrossEarnings(try money(amount))
            }
            context.insert(delivery)
        }
        return offer
    }

    // MARK: Expenses

    /// A recorded expense, inserted and returned.
    ///
    /// Dated rather than attached: nothing here takes a shift, because an
    /// expense does not belong to one.
    @discardableResult
    func expense(
        _ amount: String,
        category: ExpenseCategory = .fuel,
        hoursAfterStart hours: Double,
        note: String = ""
    ) throws -> Expense {
        let expense = try Expense(
            occurredAt: at(hours),
            amount: try money(amount),
            category: category,
            noteText: note
        )
        context.insert(expense)
        return expense
    }

    // MARK: Additional tips

    /// One tip on a delivery, recorded `seconds` after its shift began.
    ///
    /// The instant is supplied rather than taken from the clock, so every
    /// assertion about an exported timestamp is an assertion about a literal.
    @discardableResult
    func tip(
        _ amount: String,
        _ method: DeliveryTipMethod,
        on delivery: Delivery,
        recordedAfter seconds: TimeInterval
    ) throws -> DeliveryTip {
        let shiftStart = try #require(delivery.shift?.startedAt)
        let tip = try delivery.recordAdditionalTip(
            try money(amount),
            method: method,
            at: shiftStart.addingTimeInterval(seconds)
        )
        context.insert(tip)
        return tip
    }

    // MARK: Pickup places

    @discardableResult
    func place(named name: String) throws -> PickupPlace {
        let place = PickupPlace(name: try PickupPlaceName(name), createdAt: Self.start)
        context.insert(place)
        return place
    }

    // MARK: Reading it back

    /// The export record for one shift, with its route measured the way the app
    /// measures it.
    func exportRecord(of shift: Shift) throws -> ShiftExportRecord {
        try shift.exportRecord(for: shift.recordedDistance())
    }
}
