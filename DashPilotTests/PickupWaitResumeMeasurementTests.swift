import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What pickups recorded by the Park and Resume workflow do to the pickup-wait
/// median, measured through the calculator the app actually uses, before the
/// policy for them was decided.
///
/// ## What the workflow's wait is
///
/// With the workflow on, Park records Arrived at Pickup and Resume Driving
/// records Picked Up, so the recorded wait is **the time from parking at the
/// pickup to driving away from it**. A pickup the driver records by hand runs
/// from their Arrived tap to their Picked Up tap, which is pressed with the
/// order in hand. The two share a start (a driver taps Arrived as they pull up,
/// which is when Park is pressed too) and differ at the end: the workflow's
/// includes the walk in, the walk back, and however long the driver sits in the
/// vehicle before pressing Resume Driving.
///
/// ## What the numbers are
///
/// Every duration is synthetic and in minutes. "Manual" waits are
/// `[4, 6, 7, 9, 12]` (median 7), the recorded in-store waits. A workflow wait
/// for the same visit is `inStore + walk + linger`, with `walk` the two walks
/// together:
///
/// - **walk 2**: a minute in and a minute back;
/// - **linger 0, 1 or 5**: pressing Resume at once, after a glance at the next
///   order, or after five minutes with the phone in the car.
///
/// Those figures are illustrations, not measurements of any driver: DashPilot
/// does not know how long a walk or a linger takes, and nothing in production
/// reads this file or estimates either one. Every expectation is an exact
/// figure, so the suite is the record of the measurement rather than a
/// description of it.
@Suite("Pickup wait measurement under Park and Resume")
struct PickupWaitResumeMeasurementTests {
    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    /// The median the app would show over these waits if every one counted, in
    /// minutes.
    private func median(_ waits: [Double]) -> Double? {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let samples = waits.enumerated().map { index, wait in
            PickupWaitSample(duration: minutes(wait), pickedUpAt: base.addingTimeInterval(Double(index) * 3_600))
        }
        return PickupWaitCalculator().metrics(of: samples).medianDuration.map { $0 / 60 }
    }

    private let manual: [Double] = [4, 6, 7, 9, 12]

    /// The same five visits recorded by the workflow.
    private func workflow(walk: Double, linger: Double) -> [Double] {
        manual.map { $0 + walk + linger }
    }

    // MARK: One kind alone

    @Test("Manual alone: 7:00")
    func manualOnly() {
        #expect(median(manual) == 7)
    }

    @Test("Workflow alone reads long by exactly the walk and the linger, never short")
    func workflowOnly() {
        #expect(median(workflow(walk: 2, linger: 0)) == 9)
        #expect(median(workflow(walk: 2, linger: 1)) == 10)
        #expect(median(workflow(walk: 2, linger: 5)) == 14, "Twice the in-store figure")
    }

    // MARK: Mixtures

    @Test("One workflow pickup among five manual ones moves the median from 7:00 to 8:00")
    func oneAmongFive() {
        #expect(median(manual + [7 + 2]) == 8)
        #expect(median(manual + [7 + 2 + 5]) == 8, "By rank, not magnitude: a long linger moves it no further")
    }

    @Test("At the smallest sample a typical wait is offered for, one workflow pickup adds half its overhead")
    func atTheTypicalThreshold() {
        #expect(PickupWaitMetrics.minimumSampleCount == 2)
        #expect(median([8, 8 + 2]) == 9)
        #expect(median([8, 8 + 2 + 5]) == 11.5)
    }

    @Test("Workflow pickups as half the sample: 8:30 with no linger, 11:30 with five minutes of it")
    func halfTheSample() {
        #expect(median(manual + workflow(walk: 2, linger: 0)) == 8.5)
        #expect(median(manual + workflow(walk: 2, linger: 1)) == 9)
        #expect(median(manual + workflow(walk: 2, linger: 5)) == 11.5)
    }

    /// The structural finding, and the same one the retired Park-when-parking
    /// setting produced in the other direction: the figure follows the share of
    /// pickups the workflow recorded, which is a fact about the driver's
    /// setting rather than the place.
    @Test("The median climbs with the workflow's share of the sample")
    func followsTheShare() {
        let recorded = workflow(walk: 2, linger: 1)
        let medians = (0...5).compactMap { share in median(Array(manual.dropFirst(share)) + recorded.prefix(share)) }
        #expect(medians == [7, 7, 9, 9, 10, 10])
        #expect(medians == medians.sorted(), "Never down as the share grows")
    }

    // MARK: The driver's own timing

    @Test("A driver who sits in the car before walking in adds that time to the wait")
    func lingerBeforeWalkingIn() {
        // Three minutes in the car first, then an in-store wait of 7.
        #expect(median(manual + [3 + 7 + 2]) == 8)
        #expect(median([7, 3 + 7 + 2]) == 9.5)
    }

    @Test("A driver back at the car who does not press Resume at once adds that time to the wait")
    func slowToResume() {
        #expect(median([7, 7 + 2 + 3]) == 9.5)
    }

    @Test("Park and Resume pressed together is a wait of almost nothing, and pulls the median down")
    func immediate() {
        // A mistaken Park, or an order handed out at the kerb.
        #expect(median(manual + [0.25]) == 6.5)
        #expect(median([7, 0.25]) == 3.625)
    }

