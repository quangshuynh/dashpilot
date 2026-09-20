import Foundation

/// What a completed shift looks like in an exported file.
///
/// ## Why this exists rather than encoding the model
///
/// A `Shift` is a SwiftData model. Serialising it directly would put the
/// store's shape into a file a driver keeps — every schema change would become
/// a breaking change to that file, and implementation details the app is free
/// to move (a persistent identifier, a normalised matching key, a relationship's
/// ordering) would leak into an interchange format that has to be stable. So the
/// export layer is a set of plain values built *from* domain facts, and the
/// encoders never see a model at all.
///
/// ## What it deliberately preserves
///
/// The distinctions the rest of the app spends its effort keeping apart, because
/// a file is exactly where they get flattened:
///
/// - **Recorded mileage is not driven mileage.** The field is named for what it
///   is, and ``ShiftRouteExport`` says how much of the shift the route accounts
///   for.
/// - **A missing amount is not zero.** Every optional here is `null` in JSON and
///   an empty cell in CSV, never `0.00`.
/// - **Shift earnings and delivery earnings are separate facts.**
///   ``grossEarnings`` is the amount recorded on the shift; the amounts recorded
///   on ``deliveries`` are their own. Nothing here adds one to the other,
///   subtracts them, or exports a difference between them.
/// - **Elapsed time is not working time.** A shift the driver paused covers more
///   wall clock than it records as worked, and the two are separate fields with
///   the paused total beside them rather than one figure that could mean either.
/// - **Working time is not delivery active time**, and non-delivery time is not
///   idle time.
/// - **What a delivery was expected to pay is not what it paid.**
///   ``DeliveryExportRecord/expectedEarnings`` is a figure the driver entered
///   while the delivery was still running and nothing confirmed. It sits beside
///   ``DeliveryExportRecord/grossEarnings`` on the delivery that carries it and
///   nowhere else: no shift field, no summary figure and no rate in this format
///   is derived from it, and the two are never added, compared or substituted
///   for one another here.
/// - **An assumption is not a measurement, and an estimate is not a recorded
///   cost.** ``fuelMilesPerGallon`` and ``fuelGasPricePerGallon`` are figures the
///   driver typed for one shift. The estimated gallons and estimated fuel cost
///   DashPilot derives from them are **not** fields here, and neither is any net
///   figure derived from them: the file carries the recorded facts and the
///   assumptions, and a reader who wants the estimate applies the one rule the
///   documentation states. A recorded fuel purchase is an `expenses` row and
///   nothing in this file adds the two together.
/// - **What the platform paid is not everything the delivery paid.**
///   ``DeliveryExportRecord/grossEarnings`` is the platform-recorded amount,
///   unchanged and meaning exactly what it always has;
///   ``DeliveryExportRecord/additionalTips`` are the tips that reached the
///   driver outside it, each one its own record with its own method and moment;
///   and ``DeliveryExportRecord/effectiveEarnings`` is the two together, `null`
///   where the platform amount was never recorded. A consumer that sums the
///   first column alone is summing platform pay, which is what its name says.
///
/// ## What is deliberately absent
///
/// Raw positions. A shift's route samples are latitude and longitude at a
/// timestamp — substantially more sensitive than anything else in this file, and
/// not needed to answer "what has DashPilot recorded". The route appears here
/// only as a measurement and a description of its coverage. If exporting
/// coordinates is ever wanted it is a separate, explicit privacy feature with
/// its own consent, not a field that appeared because the model had it.
nonisolated struct ShiftExportRecord: Equatable, Sendable, Codable {
    /// The shift's own persisted identifier.
    ///
    /// Not invented for the export: ``Shift`` has carried a stable `UUID` since
    /// v1, so a later tool can tell two exports of the same shift apart from two
    /// different shifts without DashPilot minting a second identity for it.
    let id: UUID

    let startedAt: Date

    /// Always present: a running shift is never exported as history.
    let endedAt: Date

    /// The whole wall-clock length of the shift, waiting, repositioning and any
    /// pause included.
    let elapsedSeconds: Int?

    /// How long the driver had the shift paused, in total.
    ///
    /// `0` here is a measurement and not a missing value: a shift that was never
    /// paused was paused for no time. Absent only for a shift whose stored
    /// timestamps do not describe a duration at all.
    let pausedSeconds: Int?

    /// ``elapsedSeconds`` less ``pausedSeconds``: the time the shift was
    /// running and not paused.
    ///
    /// **The denominator of ``grossPerWorkingHour``**, and the figure to use
    /// when asking how long a shift was worked. It is not driving time or
    /// delivery time: it still includes waiting for an offer, repositioning and
    /// any break the driver did not pause for.
    let workingSeconds: Int?

    /// How many separate stretches the driver paused the shift for.
    let pauseCount: Int

    /// The currency every amount on this shift is in.
    ///
    /// Stated rather than implied, and fixed: DashPilot records one currency and
    /// converts nothing, so this is documentation of what the numbers mean and
    /// not a claim of multi-currency support.
    let currencyCode: String

    /// The amount the driver recorded for the **shift**, or `null` if they
    /// recorded none. Never derived from the deliveries below.
    let grossEarnings: ExportAmount?

    let route: ShiftRouteExport

    /// The vehicle fuel economy the driver recorded as the assumption this
    /// shift's fuel estimate is worked out under, or `null` if they recorded
    /// none.
    ///
    /// **An assumption the driver typed, not a measurement.** DashPilot has no
    /// way to observe a vehicle's fuel economy and does not try to.
    ///
    /// It is in the file because an export is the only way anything leaves
    /// DashPilot, and because it is half of what a reader needs to reproduce or
    /// check the estimate: `route.recordedDistanceMiles / fuelMilesPerGallon`
    /// gallons, at ``fuelGasPricePerGallon`` each. The **estimate itself is
    /// deliberately not a field**: see ``ExportFormat`` for why a derived
    /// estimate sitting beside recorded money is a thing a spreadsheet sums.
    let fuelMilesPerGallon: ExportDecimal?

    /// What the driver recorded a gallon of fuel costing, as the assumption this
    /// shift's estimate is worked out under, or `null` if they recorded none.
    ///
    /// In ``currencyCode``, like every other amount here. `"0.00"` is a recorded
    /// price of nothing and is a different fact from `null`, which is no price
    /// recorded at all.
    ///
    /// **It is not a recorded expense.** A fuel purchase the driver recorded
    /// appears in the file's `expenses`, with its own date, category and amount.
    /// Nothing adds the two, and nothing derives one from the other.
    let fuelGasPricePerGallon: ExportAmount?

    /// How much of the shift at least one recorded delivery was open for, with
    /// deliveries worked at the same time counted **once**.
    ///
    /// The already-unioned figure, never the sum of the deliveries' own
    /// durations — a consumer adding up the delivery rows below will get a
    /// larger number, and this is the one that is a duration of something.
    let deliveryActiveSeconds: Int?

    /// The rest of the shift's **working** time. **Not idle time**: it holds
    /// waiting for an offer, repositioning, unpaused breaks and any work the
    /// driver did not record. Paused time is not in it; that is
    /// ``pausedSeconds``.
    let nonDeliverySeconds: Int?

    /// Gross earnings per **working** hour, so a driver who paused mid-shift is
    /// not reported as having earned less per hour for pausing.
    let grossPerWorkingHour: ExportAmount?
    let grossPerDeliveryActiveHour: ExportAmount?

    /// Gross earnings per **recorded** mile. The denominator is what the route
    /// measured, which is normally less than the miles driven.
    let grossPerRecordedMile: ExportAmount?

    let deliveredCount: Int
    let cancelledCount: Int

    /// The deliveries recorded during this shift, in the order they were
    /// accepted.
    let deliveries: [DeliveryExportRecord]

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, elapsedSeconds, pausedSeconds, workingSeconds, pauseCount
        case currencyCode, grossEarnings, route
        case fuelMilesPerGallon, fuelGasPricePerGallon
        case deliveryActiveSeconds, nonDeliverySeconds
        case grossPerWorkingHour, grossPerDeliveryActiveHour, grossPerRecordedMile
        case deliveredCount, cancelledCount, deliveries
    }

    /// Written with explicit `null`s. See ``ExportDocument`` for why.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encodeAlways(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encodeAlways(pausedSeconds, forKey: .pausedSeconds)
        try container.encodeAlways(workingSeconds, forKey: .workingSeconds)
        try container.encode(pauseCount, forKey: .pauseCount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encodeAlways(grossEarnings, forKey: .grossEarnings)
        try container.encode(route, forKey: .route)
        try container.encodeAlways(fuelMilesPerGallon, forKey: .fuelMilesPerGallon)
        try container.encodeAlways(fuelGasPricePerGallon, forKey: .fuelGasPricePerGallon)
        try container.encodeAlways(deliveryActiveSeconds, forKey: .deliveryActiveSeconds)
        try container.encodeAlways(nonDeliverySeconds, forKey: .nonDeliverySeconds)
        try container.encodeAlways(grossPerWorkingHour, forKey: .grossPerWorkingHour)
        try container.encodeAlways(grossPerDeliveryActiveHour, forKey: .grossPerDeliveryActiveHour)
        try container.encodeAlways(grossPerRecordedMile, forKey: .grossPerRecordedMile)
        try container.encode(deliveredCount, forKey: .deliveredCount)
        try container.encode(cancelledCount, forKey: .cancelledCount)
        try container.encode(deliveries, forKey: .deliveries)
    }
}

