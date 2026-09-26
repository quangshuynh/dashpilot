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

    /// Must match `LaunchArgument.seededPeriodSummary`, for the same reason.
    private static let seededPeriodSummaryArgument = "-dashpilot-seeded-period-summary"

    /// Must match `LaunchArgument.seededPeriodComparison`, for the same reason.
    private static let seededPeriodComparisonArgument = "-dashpilot-seeded-period-comparison"

    /// Must match `LaunchArgument.seededExpectedPay`, for the same reason.
    private static let seededExpectedPayArgument = "-dashpilot-seeded-expected-pay"

    /// Must match `LaunchArgument.seededParkedHistory`, for the same reason.
    private static let seededParkedHistoryArgument = "-dashpilot-seeded-parked-history"

    /// Must match `LaunchArgument.seededMissedLifecycle`, for the same reason.
    private static let seededMissedLifecycleArgument = "-dashpilot-seeded-missed-lifecycle"

    /// Must match `LaunchArgument.seededStackedOffer`, for the same reason.
    private static let seededStackedOfferArgument = "-dashpilot-seeded-stacked-offer"

    /// Must match `LaunchArgument.seededMalformedOffer`, for the same reason.
    private static let seededMalformedOfferArgument = "-dashpilot-seeded-malformed-offer"

    /// Must match `LaunchArgument.seededPausedHistory`, for the same reason.
    private static let seededPausedHistoryArgument = "-dashpilot-seeded-paused-history"

    /// Must match `LaunchArgument.seededLateEndHistory`, for the same reason.
    private static let seededLateEndHistoryArgument = "-dashpilot-seeded-late-end-history"

    /// Must match `LaunchArgument.seededLateDeliveryHistory`, for the same reason.
    private static let seededLateDeliveryHistoryArgument = "-dashpilot-seeded-late-delivery-history"

    /// Must match `LaunchArgument.seededOlderWeeks`, for the same reason.
    private static let seededOlderWeeksArgument = "-dashpilot-seeded-older-weeks"

    /// Must match `LaunchArgument.seededOlderWeeksOnly`, for the same reason.
    private static let seededOlderWeeksOnlyArgument = "-dashpilot-seeded-older-weeks-only"

    /// About two and a half years of synthetic work; see
    /// `LaunchArgument.seededLongHistory` for its shape.
    private static let seededLongHistoryArgument = "-dashpilot-seeded-long-history"

    /// Must match `LaunchArgument.stubbedLocation`, for the same reason.
    private static let stubbedLocationArgument = "-dashpilot-stubbed-location"

    /// Must match `LaunchArgument.simulatedRoute`, for the same reason.
    private static let simulatedRouteArgument = "-dashpilot-simulated-route"

    /// The largest accessibility text size iOS offers, as UIKit names it.
    private static let accessibilityXXXLTextSize = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches `app` in the orientation every journey in this file is written
    /// for.
    ///
    /// Nothing here tests landscape, and nothing here set an orientation before:
    /// a run therefore inherited whatever the simulator was last left in, and a
    /// device left rotated changes what a `List` renders. A row a journey
    /// scrolls to then never becomes hittable, and the red run reads as a broken
    /// screen rather than as a rotated device. Setting it explicitly is what
    /// makes a run depend on the app rather than on a simulator's remembered
    /// state, for the reason the schemes are committed rather than autocreated.
    @MainActor
    private func launchInPortrait(_ app: XCUIApplication) {
        if XCUIDevice.shared.orientation != .portrait {
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()
    }

    /// Keeps a screenshot of the whole screen in the result bundle, for review.
    ///
    /// Not an assertion and not a snapshot comparison: it is the record a
    /// reviewer reads with `xcresulttool export attachments`, so a layout change
    /// can be looked at without re-running the journey by hand.
    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Launches against an empty throwaway store at a given text size.
    @MainActor
    private func launchWithEmptyStore(textSize: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store so the journey starts from a known
    /// empty state and never writes into a real driver's shift history.
    @MainActor
    private func launchWithEmptyStore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        launchInPortrait(app)
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
        launchInPortrait(app)
        return app
    }

    /// The same fixture, opened at a chosen preferred text size.
    ///
    /// `-UIPreferredContentSizeCategoryName` is UIKit's own launch override, so
    /// the app under test reads the size a driver would have set in Settings
    /// without the journey touching the simulator's own state, and the launch
    /// after it is an ordinary one again.
    @MainActor
    private func launchWithSeededHistory(atTextSize category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededHistoryArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        launchInPortrait(app)
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
        launchInPortrait(app)
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
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding a running shift with two
    /// deliveries waiting at their pickups, one of them carrying an expected
    /// amount and the other carrying none.
    ///
    /// An expectation can only be entered while a delivery is in progress, so
    /// none of the completed-shift fixtures can reach one. Two deliveries left
    /// at the same lifecycle point, differing only in the amount, is what lets
    /// the journeys attribute a difference in what the app does to the amount
    /// and to nothing else.
    ///
    /// The fixture's shift holds `Delivery 1` waiting at its pickup with an
    /// expected `$8.50`, and `Delivery 2` waiting at its pickup with no expected
    /// amount. Neither carries a recorded gross amount, and neither can: a
    /// running delivery is refused one.
    @MainActor
    private func launchWithExpectedPay() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededExpectedPayArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding one offer of two deliveries
    /// and a later add-on offer of one.
    ///
    /// Recording an offer of two is a single write, so what a journey has to
    /// judge is the screen afterwards: which cards carry a heading and which
    /// carry none. Two offers in the fixture is what makes that a real
    /// distinction rather than a property of the panel.
    ///
    /// The fixture's shift holds `Delivery 1` waiting at its pickup and
    /// `Delivery 2` accepted, both from the first offer, and `Delivery 3`
    /// accepted on its own twenty minutes later.
    @MainActor
    private func launchWithStackedOffer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededStackedOfferArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding one completed shift with a
    /// stretch recorded parked between its two capture sessions.
    ///
    /// 4.5 mi over two segments, 25 minutes parked, and a working duration of
    /// the whole two hours. A journey cannot produce this shape: a simulator
    /// cannot be driven into recording a route, and a live journey that parks
    /// and resumes records a stretch measured in seconds.
    @MainActor
    private func launchWithParkedHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededParkedHistoryArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding a running shift whose
    /// deliveries have recorded nothing for well over half an hour.
    ///
    /// A progress reminder's whole input is elapsed time, and a journey cannot
    /// wait half an hour for one. The fixture's shift holds `Delivery 1` waiting
    /// at its pickup since 70 minutes ago, `Delivery 2` accepted 55 minutes ago
    /// with no arrival, and `Delivery 3` picked up 40 minutes ago, which is the
    /// delivery nothing is ever offered for.
    @MainActor
    private func launchWithMissedLifecycle() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededMissedLifecycleArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding one offer of two deliveries
    /// and an offer holding none.
    ///
    /// The empty offer is a row the app cannot produce. It is seeded so a
    /// journey can prove the correction screen reads a store holding one rather
    /// than falling over on it.
    @MainActor
    private func launchWithMalformedOffer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededMalformedOfferArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding one **completed** shift that
    /// was paused twice.
    ///
    /// A journey cannot produce this state by tapping: it would have to pause a
    /// live shift, wait a measurable number of minutes and end it, which
    /// measures the clock rather than the screen.
    ///
    /// The fixture's shift runs four hours. It is paused from one hour in for 30
    /// minutes (`Pause 1`) and from two hours forty-five minutes in for 20
    /// minutes (`Pause 2`), and records one delivery from two hours in to two
    /// hours thirty. So its elapsed time is `4 hr`, its paused time `50 min` and
    /// its working time `3 hr 10 min`, and `Pause 2` begins a quarter of an hour
    /// after the delivery ends.
    @MainActor
    private func launchWithPausedHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPausedHistoryArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding one **completed** shift whose
    /// recorded end is twenty minutes later than the driver actually stopped.
    ///
    /// A journey cannot produce this state by tapping: ending a shift records
    /// the clock, and a UI test cannot drive a simulator into recording a route.
    ///
    /// The fixture's shift runs from its start to `3 hr 40 min` in, and its
    /// route is three capture sessions of ten positions each, beginning 30
    /// minutes, 3 hours 5 minutes and 3 hours 25 minutes in. It records one
    /// delivery from `3 hr 5 min` to `3 hr 10 min`, and an invented `$100.00`.
    /// So it opens showing `3 hr 40 min` elapsed, `6.7 mi` recorded over three
    /// segments, and `$27.27` per shift hour; correcting the end to `3 hr 20
    /// min` removes the third session and leaves `3 hr 20 min`, `4.5 mi` and
    /// exactly `$30.00`.
    @MainActor
    private func launchWithLateEndHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededLateEndHistoryArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store holding the **real recovery case**: a
    /// completed shift whose one delivery recorded its completion long after the
    /// order was handed over, and whose own end is late as well.
    ///
    /// A journey cannot produce this state by tapping: recording a completion
    /// records the clock.
    ///
    /// The shift, its route and its `$100.00` are the late-end fixture's, so it
    /// opens showing `3 hr 40 min`, `6.7 mi` over three segments and `$27.27`
    /// per shift hour, and correcting the end to `3 hr 20 min` leaves
    /// `3 hr 20 min`, `4.5 mi` over two segments and exactly `$30.00`. What
    /// differs is `Delivery 1`: accepted `2 hr 00 min` in, at the pickup at
    /// `2 hr 05 min`, collected at `2 hr 10 min`, recorded as delivered at
    /// `3 hr 30 min`, and carrying `$12.00`. So it reads `1 hr 30 min` accepted
    /// to delivered and `$8.00` per recorded delivery hour until the completion
    /// is corrected to `3 hr 15 min`, which makes those `1 hr 15 min` and
    /// `$9.60`.
    @MainActor
    private func launchWithLateDeliveryHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededLateDeliveryHistoryArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store with Core Location stubbed as granted.
    ///
    /// A simulator cannot be told to grant location from a journey, so the
    /// running shift's status line would otherwise only ever be reachable in its
    /// "permission required" state. The stub reports When In Use and produces no
    /// positions; everything else, including the scene phase and what the app
    /// does about it, is real.
    @MainActor
    private func launchWithStubbedLocation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        app.launchArguments.append(Self.stubbedLocationArgument)
        launchInPortrait(app)
        return app
    }

    /// Launches against a throwaway store with a synthetic vehicle feeding the
    /// real capture pipeline.
    ///
    /// The only way a journey can watch a live mileage figure move. Permission,
    /// the filter, the capture sessions, the store writes and the measurement
    /// are all the shipping ones; only the source of the positions is synthetic.
    /// The vehicle keeps moving while capture is stopped, which is what makes
    /// the distance covered during a pause a real thing that must not be
    /// recorded.
    @MainActor
    private func launchWithSimulatedRoute() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        app.launchArguments.append(Self.simulatedRouteArgument)
        launchInPortrait(app)
        return app
    }

    /// The recorded mileage the running shift's panel is showing, in miles, or
    /// `nil` when it is not showing a measured one.
    ///
    /// Read from the spoken value rather than the visible one because that is
    /// where the unit is a word: `"1.2 miles recorded. 1 capture segment…"`. A
    /// panel saying "No route recorded" has no figure, and answers `nil` rather
    /// than zero — the distinction this whole screen exists to keep.
    @MainActor
    private func recordedMiles(in app: XCUIApplication) -> Double? {
        let element = app.descendants(matching: .any)["liveRecordedMileage"]
        guard element.exists, let spoken = element.value as? String else { return nil }
        guard let unit = spoken.range(of: " mile") else { return nil }
        // The digits immediately before the unit, back to whatever is not part
        // of a number. Written without a regex literal so the test target does
        // not depend on the bare-slash syntax being enabled.
        let digits = spoken[spoken.startIndex..<unit.lowerBound]
            .reversed()
            .prefix { $0.isNumber || $0 == "." || $0 == "," }
        return Double(String(digits.reversed()).replacingOccurrences(of: ",", with: ""))
    }

    /// Waits until the panel is showing a measured mileage, and answers it.
    @MainActor
    private func waitForRecordedMiles(in app: XCUIApplication, timeout: TimeInterval = 30) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let miles = recordedMiles(in: app), miles > 0 { return miles }
            _ = app.descendants(matching: .any)["liveRecordedMileage"].waitForExistence(timeout: 0.5)
        }
        return recordedMiles(in: app)
    }

    /// The app launches into the shift screen rather than the persistence failure state.
    @MainActor
    func testLaunchesIntoShiftScreen() throws {
        let app = XCUIApplication()
        launchInPortrait(app)

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
        XCTAssertTrue(app.descendants(matching: .any)["workingTime"].exists)
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
            scrollUntilHittable(rows(in: app).firstMatch, in: app),
            "The finished shift should appear in history"
        )
    }

    // MARK: Home

    /// Before a shift, the panel says what starting now would record, and the
    /// control that starts it is on the first screen.
    @MainActor
    func testPreShiftHomeLeadsWithWhatTheNextShiftRecords() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        setCurrentGasPrice("3.29", in: app)
        goBack(in: app)

        let vehicle = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(vehicle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabelValue(vehicle, toEqual: "2020 Honda Civic, 34 miles per gallon, gas $3.29 per gallon"),
            "Showed: \(String(describing: vehicle.value))"
        )
        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(start.isHittable, "Start Shift is on the first screen, not below the fold")
        XCTAssertLessThan(vehicle.frame.minY, start.frame.minY, "What will be recorded comes before the control")
        attachScreenshot("home-pre-shift")
    }

    /// With nothing selected the panel says so and still starts a shift.
    @MainActor
    func testPreShiftHomeWithNoVehicleNeverBlocksTheStart() throws {
        let app = launchWithEmptyStore()

        let vehicle = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(vehicle.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabelValue(vehicle, toEqual: "No vehicle selected for the next shift"))
        XCTAssertFalse(vehicle.label.contains("0 MPG") || vehicle.label.contains("$0.00"))

        app.buttons["startShiftButton"].tap()
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 5), "Nothing blocks the start")
    }

    /// The running shift reads top to bottom: its state, the working clock,
    /// the figures, the vehicle, then the controls.
    @MainActor
    func testActiveShiftHomeLeadsWithStateThenTheWorkingClock() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        let status = app.descendants(matching: .any)["activeShiftStatus"]
        let working = app.descendants(matching: .any)["workingTime"]
        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        let counts = app.descendants(matching: .any)["liveDeliveryCounts"]
        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        for element in [status, working, mileage, counts, vehicle] {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is on the panel")
        }

        XCTAssertLessThan(status.frame.minY, working.frame.minY)
        XCTAssertLessThan(working.frame.minY, mileage.frame.minY)
        XCTAssertLessThan(mileage.frame.minY, vehicle.frame.minY, "Context comes after the figures")
        XCTAssertGreaterThan(working.frame.height, mileage.frame.height / 2, "The clock is the largest figure")

        XCTAssertEqual(mileage.label, "Recorded mileage")
        XCTAssertEqual(counts.label, "Deliveries")
        XCTAssertTrue(
            (counts.value as? String)?.contains("No delivery in progress") == true,
            "The counts speak the shift's own sentence: \(String(describing: counts.value))"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["liveRecordedGross"].exists,
            "No earnings figure is invented for a shift that cannot record one yet"
        )
        attachScreenshot("home-active-no-deliveries")
    }

    /// Parked and paused are two different states, told apart by more than
    /// colour, and a parked shift still says it is running.
    @MainActor
    func testParkedAndPausedAreDistinctStates() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        let park = app.buttons["parkShiftButton"]
        XCTAssertTrue(scrollUntilHittable(park, in: app))
        park.tap()

        let parked = app.descendants(matching: .any)["parkedShiftNotice"]
        XCTAssertTrue(parked.waitForExistence(timeout: 5))
        XCTAssertTrue(parked.label.contains("Parked") && parked.label.contains("still running"), "Showed: \(parked.label)")
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists, "A parked shift is still running")
        XCTAssertFalse(app.descendants(matching: .any)["pausedShiftStatus"].exists, "Parked is not paused")
        attachScreenshot("home-parked")

        let resumeDriving = app.buttons["resumeDrivingButton"]
        XCTAssertTrue(scrollUntilHittable(resumeDriving, in: app))
        resumeDriving.tap()

        let pause = app.buttons["pauseShiftButton"]
        XCTAssertTrue(scrollUntilHittable(pause, in: app))
        pause.tap()

        XCTAssertTrue(app.descendants(matching: .any)["pausedShiftStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["parkedShiftNotice"].exists, "Paused is not parked")
        XCTAssertFalse(app.buttons["parkShiftButton"].exists, "Parking is withheld while paused")
        let working = app.descendants(matching: .any)["workingTime"]
        XCTAssertEqual(working.label, "Working time, paused")
        attachScreenshot("home-paused")
    }

    /// At the largest accessibility size the panel stacks rather than
    /// squeezing, and every control is still reachable and whole.
    @MainActor
    func testActiveShiftHomeAtTheLargestTextSize() throws {
        let app = launchWithEmptyStore(textSize: Self.accessibilityXXXLTextSize)

        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(scrollUntilHittable(start, in: app, maxSwipes: 10))
        attachScreenshot("home-pre-shift-xxxl")
        start.tap()

        let working = app.descendants(matching: .any)["workingTime"]
        XCTAssertTrue(working.waitForExistence(timeout: 5))
        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app, maxSwipes: 10))
        let counts = app.descendants(matching: .any)["liveDeliveryCounts"]
        XCTAssertTrue(scrollTo(counts, in: app, maxSwipes: 10))
        XCTAssertGreaterThanOrEqual(counts.frame.minY, mileage.frame.maxY - 1, "The figures stack rather than share a row")
        attachScreenshot("home-active-xxxl")

        for identifier in ["pauseShiftButton", "endShiftButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(scrollUntilHittable(button, in: app, maxSwipes: 15), "\(identifier) is reachable")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    // MARK: Active delivery cards

    /// The card of one delivery in progress, found by the name it leads with.
    @MainActor
    private func deliveryCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "activeDeliveryStatus", title)
        ).firstMatch
    }

    /// One delivery's card says which delivery, what state and for how long,
    /// then puts the next step above everything else that can be done to it.
    @MainActor
    func testADeliveryCardLeadsWithItsStateThenItsNextStep() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()
        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollUntilHittable(startDelivery, in: app))
        startDelivery.tap()

        let card = deliveryCard("Delivery 1", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Next step, mark arrived at pickup"), "Showed: \(card.label)")
        XCTAssertTrue(
            card.label.contains("In this state for"),
            "The time at this step is said, from the recorded acceptance: \(card.label)"
        )

        let action = app.buttons["deliveryActionButton"]
        let cancel = app.buttons["cancelDeliveryButton"]
        XCTAssertTrue(scrollUntilHittable(cancel, in: app))
        XCTAssertLessThan(card.frame.minY, action.frame.minY)
        XCTAssertLessThan(action.frame.minY, cancel.frame.minY, "Cancelling sits below the step, not beside it")
        XCTAssertGreaterThan(action.frame.height, cancel.frame.height - 1, "The step is the dominant control")
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44, "A quiet control is still a full-size target")
        XCTAssertTrue(action.label.contains("Delivery 1"), "The step names its delivery: \(action.label)")
        attachScreenshot("home-one-delivery")
    }

    /// Two deliveries in different states read as two deliveries: each card
    /// leads with its own name, its own state and its own step.
    @MainActor
    func testStackedDeliveriesInDifferentStatesStayDistinct() throws {
        let app = launchWithActiveDelivery()

        let second = deliveryCard("Delivery 2", in: app)
        let third = deliveryCard("Delivery 3", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(scrollTo(third, in: app))

        XCTAssertTrue(second.label.contains("Next step, mark arrived at pickup"), "Showed: \(second.label)")
        XCTAssertTrue(third.label.contains("Next step, mark delivery completed"), "Showed: \(third.label)")
        XCTAssertTrue(second.label.contains("In this state for 25 minutes"), "Its own clock: \(second.label)")
        XCTAssertTrue(third.label.contains("In this state for 4 minutes"), "And this one its own: \(third.label)")

        let actions = app.buttons.matching(identifier: "deliveryActionButton")
        let labels = actions.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("Delivery 2") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Delivery 3") }, "\(labels)")
        attachScreenshot("home-two-stacked-deliveries")
    }

    /// The reminder still says it is a suggestion from the driver's own times,
    /// in the new card as in the old.
    @MainActor
    func testTheRestyledReminderStillClaimsNoObservation() throws {
        let app = launchWithMissedLifecycle()

        let reminder = app.descendants(matching: .any).matching(identifier: "deliverySuggestion").firstMatch
        XCTAssertTrue(scrollTo(reminder, in: app))
        XCTAssertTrue(reminder.label.contains("DashPilot cannot tell where you are"), "Showed: \(reminder.label)")
        XCTAssertTrue(reminder.label.contains("not something it observed"), "Showed: \(reminder.label)")
        let confirm = app.buttons.matching(identifier: "deliverySuggestionActionButton").firstMatch
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        attachScreenshot("home-reminder")
    }

    /// At the largest accessibility size a card grows downwards: the name and
    /// state are whole, and the step and cancelling are both still full-size.
    @MainActor
    func testADeliveryCardAtTheLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededActiveDeliveryArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.accessibilityXXXLTextSize]
        launchInPortrait(app)

        let card = deliveryCard("Delivery 2", in: app)
        XCTAssertTrue(scrollTo(card, in: app, maxSwipes: 25))
        XCTAssertTrue(card.label.contains("Next step"), "Showed: \(card.label)")

        let action = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "deliveryActionButton", "Delivery 2")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(action, in: app, maxSwipes: 25))
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        attachScreenshot("home-delivery-xxxl")

        let cancel = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "cancelDeliveryButton", "Delivery 2")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(cancel, in: app, maxSwipes: 25))
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
    }

    /// Pause a running shift, see the screen say so, and resume it.
    ///
    /// The three states a shift can be in have to be distinguishable without
    /// reading, so what is asserted is that the panel actually swaps: the
    /// running label and the Pause control give way to the paused label and the
    /// Resume control, and back again.
    @MainActor
    func testPausesAndResumesAShift() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["pauseShiftButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertFalse(app.buttons["resumeShiftButton"].exists)

        pauseButton.tap()

        let resumeButton = app.buttons["resumeShiftButton"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["pausedShiftStatus"].waitForExistence(timeout: 5),
            "A paused shift says it is paused rather than looking like a running one"
        )
        XCTAssertFalse(pauseButton.exists)
        // The working figure stays on screen: a driver on a break still needs to
        // see how long they have worked.
        XCTAssertTrue(app.descendants(matching: .any)["workingTime"].exists)
        // And the shift can still be ended from here, without resuming first.
        XCTAssertTrue(app.buttons["endShiftButton"].exists)

        resumeButton.tap()

        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertFalse(resumeButton.exists)
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
    }

    /// A paused shift explains what stopped, rather than leaving the driver to
    /// find the break in the route afterwards.
    @MainActor
    func testAPausedShiftSaysRecordingHasStopped() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["pauseShiftButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        pauseButton.tap()

        XCTAssertTrue(app.buttons["resumeShiftButton"].waitForExistence(timeout: 5))

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(
            status.label.lowercased().contains("paused")
                || status.label.lowercased().contains("stopped"),
            "The capture line says recording stopped, not that something failed: \(status.label)"
        )

        // Deliveries are not offered while paused, because a delivery started
        // then would be time the app is simultaneously reporting as not worked.
        XCTAssertTrue(
            app.descendants(matching: .any)["pausedDeliveryNotice"].waitForExistence(timeout: 5)
        )
    }

    /// Pausing and resuming does not end the shift, and the finished shift
    /// reports the time it was worked rather than the time it covered.
    @MainActor
    func testAPausedShiftIsStillTheShiftInProgress() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        app.buttons["pauseShiftButton"].tap()
        XCTAssertTrue(app.buttons["resumeShiftButton"].waitForExistence(timeout: 5))

        // Still the shift in progress: no new shift may be started over it, and
        // nothing has appeared in history.
        XCTAssertFalse(startButton.exists, "A paused shift is still the shift in progress")
        XCTAssertEqual(rows(in: app).count, 0)

        app.buttons["resumeShiftButton"].tap()
        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 5))

        app.buttons["endShiftButton"].tap()

        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollUntilHittable(rows(in: app).firstMatch, in: app),
            "The shift that was paused still finishes as one shift in history"
        )
    }

    // MARK: Live shift figures

    /// The running shift reports the miles its route has actually recorded, and
    /// the figure grows while positions are being accepted.
    ///
    /// The whole point of the panel: a driver mid-shift can see what has been
    /// recorded so far without ending the shift to find out. The word "recorded"
    /// is asserted with the figure, because a mileage read as "miles I drove" is
    /// the one claim this app must not make.
    @MainActor
    func testRecordedMileageGrowsWhileAShiftIsRecording() throws {
        let app = launchWithSimulatedRoute()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 10))

        let first = try XCTUnwrap(
            waitForRecordedMiles(in: app),
            "The panel never reported a measured distance while the route was being recorded"
        )
        XCTAssertGreaterThan(first, 0)

        // Long enough for the synthetic vehicle to cover well over a tenth of a
        // mile, which is the resolution the figure is written at.
        let deadline = Date().addingTimeInterval(30)
        var grown: Double?
        while Date() < deadline, grown == nil {
            if let miles = recordedMiles(in: app), miles > first { grown = miles }
            _ = mileage.waitForExistence(timeout: 0.5)
        }
        XCTAssertNotNil(grown, "Recorded mileage did not grow while the route was being recorded")

        let spoken = try XCTUnwrap(mileage.value as? String)
        XCTAssertTrue(spoken.contains("recorded"), "The figure has to say what it is: \(spoken)")
        XCTAssertFalse(spoken.lowercased().contains("total"), "Recorded mileage is not a total: \(spoken)")
    }

    /// Pausing stops the mileage and the working figure, and neither moves again
    /// until the driver resumes.
    ///
    /// Both are the same claim from two directions: a driver on a break is not
    /// working and is not recording, so a shift that kept either number moving
    /// would be reporting work that did not happen.
    @MainActor
    func testRecordedMileageAndWorkingTimeFreezeWhilePaused() throws {
        let app = launchWithSimulatedRoute()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let beforePause = try XCTUnwrap(waitForRecordedMiles(in: app))

        let pauseButton = app.buttons["pauseShiftButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))
        pauseButton.tap()
        XCTAssertTrue(app.buttons["resumeShiftButton"].waitForExistence(timeout: 10))

        // Read after the pause has settled: pausing flushes the positions
        // captured up to the tap, so the figure may move once more and then stop.
        let workingTime = app.descendants(matching: .any)["workingTime"]
        XCTAssertTrue(workingTime.waitForExistence(timeout: 5))
        _ = workingTime.waitForExistence(timeout: 3)

        let pausedMiles = try XCTUnwrap(recordedMiles(in: app))
        let pausedWorking = try XCTUnwrap(workingTime.value as? String)
        XCTAssertGreaterThanOrEqual(pausedMiles, beforePause)

        // Fifteen seconds during which the synthetic vehicle keeps driving. A
        // shift that measured it would be several tenths of a mile further on,
        // and a working figure that kept ticking would be fifteen seconds later.
        let waited = expectation(description: "the shift stays paused")
        waited.isInverted = true
        wait(for: [waited], timeout: 15)

        XCTAssertEqual(
            recordedMiles(in: app),
            pausedMiles,
            "Recorded mileage must not move while the shift is paused"
        )
        XCTAssertEqual(
            workingTime.value as? String,
            pausedWorking,
            "Working time must not move while the shift is paused"
        )
        // And the shift is still paused rather than having resumed by itself.
        XCTAssertTrue(app.buttons["resumeShiftButton"].exists)
    }

    /// Resuming does not add the distance covered during the break, and the
    /// route says it is partial.
    ///
    /// The synthetic vehicle keeps driving while capture is stopped, exactly as
    /// a driver who takes a break somewhere and resumes somewhere else does.
    /// Resuming mints a new capture session, so the stretch between the two is
    /// a gap and the distance across it is left out rather than guessed at.
    @MainActor
    func testResumingDoesNotRecordTheDistanceCoveredWhilePaused() throws {
        let app = launchWithSimulatedRoute()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        _ = try XCTUnwrap(waitForRecordedMiles(in: app))

        app.buttons["pauseShiftButton"].tap()
        let resumeButton = app.buttons["resumeShiftButton"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 10))

        let settling = expectation(description: "the pause settles")
        settling.isInverted = true
        wait(for: [settling], timeout: 3)
        let pausedMiles = try XCTUnwrap(recordedMiles(in: app))

        // Twenty seconds of driving nobody recorded: around half a kilometre,
        // which is several times what the first seconds after resuming add.
        let break_ = expectation(description: "the driver takes a break")
        break_.isInverted = true
        wait(for: [break_], timeout: 20)

        resumeButton.tap()
        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 10))

        // Wait for the first reading that shows the route growing again, and
        // check what it added. Bridging the break would have added the whole
        // half kilometre at once.
        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        let deadline = Date().addingTimeInterval(30)
        var afterResume: Double?
        while Date() < deadline, afterResume == nil {
            if let miles = recordedMiles(in: app), miles > pausedMiles { afterResume = miles }
            _ = mileage.waitForExistence(timeout: 0.3)
        }

        let resumedMiles = try XCTUnwrap(afterResume, "Recording did not restart after the shift was resumed")
        XCTAssertLessThan(
            resumedMiles - pausedMiles,
            0.25,
            """
            Resuming added \(resumedMiles - pausedMiles) mi at once.             The distance covered while the shift was paused was not recorded and must not be measured.
            """
        )

        let spoken = try XCTUnwrap(mileage.value as? String)
        XCTAssertTrue(
            spoken.contains("Partial route") || spoken.contains("partial route"),
            "A route with a break in it says so while the shift is still running: \(spoken)"
        )
    }

    /// A shift recording nothing says there is no route, rather than showing no
    /// miles.
    ///
    /// The stubbed provider grants permission and produces no positions, which
    /// is the shape of a shift whose capture has not produced a usable fix yet.
    /// "No route recorded" and "0.0 mi" are different statements and the panel
    /// must make the first one.
    @MainActor
    func testARunningShiftWithNoRouteSaysSoRatherThanShowingNoMiles() throws {
        let app = launchWithStubbedLocation()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 10))

        let spoken = try XCTUnwrap(mileage.value as? String)
        XCTAssertTrue(spoken.contains("No route recorded"), "Expected an absent route, read: \(spoken)")
        XCTAssertFalse(spoken.contains("0.0"), "An absent route is not a distance of zero: \(spoken)")
        XCTAssertNil(recordedMiles(in: app))
    }

    /// A running shift shows no earnings and no rates, and says why.
    ///
    /// Shift gross earnings cannot be recorded until the shift has finished, so
    /// every rate derived from them is withheld. The panel states the reason
    /// once rather than showing a dash, a zero, or a figure worked out from the
    /// amounts recorded against individual deliveries.
    @MainActor
    func testARunningShiftShowsNoEarningsOrRates() throws {
        let app = launchWithSimulatedRoute()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let notice = app.descendants(matching: .any)["liveRateNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(
            notice.label.contains("still running"),
            "The reason has to name the shift's state, not imply a missing amount: \(notice.label)"
        )

        XCTAssertFalse(
            app.descendants(matching: .any)["liveRecordedGross"].exists,
            "A running shift cannot carry an amount, so none may be shown"
        )

        // Nothing on the running panel may read as money. A currency symbol here
        // would be a figure the shift does not have.
        let deliveries = app.descendants(matching: .any)["liveDeliveryCounts"]
        XCTAssertTrue(deliveries.waitForExistence(timeout: 5))
        for element in [notice, deliveries, app.descendants(matching: .any)["liveRecordedMileage"]] {
            let text = element.label + ((element.value as? String) ?? "")
            XCTAssertFalse(text.contains("$"), "A running shift states no amount: \(text)")
            XCTAssertFalse(text.contains("/hr"), "A running shift derives no rate: \(text)")
        }
    }

    /// The running shift counts the deliveries that are open and the ones it has
    /// finished, and the counts follow what the driver actually records.
    @MainActor
    func testTheRunningShiftCountsItsDeliveries() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let counts = app.descendants(matching: .any)["liveDeliveryCounts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        XCTAssertEqual(counts.label, "Deliveries")
        XCTAssertEqual(counts.value as? String, "No delivery in progress")

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(startDelivery.waitForExistence(timeout: 5))
        startDelivery.tap()

        let settling = expectation(description: "the count follows the record")
        settling.isInverted = true
        wait(for: [settling], timeout: 2)

        XCTAssertEqual(counts.value as? String, "1 delivery in progress")
    }

    // MARK: History weeks

    /// Launches against a throwaway store holding completed shifts in three
    /// different weeks.
    ///
    /// History is scoped to the current Monday-to-Sunday week, and no journey
    /// can tap its way to a shift dated last month: ending a shift records the
    /// clock. The fixture holds, by the rules of the driver's own calendar:
    ///
    /// - **this week, Tuesday**: three hours paying `$70.00`
    /// - **last week, Wednesday**: four hours paying `$55.00`
    /// - **three weeks ago**: two shifts, paying `$41.00` and `$33.00`
    ///
    /// The gap between last week and three weeks ago is the point of the shape:
    /// a week nobody worked must not appear as an empty group, and two shifts in
    /// one week must appear under one heading.
    ///
    /// - Parameter includingCurrentWeek: `false` launches the same store without
    ///   its current-week shift, which is the empty-current-week state.
    @MainActor
    private func launchWithOlderWeeks(includingCurrentWeek: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(
            includingCurrentWeek ? Self.seededOlderWeeksArgument : Self.seededOlderWeeksOnlyArgument
        )
        launchInPortrait(app)
        return app
    }

    /// Launches the long-history fixture, optionally at a given text size.
    @MainActor
    private func launchWithLongHistory(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededLongHistoryArgument)
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        launchInPortrait(app)
        return app
    }

    /// Opens Older Weeks from the root screen.
    @MainActor
    private func openOlderWeeks(in app: XCUIApplication, maxSwipes: Int = 12) {
        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: maxSwipes), "View Older Weeks is reachable")
        older.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
                .waitForExistence(timeout: 10)
        )
    }

    /// Everything on screen whose label contains `text`.
    ///
    /// Used for the negative claims below. A `List` renders only the rows near
    /// the viewport, so this is asserted after scrolling the whole section into
    /// reach rather than on a fresh launch, and the positives beside it are what
    /// show the query itself works.
    @MainActor
    private func elements(containing text: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    @MainActor
    private func olderWeekRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "olderWeekShiftRow")
    }

    /// History lists the week the driver is in, and says which week that is.
    @MainActor
    func testHistoryShowsThisWeekOnly() throws {
        let app = launchWithOlderWeeks()

        let history = rows(in: app)
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app), "This week's shift is listed")
        XCTAssertTrue(
            waitForCount(history, toEqual: 1),
            "Only the current week's shift is listed, not the fixture's four"
        )
        XCTAssertTrue(
            waitForLabel(history.firstMatch, toContain: "$70.00"),
            "And it is this week's shift: \(history.firstMatch.label)"
        )

        let header = app.descendants(matching: .any)["historyHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(
            header.label.contains("This Week"),
            "The heading says what the list is scoped to: \(header.label)"
        )

        // The older shifts are absent from this screen rather than merely
        // further down it: the section is scrolled to its end first, so an
        // unrendered row cannot pass for a hidden one.
        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app), "The older-weeks control is reachable")
        XCTAssertEqual(elements(containing: "$55.00", in: app).count, 0, "Last week's shift is not in this list")
        XCTAssertEqual(elements(containing: "$41.00", in: app).count, 0)
        XCTAssertEqual(elements(containing: "$33.00", in: app).count, 0)

        // Two weeks, three shifts: the fixture's two older weeks, one holding a
        // single shift and one holding two.
        // The week count is worked out off the main actor, so it is waited for
        // rather than read the instant the row appears.
        XCTAssertTrue(
            waitForLabel(older, toContain: "2 weeks · 3 shifts"),
            "The control says how much is behind it: \(older.label)"
        )
    }

    /// The older work is one tap away, grouped by the week it was done in.
    @MainActor
    func testOlderWeeksAreGroupedAndReachable() throws {
        let app = launchWithOlderWeeks()

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 12))
        older.tap()

        let rows = olderWeekRows(in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))

        // Newest week first, so last week's shift leads.
        XCTAssertTrue(
            waitForLabel(rows.element(boundBy: 0), toContain: "$55.00"),
            "The newest older week is first: \(rows.element(boundBy: 0).label)"
        )

        // Every shift outside this week is here. Each week opens with its own
        // summary, so the three rows do not all fit one screen: each is scrolled
        // to in the order the list holds them, newest first, and the headings
        // passed on the way are collected rather than counted on one screen.
        let headings = app.descendants(matching: .any).matching(identifier: "olderWeekHeader")
        var headingLabels = Set<String>()
        for amount in ["$55.00", "$33.00", "$41.00"] {
            let row = rows.matching(NSPredicate(format: "label CONTAINS %@", amount)).firstMatch
            XCTAssertTrue(scrollUntilHittable(row, in: app), "The \(amount) shift is listed")
            for heading in headings.allElementsBoundByIndex where heading.exists {
                headingLabels.insert(heading.label)
            }
        }
        XCTAssertEqual(headingLabels.count, 2, "Two weeks hold shifts, and the empty weeks between them do not")
        XCTAssertFalse(headingLabels.contains(""), "A week names the days it covers")

        // This week's shift stayed on the screen it belongs to.
        XCTAssertEqual(elements(containing: "$70.00", in: app).count, 0)
    }

    /// An older shift is a shift, not a summary: it opens the same detail screen
    /// the current week's rows open, with its own recorded amount.
    @MainActor
    func testAnOlderShiftOpensItsOwnDetail() throws {
        let app = launchWithOlderWeeks()

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 12))
        older.tap()

        let rows = olderWeekRows(in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        rows.firstMatch.tap()

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5), "The same detail screen opens")
        XCTAssertTrue(
            earnings.label.contains("$55.00"),
            "And it is the tapped shift's own amount: \(earnings.label)"
        )
    }

    /// Each older week says how the whole week went before the driver opens
    /// anything in it.
    @MainActor
    func testOlderWeeksAreSummarisedBeforeTheirShifts() throws {
        let app = launchWithOlderWeeks()

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 12))
        older.tap()

        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 10), "A week says how it went")
        XCTAssertTrue(waitForCount(summaries, toEqual: 2), "One summary per week that holds shifts")

        // The newest older week holds one shift, for $55.00.
        let lastWeek = summaries.element(boundBy: 0)
        XCTAssertTrue(
            waitForLabel(lastWeek, toContain: "1 completed shift"),
            "The week says how many shifts it holds: \(lastWeek.label)"
        )
        XCTAssertTrue(
            lastWeek.label.contains("$55.00"),
            "And what they came to, using the recorded amount: \(lastWeek.label)"
        )

        // It is above the shifts rather than under them: the first summary
        // appears before the first row on screen.
        let firstRow = olderWeekRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            lastWeek.frame.minY,
            firstRow.frame.minY,
            "The week's own figures come before the shifts they are a summary of"
        )

        // And the shifts are still shifts: tapping one opens its own detail.
        firstRow.tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("$55.00"), "Showed: \(earnings.label)")
    }

    /// A week holding two shifts totals both, and the total is the week's rather
    /// than either shift's.
    @MainActor
    func testAWeekOfSeveralShiftsIsTotalled() throws {
        let app = launchWithOlderWeeks()

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 12))
        older.tap()

        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForCount(summaries, toEqual: 2))

        // The older of the two weeks holds the fixture's $41.00 and $33.00.
        let threeWeeksAgo = summaries.element(boundBy: 1)
        XCTAssertTrue(scrollTo(threeWeeksAgo, in: app))
        XCTAssertTrue(
            waitForLabel(threeWeeksAgo, toContain: "2 completed shifts"),
            "Showed: \(threeWeeksAgo.label)"
        )
        XCTAssertTrue(
            threeWeeksAgo.label.contains("$74.00"),
            "Two shifts are added up rather than listed: \(threeWeeksAgo.label)"
        )
        XCTAssertFalse(threeWeeksAgo.label.contains("$41.00"), "The week states its total, not its parts")

        // The week the driver is in is not on this screen at all, summary or
        // otherwise.
        XCTAssertEqual(elements(containing: "$70.00", in: app).count, 0)
    }

    /// The summary speaks every unit and every coverage, because a listener has
    /// no caption in view to read afterwards.
    @MainActor
    func testTheWeeklySummarySpeaksItsUnitsAndCoverage() throws {
        let app = launchWithOlderWeeks()

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 12))
        older.tap()

        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

        for expected in ["completed shift", "Recorded gross earnings", "working time"] {
            XCTAssertTrue(
                waitForLabel(summary, toContain: expected),
                "The week is one spoken sentence and says \(expected): \(summary.label)"
            )
        }
        XCTAssertTrue(
            summary.label.contains("across 1 of 1 completed shift"),
            "Every aggregate ends with what is behind it: \(summary.label)"
        )

        // The fixture's older shifts have no route, which is the more valuable
        // claim: a week nothing was measured in says so rather than reporting
        // no miles driven.
        XCTAssertTrue(
            summary.label.contains("No recorded mileage"),
            "An unmeasured week is stated as unmeasured: \(summary.label)"
        )
        XCTAssertFalse(summary.label.contains("0.0 mi"), "Missing is never a zero")
    }

    /// The summary stacks rather than truncating at the largest accessibility
    /// text size, and the shifts under it are still reachable.
    @MainActor
    func testTheWeeklySummarySurvivesLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededOlderWeeksArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.accessibilityXXXLTextSize]
        launchInPortrait(app)

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: 20))
        older.tap()

        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "The week still says how it went")
        XCTAssertTrue(
            waitForLabel(summary, toContain: "$55.00"),
            "And the figure is whole rather than shortened: \(summary.label)"
        )

        let row = olderWeekRows(in: app).firstMatch
        XCTAssertTrue(scrollTo(row, in: app, maxSwipes: 20), "The shifts under it are still reachable")
    }

    /// A week whose fuel is estimated for some shifts says whose, and keeps the
    /// estimated net apart from recorded expenses.
    @MainActor
    func testAWeeksFuelEstimateStatesItsCoverage() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        // Last week: three shifts, two of which recorded fuel assumptions.
        let lastWeek = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "3 completed shifts"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(lastWeek.label.contains("Recorded gross earnings, $185.00"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(
            lastWeek.label.contains("Estimated fuel") && lastWeek.label.contains("across 2 of 3 completed shifts"),
            "The estimate says it covers two of the three shifts: \(lastWeek.label)"
        )
        XCTAssertTrue(lastWeek.label.contains("recorded miles"), "And how much of the driving: \(lastWeek.label)")
        XCTAssertTrue(
            lastWeek.label.contains("Estimated net after fuel") && lastWeek.label.contains("never added together"),
            "The net carries the sentence that keeps it apart from recorded fuel: \(lastWeek.label)"
        )
        XCTAssertFalse(lastWeek.label.contains("Net after recorded expenses"), "Only one net is on the card")
        attachScreenshot("older-week-partial-fuel")
    }

    /// A week nobody recorded fuel for carries no fuel figure, and certainly
    /// not a zero.
    @MainActor
    func testAWeekWithoutFuelShowsNoFuelFigure() throws {
        let app = launchWithOlderWeeks()
        openOlderWeeks(in: app)

        let lastWeek = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "$55.00"), "Showed: \(lastWeek.label)")
        XCTAssertFalse(lastWeek.label.contains("Estimated fuel"), "Showed: \(lastWeek.label)")
        XCTAssertFalse(lastWeek.label.contains("$0.00"), "Missing is never a zero: \(lastWeek.label)")
    }

    /// The summary is one coherent sentence: the week, then its shifts, then
    /// the three figures that describe it, in that order.
    @MainActor
    func testTheWeeklySummaryNamesItsWeekThenItsFigures() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let header = app.descendants(matching: .any).matching(identifier: "olderWeekHeader").firstMatch
        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(summary, toContain: "completed shifts"))
        XCTAssertTrue(
            summary.label.hasPrefix(header.label),
            "The summary names its own week first: \(summary.label) / \(header.label)"
        )

        let label = summary.label
        let order = ["3 completed shifts", "Recorded gross earnings", "working time", "Recorded mileage"]
            .compactMap { label.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 4, "Every figure is spoken: \(label)")
        XCTAssertEqual(order, order.sorted(), "In the order a listener needs them: \(label)")
    }

    /// At the largest accessibility size the fuller card still says every
    /// figure whole, and the shifts under it are still reachable.
    @MainActor
    func testTheFullWeeklySummarySurvivesLargeText() throws {
        let app = launchWithLongHistory(textSize: Self.accessibilityXXXLTextSize)
        openOlderWeeks(in: app, maxSwipes: 25)

        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(summary, toContain: "$185.00"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("Estimated fuel"))
        XCTAssertGreaterThan(summary.frame.height, 44, "A summary is never a tiny cell")

        let row = olderWeekRows(in: app).firstMatch
        XCTAssertTrue(scrollTo(row, in: app, maxSwipes: 25), "The shifts under it are still reachable")
    }

    // MARK: The current week's own figures

    @MainActor
    private func currentWeekSummary(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "currentWeekSummary").firstMatch
    }

    /// The week the driver is in opens with its own figures, above the shifts
    /// that make it up, and they are this week's figures and nobody else's.
    @MainActor
    func testTheCurrentWeekOpensWithItsOwnFigures() throws {
        let app = launchWithOlderWeeks()

        let summary = currentWeekSummary(in: app)
        XCTAssertTrue(scrollTo(summary, in: app, maxSwipes: 12), "The week says how it is going")
        XCTAssertTrue(
            waitForLabel(summary, toContain: "Recorded gross earnings, $70.00"),
            "Using this week's recorded amount: \(summary.label)"
        )
        XCTAssertTrue(summary.label.contains("1 completed shift"), "Showed: \(summary.label)")
        XCTAssertFalse(summary.label.contains("$55.00"), "Last week is not in this week's figures")
        XCTAssertTrue(
            summary.label.contains("No recorded mileage"),
            "A week whose routes measured nothing says so: \(summary.label)"
        )
        XCTAssertFalse(summary.label.contains("0.0 mi"), "Missing is never a zero")

        let firstRow = rows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(firstRow, in: app), "The shifts are under it")
        XCTAssertLessThan(
            summary.frame.minY,
            firstRow.frame.minY,
            "The week's own figures come before the shifts they summarise"
        )
    }

    /// A week of recorded work leads with what it paid, then how long and how
    /// far, then its shifts and deliveries, and the shifts still open.
    @MainActor
    func testTheCurrentWeekSummaryStatesItsWork() throws {
        let app = launchWithSeededHistory()

        let summary = currentWeekSummary(in: app)
        XCTAssertTrue(scrollUntilHittable(summary, in: app, maxSwipes: 12))
        for expected in ["completed shifts", "Recorded gross earnings", "working time", "Recorded mileage"] {
            XCTAssertTrue(
                waitForLabel(summary, toContain: expected),
                "The week is one spoken sentence and says \(expected): \(summary.label)"
            )
        }
        attachScreenshot("history-current-week")

        openFirstShift(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["shiftDetailEarnings"].waitForExistence(timeout: 5),
            "A shift under the summary still opens its own detail"
        )
    }

    /// At the largest accessibility text size the week's figures stack whole,
    /// and the shifts under them are still reachable.
    @MainActor
    func testTheCurrentWeekSurvivesTheLargestTextSize() throws {
        let app = launchWithSeededHistory(atTextSize: Self.accessibilityXXXLTextSize)

        let summary = currentWeekSummary(in: app)
        XCTAssertTrue(scrollUntilHittable(summary, in: app, maxSwipes: 25), "The summary is reachable")
        XCTAssertTrue(waitForLabel(summary, toContain: "Recorded gross earnings"), "Showed: \(summary.label)")
        XCTAssertGreaterThan(summary.frame.height, 44, "A summary is never a tiny cell")
        attachScreenshot("history-xxxl")

        XCTAssertTrue(
            scrollUntilHittable(rows(in: app).firstMatch, in: app, maxSwipes: 25),
            "The shifts under it are still reachable"
        )
    }

    /// A driver with no history is told where it will come from, and no summary
    /// of nothing is drawn.
    @MainActor
    func testAnEmptyHistorySaysWhereShiftsWillAppear() throws {
        let app = launchWithEmptyStore()

        let notice = app.descendants(matching: .any)["emptyHistoryNotice"]
        XCTAssertTrue(scrollUntilHittable(notice, in: app, maxSwipes: 8), "The empty history states itself")
        XCTAssertTrue(notice.label.contains("No completed shifts yet"), "Showed: \(notice.label)")
        XCTAssertFalse(currentWeekSummary(in: app).exists, "No summary is drawn over no shifts")
        XCTAssertFalse(app.buttons["exportAllHistoryButton"].exists, "Nothing to export is not offered")
    }

    /// A week whose fuel is estimated over every shift says so, rather than
    /// leaving complete coverage as the case with no caveat.
    @MainActor
    func testAnOlderWeekWithCompleteFuelCoverageSaysSo() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
            .matching(NSPredicate(format: "label CONTAINS %@", "$50.03")).firstMatch
        XCTAssertTrue(scrollUntilHittable(summary, in: app, maxSwipes: 16), "Three weeks ago is reachable")
        XCTAssertTrue(
            summary.label.contains("Estimated fuel") && summary.label.contains("across every completed shift"),
            "Complete coverage is stated: \(summary.label)"
        )
        XCTAssertTrue(summary.label.contains("recorded miles"), "And how much of the driving: \(summary.label)")
        attachScreenshot("older-week-full-fuel")
    }

    // MARK: Historical vehicle context

    /// Opens the first shift under Older Weeks: last week's Friday, worked in
    /// the synthetic van at a recorded gas price of zero.
    @MainActor
    private func openLastWeeksFridayShift(in app: XCUIApplication, maxSwipes: Int = 12) {
        openOlderWeeks(in: app, maxSwipes: maxSwipes)
        openLastWeeksFridayRow(in: app, maxSwipes: maxSwipes)
    }

    /// The same shift, from Older Weeks when the journey is already there.
    @MainActor
    private func openLastWeeksFridayRow(in app: XCUIApplication, maxSwipes: Int = 12) {
        let row = olderWeekRows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app, maxSwipes: maxSwipes))
        XCTAssertTrue(waitForLabel(row, toContain: "$45.00"), "Showed: \(row.label)")
        row.tap()
    }

    /// A finished shift says which vehicle and assumptions it recorded, beside
    /// its fuel estimate, including a price recorded as zero.
    @MainActor
    func testAHistoricalShiftShowsTheVehicleItRecorded() throws {
        let app = launchWithLongHistory()
        openLastWeeksFridayShift(in: app)

        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(
            waitForLabel(vehicle, toContain: "Vehicle recorded with this shift: Synthetic Van"),
            "Showed: \(vehicle.label)"
        )
        XCTAssertTrue(vehicle.label.contains("20 miles per gallon"), "Showed: \(vehicle.label)")
        XCTAssertTrue(vehicle.label.contains("gas $0.00 per gallon"), "A recorded zero is said: \(vehicle.label)")

        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "$0.00 per gallon assumed"), "Showed: \(price.label)")
    }

    /// A shift that recorded no vehicle says so, and does not borrow the one
    /// selected in Settings today.
    @MainActor
    func testAShiftThatRecordedNoVehicleStaysUnnamed() throws {
        let app = launchWithLongHistory()

        openSettings(in: app)
        addVehicle(named: "Today's Car", milesPerGallon: "31", in: app)
        goBack(in: app)

        openFirstShift(in: app)
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(
            waitForLabel(vehicle, toContain: "No vehicle recorded for this shift"),
            "Showed: \(vehicle.label)"
        )
        XCTAssertFalse(vehicle.label.contains("Today's Car"), "Nothing is borrowed from Settings")
        XCTAssertFalse(
            app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"].exists,
            "No economy is invented either"
        )
    }

    /// Selecting and pricing a different vehicle today leaves last week's
    /// recorded vehicle exactly as it was.
    @MainActor
    func testSettingsChangesDoNotReachAHistoricalShift() throws {
        let app = launchWithLongHistory()

        openSettings(in: app)
        addVehicle(named: "Synthetic Van", milesPerGallon: "9", in: app)
        setCurrentGasPrice("5.55", in: app)
        goBack(in: app)

        openLastWeeksFridayShift(in: app)
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(waitForLabel(vehicle, toContain: "20 miles per gallon"), "Showed: \(vehicle.label)")
        XCTAssertFalse(vehicle.label.contains("9 miles per gallon"), "Showed: \(vehicle.label)")
        XCTAssertFalse(vehicle.label.contains("$5.55"), "Showed: \(vehicle.label)")
    }

    /// At the largest accessibility size the vehicle row still says the whole
    /// name and every figure.
    @MainActor
    func testTheHistoricalVehicleSurvivesLargeText() throws {
        let app = launchWithLongHistory(textSize: Self.accessibilityXXXLTextSize)
        openLastWeeksFridayShift(in: app, maxSwipes: 25)

        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollUntilHittable(vehicle, in: app, maxSwipes: 40))
        XCTAssertTrue(waitForLabel(vehicle, toContain: "Synthetic Van"), "Showed: \(vehicle.label)")
        XCTAssertGreaterThanOrEqual(vehicle.frame.height, 44, "The row is not squeezed to fit")
    }

    // MARK: Long histories

    /// The cents of every `$50.xx` or `$51.xx` amount in the long-history
    /// fixture's visible older rows. The fixture pays `$50.00` plus the number
    /// of weeks ago in cents, so newest first means these only ever grow.
    @MainActor
    private func visibleWeeklyCents(in app: XCUIApplication) -> [Int] {
        olderWeekRows(in: app).allElementsBoundByIndex.compactMap { row -> Int? in
            guard let range = row.label.range(of: #"\$5[01]\.\d\d"#, options: .regularExpression) else {
                return nil
            }
            let text = row.label[range].dropFirst()
            guard let value = Double(text) else { return nil }
            return Int((value * 100).rounded())
        }
    }

    /// Returns from a shift's detail to Older Weeks, which is where it was
    /// opened from; ``goBack(in:)`` expects the root screen.
    @MainActor
    private func goBackToOlderWeeks(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Older Weeks"].waitForExistence(timeout: 5))
    }

    /// Two and a half years of weeks, newest first all the way down, and the
    /// oldest shift is reachable, opens, and leaves the list where it was.
    @MainActor
    func testALongHistoryIsNewestFirstAndItsOldestShiftIsReachable() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let oldest = olderWeekRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", "$12.34")).firstMatch
        var seen: [Int] = []
        var swipes = 0
        while !(oldest.exists && oldest.isHittable), swipes < 160 {
            for cents in visibleWeeklyCents(in: app) where !seen.contains(cents) {
                seen.append(cents)
            }
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(oldest.isHittable, "The oldest shift, from about two and a half years ago, is reachable")
        XCTAssertGreaterThan(seen.count, 40, "Most of the fixture's weeks went past: \(seen.count)")
        XCTAssertEqual(seen, seen.sorted(), "Newest week first, the whole way down: \(seen)")

        // Its week is summarised like any other.
        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        let oldestWeek = summaries.matching(NSPredicate(format: "label CONTAINS %@", "$12.34")).firstMatch
        XCTAssertTrue(oldestWeek.waitForExistence(timeout: 10), "The oldest week has its own summary")

        oldest.tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("$12.34"), "It opens its own detail: \(earnings.label)")

        goBackToOlderWeeks(in: app)
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        XCTAssertTrue(oldest.isHittable, "Coming back returns to where the driver was, not to the top")

        // And the list carries on from there: back up towards newer weeks.
        app.swipeDown()
        XCTAssertTrue(
            olderWeekRows(in: app).firstMatch.waitForExistence(timeout: 5),
            "The list is still a list after returning"
        )
    }

    /// At the largest accessibility size a shift several weeks down is still
    /// reachable and opens, and its week's summary is never a tiny cell.
    @MainActor
    func testALongHistoryIsNavigableAtTheLargestTextSize() throws {
        let app = launchWithLongHistory(textSize: Self.accessibilityXXXLTextSize)
        openOlderWeeks(in: app, maxSwipes: 25)

        let target = olderWeekRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", "$50.06")).firstMatch
        XCTAssertTrue(scrollUntilHittable(target, in: app, maxSwipes: 80), "A shift a few weeks down is reachable")

        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        for index in 0..<min(summaries.count, 3) {
            let summary = summaries.element(boundBy: index)
            if summary.exists, summary.isHittable {
                XCTAssertGreaterThan(summary.frame.height, 44, "A summary is never a tiny cell")
            }
        }

        target.tap()
        // At this size the earnings section is below the fold of the detail
        // screen, so it is scrolled to rather than expected on arrival.
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(scrollTo(earnings, in: app, maxSwipes: 20), "The tapped shift's detail opens")
        XCTAssertTrue(earnings.label.contains("$50.06"), "Showed: \(earnings.label)")
        goBackToOlderWeeks(in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Returning keeps the place in the list")
    }

    // MARK: A week follows an edit to its own shifts

    /// Editing an older shift's amount updates its week's summary on return,
    /// without leaving Older Weeks, and leaves the next week's summary alone.
    @MainActor
    func testEditingAnOlderShiftRefreshesItsWeek() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        let lastWeek = summaries.firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "Recorded gross earnings, $185.00"), "Showed: \(lastWeek.label)")

        openLastWeeksFridayRow(in: app)
        let edit = app.buttons["editShiftEarningsButton"]
        XCTAssertTrue(scrollTo(edit, in: app))
        edit.tap()
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        type("50", into: app)
        app.buttons["saveEarningsButton"].tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(waitForLabel(earnings, toContain: "$50.00"), "Showed: \(earnings.label)")

        goBackToOlderWeeks(in: app)
        XCTAssertTrue(
            waitForLabel(lastWeek, toContain: "Recorded gross earnings, $190.00"),
            "The week is worked out again from what the store now says: \(lastWeek.label)"
        )
        attachScreenshot("older-weeks-after-edit")
    }

    /// Deleting an older shift updates its week's count and total on return.
    @MainActor
    func testDeletingAnOlderShiftRefreshesItsWeek() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let lastWeek = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "3 completed shifts"), "Showed: \(lastWeek.label)")

        openLastWeeksFridayRow(in: app)
        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(delete, in: app, maxSwipes: 20))
        delete.tap()
        let confirm = app.buttons.matching(identifier: "confirmDeleteShiftButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.navigationBars["Older Weeks"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "2 completed shifts"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(lastWeek.label.contains("Recorded gross earnings, $140.00"), "Showed: \(lastWeek.label)")
    }

    /// A week the driver has not worked yet says so, and does not quietly fill
    /// itself with the week before.
    @MainActor
    func testAnEmptyCurrentWeekSaysSoAndKeepsTheOlderWeeksReachable() throws {
        let app = launchWithOlderWeeks(includingCurrentWeek: false)

        let notice = app.descendants(matching: .any)["emptyCurrentWeekNotice"]
        XCTAssertTrue(scrollUntilHittable(notice, in: app, maxSwipes: 12), "The empty week states itself")
        XCTAssertEqual(rows(in: app).count, 0, "Nothing older was pulled forward to fill the list")
        XCTAssertEqual(elements(containing: "$55.00", in: app).count, 0)

        // The notice is a row of the section and the link is the row after it,
        // so the link is scrolled to rather than assumed to be on screen.
        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app), "The work that does exist is still one tap away")
        older.tap()

        // Each week opens with its own summary, so the three rows are reached
        // by scrolling, newest first, rather than counted on one screen.
        for amount in ["$55.00", "$33.00", "$41.00"] {
            let row = olderWeekRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", amount)).firstMatch
            XCTAssertTrue(scrollUntilHittable(row, in: app), "All three older shifts are there: \(amount)")
        }
    }

    // MARK: Detail

    /// Tapping a completed shift opens that shift, and shows what it recorded.
    @MainActor
    func testOpensTheDetailOfTheTappedShift() throws {
        let app = launchWithSeededHistory()
        let history = revealHistoryRows(2, in: app)
        XCTAssertEqual(history.count, 2, "The fixture holds one shift with earnings and one without")

        // The older shift: no amount, no route.
        history.element(boundBy: 1).tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertEqual(earnings.label, "No amount recorded")
        // Driving sits under the summary and the performance figures.
        let unrouted = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(unrouted, in: app))
        XCTAssertTrue(
            unrouted.label.contains("No route recorded"),
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

        // Two rows further down, under the delivery active times, so it is
        // scrolled to rather than assumed rendered with the hourly figure.
        let perMile = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(perMile, in: app))
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
        let history = revealHistoryRows(2, in: app)

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
        XCTAssertTrue(scrollUntilHittable(row, in: app))
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
        let history = revealHistoryRows(2, in: app)

        history.element(boundBy: 1).tap()

        // Driving sits under the summary and the performance figures, so it is
        // scrolled to rather than expected on arrival.
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
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
        let history = revealHistoryRows(2, in: app)

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
        XCTAssertTrue(scrollToTop(reaching: app.buttons["endShiftButton"], in: app))
        app.buttons["endShiftButton"].tap()
        let row = revealHistoryRows(1, in: app).firstMatch
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

    /// A shift and every delivery on it survive the driver leaving the app and
    /// coming back, which is what a shift spent answering messages and reading
    /// maps actually looks like.
    ///
    /// The interface is rebuilt from the store on return rather than from view
    /// state, so nothing here should have to be restored by hand. Route capture
    /// pauses and resumes across the same transition; that half is asserted in
    /// `RealWorldRecoveryTests`, because a UI test cannot make the simulator
    /// produce positions.
    @MainActor
    func testStackedWorkSurvivesLeavingAndReturningToTheApp() throws {
        let app = launchWithActiveDelivery()

        let accepted = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(accepted, in: app))

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            app.buttons["endShiftButton"].waitForExistence(timeout: 10),
            "The shift is still running; nothing about returning to the app ends one"
        )
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(accepted, in: app), "Both deliveries are still on screen")
        XCTAssertEqual(accepted.label, "Delivery 2. Mark arrived at pickup")
        XCTAssertEqual(carrying.label, "Delivery 3. Mark delivery completed")
        XCTAssertEqual(
            app.buttons.matching(identifier: "deliveryActionButton").count,
            2,
            "Neither delivery was duplicated by the return, and neither was dropped"
        )

        // And the driver can still see whether the route is being recorded.
        XCTAssertTrue(app.descendants(matching: .any)["routeCaptureStatus"].exists)

        // The recovered card is a control over the real record, not a redrawn
        // placeholder: advancing it moves that delivery and leaves the other.
        carrying.tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "The delivered one leaves the list"
        )
        XCTAssertEqual(accepted.label, "Delivery 2. Mark arrived at pickup")
    }

    // MARK: Parked for a pickup

    /// Recording the vehicle as parked stops the route, says so in two places,
    /// and leaves the shift running.
    @MainActor
    func testParkingStopsTheRouteAndLeavesTheShiftRunning() throws {
        let app = launchWithStubbedLocation()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitForLabel(status, toContain: "Location tracking active"),
            "The shift starts recording: \(status.label)"
        )

        let park = app.buttons["parkShiftButton"]
        XCTAssertTrue(scrollTo(park, in: app), "Parking is offered on a running shift")
        XCTAssertTrue(
            park.label.contains("shift keeps running"),
            "The control says aloud what it does not do: \(park.label)"
        )
        park.tap()

        // The capture status says recording has stopped, and says why.
        XCTAssertTrue(
            waitForLabel(status, toContain: "Route recording stopped while parked"),
            "Capture status: \(status.label)"
        )

        // And the panel says it again where the driver is looking, with the
        // shift's own state unchanged beside it.
        let notice = app.descendants(matching: .any)["parkedShiftNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(
            notice.label.contains("shift is still running"),
            "Parked is not paused, and the notice must not read as though it were: \(notice.label)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["activeShiftStatus"].exists,
            "The shift still reports itself as running rather than paused"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["pausedShiftStatus"].exists,
            "No pause was recorded"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["workingTime"].exists,
            "And its working time is still on screen, still counting"
        )
    }

    /// Resuming driving is one tap, and it starts recording again.
    @MainActor
    func testResumingDrivingStartsRecordingAgain() throws {
        let app = launchWithStubbedLocation()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let park = app.buttons["parkShiftButton"]
        XCTAssertTrue(scrollTo(park, in: app))
        park.tap()

        let resume = app.buttons["resumeDrivingButton"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Leaving the state is one tap")
        XCTAssertFalse(park.exists, "And parking is not offered while already parked")
        resume.tap()

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(
            waitForLabel(status, toContain: "Location tracking active"),
            "Recording starts again: \(status.label)"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["parkedShiftNotice"].exists,
            "And the notice goes with it"
        )
        XCTAssertTrue(app.buttons["parkShiftButton"].exists, "Parking is offered again")
    }

    /// A completed shift that was parked says how much of its short route the
    /// driver asked for, and reports every minute of it as worked.
    @MainActor
    func testACompletedParkedShiftExplainsItsShortRoute() throws {
        let app = launchWithParkedHistory()

        openFirstShift(in: app)

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(
            waitForLabel(mileage, toContain: "4.5 miles recorded"),
            "The two capture sessions, with nothing measured across the stretch parked: \(mileage.label)"
        )

        // The caveats are read out inside the same combined element as the
        // figure they qualify, which is the arrangement that stops a listener
        // hearing a mileage with nothing attached to it.
        let caveats = mileage
        XCTAssertTrue(
            caveats.label.contains("1 stretch parked"),
            "It says what the driver recorded: \(caveats.label)"
        )
        XCTAssertTrue(caveats.label.contains("25 min"), caveats.label)
        XCTAssertTrue(
            caveats.label.contains("time you recorded as parked"),
            "And the partial sentence stops claiming miles were driven across it: \(caveats.label)"
        )
        XCTAssertFalse(
            caveats.label.contains("more miles were driven than were recorded"),
            "That sentence is untrue of a vehicle that spent the stretch in a parking space"
        )

        // Nothing was subtracted from the shift's own time. A paused shift shows
        // a Paused row and a Working row; this one shows neither, because
        // shopping is working and working equals elapsed to the second.
        XCTAssertFalse(
            app.descendants(matching: .any)["shiftDetailPausedTime"].exists,
            "Parking records no pause"
        )
    }

    // MARK: What each stacked delivery is waiting for

    /// Three cards on one screen, each saying which delivery it is, what it is
    /// doing and what it is waiting for, without any of them being opened.
    @MainActor
    func testEveryStackedDeliverySaysWhatItIsWaitingFor() throws {
        let app = launchWithStackedOffer()

        let first = deliveryStatusCard(named: "Delivery 1", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let second = deliveryStatusCard(named: "Delivery 2", in: app)
        let third = deliveryStatusCard(named: "Delivery 3", in: app)

        // The fixture's first delivery is at its pickup and the other two were
        // only accepted, so one card is waiting for a different event from the
        // two beside it.
        XCTAssertTrue(first.label.contains("waiting at the pickup"), first.label)
        XCTAssertTrue(
            first.label.contains("Next step, mark order picked up"),
            "The card says what it is waiting for, not only what it is doing: \(first.label)"
        )

        XCTAssertTrue(second.label.contains("heading to the pickup"), second.label)
        XCTAssertTrue(second.label.contains("Next step, mark arrived at pickup"), second.label)
        XCTAssertTrue(third.label.contains("Next step, mark arrived at pickup"), third.label)

        // And the cards are distinguishable by that alone, which is the claim:
        // two deliveries in different states must not read as one.
        XCTAssertNotEqual(first.label, second.label)
        XCTAssertFalse(
            first.label.contains("Next step, mark arrived at pickup"),
            "The card at its pickup is not offered the arrival it already recorded"
        )
    }

    /// Advancing one stacked delivery moves that card's next step and leaves
    /// every other card saying exactly what it said.
    @MainActor
    func testAdvancingOneStackedDeliveryMovesOnlyItsNextStep() throws {
        let app = launchWithStackedOffer()

        let second = deliveryStatusCard(named: "Delivery 2", in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        let first = deliveryStatusCard(named: "Delivery 1", in: app)
        let firstBefore = first.label

        let step = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(step, in: app))
        step.tap()

        XCTAssertTrue(
            waitForLabel(second, toContain: "Next step, mark order picked up"),
            "Delivery 2 recorded its arrival, so its card now waits for the pickup: \(second.label)"
        )
        XCTAssertEqual(
            first.label,
            firstBefore,
            "And the card beside it says exactly what it said before"
        )
    }

    // MARK: Reminders about a lifecycle event that may have gone unrecorded

    /// Two stale deliveries each get their own reminder, naming their own
    /// delivery and offering their own next step.
    @MainActor
    func testStaleDeliveriesEachGetTheirOwnReminder() throws {
        let app = launchWithMissedLifecycle()

        let reminders = app.descendants(matching: .any).matching(identifier: "deliverySuggestion")
        XCTAssertTrue(reminders.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitForCount(reminders, toEqual: 2),
            "Two deliveries are stale; the third was picked up and is never the subject of one"
        )

        let waiting = deliveryButton("deliverySuggestionActionButton", containing: "Delivery 1", in: app)
        let heading = deliveryButton("deliverySuggestionActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(waiting.exists, "The delivery at its pickup is offered the pickup")
        XCTAssertTrue(heading.exists, "The delivery that only recorded an acceptance is offered the arrival")

        // Each control names the delivery it acts on, in print and aloud, so
        // neither is identified by where it happens to sit.
        XCTAssertTrue(
            waiting.label.hasPrefix("Delivery 1."),
            "A reminder's control names its delivery first: \(waiting.label)"
        )
        XCTAssertTrue(waiting.label.contains("Mark order picked up"), waiting.label)
        XCTAssertTrue(heading.label.hasPrefix("Delivery 2."), heading.label)
        XCTAssertTrue(heading.label.contains("Mark arrived at pickup"), heading.label)

        // Nothing is offered for the delivery that is already in the car,
        // however long it has been carried.
        XCTAssertFalse(
            deliveryButton("deliverySuggestionActionButton", containing: "Delivery 3", in: app).exists,
            "A delivery already picked up is never the subject of a reminder"
        )
    }

    /// The reminder states what was recorded and says plainly that DashPilot did
    /// not observe it.
    @MainActor
    func testAReminderStatesItsEvidenceAndClaimsNoObservation() throws {
        let app = launchWithMissedLifecycle()

        let reminder = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "deliverySuggestion",
                    "Delivery 1"
                )
            )
            .firstMatch
        XCTAssertTrue(reminder.waitForExistence(timeout: 10))

        let spoken = reminder.label
        XCTAssertTrue(
            spoken.contains("reached the pickup") && spoken.contains("records no pickup"),
            "It states what the record holds: \(spoken)"
        )
        XCTAssertTrue(spoken.contains("Already picked this order up?"), spoken)
        XCTAssertTrue(
            spoken.contains("DashPilot cannot tell where you are"),
            "The caveat travels with the reminder rather than sitting somewhere else: \(spoken)"
        )
        for claim in ["you arrived", "you picked up", "detected", "confirmed"] {
            XCTAssertFalse(
                spoken.lowercased().contains(claim),
                "A reminder must not claim \"\(claim)\": \(spoken)"
            )
        }
    }

    /// Confirming a reminder records that delivery's own step and leaves the
    /// other deliveries exactly where they were.
    @MainActor
    func testConfirmingAReminderAdvancesOnlyThatDelivery() throws {
        let app = launchWithMissedLifecycle()

        let heading = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Delivery 2. Mark arrived at pickup")

        let waitingStep = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertEqual(waitingStep.label, "Delivery 1. Mark order picked up")

        let confirm = deliveryButton("deliverySuggestionActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // The delivery the reminder named has moved, through the ordinary
        // lifecycle action rather than through anything of the reminder's own.
        XCTAssertTrue(
            waitForLabel(heading, toContain: "Delivery 2. Mark order picked up"),
            "Delivery 2 recorded its arrival: \(heading.label)"
        )
        XCTAssertEqual(
            waitingStep.label,
            "Delivery 1. Mark order picked up",
            "Delivery 1 is untouched by a reminder confirmed on Delivery 2"
        )

        // And the reminder it answered is gone, because the delivery is no
        // longer in the state it was about.
        XCTAssertTrue(
            waitForCount(
                app.buttons.matching(identifier: "deliverySuggestionActionButton"),
                toEqual: 1
            ),
            "The answered reminder leaves; the other one stays"
        )
    }

    /// Waving a reminder away records nothing and leaves the delivery alone.
    @MainActor
    func testDismissingAReminderChangesNothing() throws {
        let app = launchWithMissedLifecycle()

        let step = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(step.waitForExistence(timeout: 10))
        XCTAssertEqual(step.label, "Delivery 1. Mark order picked up")

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "3 deliveries in progress"), status.label)

        let dismiss = deliveryButton("deliverySuggestionDismissButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(
            dismiss.label.contains("Nothing is recorded"),
            "The control says aloud that it records nothing: \(dismiss.label)"
        )
        dismiss.tap()

        XCTAssertTrue(
            waitForCount(
                app.descendants(matching: .any).matching(identifier: "deliverySuggestion"),
                toEqual: 1
            ),
            "Only the dismissed reminder goes"
        )
        XCTAssertEqual(
            step.label,
            "Delivery 1. Mark order picked up",
            "The delivery is exactly where it was, so nothing was recorded"
        )
        XCTAssertTrue(
            waitForLabel(status, toContain: "3 deliveries in progress"),
            "And the shift still holds the same three deliveries: \(status.label)"
        )
    }

    // MARK: Offers containing several deliveries

    /// Deliveries accepted together are shown together, and a delivery accepted
    /// on its own is shown exactly as it always was.
    @MainActor
    func testDeliveriesAcceptedTogetherAreShownAsOneOffer() throws {
        let app = launchWithStackedOffer()

        // The panel is read before it is scrolled: `scrollTo` swipes rather than
        // waits, so a journey that starts swiping at a still-launching app can
        // exhaust its swipes before the first card exists.
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app), "The offer that held two deliveries names itself")
        XCTAssertTrue(
            heading.label.contains("Offer 1") && heading.label.contains("2 deliveries accepted together"),
            "The heading says which offer and how many: \(heading.label)"
        )

        // Exactly one heading: the add-on offer held a single delivery, and a
        // heading over every card would be the interface repeating itself.
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count,
            1,
            "An offer of one gets no heading"
        )

        // Every card still exists, still advances itself, and still says which
        // delivery it is.
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3)
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app).label,
            "Delivery 1. Mark order picked up"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app).label,
            "Delivery 2. Mark arrived at pickup"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app).label,
            "Delivery 3. Mark arrived at pickup"
        )
    }

    /// The grouping is spoken, so a listener knows which cards belong together
    /// without seeing where they sit.
    @MainActor
    func testGroupedDeliveriesSayWhatTheyWereAcceptedWith() throws {
        let app = launchWithStackedOffer()

        // The panel is read before it is scrolled: `scrollTo` swipes rather than
        // waits, so a journey that starts swiping at a still-launching app can
        // exhaust its swipes before the first card exists.
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let grouped = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activeDeliveryStatus",
                    "Delivery 1"
                )
            )
            .firstMatch
        XCTAssertTrue(scrollTo(grouped, in: app))
        XCTAssertTrue(
            grouped.label.contains("Part of Offer 1, accepted together with Delivery 2"),
            "The card names its siblings aloud: \(grouped.label)"
        )

        let alone = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activeDeliveryStatus",
                    "Delivery 3"
                )
            )
            .firstMatch
        XCTAssertTrue(scrollTo(alone, in: app))
        XCTAssertFalse(
            alone.label.contains("accepted together"),
            "A delivery accepted on its own claims no grouping: \(alone.label)"
        )
    }

    /// One delivery of an offer advances without moving its sibling, and the
    /// heading keeps stating the offer it belongs to.
    @MainActor
    func testAdvancingOneOfATwoDeliveryOfferLeavesItsSibling() throws {
        let app = launchWithStackedOffer()

        // The panel is read before it is scrolled: `scrollTo` swipes rather than
        // waits, so a journey that starts swiping at a still-launching app can
        // exhaust its swipes before the first card exists.
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let first = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        let sibling = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        // Scrolled from a known top rather than from wherever the launch left
        // the screen. `scrollTo` stops as soon as the button *exists*, and a
        // button inside a scroll view exists while it is off screen above:
        // `tap()` then scrolls it into view itself and can park it under the
        // navigation bar, where the synthesized tap lands on the bar and the
        // delivery never moves. That reproduces only in a full serial run,
        // where the app is relaunched over a running one and the panel is not
        // where an isolated launch leaves it. Going to the top first and
        // swiping down to the card makes the position the same either way.
        XCTAssertTrue(scrollToTop(reaching: app.buttons["endShiftButton"], in: app))
        XCTAssertTrue(scrollUntilHittable(first, in: app), "The card's own button can be pressed where it is")
        first.tap()

        XCTAssertTrue(
            waitForLabel(first, toContain: "Mark delivery completed"),
            "The delivery that was tapped moved on"
        )
        XCTAssertEqual(
            sibling.label,
            "Delivery 2. Mark arrived at pickup",
            "And its sibling stayed exactly where it was"
        )

        // Delivering one of the two leaves the other running, and the heading
        // now says how much of the offer is left rather than disappearing.
        first.tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2),
            "The delivered one leaves the list and the other two stay"
        )
        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(
            heading.label.contains("1 of 2 still in progress"),
            "The offer is not finished because one of its deliveries is: \(heading.label)"
        )
    }

    /// Recording an offer that contained two deliveries takes one sheet and one
    /// confirmation, and records exactly two.
    @MainActor
    func testStartingAnOfferOfTwoRecordsTwoDeliveries() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(identifier: "deliveryActionButton").count,
            0,
            "Nothing is recorded before the sheet is confirmed"
        )

        let offerControl = app.buttons["startOfferButton"]
        XCTAssertTrue(scrollTo(offerControl, in: app), "The control for a several-delivery offer is on the panel")
        offerControl.tap()

        let confirm = app.buttons["confirmStartOfferButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Start an offer of 2 deliveries", "It opens on two, and says so")
        confirm.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2),
            "Two deliveries, from one offer"
        )
        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(heading.label.contains("2 deliveries accepted together"), "Showed: \(heading.label)")

        // And the one-tap path is untouched: it adds a single delivery, in an
        // offer of its own, with no heading over it.
        XCTAssertTrue(scrollToTop(reaching: app.buttons["startDeliveryButton"], in: app))
        app.buttons["startDeliveryButton"].tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 3),
            "One more delivery, not two"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count,
            1,
            "The delivery started alone joined no group"
        )
    }

    /// Dismissing the sheet records nothing.
    @MainActor
    func testCancellingTheOfferSheetRecordsNothing() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        let offerControl = app.buttons["startOfferButton"]
        XCTAssertTrue(scrollTo(offerControl, in: app))
        offerControl.tap()

        let cancel = app.buttons["cancelStartOfferButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(identifier: "deliveryActionButton").count,
            0,
            "A dismissed sheet records no offer and no delivery"
        )
    }

    // MARK: Correcting which deliveries arrived together

    /// Two offers the driver recorded separately become the one acceptance they
    /// really were, and the panel says so afterwards.
    @MainActor
    func testCorrectingGroupingCombinesTwoOffers() throws {
        let app = launchWithStackedOffer()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "Correction is one control, not a button on every card")
        correct.tap()

        // The add-on offer is the one that moves, because it was accepted after
        // the offer it is joining.
        let combine = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "offerCorrectionMergeButton", "Combine Offer 2"))
            .firstMatch
        XCTAssertTrue(scrollTo(combine, in: app), "Offer 2 can be combined into the offer accepted before it")
        combine.tap()

        let destination = app.buttons["offerCorrectionDestinationButton"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "Combine Offer 2 into Offer 1", "The direction is in the control itself")
        destination.tap()

        // The confirmation names the deliveries that move, and says the offer
        // they leave is removed.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let confirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(confirm.label, "Combine into Offer 1")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Delivery 3 moves to Offer 1")).count > 0,
            "The confirmation names what moves rather than saying \"merge\""
        )
        confirm.tap()

        // One offer left, holding all three deliveries.
        let header = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@", "offerCorrectionOfferHeader"))
        XCTAssertTrue(waitForCount(header, toEqual: 1), "The offer left holding nothing is gone")
        XCTAssertTrue(header.firstMatch.label.contains("3 deliveries accepted together"),
                      "Showed: \(header.firstMatch.label)")

        app.buttons["closeOfferCorrectionButton"].tap()

        // And the running panel agrees, with every delivery still advancing
        // itself.
        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(heading.label.contains("3 deliveries accepted together"), "Showed: \(heading.label)")
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3)
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app).label,
            "Delivery 1. Mark order picked up",
            "The delivery that was already waiting at its pickup kept its own next step"
        )
    }

    /// An offer grouped by mistake becomes one offer per delivery, and every
    /// card keeps the step it was on.
    @MainActor
    func testCorrectingGroupingSeparatesAnOffer() throws {
        let app = launchWithStackedOffer()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app))
        correct.tap()

        let separate = app.buttons["offerCorrectionSeparateButton"]
        XCTAssertTrue(separate.waitForExistence(timeout: 5), "Only a grouped offer offers this")
        XCTAssertEqual(separate.label, "Separate Offer 1 into one offer per delivery")
        separate.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let confirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertEqual(confirm.label, "Separate Offer 1")
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Delivery 2 moves into a new offer of its own")
            ).count > 0,
            "The confirmation names the delivery that moves"
        )
        confirm.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "offerCorrectionSeparateButton"), toEqual: 0),
            "Nothing is grouped any more, so nothing offers to be separated"
        )

        app.buttons["closeOfferCorrectionButton"].tap()

        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count,
            0,
            "Three offers of one, which is what the panel looked like before offers were grouped"
        )
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3)
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app).label,
            "Delivery 1. Mark order picked up",
            "Regrouping moved no lifecycle step"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app).label,
            "Delivery 2. Mark arrived at pickup"
        )
    }

    /// One delivery leaves the offer it was grouped with, and the sibling it
    /// leaves behind is untouched.
    @MainActor
    func testSplittingOneDeliveryIntoItsOwnOffer() throws {
        let app = launchWithStackedOffer()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app))
        correct.tap()

        let delivery = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "offerCorrectionDeliveryButton", "Delivery 2"))
            .firstMatch
        XCTAssertTrue(delivery.waitForExistence(timeout: 5))
        XCTAssertEqual(delivery.label, "Move Delivery 2 out of Offer 1")
        delivery.tap()

        let split = app.buttons["offerCorrectionSplitButton"]
        XCTAssertTrue(split.waitForExistence(timeout: 5), "Splitting is offered apart from moving, not mixed into it")
        XCTAssertEqual(split.label, "Put Delivery 2 in a new offer of its own")
        split.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "offerCorrectionSeparateButton"), toEqual: 0),
            "Every offer now holds one delivery"
        )

        app.buttons["closeOfferCorrectionButton"].tap()
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count,
            0
        )
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3, "Nothing was deleted")
    }

    /// Leaving the correction screen records nothing.
    @MainActor
    func testDismissingTheCorrectionSheetChangesNothing() throws {
        let app = launchWithStackedOffer()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app))
        correct.tap()

        XCTAssertTrue(app.buttons["offerCorrectionSeparateButton"].waitForExistence(timeout: 5))
        app.buttons["closeOfferCorrectionButton"].tap()

        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(heading.label.contains("2 deliveries accepted together"), "Showed: \(heading.label)")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count,
            1,
            "The grouping is exactly what it was"
        )
    }

    /// A store holding an offer with no deliveries is read, stated, and
    /// corrected around.
    @MainActor
    func testCorrectionReadsAnOfferHoldingNoDeliveries() throws {
        let app = launchWithMalformedOffer()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "The screen opens over an anomalous store")
        correct.tap()

        let empty = app.staticTexts["offerCorrectionEmptyOffer"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "The row is stated rather than silently dropped")
        XCTAssertTrue(
            empty.label.contains("Nothing is recorded under this offer"),
            "Showed: \(empty.label)"
        )

        // And the offers around it still correct. Separating the real offer is
        // unaffected by the row beside it.
        let separate = app.buttons["offerCorrectionSeparateButton"]
        XCTAssertTrue(separate.exists, "The real offer is still correctable")
        separate.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "offerCorrectionSeparateButton"), toEqual: 0)
        )
        XCTAssertTrue(app.staticTexts["offerCorrectionEmptyOffer"].exists, "And the anomalous row is left alone")
    }

    /// Grouping is corrected from a finished shift too, and the history rows say
    /// so afterwards.
    @MainActor
    func testCorrectingGroupingFromACompletedShift() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        // Three deliveries, each recorded in an offer of its own, so no row
        // claims any grouping yet.
        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertFalse(first.label.contains("accepted together"), "Showed: \(first.label)")

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "History offers the same correction the running shift does")
        correct.tap()

        // The second offer joins the first, which is the direction the
        // acceptance times allow.
        let combine = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "offerCorrectionMergeButton", "Combine Offer 2"))
            .firstMatch
        XCTAssertTrue(scrollTo(combine, in: app))
        combine.tap()

        let destination = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "offerCorrectionDestinationButton", "into Offer 1"))
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch.tap()

        app.buttons["closeOfferCorrectionButton"].tap()

        // Left and reopened rather than scrolled back: the sheet closes onto a
        // screen already scrolled past the rows the correction changed, and a
        // journey that swipes blindly to find them again is asserting how far
        // the screen happened to have moved.
        goBack(in: app)
        openFirstShift(in: app)

        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(
            summary.label,
            "2 deliveries completed. 1 delivery cancelled",
            "Regrouping moved no count and no terminal state"
        )

        // The two rows now say they arrived together, and neither lost anything
        // it recorded.
        let corrected = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(corrected, in: app))
        XCTAssertTrue(
            corrected.label.contains("Offer 1, accepted together with Delivery 2"),
            "Showed: \(corrected.label)"
        )
        XCTAssertTrue(corrected.label.contains("Waited at pickup"), "The recorded wait is untouched")
        XCTAssertTrue(corrected.label.contains("Accepted to delivered"))
    }

    /// A shift with a single delivery has no grouping to correct, and says so by
    /// offering nothing.
    @MainActor
    func testCorrectionIsNotOfferedForASingleDelivery() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["correctOffersButton"].exists, "Nothing is recorded, so nothing can be regrouped")

        app.buttons["startDeliveryButton"].tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1)
        )
        XCTAssertFalse(app.buttons["correctOffersButton"].exists, "One delivery is not a grouping")

        XCTAssertTrue(scrollToTop(reaching: app.buttons["startDeliveryButton"], in: app))
        app.buttons["startDeliveryButton"].tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2)
        )
        XCTAssertTrue(scrollTo(app.buttons["correctOffersButton"], in: app), "Two deliveries can be regrouped")
    }

    // MARK: Taking back a delivery marked delivered by mistake

    /// The offer to undo appears the moment a delivery is marked delivered, says
    /// which delivery it belongs to, and puts that delivery back where it was.
    @MainActor
    func testUndoingADeliveryMarkedDeliveredByMistake() throws {
        let app = launchWithActiveDelivery()

        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollUntilHittable(carrying, in: app))
        carrying.tap()

        // Read before anything slow: the offer is short lived by design, so a
        // journey that spends the window scrolling is testing its own scrolling.
        let banner = app.staticTexts["undoDeliveredBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "The offer to take it back is on screen")
        XCTAssertEqual(banner.label, "Delivery 3 marked delivered", "It names the delivery it is about")

        let undo = app.buttons["undoDeliveredButton"]
        XCTAssertTrue(undo.exists)
        XCTAssertEqual(
            undo.label,
            "Undo marking Delivery 3 delivered. It becomes active again, heading to the customer.",
            "What a listener hears says which delivery, and what pressing it does"
        )
        XCTAssertTrue(scrollUpUntilHittable(undo, in: app), "and it can be pressed where it sits")
        undo.tap()

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2),
            "The delivery is among the ones being worked again"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app).label,
            "Delivery 3. Mark delivery completed",
            "and it is back at the step it was on, with the pickup it recorded still recorded"
        )
        XCTAssertFalse(app.buttons["undoDeliveredButton"].exists, "The offer goes once it has been taken")

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "2 deliveries in progress"), "Status: \(status.label)")
        XCTAssertTrue(
            status.label.contains("1 delivery completed"),
            "and the shift counts one completed delivery again, not two: \(status.label)"
        )
    }

    /// A delivery marked delivered earlier in the shift is reopened from the
    /// deliberate control, behind a confirmation that says what will happen.
    @MainActor
    func testReopeningADeliveredDeliveryFromTheShiftsRecord() throws {
        let app = launchWithActiveDelivery()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")

        // Nothing was marked delivered in this session, so there is no offer to
        // catch: this is the path for a mistake noticed later.
        XCTAssertFalse(app.buttons["undoDeliveredButton"].exists)

        let reopen = app.buttons["reopenDeliveryButton"]
        XCTAssertTrue(scrollTo(reopen, in: app), "The deliberate way back is one control under the panel")
        reopen.tap()

        let row = app.descendants(matching: .any)["deliveryRecoveryRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The shift's delivered delivery is listed")
        XCTAssertTrue(row.label.contains("Delivery 1, recorded as delivered"), "Showed: \(row.label)")
        XCTAssertTrue(
            row.label.contains("Reopening it makes it active again, heading to the customer"),
            "The row says what reopening does before anything is pressed: \(row.label)"
        )

        let rowButton = app.buttons["reopenDeliveryRowButton"]
        XCTAssertTrue(rowButton.exists)
        XCTAssertEqual(
            rowButton.label,
            "Reopen Delivery 1. It becomes active again, heading to the customer.",
            "and so does the control"
        )
        rowButton.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Reopening from history is confirmed")
        let confirm = alert.buttons.matching(identifier: "confirmReopenDeliveryButton").firstMatch
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(confirm.label, "Reopen Delivery 1", "The button repeats which delivery it acts on")
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Delivery 1 becomes active again, heading to the customer"
                )
            ).count > 0,
            "The confirmation says the delivery becomes active again rather than saying \"edit\""
        )
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["deliveryRecoveryUnavailable"].waitForExistence(timeout: 5),
            "The shift now records no delivered delivery, so there is nothing left to reopen"
        )
        app.buttons["closeDeliveryRecoveryButton"].tap()

        // And the running panel agrees: three cards, each with its own step.
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 3),
            "The reopened delivery is a card again"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app).label,
            "Delivery 1. Mark delivery completed",
            "at the step its own timestamps put it at"
        )
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app).label,
            "Delivery 2. Mark arrived at pickup",
            "and its siblings are exactly where they were"
        )
        XCTAssertFalse(
            app.buttons["reopenDeliveryButton"].exists,
            "The control goes with the last delivered delivery it could act on"
        )
    }

    /// A shift that has recorded no completion offers no way back from one.
    @MainActor
    func testRecoveryIsNotOfferedWithoutADeliveredDelivery() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reopenDeliveryButton"].exists, "Nothing is recorded, so nothing can be reopened")

        app.buttons["startDeliveryButton"].tap()
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1)
        )
        XCTAssertFalse(
            app.buttons["reopenDeliveryButton"].exists,
            "A delivery in progress has a card of its own; this is not the control for it"
        )
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
        XCTAssertTrue(
            scrollUntilHittable(rows(in: app).firstMatch, in: app),
            "The shift ends once nothing is running"
        )
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

        // Back up to the shift's own controls, which the delivery cards pushed
        // out of the list's rendered rows, the way the journey above does.
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 0))
        XCTAssertTrue(scrollToTop(reaching: app.buttons["endShiftButton"], in: app))
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

    // MARK: The actions a completed delivery offers

    /// The delivery carrying every correction offers all of them, each one
    /// tappable and each one given a column of its own.
    ///
    /// The defect this pins was a layout one: three controls sharing a single
    /// row left each about a third of a phone's width, and `Change Pickup Place`
    /// came out a word to a line. The assertions are therefore about the room
    /// each control is given rather than about where its words break. A control
    /// narrower than two-fifths of the screen is one of three in a row again,
    /// which is the state that produced the defect.
    ///
    /// Verified by mutation: putting the three back in one row fails this on the
    /// width assertion itself, at 104.7 points against the 160.8 it asks for,
    /// rather than on a timeout or on a wrapped word.
    ///
    /// The set is **six** on a delivered delivery in a finished shift, since the
    /// additional tips, the historical correction and the time correction all
    /// joined it. That is what the grid is for: each new action took the next
    /// cell rather than costing anything, and the widths below are the same
    /// widths. Six fills three even rows, so the odd case is pinned on the
    /// **cancelled** delivery further down, which offers five: the last control
    /// keeps its column instead of stretching across the row it has to itself,
    /// which is what keeps the left edge the same down the whole list.
    @MainActor
    func testCompletedDeliveryOffersEveryCorrectionWithRoomToReadIt() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        // The fixture's first delivery is the one with the whole set: it names a
        // place, that place has recorded history, it carries an amount, and it
        // is recorded as delivered in a shift that has ended.
        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app), "The delivery should be listed")

        let place = card.buttons["shiftDetailPickupPlaceButton"]
        let history = card.buttons["shiftDetailPickupHistoryButton"]
        let earnings = card.buttons["shiftDetailDeliveryEarningsButton"]
        let tips = card.buttons["shiftDetailDeliveryTipsButton"]
        let times = card.buttons["shiftDetailCorrectDeliveryTimesButton"]
        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]

        // Reaching the last of the six brings the others with it: they are the
        // five directly above it in the same card.
        XCTAssertTrue(scrollUntilHittable(correct, in: app), "Every action is reachable by scrolling")

        // Each one still names the delivery it acts on, which is what makes it
        // usable with several cards on screen and nothing to look at.
        XCTAssertEqual(place.label, "Change pickup place for Delivery 1")
        XCTAssertEqual(history.label, "Recorded pickup waits at \(Self.noodles)")
        XCTAssertEqual(earnings.label, "Edit gross earnings for Delivery 1")
        XCTAssertEqual(tips.label, "Add an additional tip to Delivery 1")
        XCTAssertTrue(
            times.label.hasPrefix("Correct the times Delivery 1 recorded."),
            "including the one that rewrites when the delivery happened: \(times.label)"
        )
        XCTAssertTrue(
            correct.label.hasPrefix("Correct Delivery 1 to cancelled."),
            "and the one that rewrites how it ended: \(correct.label)"
        )

        let width = app.windows.element(boundBy: 0).frame.width
        for action in [place, history, earnings, tips, times, correct] {
            XCTAssertTrue(action.isHittable, "Every action is tappable where it is: \(action.label)")
            XCTAssertGreaterThanOrEqual(
                action.frame.height,
                44,
                "An action keeps a standard touch target: \(action.label)"
            )
            XCTAssertGreaterThan(
                action.frame.width,
                width * 0.4,
                "An action gets a column rather than a third of a row: \(action.label)"
            )
        }

        // Two columns, not three squeezed controls and not a stack: the first
        // two sit on one line and the widths are the column's, not the words'.
        XCTAssertEqual(
            place.frame.minY,
            history.frame.minY,
            accuracy: 1,
            "The first two actions share a line"
        )
        XCTAssertGreaterThan(
            history.frame.minX,
            place.frame.maxX - 1,
            "And sit beside each other rather than overlapping"
        )
        XCTAssertEqual(
            place.frame.width,
            history.frame.width,
            accuracy: 1,
            "Both are the width of a column, whatever each is called"
        )

        // The second line holds the next two, in the same two columns, so the
        // left edge is the same down every delivery whatever each row offers.
        XCTAssertGreaterThan(earnings.frame.minY, place.frame.maxY - 1, "The third action is on the next line")
        XCTAssertEqual(
            earnings.frame.width,
            place.frame.width,
            accuracy: 1,
            "and is the width of a column"
        )
        XCTAssertEqual(earnings.frame.minX, place.frame.minX, accuracy: 1, "Aligned with the column above it")
        XCTAssertEqual(
            tips.frame.minY,
            earnings.frame.minY,
            accuracy: 1,
            "The fourth action shares the second line rather than starting a third"
        )
        XCTAssertEqual(tips.frame.minX, history.frame.minX, accuracy: 1, "in the second column")

        // The third line holds the two corrections, in the same two columns, so
        // six controls fill three even rows and no cell is left empty.
        XCTAssertGreaterThan(times.frame.minY, earnings.frame.maxY - 1, "The fifth action starts a third line")
        XCTAssertEqual(times.frame.minX, place.frame.minX, accuracy: 1, "in the first column")
        XCTAssertEqual(
            times.frame.width,
            place.frame.width,
            accuracy: 1,
            "at a column's width rather than the whole row's"
        )
        XCTAssertEqual(
            correct.frame.minY,
            times.frame.minY,
            accuracy: 1,
            "and the sixth shares that line rather than starting a fourth"
        )
        XCTAssertEqual(correct.frame.minX, history.frame.minX, accuracy: 1, "in the second column")

        // The odd count is now the **cancelled** delivery's: it offers five,
        // because nothing corrects how a cancelled delivery ended. The last
        // control keeps its column instead of stretching across the row it has
        // to itself, which is what keeps the left edge the same down the list.
        let cancelledCard = deliveryCard(containing: "Delivery 2, cancelled", in: app)
        let cancelledPlace = cancelledCard.buttons["shiftDetailPickupPlaceButton"]
        let cancelledTimes = cancelledCard.buttons["shiftDetailCorrectDeliveryTimesButton"]
        XCTAssertTrue(scrollUntilHittable(cancelledTimes, in: app), "A cancelled delivery's times are correctable")
        XCTAssertFalse(
            cancelledCard.buttons["shiftDetailCorrectToCancelledButton"].exists,
            "and nothing offers to correct how it ended, because it ended that way"
        )
        XCTAssertEqual(
            cancelledTimes.frame.minX,
            cancelledPlace.frame.minX,
            accuracy: 1,
            "The lone fifth control keeps the first column"
        )
        XCTAssertEqual(
            cancelledTimes.frame.width,
            cancelledPlace.frame.width,
            accuracy: 1,
            "at a column's width rather than the whole row's"
        )

        // And the controls still do what they did: the grid changed where they
        // are, not what they open.
        //
        // Back to a known top first, then down onto it. `earnings` belongs to
        // **Delivery 1** and the screen has just been scrolled past it to
        // Delivery 2's card, and `scrollUntilHittable` only ever searches
        // downward. Coming back up and descending again is also what keeps the
        // control clear of the navigation bar: an element that is merely
        // `isHittable` can still be parked under it, and the synthesized tap
        // then lands on the bar and opens nothing.
        XCTAssertTrue(
            scrollToTop(reaching: app.descendants(matching: .any)["shiftDetailEarnings"], in: app, swipes: 14),
            "The screen is back at the shift's own figures"
        )
        XCTAssertTrue(scrollUntilHittable(earnings, in: app), "Delivery 1's earnings action is reachable again")
        earnings.tap()
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The earnings editor still opens from its action")
        app.buttons["cancelDeliveryEarningsButton"].tap()
    }

    /// At an accessibility text size the same actions stack instead of
    /// compressing, and every one of them stays tappable.
    @MainActor
    func testCompletedDeliveryActionsStackAtAnAccessibilityTextSize() throws {
        let app = launchWithSeededHistory(atTextSize: Self.accessibilityXXXLTextSize)

        // The shift panel alone fills the screen at this size, so history is
        // below the fold and the row has to be scrolled to before it is tapped
        // rather than reached where an ordinary launch leaves it.
        let shift = rows(in: app).firstMatch
        XCTAssertTrue(scrollTo(shift, in: app, maxSwipes: 15), "A completed shift is listed, further down")
        XCTAssertTrue(scrollUntilHittable(shift, in: app, maxSwipes: 5), "And can be opened")
        shift.tap()

        // Every row is several times taller at this size, so the delivery log is
        // much further down the screen than it is by default.
        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app, maxSwipes: 30), "The delivery should be listed")

        let place = card.buttons["shiftDetailPickupPlaceButton"]
        let history = card.buttons["shiftDetailPickupHistoryButton"]
        let earnings = card.buttons["shiftDetailDeliveryEarningsButton"]
        let tips = card.buttons["shiftDetailDeliveryTipsButton"]
        let times = card.buttons["shiftDetailCorrectDeliveryTimesButton"]
        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]

        XCTAssertTrue(
            scrollUntilHittable(place, in: app, maxSwipes: 30),
            "The actions are reachable at an accessibility size too"
        )

        let width = app.windows.element(boundBy: 0).frame.width
        for action in [place, history, earnings, tips, times, correct] {
            XCTAssertTrue(action.exists, "Nothing is dropped to keep the card short")
            XCTAssertGreaterThan(
                action.frame.width,
                width * 0.7,
                "An action takes the width of the card rather than half of it: \(action.label)"
            )
        }

        // One column: the second action is under the first rather than beside
        // it, which is the card growing downwards instead of the words being
        // squeezed sideways.
        XCTAssertGreaterThan(
            history.frame.minY,
            place.frame.maxY - 1,
            "The grid becomes a single column rather than keeping two narrow ones"
        )
        XCTAssertEqual(history.frame.minX, place.frame.minX, accuracy: 1, "Still one aligned column")

        // Reached by scrolling, like anything else this far down a long screen.
        XCTAssertTrue(scrollUntilHittable(tips, in: app, maxSwipes: 10), "And every action is still tappable")
        XCTAssertGreaterThan(
            tips.frame.minY,
            earnings.frame.maxY - 1,
            "The fourth action is under the third, not beside it"
        )
        XCTAssertTrue(scrollUntilHittable(times, in: app, maxSwipes: 10))
        XCTAssertGreaterThan(
            times.frame.minY,
            tips.frame.maxY - 1,
            "the fifth under the fourth"
        )
        XCTAssertTrue(scrollUntilHittable(correct, in: app, maxSwipes: 10))
        XCTAssertGreaterThan(
            correct.frame.minY,
            times.frame.maxY - 1,
            "and the sixth under the fifth, all the way down"
        )
    }

    // MARK: Correcting a historical completion to a cancellation

    /// The whole journey, from a finished shift's own record.
    ///
    /// The claim is not only that the state changes. It is that the **time does
    /// not**: the instant the row printed beside `Delivered` is the instant it
    /// prints beside `Cancelled` afterwards, which is what keeps the shift's
    /// delivery active time and every figure over it where they were.
    @MainActor
    func testCorrectingAHistoricalCompletionToACancellation() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summary = app.staticTexts["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app), "The shift states how its deliveries ended")
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled")

        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app), "The delivered delivery is listed")
        let recordedTime = try XCTUnwrap(
            Self.time(after: "Delivered at", in: deliveryRow(containing: "Delivery 1, delivered", in: app).label),
            "The row states when it was recorded delivered"
        )

        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app), "and offers the correction")
        XCTAssertEqual(
            correct.label,
            """
            Correct Delivery 1 to cancelled. It stays a finished delivery, recorded as cancelled \
            instead of delivered.
            """,
            "The control names its subject and says the delivery stays finished"
        )
        correct.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "The correction is confirmed before anything is written")
        let confirm = alert.buttons.matching(identifier: "confirmCorrectToCancelledButton").firstMatch
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(confirm.label, "Correct Delivery 1", "The button repeats which delivery it acts on")
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Delivery 1 stays a finished delivery")
            ).count > 0,
            "The confirmation says the delivery stays finished rather than saying \"edit\""
        )
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "the time you recorded it as delivered becomes the time it was cancelled"
                )
            ).count > 0,
            "and says where the cancellation time comes from"
        )
        confirm.tap()

        let corrected = deliveryRow(containing: "Delivery 1, cancelled", in: app)
        XCTAssertTrue(corrected.waitForExistence(timeout: 5), "The delivery is recorded as cancelled")
        XCTAssertEqual(
            Self.time(after: "Cancelled at", in: corrected.label),
            recordedTime,
            "at exactly the instant it had recorded as its completion. Showed: \(corrected.label)"
        )
        XCTAssertNil(
            Self.time(after: "Delivered at", in: corrected.label),
            "and the completion is gone rather than kept beside it"
        )
        XCTAssertFalse(
            corrected.label.contains("Accepted to delivered"),
            "The interval that needed a completion goes with it"
        )
        XCTAssertTrue(
            corrected.label.contains("Picked up from \(Self.noodles)"),
            "The pickup place stays recorded"
        )
        XCTAssertTrue(
            corrected.label.contains("Gross earnings for Delivery 1"),
            "and so does the amount, which a cancelled delivery may truthfully carry"
        )

        // The shift itself is still a finished shift, and its counts have moved
        // by exactly one in each direction.
        XCTAssertTrue(scrollUpUntilHittable(summary, in: app), "The summary is above the log")
        XCTAssertEqual(
            summary.label,
            "1 delivery completed. 2 deliveries cancelled",
            "The completion became a cancellation, and nothing is in progress"
        )

        // A second correction is not offered, because the row it acted on is no
        // longer recorded as delivered.
        let correctedCard = deliveryCard(containing: "Delivery 1, cancelled", in: app)
        XCTAssertTrue(scrollTo(correctedCard, in: app))
        XCTAssertFalse(
            correctedCard.buttons["shiftDetailCorrectToCancelledButton"].exists,
            "A control that would always refuse is not offered"
        )
        XCTAssertTrue(
            correctedCard.buttons["shiftDetailDeliveryEarningsButton"].exists,
            "and the corrections that still apply are still there"
        )
    }

    /// Dismissing the confirmation writes nothing.
    @MainActor
    func testDismissingTheCancellationConfirmationChangesNothing() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app))
        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(
            deliveryRow(containing: "Delivery 1, delivered", in: app).waitForExistence(timeout: 5),
            "The delivery is exactly as it was"
        )
        XCTAssertFalse(
            deliveryRow(containing: "Delivery 1, cancelled", in: app).exists,
            "and nothing was written"
        )
    }

    /// A delivery the shift already records as cancelled has nothing to correct,
    /// and a running shift has a better correction of its own.
    @MainActor
    func testTheHistoricalCorrectionIsOfferedNowhereElse() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let cancelled = deliveryCard(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(cancelled, in: app), "The fixture records a cancelled delivery too")
        XCTAssertFalse(
            cancelled.buttons["shiftDetailCorrectToCancelledButton"].exists,
            "A cancelled delivery is already terminal as what it was"
        )

        goBack(in: app)

        // The running shift's own cards offer the lifecycle controls and the
        // reopening, and never this one: while a shift is running a mis-tapped
        // completion is reopened and finished properly.
        let app2 = launchWithActiveDelivery()
        XCTAssertTrue(app2.buttons["endShiftButton"].waitForExistence(timeout: 15), "The seeded shift is running")
        XCTAssertTrue(scrollTo(app2.buttons["reopenDeliveryButton"], in: app2), "Reopening is what is offered there")
        XCTAssertFalse(
            app2.buttons["shiftDetailCorrectToCancelledButton"].exists,
            "and the historical correction is not"
        )
    }

    /// Reads the time a row's spoken label states for one event.
    ///
    /// The row is one combined accessibility element, so its label is where the
    /// printed facts can be read back as a sentence. Returning `nil` for an
    /// event the row does not state is the point: it is how the journey asserts
    /// that the completion is **gone** rather than merely joined by a
    /// cancellation.
    private static func time(after event: String, in label: String) -> String? {
        guard let range = label.range(of: "\(event) ") else { return nil }
        let remainder = label[range.upperBound...]
        return String(remainder.prefix(while: { $0 != "." }))
    }

    // MARK: Correcting a recorded pause

    /// The whole journey, from a finished shift's own record: read the pause,
    /// correct where it ended, and watch the figure it feeds move.
    ///
    /// The claim is not only that the pause changes. It is that **exactly three
    /// figures move with it** — the paused time, the working time and the hourly
    /// rate — while the elapsed time, the delivery active time and the recorded
    /// amount stay where they were. Those are what a pause is, and is not,
    /// subtracted from.
    @MainActor
    func testCorrectingARecordedPauseFromAFinishedShift() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app), "The shift states its elapsed time")
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time")
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailPausedTime"].label,
            "50 minutes paused time, over 2 pauses"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailWorkingTime"].label,
            "3 hours, 10 minutes working time"
        )
        // The rates live below the pauses, so they are read on the way past and
        // the screen is brought back to the top before anything is tapped.
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        let perMileRate = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app), "The shift derives an hourly rate")
        let hourlyBefore = hourlyRate.label
        XCTAssertTrue(scrollTo(perMileRate, in: app))
        let perMileBefore = perMileRate.label
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))

        let row = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(scrollTo(row, in: app), "The shift lists the pauses it recorded")
        XCTAssertTrue(
            row.label.contains("30 minutes"),
            "and says how long each one was. Showed: \(row.label)"
        )

        let edit = pauseButton("editShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(edit, in: app), "Pause 1 offers its own correction")
        XCTAssertEqual(
            edit.label,
            "Edit Pause 1. Change when this pause started and ended",
            "The control names the pause it changes"
        )
        edit.tap()

        let summary = app.descendants(matching: .any)["shiftPauseEditorSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The editor opens on the pause as recorded")
        XCTAssertTrue(
            summary.label.hasPrefix("30 minutes paused"),
            "with the length it already has. Showed: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("working time becomes 3 hr, 10 min"),
            "and states the figure the driver is really changing. Showed: \(summary.label)"
        )

        // The driver resumed a quarter of an hour later than they recorded.
        setTime(minute: "45", ofPicker: "shiftPauseEndPicker", in: app)
        XCTAssertTrue(
            waitForLabel(summary, toContain: "45 minutes paused"),
            "The consequence is restated before anything is written. Showed: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("working time becomes 2 hr, 55 min"),
            "Showed: \(summary.label)"
        )
        app.buttons["shiftPauseEditorSaveButton"].tap()

        // Back on the shift, and the three figures a pause feeds have moved.
        let correctedRow = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(correctedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            correctedRow.label.contains("45 minutes"),
            "The pause records what the driver corrected it to. Showed: \(correctedRow.label)"
        )

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app), "The shift's own times are at the top")
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["shiftDetailPausedTime"], toContain: "1 hour, 5 minutes"),
            "The paused total is the corrected pause plus the one that did not move"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailWorkingTime"].label,
            "2 hours, 55 minutes working time",
            "and the working time is the elapsed time less it"
        )
        XCTAssertEqual(
            elapsed.label,
            "4 hours elapsed shift time",
            "The shift's own start and end did not move"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"].label,
            "30 minutes delivery active time",
            "and neither did the delivery it recorded"
        )
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertNotEqual(
            hourlyRate.label,
            hourlyBefore,
            "The rate that divides by working time follows the correction"
        )
        XCTAssertTrue(scrollTo(perMileRate, in: app))
        XCTAssertEqual(
            perMileRate.label,
            perMileBefore,
            "and the rate a pause has nothing to do with is exactly as it was"
        )
    }

    /// Leaving the editor writes nothing at all.
    @MainActor
    func testCancellingAPauseCorrectionChangesNothing() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let edit = pauseButton("editShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftPauseEditorSummary"].waitForExistence(timeout: 5))
        setTime(minute: "45", ofPicker: "shiftPauseEndPicker", in: app)
        app.buttons["shiftPauseEditorCancelButton"].tap()

        let row = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(
            row.label.contains("30 minutes"),
            "The pause is exactly as it was recorded. Showed: \(row.label)"
        )
    }

    /// A pause cannot be corrected over work the shift recorded, and the refusal
    /// says which fact it collided with.
    @MainActor
    func testAPauseCannotBeCorrectedOverADelivery() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        // Pause 2 begins a quarter of an hour after the shift's one delivery
        // ended, so moving its start back by half an hour puts it inside that
        // delivery.
        let edit = pauseButton("editShiftPauseButton", containing: "Pause 2", in: app)
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftPauseEditorSummary"].waitForExistence(timeout: 5))
        setTime(minute: "15", ofPicker: "shiftPauseStartPicker", in: app)

        // `firstMatch`, because a SwiftUI `Label` is a glyph and a text under one
        // identifier and reading `.label` off a query matching both is an error.
        let refusal = app.descendants(matching: .any)
            .matching(identifier: "shiftPauseEditorRefusal")
            .firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "The stretch is refused rather than saved")
        XCTAssertTrue(
            refusal.label.contains("A delivery was in progress during that time"),
            "and the refusal says which recorded fact it collided with. Showed: \(refusal.label)"
        )
        XCTAssertFalse(
            app.buttons["shiftPauseEditorSaveButton"].isEnabled,
            "Saving is withheld rather than offered and then refused"
        )

        app.buttons["shiftPauseEditorCancelButton"].tap()
        let row = pauseRow(containing: "Pause 2", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("20 minutes"), "Showed: \(row.label)")
    }

    /// Deleting a pause recorded by mistake, which makes the shift's working
    /// time longer rather than shorter.
    @MainActor
    func testDeletingAPauseRecordedByMistake() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let delete = pauseButton("deleteShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        XCTAssertEqual(
            delete.label,
            "Delete Pause 1. Record that this pause did not happen",
            "The control says what deleting a pause means rather than only that a row goes"
        )
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Deleting is confirmed before anything is written")
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "working time becomes 30 min longer")
            ).count > 0,
            "The confirmation states the direction the working time moves"
        )
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "route recorded during it is not changed")
            ).count > 0,
            "and that the route is not touched"
        )
        let confirm = alert.buttons.matching(identifier: "confirmDeleteShiftPauseButton").firstMatch
        XCTAssertEqual(confirm.label, "Delete Pause 1", "The button repeats which pause it acts on")
        confirm.tap()

        // One pause left, and it is renumbered, which is why nothing acts on a
        // pause by its number.
        let remaining = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertTrue(
            remaining.label.contains("20 minutes"),
            "The pause that is left is the one that was second. Showed: \(remaining.label)"
        )
        XCTAssertFalse(pauseRow(containing: "Pause 2", in: app).exists, "and there is no second pause now")

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["shiftDetailWorkingTime"], toContain: "3 hours, 40 minutes"),
            "The working time grew by exactly the deleted pause"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailPausedTime"].label,
            "20 minutes paused time, over 1 pause"
        )
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time", "The shift itself is untouched")
    }

    /// Dismissing the confirmation writes nothing.
    @MainActor
    func testCancellingAPauseDeletionKeepsThePause() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let delete = pauseButton("deleteShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()

        // Pause 1 first, because it is the row the screen is already on; Pause 2
        // sits below it and has to be scrolled to. A `List` does not render a row
        // it has scrolled past, so asserting its existence where the screen
        // happens to be left is an assertion about the scroll position rather
        // than about the store.
        XCTAssertTrue(
            pauseRow(containing: "Pause 1", in: app).label.contains("30 minutes"),
            "The pause the driver did not delete is untouched"
        )
        XCTAssertTrue(
            scrollTo(pauseRow(containing: "Pause 2", in: app), in: app),
            "Both pauses are still there"
        )
    }

    /// Recording a pause the driver took and never tapped anything for.
    ///
    /// It opens refused rather than pre-filled, because DashPilot observed
    /// nothing about the break and has nothing to propose.
    @MainActor
    func testAddingAPauseThatWasNeverRecorded() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let add = app.buttons["addMissedPauseButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        XCTAssertEqual(add.label, "Add a pause you did not record during the shift")
        add.tap()

        // `firstMatch`, because a SwiftUI `Label` is a glyph and a text under one
        // identifier and reading `.label` off a query matching both is an error.
        let refusal = app.descendants(matching: .any)
            .matching(identifier: "shiftPauseEditorRefusal")
            .firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "Nothing is suggested, so it opens with nothing valid")
        XCTAssertTrue(
            refusal.label.contains("A pause has to end after it started"),
            "Showed: \(refusal.label)"
        )
        XCTAssertFalse(app.buttons["shiftPauseEditorSaveButton"].isEnabled)

        // Five minutes inside the shift's first hour, which is before its first
        // pause and long before its delivery. Both pickers open on the shift's
        // own start, so only the minutes are moved: the hour a shift starts at
        // depends on the machine's time zone, and a journey that typed one would
        // be asserting where the machine is.
        setTime(minute: "50", ofPicker: "shiftPauseStartPicker", in: app)
        setTime(minute: "55", ofPicker: "shiftPauseEndPicker", in: app)

        let summary = app.descendants(matching: .any)["shiftPauseEditorSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The stretch is now one the shift can record")
        XCTAssertTrue(summary.label.hasPrefix("5 minutes paused"), "Showed: \(summary.label)")
        app.buttons["shiftPauseEditorSaveButton"].tap()

        // Numbered by when it began, so a pause added before the two recorded
        // ones is `Pause 1` and the others move down.
        let added = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(added.waitForExistence(timeout: 5), "The shift records a third pause")
        XCTAssertTrue(
            added.label.contains("5 minutes"),
            "and it is first, because it began first. Showed: \(added.label)"
        )
        XCTAssertTrue(pauseRow(containing: "Pause 3", in: app).exists, "There are three of them now")

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["shiftDetailPausedTime"], toContain: "over 3 pauses"),
            "The shift counts three pauses now"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailWorkingTime"].label,
            "3 hours, 5 minutes working time",
            "and the added five minutes came out of the working time"
        )
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time", "The shift's own times did not move")
    }

    /// A shift that records no pause still offers to record one, and says so
    /// rather than showing an empty section.
    @MainActor
    func testAShiftWithNoPausesStillOffersToRecordOne() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let none = app.staticTexts["shiftDetailNoPauses"]
        XCTAssertTrue(scrollTo(none, in: app), "The section says the shift recorded no pause")
        XCTAssertEqual(none.label, "No pauses recorded")
        XCTAssertTrue(
            app.buttons["addMissedPauseButton"].exists,
            "and still offers the one correction a shift with no pauses needs"
        )
        XCTAssertFalse(app.buttons["editShiftPauseButton"].exists, "There is nothing to edit")
        XCTAssertFalse(app.buttons["deleteShiftPauseButton"].exists, "and nothing to delete")
    }

    /// None of it is offered while a shift is running, which is where the driver
    /// may be at a wheel.
    @MainActor
    func testPauseCorrectionIsNotOfferedOnARunningShift() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 5), "The shift is running")
        for identifier in ["editShiftPauseButton", "deleteShiftPauseButton", "addMissedPauseButton"] {
            XCTAssertFalse(app.buttons[identifier].exists, "\(identifier) is not offered on a running shift")
        }

        app.buttons["pauseShiftButton"].tap()
        XCTAssertTrue(app.buttons["resumeShiftButton"].waitForExistence(timeout: 5), "and now it is paused")
        for identifier in ["editShiftPauseButton", "deleteShiftPauseButton", "addMissedPauseButton"] {
            XCTAssertFalse(
                app.buttons[identifier].exists,
                "\(identifier) is not offered on a paused shift either: the open pause is Resume's and End's"
            )
        }
    }

    // MARK: Correcting a shift's end time

    /// The whole journey: open a shift DashPilot recorded as ending late,
    /// correct the end, agree to lose the route recorded afterwards, and watch
    /// the three figures that depend on the boundary move.
    ///
    /// The claim is not only that the end changes. It is that the **mileage is
    /// measured again** rather than reduced in proportion: the shift loses one
    /// of its three equal capture sessions, so the honest answer is `4.5 mi` and
    /// a figure scaled by the time removed would be about `5.6 mi`.
    @MainActor
    func testCorrectingAShiftThatDashPilotRecordedAsEndingLate() throws {
        let app = launchWithLateEndHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app), "The shift states its elapsed time")
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time")

        // The rate and the route live below, in that order, so they are read on
        // the way past; the correction is further down still, with the others.
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(hourlyRate.label.hasPrefix("$27.27"), "Showed: \(hourlyRate.label)")

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app), "The shift states what its route recorded")
        XCTAssertTrue(mileage.label.contains("6.7 miles"), "Showed: \(mileage.label)")
        let segments = app.staticTexts["shiftDetailCaptureSegments"]
        XCTAssertTrue(segments.label.contains("3"), "Three capture segments. Showed: \(segments.label)")

        let correct = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app), "The shift offers to correct its end")
        XCTAssertEqual(
            correct.label,
            "Correct the time this shift ended",
            "The control says which fact it changes"
        )
        correct.tap()

        let summary = app.descendants(matching: .any)["shiftEndCorrectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The editor opens on the end as recorded")
        XCTAssertTrue(
            summary.label.hasPrefix("3 hours, 40 minutes elapsed"),
            "with the length the shift already has. Showed: \(summary.label)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["shiftEndCorrectionRecordedEnd"].exists,
            "and says what the recorded end is, so the picker moving does not lose it"
        )

        // The driver actually stopped twenty minutes before DashPilot recorded it.
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertTrue(
            waitForLabel(summary, toContain: "3 hours, 20 minutes elapsed"),
            "The consequence is restated before anything is written. Showed: \(summary.label)"
        )

        let warning = app.descendants(matching: .any)
            .matching(identifier: "shiftEndCorrectionRouteWarning")
            .firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "The destructive part is stated on the sheet")
        XCTAssertTrue(
            warning.label.contains("10 recorded positions"),
            "with the number of positions that go. Showed: \(warning.label)"
        )
        XCTAssertTrue(
            warning.label.contains("not reduced by the same share as the time"),
            "and it refuses the proportional reading outright. Showed: \(warning.label)"
        )

        app.buttons["shiftEndCorrectionSaveButton"].tap()

        // `firstMatch`, because the alert presents the button nested inside
        // itself and both elements carry the identifier.
        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Destroying recorded route is confirmed first")
        confirm.tap()

        // Back on the shift, with every figure the boundary feeds moved. The
        // corrections are below everything they change, so the screen goes back
        // to the top and reads down.
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(
            waitForLabel(elapsed, toContain: "3 hours, 20 minutes"),
            "The shift records the end the driver corrected it to. Showed: \(elapsed.label)"
        )
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(
            waitForLabel(hourlyRate, toContain: "$30.00"),
            "and the hourly figure divides by the corrected working time. Showed: \(hourlyRate.label)"
        )
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(
            waitForLabel(mileage, toContain: "4.5 miles"),
            "The mileage is what the positions that remain support. Showed: \(mileage.label)"
        )
        XCTAssertFalse(
            mileage.label.contains("5.6 miles"),
            "and not the route's distance scaled by the time removed"
        )
        XCTAssertTrue(
            waitForLabel(app.staticTexts["shiftDetailCaptureSegments"], toContain: "2"),
            "The third segment left with its positions"
        )
    }

    /// Declining the confirmation leaves the shift and its whole route exactly
    /// as they were.
    @MainActor
    func testDecliningTheRouteWarningKeepsTheShiftAsRecorded() throws {
        let app = launchWithLateEndHistory()
        openFirstShift(in: app)

        let correct = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        app.buttons["shiftEndCorrectionSaveButton"].tap()

        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        // The alert's own Cancel, not the sheet's: the sheet's says which shift
        // it is keeping, so matching the bare word reaches only this one.
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5),
            "The sheet stays open with the time the driver chose"
        )
        app.buttons["shiftEndCorrectionCancelButton"].tap()

        // The figures are above the corrections, so the screen goes back up.
        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time", "Nothing at all was written")
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("6.7 miles"), "and no position was deleted. Showed: \(mileage.label)")
    }

    /// An end before something the shift's deliveries recorded is refused, and
    /// the refusal says which recorded fact it collided with.
    @MainActor
    func testAnEndCannotBeCorrectedOverRecordedDeliveryWork() throws {
        let app = launchWithLateEndHistory()
        openFirstShift(in: app)

        let correct = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        // The fixture's one delivery was delivered ten minutes after the hour,
        // so five minutes past it is inside recorded work.
        setTime(minute: "05", ofPicker: "shiftEndCorrectionPicker", in: app)

        // `firstMatch`, because a SwiftUI `Label` is a glyph and a text under
        // one identifier, and reading `.label` off a query matching both is an
        // error.
        let refusal = app.descendants(matching: .any)
            .matching(identifier: "shiftEndCorrectionRefusal")
            .firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "The instant is refused rather than saved")
        XCTAssertTrue(
            refusal.label.hasPrefix("Delivery 1 has Delivered recorded at "),
            "and the refusal names the delivery and the event it collided with. Showed: \(refusal.label)"
        )
        XCTAssertTrue(
            refusal.label.contains("after the proposed shift end"),
            "rather than leaving the driver to find it. Showed: \(refusal.label)"
        )
        XCTAssertFalse(
            app.buttons["shiftEndCorrectionSaveButton"].isEnabled,
            "Saving is withheld rather than offered and then refused"
        )

        app.buttons["shiftEndCorrectionCancelButton"].tap()
        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time")
    }

    /// Moving the end **later** adds time and adds no mileage, and the sheet
    /// says so before it is saved.
    @MainActor
    func testALaterEndAddsTimeAndNoMileage() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app), "The shift states what its route recorded")
        let mileageBefore = mileage.label

        // The corrections sit below every figure, so the helper keeps going down.
        let correct = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app), "The shift offers to correct its end")
        correct.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5),
            "The editor opens on the end as recorded"
        )
        setTime(minute: "30", ofPicker: "shiftEndCorrectionPicker", in: app)

        let note = app.descendants(matching: .any)
            .matching(identifier: "shiftEndCorrectionRouteWarning")
            .firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "The sheet says what a longer shift does to the route")
        XCTAssertTrue(
            note.label.contains("No route or mileage is added"),
            "which is nothing at all. Showed: \(note.label)"
        )
        app.buttons["shiftEndCorrectionSaveButton"].tap()
        XCTAssertFalse(
            app.buttons["confirmShiftEndCorrectionButton"].firstMatch.waitForExistence(timeout: 2),
            "Nothing is destroyed, so nothing is confirmed"
        )

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(scrollTo(mileage, in: app), "The route section is still there to read")
        XCTAssertEqual(
            mileage.label,
            mileageBefore,
            "Not one metre was invented for the stretch the shift gained"
        )
    }

    /// The correction is not offered while a shift is running, which is where
    /// the driver may be at a wheel.
    @MainActor
    func testEndCorrectionIsNotOfferedOnARunningShift() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 5), "The shift is running")
        XCTAssertFalse(
            app.buttons["correctShiftEndButton"].exists,
            "A shift with no recorded end has none to correct, and End is what records one"
        )
    }

    // MARK: Correcting a completed delivery's recorded times

    /// The whole journey: open a delivery DashPilot recorded as delivered two
    /// hours after the food reached the door, correct the completion, and watch
    /// the two figures derived from it move while the route stays exactly as it
    /// was recorded.
    @MainActor
    func testCorrectingADeliveryRecordedAfterTheAppCameBack() throws {
        let app = launchWithLateDeliveryHistory()
        openFirstShift(in: app)

        // The mileage is read first and re-read at the end: the whole promise of
        // this correction is that it does not touch the route.
        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app), "The shift states what its route recorded")
        let mileageBefore = mileage.label
        XCTAssertTrue(mileageBefore.contains("6.7 miles"), "Showed: \(mileageBefore)")

        let row = app.descendants(matching: .any)["shiftDetailDeliveryRow"].firstMatch
        XCTAssertTrue(scrollTo(row, in: app), "The delivery is in the shift's record")
        XCTAssertTrue(
            row.label.contains("Accepted to delivered 1 hour, 30 minutes"),
            "with the duration its late completion implies. Showed: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("$8.00 earned per recorded delivery hour"),
            "and the hourly figure over it. Showed: \(row.label)"
        )

        let correct = app.buttons["shiftDetailCorrectDeliveryTimesButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app), "The delivery offers to correct its times")
        XCTAssertTrue(
            correct.label.hasPrefix("Correct the times Delivery 1 recorded"),
            "The control says which delivery it changes. Showed: \(correct.label)"
        )
        correct.tap()

        let summary = app.descendants(matching: .any)["deliveryTimeCorrectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The editor opens on the times as recorded")
        XCTAssertTrue(
            summary.label.contains("1 hour, 30 minutes"),
            "with the figures they produce. Showed: \(summary.label)"
        )

        let note = app.descendants(matching: .any)
            .matching(identifier: "deliveryTimeCorrectionRouteNotice")
            .firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "and says what it will not touch")
        XCTAssertTrue(
            note.label.contains("recorded mileage are not changed"),
            "which is the route. Showed: \(note.label)"
        )

        // The order really reached the door fifteen minutes past the hour.
        setTime(minute: "15", ofPicker: "deliveryTimeCorrectionPicker.delivered", in: app)
        XCTAssertTrue(
            waitForLabel(summary, toContain: "1 hour, 15 minutes"),
            "The consequence is restated before anything is written. Showed: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("$9.60"),
            "and so is the hourly figure it moves. Showed: \(summary.label)"
        )

        app.buttons["deliveryTimeCorrectionSaveButton"].tap()

        XCTAssertTrue(scrollTo(row, in: app), "Back on the shift's record")
        XCTAssertTrue(
            waitForLabel(row, toContain: "Accepted to delivered 1 hour, 15 minutes"),
            "The delivery records the completion the driver corrected it to. Showed: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("$9.60 earned per recorded delivery hour"),
            "and the rate divides by the corrected lifecycle. Showed: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("Gross earnings for Delivery 1, $12.00"),
            "over the amount that did not move. Showed: \(row.label)"
        )
        XCTAssertTrue(
            row.label.contains("Waited at pickup 5 minutes"),
            "and the wait, whose two ends did not move either. Showed: \(row.label)"
        )
        XCTAssertTrue(
            row.label.hasPrefix("Delivery 1, delivered"),
            "The delivery is still terminal, and terminal the same way. Showed: \(row.label)"
        )

        // Back to the top and then down again: the route section sits **above**
        // the deliveries, and the scroll helper that walks down cannot reach it
        // from here. This is the pair the end-correction journeys already use.
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertEqual(
            mileage.label,
            mileageBefore,
            "and not one metre of recorded route moved with the times"
        )
    }

    /// A time that would put one recorded event before another is refused, and
    /// the refusal names the event the driver has to correct as well.
    @MainActor
    func testADeliveryTimeThatBreaksTheLifecycleOrderIsRefused() throws {
        let app = launchWithLateDeliveryHistory()
        openFirstShift(in: app)

        let correct = app.buttons["shiftDetailCorrectDeliveryTimesButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()

        XCTAssertTrue(app.descendants(matching: .any)["deliveryTimeCorrectionSummary"].waitForExistence(timeout: 5))

        // The pickup was recorded ten minutes past the hour and the arrival at
        // five, so two minutes past would have the order collected before the
        // driver reached the counter.
        setTime(minute: "02", ofPicker: "deliveryTimeCorrectionPicker.pickedUp", in: app)

        // `firstMatch`, because a SwiftUI `Label` is a glyph and a text under
        // one identifier, and reading `.label` off a query matching both is an
        // error.
        let refusal = app.descendants(matching: .any)
            .matching(identifier: "deliveryTimeCorrectionRefusal")
            .firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "The time is refused rather than saved")
        XCTAssertTrue(
            refusal.label.hasPrefix("Picked up cannot be earlier than arrived at the pickup"),
            "and the refusal names the fact it collided with. Showed: \(refusal.label)"
        )
        XCTAssertTrue(
            refusal.label.contains("correct arrived at the pickup as well"),
            "and says that fact is corrected rather than moved out of the way. Showed: \(refusal.label)"
        )
        XCTAssertFalse(
            app.buttons["deliveryTimeCorrectionSaveButton"].isEnabled,
            "Saving is withheld rather than offered and then refused"
        )

        app.buttons["deliveryTimeCorrectionCancelButton"].tap()

        let row = app.descendants(matching: .any)["shiftDetailDeliveryRow"].firstMatch
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(
            row.label.contains("Waited at pickup 5 minutes"),
            "Nothing at all was written, and above all the arrival was not moved. Showed: \(row.label)"
        )
    }

    /// The real recovery, end to end.
    ///
    /// DashPilot became unreachable near the end of a shift. The remaining work
    /// was recorded once a new build was installed, so both the delivery's
    /// completion and the shift's own end are late. Correcting the end alone is
    /// refused, because the delivery records work after the proposed end — and
    /// the refusal says **which** delivery and **which** event, which is the
    /// whole of what the driver needs. They correct that, and the same end
    /// correction is then accepted and trims the route as it always did.
    @MainActor
    func testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs() throws {
        let app = launchWithLateDeliveryHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app))
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time")

        // 1. The end correction is refused.
        let correctEnd = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app))
        correctEnd.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)

        // 2. And it identifies the blocking delivery and event.
        let refusal = app.descendants(matching: .any)
            .matching(identifier: "shiftEndCorrectionRefusal")
            .firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "The end is refused")
        XCTAssertTrue(
            refusal.label.hasPrefix("Delivery 1 has Delivered recorded at "),
            "and says which delivery and which event block it. Showed: \(refusal.label)"
        )
        XCTAssertTrue(
            refusal.label.contains("Open that delivery and correct its times"),
            "and where to go next. Showed: \(refusal.label)"
        )
        XCTAssertFalse(app.buttons["shiftEndCorrectionSaveButton"].isEnabled)
        app.buttons["shiftEndCorrectionCancelButton"].tap()

        // 3 and 4. The driver opens that delivery and corrects it. The delivery
        // log is above the shift's corrections, so the screen goes back up first.
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        let correctTimes = app.buttons["shiftDetailCorrectDeliveryTimesButton"]
        XCTAssertTrue(scrollUntilHittable(correctTimes, in: app, maxSwipes: 15))
        correctTimes.tap()

        XCTAssertTrue(app.descendants(matching: .any)["deliveryTimeCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "15", ofPicker: "deliveryTimeCorrectionPicker.delivered", in: app)
        app.buttons["deliveryTimeCorrectionSaveButton"].tap()

        let row = app.descendants(matching: .any)["shiftDetailDeliveryRow"].firstMatch
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(
            waitForLabel(row, toContain: "Accepted to delivered 1 hour, 15 minutes"),
            "The delivery no longer records work after the end the driver wants. Showed: \(row.label)"
        )

        // 5. The same correction is retried.
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app))
        correctEnd.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "shiftEndCorrectionRefusal")
                .firstMatch
                .exists,
            "and it is no longer refused"
        )
        app.buttons["shiftEndCorrectionSaveButton"].tap()

        // 6. And it trims the route and rederives the figures exactly as it
        //    always has. `firstMatch`, because the alert presents the button
        //    nested inside itself.
        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Destroying recorded route is still confirmed first")
        confirm.tap()

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(
            waitForLabel(elapsed, toContain: "3 hours, 20 minutes"),
            "The shift records the end the driver corrected it to. Showed: \(elapsed.label)"
        )
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(
            waitForLabel(hourlyRate, toContain: "$30.00"),
            "and the hourly figure divides by the corrected working time. Showed: \(hourlyRate.label)"
        )
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(
            waitForLabel(mileage, toContain: "4.5 miles"),
            "measured again from the positions that remain. Showed: \(mileage.label)"
        )
    }

    /// The correction is not offered while a shift is running, which is where
    /// the driver may be at a wheel and where a mis-tapped completion is
    /// reopened and finished properly instead.
    @MainActor
    func testDeliveryTimeCorrectionIsNotOfferedOnARunningShift() throws {
        let app = launchWithActiveDelivery()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 10), "The shift is running")
        XCTAssertFalse(
            app.buttons["shiftDetailCorrectDeliveryTimesButton"].exists,
            "A delivery on a running shift has no shift window to be corrected inside"
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

    // MARK: Additional tips, from detail

    /// Records a tip a delivery received outside the platform's own amount, and
    /// reads the three figures back off the row.
    ///
    /// The whole flow happens after the driving, so the journey drives a
    /// delivery to completion first and asserts the running shift offered no tip
    /// control at any point.
    @MainActor
    func testAddsAnAdditionalTipToAFinishedDelivery() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("10.00", in: app)
        XCTAssertTrue(waitForLabel(row, toContain: "Gross earnings for Delivery 1, $10.00"))

        let tipsButton = app.buttons["shiftDetailDeliveryTipsButton"].firstMatch
        XCTAssertTrue(tipsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(
            tipsButton.label,
            "Add an additional tip to Delivery 1",
            "The control names the delivery it acts on, and says there are none yet"
        )
        tipsButton.tap()

        addTip("5.00", method: "Cash", in: app)

        // The three figures, stated in the order they add up in.
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsPlatformPay"], toContain: "$10.00")
        )
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsAdditionalTotal"], toContain: "$5.00")
        )
        let total = app.descendants(matching: .any)["deliveryTipsEffectiveTotal"]
        XCTAssertTrue(waitForLabel(total, toContain: "$15.00"), "Showed: \(total.label)")
        XCTAssertTrue(
            total.label.contains("platform pay and tips together"),
            "The spoken sentence says what the figure is made of: \(total.label)"
        )

        app.buttons["closeDeliveryTipsButton"].tap()

        // And the row itself, where the platform amount is now named as one half.
        XCTAssertTrue(waitForLabel(row, toContain: "Platform pay for Delivery 1, $10.00"))
        XCTAssertTrue(row.label.contains("not the whole of what it paid"), "Showed: \(row.label)")
        XCTAssertTrue(row.label.contains("1 additional tip for Delivery 1, $5.00"), "Showed: \(row.label)")
        XCTAssertTrue(row.label.contains("Total recorded for Delivery 1, $15.00"), "Showed: \(row.label)")
        XCTAssertEqual(
            app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.label,
            "Edit the 1 additional tip recorded for Delivery 1"
        )
    }

    /// Two tips of different methods stay two records, and the delivery reports
    /// all three of them.
    @MainActor
    func testADeliveryCanHoldSeveralAdditionalTips() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("10.00", in: app)

        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        addTip("3.00", method: "Cash", in: app)
        addTip("5.00", method: "Platform", in: app)

        XCTAssertTrue(
            waitForCount(app.descendants(matching: .any).matching(identifier: "deliveryTipRow"), toEqual: 2),
            "Two tips are two records rather than one doubled one"
        )

        let rows = app.descendants(matching: .any).matching(identifier: "deliveryTipRow")
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("$3.00"))
        XCTAssertTrue(
            rows.element(boundBy: 0).label.contains("by cash"),
            "Each says how it arrived: \(rows.element(boundBy: 0).label)"
        )
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("$5.00"))
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("by platform"))

        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsEffectiveTotal"], toContain: "$18.00")
        )

        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "2 additional tips for Delivery 1, $8.00"))
        XCTAssertTrue(row.label.contains("Total recorded for Delivery 1, $18.00"), "Showed: \(row.label)")
    }

    /// Correcting one tip replaces it, and removing one takes the record away
    /// while leaving the platform amount exactly as it was.
    @MainActor
    func testEditsAndRemovesAnAdditionalTip() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("10.00", in: app)

        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        addTip("3.00", method: "Cash", in: app)

        // Editing opens on the stored amount and replaces it.
        let editTip = app.buttons["editDeliveryTipButton"].firstMatch
        XCTAssertTrue(editTip.waitForExistence(timeout: 5))
        XCTAssertEqual(editTip.label, "Edit tip 1 for Delivery 1", "The control names which tip it acts on")
        editTip.tap()
        let field = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "3", "The editor opens on the stored amount")
        clear(field, in: app)
        field.typeText("4.50")
        app.buttons["saveDeliveryTipButton"].tap()

        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsEffectiveTotal"], toContain: "$14.50")
        )

        // Removing it takes the record away rather than reducing it to nothing.
        XCTAssertTrue(waitForDisappearance(of: app.textFields["deliveryTipAmountField"]))
        app.buttons["editDeliveryTipButton"].firstMatch.tap()
        let remove = app.buttons["removeDeliveryTipButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.label, "Remove this additional tip from Delivery 1")
        remove.tap()

        XCTAssertTrue(
            waitForCount(app.descendants(matching: .any).matching(identifier: "deliveryTipRow"), toEqual: 0)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["deliveryTipsAdditionalTotal"].exists,
            "No tip recorded is not a tip of nothing, so there is no total of them"
        )
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsPlatformPay"], toContain: "$10.00"),
            "And what the platform paid is untouched by any of it"
        )

        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "Gross earnings for Delivery 1, $10.00"))
        XCTAssertFalse(row.label.contains("additional tip"), "Showed: \(row.label)")
    }

    /// A tip of nothing is refused, in the words of a tip, and nothing is
    /// recorded.
    @MainActor
    func testATipOfNothingIsRefused() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("10.00", in: app)

        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        app.buttons["addDeliveryTipButton"].tap()

        let field = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("0")
        app.buttons["saveDeliveryTipButton"].tap()

        let message = app.descendants(matching: .any)["deliveryTipValidationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(
            message.label.lowercased().contains("more than nothing"),
            "The refusal says what a tip has to be: \(message.label)"
        )

        app.buttons["cancelDeliveryTipButton"].tap()
        XCTAssertTrue(
            waitForCount(app.descendants(matching: .any).matching(identifier: "deliveryTipRow"), toEqual: 0)
        )
    }

    /// A delivery carrying tips and no platform amount says there is no total,
    /// rather than showing the tips as what it earned.
    @MainActor
    func testTipsWithoutAPlatformAmountStateNoTotal() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))

        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        addTip("5.00", method: "Cash", in: app)

        XCTAssertTrue(
            waitForLabel(
                app.descendants(matching: .any)["deliveryTipsPlatformPay"],
                toContain: "No platform pay recorded for Delivery 1"
            )
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["deliveryTipsEffectiveTotal"].exists,
            "There is no total, because half of what the delivery paid was never written down"
        )
        let notice = app.descendants(matching: .any)["deliveryTipsNoPlatformPayNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("no total"), "Showed: \(notice.label)")

        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "1 additional tip for Delivery 1, $5.00"))
        XCTAssertFalse(row.label.contains("Total recorded"), "Showed: \(row.label)")
    }

    /// The earnings editor states the tips already recorded, so a driver is not
    /// invited to add them into the platform amount a second time.
    @MainActor
    func testTheEarningsEditorSaysTheTipsAreAlreadyRecorded() throws {
        let app = launchWithEmptyStore()
        completeAShiftWithADelivery(in: app)
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("10.00", in: app)

        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        addTip("5.00", method: "Cash", in: app)
        app.buttons["closeDeliveryTipsButton"].tap()

        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let stated = app.descendants(matching: .any)["deliveryEarningsAdditionalTips"]
        XCTAssertTrue(stated.waitForExistence(timeout: 5))
        XCTAssertTrue(stated.label.contains("$5.00"), "Showed: \(stated.label)")
        XCTAssertEqual(
            app.textFields["deliveryEarningsAmountField"].value as? String,
            "10",
            "The field holds the platform amount alone, with the tip stated beside it rather than inside it"
        )
        app.buttons["cancelDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(row, toContain: "Total recorded for Delivery 1, $15.00"))
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
            first.label.contains("$35.40 earned per recorded delivery hour"),
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
        // The first card is above the third, and the scroll helpers only walk
        // down, so the screen goes back to the top first.
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["shiftDetailEarnings"], in: app))
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("$14.75"),
            "One delivery's amount is its own, however far the lifecycles overlap: \(first.label)"
        )
    }

    /// A finished delivery states what it paid per hour of its own lifecycle,
    /// and that figure is nobody else's.
    ///
    /// The fixture makes all four claims assertable at once. Delivery 1 ran
    /// twenty-five minutes for $14.75, so $35.40 an hour. Delivery 3 ran thirty
    /// minutes for $9.50, so $19.00 an hour, and it was accepted while delivery
    /// 2 was still open: two lifecycles over the same minutes, two independent
    /// figures, neither dividing shared time between them. Delivery 2 was
    /// cancelled and has no such figure at all, because there is no completion
    /// to measure to.
    ///
    /// The rate is read off the row's own accessibility label, which is what a
    /// VoiceOver user hears and where the denominator is named in full. "Per
    /// hour" alone would be heard as a wage.
    @MainActor
    func testACompletedDeliveryStatesItsOwnEffectiveHourlyRate() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            first.label.contains("$35.40 earned per recorded delivery hour"),
            "$14.75 over twenty-five minutes, with the denominator named: \(first.label)"
        )

        let second = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertFalse(
            second.label.contains("per recorded delivery hour"),
            "There is no such thing as a cancelled hourly rate: \(second.label)"
        )

        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(
            third.label.contains("$19.00 earned per recorded delivery hour"),
            "$9.50 over its own thirty minutes, not over the time it shared with delivery 2: \(third.label)"
        )
    }

    /// A tip recorded against a finished delivery moves its hourly figure
    /// straight away, and moves nobody else's.
    ///
    /// $14.75 over twenty-five minutes is $35.40 an hour; a $5.00 cash tip makes
    /// it $19.75 over the same twenty-five minutes, which is $47.40. Nothing is
    /// recalculated on a schedule and nothing is stored: the figure is derived
    /// from the rows every time the screen reads it.
    @MainActor
    func testRecordingATipMovesThatDeliverysHourlyRate() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("$35.40 earned per recorded delivery hour"), "Showed: \(first.label)")

        // From this delivery's own card rather than firstMatch over the screen,
        // for the reason `openPickupHistory` scopes its query: five controls per
        // card put the topmost one a long scroll away from the named row.
        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        let tips = card.buttons["shiftDetailDeliveryTipsButton"]
        XCTAssertTrue(tips.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable(tips, in: app), "and is somewhere a tap will land on it")
        tips.tap()

        addTip("5.00", method: "Cash", in: app)
        app.buttons["closeDeliveryTipsButton"].tap()

        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(
            waitForLabel(first, toContain: "$47.40 earned per recorded delivery hour"),
            "The tip is half of what the delivery paid, so the rate divides both halves: \(first.label)"
        )
        XCTAssertTrue(
            first.label.contains("Total recorded for Delivery 1, $19.75"),
            "and the total it divides is on the same row: \(first.label)"
        )

        // The delivery it overlapped is untouched: a tip is a fact about one
        // delivery, and no figure here is allocated across deliveries.
        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(
            third.label.contains("$19.00 earned per recorded delivery hour"),
            "Showed: \(third.label)"
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

    // MARK: Expected pay

    /// An amount is recorded against a delivery in progress, and the card states
    /// it as what the delivery is *expected* to pay rather than as earnings.
    ///
    /// The distinction is the whole feature, so the journey asserts both halves:
    /// that the figure the driver typed is on the card under its own name, and
    /// that nothing anywhere on the running shift now reports a recorded amount.
    @MainActor
    func testRecordsExpectedPayOnARunningDelivery() throws {
        let app = launchWithExpectedPay()

        // The fixture's second delivery carries nothing, which is where the
        // control has to offer to add rather than to change.
        let card = deliveryStatus(containing: "Delivery 2", in: app)
        let add = deliveryButton("expectedEarningsButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(add, in: app), "A delivery in progress offers expected pay")
        XCTAssertEqual(add.label, "Add expected pay for Delivery 2")
        XCTAssertFalse(
            card.label.contains("Expected pay"),
            "Nothing is expected until the driver records it: \(card.label)"
        )

        add.tap()
        let field = app.textFields["deliveryExpectedEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(
            field.value as? String,
            "8.5",
            "The editor opens on this delivery's own record rather than on the other card's amount"
        )
        XCTAssertFalse(
            app.buttons["removeDeliveryExpectedEarningsButton"].exists,
            "There is nothing to remove yet"
        )
        typeExpectedPay("12.25", in: app)
        app.buttons["saveDeliveryExpectedEarningsButton"].tap()

        XCTAssertTrue(
            waitForLabel(card, toContain: "Expected pay for Delivery 2, $12.25"),
            "The card states the amount with the delivery it belongs to: \(card.label)"
        )
        XCTAssertTrue(
            card.label.contains("No gross earnings recorded yet"),
            "And says in the same breath that it is not earnings: \(card.label)"
        )
        XCTAssertFalse(
            card.label.contains("Gross earnings for Delivery 2, $12.25"),
            "An expectation is never spoken as a recorded amount: \(card.label)"
        )
        XCTAssertEqual(
            deliveryButton("expectedEarningsButton", containing: "Delivery 2", in: app).label,
            "Change expected pay for Delivery 2",
            "The control now offers to change what is recorded"
        )

        // The other delivery's own amount is untouched, so the figure went to
        // the record the control named rather than to whichever card was handy.
        XCTAssertTrue(
            deliveryStatus(containing: "Delivery 1", in: app).label.contains("Expected pay for Delivery 1, $8.50")
        )

        // And nothing about the shift now reports earnings. The notice below is
        // rendered after the amount and the rates would be, so reaching it is
        // what makes their absence a real absence rather than an unrendered row.
        let notice = app.descendants(matching: .any)["liveRateNotice"]
        XCTAssertTrue(scrollToTop(reaching: notice, in: app), "The shift panel is back on screen")
        XCTAssertEqual(notice.label, "This shift is still running. Rates are worked out once it ends.")
        XCTAssertFalse(
            app.descendants(matching: .any)["liveRecordedGross"].exists,
            "An expected amount is not a recorded one, and no shift figure counts it"
        )
        XCTAssertEqual(rows(in: app).count, 0, "Nothing was finalized into history either")
    }

    /// A delivery carrying an expected amount is delivered through the real
    /// lifecycle, is offered the chance to record what it actually paid, and is
    /// left with none when the driver says not now.
    ///
    /// What the sheet must not do is turn the expectation into earnings by
    /// itself, so the assertions after the dismissal are the point of the
    /// journey: the delivery is terminal, the expectation survives into history,
    /// and no gross amount exists anywhere.
    @MainActor
    func testDeliveringWithExpectedPayOffersItAndRecordsNothingWhenDismissed() throws {
        let app = launchWithExpectedPay()

        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(action, in: app))
        XCTAssertTrue(
            deliveryStatus(containing: "Delivery 1", in: app).label.contains("Expected pay for Delivery 1, $8.50"),
            "The fixture's first delivery carries an expectation"
        )

        // The step before the last one. The confirmation belongs to the
        // delivered event alone, so picking the order up must raise nothing.
        XCTAssertEqual(action.label, "Delivery 1. Mark order picked up")
        action.tap()
        XCTAssertTrue(waitForLabel(action, toContain: "Mark delivery completed"))
        XCTAssertFalse(
            app.buttons["confirmEarningsRecordButton"].exists,
            "Nothing is asked until the delivery is actually delivered"
        )

        action.tap()

        let expectedRow = app.descendants(matching: .any)["confirmEarningsExpectedAmount"]
        XCTAssertTrue(expectedRow.waitForExistence(timeout: 5), "The confirmation is raised")
        XCTAssertEqual(
            expectedRow.label,
            "Expected pay for Delivery 1, $8.50. No gross earnings recorded yet.",
            "The sheet states the expectation as an expectation"
        )
        XCTAssertFalse(
            app.textFields["confirmEarningsExpectedAmount"].exists,
            "The expected figure is stated rather than offered as the field to type in"
        )

        // The editable amount is a different control, named for the fact it
        // records. Seeded from the expectation, and that is all it is.
        let amount = app.textFields["confirmEarningsAmountField"]
        XCTAssertTrue(amount.exists)
        XCTAssertEqual(amount.label, "Gross earnings for Delivery 1")
        // `8.5` rather than `8.50`: an editor seeds a field with a number to be
        // typed over, and `MoneyInput` writes it without trailing zeroes.
        XCTAssertEqual(amount.value as? String, "8.5")
        XCTAssertTrue(
            app.navigationBars["Delivery 1 Delivered"].exists,
            "The sheet names the delivery it is about"
        )

        let dismiss = app.buttons["confirmEarningsDismissButton"].firstMatch
        XCTAssertEqual(dismiss.label, "Record no earnings for Delivery 1 now")
        dismiss.tap()

        XCTAssertTrue(
            waitForDisappearance(of: app.buttons["confirmEarningsRecordButton"].firstMatch),
            "Not Now closes the sheet"
        )

        // Terminal, and terminal because the lifecycle said so rather than
        // because the sheet was answered.
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "The delivered delivery has no next step and leaves the panel"
        )
        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery completed"), "Status: \(status.label)")

        // The rest of the shift is ordinary work, and only exists here so the
        // shift can be ended and its history read.
        let remaining = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        for expected in ["Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(waitForLabel(remaining, toContain: expected), "Showed: \(remaining.label)")
            remaining.tap()
        }

        let endShift = app.buttons["endShiftButton"]
        XCTAssertTrue(scrollToTop(reaching: endShift, in: app))
        endShift.tap()
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(
            row.label.contains("Expected pay for Delivery 1, $8.50. No gross earnings recorded yet."),
            "History keeps what was expected, and still says nothing was recorded: \(row.label)"
        )
        XCTAssertFalse(
            row.label.contains("Gross earnings for Delivery 1"),
            "Dismissing the confirmation recorded no amount: \(row.label)"
        )
        XCTAssertEqual(
            app.buttons
                .matching(identifier: "shiftDetailDeliveryEarningsButton")
                .matching(NSPredicate(format: "label CONTAINS %@", "Delivery 1"))
                .firstMatch
                .label,
            "Add gross earnings for Delivery 1",
            "History offers the amount again rather than treating the question as answered"
        )

        let shiftEarnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(scrollToTop(reaching: shiftEarnings, in: app))
        XCTAssertEqual(
            shiftEarnings.label,
            "No amount recorded",
            "No shift figure was invented from a delivery's expectation either"
        )
    }

    /// A delivery with no expected amount is delivered exactly as it always was,
    /// and meets no confirmation on the way.
    ///
    /// The absence is asserted without waiting out a timeout. The sheet would be
    /// presented by the same state change that removes the delivered card, so a
    /// panel that has already dropped the card and is still taking taps has
    /// answered the question: the second half of the journey opens another
    /// card's sheet, which a presented confirmation would have swallowed.
    @MainActor
    func testDeliveringWithoutExpectedPayRaisesNoConfirmation() throws {
        let app = launchWithExpectedPay()

        let card = deliveryStatus(containing: "Delivery 2", in: app)
        let action = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(action, in: app))
        XCTAssertFalse(
            card.label.contains("Expected pay"),
            "The fixture's second delivery carries no expectation: \(card.label)"
        )

        for expected in ["Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(waitForLabel(action, toContain: expected), "Showed: \(action.label)")
            action.tap()
        }

        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "The delivered delivery leaves the panel, which is where a sheet would have been raised"
        )
        XCTAssertFalse(app.buttons["confirmEarningsRecordButton"].exists, "Nothing is asked")
        XCTAssertFalse(app.descendants(matching: .any)["confirmEarningsExpectedAmount"].exists)

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery completed"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("1 delivery in progress"), "Status: \(status.label)")

        // The screen underneath is genuinely the one taking taps: a modal
        // confirmation would take this one instead of the card.
        let change = deliveryButton("expectedEarningsButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(change, in: app))
        change.tap()
        let field = app.textFields["deliveryExpectedEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The other card's own sheet opens")
        XCTAssertEqual(
            field.value as? String,
            "8.5",
            "Completing a delivery left the other delivery's expectation exactly as it was"
        )
        app.buttons["cancelDeliveryExpectedEarningsButton"].tap()

        XCTAssertTrue(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
                .waitForExistence(timeout: 5),
            "And that delivery is still in progress"
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
        let history = revealHistoryRows(2, in: app)
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
        openFirstShift(in: app)
        let deleteButton = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(deleteButton, in: app))
        deleteButton.tap()

        let cancel = app.buttons.matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(app.buttons["deleteShiftButton"].waitForExistence(timeout: 5), "Detail is still open")
        goBack(in: app)
        XCTAssertEqual(revealHistoryRows(2, in: app).count, 2, "Both shifts are still in history")
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

    /// One delivery card on the running shift's panel, identified by the
    /// delivery it names.
    /// **Matched on the start of the label, not on containment.** A card's
    /// spoken status names its siblings — `Part of Offer 1, accepted together
    /// with Delivery 2` — so `CONTAINS "Delivery 2"` matches the card belonging
    /// to Delivery 1. Every card's label begins with its own name.
    @MainActor
    private func deliveryStatusCard(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label BEGINSWITH %@",
                    "activeDeliveryStatus",
                    name
                )
            )
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

    /// The whole list cell one delivery occupies, record and controls together.
    ///
    /// ``deliveryRow(containing:in:)`` finds the combined element holding the
    /// facts, which is a sibling of the controls rather than their ancestor. A
    /// claim about one delivery's own actions has to start from something that
    /// contains them, because two deliveries picked up at the same place offer
    /// two controls with identical labels.
    @MainActor
    private func deliveryCard(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.cells
            .containing(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "shiftDetailDeliveryRow",
                    text
                )
            )
            .firstMatch
    }

    /// One recorded pause's row on the detail screen, identified by what it
    /// says.
    ///
    /// The row is one combined accessibility element, so its label is where the
    /// printed facts can be read back as a sentence — which is also what
    /// VoiceOver says.
    @MainActor
    private func pauseRow(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "shiftDetailPauseRow",
                    text
                )
            )
            .firstMatch
    }

    /// One pause's Edit or Delete control, picked out by the pause its label
    /// names rather than by where it sits.
    ///
    /// Every such button on the screen shares one identifier, and a pause is
    /// renumbered when an earlier one is deleted, so matching on the label is
    /// what makes a journey act on the pause it means.
    @MainActor
    private func pauseButton(
        _ identifier: String,
        containing text: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, text))
            .firstMatch
    }

    /// Sets the time one compact `DatePicker` holds.
    ///
    /// A compact date picker in a `Form` shows a date button and a time button;
    /// tapping the time button reveals three wheels — hour, minute and, in a
    /// twelve-hour locale, the meridiem. Every wheel a caller wants is set while
    /// they are open once, because reopening between two of them is two more
    /// taps that can land on a moving control.
    ///
    /// The wheels are then put away by tapping the **navigation bar**, which is
    /// the one thing on this sheet that is both inert and reliably hittable. The
    /// picker's own time button is not tapped again and neither is the section
    /// heading: expanded wheels sit over the whole form, so iOS reports both as
    /// not hittable and a journey that tried either would fail on its own
    /// housekeeping rather than on the screen. Putting them away matters because
    /// a caller that then sets the *other* picker has to be able to reach it.
    ///
    /// It returns once the picker's own button stops reading what it read
    /// before, so a caller asserting on the form afterwards is asserting against
    /// a picker that has finished moving.
    @MainActor
    private func setTime(
        hour: String? = nil,
        minute: String? = nil,
        meridiem: String? = nil,
        ofPicker identifier: String,
        in app: XCUIApplication
    ) {
        let picker = app.datePickers[identifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "\(identifier) is on screen")
        XCTAssertTrue(picker.buttons.count > 1, "\(identifier) shows a date and a time")
        let timeButton = picker.buttons.element(boundBy: picker.buttons.count - 1)
        let before = timeButton.label
        timeButton.tap()

        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5), "The time wheels are showing")
        if let hour {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: hour)
        }
        if let minute {
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        }
        // Absent in a twenty-four-hour locale, where the hour alone is enough.
        if let meridiem, wheels.count > 2 {
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: meridiem)
        }

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before),
            object: picker.buttons.element(boundBy: picker.buttons.count - 1)
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [changed], timeout: 5),
            .completed,
            "\(identifier) records the time that was chosen rather than the one it opened on"
        )

        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(
            waitForDisappearance(of: app.pickerWheels.firstMatch),
            "The wheels close, so the rest of the form can be reached"
        )
    }

    // MARK: Estimated fuel

    /// Records the two fuel assumptions on a finished shift, then changes one of
    /// them.
    ///
    /// The seeded fixture is the only way to reach this end to end: the estimate
    /// divides a **recorded** mileage, and a UI test cannot drive a simulator
    /// into recording a route. The exact cost is deliberately not asserted, for
    /// the reason the per-recorded-mile rate is not: it comes from the fixture's
    /// coordinates rather than from anything this journey does. What is asserted
    /// is that a figure appears, that it says what it is based on, and that
    /// doubling the fuel economy moves it.
    @MainActor
    func testAddsAndEditsFuelAssumptionsFromDetail() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app), "The estimated fuel section should be reachable")
        XCTAssertTrue(
            cost.label.contains("Add your vehicle's miles per gallon"),
            "A shift with no assumptions is told which one to add, not shown $0.00: \(cost.label)"
        )
        XCTAssertFalse(cost.label.contains("$0.00"))

        let addButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(addButton, in: app))
        XCTAssertEqual(addButton.label, "Add Fuel Assumptions", "A shift with none offers to add them")
        addButton.tap()

        typeFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()

        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "estimated fuel cost, based on recorded mileage"),
            "The estimate says what it is and what it is based on: \(cost.label)"
        )
        XCTAssertTrue(cost.label.contains("$"), "And it states an amount: \(cost.label)")
        let firstEstimate = cost.label

        let gallons = app.descendants(matching: .any)["shiftDetailEstimatedGallons"]
        XCTAssertTrue(scrollTo(gallons, in: app))
        XCTAssertTrue(
            waitForLabel(gallons, toContain: "gallons estimated, from recorded mileage"),
            "The gallons are spelled out for a listener: \(gallons.label)"
        )

        // Both assumptions are stated back, so a driver can see what the figure
        // was worked out from.
        let economy = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertTrue(scrollTo(economy, in: app))
        XCTAssertTrue(waitForLabel(economy, toContain: "25 miles per gallon assumed"), "Showed: \(economy.label)")
        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "$3.50 per gallon assumed"), "Showed: \(price.label)")

        // Editing replaces the assumptions rather than adding to them, and the
        // estimate follows: twice the fuel economy is half the fuel.
        let editButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(editButton, in: app))
        XCTAssertEqual(editButton.label, "Edit Fuel Assumptions")
        editButton.tap()

        let economyField = app.textFields["fuelMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        XCTAssertEqual(economyField.value as? String, "25", "The editor opens on the stored figures")
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.5")
        clear(economyField, in: app)
        economyField.typeText("50")
        app.buttons["saveFuelAssumptionsButton"].tap()

        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "estimated fuel cost"),
            "The estimate is still stated: \(cost.label)"
        )
        XCTAssertNotEqual(cost.label, firstEstimate, "A more economical vehicle uses less fuel over the same miles")
    }

    /// One assumption alone is not an estimate, and the screen says which half
    /// is missing rather than showing nothing.
    @MainActor
    func testFuelEstimateNamesTheMissingHalf() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let addButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(addButton, in: app))
        addButton.tap()

        typeFuelAssumptions(milesPerGallon: "25", gasPrice: nil, in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()

        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "Add what a gallon of fuel cost"),
            "The half that is missing is the one named: \(cost.label)"
        )
        XCTAssertFalse(cost.label.contains("$0.00"), "A missing price is not free fuel")

        // The half that was recorded is still shown, so the driver can see what
        // is already there.
        let economy = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertTrue(scrollTo(economy, in: app))
        XCTAssertTrue(waitForLabel(economy, toContain: "25 miles per gallon assumed"))

        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "No gas price recorded"), "Showed: \(price.label)")
    }

    /// The fixture's route has a gap in it, so the estimate has to say it is a
    /// floor rather than a total.
    @MainActor
    func testFuelEstimateKeepsThePartialRouteWording() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)

        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "This route is partial"),
            "The estimate carries the route's own caveat rather than reading as a total: \(cost.label)"
        )
        XCTAssertTrue(
            cost.label.contains("more fuel was used than this estimates"),
            "And says which way the figure is wrong: \(cost.label)"
        )
    }

    /// A fuel economy of zero is refused, and refusing it records nothing.
    @MainActor
    func testInvalidFuelAssumptionsAreNotSaved() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let addButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(addButton, in: app))
        addButton.tap()

        typeFuelAssumptions(milesPerGallon: "0", gasPrice: "3.50", in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()

        let message = validationMessage("fuelAssumptionsValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The driver should be told why it was refused")
        XCTAssertTrue(
            message.label.contains("more than zero"),
            "And told the rule, which is that it is the divisor: \(message.label)"
        )
        XCTAssertTrue(
            app.textFields["fuelGasPriceField"].exists,
            "The editor stays open with what was typed rather than discarding it"
        )

        app.buttons["cancelFuelAssumptionsButton"].tap()

        let button = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        XCTAssertEqual(
            button.label,
            "Add Fuel Assumptions",
            "A refused pair leaves the shift with neither figure recorded, including the valid one"
        )
    }

    /// The editor fills itself from the last shift that recorded assumptions, so
    /// they are typed once rather than every shift.
    ///
    /// The fixture's second shift recorded nothing, which is what makes the
    /// seeding visible: whatever appears in its fields came from the other
    /// shift.
    @MainActor
    func testFuelAssumptionsSeedFromTheLastShiftThatRecordedThem() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)
        goBack(in: app)

        let history = revealHistoryRows(2, in: app)
        history.element(boundBy: 1).tap()

        let addButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(addButton, in: app))
        XCTAssertEqual(
            addButton.label,
            "Add Fuel Assumptions",
            "This shift has recorded nothing of its own yet"
        )
        addButton.tap()

        let economyField = app.textFields["fuelMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        XCTAssertEqual(economyField.value as? String, "25", "Filled in from the last pair recorded")
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.5")

        // And leaving without saving records nothing: a filled field is a
        // suggestion, not a figure.
        app.buttons["cancelFuelAssumptionsButton"].tap()
        let button = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        XCTAssertEqual(button.label, "Add Fuel Assumptions")
    }

    /// Removing the assumptions leaves no estimate, which is not an estimate of
    /// nothing.
    @MainActor
    func testRemovingFuelAssumptionsLeavesNoEstimate() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)

        let editButton = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(editButton, in: app))
        editButton.tap()

        let remove = app.buttons["removeFuelAssumptionsButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()

        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "Add your vehicle's miles per gallon"),
            "The shift is back to having no estimate at all: \(cost.label)"
        )
        XCTAssertFalse(cost.label.contains("$0.00"), "Removing figures is not recording that no fuel was used")
    }

    // MARK: Estimated net

    /// The estimated net reads as a ledger: what was recorded, what was
    /// estimated, and what is left.
    @MainActor
    func testEstimatedNetShowsTheSubtractionItPerformed() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)

        let earnings = app.descendants(matching: .any)["shiftDetailNetRecordedEarnings"]
        XCTAssertTrue(scrollTo(earnings, in: app), "The estimated net section should be reachable")
        XCTAssertTrue(
            waitForLabel(earnings, toContain: "$86.25 recorded gross earnings for this shift"),
            "The recorded half says it is recorded: \(earnings.label)"
        )

        let fuel = app.descendants(matching: .any)["shiftDetailNetEstimatedFuel"]
        XCTAssertTrue(scrollTo(fuel, in: app))
        XCTAssertTrue(
            waitForLabel(fuel, toContain: "estimated fuel cost, based on recorded mileage"),
            "The estimated half says it is estimated, and what from: \(fuel.label)"
        )
        XCTAssertTrue(fuel.label.contains("-$"), "And it is subtracted, which the figure shows: \(fuel.label)")

        let net = app.descendants(matching: .any)["shiftDetailEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            waitForLabel(net, toContain: "estimated net after fuel"),
            "The result is named an estimate rather than a profit: \(net.label)"
        )
        XCTAssertFalse(net.label.lowercased().contains("profit"))

        let hourly = app.descendants(matching: .any)["shiftDetailEstimatedNetPerWorkingHour"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(
            waitForLabel(hourly, toContain: "estimated net after fuel per working hour"),
            "And the hourly figure names the same denominator the gross rate uses: \(hourly.label)"
        )
    }

    /// A partial route makes the fuel a floor and the net a ceiling, and the
    /// screen says so in that direction.
    @MainActor
    func testEstimatedNetStatesWhichWayAPartialRouteIsWrong() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)

        let notice = app.descendants(matching: .any)["shiftDetailEstimatedNetPartialNotice"]
        XCTAssertTrue(scrollTo(notice, in: app))
        XCTAssertTrue(
            waitForLabel(notice, toContain: "this net is a ceiling"),
            "A floor on the fuel is a ceiling on what was left: \(notice.label)"
        )
    }

    /// A shift with no fuel estimate is still entirely readable: every recorded
    /// figure and every gross rate is where it was, and only the net says it is
    /// unavailable.
    @MainActor
    func testShiftWithoutAFuelEstimateKeepsItsFinancialFigures() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(earnings, toContain: "86.25"), "The recorded amount is unaffected")

        let hourlyGross = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyGross, in: app))
        XCTAssertTrue(
            waitForLabel(hourlyGross, toContain: "gross earnings per shift hour"),
            "And so is every gross rate: \(hourlyGross.label)"
        )

        let net = app.descendants(matching: .any)["shiftDetailEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            waitForLabel(net, toContain: "Add your miles per gallon and a gas price"),
            "The net alone is unavailable, and says what would produce it: \(net.label)"
        )
        XCTAssertFalse(net.label.contains("$0.00"), "An absent net is not a net of nothing")
    }

    /// A shift with no recorded amount has no net either, and is told which
    /// figure is missing.
    @MainActor
    func testEstimatedNetNamesMissingEarnings() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)
        goBack(in: app)

        // The fixture's second shift recorded no amount, and the assumptions
        // above seed its editor, so it can reach a fuel estimate without
        // reaching an amount.
        let history = revealHistoryRows(2, in: app)
        history.element(boundBy: 1).tap()

        let net = app.descendants(matching: .any)["shiftDetailEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            waitForLabel(net, toContain: "Add what this shift paid"),
            "The missing half that is named is the earnings: \(net.label)"
        )
        XCTAssertFalse(net.label.contains("$0.00"))
    }

    // MARK: Period estimated fuel

    /// A period states its estimated fuel with the coverage behind it, and never
    /// as though the covered shifts were the whole period.
    @MainActor
    func testPeriodEstimatedFuelStatesItsCoverage() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let fuel = app.descendants(matching: .any)["periodEstimatedFuel"]
        XCTAssertTrue(scrollTo(fuel, in: app, maxSwipes: 14), "The period says what it is estimated to have spent")
        XCTAssertTrue(
            waitForLabel(fuel, toContain: "Estimated fuel"),
            "Showed: \(fuel.label)"
        )
        XCTAssertTrue(fuel.label.contains("$"), "And it states an amount: \(fuel.label)")

        // The fixture covers one of the day's two completed shifts, and the
        // counts are part of the spoken sentence rather than a caption beside
        // it.
        XCTAssertTrue(
            fuel.label.contains("1 of 2 completed shifts"),
            "The subset is stated rather than presented as the period: \(fuel.label)"
        )
        XCTAssertTrue(
            fuel.label.contains("recorded miles"),
            "And how much of the driving is behind it: \(fuel.label)"
        )
    }

    /// The estimated net is worked out over the shifts that record both halves,
    /// says so, and is kept apart from the net after recorded expenses.
    @MainActor
    func testPeriodEstimatedNetIsSeparateFromRecordedExpenses() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        // The recorded net first, because it sits above the estimated section and
        // `scrollTo` only walks downwards. The two are different figures over
        // different inputs, and neither has the other taken off it.
        let recordedNet = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(recordedNet, in: app, maxSwipes: 14))
        XCTAssertTrue(
            waitForLabel(recordedNet, toContain: "$37.65"),
            "Net after recorded expenses is unchanged by the estimate: \(recordedNet.label)"
        )
        XCTAssertFalse(
            recordedNet.label.contains("estimated fuel"),
            "The recorded net does not quietly include an estimate: \(recordedNet.label)"
        )

        let net = app.descendants(matching: .any)["periodEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app, maxSwipes: 14))
        XCTAssertTrue(
            waitForLabel(net, toContain: "Estimated net after fuel"),
            "Showed: \(net.label)"
        )
        XCTAssertTrue(
            net.label.contains("1 of 2 shifts"),
            "A partial-coverage net says which shifts it is: \(net.label)"
        )
        XCTAssertTrue(
            net.label.contains("not this period's earnings less this period's fuel"),
            "And refuses to be read as the period's: \(net.label)"
        )
        XCTAssertTrue(
            net.label.contains("never added together"),
            "The overlap with a recorded fuel expense is stated: \(net.label)"
        )
    }

    /// The comparison declares no period more profitable on an estimate.
    @MainActor
    func testTheComparisonStatesNoEstimatedFigure() throws {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPeriodComparisonArgument)
        launchInPortrait(app)
        openPeriodSummary(in: app)

        let notes = app.descendants(matching: .any)["periodComparisonNotes"]
        XCTAssertTrue(scrollTo(notes, in: app, maxSwipes: 16), "The comparison is on screen")

        XCTAssertEqual(
            elements(containing: "Estimated fuel", in: app)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "periodComparison")).count,
            0,
            "No estimate is compared between two periods"
        )
        XCTAssertEqual(
            elements(containing: "Estimated net", in: app)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "periodComparison")).count,
            0
        )
    }

    // MARK: The running shift's vehicle

    /// The question the row exists to answer, driven end to end: *which vehicle
    /// is this shift using?*, answered without leaving the driving screen.
    @MainActor
    func testTheRunningShiftNamesTheVehicleItRecorded() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app), "The running shift says which vehicle it is using")
        XCTAssertEqual(vehicle.label, "Shift vehicle")
        XCTAssertEqual(
            vehicle.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "The unit is spelled out for a listener with no caption in view"
        )
    }

    /// The invariant the whole snapshot exists for, on the surface where a
    /// driver would most easily believe the opposite: Settings answers which
    /// vehicle the **next** shift records, and the shift in progress does not
    /// follow it.
    @MainActor
    func testChangingSettingsMidShiftLeavesTheRunningShiftsVehicleAlone() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "2020 Honda Civic, 34 miles per gallon")

        // Add a second vehicle, select it, and correct the first one's figure.
        openSettings(in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        let camry = vehicleRow(containing: "2012 Toyota Camry", in: app)
        XCTAssertTrue(scrollUntilHittable(camry, in: app))
        camry.tap()
        XCTAssertTrue(waitForLabel(vehicleRow(containing: "2012 Toyota Camry", in: app), toContain: "Selected"))

        let edit = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        replaceTappedField(economyField, with: "41", in: app)
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        goBack(in: app)

        let unmoved = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(unmoved, in: app))
        XCTAssertEqual(
            unmoved.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "The shift was worked under what it recorded, not under what is selected now"
        )

        // And it is still that after leaving the app and coming back, which is
        // the closest a journey gets to a relaunch: the store is read again and
        // nothing is held in the screen's own state.
        XCUIDevice.shared.press(.home)
        app.activate()
        let returned = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(returned, in: app))
        XCTAssertEqual(returned.value as? String, "2020 Honda Civic, 34 miles per gallon")
    }

    /// A shift started with nothing selected says so, and keeps saying so after
    /// a vehicle is selected: the absence is a fact about this shift.
    @MainActor
    func testAShiftStartedWithNoVehicleBorrowsNothingFromSettings() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "No vehicle recorded for this shift")

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let stillEmpty = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(stillEmpty, in: app))
        XCTAssertEqual(
            stillEmpty.value as? String,
            "No vehicle recorded for this shift",
            "Borrowing the current selection would claim a vehicle this shift never recorded"
        )
    }

    // MARK: The next shift's vehicle

    /// Before a shift exists, Home says which vehicle Start Shift will record,
    /// and Start Shift is still the plain action it was.
    @MainActor
    func testHomeNamesTheVehicleTheNextShiftWillRecord() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Home says what the next shift will record")
        XCTAssertEqual(next.label, "Next shift vehicle")
        XCTAssertEqual(next.value as? String, "2020 Honda Civic, 34 miles per gallon")
        XCTAssertTrue(app.buttons["startShiftButton"].isHittable, "Start Shift stays its own control")
        XCTAssertFalse(
            app.descendants(matching: .any)["activeShiftVehicle"].exists,
            "The running shift's row and this one never share a screen or an identifier"
        )
    }

    /// No shift exists yet, so a change in Settings is a change to what the next
    /// shift will record, and Home follows it.
    @MainActor
    func testHomeFollowsTheSelectionUntilAShiftStarts() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.value as? String, "2020 Honda Civic, 34 miles per gallon")

        openSettings(in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        let camry = vehicleRow(containing: "2012 Toyota Camry", in: app)
        XCTAssertTrue(scrollUntilHittable(camry, in: app))
        camry.tap()
        XCTAssertTrue(waitForLabel(vehicleRow(containing: "2012 Toyota Camry", in: app), toContain: "Selected"))
        goBack(in: app)

        XCTAssertTrue(
            waitForLabelValue(next, toEqual: "2012 Toyota Camry, 28 miles per gallon"),
            "Home follows the selection while no shift has recorded one: \(String(describing: next.value))"
        )
        XCTAssertTrue(app.buttons["startShiftButton"].exists, "Changing a setting started nothing")
        XCTAssertFalse(app.descendants(matching: .any)["activeShiftVehicle"].exists)
    }

    /// The source of truth changes at the tap: before it, Settings; after it,
    /// the shift's own snapshot, which a later change in Settings does not move.
    @MainActor
    func testStartingAShiftSwitchesHomeToTheShiftsOwnVehicle() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.value as? String, "2020 Honda Civic, 34 miles per gallon")

        app.buttons["startShiftButton"].tap()

        let running = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(running, in: app))
        XCTAssertEqual(
            running.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "What Home said is what was recorded"
        )
        XCTAssertFalse(next.exists, "The next shift's row leaves with the Start Shift control")

        openSettings(in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        let camry = vehicleRow(containing: "2012 Toyota Camry", in: app)
        XCTAssertTrue(scrollUntilHittable(camry, in: app))
        camry.tap()
        XCTAssertTrue(waitForLabel(vehicleRow(containing: "2012 Toyota Camry", in: app), toContain: "Selected"))
        goBack(in: app)

        let unmoved = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(unmoved, in: app))
        XCTAssertEqual(
            unmoved.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "The running shift reads its snapshot, not the selection"
        )
        XCTAssertFalse(app.descendants(matching: .any)["nextShiftVehicle"].exists)
    }

    /// Nothing selected is said as that, and it refuses nothing.
    @MainActor
    func testHomeSaysNoVehicleIsSelectedAndStillStarts() throws {
        let app = launchWithEmptyStore()

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(next.value as? String, "No vehicle selected for the next shift")

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.isEnabled)
        startShift.tap()

        let running = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(running, in: app), "The shift started")
        XCTAssertEqual(running.value as? String, "No vehicle recorded for this shift", "And invented no vehicle")
    }

    /// A price with no vehicle: the known half is said, the missing half is
    /// left out rather than written as zero, and Start Shift is still allowed.
    @MainActor
    func testHomeSaysOnlyWhatIsKnownAboutTheNextShift() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        setCurrentGasPrice("3.29", in: app)
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabelValue(next, toEqual: "No vehicle selected for the next shift, gas $3.29 per gallon"),
            "Showed: \(String(describing: next.value))"
        )
        let shown = (next.value as? String) ?? ""
        XCTAssertFalse(shown.contains("miles per gallon"), "A missing economy is not written as 0 MPG")

        app.buttons["startShiftButton"].tap()
        let running = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(running, in: app), "Incomplete defaults refuse nothing")
        XCTAssertEqual(running.value as? String, "No vehicle recorded for this shift")
    }

    /// At the largest accessibility text size, a long vehicle name wraps inside
    /// the screen rather than running off it, and Start Shift stays reachable.
    @MainActor
    func testTheNextShiftsVehicleWrapsAtLargeTextSizes() throws {
        let app = XCUIApplication()
        app.launchArguments.append(Self.inMemoryStoreArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.accessibilityXXXLTextSize]
        launchInPortrait(app)

        let name = "2020 Honda Civic Hatchback Sport Touring"
        openSettings(in: app)
        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app, maxSwipes: 20))
        add.tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        // At this size the wrapped name pushes the economy field under the
        // keyboard, where a synthesized tap does not focus it. Saving without
        // an economy is refused, and the refusal focuses that field and scrolls
        // it into view itself, so the figure is typed into a field the editor
        // has focused rather than one a tap may have missed.
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(validationMessage("vehicleValidationMessage", in: app).waitForExistence(timeout: 5))
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: economyField
        )
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed)
        economyField.typeText("34")
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.value as? String, "\(name), 34 miles per gallon", "The whole name is kept")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(next.frame.maxX, window.maxX, "The row wraps rather than running off the screen")
        XCTAssertGreaterThan(next.frame.height, 60, "A name this long at this size takes more than one line")
        XCTAssertTrue(scrollUntilHittable(app.buttons["startShiftButton"], in: app))
    }

    // MARK: Correcting the running shift's vehicle

    /// The whole correction, driven end to end: a shift started in the wrong
    /// vehicle, moved to the right one before any driving, with Settings left
    /// exactly as it was.
    @MainActor
    func testCorrectsTheRunningShiftsVehicleBeforeAnyDriving() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        goBack(in: app)

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(
            vehicle.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "The first vehicle added is the selected one, so the shift started under it"
        )

        let change = app.buttons["changeShiftVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(change, in: app), "Correction is offered before any driving")
        change.tap()

        // The sheet keeps what the shift recorded unless the driver chooses
        // otherwise, so Save has nothing to write until something is picked.
        let save = app.buttons["saveShiftVehicleButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Saving the choices already recorded would report a change nobody made")

        let camry = app.descendants(matching: .any)
            .matching(identifier: "correctionVehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", "2012 Toyota Camry"))
            .firstMatch
        XCTAssertTrue(camry.waitForExistence(timeout: 5))
        camry.tap()
        XCTAssertTrue(waitForLabel(camry, toContain: "Chosen"), "The mark is said, not only drawn: \(camry.label)")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let corrected = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(corrected, in: app))
        XCTAssertTrue(
            waitForLabelValue(corrected, toEqual: "2012 Toyota Camry, 28 miles per gallon"),
            "The running shift now says what it was corrected to: \(String(describing: corrected.value))"
        )

        // And it survives leaving the app, because the store is the only place
        // it lives.
        XCUIDevice.shared.press(.home)
        app.activate()
        let returned = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(returned, in: app))
        XCTAssertEqual(returned.value as? String, "2012 Toyota Camry, 28 miles per gallon")

        // Settings is untouched: correcting a shift is not choosing a vehicle
        // for the next one.
        openSettings(in: app)
        let civicRow = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(civicRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            civicRow.label.contains("Selected"),
            "The selection is still the driver's own: \(civicRow.label)"
        )
        XCTAssertTrue(civicRow.label.contains("34 miles per gallon"), "And the profile is unchanged")
        XCTAssertTrue(
            vehicleRow(containing: "2012 Toyota Camry", in: app).label.contains("28 miles per gallon"),
            "As is the one the shift was corrected to"
        )
    }

    /// Once the route has recorded a distance the correction is gone, and the
    /// row it was beside is still readable.
    @MainActor
    func testTheVehicleCorrectionClosesOnceDrivingIsRecorded() throws {
        let app = launchWithSimulatedRoute()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        // The synthetic vehicle is already driving, so the correction may have
        // closed before the first look. What matters is that it is closed once a
        // distance exists, and that the row stays readable.
        let miles = try XCTUnwrap(
            waitForRecordedMiles(in: app),
            "The panel never reported a measured distance while the route was being recorded"
        )
        XCTAssertGreaterThan(miles, 0)

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(
            vehicle.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "The vehicle context is still readable after driving begins"
        )
        XCTAssertFalse(
            app.buttons["changeShiftVehicleButton"].exists,
            "A dead action is worse than no action, so the control is absent rather than disabled"
        )
    }

    /// A shift started with nothing recorded can have its assumptions filled,
    /// which is the case the snapshot itself can never reach.
    @MainActor
    func testFillsMissingVehicleAssumptionsOnAFreshShift() throws {
        let app = launchWithEmptyStore()

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "No vehicle recorded for this shift")

        // A vehicle entered after the shift began, which the shift does not take
        // on its own.
        openSettings(in: app)
        addVehicle(named: "The van", milesPerGallon: "18", in: app)
        goBack(in: app)

        let stillEmpty = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(stillEmpty, in: app))
        XCTAssertEqual(stillEmpty.value as? String, "No vehicle recorded for this shift")

        let change = app.buttons["changeShiftVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(change, in: app))
        change.tap()

        let van = app.descendants(matching: .any)
            .matching(identifier: "correctionVehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", "The van"))
            .firstMatch
        XCTAssertTrue(van.waitForExistence(timeout: 5))
        van.tap()
        app.buttons["saveShiftVehicleButton"].tap()

        let filled = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(filled, in: app))
        XCTAssertTrue(
            waitForLabelValue(filled, toEqual: "The van, 18 miles per gallon"),
            "Showed: \(String(describing: filled.value))"
        )
    }

    /// Cancelling records nothing, which is what makes the sheet safe to open
    /// while a shift is being worked.
    @MainActor
    func testCancellingTheVehicleCorrectionRecordsNothing() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        goBack(in: app)

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let change = app.buttons["changeShiftVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(change, in: app))
        change.tap()

        let camry = app.descendants(matching: .any)
            .matching(identifier: "correctionVehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", "2012 Toyota Camry"))
            .firstMatch
        XCTAssertTrue(camry.waitForExistence(timeout: 5))
        camry.tap()
        app.buttons["cancelShiftVehicleButton"].tap()

        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(
            vehicle.value as? String,
            "2020 Honda Civic, 34 miles per gallon",
            "Choosing a row is not recording it"
        )
    }

    // MARK: Settings, vehicles and fuel defaults

    /// Settings is reachable from the main screen, and it says what it is for.
    ///
    /// The entry point is a gear in the navigation bar rather than a row in the
    /// list, which is what keeps it out of the way of the shift workflow and off
    /// the top of the History section.
    @MainActor
    func testSettingsIsReachableFromHome() throws {
        let app = launchWithEmptyStore()

        let settings = app.buttons["settingsLink"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "A gear should be on the main screen")
        XCTAssertEqual(settings.label, "Settings", "A glyph alone says nothing to a listener")
        settings.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "The gear opens the preferences screen"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5),
            "A driver who has entered nothing is told so rather than shown an empty screen"
        )
        XCTAssertTrue(app.buttons["addVehicleButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["currentGasPriceRow"].exists)
    }

    /// Creates two vehicles, corrects one, and selects the other.
    ///
    /// The selection is read off the row's own accessibility label rather than
    /// off a checkmark, because a mark nobody can see is not a statement.
    @MainActor
    func testCreatesEditsAndSelectsVehicles() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        let civic = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(civic.waitForExistence(timeout: 5), "The vehicle is listed")
        XCTAssertTrue(
            waitForLabel(civic, toContain: "34 miles per gallon"),
            "The figure says its unit to a listener: \(civic.label)"
        )
        XCTAssertTrue(
            civic.label.contains("Selected"),
            "The first vehicle is the one new shifts are recorded under: \(civic.label)"
        )

        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        let camry = vehicleRow(containing: "2012 Toyota Camry", in: app)
        XCTAssertTrue(camry.waitForExistence(timeout: 5))
        XCTAssertFalse(camry.label.contains("Selected"), "Adding a vehicle is not choosing one: \(camry.label)")

        // Correcting the first one moves neither the list nor the selection.
        let edit = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        XCTAssertEqual(economyField.value as? String, "34", "The editor opens on the stored figure")
        replaceTappedField(economyField, with: "38", in: app)
        app.buttons["saveVehicleButton"].tap()

        let corrected = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(waitForLabel(corrected, toContain: "38 miles per gallon"), "Showed: \(corrected.label)")

        // Selecting the second one moves the selection to it, and off the first.
        camry.tap()
        XCTAssertTrue(
            waitForLabel(vehicleRow(containing: "2012 Toyota Camry", in: app), toContain: "Selected"),
            "The tapped vehicle becomes the one new shifts are recorded under"
        )
        XCTAssertFalse(
            vehicleRow(containing: "2020 Honda Civic", in: app).label.contains("Selected"),
            "And exactly one is selected"
        )
    }

    /// A vehicle with no name, and one with no fuel economy, are both refused
    /// with the sentence that explains the rule.
    @MainActor
    func testRefusesAVehicleWithNoNameOrNoFuelEconomy() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        app.buttons["addVehicleButton"].tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        // No fuel economy at all.
        nameField.tap()
        nameField.typeText("The van")
        app.buttons["saveVehicleButton"].tap()
        let message = validationMessage("vehicleValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "A vehicle with no economy is refused")
        XCTAssertTrue(
            message.label.contains("miles per gallon"),
            "And the refusal names what is missing: \(message.label)"
        )

        // A fuel economy of zero, which is the divisor.
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        economyField.tap()
        economyField.typeText("0")
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(
            waitForLabel(message, toContain: "more than zero"),
            "Zero is refused because it is what the recorded miles are divided by: \(message.label)"
        )

        // The name rule is not repeated here: a name of nothing but whitespace is
        // refused by ``VehicleName`` and is pinned in the domain suite, where it
        // costs no double tap on a two-word field to reach.
        app.buttons["cancelVehicleButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5),
            "Nothing refused was written"
        )
    }

    /// Records a current gas price, corrects it, and removes it.
    ///
    /// Removing is deliberately not the same as recording zero: afterwards there
    /// is no current price at all, and the row says so rather than showing
    /// `$0.00`.
    @MainActor
    func testRecordsCorrectsAndRemovesTheCurrentGasPrice() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let row = app.descendants(matching: .any)["currentGasPriceRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(row, toContain: "Current gas price"), "Showed: \(row.label)")
        XCTAssertEqual(row.value as? String, "Not set", "Nothing recorded is stated as nothing recorded")

        row.tap()
        let field = app.textFields["currentGasPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("3.19")
        app.buttons["saveCurrentGasPriceButton"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "$3.19 per gallon", "The price says its unit to a listener")

        row.tap()
        let seeded = app.textFields["currentGasPriceField"]
        XCTAssertTrue(seeded.waitForExistence(timeout: 5))
        XCTAssertEqual(seeded.value as? String, "3.19", "The editor opens on the stored figure")
        replaceTappedField(seeded, with: "3.35", in: app)
        app.buttons["saveCurrentGasPriceButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "$3.35 per gallon")

        row.tap()
        let remove = app.buttons["removeCurrentGasPriceButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Not set", "Removed is not a price of nothing")
    }

    /// The whole point of the feature, driven end to end: a shift started after
    /// the defaults are set records them, and the shift before it does not.
    @MainActor
    func testANewShiftRecordsTheCurrentDefaultsAndAnOlderOneDoesNot() throws {
        let app = launchWithEmptyStore()

        // A shift worked before anything was set records nothing.
        completeAShift(in: app)
        openFirstShift(in: app)
        let economy = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertFalse(
            economy.exists,
            "A shift worked before the driver entered any defaults records none"
        )
        goBack(in: app)

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        setCurrentGasPrice("3.19", in: app)
        goBack(in: app)

        // A shift worked afterwards carries the snapshot with no typing at all.
        completeAShift(in: app)
        openFirstShift(in: app)

        let recorded = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertTrue(scrollTo(recorded, in: app), "The new shift records the selected vehicle's economy")
        XCTAssertTrue(waitForLabel(recorded, toContain: "34 miles per gallon assumed"), "Showed: \(recorded.label)")

        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "$3.19 per gallon assumed"), "Showed: \(price.label)")

        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(
            waitForLabel(vehicle, toContain: "2020 Honda Civic"),
            "And the shift says which vehicle it was worked in: \(vehicle.label)"
        )
    }

    /// Changing the settings after a shift is recorded leaves that shift exactly
    /// as it was, and a vehicle deleted from Settings is still named by the
    /// shifts worked in it.
    ///
    /// The invariant the whole feature rests on, driven through the interface
    /// rather than only asserted in the domain suite.
    @MainActor
    func testChangingSettingsLeavesARecordedShiftAlone() throws {
        let app = launchWithEmptyStore()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        setCurrentGasPrice("3.19", in: app)
        goBack(in: app)

        completeAShift(in: app)

        // Now change everything: the economy, the price, and the vehicle itself.
        openSettings(in: app)
        let edit = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        replaceTappedField(app.textFields["vehicleMilesPerGallonField"], with: "12", in: app)
        app.buttons["saveVehicleButton"].tap()

        setCurrentGasPrice("9.99", in: app)

        let editAgain = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(editAgain, in: app))
        editAgain.tap()
        let delete = app.buttons["deleteVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        delete.tap()
        // `.firstMatch`, because a confirmation dialog's button renders as an
        // element containing its own text and both carry the identifier. An
        // unqualified query is a multiple match, which is the lesson the fuel
        // editor's validation message already taught this file.
        app.buttons.matching(identifier: "confirmDeleteVehicleButton").firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5),
            "The vehicle is gone from Settings"
        )
        goBack(in: app)

        openFirstShift(in: app)
        let recorded = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertTrue(scrollTo(recorded, in: app))
        XCTAssertTrue(
            waitForLabel(recorded, toContain: "34 miles per gallon assumed"),
            "The shift keeps the economy it recorded: \(recorded.label)"
        )
        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(
            waitForLabel(price, toContain: "$3.19 per gallon assumed"),
            "And the price: \(price.label)"
        )
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(
            waitForLabel(vehicle, toContain: "2020 Honda Civic"),
            "A shift stays intelligible with no profile behind it: \(vehicle.label)"
        )
    }

    /// An older shift is filled from the current defaults only when the driver
    /// asks, and the fields are filled rather than the store written.
    @MainActor
    func testUseCurrentDefaultsFillsAnOlderShiftOnlyWhenAsked() throws {
        let app = launchWithSeededHistory()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        setCurrentGasPrice("3.19", in: app)
        goBack(in: app)

        openFirstShift(in: app)
        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            cost.label.contains("Add your vehicle's miles per gallon"),
            "The seeded shift was worked before the defaults existed and is not filled in: \(cost.label)"
        )

        let editor = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(editor, in: app))
        editor.tap()

        let defaults = app.buttons["useCurrentDefaultsButton"]
        XCTAssertTrue(scrollUntilHittable(defaults, in: app), "An older shift is offered the current defaults")
        defaults.tap()

        XCTAssertEqual(
            app.textFields["fuelMilesPerGallonField"].value as? String,
            "34",
            "The control fills the fields with the settings"
        )
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.19")

        // Abandoning writes nothing: the shift is still as it was.
        app.buttons["cancelFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "Add your vehicle's miles per gallon"),
            "Filling a field is not recording it: \(cost.label)"
        )

        // Asking again and saving does record it, and names the vehicle.
        XCTAssertTrue(scrollUntilHittable(app.buttons["editFuelAssumptionsButton"], in: app))
        app.buttons["editFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollUntilHittable(app.buttons["useCurrentDefaultsButton"], in: app))
        app.buttons["useCurrentDefaultsButton"].tap()
        app.buttons["saveFuelAssumptionsButton"].tap()

        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(
            waitForLabel(cost, toContain: "estimated fuel cost, based on recorded mileage"),
            "Showed: \(cost.label)"
        )
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(waitForLabel(vehicle, toContain: "2020 Honda Civic"), "Showed: \(vehicle.label)")
    }

    /// Replaces the whole contents of a field the journey reached by tapping.
    ///
    /// This cost a run to learn and is worth writing down. **A synthesized tap
    /// does not move the caret**, so a field that the screen did not focus for
    /// itself is entered with the caret at position zero: the backspaces in
    /// ``clear(_:in:)`` have nothing to their left and do nothing, and the text
    /// typed next is *prepended* — `34` became `3834` rather than `38`, which
    /// reads on screen as a wrong figure rather than as a broken step. A
    /// double tap selects what is there, and typing over a selection replaces
    /// it, which needs no caret at all.
    ///
    /// ``clear(_:in:)`` is still right for a field the screen focuses on
    /// appearance, where the caret starts after the last character.
    @MainActor
    private func replaceTappedField(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let existing = (field.value as? String) ?? ""
        field.doubleTap()
        field.typeText(text)
        XCTAssertEqual(
            field.value as? String,
            text,
            "The field should hold what was typed, not \(existing) with it prepended or appended"
        )
    }

    // MARK: The completed shift's hierarchy

    /// A finished shift leads with what it paid, then how long and how far, and
    /// its corrections sit below every figure they change, with deletion apart
    /// at the foot.
    @MainActor
    func testTheDetailLeadsWithWhatTheShiftPaidThenTimeAndDistance() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("Recorded gross earnings, $86.25"), "Showed: \(earnings.label)")

        let working = app.descendants(matching: .any)["shiftDetailSummaryWorkingTime"]
        let mileage = app.descendants(matching: .any)["shiftDetailSummaryMileage"]
        XCTAssertTrue(working.waitForExistence(timeout: 5))
        XCTAssertTrue(working.label.hasSuffix("working time"), "The duration says what it is: \(working.label)")
        XCTAssertTrue(waitForLabel(mileage, toContain: "miles"), "The distance says its unit: \(mileage.label)")
        XCTAssertLessThan(earnings.frame.minY, working.frame.minY, "What the shift paid leads")
        attachScreenshot("detail-summary")

        // The rates are the performance figures, under the summary rather than
        // beside it, and the one that divides by working time is not repeated.
        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(hourly.label.contains("gross earnings per shift hour"), "Showed: \(hourly.label)")

        // The corrections come after the delivery log, and deletion after them.
        let deliveries = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(deliveries, in: app, maxSwipes: 15), "The deliveries are listed")
        let correctEnd = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app, maxSwipes: 15), "The corrections are below them")
        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollUntilHittable(delete, in: app, maxSwipes: 6))
        XCTAssertLessThan(correctEnd.frame.minY, delete.frame.minY, "Deletion stands apart, last")
    }

    /// A partial route says so where the distance is stated, and says it in the
    /// summary too, so the figure never appears without its caveat.
    @MainActor
    func testTheDetailStatesAPartialRouteBesideItsDistance() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summaryMileage = app.descendants(matching: .any)["shiftDetailSummaryMileage"]
        XCTAssertTrue(summaryMileage.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabel(summaryMileage, toContain: "more miles were driven than were recorded"),
            "The summary's figure carries the partial route: \(summaryMileage.label)"
        )

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollUntilHittable(mileage, in: app), "Driving states the route")
        XCTAssertTrue(mileage.label.contains("Partial route"), "Showed: \(mileage.label)")
        attachScreenshot("detail-partial-route")
    }

    /// At the largest accessibility size the summary's figures stack whole, and
    /// the rest of the screen is still reachable below them.
    @MainActor
    func testTheDetailSurvivesTheLargestTextSize() throws {
        let app = launchWithSeededHistory(atTextSize: Self.accessibilityXXXLTextSize)
        openFirstShift(in: app)

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("$86.25"), "The figure is whole rather than shortened")
        let working = app.descendants(matching: .any)["shiftDetailSummaryWorkingTime"]
        XCTAssertTrue(scrollTo(working, in: app))
        XCTAssertGreaterThan(working.frame.height, 44, "A stacked figure is never a tiny cell")
        attachScreenshot("detail-xxxl")

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app, maxSwipes: 30), "Driving is reachable further down")
        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(delete, in: app, maxSwipes: 60), "And so is the end of the screen")
    }

    // MARK: Settings hierarchy

    /// Settings leads with the vehicle the next shift will record, says so in
    /// words, and says plainly when there is none.
    @MainActor
    func testSettingsLeadsWithTheDefaultVehicle() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let none = app.descendants(matching: .any)["noDefaultVehicleNotice"]
        XCTAssertTrue(none.waitForExistence(timeout: 5), "No selection is stated rather than left empty")
        XCTAssertTrue(none.label.contains("No vehicle selected"), "Showed: \(none.label)")
        XCTAssertTrue(none.label.contains("next shift"), "And says what it means: \(none.label)")
        attachScreenshot("settings-no-vehicle")

        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        let summary = app.descendants(matching: .any)["defaultVehicleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The first vehicle becomes the default")
        XCTAssertEqual(
            summary.label,
            "Default vehicle: 2020 Honda Civic, 34 miles per gallon. Used for your next shift."
        )
        XCTAssertFalse(none.exists)

        let row = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(row.label.hasPrefix("Selected as the default vehicle."), "Showed: \(row.label)")

        // A gas price of zero is a price, drawn and spoken as one.
        setCurrentGasPrice("0", in: app)
        let price = app.descendants(matching: .any)["currentGasPriceRow"]
        XCTAssertEqual(price.value as? String, "$0.00 per gallon", "A recorded zero is not Not set")
        attachScreenshot("settings-default-vehicle")

        // Clearing the default is stated again rather than leaving a stale card.
        row.tap()
        XCTAssertTrue(none.waitForExistence(timeout: 5), "Tapping the default again clears it")
        XCTAssertFalse(summary.exists)
    }

    /// The vehicle editor labels each field above it, and a refusal is a
    /// sentence the shared helper reads rather than the symbol beside it.
    @MainActor
    func testTheVehicleEditorLabelsItsFieldsAndStatesARefusal() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        add.tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.label, "Vehicle name")
        XCTAssertEqual(app.textFields["vehicleMilesPerGallonField"].label, "Miles per gallon")
        attachScreenshot("vehicle-editor")

        nameField.tap()
        nameField.typeText("The van")
        app.buttons["saveVehicleButton"].tap()
        let message = validationMessage("vehicleValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("miles per gallon"), "The sentence, not a glyph: \(message.label)")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "vehicleValidationMessage").count,
            1,
            "One element carries the refusal, so no query can find a glyph called Warning instead"
        )
        attachScreenshot("vehicle-editor-validation")
    }

    /// A long vehicle name at the largest text size wraps whole on the default
    /// card and in the list, rather than being shortened.
    @MainActor
    func testSettingsSurvivesTheLargestTextSizeWithALongName() throws {
        let app = launchWithEmptyStore(textSize: Self.accessibilityXXXLTextSize)
        let name = "2020 Honda Civic Hatchback Sport Touring"
        openSettings(in: app)

        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app, maxSwipes: 20))
        add.tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        // Saved once without an economy, so the refusal focuses the economy
        // field itself: at this size a synthesized tap on a field under the
        // keyboard does not focus it.
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(validationMessage("vehicleValidationMessage", in: app).waitForExistence(timeout: 5))
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: economyField
        )
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed)
        economyField.typeText("34")
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let summary = app.descendants(matching: .any)["defaultVehicleSummary"]
        XCTAssertTrue(scrollToTop(reaching: summary, in: app), "The default card is at the top")
        XCTAssertTrue(summary.label.contains(name), "The name is whole: \(summary.label)")
        XCTAssertGreaterThan(summary.frame.height, 44)
        attachScreenshot("settings-xxxl")

        let row = vehicleRow(containing: name, in: app)
        XCTAssertTrue(scrollTo(row, in: app, maxSwipes: 20), "And in the list below it")
    }

    /// Settings says which licenses DashPilot ships under, and shows the
    /// typeface's license in full from the copy bundled beside the fonts.
    @MainActor
    func testAcknowledgementsNameBothLicensesAndShowTheFontLicense() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let link = app.buttons["acknowledgementsLink"]
        XCTAssertTrue(scrollUntilHittable(link, in: app), "About is at the foot of Settings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            elements(containing: "MIT License", in: app).firstMatch.waitForExistence(timeout: 5),
            "DashPilot's own code is MIT"
        )
        let manrope = app.descendants(matching: .any)["manropeAcknowledgement"]
        XCTAssertTrue(manrope.exists)
        XCTAssertTrue(manrope.label.contains("SIL Open Font License"), "Showed: \(manrope.label)")

        let license = app.descendants(matching: .any)["manropeLicenseText"]
        XCTAssertTrue(scrollTo(license, in: app), "The full license text is shown, read from the bundle")
        XCTAssertTrue(license.label.contains("SIL OPEN FONT LICENSE Version 1.1"), "Showed the license text")
    }

    // MARK: Settings helpers

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["settingsLink"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// One vehicle row, matched on the name inside its combined label.
    @MainActor
    private func vehicleRow(containing name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "vehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", name))
            .firstMatch
    }

    @MainActor
    private func addVehicle(named name: String, milesPerGallon: String, in app: XCUIApplication) {
        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        add.tap()

        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        let economyField = app.textFields["vehicleMilesPerGallonField"]
        economyField.tap()
        economyField.typeText(milesPerGallon)

        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func setCurrentGasPrice(_ price: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["currentGasPriceRow"]
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        row.tap()

        replaceTappedField(app.textFields["currentGasPriceField"], with: price, in: app)
        app.buttons["saveCurrentGasPriceButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: Fuel helpers

    /// Types into the two fuel fields, leaving a field alone when its argument
    /// is `nil`.
    @MainActor
    private func typeFuelAssumptions(milesPerGallon: String?, gasPrice: String?, in app: XCUIApplication) {
        if let milesPerGallon {
            let field = app.textFields["fuelMilesPerGallonField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(milesPerGallon)
        }
        if let gasPrice {
            let field = app.textFields["fuelGasPriceField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(gasPrice)
        }
    }

    /// Opens the fuel editor from a completed shift's detail screen, types both
    /// assumptions and saves.
    ///
    /// The editor seeds its fields from the last pair recorded, so each one is
    /// cleared before it is typed into: a journey that appended to a seeded
    /// field would record a figure nobody entered.
    @MainActor
    private func recordFuelAssumptions(milesPerGallon: String, gasPrice: String, in app: XCUIApplication) {
        let button = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(button, in: app), "The fuel section should be reachable")
        button.tap()

        let economyField = app.textFields["fuelMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        clear(economyField, in: app)
        economyField.typeText(milesPerGallon)

        let priceField = app.textFields["fuelGasPriceField"]
        clear(priceField, in: app)
        priceField.typeText(gasPrice)

        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(
            app.buttons["editFuelAssumptionsButton"].waitForExistence(timeout: 5),
            "The sheet closes once the pair is recorded"
        )
    }

    @MainActor
    private func rows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "completedShiftRow")
    }

    /// History's completed shift rows, scrolled until the first `count` of them
    /// are rendered.
    ///
    /// A `List` renders only rows near the viewport, so the second row of the
    /// two-shift fixture does not exist until it is scrolled to, and how far
    /// that is depends on everything above history. Adding the next shift's
    /// vehicle line to the start panel was enough to push it below the fold and
    /// fail eight journeys that had been indexing into it unscrolled. Scrolling
    /// until the last wanted row is **hittable** means every row before it is
    /// rendered too, so `element(boundBy:)` and `count` are then about the
    /// fixture rather than about the screen. A row that cannot be revealed
    /// fails here, loudly, rather than resolving to a different one.
    @MainActor
    private func revealHistoryRows(_ count: Int, in app: XCUIApplication) -> XCUIElementQuery {
        let history = rows(in: app)
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app), "History lists a completed shift")
        XCTAssertTrue(
            scrollUntilHittable(history.element(boundBy: count - 1), in: app),
            "History should reveal \(count) completed shifts"
        )
        return history
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

        assertTheShiftReachedHistory(in: app)
    }

    /// Confirms a shift just ended is listed in History, then returns to the top
    /// of the screen where the shift controls are.
    ///
    /// History opens with the week's own summary above its rows, so on a phone
    /// the first row is below the fold and a `List` has not rendered it: it is
    /// scrolled to rather than waited for. The screen is brought back to the top
    /// afterwards so a journey that starts the next shift finds its control
    /// where an ending leaves it.
    @MainActor
    private func assertTheShiftReachedHistory(in app: XCUIApplication) {
        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "The shift has ended")
        XCTAssertTrue(scrollUntilHittable(rows(in: app).firstMatch, in: app), "and is listed in History")
        XCTAssertTrue(scrollToTop(reaching: start, in: app))
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

    /// Swipes down the screen until `element` is somewhere a tap will land on it.
    ///
    /// `scrollTo` stops as soon as the element **exists**, and an element inside
    /// a scroll view exists while it is off screen. `tap()` then scrolls it into
    /// view itself, and it can park the element under the navigation bar: the
    /// synthesized tap lands on the bar, nothing happens, and the journey fails
    /// on whatever it asserted after the tap rather than on the tap itself. That
    /// is a red run that reproduces only in a full serial suite, where the app
    /// is relaunched over a running one and a panel is not where an isolated
    /// launch leaves it.
    ///
    /// It searches **downward only**, like `scrollTo`, so a caller that is not
    /// already above the element should reach a known top first.
    @MainActor
    @discardableResult
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 10
    ) -> Bool {
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    /// Swipes **up** the screen until `element` is somewhere a tap will land on
    /// it, or returns at once if it already is.
    ///
    /// The mirror of ``scrollUntilHittable(_:in:maxSwipes:)``, for something
    /// above where the screen is rather than below it. It stops as soon as the
    /// element is hittable rather than swiping a fixed number of times, because
    /// the one control it exists for is offered for a few seconds only: a
    /// journey that spends that window scrolling is measuring its own scrolling.
    @MainActor
    @discardableResult
    private func scrollUpUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) -> Bool {
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeDown()
        }
        return element.isHittable
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
    /// Opens the pickup history of the delivery whose row says `text`, from
    /// **that delivery's own card**.
    ///
    /// It used to find the button by the place its label names, taking
    /// `firstMatch` over the whole screen. That is the right button only while
    /// the deliveries name different places: once two are merged they all name
    /// one, and `firstMatch` returns the topmost card's control while the screen
    /// has been scrolled down to a later delivery. `tap()` then scrolls back up
    /// on its own, which mostly worked and sometimes left the sheet arriving
    /// after the assertion that waits for it. Scoping the query to the card
    /// removes the ambiguity rather than widening a timeout around it.
    ///
    /// It then waits for the control to be **hittable** rather than merely to
    /// exist, which is the pattern `scrollUntilHittable` exists for.
    private func openPickupHistory(from text: String, in app: XCUIApplication) {
        let card = deliveryCard(containing: text, in: app)
        XCTAssertTrue(scrollTo(card, in: app), "The delivery should be listed")

        let button = card.buttons["shiftDetailPickupHistoryButton"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "The delivery names a place, so its history is one tap away"
        )
        XCTAssertTrue(scrollUntilHittable(button, in: app), "and is somewhere a tap will land on it")
        button.tap()
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
    /// Opens History's first shift, scrolling down to it first: the week's
    /// summary sits above the rows, so on a phone the first row is below the
    /// fold and a `List` has not rendered it until it is scrolled to.
    private func openFirstShift(in app: XCUIApplication) {
        let row = rows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app, maxSwipes: 12), "History lists a completed shift")
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
            XCTAssertFalse(
                app.buttons["shiftDetailDeliveryTipsButton"].exists,
                "And neither is tip entry, which is the same typing at the same wheel"
            )
            action.tap()
        }

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(scrollToTop(reaching: endButton, in: app))
        XCTAssertFalse(
            app.buttons["shiftDetailDeliveryEarningsButton"].exists,
            "Not even once the delivery has finished, while the shift is still running"
        )
        XCTAssertFalse(app.buttons["shiftDetailDeliveryTipsButton"].exists)
        endButton.tap()

        assertTheShiftReachedHistory(in: app)
    }

    /// Records an amount against the first finished delivery on screen.
    @MainActor
    private func recordDeliveryAmount(_ text: String, in app: XCUIApplication) {
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        typeDeliveryAmount(text, in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
    }

    /// Records one additional tip from the tips sheet, which must already be
    /// open.
    ///
    /// The method control is a segmented picker rather than a wheel, so its
    /// options are ordinary buttons and no overlay is left covering the form
    /// afterwards.
    @MainActor
    private func addTip(_ amount: String, method: String, in app: XCUIApplication) {
        let add = app.buttons["addDeliveryTipButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let field = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(amount)

        let option = app.buttons[method]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The method picker offers \(method)")
        option.tap()

        app.buttons["saveDeliveryTipButton"].tap()
        // Waits for the entry sheet to be **gone**, not merely for the list
        // behind it to be reachable. The list's own controls are in the
        // hierarchy while the sheet animates away, so a journey that proceeds on
        // those alone taps a sheet that is still on screen and the tap does
        // nothing. That is a real race rather than a slow machine, and this is
        // the deterministic end of it.
        XCTAssertTrue(
            waitForDisappearance(of: app.textFields["deliveryTipAmountField"]),
            "The entry sheet closes back to the list of tips"
        )
        XCTAssertTrue(app.buttons["addDeliveryTipButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func typeDeliveryAmount(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    /// Types an amount into the expected-pay sheet's only field.
    ///
    /// The editor focuses the field itself, so the tap is about which element
    /// the keystrokes reach rather than about raising a keyboard.
    @MainActor
    private func typeExpectedPay(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["deliveryExpectedEarningsAmountField"]
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

    /// The sentence of a validation message drawn as a `Label` with a warning
    /// symbol.
    ///
    /// The identifier is mirrored onto the label's icon as well as its text, and
    /// the icon's own label is "Warning". Which of the two an `.any` query
    /// matches first is decided by the runtime's accessibility tree rather than
    /// by the screen: iOS 27 puts the text first and iOS 26.5 puts the icon
    /// first, so a journey reading `.label` off that query passed locally and
    /// read "Warning" in CI. The icon is never a static text, so this query can
    /// only ever resolve to the sentence.
    @MainActor
    private func validationMessage(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: identifier).firstMatch
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

    /// The same wait, on an element's spoken **value** rather than its label.
    ///
    /// A row whose label names the metric and whose value carries the figure is
    /// the arrangement this app uses everywhere a number is spoken, so a journey
    /// that waits for a figure has to wait on the value.
    @MainActor
    private func waitForLabelValue(_ element: XCUIElement, toEqual text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", text),
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

    // MARK: Period summaries

    /// Launches against a throwaway store holding a week of synthetic completed
    /// shifts, anchored to today.
    ///
    /// The period screen shows the day and week the driver is actually in, so
    /// the epoch-pinned fixtures the other journeys use would open it on an
    /// empty period. The fixture holds, by the rules of the driver's own
    /// calendar:
    ///
    /// - **today**: a three-hour shift paying `$86.25` with a partial route,
    ///   three delivered and one cancelled delivery, and recorded waits of 6, 11
    ///   and 41 minutes; and a two-hour shift with no amount and no route.
    /// - **earlier this week**: a five-hour shift paying `$120.00` with a
    ///   partial route and two more deliveries, waiting 8 and 20 minutes.
    @MainActor
    private func launchWithPeriodSummary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPeriodSummaryArgument)
        launchInPortrait(app)
        return app
    }

    @MainActor
    private func openPeriodSummary(in app: XCUIApplication) {
        let link = app.buttons["periodSummaryLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "History offers a way into the summaries")
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["periodTitle"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func selectPeriod(_ title: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["periodUnitPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons[title].tap()
    }

    /// The week's earnings are the sum of the amounts recorded on its shifts,
    /// and the screen says how many shifts that was.
    @MainActor
    func testWeekSummaryShowsRecordedEarningsAndTheirCoverage() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Week", in: app)

        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabel(earnings, toContain: "$206.25"),
            "The week totals the two recorded amounts: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("2 of 3 completed shifts"),
            "And says how many shifts answered: \(earnings.label)"
        )
    }

    /// The subtotal is never presented as though every shift had answered.
    @MainActor
    func testPartialEarningsCoverageIsStatedRatherThanImplied() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(earnings, toContain: "$86.25"))
        XCTAssertTrue(
            earnings.label.contains("1 of 2 completed shifts"),
            "The day's third shift has no amount, and the screen says so: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("Recorded gross earnings"),
            "A subtotal is called recorded, never the day's earnings: \(earnings.label)"
        )
    }

    /// A period's mileage is a floor, and the partial routes behind it stay
    /// visible rather than being averaged into a clean-looking total.
    @MainActor
    func testPeriodMileageSurfacesPartialRouteCoverage() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let mileage = app.descendants(matching: .any)["periodMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(
            mileage.label.contains("Recorded mileage"),
            "Mileage is recorded, not driven: \(mileage.label)"
        )
        XCTAssertTrue(
            mileage.label.contains("1 of 2 completed shifts"),
            "The shift with no route is counted, not treated as zero miles: \(mileage.label)"
        )
        XCTAssertTrue(
            mileage.label.contains("partial route capture"),
            "And the partial route behind the figure is stated: \(mileage.label)"
        )
        XCTAssertFalse(
            mileage.label.lowercased().contains("driven"),
            "The figure itself must not claim miles driven: \(mileage.label)"
        )
    }

    /// The rate divides one paired subset of shifts, and says which.
    @MainActor
    func testPeriodPerMileRateStatesThePairedSubsetItUsed() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let rate = app.descendants(matching: .any)["periodPerMileRate"]
        XCTAssertTrue(scrollTo(rate, in: app))
        XCTAssertTrue(
            rate.label.contains("gross earnings per recorded mile"),
            "The rate names what it divides: \(rate.label)"
        )
        XCTAssertTrue(
            rate.label.contains("1 of 2 shifts with both earnings and a measurable route"),
            "Only the shift carrying both halves is behind it: \(rate.label)"
        )
    }

    /// The median is the middle of the individual pickups recorded in the
    /// period, shown with the number of them behind it.
    @MainActor
    func testWeeklyPickupWaitShowsMedianAndSampleCount() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Week", in: app)

        let wait = app.descendants(matching: .any)["periodPickupWait"]
        XCTAssertTrue(scrollTo(wait, in: app))
        XCTAssertTrue(
            waitForLabel(wait, toContain: "Median recorded pickup wait"),
            "Showed: \(wait.label)"
        )
        XCTAssertTrue(
            wait.label.contains("5 recorded pickups"),
            "The week's five recorded waits are the median's basis: \(wait.label)"
        )
        XCTAssertFalse(
            wait.label.lowercased().contains("typical"),
            "A period median is not offered as a typical wait: \(wait.label)"
        )
    }

    /// A period nobody drove in shows a sentence, not a grid of zeroes.
    @MainActor
    func testEmptyPeriodShowsARealEmptyState() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Week", in: app)

        app.buttons["periodPreviousButton"].tap()

        let empty = app.descendants(matching: .any)["periodEmptyState"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "No completed shifts recorded this week.")
        XCTAssertFalse(
            app.descendants(matching: .any)["periodEarnings"].exists,
            "An empty week shows no earnings figure at all, not $0.00"
        )
        XCTAssertFalse(app.descendants(matching: .any)["periodMileage"].exists)
    }

    /// Switching the unit changes which shifts are counted.
    @MainActor
    func testSwitchingBetweenDayAndWeekChangesTheShiftsCounted() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let shiftCount = app.descendants(matching: .any)["periodShiftCount"]
        XCTAssertTrue(shiftCount.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabel(shiftCount, toContain: "2 completed shifts"),
            "Today holds two of the fixture's shifts: \(shiftCount.label)"
        )

        selectPeriod("Week", in: app)
        XCTAssertTrue(
            waitForLabel(shiftCount, toContain: "3 completed shifts"),
            "The week holds the third as well: \(shiftCount.label)"
        )

        selectPeriod("Day", in: app)
        XCTAssertTrue(
            waitForLabel(shiftCount, toContain: "2 completed shifts"),
            "And switching back counts the day again: \(shiftCount.label)"
        )
    }

    /// The amounts recorded against individual deliveries appear as their own
    /// labelled subtotal, and never as the period's earnings.
    @MainActor
    func testDeliveryAmountsAreShownSeparatelyFromTheShiftTotal() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let subtotal = app.descendants(matching: .any)["periodDeliveryEarnings"]
        XCTAssertTrue(scrollTo(subtotal, in: app))
        XCTAssertTrue(
            subtotal.label.contains("$24.25"),
            "The two delivery amounts, added: \(subtotal.label)"
        )
        XCTAssertTrue(
            subtotal.label.contains("2 of 4 deliveries"),
            "Stated across the deliveries that answered: \(subtotal.label)"
        )
        XCTAssertTrue(
            subtotal.label.contains("separate record"),
            "And named as a separate record from the shift amounts: \(subtotal.label)"
        )

        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(scrollToTop(reaching: earnings, in: app))
        XCTAssertTrue(
            earnings.label.contains("$86.25"),
            "The headline stays the shift amount: \(earnings.label)"
        )
    }

    // MARK: Period comparison

    /// Launches against a throwaway store holding three consecutive days of
    /// synthetic completed shifts, anchored to today.
    ///
    /// By the rules of the driver's own calendar it holds:
    ///
    /// - **today**: four hours paying `$100.00`, and a two-hour shift with no
    ///   amount at all.
    /// - **yesterday**: five hours paying `$80.00`, the whole of that day.
    /// - **the day before**: five hours paying `$64.00`, the whole of that day.
    /// - **the day before that**: nothing.
    @MainActor
    private func launchWithPeriodComparison() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPeriodComparisonArgument)
        launchInPortrait(app)
        return app
    }

    @MainActor
    private func comparisonRow(_ metric: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["periodComparison.\(metric)"]
    }

    /// A day is read beside the day before it, with both figures on screen and
    /// the shifts behind each of them.
    ///
    /// Today is still in progress and one of its two shifts carries no amount,
    /// so the difference is stated and a percentage is not: a part of a day
    /// against the whole of one, over records that do not cover the day, is not
    /// a ratio of anything.
    @MainActor
    func testADayIsComparedWithTheDayBeforeItAndBothCoveragesAreShown() throws {
        let app = launchWithPeriodComparison()
        openPeriodSummary(in: app)

        let earnings = comparisonRow("recordedGrossEarnings", in: app)
        XCTAssertTrue(scrollTo(earnings, in: app), "The comparison is on the summary")
        XCTAssertTrue(
            earnings.label.contains("$100.00") && earnings.label.contains("$80.00"),
            "Both figures are printed, not only the difference: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("more recorded"),
            "A total moves by more or less recorded, never by better or worse: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("1 of 2 shifts") && earnings.label.contains("1 of 1 shift"),
            "The records behind both sides are stated: \(earnings.label)"
        )
        XCTAssertFalse(
            earnings.label.contains("%"),
            "No percentage against a day that has not finished: \(earnings.label)"
        )

        let notes = app.descendants(matching: .any)["periodComparisonNotes"]
        XCTAssertTrue(scrollTo(notes, in: app))
        XCTAssertTrue(
            notes.label.contains("still in progress"),
            "And the screen says why: \(notes.label)"
        )
    }

    /// Stepping back to a finished day, whose records cover it and whose
    /// predecessor's cover that one, is the case a percentage is stated in.
    @MainActor
    func testAFinishedDayWithCompleteRecordsStatesThePercentageChange() throws {
        let app = launchWithPeriodComparison()
        openPeriodSummary(in: app)

        app.buttons["periodPreviousButton"].tap()

        let earnings = comparisonRow("recordedGrossEarnings", in: app)
        XCTAssertTrue(scrollTo(earnings, in: app))
        XCTAssertTrue(
            waitForLabel(earnings, toContain: "$64.00"),
            "Yesterday is now read beside the day before it: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("$16.00 more recorded"),
            "The difference between the two recorded amounts: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("25%"),
            "Both days are complete and finished, so the percentage is stated: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("1 of 1 shift, compared with 1 of 1 shift"),
            "Over all of both days' shifts: \(earnings.label)"
        )
    }

    /// A day before which nothing was recorded is said to hold nothing. Its
    /// earnings are missing rather than zero, and the counts are still compared.
    @MainActor
    func testAnEmptyPreviousDayIsStatedRatherThanShownAsNoEarnings() throws {
        let app = launchWithPeriodComparison()
        openPeriodSummary(in: app)

        app.buttons["periodPreviousButton"].tap()
        app.buttons["periodPreviousButton"].tap()

        let previous = app.descendants(matching: .any)["periodComparisonPrevious"]
        XCTAssertTrue(scrollTo(previous, in: app))
        XCTAssertTrue(
            waitForLabel(previous, toContain: "No completed shift and no recorded expense"),
            "The day before this one holds nothing, and the screen says so: \(previous.label)"
        )

        let earnings = comparisonRow("recordedGrossEarnings", in: app)
        XCTAssertTrue(scrollTo(earnings, in: app))
        XCTAssertTrue(
            earnings.label.contains("Not recorded"),
            "A day with no amount recorded has no figure to compare: \(earnings.label)"
        )
        XCTAssertFalse(
            earnings.label.contains("$0.00"),
            "And is never read as a day that earned nothing: \(earnings.label)"
        )

        let shifts = comparisonRow("completedShifts", in: app)
        XCTAssertTrue(scrollTo(shifts, in: app))
        XCTAssertTrue(
            shifts.label.contains("1 more recorded"),
            "The counts are still compared, as counts of records: \(shifts.label)"
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
    // MARK: Export

    /// Opens the export sheet and waits for the file to be written.
    ///
    /// The share sheet itself is deliberately never opened. `ShareLink` presents
    /// a system surface XCUITest cannot inspect reliably, and what these
    /// journeys are for is proving that DashPilot produced a file and offered
    /// it — not that iOS can share one.
    @MainActor
    private func openExport(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(scrollTo(button, in: app), "The export control should be reachable")
        button.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["exportFileName"].waitForExistence(timeout: 10),
            "The sheet writes the file when it opens"
        )
    }

    @MainActor
    private func selectExportFormat(_ title: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["exportFormatPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons[title].tap()
    }

    @MainActor
    private func exportFileName(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["exportFileName"].label
    }

    /// A completed shift offers an export, and JSON is what it writes first.
    @MainActor
    func testCompletedShiftExportsJSON() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        openExport("exportShiftButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-Shift-"), "The file is named for its scope: \(name)")
        XCTAssertTrue(name.contains(".json"), "JSON is the default format: \(name)")
        XCTAssertTrue(name.contains("1 shift"), "The sheet says how much is in the file: \(name)")

        XCTAssertTrue(
            app.buttons["shareExportButton"].waitForExistence(timeout: 5),
            "A written file is offered to the share sheet"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["exportFailureMessage"].exists,
            "Nothing failed"
        )
    }

    /// Choosing CSV rewrites the file, and the name says so.
    @MainActor
    func testCompletedShiftExportsCSV() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        openExport("exportShiftButton", in: app)
        selectExportFormat("CSV", in: app)

        let fileName = app.descendants(matching: .any)["exportFileName"]
        XCTAssertTrue(
            waitForLabel(fileName, toContain: ".csv"),
            "The CSV file replaces the JSON one: \(fileName.label)"
        )
        XCTAssertTrue(app.buttons["shareExportButton"].exists, "And it is offered to the share sheet")
    }

    /// A period summary exports the period it is showing, named for it.
    @MainActor
    func testPeriodSummaryExportsTheSelectedPeriod() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Week", in: app)

        openExport("exportPeriodButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-Week-"), "The file names the period it covers: \(name)")
        XCTAssertTrue(name.contains("3 shifts"), "The week holds three completed shifts: \(name)")
    }

    /// Switching to Day exports a different period, with a different name.
    @MainActor
    func testDayAndWeekExportDifferentPeriods() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Day", in: app)

        openExport("exportPeriodButton", in: app)
        let day = exportFileName(in: app)
        XCTAssertTrue(day.contains("DashPilot-Day-"), "\(day)")
        XCTAssertTrue(day.contains("2 shifts"), "Today holds two of the three: \(day)")

        app.buttons["dismissExportButton"].tap()
        // The export control is at the bottom of the list, so dismissing leaves
        // the screen scrolled past the picker at the top of it.
        let picker = app.segmentedControls["periodUnitPicker"]
        XCTAssertTrue(scrollToTop(reaching: picker, in: app), "The summary is back")

        selectPeriod("Week", in: app)
        openExport("exportPeriodButton", in: app)
        let week = exportFileName(in: app)

        XCTAssertTrue(week.contains("DashPilot-Week-"), "\(week)")
        XCTAssertTrue(week.contains("3 shifts"), "The week holds one more than today: \(week)")
        XCTAssertNotEqual(day, week, "Each period exports its own records")
    }

    /// A period with nothing recorded in it offers no export at all, rather than
    /// an export that would have to be refused.
    @MainActor
    func testEmptyPeriodOffersNoExport() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Day", in: app)

        // Far enough back that the fixture's shifts cannot reach it.
        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        for _ in 0..<10 { previous.tap() }

        XCTAssertTrue(
            app.descendants(matching: .any)["periodEmptyState"].waitForExistence(timeout: 5),
            "The period is empty"
        )
        XCTAssertFalse(
            app.buttons["exportPeriodButton"].exists,
            "An empty period must not offer an export it would have to refuse"
        )
    }

    /// History as a whole can be exported, and the file holds every completed
    /// shift.
    @MainActor
    func testExportsAllHistory() throws {
        let app = launchWithSeededHistory()
        openExport("exportAllHistoryButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-History-"), "\(name)")
        XCTAssertTrue(name.contains("2 shifts"), "The seeded history holds two completed shifts: \(name)")
    }

    /// History's root lists one week and reads only that week from the store,
    /// and exporting all history still means every completed shift there is.
    @MainActor
    func testExportAllHistoryIsNotScopedToTheWeekOnScreen() throws {
        let app = launchWithOlderWeeks()
        XCTAssertTrue(scrollUntilHittable(rows(in: app).firstMatch, in: app))
        XCTAssertTrue(waitForCount(rows(in: app), toEqual: 1), "The root lists this week's one shift")

        // The export control sits above History, and the scroll helpers only
        // walk down, so the screen goes back to the top first.
        XCTAssertTrue(scrollToTop(reaching: app.buttons["exportAllHistoryButton"], in: app))
        openExport("exportAllHistoryButton", in: app)
        let name = exportFileName(in: app)
        XCTAssertTrue(
            name.contains("4 shifts"),
            "The file holds this week's shift and the three before it: \(name)"
        )
    }

    /// A running shift offers no export anywhere: not on the shift panel, and
    /// not through a history export that does not exist yet.
    @MainActor
    func testRunningShiftHasNoExportControl() throws {
        let app = launchWithEmptyStore()

        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        // Before starting: no completed shift, so no history export either.
        XCTAssertFalse(app.buttons["exportAllHistoryButton"].exists)

        start.tap()
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 5))

        XCTAssertFalse(
            app.buttons["exportShiftButton"].exists,
            "A running shift is not history and offers no export"
        )
        XCTAssertFalse(
            app.buttons["exportAllHistoryButton"].exists,
            "And it does not put anything exportable into history"
        )
    }

    // MARK: Month and chosen ranges

    /// The number a period's summary reports, or `nil` if it is showing an
    /// empty state instead.
    @MainActor
    private func shiftCount(in app: XCUIApplication) -> Int? {
        let element = app.descendants(matching: .any)["periodShiftCount"]
        guard element.waitForExistence(timeout: 10) else { return nil }
        // The spoken label is "4 completed shifts".
        return Int(element.label.prefix(while: \.isNumber))
    }

    @MainActor
    private func periodTitle(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["periodTitle"].label
    }

    /// A month holds at least everything its weeks and days do.
    ///
    /// Counted rather than asserted against a literal: the fixture is anchored
    /// to whenever the test runs, so which of its shifts share a month with
    /// today depends on the date. The relationship between the three is what
    /// this journey is about, and that holds on every date.
    @MainActor
    func testMonthSummaryIncludesTheWholeWeekAndMore() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        selectPeriod("Day", in: app)
        let day = try XCTUnwrap(shiftCount(in: app), "Today holds completed shifts")

        selectPeriod("Week", in: app)
        let week = try XCTUnwrap(shiftCount(in: app), "So does this week")

        selectPeriod("Month", in: app)
        let month = try XCTUnwrap(shiftCount(in: app), "And so does this month")

        XCTAssertLessThanOrEqual(day, week, "A week holds at least its days")
        XCTAssertLessThanOrEqual(week, month, "A month holds at least the part of the week inside it")
        XCTAssertGreaterThanOrEqual(month, 2, "The fixture's shifts are all in the month it is anchored to")
    }

    /// Stepping back from the current month changes which records are included.
    /// The fixture only holds recent shifts, so the month before it is empty —
    /// and says so, rather than showing a grid of zeroes.
    @MainActor
    func testPreviousMonthChangesTheRecordsIncluded() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Month", in: app)

        let current = periodTitle(in: app)
        XCTAssertNotNil(shiftCount(in: app), "This month holds the fixture's shifts")

        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        // Two steps back, so the month before is empty whichever day of the
        // month the test runs on.
        previous.tap()
        previous.tap()

        let empty = app.descendants(matching: .any)["periodEmptyState"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "An earlier month holds nothing")
        XCTAssertTrue(
            empty.label.contains("month"),
            "The empty state names the period it is about: \(empty.label)"
        )
        XCTAssertNotEqual(periodTitle(in: app), current, "And the title moved with it")
        XCTAssertFalse(app.buttons["exportPeriodButton"].exists, "An empty month offers no export")
    }

    /// The existing rule, applied to months: nothing is offered beyond the
    /// period the driver is in.
    @MainActor
    func testCurrentMonthCannotStepForward() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Month", in: app)

        let next = app.buttons["periodNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "A future month holds no records and is not offered")

        app.buttons["periodPreviousButton"].tap()
        XCTAssertTrue(next.isEnabled, "Once in the past, the way back to now is open")
    }

    /// Leaving the app and coming back keeps the period the driver had chosen.
    ///
    /// The summary re-reads the clock on returning to the foreground, so that a
    /// screen opened before midnight does not go on calling yesterday `Today`.
    /// That re-read must move the *naming* only: the period being read stays the
    /// one the driver stepped to, and its figures do not change underneath them.
    @MainActor
    func testSummarySurvivesLeavingAndReturningToTheApp() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Month", in: app)

        app.buttons["periodPreviousButton"].tap()
        let chosen = periodTitle(in: app)

        XCUIDevice.shared.press(.home)
        app.activate()

        let title = app.descendants(matching: .any)["periodTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The summary is still the screen on show")
        XCTAssertEqual(periodTitle(in: app), chosen, "The month the driver stepped to is still selected")
        XCTAssertTrue(
            app.buttons["periodNextButton"].isEnabled,
            "And the way back to the current month is still open"
        )
    }

    /// Choosing Custom and applying a range summarises the dates it covers.
    @MainActor
    func testCustomRangeSummarisesTheChosenDates() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Custom", in: app)

        // No stepping for a chosen range: there is no neighbouring range to
        // step to, so the chevrons are replaced by the way back to the picker.
        XCTAssertFalse(app.buttons["periodPreviousButton"].exists)
        XCTAssertFalse(app.buttons["periodNextButton"].exists)

        let choose = app.buttons["periodCustomRangeButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "A range is chosen, not stepped to")
        choose.tap()

        let summary = app.descendants(matching: .any)["customRangeSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The sheet says what the dates select")
        XCTAssertTrue(
            summary.label.contains("Custom reporting range"),
            "And says what kind of thing it is: \(summary.label)"
        )

        app.buttons["customRangeApplyButton"].tap()

        XCTAssertNotNil(shiftCount(in: app), "The applied range holds the fixture's recent shifts")
        XCTAssertTrue(
            periodTitle(in: app).contains("selected day"),
            "The chosen range says how many days it covers: \(periodTitle(in: app))"
        )
    }

    /// Cancel is not a quiet Apply. The period on screen is the one that was
    /// there before the sheet opened.
    @MainActor
    func testCancellingTheRangePickerChangesNothing() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Custom", in: app)

        let before = periodTitle(in: app)
        let count = shiftCount(in: app)

        let choose = app.buttons["periodCustomRangeButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        XCTAssertTrue(app.buttons["customRangeCancelButton"].waitForExistence(timeout: 5))
        app.buttons["customRangeCancelButton"].tap()

        XCTAssertTrue(choose.waitForExistence(timeout: 5), "Back on the summary")
        XCTAssertEqual(periodTitle(in: app), before, "Cancel left the range exactly as it was")
        XCTAssertEqual(shiftCount(in: app), count)
    }

    /// The chosen range survives a trip through the other period lengths, so a
    /// driver can compare it against a week without choosing it again.
    @MainActor
    func testTheChosenRangeSurvivesSwitchingAway() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Custom", in: app)

        let chosen = periodTitle(in: app)
        XCTAssertFalse(chosen.isEmpty)

        selectPeriod("Week", in: app)
        selectPeriod("Month", in: app)
        selectPeriod("Custom", in: app)

        XCTAssertEqual(periodTitle(in: app), chosen, "The range came back as it was left")
    }

    /// Exporting a month names the month it covers.
    @MainActor
    func testExportMonthOpensTheExportFlow() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Month", in: app)

        openExport("exportPeriodButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-Month-"), "The file names the month it covers: \(name)")
        XCTAssertTrue(app.buttons["shareExportButton"].exists, "And it is offered to the share sheet")
        XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists)
    }

    /// Exporting a chosen range names both of the days the driver selected.
    @MainActor
    func testExportCustomRangeOpensTheExportFlow() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Custom", in: app)

        openExport("exportPeriodButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-Range-"), "The file names the range it covers: \(name)")
        XCTAssertTrue(name.contains("-to-"), "Both selected days are in the name: \(name)")
        XCTAssertTrue(app.buttons["shareExportButton"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists)
    }

    // MARK: Expenses

    /// Opens the expense list from the root screen.
    @MainActor
    private func openExpenses(in app: XCUIApplication) {
        // In the navigation bar, so it is reachable wherever the list has been
        // scrolled to and costs the shift history no room.
        let link = app.buttons["expensesLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "The root screen offers a way into recorded expenses")
        link.tap()
        XCTAssertTrue(app.buttons["addExpenseButton"].waitForExistence(timeout: 10))
    }

    /// Records one expense through the editor, leaving the category and date at
    /// their defaults.
    @MainActor
    private func recordExpense(_ amount: String, in app: XCUIApplication) {
        app.buttons["addExpenseButton"].tap()

        let field = app.textFields["expenseAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(amount)

        app.buttons["saveExpenseButton"].tap()
        // The list is behind a sheet until the save dismisses it, and a tap
        // synthesised during that animation lands on nothing.
        XCTAssertTrue(
            app.buttons["saveExpenseButton"].waitForNonExistence(timeout: 5),
            "The editor closes once the expense is recorded"
        )
    }

    /// Record a cost, and find it in the list with what was entered.
    @MainActor
    func testRecordsAnExpense() throws {
        let app = launchWithEmptyStore()
        openExpenses(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["expensesEmptyState"].exists)

        recordExpense("42.10", in: app)

        let row = app.descendants(matching: .any).matching(identifier: "expenseRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(row, toContain: "$42.10"), "The amount entered: \(row.label)")
        XCTAssertTrue(row.label.contains("Fuel"), "And the category it was recorded under: \(row.label)")
        XCTAssertFalse(app.descendants(matching: .any)["expensesEmptyState"].exists)
    }

    /// An amount the parser refuses is not written, and the sheet says why.
    @MainActor
    func testInvalidExpenseAmountIsNotSaved() throws {
        let app = launchWithEmptyStore()
        openExpenses(in: app)

        app.buttons["addExpenseButton"].tap()
        let field = app.textFields["expenseAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("-5")

        app.buttons["saveExpenseButton"].tap()

        let message = validationMessage("expenseValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The refusal is explained rather than silent")
        XCTAssertTrue(
            message.label.lowercased().contains("negative"),
            "And it names the rule that was broken: \(message.label)"
        )

        app.buttons["cancelExpenseButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["expensesEmptyState"].waitForExistence(timeout: 5))
    }

    /// A recorded cost can be corrected, and removed.
    @MainActor
    func testEditsAndDeletesAnExpense() throws {
        let app = launchWithEmptyStore()
        openExpenses(in: app)
        recordExpense("42.10", in: app)

        let row = app.descendants(matching: .any).matching(identifier: "expenseRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let field = app.textFields["expenseAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "42.1", "The editor opens on what was recorded")
        clear(field, in: app)
        field.typeText("50.00")
        app.buttons["saveExpenseButton"].tap()
        XCTAssertTrue(app.buttons["saveExpenseButton"].waitForNonExistence(timeout: 5))

        XCTAssertTrue(waitForLabel(row, toContain: "$50.00"), "The correction is what the list shows")

        row.tap()
        let delete = app.buttons["deleteExpenseButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        XCTAssertTrue(app.descendants(matching: .any)["expensesEmptyState"].waitForExistence(timeout: 5))
    }

    /// A day's recorded costs, their categories, and what the recorded earnings
    /// come to after them.
    @MainActor
    func testPeriodSummaryShowsRecordedExpensesAndTheNetAfterThem() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let expenses = app.descendants(matching: .any)["periodExpenses"]
        XCTAssertTrue(scrollTo(expenses, in: app), "The summary reports what the day cost")
        XCTAssertTrue(
            waitForLabel(expenses, toContain: "$48.60"),
            "The two costs recorded today, added up: \(expenses.label)"
        )
        XCTAssertTrue(
            expenses.label.contains("2 recorded expenses"),
            "With the count of records behind it: \(expenses.label)"
        )

        let categories = app.descendants(matching: .any).matching(identifier: "periodExpenseCategory")
        XCTAssertEqual(categories.count, 2, "Fuel and parking, and no category with nothing in it")

        let net = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            waitForLabel(net, toContain: "$37.65"),
            "$86.25 recorded, less $48.60 recorded: \(net.label)"
        )
    }

    /// The net figure never presents itself as profit, and never without the
    /// counts behind both of its halves.
    @MainActor
    func testNetAfterExpensesIsNotCalledProfit() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let net = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(waitForLabel(net, toContain: "net after recorded expenses"))
        XCTAssertTrue(
            net.label.contains("1 of 2 shifts"),
            "The earnings half is a subtotal, and says so: \(net.label)"
        )
        XCTAssertTrue(
            net.label.contains("not profit"),
            "And the figure states what it is not: \(net.label)"
        )
    }

    /// Recording costs changes nothing about the gross figures beside them.
    @MainActor
    func testExpensesLeaveTheGrossFiguresAlone() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForLabel(earnings, toContain: "$86.25"),
            "Gross earnings are still the amounts recorded on the shifts: \(earnings.label)"
        )
        XCTAssertTrue(earnings.label.contains("Recorded gross earnings"))
        XCTAssertFalse(earnings.label.contains("$37.65"), "The net is a separate figure, in its own section")
    }

    /// A cost recorded on a day with no shift is still that day's record.
    @MainActor
    func testExpenseOnADayWithoutAShiftIsStillSummarised() throws {
        let app = launchWithEmptyStore()
        openExpenses(in: app)
        recordExpense("42.10", in: app)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPeriodSummary(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["periodEmptyState"].waitForExistence(timeout: 5),
            "The day still holds no completed shift, and says so"
        )

        let expenses = app.descendants(matching: .any)["periodExpenses"]
        XCTAssertTrue(scrollTo(expenses, in: app), "But the cost recorded on it is not hidden behind that")
        XCTAssertTrue(waitForLabel(expenses, toContain: "$42.10"))

        let net = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            net.label.lowercased().contains("no net after recorded expenses"),
            "With no recorded earnings there is nothing to net, rather than a negative figure: \(net.label)"
        )
    }

    @MainActor
    func testShowsLocationAuthorizationState() throws {
        let app = launchWithEmptyStore()

        let status = app.descendants(matching: .any)["locationAuthorizationStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }

    // MARK: What a running shift says about recording

    /// The status line states what recording promises, rather than a green label
    /// and silence.
    @MainActor
    func testRunningShiftSaysWhatRecordingDoesAndDoesNotPromise() throws {
        let app = launchWithStubbedLocation()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        let label = status.label
        XCTAssertTrue(
            label.contains("Location tracking active"),
            "With permission granted and a shift running, capture is running: \(label)"
        )
        // The two halves of the honest claim: it carries on off screen, and it
        // is not guaranteed. Neither may be dropped for a tidier line.
        XCTAssertTrue(
            label.lowercased().contains("other apps") && label.lowercased().contains("locked"),
            "The line has to say recording continues off screen: \(label)"
        )
        XCTAssertTrue(
            label.lowercased().contains("ios can still stop it"),
            "The line must not imply guaranteed recording: \(label)"
        )
    }

    /// Leaving the app and coming back leaves the screen saying it is recording.
    ///
    /// What this reaches that a unit test cannot is the real chain: an actual
    /// scene phase, `RootView`'s reaction to it, and a status line rebuilt from
    /// whatever the capture service decided. What it deliberately does **not**
    /// claim is that the capture session was continuous across the transition:
    /// that is a fact about stored samples, and it is asserted where it can be
    /// read, in `LocationTrackingServiceTests` and `RealWorldRecoveryTests`.
    @MainActor
    func testRecordingSurvivesLeavingAndReturningToTheApp() throws {
        let app = launchWithStubbedLocation()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Location tracking active"))

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 10))
        let returned = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        XCTAssertTrue(
            returned.label.contains("Location tracking active"),
            "A session that was never stopped must not come back describing a pause: \(returned.label)"
        )
        XCTAssertFalse(
            returned.label.contains("Route recording paused"),
            "Returning claimed a break that did not happen: \(returned.label)"
        )
    }

    /// The permission panel says which scope is asked for and what it limits.
    @MainActor
    func testLocationPanelStatesTheScopeAndItsLimit() throws {
        let app = launchWithStubbedLocation()

        let panel = app.descendants(matching: .any)["locationAuthorizationPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollTo(panel, in: app))

        let text = panel.descendants(matching: .staticText).allElementsBoundByIndex
            .map(\.label)
            .joined(separator: " ")
            .lowercased()

        XCTAssertTrue(
            text.contains("another app") || text.contains("screen is locked"),
            "An authorized driver should be told recording carries on off screen: \(text)"
        )
        XCTAssertTrue(
            text.contains("started with dashpilot open"),
            "The limit of this scope is the thing a driver can be caught by: \(text)"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
