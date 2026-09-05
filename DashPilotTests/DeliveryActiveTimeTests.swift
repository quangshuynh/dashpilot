import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The union of a shift's delivery intervals: what it counts once, what it
/// refuses to count at all, and what it does with data the app could not have
/// written.
///
/// Every date here is an explicit offset from one fixed instant, so nothing in
/// this suite depends on when it runs, and no test needs a store, a container or
/// a rendered view.
@Suite("Delivery active time")
struct DeliveryActiveTimeTests {
    private let calculator = DeliveryActiveTimeCalculator()
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// One interval, stated in minutes from the fixture's start.
    private func interval(_ from: Double, _ to: Double) -> DeliveryActiveInterval {
        DeliveryActiveInterval(start: at(from), end: at(to))
    }

    /// A delivery that never recorded a terminal event.
    private func unfinished(from: Double) -> DeliveryActiveInterval {
        DeliveryActiveInterval(start: at(from), end: nil)
    }

    private func activeTime(_ intervals: [DeliveryActiveInterval]) -> DeliveryActiveTime {
        calculator.activeTime(of: intervals)
    }

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    // MARK: The union

    @Test("A shift with no deliveries has no active time to report, rather than zero minutes of it")
    func noIntervals() {
        let active = activeTime([])

        #expect(active == .none)
        #expect(active.duration == 0)
        #expect(!active.isAvailable)
        #expect(active.sourceIntervalCount == 0)
    }

    @Test("One delivery contributes exactly its own span")
    func oneInterval() {
        let active = activeTime([interval(0, 30)])

        #expect(active.duration == minutes(30))
        #expect(active.isAvailable)
        #expect(active.countedIntervalCount == 1)
        #expect(active.mergedIntervalCount == 1)
        #expect(!active.hasOverlappingDeliveries)
    }

    @Test("Two deliveries that do not overlap add up")
    func nonOverlappingIntervals() {
        let active = activeTime([interval(0, 30), interval(60, 105)])

        #expect(active.duration == minutes(75))
        #expect(active.mergedIntervalCount == 2)
        #expect(!active.hasOverlappingDeliveries)
    }

    /// The rule the whole interval exists for: 10:00–10:30 and 10:10–10:40 is
    /// forty minutes, not the fifty-five their durations sum to.
    @Test("Two overlapping deliveries count their shared minutes once")
    func partiallyOverlappingIntervals() {
        let active = activeTime([interval(0, 30), interval(10, 40)])

        #expect(active.duration == minutes(40))
        #expect(active.duration != minutes(55), "The sum of two overlapping durations is not a duration")
        #expect(active.countedIntervalCount == 2)
        #expect(active.mergedIntervalCount == 1)
        #expect(active.hasOverlappingDeliveries)
    }

