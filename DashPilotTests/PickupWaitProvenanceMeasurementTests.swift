import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What pickups recorded by Park do to the pickup-wait median, measured through
/// the calculator the app actually uses.
///
/// ## Why this suite exists
///
/// With `Pick up order when parking` on, Park writes Picked Up for the one
/// delivery at Arrived at Pickup, at the instant the driver parked. The driver
/// usually parks **before** walking in, so the recorded wait for such a
/// delivery ends before the order is handed over. The question this suite
/// answers is not whether that is shorter (it is, by construction) but whether
/// it can move the figure a driver reads, and by how much, before any decision
/// is taken about recording how a pickup was written.
///
/// ## What the numbers are
///
/// Every duration is synthetic and in minutes. "Manual" waits stand for
/// pickups recorded by the Picked Up control after the handover. "Park" waits
/// stand for pickups recorded by Park under the setting, and are the interval
/// between the arrival tap and parking:
///
/// - **immediately after Arrived**: half a minute, the arrival tapped on the
///   kerb and Park a moment later;
/// - **several minutes after Arrived**: three minutes, the arrival tapped on
///   approach and Park once a space was found.
///
/// Where a test compares against what the same pickup would have read if its
/// handover had been recorded, it adds an in-store wait equal to the manual
/// median. That counterfactual exists only here, to size the effect. The app
/// never estimates a handover and nothing in production reads this file.
///
/// Every expectation is an exact figure, so the suite is the record of the
/// measurement rather than a description of it.
@Suite("Pickup wait provenance measurement")
struct PickupWaitProvenanceMeasurementTests {
    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    /// The median the app would show over these waits, in minutes.
    private func median(_ waits: [Double]) -> Double? {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let samples = waits.enumerated().map { index, wait in
            PickupWaitSample(duration: minutes(wait), pickedUpAt: base.addingTimeInterval(Double(index) * 3_600))
        }
        return PickupWaitCalculator().metrics(of: samples).medianDuration.map { $0 / 60 }
    }

    /// Five ordinary pickups at one place: median 7 minutes.
    private let manualOdd: [Double] = [4, 6, 7, 9, 12]

    /// Four ordinary pickups at one place: median 8 minutes.
    private let manualEven: [Double] = [5, 7, 9, 11]

    private let parkImmediately = 0.5
    private let parkAfterSeveralMinutes = 3.0

    // MARK: Baselines

    @Test("Manual pickups alone: the middle value, or the midpoint of the two middle values")
    func manualOnly() {
        #expect(median(manualOdd) == 7)
        #expect(median(manualEven) == 8)
    }

    // MARK: One Park pickup

    @Test("One Park pickup among five manual ones moves the median from 7:00 to 6:30")
    func oneParkPickupInAnOddSample() {
        #expect(median(manualOdd + [parkImmediately]) == 6.5)
        #expect(
            median(manualOdd + [parkAfterSeveralMinutes]) == 6.5,
            "The median moves by rank, not magnitude: half a minute and three minutes move it the same"
        )
        // Had the handover been recorded (the Park interval plus a 7-minute
        // wait inside), the same pickup would have read 7.5 minutes.
        #expect(median(manualOdd + [parkImmediately + 7]) == 7.25)
    }

    @Test("One Park pickup among four manual ones moves the median from 8:00 to 7:00")
    func oneParkPickupInAnEvenSample() {
        #expect(median(manualEven + [parkImmediately]) == 7)
        #expect(median(manualEven + [parkImmediately + 8]) == 8.5, "Recorded at the handover instead")
    }

    @Test("At the smallest sample a typical wait is offered for, one Park pickup halves it")
    func oneParkPickupAtTheTypicalThreshold() {
        #expect(PickupWaitMetrics.minimumSampleCount == 2)
        #expect(median([8, parkImmediately]) == 4.25)
        #expect(median([8, parkImmediately + 8]) == 8.25, "Recorded at the handover instead")
    }

    @Test("One Park pickup among many barely moves it, and looks like any quick pickup")
    func oneParkPickupAmongMany() {
        let manyManual = (3...23).map(Double.init)
        #expect(median(manyManual) == 13)
        #expect(median(manyManual + [parkImmediately]) == 12.5)
        #expect(
            median(manyManual + [parkImmediately + 7]) == 12.5,
            "Below the median either way, so the provenance changes nothing here"
        )
    }

    // MARK: Many Park pickups

    @Test("Each further Park pickup below the median pushes it down one more half-rank")
    func parkPickupsAccumulate() {
        #expect(median(manualOdd + [parkImmediately, parkAfterSeveralMinutes]) == 6)
        #expect(median(manualOdd + [parkImmediately, parkImmediately, parkAfterSeveralMinutes]) == 5)
    }

    @Test("Park pickups as half the sample halve the median, from 7:00 to 3:30")
    func parkPickupsAsHalfTheSample() {
        let park: [Double] = [0.5, 0.5, 1, 3, 3]
        #expect(median(manualOdd + park) == 3.5)
        #expect(median(manualOdd + park.map { $0 + 7 }) == 7.75, "Recorded at the handover instead")
    }

    @Test("Once Park pickups are most of the sample, the median is the time from arriving to parking")
    func parkPickupsAsMostOfTheSample() {
        let park: [Double] = [0.5, 0.5, 0.5, 1, 1, 1, 2, 2, 3, 3]
        #expect(median(manualOdd + park) == 2)
        #expect(median([0.5, 1, 3]) == 1, "All Park: nothing about the wait inside is left in the figure")
    }

    // MARK: Zero

    @Test("A Park pickup at the arrival instant is a wait of zero, and it counts")
    func zeroParkWaitCounts() {
        #expect(median(manualEven + [0]) == 7)
        #expect(median([0, 0]) == 0, "Two such pickups are a typical wait of no length")
    }
}