/// What a shift's route measured, and how far it can be trusted.
///
/// A single boolean would throw away most of what the domain already knows. A
/// route can be absent, present but unmeasurable, measured and apparently
/// continuous, or measured with known gaps in it, and those are four different
/// things to tell a reader of the file. The vocabulary is
/// ``RouteDistance``'s and ``RouteQuality``'s, unchanged.
nonisolated struct ShiftRouteExport: Equatable, Sendable, Codable {
    /// Whether a distance could be measured, and if not, why.
    nonisolated enum Status: String, Equatable, Sendable, Codable {
        /// At least one unbroken stretch of capture contributed distance.
        case measured
        /// Positions were recorded, but no two of them were captured
        /// continuously, so there is no stretch to measure along.
        case notEnoughRouteRecorded
        /// The shift retained no usable position at all.
        case noRouteRecorded
    }

    let status: Status

    /// Whether the distance is known to be **less than the distance driven** —
    /// capture stopped at least once, or the route predates recorded
    /// continuity.
    let isPartial: Bool

    /// `null` when nothing was measured. Never `0`: "no distance could be
    /// measured" is not "the vehicle did not move".
    let recordedDistanceMetres: Double?

    /// The same measurement in miles, **derived** from the metres above.
    let recordedDistanceMiles: Double?

    /// Unbroken stretches of capture that contributed distance.
    let segmentCount: Int

    /// Stretches of the shift the route does not account for.
    let gapCount: Int

    /// Stored positions the calculation could use.
    let usableSampleCount: Int

    /// True for a route recorded before DashPilot tracked capture continuity,
    /// whose short breaks cannot be detected at all.
    let usesInferredContinuity: Bool

    init(_ distance: RouteDistance) {
        status = if distance.isMeasured {
            .measured
        } else {
            distance.usableSampleCount == 0 ? .noRouteRecorded : .notEnoughRouteRecorded
        }
        // Only a route that measured something can be *partial*. A shift with
        // nothing usable is missing entirely, which `status` states and which
        // "partial" would understate — the same rule `RouteQuality` applies.
        isPartial = distance.isMeasured && distance.isPartial
        recordedDistanceMetres = ExportDistance.metres(of: distance)
        recordedDistanceMiles = ExportDistance.miles(of: distance)
        segmentCount = distance.segmentCount
        gapCount = distance.gapCount
        usableSampleCount = distance.usableSampleCount
        usesInferredContinuity = distance.usesInferredContinuity
    }

    private enum CodingKeys: String, CodingKey {
        case status, isPartial, recordedDistanceMetres, recordedDistanceMiles
        case segmentCount, gapCount, usableSampleCount, usesInferredContinuity
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(isPartial, forKey: .isPartial)
        try container.encodeAlways(recordedDistanceMetres, forKey: .recordedDistanceMetres)
        try container.encodeAlways(recordedDistanceMiles, forKey: .recordedDistanceMiles)
        try container.encode(segmentCount, forKey: .segmentCount)
        try container.encode(gapCount, forKey: .gapCount)
        try container.encode(usableSampleCount, forKey: .usableSampleCount)
        try container.encode(usesInferredContinuity, forKey: .usesInferredContinuity)
    }
}

