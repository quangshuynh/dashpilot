import Foundation
import OSLog
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
    /// A pause was requested on a shift that already has one open.
    case alreadyPaused
    /// A resume was requested on a shift with no open pause.
    case notPaused
    /// A lifecycle transition was requested on a shift that has already ended.
    case shiftAlreadyEnded
    /// The pause model rejected the transition.
    case invalidPause(ShiftPauseError)
    /// A fuel economy of zero or less was recorded. It is the divisor of a fuel
    /// estimate, and there is no truthful reading of a vehicle that covers no
    /// distance on a gallon.
    case invalidFuelEconomy
    /// A negative gas price was recorded. Zero is allowed and means the fuel
    /// cost nothing; a negative price is not a thing a pump charges.
    case negativeGasPrice
    /// The driver's current defaults were offered to a shift that already
    /// records fuel assumptions of its own.
    ///
    /// The snapshot taken when a shift starts may only ever fill an empty pair.
    /// A default that could overwrite a recorded fact would be the dynamic
    /// dependence on a current global figure the snapshot exists to prevent.
    case fuelAssumptionsAlreadyRecorded
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

    /// The offers accepted during this shift, in no guaranteed order.
    ///
    /// The delete rule is `.cascade`, for the reason the deliveries' and the
    /// pauses' are: an acceptance recorded inside one shift means nothing apart
    /// from it, and leaving offers behind would orphan rows describing a shift
    /// that no longer exists. A shift's deliveries cascade from here too, so an
    /// offer and its deliveries go together whichever edge the delete walks.
    ///
    /// A collection here, where `Shift` deliberately holds no collection of its
    /// route: the cost measured in v10 was in a to-many inverse a shift gains
    /// rows in thousands of times, and an offer is recorded a few dozen times a
    /// shift at most, the same order as a delivery or a pause.
    @Relationship(deleteRule: .cascade, inverse: \Offer.shift)
    private(set) var offers: [Offer] = []

    /// The stretches of this shift the driver recorded as paused, in no
    /// guaranteed order.
    ///
    /// The delete rule is `.cascade`, for the reason the route's and the
    /// deliveries' are: a pause is a statement about one shift and means nothing
    /// apart from it, so deleting the shift must take its pauses rather than
    /// leaving rows describing a shift that no longer exists.
    @Relationship(deleteRule: .cascade, inverse: \ShiftPause.shift)
    private(set) var pauses: [ShiftPause] = []

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

    /// The vehicle fuel economy this shift's fuel estimate is worked out under,
    /// in miles per gallon, or `nil` when the driver has recorded none.
    ///
    /// **A snapshot, not a reference.** It is written when the driver records
    /// fuel assumptions for *this* shift and is never touched again by anything
    /// they enter later. A driver who changes vehicle in March has not changed
    /// what February's shifts consumed, and a finished shift that re-derived its
    /// fuel from a current global figure would rewrite its own history every time
    /// that figure moved.
    ///
    /// `private(set)` rather than `private`, unlike ``grossEarningsAmount``,
    /// for one reason: ``ShiftService/mostRecentFuelAssumptions()`` seeds the
    /// editor from the last shift that recorded assumptions, and a SwiftData
    /// `#Predicate` can only name a property it can read. Nothing else reads it:
    /// ``fuelAssumptions`` is the accessor, and it is the only place the stored
    /// pair becomes a ``FuelAssumptions``.
    ///
    /// Always greater than zero where it is present: ``setFuelAssumptions(milesPerGallon:gasPricePerGallon:vehicleName:)``
    /// refuses anything else, because it is the divisor of the estimate.
    private(set) var fuelMilesPerGallonValue: Decimal?

    /// What a gallon of fuel cost, as the assumption this shift's estimate is
    /// worked out under, or `nil` when the driver has recorded none.
    ///
    /// A snapshot for the reason above: a fill-up next month at a higher price
    /// did not make last month's driving more expensive.
    ///
    /// **`nil` and zero are different facts.** `nil` means no price was
    /// recorded, so there is no estimate; `0` means the fuel was recorded as
    /// having cost nothing, which produces an estimate of ``Money/zero``.
    private(set) var fuelGasPricePerGallonAmount: Decimal?

    /// What the vehicle this shift's fuel economy came from was called, or `nil`
    /// when the economy was typed by hand rather than taken from a vehicle
    /// profile.
    ///
    /// **A snapshot, exactly like the two figures above, and for one more
    /// reason.** A ``VehicleProfile`` is a preference the driver is invited to
    /// rename and delete. A shift holding a reference to one would either lose
    /// its label when that row went, or follow a rename it had nothing to do
    /// with; a shift holding the *name* stays intelligible with no profile
    /// behind it at all. There is deliberately no relationship between the two
    /// entities anywhere in the app.
    ///
    /// It is a label, never an input. No estimate, rate, total, coverage count
    /// or aggregate reads it, and a shift with an economy but no name produces
    /// exactly the same figures as one with both.
    ///
    /// The name is only ever recorded beside the economy it describes: see
    /// ``setFuelAssumptions(milesPerGallon:gasPricePerGallon:vehicleName:)``.
    private(set) var fuelVehicleName: String?

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
    }

    /// Whether the shift has not finished.
    ///
    /// The direct reading of `endedAt == nil`, and deliberately still that: a
    /// paused shift is unfinished, so pausing does not change this, does not
    /// change which shift ``ShiftService/activeShift()`` returns, and does not
    /// change which row a relaunch recovers. Ask ``lifecycleState`` for the
    /// distinction between running and paused.
    var isActive: Bool { endedAt == nil }

    /// Duration of a finished shift, or `nil` while it is still running.
    var completedDuration: TimeInterval? {
        endedAt.map { clampedInterval(from: startedAt, to: $0) }
    }

    /// Time covered by the shift so far, measured against `referenceDate` while running.
    func elapsed(asOf referenceDate: Date) -> TimeInterval {
        clampedInterval(from: startedAt, to: endedAt ?? referenceDate)
    }

    /// The window a finished shift covers, or `nil` while it is still running.
    ///
    /// The one place the shift's own range is built, so a route measurement and
    /// a delivery interval are checked against the same window. A running shift
    /// deliberately has none: its window is still growing, and measuring against
    /// "now" would report a gap for every red light.
    ///
    /// `nil` also for a stored shift whose end precedes its start, which
    /// ``end(at:)`` refuses to create. A range cannot be built from those
    /// timestamps at all, and trapping on a driver's device over an anomalous
    /// row is not an acceptable way to find out about one.
    var completedWindow: ClosedRange<Date>? {
        guard let endedAt, endedAt >= startedAt else { return nil }
        return startedAt...endedAt
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

    /// Checks an instant the driver proposes as the moment this finished shift
    /// ended.
    ///
    /// The adapter between the model and ``ShiftEndCorrection``, holding no rule
    /// of its own: it gathers this shift's start, its recorded end, its pauses
    /// and every lifecycle instant its deliveries record, and the value type
    /// decides. Nothing is written and nothing is mutated, so a screen can ask
    /// what a proposed end would be refused for without attempting it.
    ///
    /// `nextShiftStartedAt` is the caller's because it is the one fact here that
    /// is not this shift's own; ``ShiftEndCorrectionService`` reads it from the
    /// store.
    ///
    /// - Throws: ``ShiftEndCorrectionRefusal``.
    func endCorrection(to correctedEnd: Date, nextShiftStartedAt: Date?) throws -> ShiftEndCorrection {
        try ShiftEndCorrection(
            to: correctedEnd,
            startedAt: startedAt,
            recordedEnd: endedAt,
            pauses: pauseIntervals,
            deliveryEvents: numberedDeliveries.flatMap { numbered in
                numbered.delivery.recordedEvents.map { recorded in
                    RecordedDeliveryEvent(
                        deliveryNumber: numbered.number,
                        event: recorded.event,
                        occurredAt: recorded.occurredAt
                    )
                }
            },
            nextShiftStartedAt: nextShiftStartedAt
        )
    }

    /// Rewrites when this shift ended.
    ///
    /// **The only place `endedAt` is written after ``end(at:)`` recorded it**,
    /// and it writes nothing else: the start, the earnings, every delivery, every
    /// pause and every retained position are left exactly as they are. Taking
    /// the route evidence that now lies outside the shift with it is
    /// ``ShiftEndCorrectionService``'s, because it is a change to other rows and
    /// has to share one transaction with this one.
    ///
    /// The correction has already been checked against this shift's own facts by
    /// ``ShiftEndCorrection``. What is kept here is the one rule that is about
    /// *this row* rather than about the records around it: **a shift that has
    /// not ended has no end to correct.**
    ///
    /// - Throws: ``ShiftEndCorrectionRefusal/shiftNotCompleted`` for a shift
    ///   that is still running, and for one whose recorded end is no longer the
    ///   end the correction was built against.
    func apply(_ correction: ShiftEndCorrection) throws {
        guard endedAt == correction.recordedEnd else { throw ShiftEndCorrectionRefusal.shiftNotCompleted }
        endedAt = correction.correctedEnd
    }

    /// The device clock can move backwards (manual changes, NTP corrections),
    /// so a negative interval is treated as zero rather than surfaced as a
    /// negative duration in metrics.
    private func clampedInterval(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

extension Shift {
    /// This shift's retained positions, oldest first.
    ///
    /// **A shift does not hold its route as a collection**, and the reason is
    /// measured rather than stylistic. A `Shift.routeSamples` inverse made
    /// writing one position cost time proportional to the number of positions
    /// already attached to the shift, so recording a long shift got steadily
    /// slower as it went and deleting one walked the same collection. See
    /// ``DashPilotSchemaV10`` for the figures and for what was ruled out.
    ///
    /// So the route is fetched. Every reader here went through the collection
    /// before and goes through this query now, which keeps one definition of
    /// "this shift's route" rather than scattering the predicate.
    ///
    /// The sort is the one the walk needs and is the order the relationship
    /// never guaranteed: timestamp first, then coordinate, because a timestamp
    /// alone is not a total order and two positions fixed at the same instant
    /// would otherwise arrive in whatever order the store returned them. It is
    /// the same order ``ActiveShiftRouteService`` reads a running shift in.
    ///
    /// An empty array is returned for a shift that is not in a store, which is
    /// a shift with no recorded route because nothing could have recorded one.
    func routeSamples() -> [RouteSample] {
        guard let modelContext else { return [] }
        let shiftID = id
        let descriptor = FetchDescriptor<RouteSample>(
            predicate: #Predicate { $0.shift?.id == shiftID },
            sortBy: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.latitude),
                SortDescriptor(\.longitude)
            ]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            // A route that could not be read is not a route of zero miles, but
            // this returns what it has rather than throwing into every caller.
            // The reason names no position.
            AppLog.routeCapture.error("Could not read a shift's stored route: \(error)")
            return []
        }
    }

    /// How many positions this shift's route holds.
    ///
    /// A count rather than a fetch, so a screen that only reports the size of a
    /// route does not load one.
    var routeSampleCount: Int {
        guard let modelContext else { return 0 }
        let shiftID = id
        do {
            return try modelContext.fetchCount(
                FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == shiftID })
            )
        } catch {
            AppLog.routeCapture.error("Could not count a shift's stored route: \(error)")
            return 0
        }
    }

    /// This shift's retained positions fixed **strictly after** `boundary`,
    /// oldest first.
    ///
    /// The evidence an end-time correction moving the end back to `boundary`
    /// takes out of the shift. Strictly after, so a position fixed exactly at
    /// the boundary is kept: the driver said they stopped then, and a position
    /// recorded at that instant is the last thing that happened inside the
    /// shift rather than the first thing outside it.
    ///
    /// The predicate and the ordering are ``routeSamples()``'s, with one more
    /// clause, so there is still one definition of "this shift's route".
    ///
    /// An empty array for a shift that is not in a store, and for a read the
    /// store refused — which is why ``ShiftEndCorrectionService`` fetches
    /// through the context itself rather than through this, and this is used
    /// where a count is being shown rather than where rows are being deleted.
    func routeSamples(after boundary: Date) -> [RouteSample] {
        guard let modelContext else { return [] }
        let shiftID = id
        let descriptor = FetchDescriptor<RouteSample>(
            predicate: #Predicate { $0.shift?.id == shiftID && $0.timestamp > boundary },
            sortBy: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.latitude),
                SortDescriptor(\.longitude)
            ]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            // The reason names no position and no instant.
            AppLog.routeCapture.error("Could not read the tail of a shift's stored route: \(error)")
            return []
        }
    }

    /// How many positions this shift's route holds after `boundary`.
    ///
    /// A count rather than a fetch, for the reason ``routeSampleCount`` is one:
    /// the confirmation a driver reads before an end-time correction states how
    /// many positions would leave the shift, and stating a number should not
    /// load a route to do it.
    func routeSampleCount(after boundary: Date) -> Int {
        guard let modelContext else { return 0 }
        let shiftID = id
        do {
            return try modelContext.fetchCount(
                FetchDescriptor<RouteSample>(
                    predicate: #Predicate { $0.shift?.id == shiftID && $0.timestamp > boundary }
                )
            )
        } catch {
            AppLog.routeCapture.error("Could not count the tail of a shift's stored route: \(error)")
            return 0
        }
    }

    /// Distance recorded for this shift, measured from its retained route.
    ///
    /// Derived on demand and never stored. A shift's mileage is a *reading* of
    /// its route, not a second fact about the shift that could drift away from
    /// it: caching the total would mean an improvement to the calculation left
    /// every historical shift showing the old number, and a store holding two
    /// answers to the same question. Removing the route collection did not
    /// change that and was not an excuse to revisit it: the write cost it fixed
    /// was in recording a position, not in measuring one.
    ///
    /// Only this shift's samples are measured. Distance across a gap in capture
    /// is excluded rather than guessed, so the result is what the route can
    /// support and usually less than the miles actually driven — see
    /// ``RouteDistance``.
    func recordedDistance(
        using calculator: RouteMileageCalculator = RouteMileageCalculator()
    ) -> RouteDistance {
        calculator.distance(
            of: routeSamples().map(\.routePoint),
            // A finished shift has a window the route can be checked against; a
            // running one does not. See ``completedWindow``.
            covering: completedWindow
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

// MARK: - Fuel assumptions

extension Shift {
    /// The fuel economy and gas price this shift's estimate is worked out under.
    ///
    /// The one place the two stored columns become a ``FuelAssumptions``, so
    /// nothing else in the app handles the raw decimals.
    var fuelAssumptions: FuelAssumptions {
        FuelAssumptions(
            milesPerGallon: fuelMilesPerGallonValue,
            gasPricePerGallon: fuelGasPricePerGallonAmount.map(Money.init(amount:))
        )
    }

    /// Records the assumptions this shift's fuel estimate is worked out under,
    /// replacing whatever was recorded before.
    ///
    /// **Both halves move together, or neither does.** Every rule is checked
    /// before any column is written, so a driver who corrects a valid gas price
    /// and mistypes the economy in the same edit is left with exactly the pair
    /// they had. An edit that is refused changes nothing.
    ///
    /// Each half is independently optional: passing `nil` for one records that
    /// the driver has not entered it, which is the state that produces the
    /// naming refusal rather than a zero.
    ///
    /// Three invariants, kept on the model rather than in a view so that no
    /// screen, test or future caller can record a pair the app would refuse to
    /// estimate from:
    ///
    /// - Only a **completed** shift may carry them, by the rule that governs
    ///   ``setGrossEarnings(_:)``: entering figures is a stopped-vehicle task,
    ///   and a running shift's recorded mileage is still moving.
    /// - A fuel economy must be **greater than zero**. It is the divisor, and
    ///   there is no truthful reading of a vehicle that covers nothing on a
    ///   gallon.
    /// - A gas price may not be **negative**. Zero is allowed and meaningful:
    ///   fuel really can have cost nothing.
    ///
    /// Both are stored exactly as given. Rounding is a display decision, and the
    /// input layer refuses anything finer rather than quietly rounding here.
    ///
    /// ## The vehicle name, and the one rule it follows
    ///
    /// `vehicleName` is the vehicle the caller means this economy to describe,
    /// and it is normally `nil`: a driver typing figures into the editor is not
    /// naming a vehicle. Passing `nil` does **not** simply erase a name the
    /// shift already holds, because that would cost a driver their vehicle label
    /// every time they corrected the gas price beside it. Instead the existing
    /// name is kept exactly while the economy it describes is unchanged, and
    /// dropped the moment the economy moves.
    ///
    /// That is the whole of the rule, and it is here rather than in a view
    /// because it is a statement about what the record means: a name says *which
    /// vehicle covers this many miles on a gallon*, so a different economy is a
    /// different vehicle as far as DashPilot can honestly tell.
    ///
    /// - Throws: ``ShiftError/shiftNotCompleted``,
    ///   ``ShiftError/invalidFuelEconomy`` or ``ShiftError/negativeGasPrice``.
    func setFuelAssumptions(
        milesPerGallon: Decimal?,
        gasPricePerGallon: Money?,
        vehicleName: String? = nil
    ) throws {
        guard endedAt != nil else { throw ShiftError.shiftNotCompleted }
        try writeFuelAssumptions(
            milesPerGallon: milesPerGallon,
            gasPricePerGallon: gasPricePerGallon,
            vehicleName: vehicleName
        )
    }

    /// Copies the driver's current defaults onto a shift that has just started.
    ///
    /// **This is the earliest truthful moment to take the snapshot**, and taking
    /// it here rather than later is the substantive decision. The assumptions a
    /// shift is estimated under are the ones that were true while it was being
    /// worked: a driver who changes vehicle at lunchtime, or who notices the
    /// price has gone up, has not changed what this shift has already consumed.
    /// Reading the defaults at the *end* of a shift would let a change made
    /// mid-shift silently rewrite assumptions the whole shift was worked under,
    /// which is precisely the dependence on a current global figure the snapshot
    /// exists to prevent.
    ///
    /// Only on a shift that is still running, and only on one carrying nothing
    /// yet. Both guards exist so that this can never overwrite a recorded fact:
    /// it is the one write that happens without the driver typing anything, and
    /// the only thing it may do is fill an empty pair.
    ///
    /// Defaults holding nothing are a no-op rather than a refusal: a driver who
    /// has never opened Settings starts shifts exactly as they always did.
    ///
    /// - Throws: ``ShiftError/shiftAlreadyEnded``,
    ///   ``ShiftError/fuelAssumptionsAlreadyRecorded``,
    ///   ``ShiftError/invalidFuelEconomy`` or ``ShiftError/negativeGasPrice``.
    func recordStartingFuelDefaults(_ defaults: FuelDefaults) throws {
        guard endedAt == nil else { throw ShiftError.shiftAlreadyEnded }
        guard !fuelAssumptions.hasAny else { throw ShiftError.fuelAssumptionsAlreadyRecorded }
        guard defaults.hasAny else { return }

        try writeFuelAssumptions(
            milesPerGallon: defaults.assumptions.milesPerGallon,
            gasPricePerGallon: defaults.assumptions.gasPricePerGallon,
            vehicleName: defaults.vehicleName
        )
    }

    /// The validation and the three writes, shared by the two callers above so
    /// that there is one definition of a valid pair and one place the columns
    /// move.
    private func writeFuelAssumptions(
        milesPerGallon: Decimal?,
        gasPricePerGallon: Money?,
        vehicleName: String?
    ) throws {
        if let milesPerGallon {
            guard milesPerGallon > 0 else { throw ShiftError.invalidFuelEconomy }
        }
        if let gasPricePerGallon {
            guard !gasPricePerGallon.isNegative else { throw ShiftError.negativeGasPrice }
        }

        // Read before anything moves, so the name is judged against the economy
        // the shift currently holds rather than the one being written.
        let keptName = milesPerGallon == fuelMilesPerGallonValue ? fuelVehicleName : nil

        // Nothing above can throw from here on, so the three cannot be left
        // partly written.
        fuelMilesPerGallonValue = milesPerGallon
        fuelGasPricePerGallonAmount = gasPricePerGallon?.amount
        fuelVehicleName = vehicleName ?? keptName
    }

    /// Removes both assumptions, returning the shift to having none.
    ///
    /// Deliberately distinct from recording zero, by the rule that governs
    /// ``clearGrossEarnings()``: a driver removing figures they entered by
    /// mistake is saying "I have not recorded this", not "this shift used no
    /// fuel". Afterwards the shift has no estimate at all rather than one of
    /// ``Money/zero``.
    ///
    /// It does not throw: a shift with no assumptions to remove is already in
    /// the state the caller asked for.
    func clearFuelAssumptions() {
        fuelMilesPerGallonValue = nil
        fuelGasPricePerGallonAmount = nil
        // The label goes with the economy it described. A shift with no fuel
        // economy naming a vehicle would be claiming something about a shift it
        // estimates nothing for.
        fuelVehicleName = nil
    }

    /// What this shift's recorded mileage is estimated to have consumed, and
    /// what that cost.
    ///
    /// The adapter between the model and ``FuelEstimateCalculator``, holding no
    /// rule of its own. Nothing is stored: the estimate is derived from the
    /// route's measurement and the shift's own assumptions every time it is
    /// asked for, which is why correcting the shift's end, and with it the route
    /// it retains, moves the estimate with no fuel code involved at all.
    ///
    /// `recordedDistance` is passed in rather than measured here for the reason
    /// ``metrics(for:using:)`` takes one: measuring a route walks every position
    /// it holds, and the caller normally already has the result.
    func fuelEstimate(
        for recordedDistance: RouteDistance,
        using calculator: FuelEstimateCalculator = FuelEstimateCalculator()
    ) -> FuelEstimate {
        calculator.estimate(recordedDistance: recordedDistance, assumptions: fuelAssumptions)
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

// MARK: Offers

extension Shift {
    /// This shift's offers in the order they were accepted.
    var offersInOrder: [Offer] {
        offers.sorted(by: Offer.acceptedBefore)
    }

    /// The offers still holding at least one delivery in progress.
    var activeOffers: [Offer] {
        offersInOrder.filter { $0.state.isActive }
    }

    /// This shift's offers with the numbers the interface labels them with, each
    /// carrying its deliveries under the numbers they have everywhere else in
    /// this shift.
    var numberedOffers: [NumberedOffer] {
        NumberedOffer.numbering(offersInOrder, deliveries: numberedDeliveries)
    }

    /// The numbered offer a delivery was accepted in, or `nil` for a delivery
    /// that records none.
    func numberedOffer(containing delivery: Delivery) -> NumberedOffer? {
        guard let offerID = delivery.offer?.id else { return nil }
        return numberedOffers.first { $0.id == offerID }
    }

    /// Records an accepted offer containing `deliveryCount` deliveries.
    ///
    /// **The one place an offer and its deliveries are created**, so the two
    /// invariants that hold them together cannot be bypassed by a screen, a
    /// test or a future caller: an offer contains at least one delivery, and
    /// every delivery in it belongs to the shift the offer was accepted during.
    /// Mirrors ``beginPause(at:)`` in shape, including leaving the context
    /// insert to the caller, so that a refused or failed write leaves the store
    /// holding nothing the model does not also hold.
    ///
    /// Each delivery is created with the offer's own acceptance timestamp,
    /// because that is when the driver accepted them: they arrived in one act.
    /// From that instant on, each one advances entirely on its own.
    ///
    /// There is deliberately **no maximum**, for the reason there is no maximum
    /// on how many deliveries may be running at once: how much work a driver
    /// accepted is a fact about their work rather than a number this app is in
    /// a position to cap. The stepper on screen bounds what can be tapped;
    /// that is a control's range, not a domain rule.
    ///
    /// Both halves are returned rather than only the offer, so the caller can
    /// insert exactly what was built instead of reading it back out of a
    /// relationship on an object no store holds yet.
    ///
    /// - Throws: ``OfferError/deliveryCountNotPositive``,
    ///   ``OfferError/shiftAlreadyEnded`` or
    ///   ``OfferError/acceptedBeforeShiftStart``.
    func beginOffer(deliveryCount: Int, at date: Date) throws -> (offer: Offer, deliveries: [Delivery]) {
        guard deliveryCount >= 1 else { throw OfferError.deliveryCountNotPositive }
        guard endedAt == nil else { throw OfferError.shiftAlreadyEnded }
        guard date >= startedAt else { throw OfferError.acceptedBeforeShiftStart }

        let offer = Offer(shift: self, acceptedAt: date)
        let deliveries = (0..<deliveryCount).map { _ in
            Delivery(shift: self, offer: offer, acceptedAt: date)
        }
        return (offer, deliveries)
    }

    /// Records an offer containing deliveries this shift already holds, for a
    /// driver correcting which deliveries arrived together.
    ///
    /// **The one place an offer is created without creating deliveries**, and it
    /// is written so that the invariant ``beginOffer(deliveryCount:at:)`` keeps
    /// is kept here too: the deliveries are required up front and attached
    /// before it returns, so no caller can be handed an empty offer to fill in
    /// later.
    ///
    /// ## The acceptance timestamp is derived, not chosen
    ///
    /// The new offer takes the **earliest ``Delivery/acceptedAt`` among the
    /// deliveries moving into it**. That is a moment the driver really recorded,
    /// it is deterministic, and it is the only rule available that invents
    /// nothing: an acceptance the driver was never asked for cannot be guessed
    /// from how close two timestamps are, and asking them to type one would be
    /// asking for platform history they do not have. It also satisfies
    /// ``Offer/couldHaveContained(_:)`` for every delivery in the group by
    /// construction, so a split can never be refused for an ordering the split
    /// itself produced.
    ///
    /// Nothing about the deliveries changes but their offer. Their own
    /// acceptance, lifecycle timestamps, pickup places, amounts and terminal
    /// states are left exactly as they are.
    ///
    /// Unlike ``beginOffer(deliveryCount:at:)`` this is **allowed on a shift
    /// that has ended**. It records no new work and no new acceptance: it
    /// restates which of the deliveries already in that shift arrived together,
    /// which is a review action, and history is where a driver notices the
    /// mistake.
    ///
    /// - Throws: ``OfferMembershipError/noDeliveriesToGroup`` for an empty group,
    ///   or ``OfferMembershipError/differentShift`` if any delivery belongs to
    ///   another shift.
    func makeOffer(regrouping deliveries: [Delivery]) throws -> Offer {
        guard let earliest = deliveries.map(\.acceptedAt).min() else {
            throw OfferMembershipError.noDeliveriesToGroup
        }
        guard deliveries.allSatisfy({ $0.shift?.id == id }) else {
            throw OfferMembershipError.differentShift
        }

        let offer = Offer(shift: self, acceptedAt: earliest)
        for delivery in deliveries {
            try delivery.move(into: offer)
        }
        return offer
    }
}

// MARK: Pausing

extension Shift {
    /// The pause the driver has not ended, or `nil` when the shift is not paused.
    ///
    /// Read from the store's own rows rather than from a flag, for the reason
    /// ``activeDeliveries`` is: the rows are the authority, and the rule that a
    /// paused shift records no route depends on that being true after a relaunch
    /// as much as during a session.
    ///
    /// The newest open row wins. Pausing an already paused shift is refused, so
    /// there is never more than one; taking the newest means a store that
    /// somehow holds two produces the state a driver would expect rather than an
    /// arbitrary one, and ``ShiftService`` reports the anomaly.
    var openPause: ShiftPause? {
        pauses.filter(\.isOpen).max { $0.startedAt < $1.startedAt }
    }

    /// This shift's pauses in the order they began.
    var pausesInOrder: [ShiftPause] {
        pauses.sorted { $0.startedAt < $1.startedAt }
    }

    /// The interval each of this shift's pauses describes.
    var pauseIntervals: [ShiftPauseInterval] {
        pausesInOrder.map(\.interval)
    }

    /// Whether the driver has this shift paused right now.
    var isPaused: Bool { lifecycleState == .paused }

    /// Where this shift is in its life, derived from its own stored facts.
    ///
    /// An ended shift is ended whatever its pause rows say. A store holding an
    /// open pause on a finished shift is an anomaly the app cannot write, since
    /// ending closes the pause first, and reporting it as paused would leave a
    /// finished shift looking live.
    var lifecycleState: ShiftLifecycleState {
        if endedAt != nil { return .ended }
        return openPause == nil ? .running : .paused
    }

    /// The stretch of this shift being measured, as of `referenceDate`.
    ///
    /// A completed shift's own window; an unfinished shift's window up to the
    /// moment it is being read at. The upper bound is never allowed below the
    /// start, so a device clock that moved backwards produces a zero-length
    /// window rather than a reversed one.
    func measuredWindow(asOf referenceDate: Date) -> ClosedRange<Date> {
        startedAt...max(startedAt, endedAt ?? referenceDate)
    }

    /// How much of this shift the driver had it paused, as of `referenceDate`.
    ///
    /// The adapter between the model and ``ShiftPausedTimeCalculator``, holding
    /// no rule of its own. Nothing is stored: the figure is recomputed from the
    /// pause rows every time it is asked for.
    func pausedTime(
        asOf referenceDate: Date,
        using calculator: ShiftPausedTimeCalculator = ShiftPausedTimeCalculator()
    ) -> ShiftPausedTime {
        guard !pauses.isEmpty else { return .none }
        return calculator.pausedTime(of: pauseIntervals, within: measuredWindow(asOf: referenceDate))
    }

    /// The paused time of a finished shift, or `nil` while it is unfinished.
    var completedPausedTime: ShiftPausedTime? {
        endedAt.map { pausedTime(asOf: $0) }
    }

    /// Time the driver was not paused, measured against `referenceDate` while
    /// the shift is unfinished.
    ///
    /// **The definition of working duration in DashPilot**, and the denominator
    /// of every hourly figure derived from a shift. It is elapsed time less the
    /// time the shift was paused, and nothing else: it is not driving time,
    /// delivery time or productive time, and it still includes waiting for an
    /// offer, repositioning and any unpaused break.
    ///
    /// While a shift is paused this stops growing, because the open pause grows
    /// at exactly the rate elapsed time does. That is a property of the
    /// subtraction rather than a special case written for the screen.
    ///
    /// A shift with no pauses has a working duration identical to its elapsed
    /// duration, which is what makes every shift recorded before pausing existed
    /// keep the duration it has always had.
    func workingDuration(asOf referenceDate: Date) -> TimeInterval {
        max(0, elapsed(asOf: referenceDate) - pausedTime(asOf: referenceDate).duration)
    }

    /// Working duration of a finished shift, or `nil` while it is unfinished.
    var completedWorkingDuration: TimeInterval? {
        guard let completedDuration, let completedPausedTime else { return nil }
        return max(0, completedDuration - completedPausedTime.duration)
    }

    /// Opens a pause.
    ///
    /// The model keeps the invariants a screen, a test or a future caller must
    /// not be able to break: a shift that has ended cannot be paused, and one
    /// already paused cannot be paused again. The refusal for deliveries still
    /// in progress lives in ``ShiftService``, because it is a rule about the
    /// shift's other records rather than about this one.
    ///
    /// - Throws: ``ShiftError/shiftAlreadyEnded``, ``ShiftError/alreadyPaused``
    ///   or ``ShiftError/endPrecedesStart`` when `date` precedes the shift start.
    @discardableResult
    func beginPause(at date: Date) throws -> ShiftPause {
        guard endedAt == nil else { throw ShiftError.shiftAlreadyEnded }
        guard openPause == nil else { throw ShiftError.alreadyPaused }
        guard date >= startedAt else { throw ShiftError.endPrecedesStart }

        // The inverse relationship is what attaches it, exactly as a new
        // `Delivery` attaches to its shift. Inserting it into the context is
        // the caller's, so that a refused or failed write leaves nothing in the
        // store the model does not also hold.
        return ShiftPause(shift: self, startedAt: date)
    }

    /// This shift's pauses with the numbers the interface calls them by.
    var numberedPauses: [NumberedPause] {
        NumberedPause.numbering(pauses)
    }

    /// Checks a stretch the driver proposes to record as a pause of this shift.
    ///
    /// The adapter between the model and ``ShiftPauseCorrection``, holding no
    /// rule of its own: it gathers this shift's window, its other pauses and its
    /// delivery intervals, and the value type decides. Nothing is written, and
    /// nothing is mutated, so a screen can ask what a proposed stretch would be
    /// refused for without attempting it.
    ///
    /// - Parameters:
    ///   - startedAt: the proposed start.
    ///   - endedAt: the proposed end.
    ///   - pause: the pause being corrected, excluded from the overlap check so
    ///     that it cannot collide with itself. `nil` proposes a pause this shift
    ///     does not yet record, which is what adding a missed one means.
    /// - Throws: ``ShiftPauseCorrectionRefusal``.
    func pauseCorrection(
        from startedAt: Date,
        to endedAt: Date,
        replacing pause: ShiftPause? = nil
    ) throws -> ShiftPauseCorrection {
        try ShiftPauseCorrection(
            startedAt: startedAt,
            endedAt: endedAt,
            within: completedWindow,
            avoiding: pauses.filter { $0.id != pause?.id }.map(\.interval),
            and: deliveryActiveIntervals
        )
    }

    /// Records a pause the driver did not record at the time.
    ///
    /// **The one place a pause is created outside the live lifecycle**, and it
    /// is deliberately not ``beginPause(at:)``: that one opens a pause on a
    /// running shift and says the driver is stopping now. This one writes a
    /// completed pause onto a shift that has already finished and says the
    /// driver stopped then, which is a statement about history and is only ever
    /// made from a finished shift's own record.
    ///
    /// Nothing is detected, suggested or filled in. Both timestamps come from
    /// the driver through ``ShiftPauseCorrection``, which has already checked
    /// them against this shift's window, its other pauses and its delivery work.
    ///
    /// The context insert is the caller's, exactly as it is for
    /// ``beginPause(at:)`` and ``beginOffer(deliveryCount:at:)``, so a refused or
    /// failed write leaves the store holding nothing the model does not also
    /// hold.
    func addMissedPause(_ correction: ShiftPauseCorrection) -> ShiftPause {
        ShiftPause(shift: self, startedAt: correction.startedAt, endedAt: correction.endedAt)
    }

    /// Closes the open pause.
    ///
    /// - Throws: ``ShiftError/shiftAlreadyEnded``, ``ShiftError/notPaused``, or
    ///   ``ShiftError/invalidPause(_:)`` when the pause refuses the timestamp.
    @discardableResult
    func endOpenPause(at date: Date) throws -> ShiftPause {
        guard endedAt == nil else { throw ShiftError.shiftAlreadyEnded }
        guard let pause = openPause else { throw ShiftError.notPaused }
        do {
            try pause.end(at: date)
        } catch let error as ShiftPauseError {
            throw ShiftError.invalidPause(error)
        }
        return pause
    }
}
