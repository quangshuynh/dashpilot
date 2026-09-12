import ActivityKit
import Foundation

/// The Live Activity that represents **one shift**.
///
/// ## One activity, and it is the shift
///
/// Not one per delivery. A driver working three stacked orders is working one
/// shift, and three Lock Screen cards competing for the same glance would be
/// three chances to act on the wrong one. The shift is also the only thing every
/// figure here is scoped to: working time, recorded mileage and the delivery
/// counts are all properties of a shift, and none of them is defined for a
/// delivery on its own.
///
/// ## It is presentation, and it is never the truth
///
/// Everything below is a **snapshot of what the store said at `asOf`**. SwiftData
/// remains the only authority on whether a shift is running, paused or ended;
/// this type is what the app hands the system to draw, and nothing ever reads it
/// back to decide what happened. A snapshot that disagrees with the store is a
/// stale snapshot, and reconciling it against the store is the app's job. See
/// `ShiftLiveActivityService`.
///
/// ## Shared source, two modules
///
/// This file is compiled into the app **and** into the widget extension, which
/// is how ActivityKit matches what one requests to what the other draws. Keep it
/// free of SwiftData, of the app's services and of anything that would drag the
/// model layer into the extension: the extension is a renderer, and a second
/// copy of a lifecycle rule compiled into it is exactly the drift this project
/// designs against.
nonisolated struct ShiftActivityAttributes: ActivityAttributes, Sendable {
    /// Which shift this activity is about.
    ///
    /// The only static fact carried, and it is carried for **reconciliation**
    /// rather than for display: on relaunch the app has to be able to tell an
    /// activity describing the shift that is still running from one left behind
    /// by a shift that has ended, and an opaque local identifier is the whole of
    /// what that needs. It is never drawn, and it names nothing outside this
    /// device.
    let shiftID: UUID

    init(shiftID: UUID) {
        self.shiftID = shiftID
    }

    /// What the Lock Screen and the Dynamic Island say about the shift right now.
    ///
    /// ## What is here, and what is deliberately not
    ///
    /// A Lock Screen is read at a glance, often by someone who is about to drive.
    /// It carries the working time, what the route has recorded, whether the
    /// shift is paused, how the deliveries stand, and the one or two controls
    /// that apply.
    ///
    /// It carries **no money in any form**: no recorded gross, no hourly figure,
    /// no per-mile figure, no total and no projection. It carries **no
    /// recommendation, no goal, no place name, no address and no coordinate**
    /// either. Half of those are
    /// facts DashPilot does not have; the rest are a driver's earnings and
    /// whereabouts, printed on a surface anyone standing beside them can read.
    struct ContentState: Codable, Hashable, Sendable {
        /// Whether the driver has the shift paused.
        ///
        /// The distinction the surface exists to make glanceable: a paused shift
        /// is accumulating no working time and recording no route, and a driver
        /// who cannot tell the two states apart at a glance is the driver who
        /// finds out at the end of the day.
        let isPaused: Bool

        /// Working time as of ``asOf``, in seconds.
        ///
        /// **Working**, not elapsed: the same definition the app's panel leads
        /// with, the same one every hourly figure divides by, and the same one a
        /// spoken confirmation reports. A driver watching one number on the Lock
        /// Screen and reading a different one in the app would have no way to
        /// tell which was wrong.
        let workingDuration: TimeInterval

        /// The instant every figure here was read at.
        ///
        /// It is what makes ``workingTimerAnchor`` exact, and it is why a running
        /// shift needs no further updates to keep its clock honest.
        let asOf: Date

        /// What the route has recorded, in the app's own words:
        /// `"4.5 mi recorded"`, or the sentence that says why there is no figure.
        ///
        /// Carried as the finished sentence rather than as a number, and that is
        /// deliberate. `RouteQuality` is the one place in this project that
        /// decides how a recorded distance may be described, and a widget
        /// extension formatting metres itself would be a second answer to the
        /// one question this app is most careful about. The extension renders
        /// what the app derived.
        let mileageStatement: String

        /// `"partial route"` when the route so far is known to cover less than
        /// the shift, `nil` when no gap was detected.
        ///
        /// Travels beside the figure everywhere the figure appears. A recorded
        /// mileage shown without it is the one claim this app must not make, and
        /// a Lock Screen is the easiest place in the product to make it by
        /// accident.
        let partialRouteMarker: String?

        /// How many deliveries the driver has open right now.
        let activeDeliveryCount: Int

        /// How many this shift has completed. Cancelled deliveries are not
        /// counted here and are not shown on this surface at all.
        let completedDeliveryCount: Int

        /// What the one delivery in progress is doing (`"Waiting at the
        /// pickup"`), or `nil`.
        ///
        /// `nil` whenever the answer would be ambiguous: with two orders in the
        /// car there is no "the delivery", and a status line naming one of them
        /// would be the surface picking a delivery on the driver's behalf. It is
        /// also `nil` with none in progress, because there is nothing to say.
        let deliveryStatus: String?

        /// The controls this shift may offer, in the order they are shown.
        ///
        /// **Decided by the app, from the shift's own stored facts**, never by
        /// the extension. The extension has no access to the rules that say a
        /// shift cannot pause while a delivery is open, and inventing a local
        /// copy of them is what would eventually let the two disagree. A control
        /// that should not be here is still refused when it is pressed, by the
        /// same service the app's own buttons call, so this list is a courtesy
        /// and not a permission.
        let controls: [ShiftActivityControl]

        init(
            isPaused: Bool,
            workingDuration: TimeInterval,
            asOf: Date,
            mileageStatement: String,
            partialRouteMarker: String?,
            activeDeliveryCount: Int,
            completedDeliveryCount: Int,
            deliveryStatus: String?,
            controls: [ShiftActivityControl]
        ) {
            self.isPaused = isPaused
            self.workingDuration = workingDuration
            self.asOf = asOf
            self.mileageStatement = mileageStatement
            self.partialRouteMarker = partialRouteMarker
            self.activeDeliveryCount = activeDeliveryCount
            self.completedDeliveryCount = completedDeliveryCount
            self.deliveryStatus = deliveryStatus
            self.controls = controls
        }
    }
}
