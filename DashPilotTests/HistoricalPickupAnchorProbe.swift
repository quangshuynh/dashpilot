import Foundation
import SwiftData
@testable import DashPilot

/// The derivation under investigation on `investigate/historical-pickup-anchor`:
/// whether a position for a pickup can be read back out of data DashPilot
/// already stores, without adding a coordinate to `PickupPlace` or `Delivery`.
///
/// **Nothing here is production code and nothing here is shipped.** It lives in
/// the test target on purpose, the same way `RouteCaptureWriteProbe` does: the
/// question was "could this work", and the honest way to answer it is to build
/// the thing and measure it rather than to reason about it. If the answer turns
/// out to be no, this file is the record of why, and deleting it would delete
/// the evidence.
///
/// ## The join it rests on
///
/// Every fact it reads is already in the store, and this is the whole of the
/// path between them:
///
/// - `Delivery.shift` is a to-one reference, the inverse of `Shift.deliveries`
///   (`.cascade`). A delivery therefore names exactly one shift, and a deleted
///   shift takes its deliveries with it.
/// - `Delivery.arrivedAtPickupAt` is the moment the driver tapped **Arrived at
///   Pickup**. It is optional, monotonic against the rest of the lifecycle
///   (`markArrivedAtPickup(at:)` refuses a timestamp before the last event),
///   and it is the only timestamp in the model that claims the driver was
///   *at* the pickup.
/// - `Delivery.pickupPlace` is an optional `.nullify` reference to the place the
///   driver named. It carries no coordinate, and this derivation does not give
///   it one.
/// - `RouteSample.shift` is the **only** declaration of a shift's route;
///   `Shift` holds no collection. Every route read is therefore a fetch against
///   `$0.shift?.id`, which is what makes a *bounded* read possible at all.
/// - `RouteSample.timestamp` is when the platform fixed the position, not when
///   it was delivered, so it is directly comparable with a lifecycle timestamp.
/// - `RouteSample.horizontalAccuracy` is stored, in metres. `RoutePoint` drops
///   it and the mileage walk never reads it, so this is the first calculation in
///   the project that weighs a stored position by how good it is.
/// - `RouteSample.captureSessionID` is `nil` only for rows written before schema
///   v3. Two rows sharing a non-nil identifier were recorded with capture
///   running throughout, and a change of identifier is capture having stopped.
///
/// ## What the filter already guarantees about a stored row
///
/// Every row exists because `RouteSampleFilter` accepted it, so an anchor read
/// from one inherits: a coordinate the Earth has and not `(0, 0)`, a finite
/// non-negative accuracy of at most 100 m, a fix no more than 30 s old when it
/// was judged, a timestamp at or after the shift start and strictly after the
/// previous row's, and at least 5 m of movement from the previous row that no
/// physically impossible speed explains.
///
/// The last of those is the fact this investigation turns around. **A stationary
/// vehicle writes nothing**, so the last row before a pickup wait describes the
/// approach rather than the dwell — which was the hypothesis — and the absence
/// of rows across the dwell means either that the vehicle did not move or that
/// capture was not running. See ``StationaryBracket`` for the part of that
/// ambiguity the store can actually settle.
enum HistoricalPickupAnchorProbe {}

// MARK: - The stored position, as this derivation reads it

extension HistoricalPickupAnchorProbe {
    /// One retained position with its accuracy and its capture session kept.
    ///
    /// A plain value rather than a `RouteSample`, so the derivation, the
    /// clustering and the proximity question can all be exercised without a
    /// store. It is `RoutePoint` plus `horizontalAccuracy`: the mileage walk
    /// deliberately drops that field because no distance rule reads it, and this
    /// derivation is the case that does.
    struct CapturedPosition: Equatable, Sendable {
        var timestamp: Date
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var captureSessionID: UUID?

        init(
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            captureSessionID: UUID?
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.captureSessionID = captureSessionID
        }

        init(_ sample: RouteSample) {
            self.init(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                horizontalAccuracy: sample.horizontalAccuracy,
                captureSessionID: sample.captureSessionID
            )
        }

