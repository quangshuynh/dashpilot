import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What the shift's Live Activity is told, and what it may offer.
///
/// The claims under test are the ones a Lock Screen makes hardest to check by
/// eye: that every figure is the app's own figure rather than a second
/// calculation; that the controls follow the lifecycle rules the services
/// enforce rather than a copy of them; that a stacked shift withholds the step
/// instead of guessing, while still offering the one control that names no
/// existing order; and that the surface never carries an amount, a rate, a place
/// or a coordinate.
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

    // MARK: How long the deliveries in progress have been open

    @Test("One delivery in progress is counted from its own acceptance instant")
    func countsTheOneDeliveryFromItsOwnAcceptance() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let delivery = try DeliveryService(context: context).startDelivery(at: at(10))

        let state = shift.activityContentState(for: .none, asOf: at(1_090), locale: locale)
        let timer = try #require(state.activeDeliveryTimers.first)

        #expect(state.activeDeliveryTimers.count == 1)
        #expect(
            timer.startedAt == delivery.acceptedAt,
            "The delivery's own acceptedAt, which is where every other duration derived from it starts"
        )
        #expect(timer.timerRange.lowerBound == delivery.acceptedAt)
        #expect(
            timer.timerRange.upperBound == .distantFuture,
            "A delivery that runs long keeps counting rather than stopping at a horizon"
        )
    }

    @Test("The timer names the delivery the way the rest of the app names it")
    func namesTheDeliveryAsTheAppDoes() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let first = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(first, at: at(12))
        try deliveries.markPickedUp(first, at: at(15))
        try deliveries.markDelivered(first, at: at(20))
        _ = try deliveries.startDelivery(at: at(30))

        let state = shift.activityContentState(for: .none, asOf: at(40), locale: locale)
        let timer = try #require(state.activeDeliveryTimers.first)
        let numbered = try #require(shift.numberedActiveDeliveries.first)

        #expect(timer.title == numbered.title)
        #expect(
            timer.title == NumberedDelivery.title(number: 2),
            "Numbering runs over the whole shift, so the second delivery stays Delivery 2"
        )
    }

    @Test("The anchor does not move as time passes, so nothing has to be pushed to keep it right")
    func holdsTheDeliveryAnchorStillAsTimePasses() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))

        let early = shift.activityContentState(for: .none, asOf: at(60), locale: locale)
        let later = shift.activityContentState(for: .none, asOf: at(3_600), locale: locale)

        #expect(early.activeDeliveryTimers == later.activeDeliveryTimers)
        #expect(
            ShiftActivityUpdatePolicy.change(from: early, to: later) == .none,
            "A clock the system draws from an anchor is not a reason to hand over a snapshot"
        )
    }

    @Test("The elapsed figure is the time since the delivery was accepted, spoken with its subject")
    func speaksHowLongTheDeliveryHasBeenActive() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))

        let state = shift.activityContentState(for: .none, asOf: at(1_090), locale: locale)
        let timer = try #require(state.activeDeliveryTimers.first)

        #expect(timer.elapsed(asOf: at(1_090)) == 1_080, "Eighteen minutes since it was accepted")
        #expect(timer.elapsed(asOf: at(10)) == 0)
        #expect(
            timer.elapsed(asOf: at(0)) == 0,
            "A reference date before the acceptance is clamped rather than counted backwards"
        )

        let spoken = timer.spokenElapsed(asOf: at(1_090))
        #expect(spoken.contains("Delivery 1"))
        #expect(spoken.contains("18"))
        #expect(!spoken.contains(":"), "A colon is heard as punctuation, not as a time")

        #expect(
            timer.spokenLabel == "Delivery 1, to pickup. How long it has been active",
            "The live figure is left unlabelled, so the label beside it has to say what it measures"
        )
        #expect(
            spoken == "Delivery 1, to pickup, active for 18 minutes",
            "And the frozen sentence carries the state too, for the presentation with no live element"
        )
    }

    @Test("Each open delivery's row says what that delivery is doing")
    func statesWhatEachStackedDeliveryIsDoing() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)

        let waiting = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(waiting, at: at(20))
        _ = try deliveries.startDelivery(at: at(30))

        let state = shift.activityContentState(for: .none, asOf: at(60), locale: locale)

        // With two open there is no "the delivery", so the card's single
        // status line is withheld. Without a state on each row, a Lock Screen
        // would name both deliveries and say what neither of them was waiting
        // for, which is exactly the glance the surface exists for.
        #expect(state.deliveryStatus == nil)
        #expect(state.activeDeliveryTimers.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(state.activeDeliveryTimers.map(\.stateLabel) == ["At pickup", "To pickup"])
        #expect(
            state.activeDeliveryTimers.map(\.stateLabel) == [
                DeliveryState.arrivedAtPickup.compactStatusDescription,
                DeliveryState.accepted.compactStatusDescription
            ],
            "The word is the app's own, shortened for a line it shares, never a second vocabulary"
        )

        let spoken = state.activeDeliveryTimers.map(\.spokenLabel)
        #expect(spoken == [
            "Delivery 1, at pickup. How long it has been active",
            "Delivery 2, to pickup. How long it has been active"
        ])
    }

    @Test("Advancing one stacked delivery moves its row and no other")
    func advancingOneStackedDeliveryMovesOnlyItsRow() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)

        let first = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(20))

        let before = shift.activityContentState(for: .none, asOf: at(60), locale: locale)
        #expect(before.activeDeliveryTimers.map(\.stateLabel) == ["To pickup", "To pickup"])

        try deliveries.markArrivedAtPickup(first, at: at(70))
        let after = shift.activityContentState(for: .none, asOf: at(80), locale: locale)

        #expect(after.activeDeliveryTimers.map(\.stateLabel) == ["At pickup", "To pickup"])
        #expect(
            after.activeDeliveryTimers.map(\.startedAt) == before.activeDeliveryTimers.map(\.startedAt),
            "Neither clock is restarted by a state moving: each still counts from its own acceptance"
        )
        #expect(
            ShiftActivityUpdatePolicy.change(from: before, to: after) == .material,
            "A state the card prints has to reach the card at once, not on the route's throttle"
        )
    }

    @Test("A delivered delivery stops counting by leaving the card, not by freezing")
    func stopsCountingOnceTheDeliveryIsDelivered() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))

        #expect(shift.activityContentState(for: .none, asOf: at(20), locale: locale).activeDeliveryTimers.count == 1)

        try deliveries.markArrivedAtPickup(delivery, at: at(100))
        try deliveries.markPickedUp(delivery, at: at(300))
        try deliveries.markDelivered(delivery, at: at(600))
        let after = shift.activityContentState(for: .none, asOf: at(900), locale: locale)

        #expect(after.activeDeliveryTimers.isEmpty, "A terminal delivery is not an active one")
        #expect(after.completedDeliveryCount == 1)
        #expect(
            delivery.completedDuration == 590,
            "And the finished delivery's own duration is the one it always was"
        )
    }

    @Test("A cancelled delivery stops counting in exactly the same way")
    func stopsCountingOnceTheDeliveryIsCancelled() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))
        try deliveries.cancelDelivery(delivery, at: at(600))

        let after = shift.activityContentState(for: .none, asOf: at(900), locale: locale)

        #expect(after.activeDeliveryTimers.isEmpty)
        #expect(after.completedDeliveryCount == 0, "A cancellation is not a completion")
        #expect(after.deliveryLine == "No delivery in progress")
    }

    @Test("A reopened delivery counts from the acceptance it always had")
    func countsAReopenedDeliveryFromItsOriginalAcceptance() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))
        try deliveries.markArrivedAtPickup(delivery, at: at(100))
        try deliveries.markPickedUp(delivery, at: at(300))
        try deliveries.markDelivered(delivery, at: at(600))
        try deliveries.reopenDelivered(delivery)

        let after = shift.activityContentState(for: .none, asOf: at(700), locale: locale)
        let timer = try #require(after.activeDeliveryTimers.first)

        #expect(
            timer.startedAt == at(10),
            "Reopening clears the completion and nothing else, so the clock resumes from the acceptance"
        )
    }

    @Test("Stacked deliveries each carry their own timer, and nothing adds them together")
    func countsEachStackedDeliverySeparately() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        _ = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(610))

        let state = shift.activityContentState(for: .none, asOf: at(1_210), locale: locale)

        #expect(state.activeDeliveryTimers.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(state.activeDeliveryTimers.map(\.startedAt) == [at(10), at(610)])
        #expect(state.activeDeliveryTimers.map { $0.elapsed(asOf: at(1_210)) } == [1_200, 600])
        #expect(
            !state.activeDeliveryTimers.contains { $0.elapsed(asOf: at(1_210)) == 1_800 },
            "Two overlapping lifecycles are not half an hour of anything"
        )
        #expect(
            state.deliveryStatus == nil,
            "Naming one of two orders is still refused; naming both of their clocks is not the same thing"
        )
    }

    @Test("Finishing one of two leaves the other counting under the number it already had")
    func leavesTheRemainingStackedDeliveryCounting() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let first = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(610))
        try deliveries.markArrivedAtPickup(first, at: at(700))
        try deliveries.markPickedUp(first, at: at(800))
        try deliveries.markDelivered(first, at: at(900))

        let state = shift.activityContentState(for: .none, asOf: at(1_000), locale: locale)
        let timer = try #require(state.activeDeliveryTimers.first)

        #expect(state.activeDeliveryTimers.count == 1)
        #expect(timer.title == "Delivery 2", "Finishing one does not renumber the other")
        #expect(timer.startedAt == at(610))
    }

    @Test("Beyond three open orders the card states the remainder rather than dropping it silently")
    func statesTheOpenDeliveriesItHasNoRoomToDraw() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        for step in 0..<4 { _ = try deliveries.startDelivery(at: at(Double(10 + step * 10))) }

        let state = shift.activityContentState(for: .none, asOf: at(1_000), locale: locale)

        #expect(state.activeDeliveryTimers.count == 4, "The snapshot carries every one of them")
        #expect(state.drawnDeliveryTimers.map(\.title) == ["Delivery 1", "Delivery 2", "Delivery 3"])
        #expect(state.undrawnDeliveryTimerCount == 1)
        #expect(state.undrawnDeliveryTimerNotice == "1 more also active")
        #expect(state.spokenUndrawnDeliveryTimerNotice?.contains("1 more delivery") == true)

        // Three is the last count that fits, so nothing is stated for it.
        try deliveries.cancelDelivery(try #require(shift.numberedActiveDeliveries.last).delivery, at: at(1_100))
        let three = shift.activityContentState(for: .none, asOf: at(1_200), locale: locale)
        #expect(three.drawnDeliveryTimers.count == 3)
        #expect(three.undrawnDeliveryTimerCount == 0)
        #expect(three.undrawnDeliveryTimerNotice == nil)
    }

    @Test("A shift with nothing open carries no timer at all")
    func carriesNoTimerWithNothingOpen() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)

        #expect(shift.activityContentState(for: .none, asOf: at(60), locale: locale).activeDeliveryTimers.isEmpty)
        #expect(shift.activityContentState(for: .none, asOf: at(60), locale: locale).undrawnDeliveryTimerNotice == nil)

        try service.pauseActiveShift(at: at(120))
        #expect(
            shift.activityContentState(for: .none, asOf: at(180), locale: locale).activeDeliveryTimers.isEmpty,
            "Pausing is refused while a delivery is open, so a paused card has nothing to count"
        )
    }

    @Test("The timers change nothing about the controls the card already offered")
    func leavesTheExistingControlsExactlyAsTheyWere() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)

        let quiet = shift.activityContentState(for: .none, asOf: at(5), locale: locale)
        #expect(quiet.controls == [.startDelivery, .park, .pause, .end])
        #expect(quiet.controlNotice == nil)

        let delivery = try deliveries.startDelivery(at: at(10))
        let carrying = shift.activityContentState(for: .none, asOf: at(20), locale: locale)
        #expect(carrying.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(carrying.activeDeliveryTimers.count == 1)
        #expect(carrying.controlNotice == nil)

        _ = try deliveries.startDelivery(at: at(30))
        let stacked = shift.activityContentState(for: .none, asOf: at(40), locale: locale)
        #expect(
            stacked.controls == [.startDelivery, .park],
            "The step is still withheld, for the reason it always was, and parking reads no delivery"
        )
        #expect(stacked.activeDeliveryTimers.count == 2, "And both orders are still counted")
        #expect(stacked.controlNotice?.contains("Several deliveries") == true)

        try deliveries.markArrivedAtPickup(delivery, at: at(50))
        try deliveries.markPickedUp(delivery, at: at(60))
        try deliveries.markDelivered(delivery, at: at(70))
        let afterOne = shift.activityContentState(for: .none, asOf: at(80), locale: locale)
        #expect(afterOne.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(afterOne.controlNotice == nil)
    }

    // MARK: Which controls are offered

    @Test("A running shift with nothing open offers Start Delivery, Pause and End")
    func offersStartPauseAndEndOnAQuietRunningShift() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)

        #expect(
            shift.activityContentState(for: .none, asOf: at(30), locale: locale).controls
                == [.startDelivery, .park, .pause, .end]
        )
    }

    @Test("A running shift with one delivery open offers that delivery's next step and one more start")
    func offersTheNextStepBesideStartingAnother() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(10))

        #expect(
            shift.activityContentState(for: .none, asOf: at(20), locale: locale).controls
                == [.deliveryStep(.arriveAtPickup), .startDelivery, .park]
        )

        try deliveries.markArrivedAtPickup(delivery, at: at(30))
        #expect(
            shift.activityContentState(for: .none, asOf: at(40), locale: locale).controls
                == [.deliveryStep(.pickUp), .startDelivery, .park]
        )

        try deliveries.markPickedUp(delivery, at: at(50))
        #expect(
            shift.activityContentState(for: .none, asOf: at(60), locale: locale).controls
                == [.deliveryStep(.complete), .startDelivery, .park]
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

    @Test("A stacked shift offers no step at all, and says why")
    func offersNoStepWhileSeveralDeliveriesAreOpen() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)
        _ = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(20))

        let state = shift.activityContentState(for: .none, asOf: at(30), locale: locale)

        #expect(
            state.controls == [.startDelivery, .park],
            "Refusing the step is the answer; choosing one of two orders is not"
        )
        #expect(state.controlNotice?.contains("Several deliveries") == true)
        #expect(state.controlNotice?.contains("Open DashPilot") == true)
    }

    // MARK: Starting one more delivery

    @Test("Start Delivery is offered on a running shift whatever it is carrying")
    func offersStartDeliveryOnEveryRunningShift() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)

        #expect(shift.activityContentState(for: .none, asOf: at(5), locale: locale).controls.contains(.startDelivery))

        let first = try deliveries.startDelivery(at: at(10))
        #expect(shift.activityContentState(for: .none, asOf: at(15), locale: locale).controls.contains(.startDelivery))

        _ = try deliveries.startDelivery(at: at(20))
        #expect(
            shift.activityContentState(for: .none, asOf: at(25), locale: locale).controls.contains(.startDelivery),
            "Stacking is what the control is for, so two orders do not withdraw it"
        )

        try deliveries.markArrivedAtPickup(first, at: at(30))
        try deliveries.markPickedUp(first, at: at(40))
        try deliveries.markDelivered(first, at: at(50))
        #expect(shift.activityContentState(for: .none, asOf: at(55), locale: locale).controls.contains(.startDelivery))
    }

    @Test("A paused shift does not offer Start Delivery, which is the rule the service enforces")
    func withholdsStartDeliveryWhilePaused() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(60))

        let controls = shift.activityContentState(for: .none, asOf: at(120), locale: locale).controls
        #expect(!controls.contains(.startDelivery))

        // The same refusal, from the service that actually holds the rule.
        #expect(throws: DeliveryLifecycleError.shiftPaused) {
            try DeliveryService(context: context).startDelivery(at: at(120))
        }

        try service.resumeActiveShift(at: at(180))
        #expect(
            shift.activityContentState(for: .none, asOf: at(200), locale: locale).controls.contains(.startDelivery),
            "Resuming brings it back"
        )
    }

    @Test("An ended shift's snapshot offers no Start Delivery, and the service refuses one")
    func withholdsStartDeliveryOnceTheShiftHasEnded() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.endActiveShift(at: at(600))

        #expect(shift.lifecycleState == .ended)
        #expect(throws: DeliveryLifecycleError.noActiveShift) {
            try DeliveryService(context: context).startDelivery(at: at(700))
        }
        #expect(try DeliveryService(context: context).activeDeliveries().isEmpty)
    }

    @Test("Start Delivery is named and spoken exactly as the app's own control is")
    func startDeliveryIsNamedAsTheAppNamesIt() {
        #expect(ShiftActivityControl.startDelivery.title == DeliveryAction.start.title)
        #expect(ShiftActivityControl.startDelivery.spokenLabel == DeliveryAction.start.spokenLabel)
        #expect(
            ShiftActivityControl.startDelivery.spokenLabel.lowercased().contains("delivery"),
            "A control on a Lock Screen names its subject"
        )
        #expect(
            ShiftActivityControl.startDelivery.symbolName != ShiftActivityDeliveryStep.pickUp.symbolName,
            "Adding an order and advancing one must not look the same"
        )
    }

    @Test("Only one control carries the emphasis, whichever pair the card is showing")
    func emphasisesExactlyOneControl() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        let deliveries = DeliveryService(context: context)

        let quiet = shift.activityContentState(for: .none, asOf: at(5), locale: locale).controls
        #expect(ShiftActivityControl.emphasised(in: quiet) == .startDelivery)
        #expect(
            ShiftActivityControl.park.isProminent == false,
            "Parking is bordered for the reason pausing is: the frequent control keeps the emphasis"
        )

        _ = try deliveries.startDelivery(at: at(10))
        let carrying = shift.activityContentState(for: .none, asOf: at(15), locale: locale).controls
        #expect(
            ShiftActivityControl.emphasised(in: carrying) == .deliveryStep(.arriveAtPickup),
            "The order already in the car is what the driver reached for"
        )
        #expect(carrying.filter(\.isProminent).count == 2, "Both would take it on their own, which is why the list decides")
        #expect(ShiftActivityControl.emphasised(in: []) == nil)
        #expect(
            ShiftActivityControl.emphasised(in: [.pause, .end]) == nil,
            "Neither lifecycle control is ever the emphasised one"
        )
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

    @Test("The notice is about the withheld step, and survives the card still offering a start")
    func explainsTheWithheldStepWhileStillOfferingAStart() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)

        #expect(shift.activityContentState(for: .none, asOf: at(5), locale: locale).controlNotice == nil)

        let first = try deliveries.startDelivery(at: at(10))
        #expect(
            shift.activityContentState(for: .none, asOf: at(15), locale: locale).controlNotice == nil,
            "One order has a step, so there is nothing to explain"
        )

        let second = try deliveries.startDelivery(at: at(20))
        let stacked = shift.activityContentState(for: .none, asOf: at(25), locale: locale)
        #expect(stacked.controlNotice != nil)
        #expect(
            !stacked.controls.isEmpty,
            "The notice is no longer derived from an empty list, because the list is not empty"
        )
        #expect(stacked.controls.allSatisfy { if case .deliveryStep = $0 { false } else { true } })

        // It lifts by itself once one of them is finished, exactly as before.
        try deliveries.cancelDelivery(second, at: at(30))
        #expect(shift.activityContentState(for: .none, asOf: at(35), locale: locale).controlNotice == nil)
        #expect(first.state == .accepted, "Finishing one leaves the other exactly as it was")
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
        // Both amounts a delivery can carry, because a Lock Screen is readable
        // by whoever is standing beside the phone and neither belongs there.
        try deliveries.setExpectedEarnings(try #require(Money(exact: "8.50")), on: delivery)
        try deliveries.markArrivedAtPickup(delivery, at: at(20))
        _ = try PickupPlaceService(context: context).assignPlace(named: "Corner Cafe", to: delivery, at: at(25))

        // A second order, so the timer lines and the remainder notice are both
        // part of what the sweep reads.
        try deliveries.setExpectedEarnings(try #require(Money(exact: "12.25")), on: try deliveries.startDelivery(at: at(30)))

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
            state.controlNotice,
            state.undrawnDeliveryTimerNotice,
            state.spokenUndrawnDeliveryTimerNotice
        ].compactMap { $0 }
            + state.controls.flatMap { [$0.title, $0.spokenLabel] }
            + state.activeDeliveryTimers.flatMap { [$0.title, $0.spokenLabel, $0.spokenElapsed(asOf: at(60))] }

        for line in printed {
            #expect(!line.contains("$"), "No amount reaches a Lock Screen: \(line)")
            #expect(!line.contains("8.50"), "Not an expected amount either: \(line)")
            #expect(!line.lowercased().contains("expect"), "No expectation vocabulary: \(line)")
            #expect(!line.lowercased().contains("earn"), "No earnings vocabulary: \(line)")
            #expect(!line.lowercased().contains("per hour"), "No rate: \(line)")
            #expect(!line.lowercased().contains("per mile"), "No rate: \(line)")
            #expect(!line.contains("Corner Cafe"), "No pickup place: \(line)")
            #expect(!line.contains("40.0"), "No coordinate: \(line)")
            #expect(!line.contains("-75.0"), "No coordinate: \(line)")
        }

        #expect(state.activeDeliveryTimers.count == 2, "The timers really were part of that sweep")
        #expect(
            state.activeDeliveryTimers.allSatisfy { $0.title.hasPrefix("Delivery ") },
            "A timer names a delivery by its position in the shift and by nothing else"
        )
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
        #expect(decoded.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(
            decoded.activeDeliveryTimers == state.activeDeliveryTimers,
            "The anchor has to survive the encoding, or the clock the extension draws is not this delivery's"
        )
        #expect(decoded.activeDeliveryTimers.map(\.startedAt) == [at(10)])
    }

    // MARK: The parked pair

    @Test("A running shift offers Park, and a parked one offers Resume Driving instead")
    func offersExactlyOneOfTheParkedPair() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)

        let driving = shift.activityContentState(for: .none, asOf: at(30), locale: locale)
        #expect(driving.controls.contains(.park))
        #expect(!driving.controls.contains(.resumeDriving))
        #expect(driving.routeSuspendedNotice == nil)

        try service.parkActiveShift(at: at(60))
        let parked = shift.activityContentState(for: .none, asOf: at(90), locale: locale)
        #expect(parked.controls.contains(.resumeDriving))
        #expect(!parked.controls.contains(.park))
        #expect(parked.routeSuspendedNotice != nil, "And the card says which state it is in")

        try service.resumeDrivingOnActiveShift(at: at(120))
        let drivingAgain = shift.activityContentState(for: .none, asOf: at(150), locale: locale)
        #expect(drivingAgain.controls.contains(.park))
        #expect(!drivingAgain.controls.contains(.resumeDriving))
        #expect(drivingAgain.routeSuspendedNotice == nil)
    }

    /// The claim in the form a card could break it: never both, in any state the
    /// app can put a shift into.
    @Test("The two parked controls are never on the card together")
    func neverOffersBothParkedControls() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)

        func assertNeverBoth(_ moment: TimeInterval, _ note: String) {
            let controls = shift.activityContentState(for: .none, asOf: at(moment), locale: locale).controls
            #expect(
                !(controls.contains(.park) && controls.contains(.resumeDriving)),
                "One of the two is always a transition the store would refuse: \(note)"
            )
        }

        assertNeverBoth(5, "quiet and driving")
        try service.parkActiveShift(at: at(10))
        assertNeverBoth(15, "quiet and parked")
        try service.resumeDrivingOnActiveShift(at: at(20))

        let delivery = try deliveries.startDelivery(at: at(30))
        assertNeverBoth(35, "one order, driving")
        try service.parkActiveShift(at: at(40))
        assertNeverBoth(45, "one order, parked")
        try service.resumeDrivingOnActiveShift(at: at(50))

        _ = try deliveries.startDelivery(at: at(60))
        assertNeverBoth(65, "two orders, driving")
        try service.parkActiveShift(at: at(70))
        assertNeverBoth(75, "two orders, parked")
        try service.resumeDrivingOnActiveShift(at: at(80))

        try deliveries.markArrivedAtPickup(delivery, at: at(90))
        assertNeverBoth(95, "one order at its pickup")
    }

    /// Parking is a **shift** operation. The two refusals that thin this list
    /// out are about a delivery nobody can name and about time nobody worked,
    /// and neither has anything to say about a vehicle nobody moved.
    @Test("The parked control survives the stacked refusal and the open-delivery refusal")
    func offersTheParkedControlWhateverTheShiftIsCarrying() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)

        _ = try deliveries.startDelivery(at: at(10))
        let one = shift.activityContentState(for: .none, asOf: at(20), locale: locale)
        #expect(one.controls == [.deliveryStep(.arriveAtPickup), .startDelivery, .park])
        #expect(!one.controls.contains(.pause), "Pausing is still refused over an open order")

        _ = try deliveries.startDelivery(at: at(30))
        let stacked = shift.activityContentState(for: .none, asOf: at(40), locale: locale)
        #expect(stacked.controls == [.startDelivery, .park])
        #expect(stacked.controlNotice?.contains("Several deliveries") == true, "The step is still the thing withheld")

        // And the service agrees: parking with two orders open writes the row.
        try service.parkActiveShift(at: at(50))
        #expect(shift.isRouteSuspended)
    }

    @Test("A paused shift offers neither parked control, because a paused shift is never parked")
    func offersNoParkedControlWhilePaused() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.pauseActiveShift(at: at(60))

        let state = shift.activityContentState(for: .none, asOf: at(120), locale: locale)
        #expect(state.controls == [.resume, .end])
        #expect(!state.controls.contains(.park))
        #expect(!state.controls.contains(.resumeDriving))

        // The same refusal, from the service that actually holds the rule.
        #expect(throws: ShiftLifecycleError.shiftAlreadyPaused(pausedAt: at(60))) {
            try service.parkActiveShift(at: at(120))
        }
    }

    @Test("Resume Driving leads the card and carries the emphasis, as it does in the app")
    func emphasisesResumeDrivingWhileParked() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))
        try service.parkActiveShift(at: at(20))

        let controls = shift.activityContentState(for: .none, asOf: at(30), locale: locale).controls

        #expect(controls.first == .resumeDriving, "Leaving the state is the tap that matters")
        #expect(ShiftActivityControl.emphasised(in: controls) == .resumeDriving)
        #expect(controls.contains(.deliveryStep(.arriveAtPickup)), "The order in the shop is still advanceable")
    }

    /// The one label on this card that could be acted on under a wrong belief.
    @Test("The parked controls name the vehicle and never say pause")
    func parkedControlsAreExplicitAboutTheirSubject() {
        #expect(ShiftActivityControl.park.title == "Park Vehicle")
        #expect(ShiftActivityControl.park.spokenLabel == "Park vehicle")
        #expect(ShiftActivityControl.resumeDriving.title == "Resume Driving")
        #expect(ShiftActivityControl.resumeDriving.spokenLabel == "Resume driving")

        for control in [ShiftActivityControl.park, .resumeDriving] {
            #expect(!control.title.lowercased().contains("pause"))
            #expect(!control.spokenLabel.lowercased().contains("pause"))
            #expect(!control.spokenLabel.lowercased().contains("break"))
        }

        // And a driver must be able to tell them from the shift's own pair
        // without reading either label.
        let symbols: [String] = [
            ShiftActivityControl.park.symbolName,
            ShiftActivityControl.resumeDriving.symbolName,
            ShiftActivityControl.pause.symbolName,
            ShiftActivityControl.resume.symbolName
        ]
        #expect(Set(symbols).count == 4)
    }

    /// The delivery rows and the mileage line are untouched by the pair: this
    /// sub-interval added controls and nothing else.
    @Test("Parking changes no delivery timer, no count and no mileage sentence")
    func leavesTheRestOfTheCardExactlyAsItWas() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        _ = try deliveries.startDelivery(at: at(10))
        _ = try deliveries.startDelivery(at: at(20))

        let before = shift.activityContentState(for: .none, asOf: at(30), locale: locale)
        try service.parkActiveShift(at: at(31))
        let after = shift.activityContentState(for: .none, asOf: at(30), locale: locale)

        #expect(after.activeDeliveryTimers == before.activeDeliveryTimers)
        #expect(after.activeDeliveryCount == before.activeDeliveryCount)
        #expect(after.completedDeliveryCount == before.completedDeliveryCount)
        #expect(after.deliveryStatus == before.deliveryStatus)
        #expect(after.mileageStatement == before.mileageStatement)
        #expect(after.partialRouteMarker == before.partialRouteMarker)
        #expect(after.workingDuration == before.workingDuration, "Parking subtracts nothing")
        #expect(after.isPaused == before.isPaused, "And it is not a pause")
        #expect(after.controls != before.controls, "Only the controls and the notice moved")
    }

    /// The compact and minimal presentations read the same three values they
    /// always did, and carry no control at all.
    @Test("Compact and minimal are unchanged by the parked pair")
    func leavesCompactAndMinimalAlone() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)

        let driving = shift.activityContentState(for: .none, asOf: at(30), locale: locale)
        try service.parkActiveShift(at: at(40))
        let parked = shift.activityContentState(for: .none, asOf: at(50), locale: locale)

        #expect(parked.compactDeliveryCount == driving.compactDeliveryCount)
        #expect(parked.statusSymbolName == driving.statusSymbolName, "Parked is not paused, so the glyph is unchanged")
        #expect(parked.statusTitle == driving.statusTitle)
        // The minimal presentation's one spoken value does gain the sentence,
        // because it is the only line a listener there has.
        #expect(parked.spokenSummary.contains("Parked."))
        #expect(!driving.spokenSummary.contains("Parked"))
    }

    /// A `ContentState` that fails to decode is an activity the app cannot see,
    /// and an activity the app cannot see is a second card. This is that risk,
    /// exercised against the shape the **previous** build persisted.
    ///
    /// The bytes are the real encoder's rather than hand-written ones, with the
    /// one key an older build did not have removed from them. That is what makes
    /// this a test of the persisted shape rather than a test of a fixture: a
    /// previous build encoded these same fields with this same synthesised
    /// `Codable`, and the only differences it could have are the parked notice
    /// it did not carry and the parked controls it could not name.
    @Test("A snapshot persisted by an earlier build still decodes")
    func decodesASnapshotFromAnEarlierBuild() throws {
        let context = try makeContext()
        let shift = try startedShift(in: context)
        _ = try DeliveryService(context: context).startDelivery(at: at(10))

        // Not parked, so every control here is one an earlier build could name.
        let state = shift.activityContentState(for: .none, asOf: at(20), locale: locale)
        #expect(state.routeSuspendedNotice == nil)
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        )
        #expect(object["controls"] != nil)

        // The shape from before the parked notice existed at all, which is what
        // the field was made optional for.
        object.removeValue(forKey: "routeSuspendedNotice")
        let decoded = try JSONDecoder().decode(
            ShiftActivityAttributes.ContentState.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.routeSuspendedNotice == nil)
        #expect(decoded.controls == state.controls)
        #expect(decoded.activeDeliveryTimers == state.activeDeliveryTimers)
        #expect(decoded.workingDuration == state.workingDuration)
        #expect(decoded.activeDeliveryCount == state.activeDeliveryCount)
    }

    /// The other direction of the same risk: a card the app parks and then
    /// hands over has to survive the round trip with the control it grew.
    @Test("A parked snapshot round trips with the control this build added")
    func roundTripsTheParkedControl() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)
        let shift = try service.startShift(at: start)
        try service.parkActiveShift(at: at(30))

        let state = shift.activityContentState(for: .none, asOf: at(60), locale: locale)
        let decoded = try JSONDecoder().decode(
            ShiftActivityAttributes.ContentState.self,
            from: try JSONEncoder().encode(state)
        )

        #expect(decoded == state)
        #expect(decoded.controls.first == .resumeDriving)
        #expect(decoded.routeSuspendedNotice == state.routeSuspendedNotice)
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
