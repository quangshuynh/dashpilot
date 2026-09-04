import XCTest

final class DashPilotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app launches into the shift list rather than the persistence failure state.
    @MainActor
    func testLaunchesIntoShiftList() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Local Data Unavailable"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