        /// The total order the route is read in, matching `Shift.routeSamples()`
        /// and `RouteMileageAccumulator.orderedUsablePoints(in:)`: timestamp
        /// first, then coordinate, because a timestamp alone is not a total
        /// order and two fixes at one instant must not swap between two reads.
        static func recordedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            if lhs.latitude != rhs.latitude { return lhs.latitude < rhs.latitude }
            return lhs.longitude < rhs.longitude
        }
    }

    /// Metres between two positions, through the project's own calculation.
    ///
    /// `GeographicDistance` and nothing else: capture, mileage and this
    /// derivation must not disagree about how far apart two fixes are, and
    /// nothing here reaches for Core Location, MapKit or a geocoder.
    static func metres(from start: CapturedPosition, to end: CapturedPosition) -> Double {
        GeographicDistance.metres(
            fromLatitude: start.latitude,
            longitude: start.longitude,
            toLatitude: end.latitude,
            longitude: end.longitude
        )
    }
}

// MARK: - What an anchor is

extension HistoricalPickupAnchorProbe {
    /// Why the absence of rows across a pickup wait can or cannot be read as the
    /// vehicle having stayed put.
    ///
    /// This is the part of the ambiguity `context.md` recorded as fatal that the
    /// store can actually settle, and it is only settleable **historically**. A
    /// live detector looking at a stationary vehicle has no future to consult.
    /// A finished delivery does: the driver drove away afterwards, and the row
    /// that records them driving away carries a capture session identifier.
    ///
    /// If the row before the wait and the row after it share one non-nil
    /// session, capture did not stop between them — every path that stops it
    /// clears the identifier and the next accepted row opens a new one
    /// (`stopCapturing()`, and the pause, end, permission-loss, background and
    /// relaunch routes that call it). So the interval was **measured and
    /// empty**, not unmeasured.
    ///
    /// What that proves is bounded and worth stating exactly: every fix taken in
    /// between was either within `RouteSampleFilter.minimumDistance` (5 m) of
    /// the anchor, or was rejected for some other reason. Sustained poor
    /// accuracy is the residual hole — an urban canyon reporting more than 100 m
    /// for ten minutes writes nothing while the vehicle drives away, and looks
    /// exactly like a vehicle standing still. Nothing in the store closes that,
    /// and this investigation does not pretend otherwise.
    enum StationaryBracket: Equatable, Sendable {
        /// The row after the wait shares the anchor's capture session, so
        /// capture ran across the whole wait and recorded no movement.
        case proven
        /// There is no row after the wait within the bracket window, so the
        /// shift stopped recording at the pickup and nothing can be said.
        case unmeasured
        /// There is a row after the wait, but capture stopped and restarted in
        /// between, so the vehicle may have moved unrecorded.
        case broken
        /// Capture never stopped, but the next recorded position is too far from
        /// the anchor for the vehicle to have been standing still. Something in
        /// between went unrecorded for a reason that was not stillness.
        case departed

        var isProven: Bool { self == .proven }
    }

    /// A position derived for one completed pickup, held in memory and nowhere
    /// else.
    ///
    /// **Never persisted, never exported, never logged.** It carries the
    /// delivery and shift identities so that repeated observations can be judged
    /// independent, and it carries the two timestamps so that the lag between
    /// the last recorded movement and the driver's tap is visible rather than
    /// assumed away.
    struct DerivedAnchor: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        /// The anchor fix's own radius of uncertainty, in metres.
        var horizontalAccuracy: Double
        /// When the anchor position was fixed.
        var observedAt: Date
        /// When the driver said they had arrived.
        var arrivedAt: Date
        var shiftID: UUID
        var deliveryID: UUID
        var bracket: StationaryBracket

        /// How long before the tap the anchor position was fixed.
        ///
        /// The whole error budget of the unbracketed form: whatever the vehicle
        /// covered in this interval is the distance between the anchor and where
        /// the driver actually was. A bracketed anchor's lag is not an error,
        /// because the bracket says the vehicle did not move across it.
        var lag: TimeInterval { arrivedAt.timeIntervalSince(observedAt) }

        var position: CapturedPosition {
            CapturedPosition(
                timestamp: observedAt,
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: horizontalAccuracy,
                captureSessionID: nil
            )
        }
    }
}

