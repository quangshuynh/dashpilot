import SwiftUI
import WidgetKit

/// Everything DashPilot draws outside its own window.
///
/// One entry, and it is the shift's Live Activity. There is no Home Screen
/// widget and no Lock Screen widget: a widget is a periodic summary of stored
/// history, and every summary this app has is a reading of routes and periods
/// that the app measures on demand. Adding one would mean deciding what a
/// driver's earnings look like on a shared screen, which is a decision this
/// project has not made.
@main
struct DashPilotWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftLiveActivity()
    }
}