    @Test("A long wait moves the median by one rank, as any long wait does")
    func longWait() {
        #expect(median(manual + [40]) == 8)
        #expect(median(manual + [40, 45, 50]) == 10.5)
    }

    // MARK: Stacked

    /// Two orders at one pickup, one Park and Resume for the first and the
    /// second's steps by hand: the workflow's wait covers both orders' time
    /// inside, and the manual one ends when the second order was in hand.
    @Test("Stacked orders at one place: the workflow's wait also carries the other order's time inside")
    func stackedAtOnePlace() {
        let first = 9 + 2.0 // both orders ready after 9 minutes, and the walks
        let second = 9.0 // tapped by hand when it was in hand
        #expect(median([first, second]) == 10)
        #expect(median(manual + [first, second]) == 9)
    }

    // MARK: What the policy reads

    /// Through the calculator the app uses, with provenance: whatever the share,
    /// the figure is the driver's own pickups, and the workflow's are counted
    /// apart rather than folded in.
    @Test("With the workflow's waits left out, the figure is the manual median at every share, and the count is said")
    func policyHoldsTheFigure() {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let recorded = workflow(walk: 2, linger: 5)
        for share in 0...4 {
            let samples = manual.enumerated().map { index, wait in
                PickupWaitSample(duration: minutes(wait), pickedUpAt: base.addingTimeInterval(Double(index) * 60), provenance: .manual)
            } + recorded.prefix(share).enumerated().map { index, wait in
                PickupWaitSample(
                    duration: minutes(wait),
                    pickedUpAt: base.addingTimeInterval(Double(100 + index) * 60),
                    provenance: .resumeAutomation
                )
            }
            let metrics = PickupWaitCalculator().metrics(of: samples)
            #expect(metrics.medianDuration == minutes(7), "share \(share)")
            #expect(metrics.resumeRecordedPickupCount == share)
        }
    }
}

/// The same measurement end to end: the workflow recording both events, the
/// place reading them, and a correction rederiving them.
@MainActor
@Suite("Pickup wait measurement under Park and Resume, through the store")
struct PickupWaitResumeStoreMeasurementTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// One finished shift at one place: two pickups by hand (6 and 8 minutes),
    /// then one delivery parked for at minute 100 and resumed from `resumeAfter`
    /// minutes later.
    private func shiftAtOnePlace(resumeAfter: Double, in context: ModelContext) throws -> (PickupPlace, Delivery) {
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        let places = PickupPlaceService(context: context)
        try shifts.startShift(at: start)

        for (index, wait) in [6.0, 8.0].enumerated() {
            let base = Double(index) * 40
            let delivery = try service.startDelivery(at: at(base))
            try places.assignPlace(named: "Synthetic Noodles", to: delivery, at: at(base))
            try service.markArrivedAtPickup(delivery, at: at(base + 5))
            try service.markPickedUp(delivery, at: at(base + 5 + wait))
            try service.markDelivered(delivery, at: at(base + 30))
        }

        try SettingsService(context: context).setUsesParkAndResumeForPickups(true)
        let parked = try service.startDelivery(at: at(90))
        let place = try places.assignPlace(named: "Synthetic Noodles", to: parked, at: at(90))
        #expect(try ParkVehicleService(context: context).park(at: at(100)).pickup == .markedArrived(deliveryNumber: 3))
        #expect(
            try ParkVehicleService(context: context).resumeDriving(at: at(100 + resumeAfter)).pickup
                == .markedPickedUp(deliveryNumber: 3)
        )
        try service.markDelivered(parked, at: at(130))
        try shifts.endActiveShift(at: at(140))
        return (place, parked)
    }

    @Test("The workflow's wait is parked-to-driving, recorded exactly, and left out of the place's figure")
    func endToEnd() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let (place, parked) = try shiftAtOnePlace(resumeAfter: 11, in: context)

        #expect(parked.pickupWait == 660, "Nothing is scaled, trimmed or adjusted")
        let everyWait = PickupWaitCalculator().metrics(
            of: place.pickupWaitSamples.map { PickupWaitSample(duration: $0.duration, pickedUpAt: $0.pickedUpAt) }
        )
        #expect(everyWait.medianDuration == 480, "8 minutes, where the two by hand read 7")

        let metrics = place.pickupWaitMetrics()
        #expect(metrics.medianDuration == 420)
        #expect(metrics.sampleCount == 2)
        #expect(metrics.resumeRecordedPickupCount == 1)
        #expect(metrics.parkRecordedPickupCount == 0)
    }

    @Test("Correcting the workflow's pickup moves its wait and keeps it out of the figure")
    func correctionKeepsProvenance() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let (place, parked) = try shiftAtOnePlace(resumeAfter: 11, in: context)

        let proposed = DeliveryLifecycleRecord(parked).replacing(.pickedUp, with: at(108))
        try DeliveryService(context: context).correctRecordedTimes(parked, to: proposed)

        #expect(parked.pickupWait == 480)
        #expect(parked.pickupProvenance == .resumeAutomation)
        #expect(place.pickupWaitMetrics().resumeRecordedPickupCount == 1)
        #expect(place.pickupWaitMetrics().medianDuration == 420)
    }
}