// MARK: - The rules an anchor has to satisfy

extension HistoricalPickupAnchorProbe {
    /// The bounds a candidate anchor is judged against.
    ///
    /// Every one of them is a *rejection* rule. There is no interpolation, no
    /// extrapolation, no smoothing and no fallback: a pickup either has a
    /// position the store can support or it has none, which is the same standard
    /// the rest of the project applies to a missing figure.
    ///
    /// The values are not calibrations. They are the bounds the investigation
    /// compares against each other, and
    /// `HistoricalPickupAnchorWindowTests` reports what each one costs.
    struct AnchorPolicy: Equatable, Sendable {
        /// How far before the tap the derivation will look for a row, in
        /// seconds.
        ///
        /// The unbracketed form's error budget: at an approach speed of 10 m/s,
        /// a lookback of `W` seconds admits an anchor up to `10 × W` metres from
        /// where the driver actually was.
        var lookback: TimeInterval

        /// Largest radius of uncertainty the anchor fix may carry, in metres.
        ///
        /// Tighter than `RouteSampleFilter.maximumHorizontalAccuracy` (100 m) on
        /// purpose. A fix good enough to say which road a vehicle is on is not
        /// good enough to say which building it stopped at.
        var maximumHorizontalAccuracy: Double

        /// Whether an anchor row must carry a capture session identifier.
        ///
        /// A pre-v3 row does not, and its continuity is unknown rather than
        /// proven. Requiring one costs nothing on any store written since v3.
        var requiresCaptureSession: Bool

        /// Whether the wait must be bracketed by proven continuous capture.
        ///
        /// The strong form. See ``StationaryBracket``.
        var requiresStationaryBracket: Bool

        /// How long after the anchor the departure row may be and still bracket
        /// the wait, in seconds.
        ///
        /// A sanity bound rather than a rule about driving: a single capture
        /// session that recorded no movement for hours is more likely a stalled
        /// stream than a vehicle standing still, and a wait that long is not a
        /// pickup wait.
        var maximumBracketInterval: TimeInterval

        /// How far from the anchor the departure row may be and still bracket
        /// the wait, in metres.
        ///
        /// **This is what closes most of the poor-accuracy hole.** A vehicle
        /// that genuinely stood still is recorded again within a fix or two of
        /// pulling away, so the departure sits tens of metres from the anchor. A
        /// vehicle that drove on while every fix was too imprecise to keep
        /// writes nothing either, but the row that finally lands when accuracy
        /// recovers is wherever it got to, which is far. The two cases are
        /// indistinguishable by session alone and distinguishable by this.
        ///
        /// It is a rejection, not a correction: a departure beyond it means the
        /// wait was not measured, not that the anchor should be moved.
        var maximumDepartureDistance: Double

        init(
            lookback: TimeInterval,
            maximumHorizontalAccuracy: Double,
            requiresCaptureSession: Bool = true,
            requiresStationaryBracket: Bool = false,
            maximumBracketInterval: TimeInterval = 3_600,
            maximumDepartureDistance: Double = 150
        ) {
            self.lookback = lookback
            self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
            self.requiresCaptureSession = requiresCaptureSession
            self.requiresStationaryBracket = requiresStationaryBracket
            self.maximumBracketInterval = maximumBracketInterval
            self.maximumDepartureDistance = maximumDepartureDistance
        }

        /// Sixty seconds and 35 m, with no bracket required.
        ///
        /// The tightest defensible window: at any urban speed the vehicle
        /// covered at most a few hundred metres since the anchor, and usually
        /// far less because it was slowing down.
        static let tight = AnchorPolicy(lookback: 60, maximumHorizontalAccuracy: 35)

        /// Three minutes and 65 m.
        ///
        /// Admits the driver who parks, walks in and taps a minute or two later,
        /// at the cost of admitting the driver who was still on a main road
        /// three minutes ago.
        static let moderate = AnchorPolicy(lookback: 180, maximumHorizontalAccuracy: 65)

