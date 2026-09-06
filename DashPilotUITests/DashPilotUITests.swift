import XCTest

final class DashPilotUITests: XCTestCase {
    /// Must match `LaunchArgument.inMemoryStore`; a UI test target cannot link the app target.
    private static let inMemoryStoreArgument = "-dashpilot-in-memory-store"

    /// Must match `LaunchArgument.seededHistory`, for the same reason.
    private static let seededHistoryArgument = "-dashpilot-seeded-history"

    /// Must match `LaunchArgument.seededActiveDelivery`, for the same reason.
    private static let seededActiveDeliveryArgument = "-dashpilot-seeded-active-delivery"

    /// Must match `LaunchArgument.seededPickupHistory`, for the same reason.
    private static let seededPickupHistoryArgument = "-dashpilot-seeded-pickup-history"

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

    /// Launches against a throwaway store holding one completed shift whose
    /// deliveries give two pickup places different amounts of recorded history.
    ///
    /// The fixture's shift holds, in acceptance order: three deliveries from
    /// `Nowhere Noodles` waiting 6, 11 and 41 minutes; one from `Example Diner`
    /// waiting 20 minutes; one naming no place at all; and one that arrived at
    /// `Nowhere Noodles` and cancelled without ever picking up.
    @MainActor
    private func launchWithPickupHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPickupHistoryArgument)
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

        // Scrolled to rather than assumed on screen: this shift records
        // deliveries, so the route section sits below a taller shift section
        // than the empty one above did.
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(
            mileage.label.contains("miles recorded"),
            "Detail shows the tapped shift's own measured route: \(mileage.label)"
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
        XCTAssertTrue(scrollTo(mileage, in: app), "The route section should be reachable")
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

        XCTAssertTrue(scrollToTop(reaching: app.buttons["endShiftButton"], in: app))
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
        XCTAssertTrue(scrollToTop(reaching: app.buttons["endShiftButton"], in: app))
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

    // MARK: Delivery earnings, from detail

    /// Records an amount against one finished delivery, then changes it.
    ///
    /// The whole point of the flow is that it happens *after* the driving, so
    /// the journey drives a delivery to completion first and asserts that the
    /// running shift offered no earnings control at any point.
    @MainActor
    func testAddsAndEditsDeliveryEarningsFromDetail() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertFalse(row.label.contains("Gross earnings"), "Nothing is recorded until the driver records it")

        let addButton = app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch
        XCTAssertEqual(
            addButton.label,
            "Add gross earnings for Delivery 1",
            "The control names the delivery it acts on"
        )
        addButton.tap()

        typeDeliveryAmount("14.75", in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()

        XCTAssertTrue(
            waitForLabel(row, toContain: "Gross earnings for Delivery 1, $14.75"),
            "The amount is spoken with its delivery: \(row.label)"
        )
        XCTAssertEqual(
            app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.label,
            "Edit gross earnings for Delivery 1"
        )

        // Editing replaces the amount rather than adding to it.
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "14.75", "The editor opens on the stored amount")
        clear(field, in: app)
        field.typeText("9.50")
        app.buttons["saveDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(row, toContain: "$9.50"), "The edited amount replaces the previous one")
        XCTAssertFalse(row.label.contains("$14.75"))
    }

    /// Cancelling an edit writes nothing, leaving the amount as it was.
    @MainActor
    func testCancellingADeliveryEarningsEditKeepsTheAmount() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        typeDeliveryAmount("14.75", in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "$14.75"))

        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        field.typeText("99.99")
        app.buttons["cancelDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(row, toContain: "$14.75"), "Cancel writes nothing: \(row.label)")
        XCTAssertFalse(row.label.contains("99.99"))
    }

    /// Removing an amount returns the delivery to having none, which is not a
    /// recorded zero.
    @MainActor
    func testRemovesDeliveryEarnings() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        typeDeliveryAmount("14.75", in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "$14.75"))

        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let remove = app.buttons["removeDeliveryEarningsButton"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.label, "Remove gross earnings from Delivery 1")
        remove.tap()

        XCTAssertTrue(
            app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.label,
            "Add gross earnings for Delivery 1",
            "The delivery is back to having no amount recorded"
        )
        XCTAssertFalse(row.label.contains("Gross earnings"), "Removed is not $0.00: \(row.label)")
    }

    /// Two deliveries the driver worked at the same time hold their own amounts,
    /// and editing one leaves the other exactly as it was.
    @MainActor
    func testStackedDeliveriesKeepIndependentAmounts() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        // The fixture's first and third deliveries carry amounts and its second
        // carries none; the second and third overlap.
        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("Gross earnings for Delivery 1, $14.75"),
            "Showed: \(first.label)"
        )
        XCTAssertTrue(
            first.label.contains("$35.40 gross earnings per recorded delivery hour"),
            "The rate names its denominator in full: \(first.label)"
        )

        let second = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertFalse(
            second.label.contains("Gross earnings"),
            "A delivery with no amount recorded shows none: \(second.label)"
        )

        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("Gross earnings for Delivery 3, $9.50"), "Showed: \(third.label)")

        // Editing the third leaves the first alone.
        let editThird = app.buttons
            .matching(identifier: "shiftDetailDeliveryEarningsButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "Delivery 3"))
            .firstMatch
        XCTAssertTrue(editThird.exists)
        editThird.tap()

        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        field.typeText("20.00")
        app.buttons["saveDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(third, toContain: "$20.00"), "Showed: \(third.label)")
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("$14.75"),
            "One delivery's amount is its own, however far the lifecycles overlap: \(first.label)"
        )
    }

    /// Editing a delivery's amount does not touch what the shift recorded.
    @MainActor
    func testEditingADeliveryAmountLeavesTheShiftTotalUnchanged() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let shiftEarnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(shiftEarnings.waitForExistence(timeout: 10))
        XCTAssertTrue(shiftEarnings.label.contains("86.25"), "The fixture's shift total: \(shiftEarnings.label)")

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        app.buttons
            .matching(identifier: "shiftDetailDeliveryEarningsButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "Delivery 1"))
            .firstMatch
            .tap()

        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        field.typeText("50.00")
        app.buttons["saveDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(row, toContain: "$50.00"))

        // Back up to the shift's own figure, which nothing recalculated.
        XCTAssertTrue(scrollToTop(reaching: shiftEarnings, in: app))
        XCTAssertTrue(
            shiftEarnings.label.contains("86.25"),
            "A delivery amount never adds up to, or corrects, the shift total: \(shiftEarnings.label)"
        )
    }

    // MARK: Pickup identity

    /// A pickup place is named on a running delivery, and the card shows it.
    ///
    /// The lifecycle assertions around it are the point as much as the name is:
    /// the delivery's next step is still one tap away before and after, so the
    /// identity is genuinely optional rather than a step in the flow.
    @MainActor
    func testAssignsAPickupPlaceToARunningDelivery() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)

        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark arrived at pickup"))

        let pickup = deliveryButton("pickupPlaceButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(pickup, in: app), "The card offers a pickup place control")
        XCTAssertEqual(pickup.label, "Add pickup place for Delivery 1")
        pickup.tap()

        typePickupPlace(Self.noodles, in: app)
        app.buttons["savePickupPlaceButton"].tap()

        let status = deliveryStatus(containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(status, toContain: Self.noodles), "The card names the place: \(status.label)")
        XCTAssertTrue(waitForLabel(pickup, toContain: "Change pickup place"), "And the control now offers a change")
        XCTAssertEqual(
            action.label,
            "Delivery 1. Mark arrived at pickup",
            "Naming a pickup advances nothing"
        )

        // And the lifecycle still runs, one tap per event, exactly as before.
        for expected in ["Mark arrived at pickup", "Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(waitForLabel(action, toContain: expected), "Showed: \(action.label)")
            action.tap()
        }
        XCTAssertFalse(app.buttons["deliveryActionButton"].exists)
    }

    /// A second delivery reuses the first delivery's place from the recent list,
    /// in one tap and with no typing.
    @MainActor
    func testSecondDeliveryReusesARecentPickupPlace() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)

        let first = deliveryButton("pickupPlaceButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        first.tap()
        typePickupPlace(Self.noodles, in: app)
        app.buttons["savePickupPlaceButton"].tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app))
        startDelivery.tap()

        let second = deliveryButton("pickupPlaceButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()

        // No keyboard: the place the first delivery named is offered as recent.
        let recent = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "recentPickupPlaceButton", Self.noodles))
            .firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "The place used moments ago is offered")
        recent.tap()

        for number in ["Delivery 1", "Delivery 2"] {
            let status = deliveryStatus(containing: number, in: app)
            XCTAssertTrue(
                waitForLabel(status, toContain: Self.noodles),
                "\(number) should name the shared place, showed: \(status.label)"
            )
        }
    }

    /// A pickup place tapped onto the wrong delivery can be corrected.
    @MainActor
    func testChangesAPickupPlace() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)

        let pickup = deliveryButton("pickupPlaceButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(pickup, in: app))
        pickup.tap()
        typePickupPlace(Self.noodles, in: app)
        app.buttons["savePickupPlaceButton"].tap()

        let status = deliveryStatus(containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(status, toContain: Self.noodles))

        XCTAssertTrue(waitForLabel(pickup, toContain: "Change pickup place"))
        pickup.tap()
        let field = app.textFields["pickupPlaceNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, Self.noodles, "The editor opens on what was recorded")
        clear(field, in: app)
        field.typeText(Self.diner)
        app.buttons["savePickupPlaceButton"].tap()

        XCTAssertTrue(waitForLabel(status, toContain: Self.diner), "Showed: \(status.label)")
        XCTAssertFalse(status.label.contains(Self.noodles), "The old place is gone from the card")
    }

    /// Removing a pickup place leaves the delivery and its lifecycle intact.
    @MainActor
    func testRemovesAPickupPlace() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)

        let pickup = deliveryButton("pickupPlaceButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(pickup, in: app))
        pickup.tap()
        typePickupPlace(Self.noodles, in: app)
        app.buttons["savePickupPlaceButton"].tap()

        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark arrived at pickup"))
        action.tap()
        XCTAssertTrue(waitForLabel(action, toContain: "Mark order picked up"))

        XCTAssertTrue(waitForLabel(pickup, toContain: "Change pickup place"))
        pickup.tap()
        let remove = app.buttons["removePickupPlaceButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()

        let status = deliveryStatus(containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(status, toContain: "waiting at the pickup"), "Showed: \(status.label)")
        XCTAssertFalse(status.label.contains(Self.noodles), "The place is gone")
        XCTAssertEqual(
            action.label,
            "Delivery 1. Mark order picked up",
            "And the delivery is exactly where it was in its lifecycle"
        )
        XCTAssertTrue(waitForLabel(pickup, toContain: "Add pickup place"))
    }

    /// A completed shift's delivery log shows the place each delivery recorded,
    /// and shows nothing where none was recorded.
    @MainActor
    func testCompletedShiftDetailShowsPickupPlaces() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))

        // The fixture's first and third deliveries share one place; the second
        // carries a different one.
        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("Picked up from \(Self.noodles)"),
            "The place is spoken with the delivery: \(first.label)"
        )
        XCTAssertTrue(first.label.contains("Accepted at"), "And supplements the record rather than replacing it")

        let second = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(second.label.contains("Picked up from \(Self.diner)"), "Showed: \(second.label)")

        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(
            third.label.contains("Picked up from \(Self.noodles)"),
            "Two deliveries share one local place: \(third.label)"
        )

        // And every delivery offers the control that corrects it.
        XCTAssertTrue(
            app.buttons.matching(identifier: "shiftDetailPickupPlaceButton").firstMatch.exists,
            "A place recorded on the wrong delivery is fixable from history"
        )
    }

    // MARK: Pickup wait history

    /// A completed delivery states the wait it recorded, as a fact about that
    /// delivery rather than about the place.
    @MainActor
    func testCompletedDeliveryShowsItsOwnPickupWait() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("Waited at pickup 6 minutes"),
            "The delivery's own wait is derived from its two recorded ends: \(first.label)"
        )
        XCTAssertFalse(
            first.label.lowercased().contains("typical"),
            "One delivery's wait is not a claim about the place: \(first.label)"
        )
        XCTAssertFalse(first.label.contains("median"))
    }

    /// A place with several recorded waits shows the median, says it is the
    /// median, and says how many pickups it came from.
    @MainActor
    func testPickupPlaceHistoryShowsAMedianAndItsSampleCount() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 1, delivered", in: app)

        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(
            summary.label.contains("Typical recorded pickup wait, 11 minutes"),
            "The middle of 6, 11 and 41 minutes: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("median of 3 recorded pickups"),
            "The statistic and its sample count are spoken with the figure: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("longest 41 minutes"),
            "A long wait is kept rather than trimmed away: \(summary.label)"
        )

        // The delivery that arrived and cancelled without picking up named this
        // place too, and contributed nothing.
        XCTAssertFalse(summary.label.contains("4 recorded pickups"), "Showed: \(summary.label)")

        // Nothing on this screen ranks, grades or forecasts.
        for overclaim in ["reliable", "accurate", "predict", "average", "score", "best", "fastest"] {
            XCTAssertFalse(
                summary.label.lowercased().contains(overclaim),
                "The history must not claim \(overclaim): \(summary.label)"
            )
        }
    }

    /// A place with exactly one recorded wait says so, and refuses to call it
    /// typical.
    @MainActor
    func testOneRecordedPickupIsNotPresentedAsATypicalWait() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 5, delivered", in: app)

        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(
            summary.label.contains("1 recorded pickup, 20 minutes"),
            "The one wait is a fact and is stated: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("Not enough history for a typical wait"),
            "And its smallness is stated with it: \(summary.label)"
        )
        XCTAssertFalse(
            summary.label.lowercased().contains("typical recorded pickup wait"),
            "One observation is never offered as the place's typical wait: \(summary.label)"
        )
        XCTAssertFalse(summary.label.contains("Median"), "Showed: \(summary.label)")
    }

    /// Two places recorded on one shift keep entirely separate histories.
    @MainActor
    func testTwoPickupPlacesDoNotShareAHistory() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)

        openPickupHistory(from: "Delivery 1, delivered", in: app)
        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[Self.noodles].exists, "The sheet is titled by the place it describes")
        XCTAssertTrue(summary.label.contains("3 recorded pickups"), "Showed: \(summary.label)")
        closePickupHistory(in: app)

        openPickupHistory(from: "Delivery 5, delivered", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[Self.diner].exists)
        XCTAssertTrue(summary.label.contains("1 recorded pickup"), "Showed: \(summary.label)")
        XCTAssertFalse(
            summary.label.contains("11 minutes"),
            "The other place's median must not leak into this one: \(summary.label)"
        )
    }

    /// A delivery that names no place offers no history to open, rather than an
    /// empty one.
    @MainActor
    func testDeliveryWithoutAPickupPlaceHasNoHistoryToOpen() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)

        let unattributed = deliveryRow(containing: "Delivery 6, delivered", in: app)
        XCTAssertTrue(scrollTo(unattributed, in: app))
        XCTAssertFalse(
            unattributed.label.contains("Picked up from"),
            "It named no place: \(unattributed.label)"
        )
        XCTAssertTrue(
            unattributed.label.contains("Waited at pickup"),
            "Its own wait is still recorded: \(unattributed.label)"
        )
        XCTAssertNil(
            pickupHistoryButton(near: unattributed, in: app),
            "A delivery with no place has no place history, and is offered none"
        )
    }

    // MARK: Correcting a pickup place

    /// A misspelled place can be renamed, and the rename changes only its name.
    @MainActor
    func testRenamesAPickupPlaceFromItsHistory() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 1, delivered", in: app)

        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let before = summary.label

        let rename = app.buttons["renamePickupPlaceButton"]
        XCTAssertTrue(scrollTo(rename, in: app), "Managing the place is offered on the place's own screen")
        XCTAssertEqual(rename.label, "Rename pickup place, \(Self.noodles)", "The control names its place")
        rename.tap()

        let field = app.textFields["pickupPlaceRenameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, Self.noodles, "The sheet opens on the recorded spelling")
        clear(field, in: app)
        field.typeText(Self.renamedNoodles)
        app.buttons["savePickupPlaceRenameButton"].tap()

        XCTAssertTrue(
            app.navigationBars[Self.renamedNoodles].waitForExistence(timeout: 5),
            "The history is now titled by the new name"
        )
        XCTAssertEqual(summary.label, before, "And says exactly what it said before: a rename moves no wait")

        closePickupHistory(in: app)
        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(waitForLabel(row, toContain: "Picked up from \(Self.renamedNoodles)"))
        XCTAssertTrue(row.label.contains("Waited at pickup 6 minutes"), "Its own record is untouched: \(row.label)")
    }

    /// Renaming onto a name another place already uses is refused, and the
    /// refusal points at merging instead.
    @MainActor
    func testRenamingOntoAnExistingPlaceIsRefusedAndOffersMerge() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 1, delivered", in: app)

        let rename = app.buttons["renamePickupPlaceButton"]
        XCTAssertTrue(scrollTo(rename, in: app))
        rename.tap()

        let field = app.textFields["pickupPlaceRenameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        field.typeText(Self.diner)
        app.buttons["savePickupPlaceRenameButton"].tap()

        // A `Label` mirrors its identifier onto both the icon and the text, so
        // the text element is asked for by name rather than by `descendants`.
        let message = app.staticTexts.matching(identifier: "pickupPlaceRenameMessage").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The rename is refused rather than silently merged")
        XCTAssertTrue(message.label.contains(Self.diner), "It names what it collided with: \(message.label)")
        XCTAssertTrue(
            message.label.lowercased().contains("merge"),
            "And offers the deliberate operation that would combine them: \(message.label)"
        )
        XCTAssertTrue(field.exists, "The sheet stays open with what was typed")

        app.buttons["cancelPickupPlaceRenameButton"].tap()
        XCTAssertTrue(
            app.navigationBars[Self.noodles].waitForExistence(timeout: 5),
            "And the place still has the name it had"
        )
    }

    /// Two places a driver meant as one are merged, deliberately, and their
    /// recorded waits are then read together.
    @MainActor
    func testMergesTwoPickupPlacesIntoOneHistory() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 5, delivered", in: app)

        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 recorded pickup"), "Showed: \(summary.label)")

        let merge = app.buttons["mergePickupPlaceButton"]
        XCTAssertTrue(scrollTo(merge, in: app))
        XCTAssertEqual(merge.label, "Merge pickup place, \(Self.diner)")
        merge.tap()

        // The destination control speaks the direction in full, so the merge
        // cannot be read as symmetric.
        let destination = app.buttons
            .matching(identifier: "pickupPlaceMergeDestinationButton")
            .matching(NSPredicate(format: "label == %@", "Merge \(Self.diner) into \(Self.noodles)"))
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()

        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let spoken = confirmation.label + " " + confirmation.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(spoken.contains(Self.diner) && spoken.contains(Self.noodles), "Showed: \(spoken)")
        XCTAssertTrue(spoken.contains("will move to"), "The deliveries move: \(spoken)")
        XCTAssertFalse(
            spoken.lowercased().contains("deliveries will be deleted"),
            "Nothing recorded is destroyed: \(spoken)"
        )
        confirmation.buttons.matching(identifier: "confirmPickupPlaceMergeButton").firstMatch.tap()

        // The merged-away place is gone, so its history closes with it.
        XCTAssertTrue(waitForDisappearance(of: summary), "The source no longer exists to be shown")

        let moved = deliveryRow(containing: "Delivery 5, delivered", in: app)
        XCTAssertTrue(waitForLabel(moved, toContain: "Picked up from \(Self.noodles)"))
        XCTAssertTrue(moved.label.contains("Waited at pickup 20 minutes"), "Keeping its own record: \(moved.label)")

        // Read from the delivery that moved: its history button now names the
        // surviving place, and opens the combined history.
        openPickupHistory(from: "Delivery 5, delivered", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[Self.noodles].exists, "Under the destination's name")
        XCTAssertTrue(
            summary.label.contains("median of 4 recorded pickups"),
            "Three waits plus the one that moved: \(summary.label)"
        )
        // 6, 11, 20 and 41 minutes: the midpoint of the middle two, rounded for
        // the screen. Neither place said this before the merge.
        XCTAssertTrue(
            summary.label.contains("Typical recorded pickup wait, 16 minutes"),
            "Recomputed from the deliveries rather than from a stored figure: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("Shortest recorded wait 6 minutes")
                && summary.label.contains("longest 41 minutes"),
            "The spread spans both places' waits: \(summary.label)"
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

    /// Invented pickup-place names, matching `PreviewSupport.SyntheticPickupPlace`;
    /// a UI test target cannot link the app target, so they are repeated here.
    /// No real business is named anywhere in this repository.
    private static let noodles = "Nowhere Noodles"
    private static let diner = "Example Diner"

    /// What the rename journey renames `noodles` to. Invented, like the rest.
    private static let renamedNoodles = "Nowhere Noodle Bar"

    /// Starts a shift and one delivery on it, which is the state three of the
    /// pickup journeys begin from.
    @MainActor
    private func startShiftAndDelivery(in app: XCUIApplication) {
        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app))
        startDelivery.tap()
    }

    /// Types a name into the pickup-place sheet's only field.
    @MainActor
    private func typePickupPlace(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["pickupPlaceNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
    }

    /// One running delivery's status element, identified by which delivery it
    /// names. It is a combined element, so what the card shows is read from its
    /// label — which is also what VoiceOver says.
    @MainActor
    private func deliveryStatus(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activeDeliveryStatus",
                    text
                )
            )
            .firstMatch
    }

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

    /// Scrolls back to the top of the screen and waits for `element` there.
    ///
    /// The shift's own controls sit above the delivery section, so a test that
    /// reached a delivery card — or that tapped one XCUITest had to scroll into
    /// view first — has to come back before it can tap `End Shift`. It swipes
    /// unconditionally rather than checking first: a `List` reports a row it has
    /// scrolled past as existing and hittable, and tapping that stale frame
    /// lands on whatever is now in its place.
    @MainActor
    @discardableResult
    private func scrollToTop(reaching element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            app.swipeDown()
        }
        return element.waitForExistence(timeout: 5)
    }

    /// Opens the pickup-place history of the delivery whose row says `text`.
    ///
    /// Every delivery's history button shares one identifier, so the right one
    /// is picked out by the place it names — read off the row's own label —
    /// rather than by an index into a query over the whole screen.
    @MainActor
    private func openPickupHistory(from text: String, in app: XCUIApplication) {
        let row = deliveryRow(containing: text, in: app)
        XCTAssertTrue(scrollTo(row, in: app), "The delivery should be listed")
        let button = pickupHistoryButton(near: row, in: app)
        XCTAssertNotNil(button, "The delivery names a place, so its history is one tap away")
        button?.tap()
    }

    /// The pickup-history button belonging to one delivery, or `nil` when that
    /// delivery is offered none.
    ///
    /// Matched by the accessibility label, which names the place, because every
    /// such button on the screen shares one identifier.
    @MainActor
    private func pickupHistoryButton(near row: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        let place = [Self.noodles, Self.diner].first { row.label.contains("Picked up from \($0)") }
        guard let place else { return nil }
        let button = app.buttons
            .matching(identifier: "shiftDetailPickupHistoryButton")
            .matching(NSPredicate(format: "label CONTAINS %@", place))
            .firstMatch
        return button.exists ? button : nil
    }

    @MainActor
    private func closePickupHistory(in app: XCUIApplication) {
        let done = app.buttons["closePickupPlaceHistoryButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(
            waitForDisappearance(of: app.descendants(matching: .any)["pickupPlaceHistorySummary"]),
            "The sheet closes back to the shift's delivery log"
        )
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
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

    /// Runs one shift with one delivery taken start to finish.
    ///
    /// Also asserts the safety rule the delivery earnings flow depends on:
    /// nothing offers earnings entry for a delivery while the shift is running.
    @MainActor
    private func completeAShiftWithADelivery(in app: XCUIApplication) {
        startShiftAndDelivery(in: app)

        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        for expected in ["Mark arrived at pickup", "Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(waitForLabel(action, toContain: expected), "Showed: \(action.label)")
            XCTAssertFalse(
                app.buttons["shiftDetailDeliveryEarningsButton"].exists,
                "Earnings entry must not be offered while the driver may be driving"
            )
            action.tap()
        }

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(scrollToTop(reaching: endButton, in: app))
        XCTAssertFalse(
            app.buttons["shiftDetailDeliveryEarningsButton"].exists,
            "Not even once the delivery has finished, while the shift is still running"
        )
        endButton.tap()

        XCTAssertTrue(rows(in: app).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func typeDeliveryAmount(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
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
