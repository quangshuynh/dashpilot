import Foundation
import OSLog
import SwiftData

/// Something that can be asked to bring the shift's Live Activity back into line
/// with the store.
///
/// A protocol so that the intent layer can hold one without holding ActivityKit,
/// and so a test can watch the reconciles an intent triggers.
@MainActor
protocol ShiftActivityReconciling: AnyObject {
    func reconcile()
}

/// Keeps the shift's Live Activity describing the shift the store actually holds.
///
/// ## One function, called from everywhere
///
/// There is exactly one entry point, ``reconcile()``, and it derives what should
/// be on screen from the store rather than from what happened last. That is the
/// same shape ``LocationTrackingService/synchronize()`` has, and for the same
/// reason: a missed call costs a delay and never a wrong state, and a caller
/// never has to know which transition it is in the middle of. Starting a shift,
/// pausing one, advancing a delivery, flushing a batch of route, returning to
/// the foreground and relaunching the app all call the same function.
///
/// ## Nothing here is authoritative
///
/// SwiftData is the only place a shift's state lives, and this type writes
/// nothing to it. It reads the active shift, measures the route it has not
/// measured yet, derives a snapshot, and hands that snapshot to a presenter.
/// **ActivityKit is never asked what is true**: the only thing read back from it
/// is which activities exist and which shift each claims to be about, which is
/// what makes cleaning up a stale one possible. A snapshot is a picture of the
/// store at an instant and is never consulted afterwards.
///
/// ## What it costs
///
/// The route is measured **incrementally**, by the same ``ActiveRouteMeasurement``
/// the running shift's panel uses: a count, and a fetch of the positions after
/// the last one already measured. Nothing here ever walks a whole route, which
/// on an eight-hour shift is a quarter of a second on the main actor.
///
/// What is handed to ActivityKit is then throttled by
/// ``ShiftActivityUpdatePolicy``, so a reconcile that finds the shift unchanged
/// costs two small queries and hands over nothing at all.
///
/// `@Observable` for one reason only: it is put in the SwiftUI environment the
/// way ``LocationTrackingService`` is, so any screen that writes to the store
/// can ask it to catch up. **Nothing on it is readable state**, and no view
/// should ever draw from it. What is on the Lock Screen is derived from the
/// store, and a screen reading it back would be reading a picture of the store
/// instead of the store.
@MainActor
@Observable
final class ShiftLiveActivityService: ShiftActivityReconciling {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let presenter: any ShiftActivityPresenting
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let locale: () -> Locale

    /// The activity this app is currently keeping up to date, or `nil` when
    /// there is none.
    ///
    /// A cache of what the presenter reported, re-derived on every pass. It is
    /// never trusted over ``ShiftActivityPresenting/activities()``: an activity
    /// the driver dismissed, or one the system ended, is gone whatever this
    /// holds.
    @ObservationIgnored private var handle: ShiftActivityHandle?

    /// The last snapshot handed over, and when.
    ///
    /// Both are what ``ShiftActivityUpdatePolicy`` decides against. They are
    /// deliberately *not* read back from ActivityKit: what matters is what this
    /// app sent, and asking the system what it is displaying would make a
    /// presentation surface an input to the app's own behaviour.
    @ObservationIgnored private var lastPushed: ShiftActivityAttributes.ContentState?
    @ObservationIgnored private var lastPushedAt: Date?

    /// The open measurement of the running shift's route.
    @ObservationIgnored private var routeMeasurement: ActiveRouteMeasurement?

    init(
        context: ModelContext,
        presenter: any ShiftActivityPresenting,
        now: @escaping () -> Date = { .now },
        locale: @escaping () -> Locale = { .autoupdatingCurrent }
    ) {
        self.context = context
        self.presenter = presenter
        self.now = now
        self.locale = locale
    }

    /// Brings the Live Activity into line with the store.
    ///
    /// Safe to call at any time and as often as the app likes.
    func reconcile() {
        let activeShift: Shift?
        do {
            activeShift = try ShiftService(context: context).activeShift()
        } catch {
            // A store that could not be read is not a shift that has ended. The
            // activity is left exactly as it is: removing it would tell the
            // driver their shift had finished because a query failed.
            AppLog.activity.error("Could not read the active shift; the Live Activity was left alone: \(error)")
            return
        }

        guard let shift = activeShift, shift.lifecycleState.isUnfinished else {
            endEverything()
            return
        }

        guard presenter.isAvailable else {
            // Live Activities are off for DashPilot or for the device. Nothing
            // to end, because the system has already removed whatever there
            // was, and nothing to start.
            forgetActivity()
            return
        }

        adoptOrCleanUp(for: shift)
        present(shift)
    }

