#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Synthetic data and services for SwiftUI previews. Never contains real driver
/// history, and never a real coordinate.
enum PreviewSupport {
    static func emptyContainer() -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! ModelContainerFactory.makeInMemoryContainer()
    }

    static func populatedContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000),
        includingActiveShift: Bool = true
    ) -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! seededHistoryContainer(referenceDate: referenceDate, includingActiveShift: includingActiveShift)
    }

    /// The same synthetic history, built through a throwing call so a UI test
    /// launch can report a store failure rather than trapping inside it.
    static func seededHistoryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000),
        includingActiveShift: Bool = true
    ) throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let completed = Shift(startedAt: referenceDate.addingTimeInterval(-4 * 3600))
        try? completed.end(at: referenceDate.addingTimeInterval(-3600))

        let earlier = Shift(startedAt: referenceDate.addingTimeInterval(-30 * 3600))
        try? earlier.end(at: referenceDate.addingTimeInterval(-25 * 3600))

        // One shift with an amount recorded and one without, so both the
        // recorded figure and the "Add Earnings" affordance are visible. The
        // amount is invented for the preview, like every other value here.
        try? completed.setGrossEarnings(Money(minorUnits: 8625))

        var shifts = [completed, earlier]
        if includingActiveShift {
            shifts.append(Shift(startedAt: referenceDate.addingTimeInterval(-1800)))
        }

        for shift in shifts {
            context.insert(shift)
        }

        // The most recent completed shift gets a short synthetic route in two
        // capture sessions, so the history row shows a measured, partial
        // distance. The older one keeps no route, so the "nothing to measure"
        // wording is visible too.
        for sample in syntheticRoute(from: completed.startedAt) {
            context.insert(sample.attached(to: completed))
        }

        // Two completed deliveries and one cancelled, so the detail screen shows
        // a delivered lifecycle, a cancelled one, both derived intervals, and a
        // pair whose lifecycles overlap. Every timestamp is an invented offset
        // from the fixture's start.
        let deliveries = syntheticDeliveries(in: completed, from: completed.startedAt)
        for delivery in deliveries {
            context.insert(delivery)
        }

        // Two of the three name the same pickup place, which is what a reused
        // local place looks like in history.
        attachPickupPlaces(to: deliveries, in: context, at: completed.startedAt)

        // Two of the three carry an invented amount and one carries none, so
        // the three states a delivery can be in — recorded, not recorded, and
        // recorded on a delivery that overlapped another — are all on screen.
        attachDeliveryEarnings(to: deliveries)

        try? context.save()

        return container
    }

    /// A throwaway store holding a running shift with **two** deliveries in
    /// progress at once, at different points in their lifecycles.
    ///
    /// This is the state a relaunch recovers into for a driver working stacked
    /// orders, and the shape that makes the interesting claims assertable
    /// through the interface: two cards, each offering its own next step,
    /// advancing one leaving the other alone, and a shift end refused while
    /// either is unfinished.
    static func activeDeliveryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000)
    ) -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! seededActiveDeliveryContainer(referenceDate: referenceDate)
    }

    /// The same fixture, built through a throwing call so a UI test launch can
    /// report a store failure rather than trapping inside it.
    ///
    /// The three deliveries are numbered by acceptance, so the shift holds
    /// `Delivery 1` delivered, `Delivery 2` accepted and `Delivery 3` picked up.
    /// Every timestamp is an invented offset from the fixture's reference date.
    static func seededActiveDeliveryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000)
    ) throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let shift = Shift(startedAt: referenceDate.addingTimeInterval(-5400))
        context.insert(shift)

        // One delivery already completed in this shift, so the status line has a
        // count to state alongside the two still running.
        let finished = Delivery(shift: shift, acceptedAt: referenceDate.addingTimeInterval(-5000))
        try? finished.markArrivedAtPickup(at: referenceDate.addingTimeInterval(-4700))
        try? finished.markPickedUp(at: referenceDate.addingTimeInterval(-4300))
        try? finished.markDelivered(at: referenceDate.addingTimeInterval(-3800))
        context.insert(finished)

        // Accepted and no further: its next step is arriving at the pickup.
        let accepted = Delivery(shift: shift, acceptedAt: referenceDate.addingTimeInterval(-1500))
        context.insert(accepted)

        // Accepted later but already in the car, which is exactly why the two
        // cards cannot share one control: the later delivery is further along.
        let carrying = Delivery(shift: shift, acceptedAt: referenceDate.addingTimeInterval(-900))
        try? carrying.markArrivedAtPickup(at: referenceDate.addingTimeInterval(-600))
        try? carrying.markPickedUp(at: referenceDate.addingTimeInterval(-240))
        context.insert(carrying)

        // One of the running deliveries already names a place and one does not,
        // so both states of the card's secondary control are on screen at once.
        if let name = try? PickupPlaceName(SyntheticPickupPlace.noodles) {
            let place = PickupPlace(name: name, createdAt: referenceDate.addingTimeInterval(-5000))
            context.insert(place)
            carrying.setPickupPlace(place)
        }

        try? context.save()

        return container
    }

    // MARK: Period summaries

    /// A throwaway store holding a week of synthetic completed shifts, built
    /// around **today** rather than a fixed instant.
    ///
    /// Every other fixture in this file is pinned to one epoch date, which is
    /// what makes them repeatable. A period summary cannot be: the screen shows
    /// the day and week the driver is actually in, so a fixture anchored to 2025
    /// would open on an empty period and prove nothing. The offsets below are
    /// still fixed — only their anchor moves.
    ///
    /// What the fixture is built to show:
    ///
    /// | Shift | When | Amount | Route | Deliveries |
    /// | --- | --- | --- | --- | --- |
    /// | 1 | today, 3 hours | `$86.25` | measured, partial | 3 delivered, 1 cancelled |
    /// | 2 | today, 2 hours | none | none recorded | none |
    /// | 3 | earlier this week, 5 hours | `$120.00` | measured, partial | 2 delivered |
    ///
    /// Both measured routes are partial, and that is not an accident of the
    /// fixture: a short synthetic route inside a multi-hour shift leaves the rest
    /// of the shift unaccounted for, which is exactly what foreground-only
    /// capture does to a real one.
    ///
    /// So the day shows an amount over **1 of 2** shifts and the week over
    /// **2 of 3** — coverage that is visibly incomplete, which is the state the
    /// screen exists to report honestly. The recorded waits are 6, 11 and 41
    /// minutes today and 8 and 20 more across the week, so the median is 11
    /// minutes either way while the sample count changes.
    ///
    /// Three invented expenses sit alongside, dated rather than attached to any
    /// of those shifts:
    ///
    /// | Expense | When | Category |
    /// | --- | --- | --- |
    /// | `$42.10` | today | fuel |
    /// | `$6.50` | today | parking and tolls |
    /// | `$89.99` | earlier this week | maintenance |
    ///
    /// The day therefore records `$48.60` of costs against `$86.25` of gross
    /// earnings — `$37.65` net after recorded expenses — and the week `$138.59`
    /// against `$206.25`, leaving `$67.66`.
    static func periodSummaryContainer(now: Date = .now) -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! seededPeriodSummaryContainer(now: now)
    }

    /// The same fixture, built through a throwing call so a UI test launch can
    /// report a store failure rather than trapping inside it.
    static func seededPeriodSummaryContainer(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let today = calendar.startOfDay(for: now)

        // A day in this week that is not today, so the day and the week views
        // genuinely differ. Which day that is depends on the driver's own first
        // weekday, so it is derived rather than assumed.
        let otherDay = otherDayThisWeek(from: today, now: now, calendar: calendar)

        // Today, three hours, with an amount and a partial route.
        let first = shift(startingAt: today.addingTimeInterval(9 * 3600), hours: 3, in: context)
        try? first.setGrossEarnings(Money(minorUnits: 8625))
        for sample in syntheticRoute(from: first.startedAt) {
            context.insert(sample.attached(to: first))
        }
        seedDeliveries(
            in: first,
            waitsInMinutes: [6, 11, 41],
            cancelling: true,
            placeNames: [SyntheticPickupPlace.noodles, SyntheticPickupPlace.diner],
            context: context
        )

        // Today, two hours, with neither an amount nor a route: the shift that
        // makes every coverage figure on the screen incomplete.
        _ = shift(startingAt: today.addingTimeInterval(14 * 3600), hours: 2, in: context)

        // Earlier this week, five hours, with an amount and a route of its own.
        let third = shift(startingAt: otherDay.addingTimeInterval(10 * 3600), hours: 5, in: context)
        try? third.setGrossEarnings(Money(minorUnits: 12_000))
        for sample in syntheticRoute(from: third.startedAt, sessions: 1) {
            context.insert(sample.attached(to: third))
        }
        // The same two invented places again, so the period counts places rather
        // than deliveries: five deliveries here name two places between them.
        seedDeliveries(
            in: third,
            waitsInMinutes: [8, 20],
            cancelling: false,
            placeNames: [SyntheticPickupPlace.noodles],
            context: context
        )

        // Three invented costs, dated rather than attached to any of the shifts
        // above: two today and one earlier in the week, in three categories.
        //
        // The figures are chosen so the day and the week say different things
        // and neither is a round number that could be mistaken for a
        // placeholder. Today: $42.10 + $6.50 = $48.60 recorded, against $86.25
        // of recorded gross earnings, so the net after recorded expenses is
        // $37.65. The week adds $89.99, so $138.59 against $206.25 leaves
        // $67.66.
        seedExpenses(
            [
                (
                    today.addingTimeInterval(8 * 3600 + 1_800),
                    Money(minorUnits: 4_210),
                    .fuel,
                    "Half tank before the lunch rush"
                ),
                (today.addingTimeInterval(12 * 3600), Money(minorUnits: 650), .parkingAndTolls, ""),
                (otherDay.addingTimeInterval(9 * 3600), Money(minorUnits: 8_999), .maintenance, "Oil change")
            ],
            in: context
        )

        try? context.save()

        return container
    }

    /// Inserts synthetic expenses.
    ///
    /// Every amount, date and note here is invented. An expense carries no shift
    /// and no delivery, which is why this takes none: the fixture dates them and
    /// nothing else relates them to the work above.
    private static func seedExpenses(
        _ expenses: [(Date, Money, ExpenseCategory, String)],
        in context: ModelContext
    ) {
        for (occurredAt, amount, category, note) in expenses {
            guard let expense = try? Expense(
                occurredAt: occurredAt,
                amount: amount,
                category: category,
                noteText: note
            ) else { continue }
            context.insert(expense)
        }
    }

    /// The start of a day in the same week as `today` that is not `today`.
    ///
    /// Falls back to `today` only if the calendar cannot describe the week at
    /// all, which would make the fixture's day and week views identical rather
    /// than wrong.
    private static func otherDayThisWeek(from today: Date, now: Date, calendar: Calendar) -> Date {
        guard let week = ReportingPeriod(unit: .week, containing: now, calendar: calendar) else { return today }
        let weekStart = calendar.startOfDay(for: week.start)
        guard weekStart == today else { return weekStart }
        // Today is the first day of the week, so the second day is the one that
        // is still in this week and is not today.
        return calendar.date(byAdding: .day, value: 1, to: weekStart) ?? today
    }

    /// One completed synthetic shift, inserted and returned.
    private static func shift(startingAt start: Date, hours: Double, in context: ModelContext) -> Shift {
        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(hours * 3600))
        context.insert(shift)
        return shift
    }

    /// Deliveries for a period fixture: one delivered per recorded wait, plus an
    /// optional cancellation that never reached a pickup.
    ///
    /// The cancelled one is what keeps the delivery counts from collapsing into
    /// a single figure on screen, and it deliberately contributes no wait: the
    /// app was never told the order was collected.
    private static func seedDeliveries(
        in shift: Shift,
        waitsInMinutes waits: [Double],
        cancelling: Bool,
        placeNames: [String] = [],
        context: ModelContext
    ) {
        let start = shift.startedAt
        var offset: TimeInterval = 300

        let places = placeNames.compactMap { name -> PickupPlace? in
            guard let name = try? PickupPlaceName(name) else { return nil }
            let place = PickupPlace(name: name, createdAt: start)
            context.insert(place)
            return place
        }

        for (index, wait) in waits.enumerated() {
            let accepted = start.addingTimeInterval(offset)
            let delivery = Delivery(shift: shift, acceptedAt: accepted)
            try? delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(180))
            try? delivery.markPickedUp(at: accepted.addingTimeInterval(180 + wait * 60))
            try? delivery.markDelivered(at: accepted.addingTimeInterval(600 + wait * 60))
            if !places.isEmpty {
                delivery.setPickupPlace(places[index % places.count])
            }
            context.insert(delivery)

            // Two of them carry an invented amount and the rest carry none, so
            // the delivery subtotal on screen is visibly short of its deliveries.
            if index == 0 {
                try? delivery.setGrossEarnings(Money(minorUnits: 1475))
            } else if index == 1 {
                try? delivery.setGrossEarnings(Money(minorUnits: 950))
            }

            offset += 900 + wait * 60
        }

        guard cancelling else { return }
        let accepted = start.addingTimeInterval(offset)
        let cancelled = Delivery(shift: shift, acceptedAt: accepted)
        try? cancelled.markArrivedAtPickup(at: accepted.addingTimeInterval(180))
        try? cancelled.cancel(at: accepted.addingTimeInterval(900))
        context.insert(cancelled)
    }

    // MARK: Pickup wait history

    /// A throwaway store holding one completed shift whose deliveries give two
    /// pickup places deliberately different amounts of history.
    ///
    /// The seeded history fixture cannot serve this: its three deliveries are
    /// pinned by the active-time and rate journeys that assert exact figures
    /// over them, and a place needs several recorded waits — plus one delivery
    /// that recorded none — before the median, the sample count and the
    /// insufficient-history wording are all reachable through the interface.
    ///
    /// Every timestamp is an invented offset. What the fixture is built to show:
    ///
    /// | Place | Deliveries | Recorded waits |
    /// | --- | --- | --- |
    /// | `Nowhere Noodles` | four | 6 min, 11 min, 41 min — median 11 min |
    /// | `Example Diner` | one | 20 min — one sample, not a typical wait |
    ///
    /// The fourth Noodles delivery was cancelled after arriving and before any
    /// pickup, so it contributes nothing; the last delivery names no place at
    /// all, so it offers no history to open. The 41-minute wait is kept rather
    /// than trimmed, which is the whole reason the median is the headline.
    static func pickupHistoryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000)
    ) -> ModelContainer {
        // Previews cannot meaningfully recover from a container failure.
        try! seededPickupHistoryContainer(referenceDate: referenceDate)
    }

    /// The same fixture, built through a throwing call so a UI test launch can
    /// report a store failure rather than trapping inside it.
    static func seededPickupHistoryContainer(
        referenceDate: Date = Date(timeIntervalSince1970: 1_756_000_000)
    ) throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let start = referenceDate.addingTimeInterval(-5 * 3600)
        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(4 * 3600))
        context.insert(shift)

        let noodles = place(named: SyntheticPickupPlace.noodles, at: start, in: context)
        let diner = place(named: SyntheticPickupPlace.diner, at: start.addingTimeInterval(60), in: context)

        // accepted, arrived, picked up, delivered — offsets in seconds from the
        // shift's start. The wait each one records is the gap between the second
        // and third columns.
        let waits: [(place: PickupPlace?, offsets: (TimeInterval, TimeInterval, TimeInterval?, TimeInterval?))] = [
            (noodles, (300, 600, 960, 1_500)),       // 6 min
            (noodles, (1_800, 2_100, 2_760, 3_300)), // 11 min
            (noodles, (3_600, 3_900, 6_360, 7_200)), // 41 min, kept
            (diner, (8_400, 8_700, 9_900, 10_500)),  // 20 min
            (nil, (10_800, 11_100, 11_400, 12_000))  // 5 min, at no place
        ]

        for wait in waits {
            let delivery = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(wait.offsets.0))
            try? delivery.markArrivedAtPickup(at: start.addingTimeInterval(wait.offsets.1))
            if let pickedUp = wait.offsets.2 {
                try? delivery.markPickedUp(at: start.addingTimeInterval(pickedUp))
            }
            if let delivered = wait.offsets.3 {
                try? delivery.markDelivered(at: start.addingTimeInterval(delivered))
            }
            delivery.setPickupPlace(wait.place)
            context.insert(delivery)
        }

        // Cancelled after arriving and before any pickup: it names the place and
        // records an arrival, and still contributes no wait to it.
        let abandoned = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(7_500))
        try? abandoned.markArrivedAtPickup(at: start.addingTimeInterval(7_800))
        try? abandoned.cancel(at: start.addingTimeInterval(8_100))
        abandoned.setPickupPlace(noodles)
        context.insert(abandoned)

        try? context.save()

        return container
    }

    /// The shapes of pickup-wait history the sheet has to handle.
    enum PickupHistoryFixture {
        /// Enough recorded waits for a median, including one long one.
        case severalRecordedWaits
        /// Exactly one, which is a fact but not a typical wait.
        case oneRecordedWait
        /// A place every delivery reached without recording a pickup.
        case noRecordedWaits
    }

    /// The pickup-place history sheet over a synthetic place.
    @MainActor
    static func pickupPlaceHistory(_ fixture: PickupHistoryFixture) -> some View {
        let container = emptyContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_756_000_000)

        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(4 * 3600))
        context.insert(shift)

        let subject = place(named: SyntheticPickupPlace.noodles, at: start, in: context)

        // Arrival-to-pickup gaps, in seconds. `nil` is a delivery that arrived
        // and never recorded a pickup, which records no wait.
        let waits: [TimeInterval?] = switch fixture {
        case .severalRecordedWaits: [360, 660, 2_460, 900]
        case .oneRecordedWait: [1_200]
        case .noRecordedWaits: [nil, nil]
        }

        for (index, wait) in waits.enumerated() {
            let accepted = start.addingTimeInterval(Double(index) * 3_000 + 300)
            let delivery = Delivery(shift: shift, acceptedAt: accepted)
            try? delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(300))
            if let wait {
                try? delivery.markPickedUp(at: accepted.addingTimeInterval(300 + wait))
                try? delivery.markDelivered(at: accepted.addingTimeInterval(900 + wait))
            } else {
                try? delivery.cancel(at: accepted.addingTimeInterval(1_200))
            }
            delivery.setPickupPlace(subject)
            context.insert(delivery)
        }
        try? context.save()

        return PickupPlaceHistoryView(place: subject).modelContainer(container)
    }

    /// One synthetic place, inserted and returned.
    ///
    /// Force-unwrapped for the reason the containers above are: every name in
    /// this file is an invented literal that validates, and a fixture cannot
    /// meaningfully carry on without the place it is built around.
    private static func place(named name: String, at date: Date, in context: ModelContext) -> PickupPlace {
        let place = PickupPlace(name: try! PickupPlaceName(name), createdAt: date)
        context.insert(place)
        return place
    }

    /// Invented pickup-place names, obviously fictional and used everywhere a
    /// fixture needs one.
    ///
    /// No real business is named in this repository. These exist so a preview,
    /// a screenshot and a UI test can show that a delivery carries a pickup
    /// place — and that two deliveries can share one — without putting a
    /// merchant, or a driver's actual working area, into the project.
    enum SyntheticPickupPlace {
        static let noodles = "Nowhere Noodles"
        static let diner = "Example Diner"
    }

    /// A pickup place attached to the deliveries that name it.
    ///
    /// Built directly rather than through ``PickupPlaceService`` because a
    /// fixture is describing a store that already exists, not performing the
    /// driver's action. Reuse is expressed the way the service would leave it:
    /// one place object, referenced by two deliveries.
    private static func attachPickupPlaces(to deliveries: [Delivery], in context: ModelContext, at date: Date) {
        guard let noodles = try? PickupPlaceName(SyntheticPickupPlace.noodles),
              let diner = try? PickupPlaceName(SyntheticPickupPlace.diner) else { return }

        let shared = PickupPlace(name: noodles, createdAt: date)
        let other = PickupPlace(name: diner, createdAt: date.addingTimeInterval(60))
        context.insert(shared)
        context.insert(other)

        // The first and third share a place, so the history screen shows a
        // repeated pickup; the second carries a different one and any further
        // delivery carries none, which is the ordinary case.
        if deliveries.indices.contains(0) { deliveries[0].setPickupPlace(shared) }
        if deliveries.indices.contains(1) { deliveries[1].setPickupPlace(other) }
        if deliveries.indices.contains(2) { deliveries[2].setPickupPlace(shared) }
    }

    /// Invented per-delivery amounts for the seeded history.
    ///
    /// The first delivery ran 25 minutes for `$14.75` and the third 30 minutes
    /// for `$9.50`, which are `$35.40` and `$19.00` per recorded delivery hour.
    /// The cancelled one in between is left with **no** amount rather than with
    /// zero: a delivery nobody recorded a figure for and one recorded as paying
    /// nothing are different states, and a fixture that showed only one of them
    /// would let the difference go untested on screen.
    ///
    /// Nothing here relates to the shift's own `$86.25`. The two figures are
    /// independent by design, they deliberately do not add up, and no screen
    /// reconciles them.
    private static func attachDeliveryEarnings(to deliveries: [Delivery]) {
        if deliveries.indices.contains(0) {
            try? deliveries[0].setGrossEarnings(Money(minorUnits: 1475))
        }
        if deliveries.indices.contains(2) {
            try? deliveries[2].setGrossEarnings(Money(minorUnits: 950))
        }
    }

    /// Three made-up deliveries for one shift: two delivered and one cancelled
    /// after the driver had already waited at the pickup.
    ///
    /// The second and third overlap — the driver accepted the third while the
    /// second was still open — so the history screen has a stacked pair to
    /// present, with each delivery's own intervals and no total across them.
    ///
    /// Offsets only, plus an invented pickup place attached separately. No
    /// customer and no address appears anywhere in DashPilot, so there is none
    /// to invent here either.
    private static func syntheticDeliveries(in shift: Shift, from start: Date) -> [Delivery] {
        func delivery(
            acceptedAfter: TimeInterval,
            arrivedAfter: TimeInterval?,
            pickedUpAfter: TimeInterval?,
            deliveredAfter: TimeInterval?,
            cancelledAfter: TimeInterval? = nil
        ) -> Delivery {
            let delivery = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(acceptedAfter))
            if let arrivedAfter {
                try? delivery.markArrivedAtPickup(at: start.addingTimeInterval(arrivedAfter))
            }
            if let pickedUpAfter {
                try? delivery.markPickedUp(at: start.addingTimeInterval(pickedUpAfter))
            }
            if let deliveredAfter {
                try? delivery.markDelivered(at: start.addingTimeInterval(deliveredAfter))
            }
            if let cancelledAfter {
                try? delivery.cancel(at: start.addingTimeInterval(cancelledAfter))
            }
            return delivery
        }

        return [
            delivery(acceptedAfter: 300, arrivedAfter: 600, pickedUpAfter: 1_020, deliveredAfter: 1_800),
            // Cancelled after a wait at the pickup: the arrival it did record is
            // kept, and the intervals it cannot support are simply absent.
            delivery(
                acceptedAfter: 2_400,
                arrivedAfter: 2_700,
                pickedUpAfter: nil,
                deliveredAfter: nil,
                cancelledAfter: 3_600
            ),
            // Accepted while the one above was still open, and delivered after
            // it was cancelled: two overlapping lifecycles, both valid.
            delivery(acceptedAfter: 3_000, arrivedAfter: 3_300, pickedUpAfter: 3_900, deliveredAfter: 4_800)
        ]
    }

    /// The shapes of completed shift a detail screen has to handle.
    enum DetailFixture {
        /// An amount recorded and a measured route with a gap in it, which is
        /// the ordinary case and the one where every figure exists.
        case withEarningsAndRoute
        /// Neither, which is the case where the screen has to explain absences
        /// rather than show numbers.
        case withoutEarningsOrRoute
    }

    /// A short made-up route: by default two capture sessions with a gap
    /// between them.
    ///
    /// The origin is a round number in open country chosen for arithmetic, not a
    /// place anyone has driven, and every position is an explicit offset north
    /// of it. No preview contains a real coordinate.
    ///
    /// `sessions: 1` produces one unbroken stretch instead, so a fixture can
    /// hold a route with no detected gap beside one that has them — which is
    /// what lets a period summary show a partial count that is neither none nor
    /// all of its shifts.
    private static func syntheticRoute(from start: Date, sessions: Int = 2) -> [PreviewRouteSample] {
        let firstSession = UUID()
        let secondSession = UUID()
        let metresPerDegreeLatitude = 111_320.0

        func sample(secondsIn: TimeInterval, northMetres: Double, session: UUID) -> PreviewRouteSample {
            PreviewRouteSample(
                timestamp: start.addingTimeInterval(secondsIn),
                latitude: 40.0 + northMetres / metresPerDegreeLatitude,
                longitude: -75.0,
                captureSessionID: session
            )
        }

        let first = (0..<12).map { step in
            sample(secondsIn: Double(step) * 20, northMetres: Double(step) * 400, session: firstSession)
        }
        guard sessions > 1 else { return first }

        return first + (0..<8).map { step in
            // Half an hour later and further along: the driver had DashPilot in
            // the background in between, and that distance is not recorded.
            sample(
                secondsIn: 1800 + Double(step) * 20,
                northMetres: 9_000 + Double(step) * 400,
                session: secondSession
            )
        }
    }

    /// A position waiting to be attached to a shift.
    private struct PreviewRouteSample {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let captureSessionID: UUID

        func attached(to shift: Shift) -> RouteSample {
            RouteSample(
                shift: shift,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: 8,
                captureSessionID: captureSessionID
            )
        }
    }

    /// The root screen with both location services stubbed.
    ///
    /// Previews get the stub tracking provider, so no preview ever starts a
    /// `CLLocationManager` or reads a position.
    @MainActor
    static func rootView(
        container: ModelContainer,
        status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> some View {
        let authorization = LocationAuthorizationService(
            provider: StubLocationAuthorizationProvider(status: status)
        )
        let routeCapture = LocationTrackingService(
            context: container.mainContext,
            authorization: authorization,
            provider: StubLocationTrackingProvider()
        )
        return RootView()
            .modelContainer(container)
            .environment(authorization)
            .environment(routeCapture)
    }

    /// The completed shift detail screen over a synthetic shift.
    ///
    /// Wrapped in its own `NavigationStack` so the title and the destructive
    /// confirmation appear the way they do when a history row pushes it.
    @MainActor
    static func completedShiftDetail(_ fixture: DetailFixture) -> some View {
        let container = emptyContainer()
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(3 * 3600))

        if fixture == .withEarningsAndRoute {
            try? shift.setGrossEarnings(Money(minorUnits: 8625))
        }
        container.mainContext.insert(shift)
        if fixture == .withEarningsAndRoute {
            for sample in syntheticRoute(from: start) {
                container.mainContext.insert(sample.attached(to: shift))
            }
            let deliveries = syntheticDeliveries(in: shift, from: start)
            for delivery in deliveries {
                container.mainContext.insert(delivery)
            }
            attachPickupPlaces(to: deliveries, in: container.mainContext, at: start)
            attachDeliveryEarnings(to: deliveries)
        }
        try? container.mainContext.save()

        return NavigationStack {
            CompletedShiftDetailView(shift: shift)
        }
        .modelContainer(container)
    }

    /// The earnings editor over a synthetic completed shift.
    @MainActor
    static func earningsEditor(withRecordedEarnings: Bool) -> some View {
        let container = emptyContainer()
        let shift = Shift(startedAt: Date(timeIntervalSince1970: 1_756_000_000))
        try? shift.end(at: Date(timeIntervalSince1970: 1_756_000_000 + 4 * 3600))
        if withRecordedEarnings {
            try? shift.setGrossEarnings(Money(minorUnits: 8625))
        }
        container.mainContext.insert(shift)

        return ShiftEarningsEditor(shift: shift).modelContainer(container)
    }

    /// The expense editor, empty or over one synthetic recorded cost.
    @MainActor
    static func expenseEditor(editingExisting: Bool) -> some View {
        let container = emptyContainer()
        let expense = try? Expense(
            occurredAt: Date(timeIntervalSince1970: 1_756_000_000),
            amount: Money(minorUnits: 4_210),
            category: .fuel,
            noteText: "Half tank before the lunch rush"
        )
        if editingExisting, let expense {
            container.mainContext.insert(expense)
        }

        return ExpenseEditor(expense: editingExisting ? expense : nil).modelContainer(container)
    }

    /// The delivery earnings editor over a synthetic delivered delivery.
    ///
    /// The delivery is finished, because a delivery still in progress is one the
    /// editor is never presented for and the model refuses an amount on.
    @MainActor
    static func deliveryEarningsEditor(withRecordedEarnings: Bool) -> some View {
        let container = emptyContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_756_000_000)

        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(4 * 3600))
        context.insert(shift)

        let delivery = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(300))
        try? delivery.markArrivedAtPickup(at: start.addingTimeInterval(600))
        try? delivery.markPickedUp(at: start.addingTimeInterval(1_020))
        try? delivery.markDelivered(at: start.addingTimeInterval(1_800))
        context.insert(delivery)

        if withRecordedEarnings {
            try? delivery.setGrossEarnings(Money(minorUnits: 1475))
        }

        return DeliveryEarningsEditor(numbered: NumberedDelivery(number: 1, delivery: delivery))
            .modelContainer(container)
    }

    // MARK: Export

    /// The scopes the export sheet has to present.
    enum ExportFixture {
        /// One completed shift, with an amount, a route and its deliveries.
        case singleShift
        /// The week the synthetic period fixture covers.
        case week
    }

    /// The export sheet over a synthetic store.
    ///
    /// The file it writes goes into the app's temporary export directory like
    /// any other, and holds only invented amounts, offsets and place names.
    @MainActor
    static func exportSheet(_ fixture: ExportFixture) -> some View {
        let container = periodSummaryContainer()
        let scope: ExportScope

        switch fixture {
        case .singleShift:
            let descriptor = FetchDescriptor<Shift>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            let shift = (try? container.mainContext.fetch(descriptor))?.first
            // A fixture with no shift cannot demonstrate the sheet, but it can
            // still show the refusal, which is a state worth seeing.
            scope = .shift(shift?.id ?? UUID())
        case .week:
            scope = ReportingPeriod(unit: .week, containing: .now)
                .map(ExportScope.period) ?? .allHistory
        }

        return ShiftExportSheet(scope: scope).modelContainer(container)
    }

    /// The custom range selector, opened on this week's dates.
    ///
    /// No store: the sheet chooses dates and nothing else. What the chosen range
    /// then holds is ``PeriodSummaryView``'s question.
    @MainActor
    static func customRangeSheet() -> some View {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let start = ReportingPeriod(unit: .week, containing: now, calendar: calendar)?.start ?? now
        return CustomRangeSheet(start: start, end: now, latestSelectableDay: now) { _, _ in }
    }

    /// The pickup-place editor over a synthetic delivery.
    ///
    /// The store is seeded with a second delivery that already names a place, so
    /// the sheet has a recent place to offer as well as an empty field.
    @MainActor
    static func pickupPlaceEditor(withRecordedPlace: Bool) -> some View {
        let container = emptyContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_756_000_000)

        let shift = Shift(startedAt: start)
        context.insert(shift)

        let earlier = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(300))
        let subject = Delivery(shift: shift, acceptedAt: start.addingTimeInterval(1_800))
        context.insert(earlier)
        context.insert(subject)

        if let name = try? PickupPlaceName(SyntheticPickupPlace.diner) {
            let place = PickupPlace(name: name, createdAt: start)
            context.insert(place)
            earlier.setPickupPlace(place)
        }
        if withRecordedPlace, let name = try? PickupPlaceName(SyntheticPickupPlace.noodles) {
            let place = PickupPlace(name: name, createdAt: start.addingTimeInterval(60))
            context.insert(place)
            subject.setPickupPlace(place)
        }
        try? context.save()

        let numbered = NumberedDelivery(number: 2, delivery: subject)
        return PickupPlaceEditor(numbered: numbered).modelContainer(container)
    }

    /// The rename sheet over a synthetic place that a delivery already names.
    ///
    /// A second place exists in the store so the preview exercises the screen a
    /// collision is actually reachable from.
    @MainActor
    static func pickupPlaceRename() -> some View {
        let (container, subject, _) = twoPlacesSharingAShift()
        return PickupPlaceRenameView(place: subject).modelContainer(container)
    }

    /// The merge sheet over a synthetic place, with one destination to choose.
    @MainActor
    static func pickupPlaceMerge() -> some View {
        let (container, subject, _) = twoPlacesSharingAShift()
        return PickupPlaceMergeView(source: subject, onMerged: {}).modelContainer(container)
    }

    /// One completed shift, two synthetic places, and a delivery at each.
    ///
    /// Enough for both correction screens: the first place is the one being
    /// renamed or merged away, and the second is what a rename could collide
    /// with and what a merge can be pointed at.
    @MainActor
    private static func twoPlacesSharingAShift() -> (ModelContainer, PickupPlace, PickupPlace) {
        let container = emptyContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_756_000_000)

        let shift = Shift(startedAt: start)
        try? shift.end(at: start.addingTimeInterval(4 * 3600))
        context.insert(shift)

        let subject = place(named: SyntheticPickupPlace.diner, at: start, in: context)
        let other = place(named: SyntheticPickupPlace.noodles, at: start.addingTimeInterval(60), in: context)

        for (index, attached) in [subject, other].enumerated() {
            let accepted = start.addingTimeInterval(Double(index) * 3_000 + 300)
            let delivery = Delivery(shift: shift, acceptedAt: accepted)
            try? delivery.markArrivedAtPickup(at: accepted.addingTimeInterval(300))
            try? delivery.markPickedUp(at: accepted.addingTimeInterval(900))
            try? delivery.markDelivered(at: accepted.addingTimeInterval(1_800))
            delivery.setPickupPlace(attached)
            context.insert(delivery)
        }
        try? context.save()

        return (container, subject, other)
    }
}
#endif
