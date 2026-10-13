import Testing
@testable import DashPilot

struct WorkspaceNavigationTests {
    @Test("Cold launch recovers unfinished work and otherwise welcomes the driver", arguments: [false, true])
    func coldLaunch(hasUnfinishedShift: Bool) {
        var navigation = WorkspaceNavigation()
        navigation.chooseInitialWorkspace(hasUnfinishedShift: hasUnfinishedShift)
        #expect(navigation.selection == (hasUnfinishedShift ? .work : .home))
    }

    @Test("Reappearance preserves selection even when authoritative shift state changes",
          arguments: [Workspace.home, .work, .money], [false, true])
    func reappearance(selection: Workspace, hasUnfinishedShift: Bool) {
        var navigation = WorkspaceNavigation()
        navigation.chooseInitialWorkspace(hasUnfinishedShift: !hasUnfinishedShift)
        navigation.selection = selection
        navigation.chooseInitialWorkspace(hasUnfinishedShift: hasUnfinishedShift)
        #expect(navigation.selection == selection)
    }
}
