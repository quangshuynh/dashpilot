import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a delivery's lifecycle does and does not say about a wait at a pickup.
///
/// Every date is an explicit offset from one fixed instant, so nothing here
/// depends on when it runs, and no test needs a store or a rendered view.
@Suite("Pickup wait samples")
struct PickupWaitSampleTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    /// A delivery built by tapping through its lifecycle, exactly as the app
    /// would. Every event is optional so a partial lifecycle is expressible.
    private func delivery(
        accepted: Double = 0,
        arrived: Double? = nil,
        pickedUp: Double? = nil,
        delivered: Double? = nil,
        cancelled: Double? = nil
    ) -> Delivery {
        let shift = Shift(startedAt: at(accepted))
        let delivery = Delivery(shift: shift, acceptedAt: at(accepted))
        if let arrived { try? delivery.markArrivedAtPickup(at: at(arrived)) }
        if let pickedUp { try? delivery.markPickedUp(at: at(pickedUp)) }
        if let delivered { try? delivery.markDelivered(at: at(delivered)) }
        if let cancelled { try? delivery.cancel(at: at(cancelled)) }
        return delivery
    }

    // MARK: The ordinary case

    @Test("A delivery that arrived and then picked up records the gap between them")
    func recordsTheGapBetweenArrivalAndPickup() throws {
        let sample = try #require(PickupWaitSample(delivery(accepted: 0, arrived: 5, pickedUp: 16, delivered: 30)))

        #expect(sample.duration == minutes(11))
        #expect(sample.pickedUpAt == at(16), "The wait is stamped by when it ended")
    }

    @Test("An order waiting on the counter records a wait of no length, not no wait")
    func zeroWaitIsStillASample() throws {
        let sample = try #require(PickupWaitSample(delivery(accepted: 0, arrived: 5, pickedUp: 5, delivered: 20)))

        #expect(sample.duration == 0)
    }

    @Test("Acceptance and delivery are not consulted")
    func onlyTheTwoPickupEventsMatter() throws {
        let early = try #require(PickupWaitSample(delivery(accepted: 0, arrived: 5, pickedUp: 13, delivered: 14)))
        let late = try #require(PickupWaitSample(delivery(accepted: 4, arrived: 5, pickedUp: 13, delivered: 90)))

        #expect(early.duration == late.duration, "Two deliveries that waited the same waited the same")
        #expect(early.duration == minutes(8))
    }

    // MARK: Missing ends

    @Test("A delivery still waiting has no wait to report")
    func stillWaitingRecordsNothing() {
        #expect(PickupWaitSample(delivery(accepted: 0, arrived: 5)) == nil)
    }

    @Test("A delivery that never recorded an arrival has no wait to report")
    func missingArrivalRecordsNothing() {
        let delivery = delivery(accepted: 0)
        // Picking up without arriving is refused, so this is the state a
        // delivery is actually in: accepted, and nothing else.
        #expect(delivery.arrivedAtPickupAt == nil)
        #expect(PickupWaitSample(delivery) == nil)
    }

    @Test("A delivery that recorded neither end has no wait to report")
    func acceptedOnlyRecordsNothing() {
        #expect(PickupWaitSample(delivery(accepted: 0)) == nil)
    }

    // MARK: Cancellation

    @Test("A delivery cancelled before pickup contributes nothing, however long it stood there")
    func cancelledBeforePickupContributesNothing() {
        let abandoned = delivery(accepted: 0, arrived: 5, cancelled: 45)

        #expect(abandoned.state == .cancelled)
        #expect(abandoned.arrivedAtPickupAt != nil, "The arrival it did record is kept")
        #expect(
            PickupWaitSample(abandoned) == nil,
            "Forty minutes before giving up is not a recorded wait: the order was never picked up"
        )
    }

    @Test("A delivery cancelled after pickup did wait, and the wait counts")
    func cancelledAfterPickupStillContributes() throws {
        let spoiled = delivery(accepted: 0, arrived: 5, pickedUp: 12, cancelled: 40)

        #expect(spoiled.state == .cancelled)
        let sample = try #require(PickupWaitSample(spoiled))
        #expect(sample.duration == minutes(7), "Whatever went wrong afterwards, the wait happened")
    }

    // MARK: Data the app could not have written

    @Test("A pickup recorded before the arrival it followed is excluded, never clamped to zero")
    func malformedIntervalIsExcluded() {
        // Unreachable through the transitions, which refuse a backwards
        // timestamp; assembled here as the anomalous store it would be.
        let shift = Shift(startedAt: at(0))
        let delivery = Delivery(shift: shift, acceptedAt: at(0))
        try? delivery.markArrivedAtPickup(at: at(20))
        try? delivery.markPickedUp(at: at(5))

        #expect(delivery.pickedUpAt == nil, "The transition refuses it in the first place")
        #expect(PickupWaitSample(delivery) == nil)
        #expect(delivery.pickupWait == nil)
    }

    @Test("The transitions refuse a backwards pickup, so no negative wait can be stored")
    func transitionsRefuseABackwardsPickup() {
        let shift = Shift(startedAt: at(0))
        let delivery = Delivery(shift: shift, acceptedAt: at(0))
        try? delivery.markArrivedAtPickup(at: at(20))

        #expect(throws: DeliveryError.timestampPrecedesLastEvent) {
            try delivery.markPickedUp(at: at(5))
        }
    }
}