        /// Ten minutes and 100 m, the filter's own accuracy ceiling.
        ///
        /// Deliberately too loose to be a proposal. It exists so the cost of
        /// looseness is a measured number rather than an assertion.
        static let wide = AnchorPolicy(lookback: 600, maximumHorizontalAccuracy: 100)

        /// Ten minutes, 50 m, and a proven stationary bracket.
        ///
        /// The form this investigation actually argues for. The long lookback is
        /// safe *because* of the bracket: an anchor eight minutes before the tap
        /// is admitted only when the store can show the vehicle did not move in
        /// those eight minutes, which makes the lag stop being an error term.
        static let bracketed = AnchorPolicy(
            lookback: 600,
            maximumHorizontalAccuracy: 50,
            requiresStationaryBracket: true
        )

        static let allVariants: [(name: String, policy: AnchorPolicy)] = [
            ("tight", .tight),
            ("moderate", .moderate),
            ("wide", .wide),
            ("bracketed", .bracketed)
        ]
    }
}

// MARK: - Deriving one anchor

extension HistoricalPickupAnchorProbe {
    /// Why a pickup produced no anchor.
    ///
    /// Reported rather than collapsed into `nil` so the scenarios can assert
    /// *which* rule refused, and so the report can say where recall is actually
    /// lost. Every case names a rule, never a position.
    enum AnchorRefusal: String, Error, Equatable, Sendable, CaseIterable {
        /// The delivery has no `arrivedAtPickup`, so there is no moment to
        /// anchor to.
        case noArrival
        /// The delivery is not attached to a shift, so there is no route to
        /// read.
        case noShift
        /// The shift has no retained row at or before the arrival at all.
        case noRouteBeforeArrival
        /// Rows exist, but the newest one before the arrival is older than the
        /// lookback allows.
        case outsideLookback
        /// The anchor row's own fix is too imprecise to name a building.
        case poorAccuracy
        /// The anchor row predates capture-session tracking, so its continuity
        /// is unknown.
        case unknownContinuity
        /// A stationary bracket was required and the store cannot prove one.
        case unprovenStationarity
    }

    /// Derives the anchor for one arrival from a route already narrowed to that
    /// shift.
    ///
    /// `route` may arrive in any order and may hold anything the store returned;
    /// it is ordered here by the same total order the rest of the project reads a
    /// route in. It must be the *whole* of the shift's route within the window
    /// being considered, because the stationary bracket's claim is that there is
    /// nothing between the anchor and the departure, and a truncated read would
    /// make that claim out of a gap in the read rather than a gap in the route.
    static func anchor(
        forArrivalAt arrivedAt: Date,
        deliveryID: UUID,
        shiftID: UUID,
        in route: [CapturedPosition],
        under policy: AnchorPolicy
    ) -> Result<DerivedAnchor, AnchorRefusal> {
        let ordered = route.sorted(by: CapturedPosition.recordedBefore)

        guard let anchorIndex = ordered.lastIndex(where: { $0.timestamp <= arrivedAt }) else {
            return .failure(.noRouteBeforeArrival)
        }
        let candidate = ordered[anchorIndex]

        guard arrivedAt.timeIntervalSince(candidate.timestamp) <= policy.lookback else {
            return .failure(.outsideLookback)
        }
        guard candidate.horizontalAccuracy <= policy.maximumHorizontalAccuracy else {
            return .failure(.poorAccuracy)
        }
        if policy.requiresCaptureSession, candidate.captureSessionID == nil {
            return .failure(.unknownContinuity)
        }

        let bracket = self.bracket(
            after: candidate,
            in: ordered[ordered.index(after: anchorIndex)...],
            under: policy
        )
        if policy.requiresStationaryBracket, !bracket.isProven {
            return .failure(.unprovenStationarity)
        }

        return .success(
            DerivedAnchor(
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                horizontalAccuracy: candidate.horizontalAccuracy,
                observedAt: candidate.timestamp,
                arrivedAt: arrivedAt,
                shiftID: shiftID,
                deliveryID: deliveryID,
                bracket: bracket
            )
        )
    }