    // MARK: Reconciling which activity is ours

    /// Adopts the activity describing this shift, and ends every other one.
    ///
    /// **This is the relaunch path**, and it is the ordinary path too. A new
    /// process holds no handle, so the activity a shift already has is found by
    /// its shift identifier and adopted rather than replaced; without that, every
    /// relaunch during a shift would leave the previous card behind and add a
    /// second.
    ///
    /// Anything describing a different shift is ended. That is what clears a
    /// card left behind by a termination between a shift ending and the activity
    /// being removed, which is the one way this app can leave a Lock Screen
    /// claiming work that had stopped.
    private func adoptOrCleanUp(for shift: Shift) {
        let visible = presenter.activities()

        for stale in visible where stale.shiftID != shift.id {
            AppLog.activity.notice("Ending a Live Activity left behind by a shift that is no longer running")
            presenter.end(stale)
        }

        let ours = visible.first { $0.shiftID == shift.id }
        guard handle?.id != ours?.id else { return }

        // Either the app has just adopted an activity it did not request, or the
        // one it was keeping up to date is gone. Both mean the snapshot it last
        // sent says nothing about what is on screen now, so the throttle starts
        // again and the next derivation is pushed.
        handle = ours
        lastPushed = nil
        lastPushedAt = nil
        if ours != nil {
            AppLog.activity.info("Adopted the Live Activity already showing the shift in progress")
        }
    }

    /// Ends every activity this process can see and forgets the shift's route
    /// measurement.
    ///
    /// Called when the store holds no unfinished shift, which covers a shift that
    /// ended, one deleted after it ended, and a first launch that finds a card
    /// left over from a previous install of the same app.
    private func endEverything() {
        for activity in presenter.activities() {
            presenter.end(activity)
        }
        forgetActivity()
    }

    private func forgetActivity() {
        handle = nil
        lastPushed = nil
        lastPushedAt = nil
        routeMeasurement = nil
    }

    // MARK: Deriving and handing over

    /// Derives the snapshot for `shift` and hands it over if the policy says so.
    private func present(_ shift: Shift) {
        // No reading of the route, no snapshot. A shift whose route could not be
        // read has not recorded no miles, and starting a card that says so
        // because a query failed is the invention this app refuses elsewhere.
        // The next reconcile tries again.
        guard let measurement = measureRoute(of: shift) else { return }

        let reference = now()
        let content = shift.activityContentState(
            for: measurement.recordedDistance,
            asOf: reference,
            locale: locale()
        )

        guard let handle else {
            guard let started = presenter.start(shiftID: shift.id, content: content) else { return }
            self.handle = started
            lastPushed = content
            lastPushedAt = reference
            return
        }

        let change = ShiftActivityUpdatePolicy.change(from: lastPushed, to: content)
        guard ShiftActivityUpdatePolicy.shouldPush(change, lastPushedAt: lastPushedAt, now: reference) else {
            return
        }

        presenter.update(handle, content: content)
        lastPushed = content
        lastPushedAt = reference
    }

    /// Extends the shift's route measurement with whatever the store has gained,
    /// or `nil` when the store could not be read and there is nothing to fall
    /// back to.
    ///
    /// A failed read leaves the previous measurement standing, for the reason
    /// the running shift's panel leaves its figure standing: the figure was true
    /// when it was measured, and one failed query does not make it false. A
    /// measurement of a *different* shift is not a fallback at all, so it is
    /// discarded rather than attributed to this one.
    private func measureRoute(of shift: Shift) -> ActiveRouteMeasurement? {
        do {
            let measurement = try ActiveShiftRouteService(context: context)
                .measurement(extending: routeMeasurement, of: shift)
            routeMeasurement = measurement
            return measurement
        } catch {
            AppLog.activity.error("Could not read the running shift's route for its Live Activity: \(error)")
            return routeMeasurement?.shiftID == shift.id ? routeMeasurement : nil
        }
    }
}
