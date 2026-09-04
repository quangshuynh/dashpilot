import XCTest

final class DashPilotUITests: XCTestCase {
    /// Must match `LaunchArgument.inMemoryStore`; a UI test target cannot link the app target.
    private static let inMemoryStoreArgument = "-dashpilot-in-memory-store"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches against a throwaway store so the journey starts from a known
    /// empty state and never writes into a real driver's shift history.
    @MainActor
    private func launchWithEmptyStore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        app.launch()
        return app
    }

    /// The app launches into the shift screen rather than the persistence failure state.
    @MainActor
    func testLaunchesIntoShiftScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Local Data Unavailable"].exists)
    }

    /// The one journey the app currently has: start a shift, see it running, end it,
    /// and find it in history.
    @MainActor
    func testStartsAndEndsAShift() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))

        startButton.tap()

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["elapsedTime"].exists)
        XCTAssertFalse(startButton.exists, "Only one shift may be running at a time")

        endButton.tap()

        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertFalse(endButton.exists)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "completedShiftRow")
                .firstMatch.waitForExistence(timeout: 5),
            "The finished shift should appear in history"
        )
    }

    /// The authorization panel is on screen from launch, in whatever state the
    /// device is in.
    ///
    /// Only its presence is asserted: which state it shows depends on the
    /// simulator's permission database, and this test must not depend on that.
    /// The mapping from each authorization state to what is displayed is
    /// covered by `LocationAuthorizationServiceTests` instead, and no test
    /// drives the system permission alert — automating it would be brittle and
    /// would change the device state other tests run against.
    @MainActor
    func testShowsLocationAuthorizationState() throws {
        let app = launchWithEmptyStore()

        let status = app.descendants(matching: .any)["locationAuthorizationStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