    /// Judges the first row recorded after the anchor.
    ///
    /// `following` must begin immediately after the anchor in the shift's own
    /// order. The first element is therefore the departure, and the emptiness of
    /// the interval between is a property of the route rather than something
    /// checked here.
    static func bracket(
        after anchor: CapturedPosition,
        in following: ArraySlice<CapturedPosition>,
        under policy: AnchorPolicy
    ) -> StationaryBracket {
        guard let departure = following.first else { return .unmeasured }
        guard departure.timestamp.timeIntervalSince(anchor.timestamp) <= policy.maximumBracketInterval else {
            return .unmeasured
        }
        guard let anchorSession = anchor.captureSessionID,
              let departureSession = departure.captureSessionID,
              anchorSession == departureSession
        else {
            return .broken
        }
        guard metres(from: anchor, to: departure) <= policy.maximumDepartureDistance else {
            return .departed
        }
        return .proven
    }
}

// MARK: - Reading anchors out of a store, without scanning it

extension HistoricalPickupAnchorProbe {
    /// What one bounded derivation cost and how it was paid for.
    struct DerivationCost: Equatable, Sendable {
        /// Fetches issued against `RouteSample`.
        var routeFetchCount = 0
        /// Rows those fetches returned, in total.
        var fetchedRowCount = 0
        /// Deliveries considered.
        var deliveryCount = 0
    }

    /// Derives a place's anchors with timestamp-bounded fetches, touching no row
    /// outside the windows the arrivals themselves define.
    ///
    /// **This is the shape the performance question turns on.** The naive
    /// derivation reads a shift's whole route through `Shift.routeSamples()` and
    /// walks it, which is proportional to the length of every shift the place
    /// appears in. This one issues at most two limited fetches per delivery:
    ///
    /// - the newest row in `(arrivedAt − lookback, arrivedAt]`, sorted
    ///   descending with `fetchLimit = 1`, which is the anchor;
    /// - the oldest row strictly after it and within the bracket window, sorted
    ///   ascending with `fetchLimit = 1`, which is the departure.
    ///
    /// The second fetch returning the *first* row after the anchor is what makes
    /// the emptiness between them a fact rather than an assumption, so the
    /// bounded read proves exactly what the whole-route read proves.
    ///
    /// `limit` caps how many of a place's deliveries are consulted, newest
    /// first, so the cost is bounded by the policy rather than by how long the
    /// driver has used the app.
    ///
    /// Two rows sharing a timestamp are not distinguished by the departure
    /// fetch's `>` bound, exactly as `RouteMileageAccumulator` collapses them:
    /// capture cannot produce them, since the filter rejects a duplicate
    /// timestamp.
    @MainActor
    static func anchors(
        for place: PickupPlace,
        in context: ModelContext,
        under policy: AnchorPolicy,
        limit: Int = 12,
        cost: inout DerivationCost
    ) -> [DerivedAnchor] {
        let arrivals = place.deliveries
            .compactMap { delivery -> (delivery: Delivery, arrivedAt: Date, shiftID: UUID)? in
                guard let arrivedAt = delivery.arrivedAtPickupAt, let shiftID = delivery.shift?.id else {
                    return nil
                }
                return (delivery, arrivedAt, shiftID)
            }
            .sorted { lhs, rhs in
                if lhs.arrivedAt != rhs.arrivedAt { return lhs.arrivedAt > rhs.arrivedAt }
                return lhs.delivery.id.uuidString < rhs.delivery.id.uuidString
            }
            .prefix(limit)

        var derived: [DerivedAnchor] = []
        for arrival in arrivals {
            cost.deliveryCount += 1
            guard let candidate = newestRow(
                forShift: arrival.shiftID,
                notLaterThan: arrival.arrivedAt,
                notEarlierThan: arrival.arrivedAt.addingTimeInterval(-policy.lookback),
                in: context,
                cost: &cost
            ) else { continue }

            guard candidate.horizontalAccuracy <= policy.maximumHorizontalAccuracy else { continue }
            if policy.requiresCaptureSession, candidate.captureSessionID == nil { continue }

            let departure = oldestRow(
                forShift: arrival.shiftID,
                laterThan: candidate.timestamp,
                notLaterThan: candidate.timestamp.addingTimeInterval(policy.maximumBracketInterval),
                in: context,
                cost: &cost
            )
            // The fetch returned the *first* row after the anchor, so a slice
            // holding just it carries exactly the fact the whole-route form
            // reads: what came next, and that nothing came between.
            let following: [CapturedPosition] = departure.map { [$0] } ?? []
            let bracket = self.bracket(after: candidate, in: following[...], under: policy)
            if policy.requiresStationaryBracket, !bracket.isProven { continue }

            derived.append(
                DerivedAnchor(
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    horizontalAccuracy: candidate.horizontalAccuracy,
                    observedAt: candidate.timestamp,
                    arrivedAt: arrival.arrivedAt,
                    shiftID: arrival.shiftID,
                    deliveryID: arrival.delivery.id,
                    bracket: bracket
                )
            )
        }
        return derived
    }