/// The median rule, on numbers, without a delivery or a store in the way.
@Suite("Pickup wait median")
struct PickupWaitMedianTests {
    private let calculator = PickupWaitCalculator()

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    private func median(_ durations: [TimeInterval]) -> TimeInterval? {
        PickupWaitCalculator.median(of: durations)
    }

    @Test("No samples have no median")
    func noSamples() {
        #expect(median([]) == nil)
        #expect(calculator.metrics(of: [PickupWaitSample]()) == .none)
    }

    @Test("One sample is its own median")
    func oneSample() {
        #expect(median([minutes(11)]) == minutes(11))
    }

    @Test("Two samples take the midpoint between them")
    func twoSamples() {
        #expect(median([minutes(6), minutes(14)]) == minutes(10))
    }

    @Test("An odd count takes the middle value")
    func oddCount() {
        #expect(median([minutes(3), minutes(8), minutes(41)]) == minutes(8))
        #expect(median([minutes(1), minutes(2), minutes(3), minutes(4), minutes(90)]) == minutes(3))
    }

    @Test("An even count takes the midpoint of the two middle values")
    func evenCount() {
        #expect(median([minutes(2), minutes(6), minutes(10), minutes(60)]) == minutes(8))
    }

    @Test("The median does not depend on the order the samples arrived in")
    func orderIndependent() {
        let durations = [minutes(41), minutes(6), minutes(11), minutes(9), minutes(20)]

        #expect(median(durations) == minutes(11))
        #expect(median(durations.reversed()) == minutes(11))
        #expect(median(durations.sorted()) == minutes(11))
        #expect(median(durations.shuffled()) == minutes(11))
    }

    @Test("Repeated values are counted as the separate observations they are")
    func repeatedValues() {
        #expect(median([minutes(5), minutes(5), minutes(5)]) == minutes(5))
        #expect(median([minutes(5), minutes(5), minutes(5), minutes(40)]) == minutes(5))

        let metrics = calculator.metrics(of: [minutes(5), minutes(5)].map { sample($0) })
        #expect(metrics.sampleCount == 2, "Two identical waits are two waits")
        #expect(!metrics.hasSpread)
    }

    @Test("A midpoint that is not a whole second is kept exactly, and rounded only on screen")
    func fractionalMidpoint() throws {
        let exact = try #require(median([600, 601]))

        #expect(exact == 600.5, "Nothing rounds inside the calculation")
        #expect(DurationText.short(exact) == "10 min", "The screen shows whole units")
    }

