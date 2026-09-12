import ActivityKit
import Foundation
import OSLog

/// One Live Activity this process can address.
///
/// The activity's own identifier, plus the shift it claims to describe. Both are
/// needed for reconciliation: the identifier says which activity to update or
/// end, and the shift identifier says whether it is still describing the right
/// one. Nothing else about an activity is carried, and nothing here is stored.
nonisolated struct ShiftActivityHandle: Equatable, Sendable {
    let id: String
    let shiftID: UUID
}

/// The seam between the app's reconciliation and ActivityKit itself.
///
/// ## Why it exists
///
/// Two reasons, and the second is the important one.
///
/// ActivityKit cannot run in a unit test: there is no Lock Screen, no
/// authorization to grant, and `Activity.request` refuses outside a real app
/// process. Everything this interval actually has to get right is
/// reconciliation logic: that a shift paused and resumed produces one activity
/// that says the right thing, that a relaunch adopts the activity it already has
/// rather than adding a second, that a shift ending ends it, and that an
/// activity left behind by a shift that is gone is cleaned up. All of it is
/// testable against a recorder that answers the way ActivityKit answers.
///
/// The second reason: a **throwaway store must never reach a real system
/// surface**. The UI journeys run over synthetic in-memory fixtures, and a
/// Lock Screen card outlives the process that requested it. The fixture launches
/// present through a recorder for that reason, not merely for speed.
///
/// ## Why nothing here is `async`
///
/// ActivityKit's own `update` and `end` are, and the implementation awaits them.
/// But the caller is a reconciliation pass that runs to completion against the
/// store, and making it suspend would open exactly the window this project keeps
/// closing elsewhere: a second writer interleaving between the read and what it
/// implies. So the work is handed over and not waited on, and the next reconcile
/// is what corrects a hand-over that did not land.
@MainActor
protocol ShiftActivityPresenting: AnyObject {
    /// Whether Live Activities can be shown at all right now.
    ///
    /// `false` when the driver has turned them off for DashPilot or for the
    /// device. It is read on every pass rather than once, because it is a
    /// Settings switch and Settings is not somewhere the app is watching.
    var isAvailable: Bool { get }

    /// Every shift activity this process can currently address.
    ///
    /// **The one thing the app reads back from ActivityKit**, and it reads
    /// identity rather than content: which activities exist and which shift each
    /// says it is about. What any of them currently displays is never consulted,
    /// because the store is what a shift's state is read from.
    func activities() -> [ShiftActivityHandle]

    /// Requests a new activity, or returns `nil` if the system refused one.
    func start(
        shiftID: UUID,
        content: ShiftActivityAttributes.ContentState
    ) -> ShiftActivityHandle?

    /// Hands over a newer snapshot.
    func update(_ handle: ShiftActivityHandle, content: ShiftActivityAttributes.ContentState)

    /// Removes the activity immediately.
    ///
    /// Immediately, rather than after the system's default lingering period: an
    /// activity outliving the shift it describes is a card on a Lock Screen
    /// claiming a shift is being worked when it has finished, which is the one
    /// failure this surface must not have.
    func end(_ handle: ShiftActivityHandle)
}

/// The shipping presenter, backed by ActivityKit.
///
/// It holds the `Activity` objects the app has seen, keyed by identifier, so
/// that a handle can be turned back into something to update. That map is a
/// cache of what ActivityKit already knows and never a record of what is true:
/// it is rebuilt from `Activity.activities` on every read, so a relaunch, a
/// dismissal by the driver and an activity ended by the system all resolve the
/// same way.
@MainActor
final class LiveShiftActivityPresenter: ShiftActivityPresenting {
    private var known: [String: Activity<ShiftActivityAttributes>] = [:]

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func activities() -> [ShiftActivityHandle] {
        let live = Activity<ShiftActivityAttributes>.activities
        known = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        return live.map { ShiftActivityHandle(id: $0.id, shiftID: $0.attributes.shiftID) }
    }

    func start(
        shiftID: UUID,
        content: ShiftActivityAttributes.ContentState
    ) -> ShiftActivityHandle? {
        do {
            let activity = try Activity.request(
                attributes: ShiftActivityAttributes(shiftID: shiftID),
                // No stale date. The surface's own clock stays correct with no
                // updates at all, and the route figure is explicitly a floor
                // that a driver reads as "at least this much"; marking it stale
                // would dim a card whose every claim is still true.
                content: ActivityContent(state: content, staleDate: nil)
            )
            known[activity.id] = activity
            // Structural. Not how long the shift has run, not what it recorded.
            AppLog.activity.info("Live Activity started for the shift in progress")
            return ShiftActivityHandle(id: activity.id, shiftID: shiftID)
        } catch {
            // A refusal is not a failure of the shift. The shift is recorded
            // either way, and the next reconcile tries again.
            AppLog.activity.error("The system refused a Live Activity: \(error)")
            return nil
        }
    }

    func update(_ handle: ShiftActivityHandle, content: ShiftActivityAttributes.ContentState) {
        guard let activity = resolve(handle) else { return }
        Task { @MainActor in
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    func end(_ handle: ShiftActivityHandle) {
        guard let activity = resolve(handle) else { return }
        known[handle.id] = nil
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        AppLog.activity.info("Live Activity ended")
    }

    /// The activity behind a handle, re-reading ActivityKit once if the app has
    /// not seen it before. A handle the system no longer knows resolves to
    /// nothing, and the caller's next reconcile starts a replacement.
    private func resolve(_ handle: ShiftActivityHandle) -> Activity<ShiftActivityAttributes>? {
        if let activity = known[handle.id] { return activity }
        _ = activities()
        return known[handle.id]
    }
}

/// A presenter that shows nothing.
///
/// Used by the debug launches that run over a throwaway store: their data is
/// synthetic, and a Live Activity is a real system surface that outlives the
/// process which requested it. Nothing about it is a stub of the reconciliation
/// runs exactly as it does in a shipping build, over the same rules, and simply
/// has nowhere to draw.
@MainActor
final class SuppressedShiftActivityPresenter: ShiftActivityPresenting {
    var isAvailable: Bool { false }
    func activities() -> [ShiftActivityHandle] { [] }
    func start(shiftID: UUID, content: ShiftActivityAttributes.ContentState) -> ShiftActivityHandle? { nil }
    func update(_ handle: ShiftActivityHandle, content: ShiftActivityAttributes.ContentState) {}
    func end(_ handle: ShiftActivityHandle) {}
}