/// One delivery in an exported shift.
///
/// Every timestamp here exists because the driver tapped a control. A delivery
/// they did not record is not in the file, and nothing was imported from a
/// delivery platform.
///
/// The pickup place appears as the **name the driver typed** and nothing else.
/// The normalised key the catalogue matches on is an internal rule that is
/// allowed to improve; exporting it would publish an implementation detail as
/// though it were an identifier, and would let a consumer group places by a
/// rule this app is free to change tomorrow.
nonisolated struct DeliveryExportRecord: Equatable, Sendable, Codable {
    /// The delivery's own persisted identifier, for the reason
    /// ``ShiftExportRecord/id`` is exported.
    let id: UUID

    /// What the interface calls this delivery within its shift — `Delivery 2`
    /// is `number: 2`. A **local display number**, not an order identifier: it
    /// comes from the order the shift accepted its deliveries in, and nobody
    /// outside this app would recognise it.
    let number: Int

    /// Which **accepted offer** within this shift the delivery arrived in, or
    /// `null` for a delivery that records none.
    ///
    /// The grouping key, and the whole of what this format says about offers.
    /// Two deliveries of one shift carrying the same number were accepted
    /// together, in one act; two carrying different numbers were two decisions,
    /// however much their times overlap. It is scoped to the shift that contains
    /// them, exactly as ``number`` is.
    ///
    /// A **local display number** like ``number``, counted from the order the
    /// shift accepted its offers in. It is not a platform's offer identifier,
    /// and DashPilot has never seen one: an offer here is a grouping the driver
    /// recorded, not a message anything sent.
    ///
    /// Deliberately the only offer field. There is no offer object, no offer
    /// total, no offer duration and no offer rate anywhere in this format: an
    /// offer holds no money and no time of its own, and a figure derived from
    /// one would be a claim this app cannot support. A consumer that wants the
    /// deliveries of one offer groups the shift's `deliveries` by this key.
    ///
    /// `null` appears for a delivery holding no offer, which this build cannot
    /// produce and which a store migrated to schema 12 does not contain. It is
    /// written rather than assumed for the reason every optional here is.
    let offerNumber: Int?

    /// `accepted`, `arrivedAtPickup`, `pickedUp`, `delivered` or `cancelled` —
    /// ``DeliveryState``'s own vocabulary. A cancelled delivery is exported as
    /// what it is and is never counted as completed.
    let state: DeliveryState

    let acceptedAt: Date
    let arrivedAtPickupAt: Date?
    let pickedUpAt: Date?
    let deliveredAt: Date?
    let cancelledAt: Date?

    /// The spelling the driver chose, or `null` when they named no place.
    let pickupPlaceName: String?

    /// The **recorded** wait: `pickedUpAt − arrivedAtPickupAt`, and only when
    /// both ends exist and are in order. Nothing here is predicted, and a
    /// delivery cancelled before the pickup contributes no wait rather than a
    /// wait of zero.
    let pickupWaitSeconds: Int?

    /// Acceptance to completion, for a delivery that was actually delivered.
    let acceptedToDeliveredSeconds: Int?

    /// The amount recorded against **this delivery**, or `null` if none was.
    /// Independent of the shift's own amount in both directions.
    let grossEarnings: ExportAmount?

    /// What the driver said they **expected** this delivery to pay, or `null` if
    /// they said nothing.
    ///
    /// **Not earnings, and never a substitute for ``grossEarnings``.** It was
    /// entered while the delivery was still in progress, from whatever the
    /// driver saw when they accepted the order; nothing confirmed it and nothing
    /// was paid on it. A delivery may carry this with `grossEarnings` still
    /// `null`, which means the driver expected an amount and has not recorded
    /// what the delivery actually paid. That is not a delivery that earned this
    /// figure.
    ///
    /// It is in the file so that a fact the driver entered is not silently
    /// dropped on the way out, since an export is the only way anything leaves
    /// DashPilot, and it appears **only here, on the delivery that carries
    /// it**. Nothing sums it, no shift field includes it, no summary figure is
    /// derived from it, and there is no expected counterpart to any total or
    /// rate anywhere in this format. A consumer adding this column to an
    /// earnings figure is adding an expectation to a record of payment.
    let expectedEarnings: ExportAmount?

    /// Every tip this delivery received **outside** ``grossEarnings``, one
    /// record each, oldest first. Always present, and `[]` where none was
    /// recorded.
    ///
    /// Individual facts rather than one summed figure, deliberately. A tip has a
    /// method and a moment as well as an amount, and the method is the part a
    /// driver acts on: cash was handed over at the door and is already theirs,
    /// while a platform tip arrives in a payout. A single total would say only
    /// how much and would make the file unable to answer either of the other two
    /// questions. ``additionalTipsTotal`` is offered beside them for a consumer
    /// that wants the sum without doing it, never instead of them.
    ///
    /// **None of this is inside ``grossEarnings``.** A tip the platform folded
    /// into what it recorded paying is part of that amount and is not here.
    let additionalTips: [DeliveryTipExportRecord]

    /// ``additionalTips`` added up, or `null` where none was recorded.
    ///
    /// `null` rather than `"0.00"`, by the rule every other absence here
    /// follows: no tip recorded is not a tip of nothing.
    let additionalTipsTotal: ExportAmount?

    /// What this delivery actually paid: ``grossEarnings`` plus
    /// ``additionalTipsTotal``.
    ///
    /// **`null` whenever ``grossEarnings`` is `null`**, even where tips were
    /// recorded, and that is the field's whole point. A delivery carrying a cash
    /// tip and no platform amount did not earn the tip; it earned the tip plus
    /// an amount nobody wrote down, and a file that reported the tip as the
    /// delivery's earnings would be inventing the rest. The same delivery
    /// contributes nothing to `summary.deliveryEarnings` and counts against its
    /// coverage, exactly as a delivery with no amount at all always has.
    let effectiveEarnings: ExportAmount?

    /// This delivery's ``effectiveEarnings`` over its own lifecycle. Never
    /// summed or averaged with another delivery's: overlapping deliveries share
    /// minutes.
    ///
    /// Renamed from `grossPerDeliveryHour`, which is half of why this format is
    /// at version 4. The numerator moved from the platform amount to what the
    /// delivery actually paid, and a name saying `gross` while dividing
    /// something else is the one change a reader could not detect.
    let effectiveEarningsPerDeliveryHour: ExportAmount?

    private enum CodingKeys: String, CodingKey {
        case id, number, offerNumber, state, acceptedAt, arrivedAtPickupAt, pickedUpAt, deliveredAt, cancelledAt
        case pickupPlaceName, pickupWaitSeconds, acceptedToDeliveredSeconds
        case grossEarnings, expectedEarnings
        case additionalTips, additionalTipsTotal, effectiveEarnings
        case effectiveEarningsPerDeliveryHour
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encodeAlways(offerNumber, forKey: .offerNumber)
        try container.encode(state, forKey: .state)
        try container.encode(acceptedAt, forKey: .acceptedAt)
        try container.encodeAlways(arrivedAtPickupAt, forKey: .arrivedAtPickupAt)
        try container.encodeAlways(pickedUpAt, forKey: .pickedUpAt)
        try container.encodeAlways(deliveredAt, forKey: .deliveredAt)
        try container.encodeAlways(cancelledAt, forKey: .cancelledAt)
        try container.encodeAlways(pickupPlaceName, forKey: .pickupPlaceName)
        try container.encodeAlways(pickupWaitSeconds, forKey: .pickupWaitSeconds)
        try container.encodeAlways(acceptedToDeliveredSeconds, forKey: .acceptedToDeliveredSeconds)
        try container.encodeAlways(grossEarnings, forKey: .grossEarnings)
        try container.encodeAlways(expectedEarnings, forKey: .expectedEarnings)
        try container.encode(additionalTips, forKey: .additionalTips)
        try container.encodeAlways(additionalTipsTotal, forKey: .additionalTipsTotal)
        try container.encodeAlways(effectiveEarnings, forKey: .effectiveEarnings)
        try container.encodeAlways(effectiveEarningsPerDeliveryHour, forKey: .effectiveEarningsPerDeliveryHour)
    }
}