    @Test("A long wait is retained rather than trimmed as an outlier")
    func longWaitRetained() {
        let durations = [minutes(5), minutes(6), minutes(7), minutes(8), minutes(95)]
        let metrics = calculator.metrics(of: durations.map { sample($0) })

        #expect(metrics.medianDuration == minutes(7), "The median is where most of the pickups were")
        #expect(metrics.longestDuration == minutes(95), "And the long one is still on the record")
        #expect(metrics.sampleCount == 5, "Nothing was dropped to make the middle look better")
    }

    @Test("Many samples still resolve to the middle one")
    func manySamples() {
        let durations = (1...101).map { minutes(Double($0)) }
        let metrics = calculator.metrics(of: durations.shuffled().map { sample($0) })

        #expect(metrics.sampleCount == 101)
        #expect(metrics.medianDuration == minutes(51))
        #expect(metrics.shortestDuration == minutes(1))
        #expect(metrics.longestDuration == minutes(101))
    }

    /// A sample of a given length, at a distinct instant so the samples are not
    /// silently deduplicated anywhere.
    private func sample(_ duration: TimeInterval) -> PickupWaitSample {
        PickupWaitSample(duration: duration, pickedUpAt: Date(timeIntervalSince1970: 1_756_000_000 + duration))
    }
}

