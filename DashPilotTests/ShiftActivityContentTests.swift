import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What the shift's Live Activity is told, and what it may offer.
///
/// The claims under test are the ones a Lock Screen makes hardest to check by
/// eye: that every figure is the app's own figure rather than a second
/// calculation; that the controls follow the lifecycle rules the services
/// enforce rather than a copy of them; that a stacked shift offers nothing
/// instead of guessing; and that the surface never carries an amount, a rate, a
/// place or a coordinate.
@MainActor
@Suite("Shift Live Activity content")
struct ShiftActivityContentTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let locale = Locale(identifier: "en_US")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A running shift in a store, with `count` positions recorded 20 m apart.
    @discardableResult
    private func record(
        _ count: Int,
        from index: Int,
        for shift: Shift,
        in session: UUID,
        context: ModelContext
    ) throws -> [RouteSample] {
        let samples = (index..<(index + count)).map { step in
            RouteSample(
                shift: shift,
                sample: SyntheticRoute.sample(at: at(Double(step)), northMetres: Double(step) * 20),
                captureSessionID: session
            )
        }
        for sample in samples { context.insert(sample) }
        try context.save()
        return samples
    }

    private func startedShift(in context: ModelContext) throws -> Shift {
        let shift = try ShiftService(context: context).startShift(at: start)
        return shift
    }

    // MARK: The figures are the app's own figures

    @Test("The working figure is the shift's working duration, not its elapsed one")
    func carriesWorkingDurationRatherThanElapsed() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(600))
        try service.resumeActiveShift(at: at(1_200))

        let state = shift.activityContentState(for: .none, asOf: at(1_800), locale: locale)

        #expect(state.workingDuration == shift.workingDuration(asOf: at(1_800)))
        #expect(state.workingDuration == 1_200, "Half an hour paused out of an hour elapsed")
        #expect(shift.elapsed(asOf: at(1_800)) == 1_800)
    }

    @Test("The mileage sentence is the one the app writes everywhere else")
    func carriesTheAppsOwnMileageSentence() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        try record(40, from: 0, for: shift, in: UUID(), context: context)

        let distance = shift.recordedDistance()
        let state = shift.activityContentState(for: distance, asOf: at(40), locale: locale)

        #expect(state.mileageStatement == RouteQuality(distance).mileageStatement(locale: locale))
        #expect(state.mileageStatement.contains("recorded"))
    }

    @Test("A route with a gap carries the partial marker beside the figure")
    func carriesThePartialMarker() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        // Two capture sessions, which is what a pause and a resume produce.
        try record(20, from: 0, for: shift, in: UUID(), context: context)
        try record(20, from: 600, for: shift, in: UUID(), context: context)

        let distance = shift.recordedDistance()
        let state = shift.activityContentState(for: distance, asOf: at(620), locale: locale)

        #expect(distance.gapCount == 1)
        #expect(state.partialRouteMarker == "partial route")
        #expect(state.mileageLine.hasSuffix("· partial route"))
        #expect(state.spokenMileageLine.contains("Partial route"))
    }

    @Test("A shift with no route says so rather than showing no miles")
    func saysThereIsNoRouteRatherThanZero() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)

        let state = shift.activityContentState(for: .none, asOf: at(60), locale: locale)

        #expect(state.mileageStatement == "No route recorded")
        #expect(state.partialRouteMarker == nil, "A route that does not exist is not a route with gaps in it")
        #expect(state.mileageLine == "No route recorded")
    }

    @Test("The delivery counts are the shift's own summary")
    func carriesTheShiftsDeliveryCounts() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let first = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(first, at: at(20))
        try deliveries.markPickedUp(first, at: at(30))
        try deliveries.markDelivered(first, at: at(40))
        _ = try deliveries.startDelivery(at: at(50))
        _ = try deliveries.startDelivery(at: at(60))

        let state = shift.activityContentState(for: .none, asOf: at(70), locale: locale)

        #expect(state.activeDeliveryCount == shift.deliverySummary.inProgress)
        #expect(state.completedDeliveryCount == shift.deliverySummary.completed)
        #expect(state.activeDeliveryCount == 2)
        #expect(state.completedDeliveryCount == 1)
        #expect(state.deliveryLine == "2 in progress · 1 delivered")
        #expect(state.spokenDeliveryLine == "2 deliveries in progress. 1 delivery delivered")
    }

    // MARK: What a driver is told about the one delivery in progress

    @Test("One delivery in progress names what it is doing")
    func namesWhatTheOneDeliveryIsDoing() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let delivery = try DeliveryService(context: context).startDelivery(at: at(10))
        try DeliveryService(context: context).markArrivedAtPickup(delivery, at: at(20))

        let state = shift.activityContentState(for: .none, asOf: at(30), locale: locale)

        #expect(state.deliveryStatus == DeliveryState.arrivedAtPickup.statusDescription)
        #expect(state.deliveryStatus == "Waiting at the pickup")
    }

    @Test("No delivery in progress says nothing about one")
    func saysNothingAboutADeliveryWhenThereIsNone() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)

        #expect(shift.activityContentState(for: .none, asOf: at(30), locale: locale).deliveryStatus == nil)
    }

    @Test("Two deliveries in progress name neither of them")
    func namesNeitherOfTwoDeliveries() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let first = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(first, at: at(20))
        _ = try deliveries.startDelivery(at: at(30))

        let state = shift.activityContentState(for: .none, asOf: at(40), locale: locale)

        #expect(
            state.deliveryStatus == nil,
            "With two orders in the car there is no 'the delivery' for a status line to describe"
        )
    }

    // MARK: Which controls are offered

    @Test("A running shift with nothing open offers Pause and End")
    func offersPauseAndEndOnAQuietRunningShift() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)

        #expect(shift.activityContentState(for: .none, asOf: at(30), locale: locale).controls == [.pause, .end])
    }

    @Test("A running shift with one delivery open offers that delivery's next step and nothing else")
    func offersOnlyTheNextStep() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))

        #expect(
            shift.activityContentState(for: .none, asOf: at(20), locale: locale).controls
                == [.deliveryStep(.arriveAtPickup)]
        )

        try deliveries.markArrivedAtPickup(delivery, at: at(30))
        #expect(
            shift.activityContentState(for: .none, asOf: at(40), locale: locale).controls
                == [.deliveryStep(.pickUp)]
        )

        try deliveries.markPickedUp(delivery, at: at(50))
        #expect(
            shift.activityContentState(for: .none, asOf: at(60), locale: locale).controls
                == [.deliveryStep(.complete)]
        )
    }

    @Test("Pause and End are withheld while a delivery is open, which is the rule the service enforces")
    func withholdsPauseAndEndWhileADeliveryIsOpen() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))

        let controls = shift.activityContentState(for: .none, asOf: at(20), locale: locale).controls
        #expect(!controls.contains(.pause))
        #expect(!controls.contains(.end))

        // The same two refusals, from the service that actually holds the rule.
        #expect(throws: ShiftLifecycleError.activeDeliveriesBlockPause(count: 1)) {
            try service.pauseActiveShift(at: at(20))
        }
        #expect(throws: ShiftLifecycleError.activeDeliveriesInProgress(count: 1)) {
            try service.endActiveShift(at: at(20))
        }
    }

    @Test("A stacked shift offers nothing at all, and says why")
    func offersNothingWhileSeveralDeliveriesAreOpen() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        _ = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(20))

        let state = shift.activityContentState(for: .none, asOf: at(30), locale: locale)

        #expect(state.controls.isEmpty, "Refusing is the answer; choosing one of two orders is not")
        #expect(state.controlNotice?.contains("Several deliveries") == true)
        #expect(state.controlNotice?.contains("Open DashPilot") == true)
    }

    @Test("A paused shift offers Resume and End")
    func offersResumeAndEndWhilePaused() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(60))

        let state = shift.activityContentState(for: .none, asOf: at(120), locale: locale)

        #expect(state.isPaused)
        #expect(state.controls == [.resume, .end])
        #expect(state.controlNotice == nil)
    }

    @Test("Ending a paused shift is offered because the service permits it")
    func offersEndOnAPausedShiftBecauseItIsPermitted() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(60))

        #expect(shift.activityContentState(for: .none, asOf: at(120), locale: locale).controls.contains(.end))

        try service.endActiveShift(at: at(180))
        #expect(shift.endedAt == at(180))
        #expect(shift.completedWorkingDuration == 60, "The pause was closed at the end instant")
    }

    // MARK: The vocabulary cannot drift from the app's

    @Test("Every delivery step is named exactly as the app's own control names it")
    func stepTitlesMatchTheAppsActionTitles() {
        let pairs: [(DeliveryAction, ShiftActivityDeliveryStep)] = [
            (.arriveAtPickup, .arriveAtPickup),
            (.pickUp, .pickUp),
            (.complete, .complete)
        ]

        for (action, step) in pairs {
            #expect(ShiftActivityDeliveryStep(action) == step)
            #expect(step.title == action.title)
            #expect(step.spokenLabel == action.spokenLabel)
        }

        #expect(
            ShiftActivityDeliveryStep(.start) == nil,
            "Starting a delivery is not a step of an existing one"
        )
        #expect(
            ShiftActivityDeliveryStep.allCases.count == DeliveryAction.allCases.count - 1,
            "Every action but start has exactly one step"
        )
    }

    @Test("The status heading matches the app's own lifecycle titles")
    func statusHeadingsMatchTheAppsTitles() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)

        #expect(
            shift.activityContentState(for: .none, asOf: at(10), locale: locale).statusTitle
                == ShiftLifecycleState.running.title
        )

        try service.pauseActiveShift(at: at(20))
        #expect(
            shift.activityContentState(for: .none, asOf: at(30), locale: locale).statusTitle
                == ShiftLifecycleState.paused.title
        )
    }

    // MARK: What must never be on a Lock Screen

    @Test("Nothing on the surface carries money, a rate, a place or a coordinate")
    func carriesNothingSensitive() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        try record(40, from: 0, for: shift, in: UUID(), context: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(delivery, at: at(20))
        _ = try PickupPlaceService(context: context).assignPlace(named: "Corner Cafe", to: delivery, at: at(25))

        let state = shift.activityContentState(for: shift.recordedDistance(), asOf: at(60), locale: locale)

        // Everything the surface can print, in one place.
        let printed = [
            state.statusTitle,
            state.formattedWorkingTime,
            state.spokenWorkingTime,
            state.mileageLine,
            state.spokenMileageLine,
            state.deliveryLine,
            state.spokenDeliveryLine,
            state.spokenSummary,
            state.compactDeliveryCount,
            state.deliveryStatus,
            state.controlNotice
        ].compactMap { $0 } + state.controls.flatMap { [$0.title, $0.spokenLabel] }

        for line in printed {
            #expect(!line.contains("$"), "No amount reaches a Lock Screen: \(line)")
            #expect(!line.lowercased().contains("earn"), "No earnings vocabulary: \(line)")
            #expect(!line.lowercased().contains("per hour"), "No rate: \(line)")
            #expect(!line.lowercased().contains("per mile"), "No rate: \(line)")
            #expect(!line.contains("Corner Cafe"), "No pickup place: \(line)")
            #expect(!line.contains("40.0"), "No coordinate: \(line)")
            #expect(!line.contains("-75.0"), "No coordinate: \(line)")
        }
    }

    @Test("The snapshot encodes and decodes as the same snapshot")
    func roundTripsThroughCoding() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))
        let state = shift.activityContentState(for: .none, asOf: at(20), locale: locale)

        let decoded = try JSONDecoder().decode(
            ShiftActivityAttributes.ContentState.self,
            from: try JSONEncoder().encode(state)
        )

        #expect(decoded == state)
        #expect(decoded.controls == [.deliveryStep(.arriveAtPickup)])
    }

    // MARK: The working clock the system draws

    @Test("The working clock is anchored so the system can count it without an update")
    func anchorsTheWorkingClock() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)

        let first = shift.activityContentState(for: .none, asOf: at(600), locale: locale)
        let later = shift.activityContentState(for: .none, asOf: at(3_000), locale: locale)

        #expect(first.workingTimerAnchor == start)
        #expect(
            later.workingTimerAnchor == first.workingTimerAnchor,
            "A running shift's anchor does not move, which is why no update is needed for the clock"
        )
        #expect(first.workingTimerRange.upperBound == .distantFuture)
    }

    @Test("A paused shift's working figure is fixed, and is drawn rather than counted")
    func holdsTheWorkingFigureStillWhilePaused() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(600))

        let atPause = shift.activityContentState(for: .none, asOf: at(600), locale: locale)
        let muchLater = shift.activityContentState(for: .none, asOf: at(4_200), locale: locale)

        #expect(atPause.workingDuration == 600)
        #expect(muchLater.workingDuration == 600, "An hour on a break is not an hour worked")
        #expect(muchLater.formattedWorkingTime == atPause.formattedWorkingTime)
    }

    /// The paused figure sits where the running clock sat, so it has to be
    /// written the way the system writes that clock: minutes and seconds under
    /// an hour, and the hour field only once there is one.
    @Test("The paused figure is written the way the system's own timer is")
    func writesThePausedFigureLikeTheSystemTimer() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(51))

        #expect(shift.activityContentState(for: .none, asOf: at(60), locale: locale).formattedWorkingTime == "0:51")

        try service.resumeActiveShift(at: at(60))
        try service.pauseActiveShift(at: at(3_660))
        // 51 seconds worked before the break, then an hour after it.
        let long = shift.activityContentState(for: .none, asOf: at(3_700), locale: locale)
        #expect(long.workingDuration == 3_651)
        #expect(long.formattedWorkingTime == "1:00:51")
    }

    @Test("The spoken working figure is words rather than a clock string")
    func speaksTheWorkingFigureInWords() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(3_661))

        let spoken = shift.activityContentState(for: .none, asOf: at(3_700), locale: locale).spokenWorkingTime

        #expect(spoken.contains("hour"))
        #expect(spoken.contains("minute"))
        #expect(spoken.contains("second"))
        #expect(!spoken.contains(":"), "A colon is heard as punctuation, not as a time")
    }
}