    @MainActor
    private static func newestRow(
        forShift shiftID: UUID,
        notLaterThan upperBound: Date,
        notEarlierThan lowerBound: Date,
        in context: ModelContext,
        cost: inout DerivationCost
    ) -> CapturedPosition? {
        var descriptor = FetchDescriptor<RouteSample>(
            predicate: #Predicate { sample in
                sample.shift?.id == shiftID
                    && sample.timestamp <= upperBound
                    && sample.timestamp >= lowerBound
            },
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.latitude, order: .reverse),
                SortDescriptor(\.longitude, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        cost.routeFetchCount += 1
        let rows = (try? context.fetch(descriptor)) ?? []
        cost.fetchedRowCount += rows.count
        return rows.first.map(CapturedPosition.init)
    }

    @MainActor
    private static func oldestRow(
        forShift shiftID: UUID,
        laterThan lowerBound: Date,
        notLaterThan upperBound: Date,
        in context: ModelContext,
        cost: inout DerivationCost
    ) -> CapturedPosition? {
        var descriptor = FetchDescriptor<RouteSample>(
            predicate: #Predicate { sample in
                sample.shift?.id == shiftID
                    && sample.timestamp > lowerBound
                    && sample.timestamp <= upperBound
            },
            sortBy: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.latitude),
                SortDescriptor(\.longitude)
            ]
        )
        descriptor.fetchLimit = 1
        cost.routeFetchCount += 1
        let rows = (try? context.fetch(descriptor)) ?? []
        cost.fetchedRowCount += rows.count
        return rows.first.map(CapturedPosition.init)
    }
}

// MARK: - Whether repeated pickups agree

extension HistoricalPickupAnchorProbe {
    /// The bounds a place's own history is judged against before it is allowed a
    /// representative position.
    struct ClusterPolicy: Equatable, Sendable {
        /// Fewest independent observations a place may be described by.
        var minimumObservations: Int

        /// How far from the medoid an observation may sit and still be counted
        /// as agreeing with it, in metres.
        ///
        /// Sized for a parking area rather than for GPS error: repeated pickups
        /// at one restaurant are not repeated stops at one *point*, they are
        /// stops anywhere a vehicle fits.
        var agreementRadius: Double

        /// What share of the observations must agree before the place is
        /// described at all.
        var minimumAgreementFraction: Double

        /// How close together two arrivals in one shift may be and still count
        /// as one visit, in seconds.
        ///
        /// Stacked deliveries are the reason this exists. Two orders collected
        /// from one restaurant four minutes apart are one stop seen twice, and
        /// counting them twice would let a single visit satisfy a quorum meant
        /// to require several.
        var independenceInterval: TimeInterval

        init(
            minimumObservations: Int = 3,
            agreementRadius: Double = 75,
            minimumAgreementFraction: Double = 0.6,
            independenceInterval: TimeInterval = 3_600
        ) {
            self.minimumObservations = minimumObservations
            self.agreementRadius = agreementRadius
            self.minimumAgreementFraction = minimumAgreementFraction
            self.independenceInterval = independenceInterval
        }

        static let standard = ClusterPolicy()
    }

    /// Why a place got no representative position.
    enum ClusterRefusal: String, Error, Equatable, Sendable, CaseIterable {
        /// Too few independent observations to say anything.
        case insufficientHistory
        /// The observations exist but do not agree with each other well enough
        /// for any one of them to stand for the place.
        case observationsDisagree
    }