/// Which deliveries a place's history is built from, and which it leaves out.
@Suite("Pickup wait aggregation by place")
struct PickupWaitAggregationTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    /// An in-memory store holding one completed shift, plus a place factory, so
    /// the relationships the metrics read are the ones SwiftData maintains.
    private func makeContext() throws -> (context: ModelContext, shift: Shift) {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = Shift(startedAt: at(0))
        context.insert(shift)
        return (context, shift)
    }

    private func place(_ name: String, in context: ModelContext) throws -> PickupPlace {
        let place = try PickupPlace(name: PickupPlaceName(name), createdAt: at(0))
        context.insert(place)
        return place
    }

    /// One delivery with the given wait, attached to `place` unless none is
    /// given. `wait` of `nil` never records a pickup.
    @discardableResult
    private func record(
        wait: Double?,
        arrivingAt arrival: Double,
        at place: PickupPlace?,
        in context: ModelContext,
        on shift: Shift
    ) -> Delivery {
        let delivery = Delivery(shift: shift, acceptedAt: at(arrival - 5))
        try? delivery.markArrivedAtPickup(at: at(arrival))
        if let wait {
            try? delivery.markPickedUp(at: at(arrival + wait))
            try? delivery.markDelivered(at: at(arrival + wait + 10))
        } else {
            try? delivery.cancel(at: at(arrival + 30))
        }
        delivery.setPickupPlace(place)
        context.insert(delivery)
        return delivery
    }

    @Test("A place's history is built from its own deliveries")
    func onePlace() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: 6, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: 11, arrivingAt: 40, at: noodles, in: context, on: shift)
        record(wait: 41, arrivingAt: 80, at: noodles, in: context, on: shift)
        try context.save()

        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics.sampleCount == 3)
        #expect(metrics.medianDuration == minutes(11))
        #expect(metrics.shortestDuration == minutes(6))
        #expect(metrics.longestDuration == minutes(41))
        #expect(metrics.mostRecentSampleAt == at(121), "The last wait ended 41 minutes after arriving at 80")
    }

    @Test("Two places keep entirely separate histories")
    func twoPlacesStaySeparate() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)
        let diner = try place("Example Diner", in: context)

        record(wait: 4, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: 6, arrivingAt: 40, at: noodles, in: context, on: shift)
        record(wait: 30, arrivingAt: 70, at: diner, in: context, on: shift)
        try context.save()

        #expect(noodles.pickupWaitMetrics().sampleCount == 2)
        #expect(noodles.pickupWaitMetrics().medianDuration == minutes(5))
        #expect(diner.pickupWaitMetrics().sampleCount == 1)
        #expect(diner.pickupWaitMetrics().medianDuration == minutes(30))
    }

    @Test("A place reused across shifts groups every wait recorded at it")
    func reusedPlaceGroupsAcrossShifts() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let noodles = try place("Nowhere Noodles", in: context)

        for (index, wait) in [8.0, 12.0, 20.0].enumerated() {
            let shift = Shift(startedAt: at(Double(index) * 600))
            context.insert(shift)
            record(wait: wait, arrivingAt: Double(index) * 600 + 10, at: noodles, in: context, on: shift)
        }
        try context.save()

        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics.sampleCount == 3, "One place, three nights")
        #expect(metrics.medianDuration == minutes(12))
    }

    @Test("A delivery that names no place contributes to no place's history")
    func deliveryWithoutAPlaceIsExcluded() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: 10, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: 50, arrivingAt: 40, at: nil, in: context, on: shift)
        try context.save()

        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics.sampleCount == 1)
        #expect(metrics.medianDuration == minutes(10), "The unattributed wait belongs to no place")
        #expect(metrics.longestDuration == minutes(10))
    }

    @Test("A delivery whose lifecycle records no pickup is excluded from its place's history")
    func incompleteLifecycleIsExcluded() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: 10, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: 20, arrivingAt: 40, at: noodles, in: context, on: shift)
        // Arrived, waited half an hour, then cancelled without ever picking up.
        record(wait: nil, arrivingAt: 80, at: noodles, in: context, on: shift)
        try context.save()

        #expect(noodles.deliveries.count == 3, "All three deliveries still name the place")
        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics.sampleCount == 2, "Only two of them recorded a wait")
        #expect(metrics.medianDuration == minutes(15))
        #expect(metrics.longestDuration == minutes(20), "The abandoned half hour is not the longest wait")
    }

    @Test("The sample count matches the waits that were included")
    func sampleCountMatchesIncludedWaits() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: 5, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: nil, arrivingAt: 40, at: noodles, in: context, on: shift)
        record(wait: 9, arrivingAt: 100, at: noodles, in: context, on: shift)
        record(wait: 12, arrivingAt: 140, at: noodles, in: context, on: shift)
        try context.save()

        let samples = noodles.pickupWaitSamples
        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics.sampleCount == samples.count)
        #expect(samples.map(\.duration) == [minutes(5), minutes(9), minutes(12)], "Oldest first")
    }

    @Test("A place nothing was ever picked up at has no history rather than a zero")
    func placeWithNoWaits() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: nil, arrivingAt: 10, at: noodles, in: context, on: shift)
        try context.save()

        let metrics = noodles.pickupWaitMetrics()
        #expect(metrics == .none)
        #expect(metrics.medianDuration == nil, "Nothing stands in for the wait that was not recorded")
        #expect(metrics.sampleCount == 0)
    }

    @Test("Nothing aggregated is written back to the place")
    func nothingIsPersisted() throws {
        let (context, shift) = try makeContext()
        let noodles = try place("Nowhere Noodles", in: context)

        record(wait: 6, arrivingAt: 10, at: noodles, in: context, on: shift)
        record(wait: 11, arrivingAt: 40, at: noodles, in: context, on: shift)
        try context.save()

        _ = noodles.pickupWaitMetrics()
        #expect(!context.hasChanges, "Deriving metrics must not dirty the store")

        // The place's stored surface stays identity only. `PickupPlacePersistenceTests`
        // pins the whole shape; this names the fields *these* metrics would be
        // the reason to add, so adding one fails here too.
        let place = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "PickupPlace" })
        let properties = Set(place.properties.map(\.name))
        for aggregate in ["medianWait", "averageWait", "pickupCount", "waitSampleCount", "lastWaitAt"] {
            #expect(!properties.contains(aggregate), "\(aggregate) is derived, never stored")
        }
    }
}

/// What may be said about a place, at each amount of history.
///
/// Wording is asserted rather than eyeballed because the failure mode is a
/// claim: "typical wait 20 min" over a single pickup would be wrong in a way no
/// arithmetic test would catch.
@Suite("Pickup wait history wording")
struct PickupWaitWordingTests {
    private let calculator = PickupWaitCalculator()

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    private func metrics(_ waits: [Double]) -> PickupWaitMetrics {
        calculator.metrics(
            of: waits.enumerated().map { index, wait in
                PickupWaitSample(
                    duration: minutes(wait),
                    pickedUpAt: Date(timeIntervalSince1970: 1_756_000_000 + Double(index) * 3600)
                )
            }
        )
    }

