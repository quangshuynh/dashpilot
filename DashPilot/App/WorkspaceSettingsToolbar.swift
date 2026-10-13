import SwiftUI

/// One Settings route, shared by the three workspace roots.
struct WorkspaceSettingsToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink(value: WorkspaceDestination.settings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Your vehicles, work preferences, and app welcome.")
            .accessibilityIdentifier("settingsLink")
        }
    }
}

/// Root destinations use values so Home can reveal Work's active controls or
/// History even when that workspace last showed a pushed destination.
enum WorkspaceDestination: Hashable {
    case settings, expenses, periodSummary, olderWeeks
}

private struct WorkspaceDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar { WorkspaceSettingsToolbar() }
            .navigationDestination(for: WorkspaceDestination.self) { destination in
                switch destination {
                case .settings: SettingsView()
                case .expenses: ExpenseListView()
                case .periodSummary: PeriodSummaryView()
                case .olderWeeks: OlderHistoryWeeksView()
                }
            }
    }
}

extension View {
    func workspaceDestinations() -> some View {
        modifier(WorkspaceDestinations())
    }
}
