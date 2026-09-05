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

    /// Start a shift, see it running, end it, and find it in history.
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
            rows(in: app).firstMatch.waitForExistence(timeout: 5),
            "The finished shift should appear in history"
        )
    }

    // MARK: Detail

    /// Tapping a completed shift opens that shift, and shows what it recorded.
    @MainActor
    func testOpensTheDetailOfTheTappedShift() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(history.count, 2, "The fixture holds one shift with earnings and one without")

        // The older shift: no amount, no route.
        history.element(boundBy: 1).tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertEqual(earnings.label, "No amount recorded")
        XCTAssertTrue(
            app.descendants(matching: .any)["shiftDetailRecordedMileage"].label.contains("No route recorded"),
            "A shift with nothing measurable says so rather than showing zero miles"
        )
        goBack(in: app)

        // The recent shift: its own amount and its own route, not the other's.
        history.element(boundBy: 0).tap()
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("$86.25"), "Detail shows the tapped shift's amount: \(earnings.label)")
        XCTAssertTrue(
            app.descendants(matching: .any)["shiftDetailRecordedMileage"].label.contains("miles recorded"),
            "Detail shows the tapped shift's own measured route"
        )
    }

    /// A completed shift with earnings and a measured route shows both rates,
    /// each saying what it divides by.
    @MainActor
    func testDetailShowsBothDerivedRates() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        // The hourly figure is asserted exactly because it comes from the
        // fixture's timestamps ($86.25 over three hours); the per-mile figure is
        // asserted by its wording only, because its denominator comes from
        // measuring synthetic coordinates and pinning its cents would test the
        // haversine, not the screen.
        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app), "The performance section should be reachable")
        XCTAssertTrue(
            hourly.label.contains("$28.75 gross earnings per shift hour"),
            "The hourly rate divides by the whole elapsed shift: \(hourly.label)"
        )

        let perMile = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(
            perMile.label.contains("gross earnings per recorded mile"),
            "The per-mile rate must say which miles it divides by: \(perMile.label)"
        )
        XCTAssertFalse(
            perMile.label.contains("per mile driven"),
            "A bare per-mile claim would present recorded mileage as the mileage driven: \(perMile.label)"
        )
    }

    /// A route with known gaps is marked partial, and the detail screen says
    /// what the gaps are.
    @MainActor
    func testDetailExplainsRouteQuality() throws {
        let app = launchWithSeededHistory()

        let row = rows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(
            row.label.contains("more miles were driven than were recorded"),
            "The row still says the route is partial: \(row.label)"
        )

        row.tap()

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 5))
        XCTAssertTrue(
            mileage.label.contains("Partial route"),
            "Detail states partiality in plain language: \(mileage.label)"
        )
        XCTAssertFalse(
            mileage.label.contains("Coverage"),
            "Nothing may claim a coverage percentage: \(mileage.label)"
        )

        // The fixture is two capture sessions with a gap in between, which is
        // what makes the route partial in the first place.
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailCaptureSegments"].label, "2 capture segments")
        XCTAssertTrue(
            app.descendants(matching: .any)["shiftDetailCaptureGaps"].label.contains("capture gap"),
            "Detail counts the gaps the mileage excluded"
        )
    }

    /// A shift with nothing measurable in its route shows no counts at all,
    /// rather than counts of zero.
    @MainActor
    func testDetailInventsNoRouteInformation() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))

        history.element(boundBy: 1).tap()

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 5))
        XCTAssertTrue(mileage.label.contains("No route recorded"))
        XCTAssertFalse(mileage.label.contains("0.0"), "An unmeasurable route is not a distance of zero")
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailCaptureSegments"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailCaptureGaps"].exists)
    }

    /// A shift with no amount recorded is told why it has no rates, rather than
    /// being shown rates of zero.
    @MainActor
    func testDetailExplainsRatesItCannotDerive() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))

        let withoutEarnings = history.element(boundBy: 1)
        XCTAssertFalse(
            withoutEarnings.label.contains("gross earnings per"),
            "No amount recorded means no rate on the row: \(withoutEarnings.label)"
        )
        XCTAssertFalse(withoutEarnings.label.contains("$0.00"))

        withoutEarnings.tap()

        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(
            hourly.label.contains("Add what this shift paid"),
            "Detail explains the absent rate instead of showing zero: \(hourly.label)"
        )
        XCTAssertFalse(hourly.label.contains("$0.00"))
    }

    // MARK: Earnings, from detail

    /// Records earnings on a finished shift, then changes the amount.
    ///
    /// The whole point of the flow is that it happens *after* driving, so the
    /// journey ends a shift first and asserts that no earnings control existed
    /// while it was running.
    @MainActor
    func testAddsAndEditsEarningsFromDetail() throws {
        let app = launchWithEmptyStore()
        completeAShift(in: app)
        openFirstShift(in: app)

        let addButton = app.buttons["editShiftEarningsButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertEqual(addButton.label, "Add Earnings", "A shift with no amount offers to add one")

        addButton.tap()
        type("86.25", into: app)
        app.buttons["saveEarningsButton"].tap()

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(waitForLabel(earnings, toContain: "86.25"), "Detail shows the recorded amount: \(earnings.label)")
        XCTAssertEqual(app.buttons["editShiftEarningsButton"].label, "Edit Earnings")

        // Editing replaces the amount rather than adding to it.
        app.buttons["editShiftEarningsButton"].tap()
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "86.25", "The editor opens on the stored amount")
        clear(field, in: app)
        type("104.10", into: app)
        app.buttons["saveEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(earnings, toContain: "104.10"), "The edited amount replaces the previous one")
        XCTAssertFalse(earnings.label.contains("86.25"))

        // And the history row behind it is the same shift.
        goBack(in: app)
        let row = rows(in: app).firstMatch
        XCTAssertTrue(waitForLabel(row, toContain: "104.10"), "History shows the amount too: \(row.label)")
    }

    /// An amount that cannot be read is refused, and refusing it changes nothing.
    @MainActor
    func testInvalidEarningsAreNotSaved() throws {
        let app = launchWithEmptyStore()
        completeAShift(in: app)
        openFirstShift(in: app)

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
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailEarnings"].label, "No amount recorded")
    }

    /// Earnings on a shift with no route give an hourly rate and no invented
    /// per-mile one.
    @MainActor
    func testEarningsWithoutARouteShowNoPerMileRate() throws {
        let app = launchWithEmptyStore()
        completeAShift(in: app)
        openFirstShift(in: app)

        app.buttons["editShiftEarningsButton"].tap()
        type("86.25", into: app)
        app.buttons["saveEarningsButton"].tap()

        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(waitForLabel(hourly, toContain: "gross earnings per shift hour"))

        let perMile = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(perMile, in: app))
        XCTAssertTrue(
            perMile.label.contains("No usable position was recorded"),
            "A shift with nothing measurable in its route is told why, not shown a rate: \(perMile.label)"
        )
        XCTAssertFalse(perMile.label.contains("$0.00"))
    }

    // MARK: Deletion

    /// Deletes a completed shift from its detail screen and returns to a history
    /// that no longer holds it.
    @MainActor
    func testDeletesACompletedShift() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(history.count, 2)

        history.element(boundBy: 0).tap()

        let deleteButton = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(deleteButton, in: app), "Deletion lives at the bottom of the detail screen")
        deleteButton.tap()

        // Destructive and explicit: the confirmation says the route goes too.
        // `firstMatch` because SwiftUI mirrors the identifier onto the button's
        // own label element as well as the button.
        let confirm = app.buttons.matching(identifier: "confirmDeleteShiftButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "route positions")).count > 0,
            "The confirmation must say the shift's route is deleted with it"
        )
        confirm.tap()

        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 5), "Detail returns to history")
        let remaining = rows(in: app)
        XCTAssertTrue(waitForCount(remaining, toEqual: 1), "The deleted shift is gone from history")
        XCTAssertFalse(remaining.firstMatch.label.contains("$86.25"), "And the shift that remains is the other one")
    }

    /// Backing out of the confirmation deletes nothing.
    @MainActor
    func testCancellingDeletionKeepsTheShift() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))

        history.element(boundBy: 0).tap()
        let deleteButton = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(deleteButton, in: app))
        deleteButton.tap()

        let cancel = app.buttons.matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(app.buttons["deleteShiftButton"].waitForExistence(timeout: 5), "Detail is still open")
        goBack(in: app)
        XCTAssertTrue(waitForCount(rows(in: app), toEqual: 2), "Both shifts are still in history")
    }

    // MARK: Helpers

    @MainActor
    private func rows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "completedShiftRow")
    }

    /// Runs one shift start-to-finish.
    ///
    /// Also asserts the safety rule the earnings flow depends on: nothing offers
    /// earnings entry while a shift is running.
    @MainActor
    private func completeAShift(in app: XCUIApplication) {
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

        XCTAssertTrue(rows(in: app).firstMatch.waitForExistence(timeout: 5))
    }

    /// Brings an element into the accessibility hierarchy before asserting on it.
    ///
    /// A `List` only renders the rows near the viewport, so a section further
    /// down the detail screen does not exist until it is scrolled to — which is
    /// a fact about `UICollectionView`, not about the screen being wrong.
    @MainActor
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func openFirstShift(in app: XCUIApplication) {
        let row = rows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 5))
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

    /// A row and a detail metric are each one combined accessibility element, so
    /// what they display is read from the label — which is also what a VoiceOver
    /// user hears.
    @MainActor
    private func waitForLabel(_ element: XCUIElement, toContain text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, toEqual count: Int) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count),
            object: query
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