    @Test("A delivery worked entirely inside another adds nothing to the total")
    func nestedInterval() {
        let active = activeTime([interval(0, 60), interval(15, 30)])

        #expect(active.duration == minutes(60))
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("A chain of overlaps merges into the single stretch it covers")
    func chainedOverlaps() {
        let active = activeTime([interval(0, 20), interval(15, 35), interval(30, 50), interval(45, 70)])

        #expect(active.duration == minutes(70))
        #expect(active.countedIntervalCount == 4)
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("Two chains stay two stretches, and the time between them is not counted")
    func twoSeparateChains() {
        let active = activeTime([interval(0, 20), interval(10, 30), interval(90, 110), interval(100, 125)])

        #expect(active.duration == minutes(65))
        #expect(active.mergedIntervalCount == 2)
    }

    @Test("Deliveries recorded over identical spans are one span")
    func identicalIntervals() {
        let active = activeTime([interval(0, 25), interval(0, 25), interval(0, 25)])

        #expect(active.duration == minutes(25))
        #expect(active.countedIntervalCount == 3)
        #expect(active.mergedIntervalCount == 1)
    }

    /// One delivery ending exactly as the next begins is a continuous stretch of
    /// delivery activity, not two stretches with a zero-length gap.
    @Test("A delivery beginning exactly when another ends leaves no gap")
    func touchingIntervals() {
        let active = activeTime([interval(0, 30), interval(30, 60)])

        #expect(active.duration == minutes(60))
        #expect(active.mergedIntervalCount == 1)
        #expect(active.hasOverlappingDeliveries)
    }

    @Test("Deliveries accepted at the same instant merge to the later of their ends")
    func sameStartDifferentEnds() {
        let active = activeTime([interval(0, 20), interval(0, 45)])

        #expect(active.duration == minutes(45))
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("Deliveries finishing at the same instant merge from the earlier of their starts")
    func sameEndDifferentStarts() {
        let active = activeTime([interval(10, 45), interval(0, 45)])

        #expect(active.duration == minutes(45))
        #expect(active.mergedIntervalCount == 1)
    }

    /// A delivery accepted and finished in the same instant really did cover no
    /// time. That is a measurement of zero, which is why it is counted.
    @Test("A delivery of no length is counted and contributes nothing")
    func zeroDurationInterval() {
        let active = activeTime([interval(20, 20)])

        #expect(active.duration == 0)
        #expect(active.isAvailable, "A measured zero is a measurement, not an absence of one")
        #expect(active.countedIntervalCount == 1)
        #expect(active.malformedIntervalCount == 0)
    }

    @Test("A zero-length delivery inside another changes nothing")
    func zeroDurationIntervalInsideAnother() {
        let active = activeTime([interval(0, 40), interval(20, 20)])

        #expect(active.duration == minutes(40))
        #expect(active.mergedIntervalCount == 1)
    }

    // MARK: Data the app could not have written

    @Test("A delivery whose end precedes its start is left out rather than reversed")
    func malformedInterval() {
        let active = activeTime([interval(0, 30), interval(80, 50)])

        #expect(active.duration == minutes(30))
        #expect(active.countedIntervalCount == 1)
        #expect(active.malformedIntervalCount == 1)
        #expect(active.sourceIntervalCount == 2)
        #expect(active.unusableIntervalCount == 1)
    }

    @Test("A delivery with no terminal event is counted as unfinished, never given an end")
    func unfinishedInterval() {
        let active = activeTime([interval(0, 30), unfinished(from: 40)])

        #expect(active.duration == minutes(30))
        #expect(active.unfinishedIntervalCount == 1)
        #expect(active.malformedIntervalCount == 0)
        #expect(active.sourceIntervalCount == 2)
    }

    @Test("A shift whose only deliveries are unusable reports no active time, not zero minutes of it")
    func onlyUnusableIntervals() {
        let active = activeTime([unfinished(from: 0), interval(80, 50)])

        #expect(active.duration == 0)
        #expect(!active.isAvailable, "Nothing was measured, which is not the same as measuring nothing")
        #expect(active.sourceIntervalCount == 2)
        #expect(active.unusableIntervalCount == 2)
    }

    // MARK: Order

    /// The union is a property of the set of intervals, so every arrangement of
    /// the same four must produce the same figure — including the ones a
    /// relationship, a fetch or a shuffle could hand over.
    @Test("The result does not depend on the order the intervals arrive in")
    func orderIndependence() {
        let intervals = [interval(0, 30), interval(10, 40), interval(90, 100), interval(30, 35)]
        let expected = activeTime(intervals)

        #expect(expected.duration == minutes(50))

        for arrangement in Self.permutations(of: intervals) {
            let active = activeTime(arrangement)
            #expect(active.duration == expected.duration)
            #expect(active.mergedIntervalCount == expected.mergedIntervalCount)
            #expect(active.countedIntervalCount == expected.countedIntervalCount)
        }
    }

    @Test("Reversing the input changes nothing, including for identical starts")
    func reversedInputMatches() {
        let intervals = [interval(0, 10), interval(0, 45), interval(45, 60), interval(20, 25)]

        #expect(activeTime(intervals) == activeTime(intervals.reversed()))
    }

    // MARK: Scale

    @Test("A thousand chained deliveries merge into the one stretch they cover")
    func manyChainedIntervals() {
        let intervals = (0..<1_000).map { step in
            interval(Double(step) * 0.5, Double(step) * 0.5 + 1)
        }

        let active = activeTime(intervals)

        #expect(active.countedIntervalCount == 1_000)
        #expect(active.mergedIntervalCount == 1)
        #expect(active.duration == minutes(Double(999) * 0.5 + 1))
    }

    @Test("A thousand separate deliveries stay a thousand stretches")
    func manyDisjointIntervals() {
        let intervals = (0..<1_000).map { step in
            interval(Double(step) * 10, Double(step) * 10 + 4)
        }

        let active = activeTime(intervals)

        #expect(active.mergedIntervalCount == 1_000)
        #expect(active.duration == minutes(4_000))
        #expect(!active.hasOverlappingDeliveries)
    }

    // MARK: The shift's window

    private var window: ClosedRange<Date> { at(0)...at(180) }

    private func clippedActiveTime(_ intervals: [DeliveryActiveInterval]) -> DeliveryActiveTime {
        calculator.activeTime(of: intervals, within: window)
    }

    @Test("An interval inside the shift is measured exactly as it was recorded")
    func intervalInsideTheWindow() {
        #expect(clippedActiveTime([interval(30, 75)]).duration == minutes(45))
    }

    @Test("A delivery accepted before the shift began contributes only the part inside it")
    func intervalStartingBeforeTheWindow() {
        let active = clippedActiveTime([interval(-20, 40)])

        #expect(active.duration == minutes(40), "Clipped to the shift's start, not measured from before it")
        #expect(active.countedIntervalCount == 1)
        #expect(active.malformedIntervalCount == 0)
    }

    @Test("A delivery finishing after the shift ended contributes only the part inside it")
    func intervalEndingAfterTheWindow() {
        #expect(clippedActiveTime([interval(150, 260)]).duration == minutes(30))
    }

    @Test("A delivery spanning the whole shift contributes the whole shift and no more")
    func intervalSpanningTheWindow() {
        #expect(clippedActiveTime([interval(-60, 300)]).duration == minutes(180))
    }

    @Test("A delivery lying entirely outside the shift contributes nothing and is counted as anomalous")
    func intervalOutsideTheWindow() {
        let active = clippedActiveTime([interval(-90, -30), interval(200, 240)])

        #expect(active.duration == 0)
        #expect(!active.isAvailable)
        #expect(active.malformedIntervalCount == 2)
        #expect(active.countedIntervalCount == 0)
    }

    @Test("Clipping happens before merging, so overlap outside the shift is not counted inside it")
    func clippingPrecedesMerging() {
        let active = clippedActiveTime([interval(-30, 20), interval(-25, 10)])

        #expect(active.duration == minutes(20))
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("Active time can never exceed the shift it is measured within")
    func neverExceedsTheWindow() {
        let elapsed = window.upperBound.timeIntervalSince(window.lowerBound)
        let extremes = [
            [interval(-600, 600)],
            [interval(-600, 600), interval(-10, 400), interval(0, 180)],
            (0..<50).map { interval(Double($0) * -20, Double($0) * 20 + 400) }
        ]

        for intervals in extremes {
            #expect(clippedActiveTime(intervals).duration <= elapsed)
        }
    }
}

extension DeliveryActiveTimeTests {
    /// Every arrangement of `values`, so an order-independence claim is asserted
    /// against all of them rather than against one shuffle that happened to
    /// pass.
    static func permutations<Element>(of values: [Element]) -> [[Element]] {
        guard values.count > 1 else { return [values] }
        return values.indices.flatMap { index -> [[Element]] in
            var rest = values
            let picked = rest.remove(at: index)
            return permutations(of: rest).map { [picked] + $0 }
        }
    }
}

/// The same union, read from recorded deliveries and bounded by the shift they
/// belong to.
///
/// These build real `Shift` and `Delivery` models in a throwaway store, so the
/// adapter from persisted timestamps to intervals — and the shift's own
/// `deliveries` relationship it reads them through — are asserted rather than
/// assumed.
@MainActor
@Suite("Delivery active time of a shift")
struct ShiftDeliveryActiveTimeTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A finished shift in a throwaway store, ready for deliveries.
    private func completedShift(in context: ModelContext, endingAfter minutes: Double = 240) throws -> Shift {
        let shift = Shift(startedAt: start)
        context.insert(shift)
        try shift.end(at: at(minutes))
        return shift
    }

    /// A delivery on `shift` that ran to completion.
    ///
    /// The pickup steps take the acceptance timestamp: this suite is about the
    /// interval between the two ends, and what happens in between changes
    /// nothing about it.
    @discardableResult
    private func delivered(in shift: Shift, from: Double, to: Double, context: ModelContext) throws -> Delivery {
        let delivery = Delivery(shift: shift, acceptedAt: at(from))
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(from))
        try delivery.markPickedUp(at: at(from))
        try delivery.markDelivered(at: at(to))
        return delivery
    }

    /// A delivery on `shift` that the driver cancelled.
    @discardableResult
    private func cancelled(in shift: Shift, from: Double, to: Double, context: ModelContext) throws -> Delivery {
        let delivery = Delivery(shift: shift, acceptedAt: at(from))
        context.insert(delivery)
        try delivery.cancel(at: at(to))
        return delivery
    }

    @Test("A completed shift with no deliveries reports no active time")
    func shiftWithoutDeliveries() throws {
        let context = try makeContext()

        #expect(try completedShift(in: context).deliveryActiveTime() == .none)
    }

    @Test("A delivery's interval runs from acceptance to completion")
    func oneDeliveredDelivery() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 10, to: 55, context: context)

        #expect(shift.deliveryActiveTime().duration == minutes(45))
    }

