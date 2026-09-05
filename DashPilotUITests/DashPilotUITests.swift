import XCTest

final class DashPilotUITests: XCTestCase {
    /// Must match `LaunchArgument.inMemoryStore`; a UI test target cannot link the app target.
    private static let inMemoryStoreArgument = "-dashpilot-in-memory-store"

    /// Must match `LaunchArgument.seededHistory`, for the same reason.
    private static let seededHistoryArgument = "-dashpilot-seeded-history"

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

    /// Launches against a throwaway store holding the synthetic history fixture.
    ///
    /// A UI test cannot make the simulator record a route, so a measured,
    /// partial route — and the per-recorded-mile rate over it — can only be
    /// reached from seeded data.
    @MainActor
    private func launchWithSeededHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededHistoryArgument)
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
        // A driver has to be able to see whether their route is being recorded.
        // Only its presence is asserted: which state it shows depends on the
        // simulator's location permission, and every mapping from a capture
        // state to what is displayed is covered by the service tests instead.
        XCTAssertTrue(app.descendants(matching: .any)["routeCaptureStatus"].exists)
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

    /// Records earnings on a finished shift, then changes the amount.
    ///
    /// The whole point of the flow is that it happens *after* driving, so the
    /// journey ends a shift first and asserts that no earnings control existed
    /// while it was running.
    @MainActor
    func testAddsAndEditsEarningsOnACompletedShift() throws {
        let app = launchWithEmptyStore()
        let row = completeAShift(in: app)

        let addButton = app.buttons["editShiftEarningsButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertEqual(addButton.label, "Add Earnings", "A shift with no amount offers to add one")

        addButton.tap()
        type("86.25", into: app)
        app.buttons["saveEarningsButton"].tap()

        XCTAssertTrue(
            waitForRowLabel(row, toContain: "86.25"),
            "The recorded amount should appear on the shift: \(row.label)"
        )
        XCTAssertEqual(app.buttons["editShiftEarningsButton"].label, "Edit Earnings")

        // Editing replaces the amount rather than adding to it.
        app.buttons["editShiftEarningsButton"].tap()
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "86.25", "The editor opens on the stored amount")
        clear(field, in: app)
        type("104.10", into: app)
        app.buttons["saveEarningsButton"].tap()

        XCTAssertTrue(
            waitForRowLabel(row, toContain: "104.10"),
            "The edited amount should replace the previous one: \(row.label)"
        )
        XCTAssertFalse(row.label.contains("86.25"))
    }

    /// An amount that cannot be read is refused, and refusing it changes nothing.
    @MainActor
    func testInvalidEarningsAreNotSaved() throws {
        let app = launchWithEmptyStore()
        _ = completeAShift(in: app)

        app.buttons["editShiftEarningsButton"].tap()
        type("1.2.3", into: app)
        app.buttons["saveEarningsButton"].tap()

        let message = app.descendants(matching: .any)["earningsValidationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The driver should be told why it was refused")
        XCTAssertTrue(
            app.textFields["earningsAmountField"].exists,
            "The editor stays open with what was typed rather than discarding it"
        )

        app.buttons["cancelEarningsButton"].tap()

        XCTAssertTrue(app.buttons["editShiftEarningsButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["editShiftEarningsButton"].label,
            "Add Earnings",
            "A refused amount leaves the shift with no earnings recorded"
        )
    }

    /// A completed shift with earnings and a measured route shows both rates.
    ///
    /// The row is one combined accessibility element, so the assertions read its
    /// label — which is also what a VoiceOver user hears. The hourly figure is
    /// asserted exactly because it comes from the fixture's timestamps
    /// ($86.25 over three hours); the per-mile figure is asserted by its wording
    /// only, because the distance comes from measuring synthetic coordinates and
    /// pinning its cents would test the haversine, not the row.
    @MainActor
    func testShowsDerivedRatesOnACompletedShift() throws {
        let app = launchWithSeededHistory()

        let row = app.descendants(matching: .any).matching(identifier: "completedShiftRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        XCTAssertTrue(
            row.label.contains("$28.75 gross earnings per shift hour"),
            "The hourly rate divides by the whole elapsed shift: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("gross earnings per recorded mile"),
            "The per-mile rate must say which miles it divides by: \(row.label)"
        )
        XCTAssertFalse(
            row.label.contains("earnings per mile"),
            "A bare per-mile claim would present recorded mileage as the mileage driven: \(row.label)"
        )
    }

    /// A route with known gaps stays labelled as partial next to the rate that
    /// divides by it.
    @MainActor
    func testPartialRouteRemainsLabelled() throws {
        let app = launchWithSeededHistory()

        let row = app.descendants(matching: .any).matching(identifier: "completedShiftRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        XCTAssertTrue(
            row.label.contains("partial route"),
            "The visible mileage line marks the route partial: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("Route capture was partial"),
            "And it is said again where the rate is spoken: \(row.label)"
        )
    }

    /// A shift with no amount recorded shows no rates at all, rather than rates
    /// of zero.
    @MainActor
    func testShiftWithoutEarningsShowsNoRates() throws {
        let app = launchWithSeededHistory()

        let rows = app.descendants(matching: .any).matching(identifier: "completedShiftRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2, "The fixture holds one shift with earnings and one without")

        let withoutEarnings = rows.element(boundBy: 1)
        XCTAssertFalse(
            withoutEarnings.label.contains("gross earnings per"),
            "No amount recorded means no rate, not a rate of zero: \(withoutEarnings.label)"
        )
        XCTAssertFalse(withoutEarnings.label.contains("$0.00"))
    }

    /// Earnings on a shift with no route give an hourly rate and no invented
    /// per-mile one.
    @MainActor
    func testEarningsWithoutARouteShowNoPerMileRate() throws {
        let app = launchWithEmptyStore()
        let row = completeAShift(in: app)

        app.buttons["editShiftEarningsButton"].tap()
        type("86.25", into: app)
        app.buttons["saveEarningsButton"].tap()

        XCTAssertTrue(waitForRowLabel(row, toContain: "gross earnings per shift hour"))
        XCTAssertTrue(row.label.contains("No route recorded"))
        XCTAssertFalse(
            row.label.contains("recorded mile"),
            "A shift with nothing measurable in its route has no per-mile rate: \(row.label)"
        )
    }

    // MARK: Helpers

    /// Runs one shift start-to-finish and returns its row in history.
    ///
    /// Also asserts the safety rule the earnings flow depends on: nothing
    /// offers earnings entry while a shift is running.
    @MainActor
    private func completeAShift(in app: XCUIApplication) -> XCUIElement {
        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["editShiftEarningsButton"].exists,
            "Earnings entry must not be offered while the driver may be driving"
        )
        endButton.tap()

        let row = app.descendants(matching: .any).matching(identifier: "completedShiftRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        return row
    }

    @MainActor
    private func type(_ text: String, into app: XCUIApplication) {
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func clear(_ field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    }

    /// The row is one combined accessibility element, so what it displays is
    /// read from its label rather than from separate text elements.
    @MainActor
    private func waitForRowLabel(_ row: XCUIElement, toContain text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: row
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
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
