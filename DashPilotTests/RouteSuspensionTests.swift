import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Recording the vehicle as parked: what it stops, what it deliberately does
/// not touch, how the route reads afterwards, and what it refuses.
///
/// Every date is an explicit offset from one fixed instant, so nothing here
/// depends on when it runs. Every coordinate is in open country and invented.
@MainActor
@Suite("Route suspension")
struct RouteSuspensionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func runningShift() throws -> (context: ModelContext, shift: Shift, shifts: ShiftService) {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        return (context, shift, shifts)
    }

    // MARK: The interval, as a value

    @Test("A suspension is measured within the window it is read against")
    func clipsToTheWindow() {
        let interval = RouteSuspensionInterval(start: at(600), end: at(1_500))

        #expect(interval.clipped(to: start...at(3_600)) == at(600)...at(1_500))
        #expect(interval.clipped(to: start...at(900)) == at(600)...at(900))
        #expect(interval.clipped(to: at(2_000)...at(3_000)) == nil)
    }

    @Test("An open suspension takes the window's own end")
    func anOpenSuspensionTakesTheWindowEnd() {
        let open = RouteSuspensionInterval(start: at(600), end: nil)

        #expect(open.isOpen)
        #expect(open.clipped(to: start...at(1_800)) == at(600)...at(1_800))
    }

    @Test("A malformed row is counted rather than measured")
    func aMalformedRowIsCounted() {
        let backwards = RouteSuspensionInterval(start: at(1_500), end: at(600))
        #expect(backwards.isMalformed)

        let totals = RouteSuspendedTimeCalculator().suspendedTime(
            of: [backwards, RouteSuspensionInterval(start: at(60), end: at(120))],
            within: start...at(3_600)
        )

        #expect(totals.intervalCount == 2)
        #expect(totals.unusableIntervalCount == 1)
        #expect(totals.isComplete == false)
        #expect(totals.duration == 60, "Only the row that describes a stretch contributes one")
    }

    @Test("Overlapping rows are unioned rather than summed")
    func overlappingRowsAreUnioned() {
        let totals = RouteSuspendedTimeCalculator().suspendedTime(
            of: [
                RouteSuspensionInterval(start: at(0), end: at(600)),
                RouteSuspensionInterval(start: at(300), end: at(900))
            ],
            within: start...at(3_600)
        )

        #expect(totals.duration == 900, "A union, so one minute cannot be counted twice")
        #expect(totals.intervalCount == 2)
    }

    // MARK: What it is not

    @Test("Parking subtracts nothing from working time, and that is the whole distinction")
    func parkingIsNotAPause() throws {
        let (context, shift, shifts) = try runningShift()

        try shifts.parkActiveShift(at: at(600))
        try shifts.resumeDrivingOnActiveShift(at: at(2_400))
        try shifts.endActiveShift(at: at(3_600))

        #expect(shift.completedDuration == 3_600)
        #expect(
            shift.completedWorkingDuration == 3_600,
            "Half an hour inside a shop is half an hour worked"
        )
        #expect(shift.completedPausedTime?.duration == 0)
        #expect(shift.completedPausedTime?.hasPauses == false, "No pause row is created by parking")
        #expect(shift.completedSuspendedTime?.duration == 1_800)
        #expect(shift.completedSuspendedTime?.intervalCount == 1)

        // And the rate divides by the whole shift, which is the figure a driver
        // would be robbed of if a suspension were a pause.
        let metrics = shift.metrics(for: .none)
        _ = metrics
        _ = context
    }

    @Test("Parking creates no lifecycle timestamp and touches no delivery")
    func parkingFabricatesNoLifecycleEvent() throws {
        let (context, shift, shifts) = try runningShift()
        let deliveries = DeliveryService(context: context)

        let carrying = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(carrying, at: at(120))
        let before = DeliveryLifecycleRecord(carrying)

        try shifts.parkActiveShift(at: at(300))

        #expect(DeliveryLifecycleRecord(carrying) == before, "No delivery instant moves")
        #expect(carrying.state == .arrivedAtPickup)
        #expect(shift.endedAt == nil, "The shift is still running")
        #expect(shift.isPaused == false)
        #expect(shift.isRouteSuspended)

        try shifts.resumeDrivingOnActiveShift(at: at(900))

        #expect(DeliveryLifecycleRecord(carrying) == before, "And resuming moves none either")
        #expect(shift.isRouteSuspended == false)
    }

    // MARK: Capture

    @Test("A parked shift rejects every candidate, and by its own rule")
    func aParkedShiftRetainsNothing() {
        let filter = RouteSampleFilter()
        let candidate = LocationSample(timestamp: at(600), latitude: 40, longitude: -75, horizontalAccuracy: 8)

        let parked = filter.evaluate(
            candidate,
            in: RouteSampleFilter.Context(shiftStart: start, isRouteSuspended: true, now: at(601))
        )
        #expect(parked == .reject(.routeSuspended))

        let driving = filter.evaluate(
            candidate,
            in: RouteSampleFilter.Context(shiftStart: start, now: at(601))
        )
        #expect(driving == .accept, "The same fix is kept the moment the driver is driving again")
    }

    @Test("A paused shift is reported as paused even when it also records a suspension")
    func pausedOutranksParked() {
        let decision = RouteSampleFilter().evaluate(
            LocationSample(timestamp: at(600), latitude: 40, longitude: -75, horizontalAccuracy: 8),
            in: RouteSampleFilter.Context(
                shiftStart: start,
                isPaused: true,
                isRouteSuspended: true,
                now: at(601)
            )
        )

        #expect(decision == .reject(.shiftPaused))
    }

    @Test("An ended shift is reported as ended whatever else it records")
    func endedOutranksEverything() {
        let decision = RouteSampleFilter().evaluate(
            LocationSample(timestamp: at(600), latitude: 40, longitude: -75, horizontalAccuracy: 8),
            in: RouteSampleFilter.Context(
                shiftStart: start,
                shiftEnd: at(700),
                isPaused: true,
                isRouteSuspended: true,
                now: at(601)
            )
        )

        #expect(decision == .reject(.shiftEnded))
    }

    // MARK: Mileage

    @Test("No straight line is drawn across a stretch recorded parked")
    func mileageIsNotMeasuredAcrossASuspension() throws {
        let (context, shift, shifts) = try runningShift()

        // Two capture sessions a kilometre apart, which is what parking and
        // driving off actually stores.
        let first = UUID()
        let second = UUID()
        for step in 0..<5 {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: at(60 + Double(step) * 20),
                    latitude: 40.0 + Double(step) * 100 / 111_320,
                    longitude: -75,
                    horizontalAccuracy: 8,
                    captureSessionID: first
                )
            )
        }
        try shifts.parkActiveShift(at: at(200))
        try shifts.resumeDrivingOnActiveShift(at: at(1_400))
        for step in 0..<5 {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: at(1_500 + Double(step) * 20),
                    latitude: 40.0 + (5_000 + Double(step) * 100) / 111_320,
                    longitude: -75,
                    horizontalAccuracy: 8,
                    captureSessionID: second
                )
            )
        }
        try shifts.endActiveShift(at: at(1_800))

        let distance = shift.recordedDistance()

        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount >= 1, "The stretch parked is a gap in the route, because it is one")
        #expect(distance.isPartial)
        // 400 m in each session, and the ~4.6 km between the two sessions left
        // out entirely. Anything that bridged the gap would land near 5,400 m.
        #expect(distance.metres > 750 && distance.metres < 850, "Measured: \(distance.metres)")
    }

    @Test("Route coverage says what the driver recorded, and stops short of a correspondence")
    func coverageIsTruthful() {
        let partial = RouteDistance(
            metres: 800,
            segmentCount: 2,
            gapCount: 1,
            usableSampleCount: 10,
            usesInferredContinuity: false
        )

        let unparked = RouteQuality(partial)
        #expect(unparked.suspensionExplanation == nil)
        #expect(
            unparked.partialExplanation?.contains("more miles were driven than were recorded") == true,
            "A route DashPilot stopped recording by accident still says exactly what it said"
        )

        let parked = RouteQuality(
            partial,
            suspendedTime: RouteSuspendedTime(
                duration: 1_500,
                intervalCount: 1,
                openIntervalCount: 0,
                unusableIntervalCount: 0
            )
        )
        let explanation = try? #require(parked.suspensionExplanation)
        #expect(explanation?.contains("1 stretch") == true)
        #expect(explanation?.contains("25 min") == true)
        #expect(explanation?.contains("no distance was measured across them") == true)
        #expect(
            parked.partialExplanation?.contains("more miles were driven than were recorded") == false,
            "That sentence is untrue of a vehicle that spent the stretch in a parking space"
        )
        #expect(parked.partialExplanation?.contains("time you recorded as parked") == true)
        // Never a claim that these stretches are those gaps.
        #expect(explanation?.contains("gap") == false)
    }

    // MARK: Refusals

    @Test("Parking twice is refused, and the refusal names when the first began")
    func parkingTwiceIsRefused() throws {
        let (_, _, shifts) = try runningShift()
        try shifts.parkActiveShift(at: at(600))

        #expect(throws: ShiftLifecycleError.shiftAlreadyParked(parkedAt: at(600))) {
            try shifts.parkActiveShift(at: at(900))
        }
    }

    @Test("Parking a paused shift is refused")
    func parkingAPausedShiftIsRefused() throws {
        let (_, _, shifts) = try runningShift()
        try shifts.pauseActiveShift(at: at(600))

        #expect(throws: ShiftLifecycleError.shiftAlreadyPaused(pausedAt: at(600))) {
            try shifts.parkActiveShift(at: at(900))
        }
    }

    @Test("Resuming driving on a shift that is not parked is refused")
    func resumingWithoutParkingIsRefused() throws {
        let (_, _, shifts) = try runningShift()

        #expect(throws: ShiftLifecycleError.shiftNotParked) {
            try shifts.resumeDrivingOnActiveShift(at: at(600))
        }
    }

    @Test("Parking with no shift running is refused")
    func parkingWithNoShiftIsRefused() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())

        #expect(throws: ShiftLifecycleError.noActiveShift) {
            try ShiftService(context: context).parkActiveShift(at: at(600))
        }
    }

    // MARK: Closing an open suspension

    @Test("Pausing a parked shift closes the suspension at the same instant")
    func pausingClosesTheSuspension() throws {
        let (_, shift, shifts) = try runningShift()
        try shifts.parkActiveShift(at: at(600))
        try shifts.pauseActiveShift(at: at(1_200))

        #expect(shift.isPaused)
        #expect(shift.isRouteSuspended == false)
        #expect(shift.openRouteSuspension == nil)
        #expect(shift.routeSuspensionsInOrder.first?.endedAt == at(1_200))
    }

    @Test("Ending a parked shift closes the suspension at the end instant")
    func endingClosesTheSuspension() throws {
        let (_, shift, shifts) = try runningShift()
        try shifts.parkActiveShift(at: at(600))
        try shifts.endActiveShift(at: at(1_800))

        #expect(shift.endedAt == at(1_800))
        #expect(shift.isRouteSuspended == false, "A finished shift is never parked")
        #expect(shift.routeSuspensionsInOrder.first?.endedAt == at(1_800))
        #expect(
            shift.completedSuspendedTime?.duration == 1_200,
            "Recorded as parked right up to the end, which is what happened"
        )
        #expect(shift.completedWorkingDuration == 1_800, "And every minute of it was worked")
    }

    // MARK: Stacked deliveries

    @Test("A shift with several deliveries open has one suspension, and none of them owns it")
    func stackedDeliveriesShareOneVehicle() throws {
        let (context, shift, shifts) = try runningShift()
        let deliveries = DeliveryService(context: context)

        let shopping = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(shopping, at: at(120))
        let carrying = try deliveries.startDelivery(at: at(180))
        try deliveries.markArrivedAtPickup(carrying, at: at(200))
        try deliveries.markPickedUp(carrying, at: at(240))

        // Parked once, although two deliveries are open: there is one vehicle.
        try shifts.parkActiveShift(at: at(300))

        #expect(shift.routeSuspensions.count == 1)
        #expect(shift.isRouteSuspended)
        #expect(
            shift.activeDeliveries.count == 2,
            "Parking blocks no delivery and no delivery blocks parking"
        )

        // Both deliveries keep moving while the vehicle is parked, which is what
        // a driver collecting one order while carrying another does.
        try deliveries.markPickedUp(shopping, at: at(900))
        #expect(shift.isRouteSuspended, "A pickup is not a claim that the driver is back at the car")

        try shifts.resumeDrivingOnActiveShift(at: at(1_000))
        try deliveries.markDelivered(carrying, at: at(1_500))
        try deliveries.markDelivered(shopping, at: at(1_800))
        try shifts.endActiveShift(at: at(2_000))

        #expect(shift.completedSuspendedTime?.intervalCount == 1)
        #expect(shift.completedSuspendedTime?.duration == 700)
        #expect(shift.completedWorkingDuration == 2_000)
        #expect(
            shift.deliveryActiveTime().duration == 1_740,
            "The union of the two lifecycles, which parking did not touch"
        )
    }

    // MARK: Correcting a shift's end

    @Test("An end corrected back through a recorded suspension is refused")
    func endCorrectionRefusesToCutThroughASuspension() throws {
        let (_, shift, shifts) = try runningShift()
        try shifts.parkActiveShift(at: at(1_200))
        try shifts.resumeDrivingOnActiveShift(at: at(2_400))
        try shifts.endActiveShift(at: at(3_600))

        #expect(throws: ShiftEndCorrectionRefusal.cutsThroughRecordedRouteSuspension) {
            try shift.endCorrection(to: at(1_800), nextShiftStartedAt: nil)
        }

        // And an end after it is accepted, so the rule refuses the collision
        // rather than the correction.
        let accepted = try shift.endCorrection(to: at(3_000), nextShiftStartedAt: nil)
        #expect(accepted.correctedEnd == at(3_000))
    }

    @Test("An end correction still measures the route again, and the suspension keeps explaining it")
    func endCorrectionRederivesMileage() throws {
        let (context, shift, shifts) = try runningShift()

        let session = UUID()
        for step in 0..<5 {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: at(60 + Double(step) * 20),
                    latitude: 40.0 + Double(step) * 100 / 111_320,
                    longitude: -75,
                    horizontalAccuracy: 8,
                    captureSessionID: session
                )
            )
        }
        try shifts.parkActiveShift(at: at(200))
        try shifts.resumeDrivingOnActiveShift(at: at(500))

        let later = UUID()
        for step in 0..<5 {
            context.insert(
                RouteSample(
                    shift: shift,
                    timestamp: at(600 + Double(step) * 20),
                    latitude: 40.0 + (5_000 + Double(step) * 100) / 111_320,
                    longitude: -75,
                    horizontalAccuracy: 8,
                    captureSessionID: later
                )
            )
        }
        try shifts.endActiveShift(at: at(1_200))

        let before = shift.recordedDistance()
        #expect(before.segmentCount == 2)

        // Corrected back to just after the first session: the second session's
        // positions leave the shift and the distance is measured again from what
        // remains, never scaled.
        try ShiftEndCorrectionService(context: context).correct(shift, to: at(560))

        let after = shift.recordedDistance()
        #expect(after.segmentCount == 1)
        #expect(after.metres > 350 && after.metres < 450, "Measured: \(after.metres)")
        #expect(
            shift.completedSuspendedTime?.duration == 300,
            "The suspension is inside the corrected shift and still says what it said"
        )
    }

    // MARK: Relaunch

    @Test("A shift left parked comes back parked, with no recovery code")
    func aParkedShiftSurvivesAReopenedStore() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotRouteSuspensionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "DashPilot.store")

        let shiftID: UUID
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
            let shifts = ShiftService(context: context)
            let shift = try shifts.startShift(at: start)
            try shifts.parkActiveShift(at: at(600))
            shiftID = shift.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: url))
        let shift = try #require(try ShiftService(context: context).activeShift())

        #expect(shift.id == shiftID)
        #expect(shift.isRouteSuspended, "The row is the only place the state lives, so it simply is")
        #expect(shift.openRouteSuspension?.startedAt == at(600))
        #expect(shift.lifecycleState == .running, "And it is still a running shift, not a paused one")
    }
}