    /// The interval is acceptance to the terminal event, not the wait or the
    /// drive: a delivery is active for every minute between the two.
    @Test("The interval is read from the delivery's own terminal timestamp")
    func intervalUsesTheTerminalTimestamp() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        let delivery = Delivery(shift: shift, acceptedAt: at(10))
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(20))
        try delivery.markPickedUp(at: at(35))
        try delivery.markDelivered(at: at(50))

        let interval = DeliveryActiveInterval(delivery)

        #expect(interval.start == at(10))
        #expect(interval.end == at(50))
        #expect(!interval.isUnfinished)
        #expect(!interval.isMalformed)
    }

    /// A cancelled delivery is work the driver did. It ends when they recorded
    /// it ending, and it is not dropped for having ended the other way.
    @Test("A cancelled delivery is active from acceptance until it was cancelled")
    func cancelledDeliveryContributes() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try cancelled(in: shift, from: 20, to: 50, context: context)

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(30))
        #expect(active.countedIntervalCount == 1)
        #expect(shift.deliverySummary.completed == 0, "It still is not a completed delivery")
        #expect(shift.deliverySummary.cancelled == 1)
    }

    @Test("A cancelled delivery overlapping a completed one shares its minutes rather than adding them")
    func cancelledOverlappingDelivered() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 0, to: 30, context: context)
        try cancelled(in: shift, from: 10, to: 40, context: context)

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(40))
        #expect(active.hasOverlappingDeliveries)
    }

    @Test("Three stacked deliveries count their shared minutes once")
    func threeStackedDeliveries() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 0, to: 40, context: context)
        try delivered(in: shift, from: 15, to: 55, context: context)
        try delivered(in: shift, from: 30, to: 70, context: context)

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(70))
        #expect(active.duration != minutes(120), "Their durations sum to two hours; they covered seventy minutes")
        #expect(active.countedIntervalCount == 3)
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("One delivery completed while another continues leaves the other running the clock")
    func oneFinishesWhileAnotherContinues() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 0, to: 25, context: context)
        try delivered(in: shift, from: 20, to: 90, context: context)

        #expect(shift.deliveryActiveTime().duration == minutes(90))
    }

    @Test("Deliveries accepted at the same instant are one interval from that instant")
    func sameAcceptanceTimestamp() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 30, to: 60, context: context)
        try delivered(in: shift, from: 30, to: 95, context: context)

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(65))
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("Deliveries finishing at the same instant end their stretch once")
    func sameTerminalTimestamp() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 10, to: 80, context: context)
        try cancelled(in: shift, from: 40, to: 80, context: context)

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(70))
        #expect(active.mergedIntervalCount == 1)
    }

    @Test("Delivery active time never exceeds the shift's own elapsed duration")
    func neverExceedsElapsedDuration() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context, endingAfter: 120)
        try delivered(in: shift, from: 0, to: 60, context: context)
        try delivered(in: shift, from: 30, to: 120, context: context)
        try cancelled(in: shift, from: 100, to: 120, context: context)

        let elapsed = try #require(shift.completedDuration)
        let active = shift.deliveryActiveTime()

        #expect(active.duration <= elapsed)
        #expect(active.duration == minutes(120))
    }

    /// A shift cannot be ended while a delivery is active, so this describes a
    /// store holding a row the app could not have written. It must stay safe
    /// rather than invent an end for the delivery that never finished.
    @Test("A completed shift holding an unfinished delivery stays safe and counts it as unusable")
    func completedShiftWithAnUnfinishedDelivery() throws {
        let context = try makeContext()
        let shift = try completedShift(in: context)
        try delivered(in: shift, from: 10, to: 40, context: context)
        context.insert(Delivery(shift: shift, acceptedAt: at(60)))

        let active = shift.deliveryActiveTime()

        #expect(active.duration == minutes(30))
        #expect(active.unfinishedIntervalCount == 1)
        #expect(active.sourceIntervalCount == 2)
        #expect(active.isAvailable, "The delivery that did finish is still measurable")
    }

    @Test("A running shift has no window, and its unfinished delivery contributes nothing")
    func runningShift() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let delivery = Delivery(shift: shift, acceptedAt: at(10))
        context.insert(delivery)
        try delivery.markArrivedAtPickup(at: at(20))

        let active = shift.deliveryActiveTime()

        #expect(shift.completedWindow == nil)
        #expect(!active.isAvailable)
        #expect(active.unfinishedIntervalCount == 1)
    }
}