/// The same measurement through the store: Park recording the pickup, the
/// place reading it, and a correction rederiving it.
@MainActor
@Suite("Pickup wait provenance measurement through the store")
struct PickupWaitProvenanceStoreMeasurementTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    /// One finished shift at one place: two pickups recorded with the Picked Up
    /// control (6 and 8 minutes), then one delivery that arrived at minute 100
    /// and was recorded picked up by Park `parkAfter` minutes later.
    private func shiftAtOnePlace(parkAfter: Double, in context: ModelContext) throws -> (PickupPlace, Delivery) {
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        let places = PickupPlaceService(context: context)
        try shifts.startShift(at: start)

        for (index, wait) in [6.0, 8.0].enumerated() {
            let base = Double(index) * 40
            let delivery = try #require(try service.startOffer(deliveryCount: 1, at: at(base)).deliveriesInOrder.first)
            try places.assignPlace(named: "Synthetic Noodles", to: delivery, at: at(base))
            try service.markArrivedAtPickup(delivery, at: at(base + 5))
            try service.markPickedUp(delivery, at: at(base + 5 + wait))
            try service.markDelivered(delivery, at: at(base + 30))
        }

        try SettingsService(context: context).setRecordsPickupWhenParking(true)
        let parked = try #require(try service.startOffer(deliveryCount: 1, at: at(90)).deliveriesInOrder.first)
        let place = try places.assignPlace(named: "Synthetic Noodles", to: parked, at: at(90))
        try service.markArrivedAtPickup(parked, at: at(100))
        let result = try ParkVehicleService(context: context).park(at: at(100 + parkAfter))
        #expect(result.pickup.recordedPickup)
        try ShiftService(context: context).resumeDrivingOnActiveShift(at: at(115))
        try service.markDelivered(parked, at: at(130))
        try shifts.endActiveShift(at: at(140))
        return (place, parked)
    }

    /// The place's waits with every one counted, which is what the figure was
    /// before provenance was recorded (policy A). Built by dropping each
    /// sample's provenance, so the measurement keeps describing that figure
    /// now that the app's own leaves Park's waits out.
    private func everyWaitCounted(_ place: PickupPlace) -> PickupWaitMetrics {
        PickupWaitCalculator().metrics(
            of: place.pickupWaitSamples.map { PickupWaitSample(duration: $0.duration, pickedUpAt: $0.pickedUpAt) }
        )
    }

    @Test("Park at the arrival instant enters the place's history as a wait of zero")
    func parkAtTheArrivalInstant() throws {
        let context = try makeContext()
        let (place, parked) = try shiftAtOnePlace(parkAfter: 0, in: context)

        #expect(parked.pickupWait == 0)
        let metrics = everyWaitCounted(place)
        #expect(metrics.sampleCount == 3)
        #expect(metrics.medianDuration == 360, "6 minutes, where two manual pickups alone read 7")
        #expect(metrics.shortestDuration == 0)

        #expect(place.pickupWaitMetrics().medianDuration == 420, "The app's figure now leaves it out")
    }

    @Test("Correcting the pickup Park recorded rederives the place's median at once")
    func correctionRederives() throws {
        let context = try makeContext()
        let (place, parked) = try shiftAtOnePlace(parkAfter: 0.5, in: context)
        #expect(everyWaitCounted(place).medianDuration == 360)

        let proposed = DeliveryLifecycleRecord(parked).replacing(.pickedUp, with: at(109))
        try DeliveryService(context: context).correctRecordedTimes(parked, to: proposed)

        #expect(parked.pickupWait == 540)
        #expect(everyWaitCounted(place).medianDuration == 480, "8 minutes: nothing is cached to invalidate")
    }
}
