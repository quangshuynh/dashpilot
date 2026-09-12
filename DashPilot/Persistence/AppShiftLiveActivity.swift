import Foundation
import OSLog
import SwiftData

/// The one Live Activity coordinator this process builds.
///
/// It sits beside ``AppModelContainer`` and exists for the same reason: an App
/// Intent can run with no interface on screen, and iOS may launch the process
/// solely to perform one. A shift paused from the Lock Screen has to update the
/// same activity the app's own screen updates, and two coordinators over one
/// activity would race each other into two cards.
///
/// Built once, lazily, on first use, over the process's own container. `nil`
/// when the store could not be opened: there is no shift to describe, and that
/// failure is already the whole screen.
///
/// ## The throwaway stores present nothing
///
/// A Live Activity is a real system surface that outlives the process which
/// requested it, and the debug launch fixtures run over synthetic in-memory data
/// that must never reach one. Those launches get
/// ``SuppressedShiftActivityPresenter``, which is not a stub of the
/// reconciliation: the coordinator runs exactly as it does in a shipping build,
/// over the same rules, and simply has nowhere to draw.
@MainActor
enum AppShiftLiveActivity {
    /// The process's coordinator, or `nil` if the store could not be opened.
    static let shared: ShiftLiveActivityService? = make()

    private static func make() -> ShiftLiveActivityService? {
        guard let container = try? AppModelContainer.shared.get() else {
            AppLog.activity.error("The Live Activity coordinator could not open the local store")
            return nil
        }
        return ShiftLiveActivityService(
            context: container.mainContext,
            presenter: makePresenter()
        )
    }

    private static func makePresenter() -> any ShiftActivityPresenting {
        #if DEBUG
        if LaunchArgument.isUsingThrowawayStore() {
            return SuppressedShiftActivityPresenter()
        }
        #endif
        return LiveShiftActivityPresenter()
    }
}
