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
/// - **Elapsed time is not delivery active time**, and non-delivery time is not
///   idle time.
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

    /// The whole wall-clock length of the shift, waiting and repositioning
    /// included.
    let elapsedSeconds: Int?

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

    /// How much of the shift at least one recorded delivery was open for, with
    /// deliveries worked at the same time counted **once**.
    ///
    /// The already-unioned figure, never the sum of the deliveries' own
    /// durations — a consumer adding up the delivery rows below will get a
    /// larger number, and this is the one that is a duration of something.
    let deliveryActiveSeconds: Int?

    /// The rest of the shift. **Not idle time**: it holds waiting for an offer,
    /// repositioning, breaks and any work the driver did not record.
    let nonDeliverySeconds: Int?

    let grossPerElapsedHour: ExportAmount?
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
        case id, startedAt, endedAt, elapsedSeconds, currencyCode, grossEarnings, route
        case deliveryActiveSeconds, nonDeliverySeconds
        case grossPerElapsedHour, grossPerDeliveryActiveHour, grossPerRecordedMile
        case deliveredCount, cancelledCount, deliveries
    }

    /// Written with explicit `null`s. See ``ExportDocument`` for why.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encodeAlways(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encodeAlways(grossEarnings, forKey: .grossEarnings)
        try container.encode(route, forKey: .route)
        try container.encodeAlways(deliveryActiveSeconds, forKey: .deliveryActiveSeconds)
        try container.encodeAlways(nonDeliverySeconds, forKey: .nonDeliverySeconds)
        try container.encodeAlways(grossPerElapsedHour, forKey: .grossPerElapsedHour)
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

    /// This delivery's amount over its own lifecycle. Never summed or averaged
    /// with another delivery's: overlapping deliveries share minutes.
    let grossPerDeliveryHour: ExportAmount?

    private enum CodingKeys: String, CodingKey {
        case id, number, state, acceptedAt, arrivedAtPickupAt, pickedUpAt, deliveredAt, cancelledAt
        case pickupPlaceName, pickupWaitSeconds, acceptedToDeliveredSeconds
        case grossEarnings, grossPerDeliveryHour
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
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
        try container.encodeAlways(grossPerDeliveryHour, forKey: .grossPerDeliveryHour)
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
