import Foundation

/// Scene-local navigation, never persisted with the driver's work.
nonisolated enum Workspace: Hashable {
    case home, work, money
}

nonisolated struct WorkspaceNavigation {
    var selection: Workspace = .home
    private var hasChosenInitialWorkspace = false

    /// Recovery takes priority at cold launch. Later appearances and foreground
    /// reconciliation keep the driver's selection, including during a shift.
    mutating func chooseInitialWorkspace(hasUnfinishedShift: Bool) {
        guard !hasChosenInitialWorkspace else { return }
        selection = hasUnfinishedShift ? .work : .home
        hasChosenInitialWorkspace = true
    }
}

/// An explicit Home action can reveal a section without discarding Work's
/// presentation state. A new identity makes repeated requests meaningful.
nonisolated struct WorkFocusRequest: Equatable {
    enum Destination: Hashable {
        case activeShift, history
    }

    let id = UUID()
    let destination: Destination
}