    /// A place's history, reduced to one of its own observations.
    struct AnchorCluster: Equatable, Sendable {
        /// The **medoid**: the observation with the smallest total distance to
        /// the others.
        ///
        /// Deliberately one of the driver's own recorded positions rather than
        /// an averaged or interpolated one. A mean of coordinates is a place
        /// nobody stopped at, and it would be the app inventing a position and
        /// then treating it as observed. A medoid is a position that actually
        /// happened.
        ///
        /// No ML, no clustering library, no learning: a full pairwise distance
        /// table over at most a dozen points, minimised, with a total order
        /// breaking ties.
        var representative: DerivedAnchor

        /// The furthest agreeing observation's distance from the medoid, in
        /// metres. How wide the place actually is, as observed.
        var agreementRadius: Double

        /// Observations that agreed, including the medoid.
        var agreeingCount: Int

        /// Independent observations considered.
        var consideredCount: Int

        /// Largest distance between any two agreeing observations, in metres.
        var spread: Double
    }

    /// Reduces a place's independent observations to one representative, or
    /// refuses.
    ///
    /// Refusing is the common case by design, and it is the whole safety
    /// argument: a place the driver visited twice, or visited in five places
    /// that disagree, gets no position at all rather than a weak one.
    static func cluster(
        _ anchors: [DerivedAnchor],
        under policy: ClusterPolicy
    ) -> Result<AnchorCluster, ClusterRefusal> {
        let independent = independentObservations(in: anchors, under: policy)
        guard independent.count >= policy.minimumObservations else {
            return .failure(.insufficientHistory)
        }

        let medoid = self.medoid(of: independent)
        let agreeing = independent.filter {
            metres(from: medoid.position, to: $0.position) <= policy.agreementRadius
        }

        guard agreeing.count >= policy.minimumObservations else { return .failure(.observationsDisagree) }
        let fraction = Double(agreeing.count) / Double(independent.count)
        guard fraction >= policy.minimumAgreementFraction else { return .failure(.observationsDisagree) }

        let radius = agreeing.map { metres(from: medoid.position, to: $0.position) }.max() ?? 0
        var spread = 0.0
        for (index, one) in agreeing.enumerated() {
            for other in agreeing[agreeing.index(after: index)...] {
                spread = max(spread, metres(from: one.position, to: other.position))
            }
        }

        return .success(
            AnchorCluster(
                representative: medoid,
                agreementRadius: radius,
                agreeingCount: agreeing.count,
                consideredCount: independent.count,
                spread: spread
            )
        )
    }

    /// One observation per visit, in a deterministic order.
    ///
    /// Arrivals are grouped by shift and walked oldest first; within a shift, an
    /// arrival is kept only when it is more than `independenceInterval` after the
    /// last one kept. Two shifts are always independent of each other.
    static func independentObservations(
        in anchors: [DerivedAnchor],
        under policy: ClusterPolicy
    ) -> [DerivedAnchor] {
        let ordered = anchors.sorted { lhs, rhs in
            if lhs.arrivedAt != rhs.arrivedAt { return lhs.arrivedAt < rhs.arrivedAt }
            return lhs.deliveryID.uuidString < rhs.deliveryID.uuidString
        }

        var lastKeptPerShift: [UUID: Date] = [:]
        var kept: [DerivedAnchor] = []
        for anchor in ordered {
            if let last = lastKeptPerShift[anchor.shiftID],
               anchor.arrivedAt.timeIntervalSince(last) <= policy.independenceInterval {
                continue
            }
            lastKeptPerShift[anchor.shiftID] = anchor.arrivedAt
            kept.append(anchor)
        }
        return kept
    }

