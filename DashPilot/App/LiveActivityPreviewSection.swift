#if DEBUG
import SwiftData
import SwiftUI

/// The running shift's Live Activity card, drawn inside the app for a UI
/// journey. Debug builds only, and only under
/// ``LaunchArgument/liveActivityPreview``.
///
/// ## What it is, and what it is not
///
/// It is the extension's own ``ShiftActivityLockScreenView``, fed by the
/// snapshot the app would hand ActivityKit, clipped to the **160 points** the
/// system gives a Lock Screen card. A control a journey can reach here is a
/// control inside that height, in the order the app chose; one that is not
/// hittable here is one the Lock Screen would have cut off.
///
/// It is not the system's rendering: the Lock Screen draws its own background
/// and margins around the card, and nothing here observes that.
struct LiveActivityPreviewSection: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext

    /// Read so that this redraws when anything the card shows changes: a
    /// delivery's step, a parked stretch, the pickup workflow setting.
    @Query private var deliveries: [Delivery]
    @Query private var suspensions: [RouteSuspension]
    @Query private var settings: [DriverSettings]

    var body: some View {
        let state = content
        Section {
            ShiftActivityLockScreenView(state: state)
                .frame(height: 160, alignment: .top)
                .clipped()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("liveActivityPreview")
        } header: {
            Text("Live Activity preview")
        }
    }

    private var content: ShiftActivityAttributes.ContentState {
        // Touched so the queries above are dependencies of this body.
        _ = (deliveries.map(\.state), suspensions.map(\.isOpen), settings.first?.pickupWorkflowPreferences)
        let distance = (try? ActiveShiftRouteService(context: modelContext).measurement(extending: nil, of: shift))?
            .recordedDistance ?? .none
        return ShiftLiveActivityService.content(
            for: shift,
            recordedDistance: distance,
            asOf: .now,
            locale: .autoupdatingCurrent,
            context: modelContext
        )
    }
}
#endif
