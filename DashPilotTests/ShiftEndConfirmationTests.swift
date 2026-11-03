import Foundation
import SwiftData
import Testing
import UIKit
@testable import DashPilot

/// Ending a shift from the Live Activity takes two taps, and the second is
/// checked against the app's own record rather than the card.
///
/// Every check is made through ``IntentLifecycleService``, the path the Lock
/// Screen buttons take, with explicit timestamps so expiry is decided by the
/// dates presented and nothing depends on how long a test runs.
@MainActor
@Suite("Live Activity end confirmation")
struct ShiftEndConfirmationTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private struct Fixture {
        let context: ModelContext
        let confirmations: ShiftEndConfirmationStore
        let recaps: PostShiftRecapRequests
        let activity: Recorder
        let service: IntentLifecycleService
    }

    @MainActor
    final class Recorder: ShiftActivityReconciling {
        private(set) var count = 0
        func reconcile() { count += 1 }
    }

    private func makeFixture() throws -> Fixture {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let confirmations = ShiftEndConfirmationStore(schedulesExpiry: false)
        let recaps = PostShiftRecapRequests()
        let activity = Recorder()
        let service = IntentLifecycleService(
            context: context, activity: activity, confirmations: confirmations, recaps: recaps
        )
        return Fixture(context: context, confirmations: confirmations, recaps: recaps, activity: activity, service: service)
    }

    private func runningShift(_ fixture: Fixture) throws -> Shift {
        try ShiftService(context: fixture.context).startShift(at: start)
    }

    // MARK: The first tap

    @Test("The first End Shift tap never ends the shift")
    func firstTapEndsNothing() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)

        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        #expect(shift.endedAt == nil)
        #expect(shift.lifecycleState == .running)
        #expect(request.shiftID == shift.id)
        #expect(request.expiresAt == at(60 + PendingShiftEnd.window))
        #expect(fixture.recaps.shiftID == nil, "No recap before an end is written")
        #expect(fixture.activity.count == 1, "The card is redrawn with the confirmation")
    }

    @Test("Repeated first taps never end the shift, and each replaces the token")
    func repeatedFirstTapsEndNothing() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)

        let first = try fixture.service.requestEndShiftConfirmation(at: at(60))
        let second = try fixture.service.requestEndShiftConfirmation(at: at(61))

        #expect(shift.endedAt == nil)
        #expect(first.token != second.token)
        #expect(throws: IntentLifecycleError.endConfirmationStale) {
            try fixture.service.confirmEndShift(first.reference, at: at(62))
        }
        #expect(shift.endedAt == nil, "A card drawn for the first request cannot confirm the second")
        #expect(fixture.confirmations.pending == second, "and does not withdraw it either")
    }

    @Test("Unresolved deliveries refuse the first tap, with the end's own sentence")
    func unresolvedDeliveriesBlockTheFirstTap() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        _ = try DeliveryService(context: fixture.context).startDelivery(at: at(10))

        #expect(throws: IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 1))) {
            try fixture.service.requestEndShiftConfirmation(at: at(60))
        }
        #expect(fixture.confirmations.pending == nil, "No confirmation is offered that the end would refuse")
        #expect(shift.endedAt == nil)
    }

    @Test("With no shift running the first tap is refused")
    func firstTapWithNoShift() throws {
        let fixture = try makeFixture()
        #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
            try fixture.service.requestEndShiftConfirmation(at: at(60))
        }
        #expect(fixture.confirmations.pending == nil)
    }

    // MARK: The second tap

    @Test("A valid second tap ends exactly the intended shift and offers its recap")
    func validConfirmationEndsTheIntendedShift() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        let outcome = try fixture.service.confirmEndShift(request.reference, at: at(63))

        #expect(shift.endedAt == at(63))
        #expect(outcome == .shiftEnded(duration: 63))
        #expect(fixture.confirmations.pending == nil, "The confirmation is used up")
        #expect(fixture.recaps.shiftID == shift.id)
    }

    @Test("A paused shift ends on confirmation and closes its pause at the end")
    func confirmationEndsAPausedShift() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        try ShiftService(context: fixture.context).pauseActiveShift(at: at(30))
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        _ = try fixture.service.confirmEndShift(request.reference, at: at(62))

        #expect(shift.endedAt == at(62))
        #expect(shift.openPause == nil)
    }

    @Test("A second tap after the window ends nothing", arguments: [PendingShiftEnd.window, PendingShiftEnd.window + 600])
    func expiredConfirmationEndsNothing(after delay: TimeInterval) throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        #expect(throws: IntentLifecycleError.endConfirmationExpired) {
            try fixture.service.confirmEndShift(request.reference, at: at(60 + delay))
        }
        #expect(shift.endedAt == nil)
        #expect(fixture.confirmations.pending == nil, "An expired confirmation cannot be revived")
        #expect(fixture.recaps.shiftID == nil)
    }

    @Test("A clock moved behind the first tap is not taken as time remaining")
    func clockMovedBackEndsNothing() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        #expect(throws: IntentLifecycleError.endConfirmationExpired) {
            try fixture.service.confirmEndShift(request.reference, at: at(59))
        }
        #expect(shift.endedAt == nil)
    }

    @Test("Keep Shift withdraws the confirmation; a later Confirm End ends nothing")
    func cancellationLeavesTheShiftRunning() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        fixture.service.keepShift(request.reference)

        #expect(fixture.confirmations.pending == nil)
        #expect(throws: IntentLifecycleError.endConfirmationExpired) {
            try fixture.service.confirmEndShift(request.reference, at: at(61))
        }
        #expect(shift.endedAt == nil)
        #expect(shift.lifecycleState == .running)
    }

    @Test("A repeated Confirm End after success never ends anything else")
    func repeatedConfirmationAfterSuccess() throws {
        let fixture = try makeFixture()
        let first = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))
        _ = try fixture.service.confirmEndShift(request.reference, at: at(61))

        // A new shift starts before the delayed duplicate arrives.
        let second = try ShiftService(context: fixture.context).startShift(at: at(120))
        #expect(throws: IntentLifecycleError.endConfirmationStale) {
            try fixture.service.confirmEndShift(request.reference, at: at(121))
        }
        #expect(second.endedAt == nil, "The duplicate names the first shift, so the second keeps running")
        #expect(first.endedAt == at(61))
    }

    @Test("A confirmation drawn for an earlier shift cannot end the one running now")
    func staleShiftIdentityEndsNothing() throws {
        let fixture = try makeFixture()
        _ = try runningShift(fixture)
        let stale = try fixture.service.requestEndShiftConfirmation(at: at(60))
        fixture.service.keepShift(stale.reference)
        try ShiftService(context: fixture.context).endActiveShift(at: at(70))

        let current = try ShiftService(context: fixture.context).startShift(at: at(80))
        let fresh = try fixture.service.requestEndShiftConfirmation(at: at(81))
        // The card for the old shift presents the new token by mistake: the
        // shift it names is still checked first.
        let mismatched = ShiftActivityEndConfirmation(shiftID: stale.shiftID, token: fresh.token)

        #expect(throws: IntentLifecycleError.endConfirmationStale) {
            try fixture.service.confirmEndShift(mismatched, at: at(82))
        }
        #expect(current.endedAt == nil)
        #expect(fixture.confirmations.pending == fresh, "The current shift's confirmation is untouched")
    }

    @Test("Concurrent Confirm End presses end the shift once")
    func concurrentConfirmationsEndOnce() async throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))
        let service = fixture.service
        let reference = request.reference
        let date = at(62)

        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor in
                    (try? service.confirmEndShift(reference, at: date)) != nil
                }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }

        #expect(results.filter { $0 }.count == 1, "Exactly one press ended the shift: \(results)")
        #expect(shift.endedAt == date)
        let ended = try fixture.context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.endedAt != nil }))
        #expect(ended.count == 1)
    }

    @Test("A delivery started between the taps still blocks the end")
    func deliveryStartedBetweenTapsStillBlocks() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))
        _ = try DeliveryService(context: fixture.context).startDelivery(at: at(61))

        #expect(throws: IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 1))) {
            try fixture.service.confirmEndShift(request.reference, at: at(62))
        }
        #expect(shift.endedAt == nil)
        #expect(fixture.recaps.shiftID == nil)
    }

    // MARK: What the card shows

    @Test("While a confirmation is pending the card asks, Keep Shift first")
    func cardOffersTheConfirmation() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))

        let state = shift.activityContentState(for: .none, asOf: at(61), pendingEnd: request)
        #expect(state.controls == [.keepShift(request.reference), .confirmEnd(request.reference)])
        #expect(ShiftActivityControl.emphasised(in: state.controls) == .keepShift(request.reference))

        let expired = shift.activityContentState(for: .none, asOf: at(60 + PendingShiftEnd.window), pendingEnd: request)
        #expect(expired.controls == [.startDelivery, .park, .pause, .end], "An expired confirmation is not drawn")
    }

    @Test("A confirmation is never drawn for another shift or where End is not offered")
    func cardNeverOffersAnUnendableConfirmation() throws {
        let fixture = try makeFixture()
        let shift = try runningShift(fixture)
        let other = PendingShiftEnd(shiftID: UUID(), token: UUID(), requestedAt: at(60))
        #expect(shift.activityContentState(for: .none, asOf: at(61), pendingEnd: other).controls.contains(.end))

        let request = try fixture.service.requestEndShiftConfirmation(at: at(60))
        _ = try DeliveryService(context: fixture.context).startDelivery(at: at(61))
        let carrying = shift.activityContentState(for: .none, asOf: at(62), pendingEnd: request)
        #expect(!carrying.controls.contains(.confirmEnd(request.reference)))
        #expect(!carrying.controls.contains(.keepShift(request.reference)))
    }

    @Test("The confirmation controls say what they do, without relying on colour")
    func confirmationControlsAreLabelled() {
        let reference = ShiftActivityEndConfirmation(shiftID: UUID(), token: UUID())
        #expect(ShiftActivityControl.confirmEnd(reference).title == "Confirm End")
        #expect(ShiftActivityControl.keepShift(reference).title == "Keep Shift")
        #expect(ShiftActivityControl.confirmEnd(reference).spokenLabel.contains("shift"))
        #expect(ShiftActivityControl.keepShift(reference).spokenLabel.contains("shift"))
        #expect(ShiftActivityControl.confirmEnd(reference).symbolName != ShiftActivityControl.end.symbolName)
        for control in [ShiftActivityControl.confirmEnd(reference), .keepShift(reference)] {
            #expect(UIImage(systemName: control.symbolName) != nil, "\(control.symbolName) is a system symbol")
        }
        #expect(!ShiftActivityControl.confirmEnd(reference).isProminent)
    }

    @Test("A Live Activity confirmation survives a content-state round trip")
    func confirmationControlsAreCodable() throws {
        let reference = ShiftActivityEndConfirmation(shiftID: UUID(), token: UUID())
        let controls: [ShiftActivityControl] = [.keepShift(reference), .confirmEnd(reference)]
        let decoded = try JSONDecoder().decode([ShiftActivityControl].self, from: JSONEncoder().encode(controls))
        #expect(decoded == controls)
    }
}
