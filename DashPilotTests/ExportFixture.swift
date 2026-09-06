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
        earnings: String? = nil
    ) throws -> Delivery {
        let start = shift.startedAt
        let delivery = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(accepted))
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
        earnings: String? = nil
    ) throws -> Delivery {
        let start = shift.startedAt
        let delivery = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(accepted))
        try delivery.markArrivedAtPickup(at: start.addingTimeInterval(accepted + 180))
        try delivery.cancel(at: start.addingTimeInterval(accepted + 900))
        delivery.setPickupPlace(place)
        if let earnings { try delivery.setGrossEarnings(try money(earnings)) }
        context.insert(delivery)
        return delivery
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