    /// The observation closest to all the others.
    ///
    /// Ties are broken by arrival time and then by the delivery's identity, so
    /// two observations equally central cannot swap between two derivations.
    static func medoid(of anchors: [DerivedAnchor]) -> DerivedAnchor {
        precondition(!anchors.isEmpty, "A medoid of nothing is not a position")
        var best = anchors[0]
        var bestTotal = Double.infinity
        for candidate in anchors {
            let total = anchors.reduce(0.0) { $0 + metres(from: candidate.position, to: $1.position) }
            if total < bestTotal
                || (total == bestTotal && (candidate.arrivedAt, candidate.deliveryID.uuidString)
                    < (best.arrivedAt, best.deliveryID.uuidString)) {
                best = candidate
                bestTotal = total
            }
        }
        return best
    }
}

// MARK: - The one question a detector would ask

extension HistoricalPickupAnchorProbe {
    /// The bounds the proximity question is asked under.
    struct ProximityPolicy: Equatable, Sendable {
        /// How close the current position must be to a place's representative,
        /// in metres.
        var matchRadius: Double

        /// How much further away the next-closest place must be before the
        /// closest one is named, in metres.
        ///
        /// The shopping-plaza rule. Two restaurants sharing a car park are two
        /// places whose observed positions are metres apart, and naming either
        /// of them would be a coin toss the driver would read as knowledge.
        var ambiguityMargin: Double

        /// Largest radius of uncertainty the current fix may carry, in metres.
        var maximumHorizontalAccuracy: Double

        init(matchRadius: Double = 60, ambiguityMargin: Double = 40, maximumHorizontalAccuracy: Double = 30) {
            self.matchRadius = matchRadius
            self.ambiguityMargin = ambiguityMargin
            self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
        }

        static let standard = ProximityPolicy()
    }

    /// What the proximity question answers.
    ///
    /// Four outcomes rather than a boolean, because three different things are
    /// all "no" and a detector would act differently on each.
    enum ProximityAnswer: Equatable, Sendable {
        /// Exactly one place is within the radius and no other is close enough
        /// to be confused with it.
        case match(placeID: UUID, metres: Double)
        /// Nothing this driver has picked up from is near here.
        case noMatch
        /// More than one place is near here and they cannot be told apart.
        case ambiguous(placeIDs: [UUID])
        /// No place has enough agreeing history to be asked about.
        case insufficientHistory
        /// The current fix is not good enough to ask the question with.
        case positionTooImprecise
    }

    /// Whether a current stationary position is at a place this driver has
    /// picked up from before.
    ///
    /// `clusters` is the in-memory result of ``cluster(_:under:)`` for each place
    /// with a usable history, keyed by the place's identity. Nothing is read from
    /// a store here and nothing is written to one.
    static func place(
        at current: CapturedPosition,
        among clusters: [UUID: AnchorCluster],
        under policy: ProximityPolicy
    ) -> ProximityAnswer {
        guard current.horizontalAccuracy >= 0,
              current.horizontalAccuracy <= policy.maximumHorizontalAccuracy
        else {
            return .positionTooImprecise
        }
        guard !clusters.isEmpty else { return .insufficientHistory }

        let distances = clusters
            .map { (placeID: $0.key, metres: metres(from: current, to: $0.value.representative.position)) }
            .sorted { lhs, rhs in
                if lhs.metres != rhs.metres { return lhs.metres < rhs.metres }
                return lhs.placeID.uuidString < rhs.placeID.uuidString
            }

        let within = distances.filter { $0.metres <= policy.matchRadius }
        guard let closest = within.first else { return .noMatch }
        guard within.count == 1 else {
            // Two candidates inside the radius are only distinguishable if the
            // second is clearly further. Otherwise the honest answer is that the
            // driver is somewhere near both.
            let runnerUp = within[1]
            guard runnerUp.metres - closest.metres >= policy.ambiguityMargin else {
                return .ambiguous(placeIDs: within.map(\.placeID))
            }
            return .match(placeID: closest.placeID, metres: closest.metres)
        }

        // A place just outside the radius still makes the one inside it
        // ambiguous, because the radius is not a wall the driver parked against.
        if distances.count > 1 {
            let runnerUp = distances[1]
            guard runnerUp.metres - closest.metres >= policy.ambiguityMargin else {
                return .ambiguous(placeIDs: [closest.placeID, runnerUp.placeID])
            }
        }
        return .match(placeID: closest.placeID, metres: closest.metres)
    }
}