/// One tip a delivery received outside what the platform recorded paying for it.
///
/// Three facts and nothing else: what it was, how it arrived, and when the
/// driver recorded it. There is no payer, no order reference, no payout batch
/// and no identifier of anything outside DashPilot, because none of that is
/// recorded: a tip is here because the driver typed it.
nonisolated struct DeliveryTipExportRecord: Equatable, Sendable, Codable {
    /// The tip's own persisted identifier, for the reason
    /// ``DeliveryExportRecord/id`` is exported.
    let id: UUID

    /// Always present, and always more than zero: a tip of nothing is refused
    /// on the way in rather than stored, so there is no absence to express here.
    let amount: ExportAmount

    /// `cash` or `platform`, which is ``DeliveryTipMethod``'s own vocabulary, or
    /// `null` for a stored value this build cannot name.
    ///
    /// `null` rather than a guess. Both words say something definite about where
    /// the money came from, and picking one for an unrecognised value would
    /// invent it; the amount is still exact and still counts, because how much
    /// arrived is a separate question from how it arrived.
    let method: DeliveryTipMethod?

    /// When the driver **recorded** the tip.
    ///
    /// Not when the money changed hands, and the field is named for what it is.
    /// DashPilot never asked for that second time and does not hold it; no
    /// figure anywhere is derived from this one, and a tip belongs to the period
    /// its delivery's shift does.
    let recordedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, amount, method, recordedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(amount, forKey: .amount)
        try container.encodeAlways(method, forKey: .method)
        try container.encode(recordedAt, forKey: .recordedAt)
    }
}

// MARK: Explicit nulls

nonisolated extension KeyedEncodingContainer {
    /// Encodes an optional as an explicit `null` rather than omitting the key.
    ///
    /// Swift's synthesised encoding uses `encodeIfPresent`, which drops the key
    /// entirely. That is the wrong contract for this file: a reader would have
    /// to know the full set of keys to tell "DashPilot did not record this" from
    /// "this version of DashPilot does not have this field". Writing `null`
    /// makes every record the same shape and says the absence out loud.
    mutating func encodeAlways(_ value: (some Encodable)?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
