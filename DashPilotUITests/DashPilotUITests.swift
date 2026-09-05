import XCTest

final class DashPilotUITests: XCTestCase {
    /// Must match `LaunchArgument.inMemoryStore`; a UI test target cannot link the app target.
    private static let inMemoryStoreArgument = "-dashpilot-in-memory-store"

    /// Must match `LaunchArgument.seededHistory`, for the same reason.
    private static let seededHistoryArgument = "-dashpilot-seeded-history"

    /// Must match `LaunchArgument.seededActiveDelivery`, for the same reason.
    private static let seededActiveDeliveryArgument = "-dashpilot-seeded-active-delivery"

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

    /// Launches against a throwaway store holding a running shift with two
    /// deliveries already in progress, at different points in their lifecycles.
    ///
    /// This is the state a relaunch recovers into for stacked work. A UI test
    /// cannot terminate and reopen the in-memory store the other journeys use,
    /// so seeding it at launch is how the recovered interface is asserted end to
    /// end; that the store itself recovers every active delivery is proved in
    /// `DeliveryPersistenceTests`.
    ///
    /// The fixture's shift holds `Delivery 1` delivered, `Delivery 2` accepted
    /// and `Delivery 3` picked up.
    @MainActor
    private func launchWithActiveDelivery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededActiveDeliveryArgument)
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

    /// A completed shift with earnings and a measured route shows the rates over
    /// elapsed time and over recorded mileage, each saying what it divides by.
    /// The third, over delivery active time, has its own journey below.
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

    /// A completed shift states how much of it a delivery was active for, and
    /// what is left over — with overlapping deliveries counted once.
    ///
    /// The fixture's three deliveries run 5–30, 40–60 and 50–80 minutes into a
    /// three-hour shift. Two of them overlap, so the union is 65 minutes where
    /// their durations sum to 75.
    @MainActor
    func testDetailShowsDeliveryActiveAndNonDeliveryTime() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let active = app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"]
        XCTAssertTrue(active.waitForExistence(timeout: 5))
        XCTAssertTrue(
            active.label.contains("delivery active time"),
            "VoiceOver must hear which duration this is: \(active.label)"
        )
        XCTAssertTrue(active.label.contains("1 hour"), "The union is 65 minutes: \(active.label)")
        XCTAssertTrue(active.label.contains("5 minutes"))
        XCTAssertFalse(
            active.label.contains("15 minutes"),
            "Adding the overlapping deliveries' durations would give 1 hour 15: \(active.label)"
        )

        let nonDelivery = app.descendants(matching: .any)["shiftDetailNonDeliveryTime"]
        XCTAssertTrue(nonDelivery.exists)
        XCTAssertTrue(
            nonDelivery.label.contains("non-delivery time"),
            "The rest of the shift is named for what it is, not called idle: \(nonDelivery.label)"
        )
        XCTAssertTrue(nonDelivery.label.contains("1 hour"))
        XCTAssertTrue(nonDelivery.label.contains("55 minutes"), "Three hours less 65 minutes: \(nonDelivery.label)")

        // The three durations are told apart in words, not by position.
        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(elapsed.label.contains("elapsed shift time"), "\(elapsed.label)")
    }

    /// The active-hour rate divides by the unioned active time, not by the sum
    /// of the deliveries' durations.
    ///
    /// $86.25 over 65 minutes is $79.62. Over the 75 minutes the same three
    /// deliveries add up to it would be $69.00, which is the mistake this rate
    /// exists to avoid.
    @MainActor
    func testDetailActiveHourRateDividesByTheUnionedTime() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let rate = app.descendants(matching: .any)["shiftDetailActiveHourlyRate"]
        XCTAssertTrue(scrollTo(rate, in: app), "The performance section should be reachable")
        XCTAssertTrue(
            rate.label.contains("$79.62 gross earnings per delivery active hour"),
            "The denominator is the union of the overlapping deliveries: \(rate.label)"
        )
        XCTAssertFalse(
            rate.label.contains("$69.00"),
            "Summing the deliveries' durations would understate the rate: \(rate.label)"
        )

        // It remains gross earnings, and it never claims to measure work.
        for overclaim in ["wage", "true hourly", "net", "working", "driving"] {
            XCTAssertFalse(
                rate.label.lowercased().contains(overclaim),
                "The rate must not be described as \(overclaim): \(rate.label)"
            )
        }
    }

    /// A shift that recorded no deliveries shows no active time and no
    /// active-hour rate, rather than zero minutes and a rate divided by nothing.
    @MainActor
    func testShiftWithoutDeliveriesInventsNoActiveTime() throws {
        let app = launchWithSeededHistory()
        let history = rows(in: app)
        XCTAssertTrue(history.firstMatch.waitForExistence(timeout: 10))

        history.element(boundBy: 1).tap()

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5), "The shift still has an elapsed duration")
        XCTAssertFalse(
            app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"].exists,
            "No deliveries recorded is not zero minutes of delivery active time"
        )
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailNonDeliveryTime"].exists)

        let rate = app.descendants(matching: .any)["shiftDetailActiveHourlyRate"]
        XCTAssertTrue(scrollTo(rate, in: app))
        XCTAssertTrue(
            rate.label.contains("No gross earnings per delivery active hour"),
            "An absent rate is stated as absent: \(rate.label)"
        )
        XCTAssertFalse(rate.label.contains("$"), "Nothing may stand in for the rate: \(rate.label)")
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
        let segments = app.descendants(matching: .any)["shiftDetailCaptureSegments"]
        XCTAssertTrue(scrollTo(segments, in: app), "The route section's counts should be reachable")
        XCTAssertEqual(segments.label, "2 capture segments")
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

    // MARK: Deliveries

    /// Records one delivery from start to finish, one tap per event.
    ///
    /// The assertion that matters at every step is the button's spoken label:
    /// the card must offer exactly the next lifecycle action, named, and named
    /// for the delivery it belongs to.
    @MainActor
    func testRecordsADeliveryThroughItsLifecycle() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app), "The running shift offers a delivery control")
        XCTAssertEqual(startDelivery.label, "Start delivery")
        XCTAssertFalse(
            app.buttons["cancelDeliveryButton"].exists,
            "There is nothing to cancel before a delivery starts"
        )

        startDelivery.tap()

        // One primary action per state, in order, each naming its own event and
        // its own delivery.
        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        for expected in ["Mark arrived at pickup", "Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(
                waitForLabel(action, toContain: expected),
                "The control should offer \(expected), showed: \(action.label)"
            )
            XCTAssertTrue(
                app.buttons["cancelDeliveryButton"].exists,
                "A delivery in progress can be cancelled"
            )
            action.tap()
        }

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery completed"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("No delivery in progress"))
        XCTAssertFalse(app.buttons["cancelDeliveryButton"].exists)
        XCTAssertFalse(app.buttons["deliveryActionButton"].exists, "A finished delivery has no next step")

        // And the shift can now be ended, with the delivery recorded against it.
        app.buttons["endShiftButton"].tap()
        let row = rows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "1 delivery completed")
    }

    /// A second delivery starts while the first is still running, and the two
    /// appear as two cards with their own controls.
    @MainActor
    func testStartsASecondDeliveryWhileTheFirstIsRunning() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app))
        startDelivery.tap()

        let first = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(first, toContain: "Mark arrived at pickup"))

        // Starting another one is one tap, and it is still offered while the
        // first is running rather than hidden behind anything.
        XCTAssertTrue(startDelivery.exists, "Start Delivery stays available with a delivery in progress")
        startDelivery.tap()

        let second = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5), "A second card appears for the second delivery")
        XCTAssertEqual(
            first.label,
            "Delivery 1. Mark arrived at pickup",
            "Starting another delivery does not move the first one along"
        )
        XCTAssertEqual(second.label, "Delivery 2. Mark arrived at pickup")

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "2 deliveries in progress"), "Status: \(status.label)")

        // Advancing one leaves the other exactly where it was.
        second.tap()
        XCTAssertTrue(waitForLabel(second, toContain: "Delivery 2. Mark order picked up"))
        XCTAssertEqual(first.label, "Delivery 1. Mark arrived at pickup", "Delivery 1 is untouched")
    }

    /// Two deliveries left in progress are both picked up on the next launch,
    /// each showing its own next step.
    @MainActor
    func testRecoversEveryActiveDeliveryOnLaunch() throws {
        let app = launchWithActiveDelivery()

        let accepted = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(accepted, in: app), "The recovered deliveries have their own controls")
        XCTAssertEqual(
            accepted.label,
            "Delivery 2. Mark arrived at pickup",
            "The fixture's second delivery was only accepted, so its next step is arriving"
        )
        XCTAssertEqual(
            carrying.label,
            "Delivery 3. Mark delivery completed",
            "The third was already picked up, so its next step is delivering it"
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "deliveryActionButton").count,
            2,
            "Two active deliveries, neither collapsed into the other nor duplicated"
        )

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(status.label.contains("2 deliveries in progress"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("1 delivery completed"), "The shift's earlier delivery is still counted")
    }

    /// Completing one of two deliveries leaves the other running.
    @MainActor
    func testCompletingOneDeliveryLeavesTheOtherRunning() throws {
        let app = launchWithActiveDelivery()

        let accepted = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(carrying, in: app))
        carrying.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "The delivered one leaves the list"
        )
        XCTAssertEqual(
            accepted.label,
            "Delivery 2. Mark arrived at pickup",
            "The remaining delivery keeps its number and its own next step"
        )

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery in progress"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("2 deliveries completed"))
    }

    /// A shift cannot be ended while any delivery is in progress, the refusal
    /// says how many, and it stays refused until the last one is resolved.
    @MainActor
    func testActiveDeliveriesBlockEndingTheShift() throws {
        let app = launchWithActiveDelivery()

        let endShift = app.buttons["endShiftButton"]
        XCTAssertTrue(endShift.waitForExistence(timeout: 10))
        endShift.tap()

        let plural = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "2 deliveries are still in progress")
        )
        XCTAssertTrue(
            plural.firstMatch.waitForExistence(timeout: 5),
            "Ending is refused with a reason that counts them, not silently"
        )
        app.buttons["OK"].tap()

        // Nothing was ended and nothing was silently completed.
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 5), "The shift is still running")
        XCTAssertTrue(rows(in: app).count == 0, "No completed shift appeared in history")

        // Resolving one of the two is not enough.
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(carrying, in: app))
        carrying.tap()
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1))

        app.buttons["endShiftButton"].tap()
        let singular = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "A delivery is still in progress")
        )
        XCTAssertTrue(
            singular.firstMatch.waitForExistence(timeout: 5),
            "One remaining delivery still blocks the end, and the wording follows the count"
        )
        app.buttons["OK"].tap()

        // Resolving the last one unblocks it.
        let accepted = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(accepted, in: app))
        accepted.tap()
        XCTAssertTrue(waitForLabel(accepted, toContain: "Mark order picked up"))
        accepted.tap()
        XCTAssertTrue(waitForLabel(accepted, toContain: "Mark delivery completed"))
        accepted.tap()

        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 0))
        app.buttons["endShiftButton"].tap()
        XCTAssertTrue(rows(in: app).firstMatch.waitForExistence(timeout: 5), "The shift ends once nothing is running")
    }

    /// Cancelling names the delivery it will cancel, keeps it as history, and
    /// leaves the other delivery alone.
    @MainActor
    func testCancellingOneDeliveryKeepsItAsHistoryAndSparesTheOther() throws {
        let app = launchWithActiveDelivery()

        let cancel = deliveryButton("cancelDeliveryButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(cancel, in: app))
        XCTAssertEqual(cancel.label, "Delivery 2. Cancel this delivery", "The control says which delivery it ends")
        cancel.tap()

        // The confirmation names it too: with two in progress, "Cancel Delivery"
        // alone would be ambiguous.
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cancel Delivery 2?"))
        XCTAssertTrue(title.firstMatch.waitForExistence(timeout: 5), "The confirmation names the delivery")

        // `firstMatch` because SwiftUI mirrors the identifier onto the button's
        // own label element as well as the button.
        let confirm = app.buttons.matching(identifier: "confirmCancelDeliveryButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery cancelled"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("1 delivery completed"), "The cancelled one is not counted as completed")

        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(carrying.exists, "The other delivery is untouched by the cancellation")
        XCTAssertEqual(carrying.label, "Delivery 3. Mark delivery completed")
        carrying.tap()

        app.buttons["endShiftButton"].tap()
        openFirstShift(in: app)
        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled")
    }

    /// A completed shift's detail lists what each delivery recorded, including
    /// two whose lifecycles overlapped.
    @MainActor
    func testCompletedShiftDetailShowsDeliveryLifecycles() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(
            summary.label,
            "2 deliveries completed. 1 delivery cancelled",
            "The fixture holds two delivered and one cancelled"
        )

        // Rows are matched by what they say rather than by index. A `List` only
        // renders what is near the viewport, so a count over the whole section
        // would be asserting how far the screen happened to have scrolled.
        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app), "The first delivery is listed")
        XCTAssertTrue(first.label.contains("Accepted at"), "Each recorded event is spoken with its time: \(first.label)")
        XCTAssertTrue(
            first.label.contains("Waited at pickup"),
            "The pickup wait is derived from both its ends: \(first.label)"
        )
        XCTAssertTrue(first.label.contains("Accepted to delivered"))

        // The cancelled one is listed too, keeping what happened and claiming
        // nothing that did not.
        let cancelled = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(cancelled, in: app), "A cancelled delivery is history, not an omission")
        let label = cancelled.label
        XCTAssertTrue(label.contains("Arrived at pickup at"), "The arrival that happened is kept: \(label)")
        XCTAssertFalse(label.contains("Picked up at"), "Nothing it did not record is shown: \(label)")
        XCTAssertFalse(label.contains("Waited at pickup"), "A wait with no end is not derived: \(label)")
        XCTAssertFalse(label.contains("Accepted to delivered"))

        // And the third, accepted while the second was still open: overlapping
        // deliveries stay separate rows rather than being merged or flagged.
        XCTAssertTrue(
            scrollTo(deliveryRow(containing: "Delivery 3, delivered", in: app), in: app),
            "Every recorded delivery is listed"
        )
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

    /// One of the running shift's delivery controls, identified by which
    /// delivery its label names rather than by where it sits in the list.
    @MainActor
    private func deliveryButton(
        _ identifier: String,
        containing text: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, text))
            .firstMatch
    }

    /// One delivery row on the detail screen, identified by what it says.
    @MainActor
    private func deliveryRow(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "shiftDetailDeliveryRow",
                    text
                )
            )
            .firstMatch
    }

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
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
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