    @Test("No recorded waits says so, and explains what a wait is measured from")
    func noHistory() {
        let none = metrics([])

        #expect(none.availability == .noRecordedWaits)
        #expect(none.typicalDuration == nil)
        #expect(none.basisStatement == "No recorded pickup waits")
        #expect(none.insufficientHistoryExplanation?.contains("recorded arrival") == true)
        #expect(none.spreadStatement == nil)
    }

    @Test("One recorded wait is stated as one recorded wait, and never as a typical one")
    func oneSample() {
        let single = metrics([20])

        #expect(single.availability == .insufficientHistory)
        #expect(single.sampleCount == 1)
        #expect(single.medianDuration == minutes(20), "The wait itself is a fact and is shown")
        #expect(single.typicalDuration == nil, "But it is not offered as the place's typical wait")
        #expect(single.basisStatement == "1 recorded pickup")
        #expect(single.insufficientHistoryExplanation == "Not enough history for a typical wait.")
        #expect(single.spokenStatement == "1 recorded pickup, 20 minutes. Not enough history for a typical wait.")
    }

    @Test("Two recorded waits cross the threshold, and the count is still said")
    func thresholdCrossing() {
        let below = metrics([20])
        let atThreshold = metrics([20, 30])

        #expect(PickupWaitMetrics.minimumSampleCount == 2)
        #expect(below.availability == .insufficientHistory)
        #expect(atThreshold.availability == .available)
        #expect(atThreshold.typicalDuration == minutes(25))
        #expect(atThreshold.basisStatement == "Median of 2 recorded pickups")
        #expect(
            atThreshold.spokenStatement
                == "Typical recorded pickup wait, 25 minutes, median of 2 recorded pickups.",
            "Showed: \(atThreshold.spokenStatement)"
        )
    }

    @Test("A longer history names the statistic and the number of pickups behind it")
    func availableHistory() {
        let history = metrics([6, 11, 41])

        #expect(history.basisStatement == "Median of 3 recorded pickups")
        #expect(history.insufficientHistoryExplanation == nil)
        #expect(history.spreadStatement == "Shortest 6 min · Longest 41 min", "Showed: \(history.spreadStatement ?? "")")
        #expect(history.spokenSpreadStatement == "Shortest recorded wait 6 minutes, longest 41 minutes.")
    }

    @Test("Identical waits have no spread to contrast")
    func noSpread() {
        let flat = metrics([9, 9, 9])

        #expect(!flat.hasSpread)
        #expect(flat.spreadStatement == nil, "Shortest 9 min, longest 9 min is noise")
        #expect(flat.typicalDuration == minutes(9))
    }

    @Test("Nothing claims the history is reliable, accurate or predictive", arguments: [[Double](), [20], [6, 11, 41]])
    func neverOverclaims(waits: [Double]) {
        let history = metrics(waits)
        let forbidden = [
            "reliable", "accurate", "predict", "expect", "usually will", "guarantee",
            "average", "estimate", "score", "rank", "best", "worst", "fast", "slow"
        ]

        let statements = [
            history.basisStatement,
            history.insufficientHistoryExplanation,
            history.spokenStatement,
            history.spreadStatement,
            history.spokenSpreadStatement,
            PickupWaitMetrics.typicalTitle
        ].compactMap { $0 }

        for statement in statements {
            for word in forbidden {
                #expect(
                    !statement.lowercased().contains(word),
                    "\"\(statement)\" must not claim \(word)"
                )
            }
        }
    }

    @Test("Every statement about a duration carries the count it came from")
    func countIsAlwaysStated() {
        for waits in [[20.0], [6.0, 11.0], [6.0, 11.0, 41.0]] {
            let history = metrics(waits)
            #expect(
                history.basisStatement.contains("\(history.sampleCount)"),
                "Showed: \(history.basisStatement)"
            )
            #expect(history.spokenStatement.contains("\(history.sampleCount)"))
        }
    }
}
