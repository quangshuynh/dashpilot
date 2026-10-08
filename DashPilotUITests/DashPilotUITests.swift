import XCTest

final class DashPilotUITests: XCTestCase {
    /// Must match `LaunchArgument.inMemoryStore`; a UI test target cannot link the app target.
    private static let inMemoryStoreArgument = "-dashpilot-in-memory-store"

    /// Must match `LaunchArgument.seededHistory`, for the same reason.
    private static let seededHistoryArgument = "-dashpilot-seeded-history"

    /// Must match `LaunchArgument.seededActiveDelivery`, for the same reason.
    private static let seededActiveDeliveryArgument = "-dashpilot-seeded-active-delivery"

    /// Must match `LaunchArgument.seededPeriodSummary`, for the same reason.
    private static let seededPeriodSummaryArgument = "-dashpilot-seeded-period-summary"

    /// Must match `LaunchArgument.seededMissedLifecycle`, for the same reason.
    private static let seededMissedLifecycleArgument = "-dashpilot-seeded-missed-lifecycle"

    /// Must match `LaunchArgument.seededStackedOffer`, for the same reason.
    private static let seededStackedOfferArgument = "-dashpilot-seeded-stacked-offer"

    /// Must match `LaunchArgument.seededPausedHistory`, for the same reason.
    private static let seededPausedHistoryArgument = "-dashpilot-seeded-paused-history"

    /// Must match `LaunchArgument.seededLateDeliveryHistory`, for the same reason.
    private static let seededLateDeliveryHistoryArgument = "-dashpilot-seeded-late-delivery-history"

    /// Must match `LaunchArgument.seededOlderWeeks`, for the same reason.
    private static let seededOlderWeeksArgument = "-dashpilot-seeded-older-weeks"

    /// Must match `LaunchArgument.seededOlderWeeksOnly`, for the same reason.
    private static let seededOlderWeeksOnlyArgument = "-dashpilot-seeded-older-weeks-only"

    /// Must match `OnboardingRecord.fresh`: forget the welcome was finished and
    /// let it show over a throwaway store.
    private static let onboardingFreshArgument = "-dashpilot-onboarding-fresh"

    /// Must match `OnboardingRecord.observe`: let it show over a throwaway
    /// store without forgetting.
    private static let onboardingObserveArgument = "-dashpilot-onboarding-observe"

    /// Must match `OnboardingRecord.completed`.
    private static let onboardingCompletedArgument = "-dashpilot-onboarding-completed"

    /// Must match `LaunchArgument.simulatedRoute`, for the same reason.
    private static let simulatedRouteArgument = "-dashpilot-simulated-route"

    /// How long a journey waits for a condition it has caused, such as a row
    /// reading Selected after a tap.
    ///
    /// A wait returns the moment its condition holds, so this costs a passing
    /// run nothing; it only decides how long a failing one looks. It was 5 s,
    /// and CI run 37088082650 showed why that is too short on a loaded runner:
    /// in `testChangingSettingsMidShiftLeavesTheRunningShiftsVehicleAlone` one
    /// query took 5.3 s and one tap 8.8 s, the recording shows the vehicle
    /// selected before the wait began, and the 5-second wait still expired
    /// after a single stale evaluation. 15 s is three of the slowest measured
    /// snapshots, not a sleep.
    static let conditionTimeout: TimeInterval = 15

    /// The largest accessibility text size iOS offers, as UIKit names it.
    private static let accessibilityXXXLTextSize = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Keeps the screen as it was at the failing assertion, on the issue
    /// itself, so a red run is read from the step that failed rather than by
    /// scrubbing the whole recording for it.
    override func record(_ issue: XCTIssue) {
        var issue = issue
        let screenshot = MainActor.assumeIsolated { XCUIScreen.main.screenshot() }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Screen at failure"
        attachment.lifetime = .keepAlways
        issue.add(attachment)
        super.record(issue)
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
        // The real store, so the welcome would show on a fresh simulator; this
        // journey is about the store opening, so the welcome counts as seen.
        app.launchArguments.append(Self.onboardingCompletedArgument)
        launchInPortrait(app)

        XCTAssertTrue(app.navigationBars["DashPilot"].appears())
        XCTAssertFalse(app.staticTexts["Local Data Unavailable"].exists)
    }

    // MARK: The welcome

    /// A first launch opens on the welcome, which steps through four screens
    /// and closes on Start Using DashPilot; a relaunch does not show it again.
    ///
    /// Copy and artwork are not asserted line by line: what a journey can
    /// prove is that a new driver meets it, can finish it, and is not met by it
    /// twice. When it is shown is `OnboardingPolicyTests`'.
    @MainActor
    func testFirstLaunchShowsTheWelcomeOnceAndFinishingItPersists() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.inMemoryStoreArgument, Self.onboardingFreshArgument]
        launchInPortrait(app)

        let step = app.staticTexts["onboardingStep"]
        XCTAssertTrue(step.appears(), "A new driver is welcomed")
        XCTAssertEqual(step.label, "Step 1 of 4", "The step is said in words")
        XCTAssertFalse(app.buttons["startShiftButton"].isHittable, "The welcome is in front of the shift screen")

        let next = app.buttons["nextOnboardingButton"]
        XCTAssertEqual(next.label, "Get Started")
        for page in 2...4 {
            next.tap()
            XCTAssertTrue(waitForLabel(step, toContain: "Step \(page) of 4"))
        }
        XCTAssertTrue(app.buttons["onboardingBackButton"].exists, "A driver can go back")
        XCTAssertFalse(app.buttons["skipOnboardingButton"].exists, "The last screen has its own way out")

        let finish = app.buttons["finishOnboardingButton"]
        XCTAssertEqual(finish.label, "Start Using DashPilot")
        XCTAssertGreaterThanOrEqual(onPixelGrid(finish.frame.height), 44)
        finish.tap()
        XCTAssertTrue(app.buttons["startShiftButton"].appears())
        XCTAssertTrue(waitForDisappearance(of: step))

        // Relaunched without forgetting: the welcome stays finished.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments += [Self.inMemoryStoreArgument, Self.onboardingObserveArgument]
        launchInPortrait(again)
        XCTAssertTrue(again.buttons["startShiftButton"].appears())
        XCTAssertFalse(again.staticTexts["onboardingStep"].exists, "Shown once, not on every launch")
    }

    /// The welcome reopens from Settings, reads at the largest text size with
    /// its controls whole and reachable, and closes back to Settings.
    @MainActor
    func testTheWelcomeReopensFromSettingsAtTheLargestTextSize() throws {
        let app = launchWithEmptyStore(textSize: Self.accessibilityXXXLTextSize)
        XCTAssertFalse(app.staticTexts["onboardingStep"].exists, "Not shown over a throwaway store unasked")

        openSettings(in: app)
        let reopen = app.buttons["reopenOnboardingButton"]
        XCTAssertTrue(scrollUntilHittable(reopen, in: app, maxSwipes: 20))
        reopen.tap()

        let title = app.staticTexts.matching(identifier: "onboardingTitle").firstMatch
        XCTAssertTrue(title.appears())
        XCTAssertEqual(app.staticTexts["onboardingStep"].label, "Step 1 of 4")
        let next = app.buttons["nextOnboardingButton"]
        XCTAssertTrue(next.isHittable, "The primary control is reachable at the largest size")
        XCTAssertGreaterThanOrEqual(onPixelGrid(next.frame.height), 44)
        attachScreenshot("onboarding-largest-text")

        let close = app.buttons["skipOnboardingButton"]
        XCTAssertEqual(close.label, "Close", "Reopened, it closes rather than skips")
        XCTAssertGreaterThanOrEqual(onPixelGrid(close.frame.height), 44)
        close.tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears())
    }

    /// Start a shift, see it running, end it, and find it in history.
    @MainActor
    func testStartsAndEndsAShift() throws {
        let app = launchWithEmptyStore()

        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.appears())

        startButton.tap()

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(endButton.appears())
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["workingTime"].exists)
        // A driver has to be able to see whether their route is being recorded.
        // Only its presence is asserted: which state it shows depends on the
        // simulator's location permission, and every mapping from a capture
        // state to what is displayed is covered by the service tests instead.
        XCTAssertTrue(app.descendants(matching: .any)["routeCaptureStatus"].exists)
        XCTAssertFalse(startButton.exists, "Only one shift may be running at a time")

        endButton.tap()

        XCTAssertTrue(startButton.appears())
        XCTAssertFalse(endButton.exists)
        XCTAssertTrue(
            scrollUntilHittable(rows(in: app).firstMatch, in: app),
            "The finished shift should appear in history"
        )
    }

    // MARK: Home

    /// Which vehicle a shift records, before and after Start: Home says what
    /// the next shift would record, says only the half that is known, follows
    /// Settings until a shift starts, and from the tap the running shift reads
    /// its own snapshot, which a later selection or correction of the profile
    /// does not move, even across leaving the app.
    ///
    /// Was seven journeys, each adding the same vehicle. The snapshot rules are
    /// `ShiftVehicleContextTests` and `RecordedShiftVehicleTests`, including a
    /// shift started with no vehicle at all.
    @MainActor
    func testHomeNamesTheNextShiftsVehicleAndTheShiftKeepsItsOwn() throws {
        let app = launchWithEmptyStore()

        // A price with no vehicle: the known half, and no 0 MPG.
        openSettings(in: app)
        setCurrentGasPrice("3.29", in: app)
        goBack(in: app)
        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.appears())
        XCTAssertEqual(next.label, "Next shift vehicle")
        XCTAssertTrue(
            waitForLabelValue(next, toEqual: "No vehicle selected for the next shift, gas $3.29 per gallon"),
            "Showed: \(String(describing: next.value))"
        )

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)
        XCTAssertTrue(
            waitForLabelValue(next, toEqual: "2020 Honda Civic, 34 miles per gallon, gas $3.29 per gallon"),
            "Showed: \(String(describing: next.value))"
        )
        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(start.isHittable, "Start Shift is on the first screen, not below the fold")
        XCTAssertLessThan(next.frame.minY, start.frame.minY, "What will be recorded comes before the control")
        XCTAssertFalse(app.descendants(matching: .any)["activeShiftVehicle"].exists)
        attachScreenshot("home-pre-shift")

        // No shift yet, so a change in Settings is a change to the next one.
        openSettings(in: app)
        addVehicle(named: "2012 Toyota Camry", milesPerGallon: "28", in: app)
        let camry = vehicleRow(containing: "2012 Toyota Camry", in: app)
        XCTAssertTrue(scrollUntilHittable(camry, in: app))
        camry.tap()
        XCTAssertTrue(waitForLabel(vehicleRow(containing: "2012 Toyota Camry", in: app), toContain: "Selected"))
        goBack(in: app)
        XCTAssertTrue(
            waitForLabelValue(next, toEqual: "2012 Toyota Camry, 28 miles per gallon, gas $3.29 per gallon"),
            "Home follows the selection while no shift has recorded one: \(String(describing: next.value))"
        )

        // From the tap, the shift's own snapshot.
        start.tap()
        let running = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(running, in: app))
        XCTAssertEqual(running.label, "Shift vehicle")
        XCTAssertEqual(running.value as? String, "2012 Toyota Camry, 28 miles per gallon", "What Home said is what was recorded")
        XCTAssertFalse(next.exists, "The next shift's row leaves with the Start Shift control")

        openSettings(in: app)
        let civic = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(scrollUntilHittable(civic, in: app))
        civic.tap()
        XCTAssertTrue(waitForLabel(vehicleRow(containing: "2020 Honda Civic", in: app), toContain: "Selected"))
        let edit = app.buttons["Edit 2012 Toyota Camry"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        XCTAssertTrue(economyField.appears())
        replaceTappedField(economyField, with: "41", in: app)
        app.buttons["saveVehicleButton"].tap()
        assertVehicleSheetClosed(in: app)
        goBack(in: app)

        XCTAssertTrue(scrollTo(running, in: app))
        XCTAssertEqual(
            running.value as? String,
            "2012 Toyota Camry, 28 miles per gallon",
            "The shift is worked under what it recorded, not under what is selected now"
        )
        XCUIDevice.shared.press(.home)
        app.activate()
        let returned = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(returned, in: app))
        XCTAssertEqual(returned.value as? String, "2012 Toyota Camry, 28 miles per gallon")
        XCTAssertFalse(app.descendants(matching: .any)["nextShiftVehicle"].exists)
    }

    /// One day's summary, read top to bottom: every figure states the coverage
    /// behind it, none claims more than its records, and the day exports its
    /// own records.
    ///
    /// The arithmetic behind every number is pinned in `PeriodMetricsTests`,
    /// `PeriodExpenseMetricsTests` and `PeriodFuelMetricsTests`; what only the
    /// screen can show is that each figure reaches it with its wording and its
    /// counts, which one pass down the list reads in the order it is drawn.
    @MainActor
    func testTheDaySummaryStatesEachFigureWithItsCoverage() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        // Earnings: a subtotal, called recorded, with the shifts behind it, and
        // untouched by the expenses recorded beside it.
        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(earnings.appears())
        XCTAssertTrue(waitForLabel(earnings, toContain: "$86.25"), "Showed: \(earnings.label)")
        XCTAssertTrue(
            earnings.label.contains("1 of 2 completed shifts"),
            "The day's other shift has no amount, and the screen says so: \(earnings.label)"
        )
        XCTAssertTrue(
            earnings.label.contains("Recorded gross earnings"),
            "A subtotal is called recorded, never the day's earnings: \(earnings.label)"
        )
        XCTAssertFalse(earnings.label.contains("$37.65"), "The net is a separate figure, in its own section")
        let shiftCount = app.descendants(matching: .any)["periodShiftCount"]
        XCTAssertTrue(scrollTo(shiftCount, in: app))
        XCTAssertTrue(waitForLabel(shiftCount, toContain: "2 completed shifts"), "Showed: \(shiftCount.label)")

        // Recorded expenses and the net after them, which is not profit.
        let expenses = app.descendants(matching: .any)["periodExpenses"]
        XCTAssertTrue(scrollTo(expenses, in: app), "The summary reports what the day cost")
        XCTAssertTrue(waitForLabel(expenses, toContain: "$48.60"), "Showed: \(expenses.label)")
        XCTAssertTrue(expenses.label.contains("2 recorded expenses"), "Showed: \(expenses.label)")
        let categories = app.descendants(matching: .any).matching(identifier: "periodExpenseCategory")
        XCTAssertEqual(categories.count, 2, "Fuel and parking, and no category with nothing in it")

        let net = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(waitForLabel(net, toContain: "$37.65"), "$86.25 less $48.60: \(net.label)")
        XCTAssertTrue(net.label.contains("net after recorded expenses"), "Showed: \(net.label)")
        XCTAssertTrue(net.label.contains("1 of 2 shifts"), "The earnings half is a subtotal: \(net.label)")
        XCTAssertTrue(net.label.contains("not profit"), "And the figure states what it is not: \(net.label)")
        XCTAssertFalse(net.label.contains("estimated fuel"), "No estimate is folded in: \(net.label)")

        // Mileage is a floor, and the rate over it names its paired subset.
        let mileage = app.descendants(matching: .any)["periodMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app, maxSwipes: 14))
        XCTAssertTrue(mileage.label.contains("Recorded mileage"), "Showed: \(mileage.label)")
        XCTAssertTrue(
            mileage.label.contains("1 of 2 completed shifts"),
            "The shift with no route is counted, not treated as zero miles: \(mileage.label)"
        )
        XCTAssertTrue(mileage.label.contains("partial route capture"), "Showed: \(mileage.label)")
        XCTAssertFalse(mileage.label.lowercased().contains("driven"), "Showed: \(mileage.label)")

        let rate = app.descendants(matching: .any)["periodPerMileRate"]
        XCTAssertTrue(scrollTo(rate, in: app, maxSwipes: 14))
        XCTAssertTrue(rate.label.contains("gross earnings per recorded mile"), "Showed: \(rate.label)")
        XCTAssertTrue(
            rate.label.contains("1 of 2 shifts with both earnings and a measurable route"),
            "Only the shift carrying both halves is behind it: \(rate.label)"
        )

        // Delivery amounts, as their own subtotal and never the headline.
        let subtotal = app.descendants(matching: .any)["periodDeliveryEarnings"]
        XCTAssertTrue(scrollTo(subtotal, in: app, maxSwipes: 14))
        XCTAssertTrue(subtotal.label.contains("$24.25"), "The two delivery amounts, added: \(subtotal.label)")
        XCTAssertTrue(subtotal.label.contains("2 of 4 deliveries"), "Showed: \(subtotal.label)")
        XCTAssertTrue(subtotal.label.contains("separate record"), "Showed: \(subtotal.label)")

        // The estimates, after every recorded figure, each with its coverage.
        let fuel = app.descendants(matching: .any)["periodEstimatedFuel"]
        XCTAssertTrue(scrollTo(fuel, in: app, maxSwipes: 14))
        XCTAssertTrue(waitForLabel(fuel, toContain: "Estimated fuel"), "Showed: \(fuel.label)")
        XCTAssertTrue(fuel.label.contains("$"), "And it states an amount: \(fuel.label)")
        XCTAssertTrue(fuel.label.contains("1 of 2 completed shifts"), "Showed: \(fuel.label)")
        XCTAssertTrue(fuel.label.contains("recorded miles"), "Showed: \(fuel.label)")

        let estimatedNet = app.descendants(matching: .any)["periodEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(estimatedNet, in: app, maxSwipes: 14))
        XCTAssertTrue(waitForLabel(estimatedNet, toContain: "Estimated net after fuel"), "Showed: \(estimatedNet.label)")
        XCTAssertTrue(estimatedNet.label.contains("1 of 2 shifts"), "Showed: \(estimatedNet.label)")
        XCTAssertTrue(
            estimatedNet.label.contains("not this period's earnings less this period's fuel"),
            "And refuses to be read as the period's: \(estimatedNet.label)"
        )
        XCTAssertTrue(estimatedNet.label.contains("never added together"), "Showed: \(estimatedNet.label)")

        // The day exports its own records, named for it. Which records each
        // scope selects, for a week, a month and a range too, is
        // `MonthAndRangeExportTests`.
        openExport("exportPeriodButton", in: app)
        let file = exportFileName(in: app)
        XCTAssertTrue(file.contains("DashPilot-Day-"), "The file is named for its scope: \(file)")
        XCTAssertTrue(file.contains("2 shifts"), "Today holds two of the fixture's three shifts: \(file)")
        XCTAssertTrue(app.buttons["shareExportButton"].exists, "Offered to the share sheet")
        XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists, "Nothing failed")
    }

    /// Months: a month holds at least its days and any week inside it; the
    /// current month cannot step forward; a month stepped back to survives
    /// leaving the app; and an empty month names itself and offers no export.
    ///
    /// Was four journeys over this fixture. Month boundaries are
    /// `MonthAndCustomPeriodTests`.
    @MainActor
    func testMonthsHoldTheirDaysStepBackAndSurviveLeavingTheApp() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        selectPeriod("Day", in: app)
        let day = try XCTUnwrap(shiftCount(in: app), "Today holds completed shifts")
        selectPeriod("Week", in: app)
        let week = try XCTUnwrap(shiftCount(in: app), "So does this week")
        selectPeriod("Month", in: app)
        let month = try XCTUnwrap(shiftCount(in: app), "And so does this month")
        XCTAssertLessThanOrEqual(day, week, "A week holds at least its days")
        XCTAssertLessThanOrEqual(day, month, "A month holds at least its days")
        // A week can straddle two months (the week of 1 October 2026 began in
        // September), so `week <= month` holds only for a week inside the month.
        if Self.currentWeekIsInsideCurrentMonth() {
            XCTAssertLessThanOrEqual(week, month, "A month holds at least a week that lies inside it")
        }
        XCTAssertGreaterThanOrEqual(month, 2, "The fixture's shifts are all in the month it is anchored to")
        let current = periodTitle(in: app)

        let next = app.buttons["periodNextButton"]
        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(next.appears())
        XCTAssertFalse(next.isEnabled, "A future month holds no records and is not offered")
        previous.tap()
        XCTAssertTrue(next.isEnabled, "Once in the past, the way back to now is open")
        let chosen = periodTitle(in: app)

        // Re-reading the clock on return moves the naming only.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["periodTitle"].appears())
        XCTAssertEqual(periodTitle(in: app), chosen, "The month the driver stepped to is still selected")
        XCTAssertTrue(next.isEnabled)

        // Two steps back, so the month is empty whichever day the test runs on.
        previous.tap()
        let empty = app.descendants(matching: .any)["periodEmptyState"]
        XCTAssertTrue(empty.appears(), "An earlier month holds nothing")
        XCTAssertTrue(empty.label.contains("month"), "The empty state names its period: \(empty.label)")
        XCTAssertNotEqual(periodTitle(in: app), current)
        XCTAssertFalse(app.buttons["exportPeriodButton"].exists, "An empty month offers no export")
    }

    /// A completed shift exports JSON first, named for its scope and size, and
    /// choosing CSV rewrites the file under a new name.
    ///
    /// Was two journeys. What the files hold is `ShiftExportJSONTests` and
    /// `ShiftExportCSVTests`.
    @MainActor
    func testAShiftExportsAsJSONOrCSV() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        openExport("exportShiftButton", in: app)

        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-Shift-"), "The file is named for its scope: \(name)")
        XCTAssertTrue(name.contains(".json"), "JSON is the default format: \(name)")
        XCTAssertTrue(name.contains("1 shift"), "The sheet says how much is in the file: \(name)")
        XCTAssertTrue(app.buttons["shareExportButton"].appears(), "Offered to the share sheet")
        XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists, "Nothing failed")

        selectExportFormat("CSV", in: app)
        let fileName = app.descendants(matching: .any)["exportFileName"]
        XCTAssertTrue(waitForLabel(fileName, toContain: ".csv"), "The CSV file replaces the JSON one: \(fileName.label)")
        XCTAssertTrue(app.buttons["shareExportButton"].exists)
    }

    /// Expenses: a negative amount is refused with the rule it broke and
    /// nothing written; a cost is recorded with its category, corrected and
    /// deleted; and a cost on a day with no shift is still that day's record,
    /// with no net invented from it.
    ///
    /// Was four journeys. Parsing is `ExpenseTests`; the period's
    /// arithmetic is `PeriodExpenseMetricsTests`.
    @MainActor
    func testExpensesAreRecordedRefusedCorrectedAndSummarised() throws {
        let app = launchWithEmptyStore()
        openExpenses(in: app)
        let empty = app.descendants(matching: .any)["expensesEmptyState"]
        XCTAssertTrue(empty.exists)

        app.buttons["addExpenseButton"].tap()
        let field = app.textFields["expenseAmountField"]
        XCTAssertTrue(field.appears())
        enter("-5", into: field, in: app)
        app.buttons["saveExpenseButton"].tap()
        let message = validationMessage("expenseValidationMessage", in: app)
        XCTAssertTrue(message.appears(), "The refusal is explained rather than silent")
        XCTAssertTrue(message.label.lowercased().contains("negative"), "It names the rule: \(message.label)")
        app.buttons["cancelExpenseButton"].tap()
        XCTAssertTrue(empty.appears(), "Nothing refused was written")

        recordExpense("42.10", in: app)
        let row = app.descendants(matching: .any).matching(identifier: "expenseRow").firstMatch
        XCTAssertTrue(row.appears())
        XCTAssertTrue(waitForLabel(row, toContain: "$42.10"), "The amount entered: \(row.label)")
        XCTAssertTrue(row.label.contains("Fuel"), "And its category: \(row.label)")
        XCTAssertFalse(empty.exists)

        row.tap()
        XCTAssertTrue(field.appears())
        XCTAssertEqual(field.value as? String, "42.1", "The editor opens on what was recorded")
        clear(field, in: app)
        enter("50.00", into: field, in: app)
        app.buttons["saveExpenseButton"].tap()
        XCTAssertTrue(app.buttons["saveExpenseButton"].disappears())
        XCTAssertTrue(waitForLabel(row, toContain: "$50.00"), "The correction is what the list shows")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPeriodSummary(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["periodEmptyState"].appears(),
            "The day still holds no completed shift, and says so"
        )
        let expenses = app.descendants(matching: .any)["periodExpenses"]
        XCTAssertTrue(scrollTo(expenses, in: app), "But the cost recorded on it is not hidden behind that")
        XCTAssertTrue(waitForLabel(expenses, toContain: "$50.00"))
        let net = app.descendants(matching: .any)["periodNetAfterExpenses"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(
            net.label.lowercased().contains("no net after recorded expenses"),
            "With no recorded earnings there is nothing to net: \(net.label)"
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openExpenses(in: app)
        XCTAssertTrue(row.appears())
        row.tap()
        let delete = app.buttons["deleteExpenseButton"]
        XCTAssertTrue(delete.appears())
        delete.tap()
        XCTAssertTrue(empty.appears())
    }

    /// Park and Pause are different states of a running shift, told apart by
    /// more than colour, and each changes exactly what it should.
    ///
    /// Parked: the shift still runs, the route stops, and the delivery entry
    /// stays because an offer can arrive at a counter. Paused: working time
    /// stops, the capture line says so, no delivery can be started, the shift is
    /// still the shift in progress and nothing reaches history; resuming brings
    /// it all back, and ending it after a pause is one shift in history.
    ///
    /// Was five journeys, each launching an empty store and starting a shift.
    @MainActor
    func testParkAndPauseAreDistinctStatesOfTheRunningShift() throws {
        let app = launchWithEmptyStore()
        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.appears())
        startShift.tap()

        XCTAssertTrue(app.buttons["pauseShiftButton"].appears())
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertFalse(app.buttons["resumeShiftButton"].exists)
        let entry = app.buttons["startDeliveryButton"]
        XCTAssertTrue(entry.appears())

        pressPark(in: app)
        let parked = app.descendants(matching: .any)["parkedShiftNotice"]
        XCTAssertTrue(parked.appears())
        XCTAssertTrue(parked.label.contains("Parked") && parked.label.contains("still running"), "Showed: \(parked.label)")
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists, "A parked shift is still running")
        XCTAssertFalse(app.descendants(matching: .any)["pausedShiftStatus"].exists, "Parked is not paused")
        XCTAssertTrue(entry.isHittable, "Parked: an accepted offer can still be recorded")
        attachScreenshot("home-parked")
        pressResumeDriving(in: app)

        let pause = app.buttons["pauseShiftButton"]
        XCTAssertTrue(reachShiftControl(pause, in: app))
        pause.tap()
        let resume = app.buttons["resumeShiftButton"]
        XCTAssertTrue(resume.appears())
        XCTAssertTrue(
            app.descendants(matching: .any)["pausedShiftStatus"].appears(),
            "A paused shift says it is paused rather than looking like a running one"
        )
        XCTAssertFalse(app.descendants(matching: .any)["parkedShiftNotice"].exists, "Paused is not parked")
        XCTAssertFalse(app.buttons["parkShiftButton"].exists, "Parking is withheld while paused")
        let working = app.descendants(matching: .any)["workingTime"]
        XCTAssertTrue(working.exists, "A driver on a break still sees how long they have worked")
        XCTAssertEqual(working.label, "Working time, paused")
        XCTAssertTrue(app.buttons["endShiftButton"].exists, "And can end the shift without resuming")
        XCTAssertTrue(waitForDisappearance(of: entry), "Paused: nothing offers to start a delivery")
        XCTAssertTrue(app.descendants(matching: .any)["pausedDeliveryNotice"].exists, "And the panel says why")
        XCTAssertFalse(startShift.exists, "A paused shift is still the shift in progress")
        XCTAssertEqual(rows(in: app).count, 0, "Nothing has reached history")
        let capture = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(reachShiftControl(capture, in: app))
        XCTAssertTrue(
            capture.label.lowercased().contains("paused") || capture.label.lowercased().contains("stopped"),
            "The capture line says recording stopped, not that something failed: \(capture.label)"
        )
        attachScreenshot("home-paused")

        XCTAssertTrue(scrollToTop(reaching: resume, in: app))
        resume.tap()
        XCTAssertTrue(app.buttons["pauseShiftButton"].appears())
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertTrue(entry.appears(), "Resumed: the entry is back")

        let end = app.buttons["endShiftButton"]
        XCTAssertTrue(reachShiftControl(end, in: app))
        end.tap()
        XCTAssertTrue(startShift.appears())
        XCTAssertTrue(
            scrollUntilHittable(rows(in: app).firstMatch, in: app),
            "The shift that was paused and parked still finishes as one shift in history"
        )
    }

    /// At the largest accessibility size a running shift with stacked
    /// deliveries stacks rather than squeezes: the figures, each card's name,
    /// state and step, cancelling, and Pause and End are all whole, reachable
    /// and full-size.
    ///
    /// Was two journeys, the empty panel and one card, each at AX5.
    @MainActor
    func testTheRunningShiftAtTheLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededActiveDeliveryArgument)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.accessibilityXXXLTextSize]
        launchInPortrait(app)

        let working = app.descendants(matching: .any)["workingTime"]
        XCTAssertTrue(working.appears())
        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app, maxSwipes: 10))
        let counts = app.descendants(matching: .any)["liveDeliveryCounts"]
        XCTAssertTrue(scrollTo(counts, in: app, maxSwipes: 10))
        XCTAssertGreaterThanOrEqual(counts.frame.minY, mileage.frame.maxY - 1, "The figures stack rather than share a row")
        attachScreenshot("home-active-xxxl")

        let card = deliveryCard("Delivery 2", in: app)
        XCTAssertTrue(scrollTo(card, in: app, maxSwipes: 25))
        XCTAssertTrue(card.label.contains("Next step"), "Showed: \(card.label)")
        let action = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "deliveryActionButton", "Delivery 2")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(action, in: app, maxSwipes: 25))
        XCTAssertGreaterThanOrEqual(onPixelGrid(action.frame.height), 44)
        attachScreenshot("home-delivery-xxxl")
        let cancel = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "cancelDeliveryButton", "Delivery 2")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(cancel, in: app, maxSwipes: 25))
        XCTAssertGreaterThanOrEqual(onPixelGrid(cancel.frame.height), 44)

        for identifier in ["pauseShiftButton", "endShiftButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(scrollUntilHittable(button, in: app, maxSwipes: 25), "\(identifier) is reachable")
            XCTAssertGreaterThanOrEqual(onPixelGrid(button.frame.height), 44)
        }
    }

    /// Two deliveries left in progress come back on launch as two cards, each
    /// with its own name, state, clock and next step, laid out step first; they
    /// survive leaving the app and coming back; and a recovered card is a
    /// control over the real record.
    ///
    /// Was four journeys over the same fixture.
    @MainActor
    func testRecoveredStackedDeliveriesStayDistinctAndSurviveLeavingTheApp() throws {
        let app = launchWithActiveDelivery()

        let accepted = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(accepted, in: app), "The recovered deliveries have their own controls")
        XCTAssertEqual(accepted.label, "Delivery 2. Mark arrived at pickup")
        XCTAssertEqual(carrying.label, "Delivery 3. Mark delivery completed")
        XCTAssertEqual(
            app.buttons.matching(identifier: "deliveryActionButton").count, 2,
            "Two active deliveries, neither collapsed into the other nor duplicated"
        )
        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(status.label.contains("2 deliveries in progress"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("1 delivery completed"), "The earlier delivery is still counted")

        let second = deliveryCard("Delivery 2", in: app)
        let third = deliveryCard("Delivery 3", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(second.label.contains("Next step, mark arrived at pickup"), "Showed: \(second.label)")
        XCTAssertTrue(second.label.contains("In this state for 25 minutes"), "Its own clock: \(second.label)")
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("Next step, mark delivery completed"), "Showed: \(third.label)")
        XCTAssertTrue(third.label.contains("In this state for 4 minutes"), "And this one its own: \(third.label)")
        attachScreenshot("home-two-stacked-deliveries")

        // The card leads with its state, then the step, then cancelling.
        let cancel = deliveryButton("cancelDeliveryButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(scrollUntilHittable(cancel, in: app))
        XCTAssertLessThan(second.frame.minY, accepted.frame.minY)
        XCTAssertLessThan(accepted.frame.minY, cancel.frame.minY, "Cancelling sits below the step, not beside it")
        XCTAssertGreaterThan(accepted.frame.height, cancel.frame.height - 1, "The step is the dominant control")
        XCTAssertGreaterThanOrEqual(onPixelGrid(cancel.frame.height), 44, "A quiet control is still a full-size target")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(
            app.descendants(matching: .any)["activeShiftStatus"].appears(),
            "The shift is still running; returning to the app ends nothing"
        )
        XCTAssertTrue(scrollTo(accepted, in: app), "Both deliveries are still on screen")
        XCTAssertEqual(accepted.label, "Delivery 2. Mark arrived at pickup")
        XCTAssertEqual(carrying.label, "Delivery 3. Mark delivery completed")
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 2, "Neither duplicated nor dropped")
        XCTAssertTrue(scrollTo(app.descendants(matching: .any)["routeCaptureStatus"], in: app))

        XCTAssertTrue(scrollUpUntilHittable(carrying, in: app, maxSwipes: 6))
        tapWithinReach(carrying, in: app)
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "The delivered one leaves the list"
        )
        XCTAssertEqual(accepted.label, "Delivery 2. Mark arrived at pickup", "And the other keeps its step")
        XCTAssertTrue(waitForLabel(status, toContain: "2 deliveries completed"), "Status: \(status.label)")
    }

    /// One simulated drive through the live figures: recorded mileage grows
    /// while positions are accepted and says it is recorded; the running shift
    /// shows no earnings or rate and says why; pausing freezes both mileage and
    /// working time; resuming does not add the distance covered during the
    /// break and says the route is now partial; and once a distance exists the
    /// vehicle correction is gone while the vehicle row stays readable.
    ///
    /// Was five journeys, three of which each waited fifteen to twenty seconds
    /// for the synthetic vehicle to move.
    @MainActor
    func testARecordedRouteGrowsFreezesWhilePausedAndLeavesTheBreakOut() throws {
        let app = launchWithSimulatedRoute()

        openSettings(in: app)
        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        goBack(in: app)
        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.appears())
        startShift.tap()

        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(mileage.appears())
        let first = try XCTUnwrap(waitForRecordedMiles(in: app), "No measured distance while recording")
        XCTAssertGreaterThan(first, 0)
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

        // No money on a running shift, and the reason with the shift's context.
        let counts = app.descendants(matching: .any)["liveDeliveryCounts"]
        let figures = [counts, mileage].map { $0.label + (($0.value as? String) ?? "") }
        let notice = app.descendants(matching: .any)["liveRateNotice"]
        XCTAssertTrue(reachShiftControl(notice, in: app), "The rate notice is with the shift's context")
        XCTAssertTrue(notice.label.contains("still running"), "Showed: \(notice.label)")
        XCTAssertFalse(app.descendants(matching: .any)["liveRecordedGross"].exists)
        for text in figures + [notice.label] {
            XCTAssertFalse(text.contains("$"), "A running shift states no amount: \(text)")
            XCTAssertFalse(text.contains("/hr"), "A running shift derives no rate: \(text)")
        }

        // Driving has been recorded, so the vehicle can no longer be corrected.
        let vehicle = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "2020 Honda Civic, 34 miles per gallon")
        XCTAssertFalse(
            app.buttons["changeShiftVehicleButton"].exists,
            "A dead action is worse than no action, so the control is absent rather than disabled"
        )

        // Pausing freezes both figures; the vehicle keeps driving meanwhile.
        let pause = app.buttons["pauseShiftButton"]
        XCTAssertTrue(reachShiftControl(pause, in: app))
        pause.tap()
        let resume = app.buttons["resumeShiftButton"]
        XCTAssertTrue(resume.appears())
        let workingTime = app.descendants(matching: .any)["workingTime"]
        XCTAssertTrue(scrollToTop(reaching: workingTime, in: app))
        let settling = expectation(description: "the pause settles")
        settling.isInverted = true
        wait(for: [settling], timeout: 3)
        let pausedMiles = try XCTUnwrap(recordedMiles(in: app))
        let pausedWorking = try XCTUnwrap(workingTime.value as? String)

        let paused = expectation(description: "the driver takes a break")
        paused.isInverted = true
        wait(for: [paused], timeout: 20)
        XCTAssertEqual(recordedMiles(in: app), pausedMiles, "Recorded mileage must not move while paused")
        XCTAssertEqual(workingTime.value as? String, pausedWorking, "Working time must not move while paused")
        XCTAssertTrue(resume.exists, "And the shift did not resume by itself")

        resume.tap()
        XCTAssertTrue(app.buttons["pauseShiftButton"].appears())
        let resumeDeadline = Date().addingTimeInterval(30)
        var afterResume: Double?
        while Date() < resumeDeadline, afterResume == nil {
            if let miles = recordedMiles(in: app), miles > pausedMiles { afterResume = miles }
            _ = mileage.waitForExistence(timeout: 0.3)
        }
        let resumedMiles = try XCTUnwrap(afterResume, "Recording did not restart after the shift was resumed")
        XCTAssertLessThan(
            resumedMiles - pausedMiles, 0.25,
            "Resuming added \(resumedMiles - pausedMiles) mi at once; the break must not be measured"
        )
        let resumedSpoken = try XCTUnwrap(mileage.value as? String)
        XCTAssertTrue(
            resumedSpoken.lowercased().contains("partial route"),
            "A route with a break in it says so while the shift is still running: \(resumedSpoken)"
        )
    }

    // MARK: Active delivery cards

    /// The card of one delivery in progress, found by the name it leads with.
    @MainActor
    private func deliveryCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "activeDeliveryStatus", title)
        ).firstMatch
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

    /// Opens Older Weeks from the root screen.
    @MainActor
    private func openOlderWeeks(in app: XCUIApplication, maxSwipes: Int = 12) {
        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app, maxSwipes: maxSwipes), "View Older Weeks is reachable")
        older.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
                .appears()
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

    /// History lists the week the driver is in, opens with that week's own
    /// figures, says how much is behind View Older Weeks, exports every shift
    /// rather than the week on screen, and follows an edit made to the week's
    /// shift when the driver comes back.
    ///
    /// Was five journeys over this fixture (and one over the seeded history for
    /// the export). The week's scope and partition are `HistoryFetchScopeTests`.
    @MainActor
    func testHistoryShowsThisWeekWithItsOwnFiguresAndFollowsAnEdit() throws {
        let app = launchWithOlderWeeks()

        let history = rows(in: app)
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app), "This week's shift is listed")
        XCTAssertTrue(waitForCount(history, toEqual: 1), "Only the current week's shift is listed")
        XCTAssertTrue(waitForLabel(history.firstMatch, toContain: "$70.00"), "Showed: \(history.firstMatch.label)")
        let header = app.descendants(matching: .any)["historyHeader"]
        XCTAssertTrue(header.appears())
        XCTAssertTrue(header.label.contains("This Week"), "Showed: \(header.label)")

        let older = app.buttons["olderHistoryWeeksLink"]
        XCTAssertTrue(scrollUntilHittable(older, in: app), "The older-weeks control is reachable")
        XCTAssertEqual(elements(containing: "$55.00", in: app).count, 0, "Last week's shift is not in this list")
        XCTAssertEqual(elements(containing: "$41.00", in: app).count, 0)
        XCTAssertEqual(elements(containing: "$33.00", in: app).count, 0)
        XCTAssertTrue(waitForLabel(older, toContain: "2 weeks · 3 shifts"), "Showed: \(older.label)")

        let summary = currentWeekSummary(in: app)
        XCTAssertTrue(scrollToTop(reaching: summary, in: app, swipes: 12), "The week says how it is going")
        XCTAssertTrue(waitForLabel(summary, toContain: "Recorded gross earnings, $70.00"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("1 completed shift"), "Showed: \(summary.label)")
        XCTAssertFalse(summary.label.contains("$55.00"), "Last week is not in this week's figures")
        XCTAssertTrue(summary.label.contains("No recorded mileage"), "Showed: \(summary.label)")
        XCTAssertFalse(summary.label.contains("0.0 mi"), "Missing is never a zero")
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app))
        XCTAssertLessThan(summary.frame.minY, history.firstMatch.frame.minY, "The figures come before the shifts")

        // Export All History means the store, not the week on screen.
        XCTAssertTrue(scrollToTop(reaching: app.buttons["exportAllHistoryButton"], in: app))
        openExport("exportAllHistoryButton", in: app)
        let name = exportFileName(in: app)
        XCTAssertTrue(name.contains("DashPilot-History-"), "\(name)")
        XCTAssertTrue(name.contains("4 shifts"), "This week's shift and the three before it: \(name)")
        app.buttons["dismissExportButton"].tap()

        // An edit to this week's shift is followed on return, not on relaunch.
        openFirstShift(in: app)
        let edit = app.buttons["editShiftEarningsButton"]
        XCTAssertTrue(scrollTo(edit, in: app))
        edit.tap()
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.appears())
        clear(field, in: app)
        type("90", into: app)
        app.buttons["saveEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailEarnings"], toContain: "$90.00"))
        goBack(in: app)
        XCTAssertTrue(scrollToTop(reaching: summary, in: app, swipes: 12))
        XCTAssertTrue(waitForLabel(summary, toContain: "Recorded gross earnings, $90.00"), "Showed: \(summary.label)")
        XCTAssertFalse(summary.label.contains("$70.00"), "The previous figure is gone: \(summary.label)")
    }

    /// Older Weeks groups every other shift by its week, newest first, with no
    /// group for a week nobody worked; each week opens with one spoken summary
    /// (its shifts, earnings, working time, coverage, and no mileage or fuel
    /// figure it does not have) above its shifts; a week of two shifts states
    /// its total rather than its parts; and a shift opens its own detail.
    ///
    /// Was six journeys, each launching this fixture and opening Older Weeks.
    /// The totals are `HistoryWeekSummaryTests`'.
    @MainActor
    func testOlderWeeksAreGroupedSummarisedAndOpen() throws {
        let app = launchWithOlderWeeks()
        openOlderWeeks(in: app)

        let summaries = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
        XCTAssertTrue(waitForCount(summaries, toEqual: 2), "One summary per week that holds shifts")
        let lastWeek = summaries.element(boundBy: 0)
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "1 completed shift"), "Showed: \(lastWeek.label)")
        for expected in ["$55.00", "Recorded gross earnings", "working time", "across 1 of 1 completed shift", "No recorded mileage"] {
            XCTAssertTrue(lastWeek.label.contains(expected), "The week says \(expected): \(lastWeek.label)")
        }
        XCTAssertFalse(lastWeek.label.contains("0.0 mi"), "Missing is never a zero")
        XCTAssertFalse(lastWeek.label.contains("Estimated fuel"), "No fuel figure for a week with none")
        XCTAssertFalse(lastWeek.label.contains("$0.00"))

        let rows = olderWeekRows(in: app)
        XCTAssertTrue(rows.firstMatch.appears())
        XCTAssertTrue(waitForLabel(rows.element(boundBy: 0), toContain: "$55.00"), "The newest older week is first")
        XCTAssertLessThan(lastWeek.frame.minY, rows.firstMatch.frame.minY, "The week's figures come before its shifts")

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

        let threeWeeksAgo = summaries.matching(NSPredicate(format: "label CONTAINS %@", "$74.00")).firstMatch
        XCTAssertTrue(threeWeeksAgo.appears(), "Two shifts are added up rather than listed")
        XCTAssertTrue(threeWeeksAgo.label.contains("2 completed shifts"), "Showed: \(threeWeeksAgo.label)")
        XCTAssertFalse(threeWeeksAgo.label.contains("$41.00"), "The week states its total, not its parts")
        XCTAssertEqual(elements(containing: "$70.00", in: app).count, 0, "This week is not on this screen")

        let row = rows.matching(NSPredicate(format: "label CONTAINS %@", "$41.00")).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        row.tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.appears(), "The same detail screen opens")
        XCTAssertTrue(earnings.label.contains("$41.00"), "With the tapped shift's own amount: \(earnings.label)")
    }

    // MARK: The current week's own figures

    @MainActor
    private func currentWeekSummary(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "currentWeekSummary").firstMatch
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
        XCTAssertTrue(earnings.appears())
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
        XCTAssertTrue(earnings.appears())
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

    /// Deleting a completed shift is confirmed, says its route goes with it,
    /// and backing out deletes nothing.
    ///
    /// Was two journeys over this fixture.
    @MainActor
    func testDeletingACompletedShiftIsConfirmed() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(delete, in: app), "Deletion lives at the bottom of the detail screen")
        delete.tap()
        let cancel = app.buttons.matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.appears())
        cancel.tap()
        XCTAssertTrue(app.buttons["deleteShiftButton"].appears(), "Backing out deletes nothing")

        app.buttons["deleteShiftButton"].tap()
        let confirm = app.buttons.matching(identifier: "confirmDeleteShiftButton").firstMatch
        XCTAssertTrue(confirm.appears())
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "route positions")).count > 0,
            "The confirmation says the shift's route is deleted with it"
        )
        tapClosingDialog(confirm)
        XCTAssertTrue(app.navigationBars["DashPilot"].appears(), "Detail returns to history")
        let remaining = rows(in: app)
        XCTAssertTrue(waitForCount(remaining, toEqual: 1), "The deleted shift is gone from history")
        XCTAssertFalse(remaining.firstMatch.label.contains("$86.25"), "And the one that remains is the other")
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
        XCTAssertTrue(addButton.appears())
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
        XCTAssertTrue(field.appears())
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
        XCTAssertTrue(startShift.appears())
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
            tapWithinReach(action, in: app)
        }

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery completed"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("No delivery in progress"))
        XCTAssertFalse(app.buttons["cancelDeliveryButton"].exists)
        XCTAssertFalse(app.buttons["deliveryActionButton"].exists, "A finished delivery has no next step")

        // And the shift can now be ended, with the delivery recorded against it.
        XCTAssertTrue(reachShiftControl(app.buttons["endShiftButton"], in: app))
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
        XCTAssertTrue(startShift.appears())
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
        XCTAssertTrue(second.appears(), "A second card appears for the second delivery")
        XCTAssertEqual(
            first.label,
            "Delivery 1. Mark arrived at pickup",
            "Starting another delivery does not move the first one along"
        )
        XCTAssertEqual(second.label, "Delivery 2. Mark arrived at pickup")

        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "2 deliveries in progress"), "Status: \(status.label)")

        // Advancing one leaves the other exactly where it was.
        tapWithinReach(second, in: app)
        XCTAssertTrue(waitForLabel(second, toContain: "Delivery 2. Mark order picked up"))
        XCTAssertEqual(first.label, "Delivery 1. Mark arrived at pickup", "Delivery 1 is untouched")
    }

    // MARK: Pick up orders with Park & Resume

    /// Sets one of the two pickup workflow switches on the Settings screen,
    /// which must already be open.
    ///
    /// Waits on the switch's own value rather than on the tap, so a tap that
    /// landed on the row's title and did nothing fails here and not in the
    /// parking assertions after it.
    @MainActor
    private func setSwitch(_ identifier: String, to isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(scrollTo(toggle, in: app), "\(identifier) is on the Settings screen")
        XCTAssertTrue(scrollUntilHittable(toggle, in: app))
        let wanted = isOn ? "1" : "0"
        if (toggle.value as? String) != wanted {
            // The switch itself, at the row's trailing edge: a tap on the title
            // of a SwiftUI toggle row does not always reach the switch.
            toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        }
        XCTAssertTrue(
            waitUntil { (toggle.value as? String) == wanted },
            "\(identifier) reads \(wanted): \(String(describing: toggle.value))"
        )
    }

    /// Opens Settings, sets the workflow and, when asked, stacked orders, and
    /// comes back.
    @MainActor
    private func setPickupWorkflow(_ isOn: Bool, stackedOrders: Bool? = nil, in app: XCUIApplication) {
        openSettings(in: app)
        setSwitch("pickupWorkflowToggle", to: isOn, in: app)
        if let stackedOrders {
            setSwitch("stackedOrdersInOrderToggle", to: stackedOrders, in: app)
        }
        goBack(in: app)
    }

    /// Brings one of the shift's own controls to where a tap lands, from
    /// wherever the journey left the screen.
    ///
    /// Park and Resume Driving sit above the delivery cards and Pause and End
    /// below them, so a journey can be on either side. It goes to the top unconditionally first, for
    /// the reason ``scrollToTop(reaching:in:swipes:)`` gives: a `List` reports a
    /// control it has scrolled past as hittable, and a tap on that stale frame
    /// lands on whatever is there now. Then it searches downward.
    @MainActor
    private func reachShiftControl(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
        // The top is found by the working clock, which every running or paused
        // shift draws first: Pause and End sit below the delivery cards, so at
        // the top they may not be rendered yet.
        scrollToTop(reaching: app.descendants(matching: .any)["workingTime"], in: app)
            && scrollUntilHittable(control, in: app)
    }

    /// Presses Park on the running shift's panel.
    @MainActor
    private func pressPark(in app: XCUIApplication) {
        let park = app.buttons["parkShiftButton"]
        XCTAssertTrue(reachShiftControl(park, in: app), "Parking is offered on a running shift")
        park.tap()
        XCTAssertTrue(
            app.buttons["resumeDrivingButton"].appears(),
            "The vehicle is parked whatever the pickup workflow decides"
        )
    }

    /// Presses Resume Driving on the running shift's panel.
    @MainActor
    private func pressResumeDriving(in app: XCUIApplication) {
        let resume = app.buttons["resumeDrivingButton"]
        XCTAssertTrue(reachShiftControl(resume, in: app))
        resume.tap()
        XCTAssertTrue(
            app.buttons["parkShiftButton"].appears(),
            "The vehicle is driving whatever the pickup workflow decides"
        )
    }

    /// The workflow's line on the running shift, once it says `text`.
    @MainActor
    @discardableResult
    private func assertPickupWorkflowNotice(contains text: String, in app: XCUIApplication) -> XCUIElement {
        let notice = app.descendants(matching: .any)["pickupWorkflowNotice"]
        XCTAssertTrue(scrollUpUntilHittable(notice, in: app, maxSwipes: 6), "The line sits under the shift's status")
        XCTAssertTrue(waitForLabel(notice, toContain: text), "Showed: \(notice.label)")
        return notice
    }

    /// A delivery card, once its spoken status says `state`.
    @MainActor
    private func assertCard(_ name: String, says state: String, in app: XCUIApplication) {
        let card = deliveryStatusCard(named: name, in: app)
        XCTAssertTrue(scrollTo(card, in: app), "\(name) is on the panel")
        XCTAssertTrue(waitForLabel(card, toContain: state), "\(name): \(card.label)")
    }

    /// The workflow the driver asked for after a real shift: Park records
    /// Arrived at Pickup and Resume Driving records Picked Up, each saying which
    /// delivery and that their setting did it; Undo after Park takes the arrival
    /// back and leaves the vehicle parked, and Undo after Resume takes the
    /// pickup back and leaves it driving.
    ///
    /// Was three journeys, each starting a shift and a delivery. Selection,
    /// stacked orders and refusals are `ParkResumePickupWorkflowTests`.
    @MainActor
    func testParkAndResumeRecordThePickupAndUndoTakesEachBack() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)
        assertCard("Delivery 1", says: "heading to the pickup", in: app)
        setPickupWorkflow(true, in: app)

        pressPark(in: app)
        let parked = assertPickupWorkflowNotice(contains: "Delivery 1 marked Arrived at Pickup", in: app)
        XCTAssertTrue(parked.label.contains("Recorded automatically when you parked"), parked.label)
        XCTAssertTrue(parked.label.contains("Pick up orders with Park & Resume"), "Their setting, not a detection")
        XCTAssertFalse(app.alerts.firstMatch.exists, "No alert stands between the driver and the door")
        assertCard("Delivery 1", says: "waiting at the pickup", in: app)

        let undo = app.buttons["undoPickupWorkflowStepButton"]
        XCTAssertTrue(scrollUpUntilHittable(undo, in: app, maxSwipes: 6), "Undo is offered beside what was recorded")
        XCTAssertTrue(undo.label.contains("Undo Arrived at Pickup for Delivery 1"), undo.label)
        XCTAssertTrue(undo.label.contains("The vehicle is still parked"), undo.label)
        XCTAssertGreaterThanOrEqual(onPixelGrid(undo.frame.height), 44)
        undo.tap()
        assertPickupWorkflowNotice(contains: "Undid Arrived at Pickup for Delivery 1", in: app)
        XCTAssertTrue(waitForDisappearance(of: undo), "The offer goes once used")
        XCTAssertTrue(app.descendants(matching: .any)["parkedShiftNotice"].exists, "The vehicle is still parked")
        assertCard("Delivery 1", says: "heading to the pickup", in: app)

        // Driving and parking again: Park records the arrival afresh, and
        // Resume Driving records the pickup.
        pressResumeDriving(in: app)
        pressPark(in: app)
        assertPickupWorkflowNotice(contains: "Delivery 1 marked Arrived at Pickup", in: app)
        pressResumeDriving(in: app)
        let resumed = assertPickupWorkflowNotice(contains: "Delivery 1 marked Picked Up", in: app)
        XCTAssertTrue(resumed.label.contains("Recorded automatically when you resumed driving"), resumed.label)
        XCTAssertFalse(app.descendants(matching: .any)["parkedShiftNotice"].exists, "The vehicle is driving")
        assertCard("Delivery 1", says: "heading to the customer", in: app)

        let undoPickup = app.buttons["undoPickupWorkflowStepButton"]
        XCTAssertTrue(scrollUpUntilHittable(undoPickup, in: app, maxSwipes: 6))
        XCTAssertTrue(undoPickup.label.contains("Undo Picked Up for Delivery 1"), undoPickup.label)
        XCTAssertTrue(undoPickup.label.contains("still recorded as driving"), undoPickup.label)
        undoPickup.tap()
        assertPickupWorkflowNotice(contains: "Undid Picked Up for Delivery 1", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["parkedShiftNotice"].exists, "Still driving")
        XCTAssertTrue(app.buttons["parkShiftButton"].exists)
        assertCard("Delivery 1", says: "waiting at the pickup", in: app)
    }

    /// Reminders about a step that may have gone unrecorded: one per stale
    /// delivery, never for one already in the car, each naming its delivery and
    /// its step, stating what the record holds and claiming no observation;
    /// dismissing one records nothing, and confirming one advances only that
    /// delivery through its ordinary step.
    ///
    /// Was five journeys over this fixture. Which deliveries are stale is
    /// `DeliveryProgressAssistanceTests`.
    @MainActor
    func testRemindersStateTheirEvidenceAndAnswerOnlyTheirOwnDelivery() throws {
        let app = launchWithMissedLifecycle()

        let reminders = app.descendants(matching: .any).matching(identifier: "deliverySuggestion")
        XCTAssertTrue(reminders.firstMatch.appears())
        XCTAssertTrue(waitForCount(reminders, toEqual: 2), "The delivery already picked up gets none")
        let waiting = deliveryButton("deliverySuggestionActionButton", containing: "Delivery 1", in: app)
        let heading = deliveryButton("deliverySuggestionActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(waiting.label.hasPrefix("Delivery 1.") && waiting.label.contains("Mark order picked up"), waiting.label)
        XCTAssertTrue(heading.label.hasPrefix("Delivery 2.") && heading.label.contains("Mark arrived at pickup"), heading.label)
        XCTAssertFalse(deliveryButton("deliverySuggestionActionButton", containing: "Delivery 3", in: app).exists)
        XCTAssertGreaterThanOrEqual(onPixelGrid(waiting.frame.height), 44)

        let first = reminders.matching(NSPredicate(format: "label CONTAINS %@", "Delivery 1")).firstMatch
        let spoken = first.label
        XCTAssertTrue(spoken.contains("reached the pickup") && spoken.contains("records no pickup"), spoken)
        XCTAssertTrue(spoken.contains("Already picked this order up?"), spoken)
        XCTAssertTrue(spoken.contains("DashPilot cannot tell where you are"), spoken)
        XCTAssertTrue(spoken.contains("not something it observed"), spoken)
        for claim in ["you arrived", "you picked up", "detected", "confirmed"] {
            XCTAssertFalse(spoken.lowercased().contains(claim), "A reminder must not claim \"\(claim)\"")
        }
        attachScreenshot("home-reminder")

        let stepOne = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        let stepTwo = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertEqual(stepOne.label, "Delivery 1. Mark order picked up")
        XCTAssertEqual(stepTwo.label, "Delivery 2. Mark arrived at pickup")
        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "3 deliveries in progress"), status.label)

        let dismiss = deliveryButton("deliverySuggestionDismissButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(dismiss.label.contains("Nothing is recorded"), dismiss.label)
        tapWithinReach(dismiss, in: app)
        XCTAssertTrue(waitForCount(reminders, toEqual: 1), "Only the dismissed reminder goes")
        XCTAssertEqual(stepOne.label, "Delivery 1. Mark order picked up", "Dismissing recorded nothing")

        XCTAssertTrue(heading.appears())
        tapWithinReach(heading, in: app)
        XCTAssertTrue(waitForLabel(stepTwo, toContain: "Delivery 2. Mark order picked up"), stepTwo.label)
        XCTAssertEqual(stepOne.label, "Delivery 1. Mark order picked up", "Delivery 1 is untouched")
        XCTAssertTrue(waitForCount(reminders, toEqual: 0), "The answered reminder leaves too")
        XCTAssertTrue(waitForLabel(status, toContain: "3 deliveries in progress"), status.label)
    }

    /// The several-delivery sheet: cancelling it records nothing; it opens on
    /// two and says so, keeps Start pinned under its form with the count and
    /// both switches above it, says what it will record, and records one offer
    /// however fast Start is pressed twice; the one-tap path still adds a single
    /// delivery in an offer of its own.
    ///
    /// Was three journeys, each starting an empty shift.
    @MainActor
    func testTheOfferSheetRecordsOneOfferOrNothing() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()
        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(startDelivery.appears())
        let actions = app.buttons.matching(identifier: "deliveryActionButton")

        let offerControl = app.buttons["startOfferButton"]
        XCTAssertTrue(scrollTo(offerControl, in: app), "The control for a several-delivery offer is on the panel")
        offerControl.tap()
        let cancel = app.buttons["cancelStartOfferButton"]
        XCTAssertTrue(cancel.appears())
        cancel.tap()
        XCTAssertTrue(startDelivery.appears())
        XCTAssertEqual(actions.count, 0, "A dismissed sheet records nothing")

        offerControl.tap()
        let confirm = app.buttons["confirmStartOfferButton"]
        let stepper = app.steppers["offerDeliveryCountStepper"]
        let pickup = app.switches["offerSamePickupToggle"]
        let dropOff = app.switches["offerSameDropOffToggle"]
        XCTAssertTrue(confirm.appears())
        XCTAssertEqual(confirm.label, "Start an offer of 2 deliveries", "It opens on two, and says so")
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(waitForLabel(confirm, toContain: "Start an offer of 3 deliveries"), "The action follows the count")
        XCTAssertLessThan(stepper.frame.minY, pickup.frame.minY)
        XCTAssertLessThan(pickup.frame.minY, dropOff.frame.minY)
        XCTAssertLessThan(dropOff.frame.maxY, confirm.frame.minY, "No switch is under the action")
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable, "Start is reachable with the form scrolled to its end")
        setSwitch("offerSamePickupToggle", to: true, in: app)
        setSwitch("offerSameDropOffToggle", to: true, in: app)
        XCTAssertTrue(waitForLabel(confirm, toContain: "same pickup and same drop-off"), "Showed: \(confirm.label)")
        attachScreenshot("offer-sheet-three-shared")
        confirm.doubleTap()
        XCTAssertTrue(waitForDisappearance(of: confirm))
        XCTAssertTrue(waitForCount(actions, toEqual: 3), "Three deliveries, from one offer")
        let headers = app.descendants(matching: .any).matching(identifier: "offerGroupHeader")
        XCTAssertEqual(headers.count, 1, "One offer, not two")
        XCTAssertTrue(headers.firstMatch.label.contains("3 deliveries accepted together"), headers.firstMatch.label)
        XCTAssertTrue(headers.firstMatch.label.contains("same pickup and drop-off"), headers.firstMatch.label)

        XCTAssertTrue(scrollToTop(reaching: startDelivery, in: app))
        startDelivery.tap()
        XCTAssertTrue(waitForCount(actions, toEqual: 4), "One more delivery, not two")
        XCTAssertEqual(headers.count, 1, "The delivery started alone joined no group")
    }

    /// Correcting grouping on a running shift: leaving the sheet changes
    /// nothing; two offers recorded separately are combined into the one they
    /// were, named and confirmed; one delivery is split into an offer of its
    /// own; and an offer grouped by mistake is separated into one per
    /// delivery; every card keeps its step throughout.
    ///
    /// Was four journeys over this fixture. Every correction's rules are
    /// `OfferCorrectionServiceTests` and `OfferCorrectionInvarianceTests`.
    @MainActor
    func testCorrectingGroupingOnARunningShift() throws {
        let app = launchWithStackedOffer()
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].appears())
        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "Correction is one control, not a button on every card")
        let heading = app.descendants(matching: .any)["offerGroupHeader"]

        correct.tap()
        XCTAssertTrue(app.buttons["offerCorrectionSeparateButton"].appears())
        app.buttons["closeOfferCorrectionButton"].tap()
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(heading.label.contains("2 deliveries accepted together"), "Leaving changed nothing")

        XCTAssertTrue(scrollTo(correct, in: app))
        correct.tap()
        let combine = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "offerCorrectionMergeButton", "Combine Offer 2"))
            .firstMatch
        XCTAssertTrue(scrollTo(combine, in: app), "Offer 2 can be combined into the offer accepted before it")
        combine.tap()
        let destination = app.buttons["offerCorrectionDestinationButton"]
        XCTAssertTrue(destination.appears())
        XCTAssertEqual(destination.label, "Combine Offer 2 into Offer 1", "The direction is in the control")
        destination.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.appears())
        let confirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertEqual(confirm.label, "Combine into Offer 1")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Delivery 3 moves to Offer 1")).count > 0,
            "The confirmation names what moves"
        )
        tapClosingDialog(confirm)
        let offerHeaders = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "offerCorrectionOfferHeader"))
        XCTAssertTrue(waitForCount(offerHeaders, toEqual: 1), "The offer left holding nothing is gone")
        XCTAssertTrue(offerHeaders.firstMatch.label.contains("3 deliveries accepted together"))

        // One delivery split out into an offer of its own.
        let delivery = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "offerCorrectionDeliveryButton", "Delivery 2"))
            .firstMatch
        XCTAssertTrue(scrollTo(delivery, in: app))
        XCTAssertEqual(delivery.label, "Move Delivery 2 out of Offer 1")
        delivery.tap()
        let split = app.buttons["offerCorrectionSplitButton"]
        XCTAssertTrue(split.appears(), "Splitting is offered apart from moving, not mixed into it")
        XCTAssertEqual(split.label, "Put Delivery 2 in a new offer of its own")
        split.tap()
        XCTAssertTrue(alert.appears())
        tapClosingDialog(alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch)
        XCTAssertTrue(waitForCount(offerHeaders, toEqual: 2))
        // Which of the two is Offer 1 is not this journey's to assume. The new
        // offer takes Delivery 2's acceptance, which is the instant Delivery 1
        // was accepted in too, so the two offers tie on acceptance time and
        // `Offer.acceptedBefore` settles the tie by identity. The journey reads
        // the number Delivery 2 was given and asserts who is with whom.
        let splitOut = try XCTUnwrap(offerNumber(of: "Delivery 2", in: app), "Delivery 2 is in an offer")
        let pair = splitOut == 1 ? 2 : 1
        XCTAssertEqual(offerNumber(of: "Delivery 1", in: app), pair, "Delivery 1 stayed where it was")
        XCTAssertEqual(offerNumber(of: "Delivery 3", in: app), pair, "Delivery 3 stayed with Delivery 1")
        let headerLabels = offerHeaders.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(headerLabels.contains { $0.hasPrefix("Offer \(splitOut). 1 delivery") }, "\(headerLabels)")
        XCTAssertTrue(
            headerLabels.contains { $0.hasPrefix("Offer \(pair). 2 deliveries accepted together") },
            "\(headerLabels)"
        )

        let separate = app.buttons["offerCorrectionSeparateButton"]
        XCTAssertTrue(separate.appears())
        XCTAssertEqual(separate.label, "Separate Offer \(pair) into one offer per delivery")
        separate.tap()
        XCTAssertTrue(alert.appears())
        let separateConfirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertEqual(separateConfirm.label, "Separate Offer \(pair)")
        tapClosingDialog(separateConfirm)
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "offerCorrectionSeparateButton"), toEqual: 0))
        app.buttons["closeOfferCorrectionButton"].tap()

        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count, 0,
            "Three offers of one"
        )
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3, "Nothing was deleted")
        XCTAssertEqual(
            deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app).label,
            "Delivery 1. Mark order picked up",
            "Regrouping moved no lifecycle step"
        )
        XCTAssertEqual(deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app).label, "Delivery 2. Mark arrived at pickup")
    }

    /// A shift cannot end while any delivery is in progress, and says how many;
    /// a cancellation is named, confirmed, kept as history and spares the other
    /// delivery; one left still blocks the end, in wording that follows the
    /// count; once nothing is running the shift ends with both outcomes in its
    /// record.
    ///
    /// Was three journeys over this fixture.
    @MainActor
    func testActiveDeliveriesBlockEndingUntilEachIsResolved() throws {
        let app = launchWithActiveDelivery()

        let endShift = app.buttons["endShiftButton"]
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].appears())
        XCTAssertTrue(reachShiftControl(endShift, in: app), "End is below the delivery cards")
        endShift.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 deliveries are still in progress"))
                .firstMatch.appears(),
            "Ending is refused with a reason that counts them"
        )
        tapClosingDialog(app.buttons["OK"])
        XCTAssertTrue(app.buttons["endShiftButton"].appears(), "The shift is still running")
        XCTAssertTrue(rows(in: app).count == 0, "No completed shift appeared in history")

        // Cancelling one is named, confirmed, and spares the other.
        let cancel = deliveryButton("cancelDeliveryButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["activeShiftStatus"], in: app))
        XCTAssertTrue(scrollTo(cancel, in: app))
        XCTAssertEqual(cancel.label, "Delivery 2. Cancel this delivery", "The control says which delivery it ends")
        tapWithinReach(cancel, in: app)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cancel Delivery 2?"))
                .firstMatch.appears(),
            "The confirmation names the delivery"
        )
        let confirm = app.buttons.matching(identifier: "confirmCancelDeliveryButton").firstMatch
        XCTAssertTrue(confirm.appears())
        tapClosingDialog(confirm)
        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(waitForLabel(status, toContain: "1 delivery cancelled"), "Status: \(status.label)")
        XCTAssertTrue(status.label.contains("1 delivery completed"), "The cancelled one is not counted as completed")
        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(carrying.exists, "The other delivery is untouched by the cancellation")
        XCTAssertEqual(carrying.label, "Delivery 3. Mark delivery completed")

        // One left still blocks the end, and the wording follows the count.
        XCTAssertTrue(reachShiftControl(app.buttons["endShiftButton"], in: app))
        app.buttons["endShiftButton"].tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A delivery is still in progress"))
                .firstMatch.appears(),
            "One remaining delivery still blocks the end, and the wording follows the count"
        )
        tapClosingDialog(app.buttons["OK"])

        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["activeShiftStatus"], in: app))
        XCTAssertTrue(scrollTo(carrying, in: app))
        tapWithinReach(carrying, in: app)
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 0))
        XCTAssertTrue(reachShiftControl(app.buttons["endShiftButton"], in: app))
        app.buttons["endShiftButton"].tap()
        openFirstShift(in: app)
        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled")
    }

    /// Correcting a historical completion to the cancellation it was: the
    /// control names its subject, dismissing the confirmation writes nothing,
    /// confirming keeps the recorded instant as the cancellation time and
    /// keeps the place and amount, the counts move by one each way, and a
    /// delivery already cancelled is offered no such correction.
    ///
    /// Was three journeys over this fixture; the refusal on a running shift is
    /// `HistoricalDeliveryCancellationServiceTests`.
    @MainActor
    func testCorrectingAHistoricalCompletionToACancellation() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summary = app.staticTexts["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled")
        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app))
        let recordedTime = try XCTUnwrap(
            Self.time(after: "Delivered at", in: deliveryRow(containing: "Delivery 1, delivered", in: app).label)
        )
        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        XCTAssertEqual(
            correct.label,
            "Correct Delivery 1 to cancelled. It stays a finished delivery, recorded as cancelled instead of delivered."
        )

        correct.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.appears(), "Confirmed before anything is written")
        dismiss(alert, tapping: "Cancel")
        XCTAssertTrue(deliveryRow(containing: "Delivery 1, delivered", in: app).appears())
        XCTAssertFalse(deliveryRow(containing: "Delivery 1, cancelled", in: app).exists, "Dismissing wrote nothing")

        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()
        XCTAssertTrue(alert.appears())
        let confirm = alert.buttons.matching(identifier: "confirmCorrectToCancelledButton").firstMatch
        XCTAssertEqual(confirm.label, "Correct Delivery 1")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Delivery 1 stays a finished delivery")).count > 0
        )
        XCTAssertTrue(
            alert.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "the time you recorded it as delivered becomes the time it was cancelled")
            ).count > 0
        )
        tapClosingDialog(confirm)

        let corrected = deliveryRow(containing: "Delivery 1, cancelled", in: app)
        XCTAssertTrue(corrected.appears())
        XCTAssertEqual(Self.time(after: "Cancelled at", in: corrected.label), recordedTime, "The same instant")
        XCTAssertNil(Self.time(after: "Delivered at", in: corrected.label), "The completion is gone")
        XCTAssertFalse(corrected.label.contains("Accepted to delivered"))
        XCTAssertTrue(corrected.label.contains("Picked up from \(Self.noodles)"), "The place stays")
        XCTAssertTrue(corrected.label.contains("Gross earnings for Delivery 1"), "And the amount")
        XCTAssertTrue(scrollUpUntilHittable(summary, in: app))
        XCTAssertEqual(summary.label, "1 delivery completed. 2 deliveries cancelled")

        let correctedCard = deliveryCard(containing: "Delivery 1, cancelled", in: app)
        XCTAssertTrue(scrollTo(correctedCard, in: app))
        XCTAssertFalse(correctedCard.buttons["shiftDetailCorrectToCancelledButton"].exists, "Not offered twice")
        XCTAssertTrue(correctedCard.buttons["shiftDetailDeliveryEarningsButton"].exists, "The others still apply")
        let alreadyCancelled = deliveryCard(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(alreadyCancelled, in: app))
        XCTAssertFalse(alreadyCancelled.buttons["shiftDetailCorrectToCancelledButton"].exists, "Already terminal as what it was")
    }

    /// Deleting a recorded pause and adding one never recorded: deleting is
    /// confirmed and says the working time grows and the route is untouched,
    /// backing out keeps it, and the pause left is renumbered; a missed pause
    /// opens refused rather than suggested, and once given a valid stretch is
    /// numbered by when it began and comes out of working time.
    ///
    /// Was three journeys over this fixture.
    @MainActor
    func testDeletingAndAddingPauses() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let delete = pauseButton("deleteShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        XCTAssertEqual(delete.label, "Delete Pause 1. Record that this pause did not happen")
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.appears())
        dismiss(alert, tapping: "Cancel")
        XCTAssertTrue(pauseRow(containing: "Pause 1", in: app).label.contains("30 minutes"), "Backing out keeps it")

        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        delete.tap()
        XCTAssertTrue(alert.appears())
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "working time becomes 30 min longer")).count > 0
        )
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "route recorded during it is not changed")).count > 0
        )
        let confirm = alert.buttons.matching(identifier: "confirmDeleteShiftPauseButton").firstMatch
        XCTAssertEqual(confirm.label, "Delete Pause 1")
        tapClosingDialog(confirm)
        let remaining = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(remaining.appears())
        XCTAssertTrue(remaining.label.contains("20 minutes"), "The pause left is the one that was second")
        XCTAssertFalse(pauseRow(containing: "Pause 2", in: app).exists)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailWorkingTime"], toContain: "3 hours, 40 minutes"))
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailPausedTime"].label, "20 minutes paused time, over 1 pause")

        let add = app.buttons["addMissedPauseButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        XCTAssertEqual(add.label, "Add a pause you did not record during the shift")
        add.tap()
        let refusal = app.descendants(matching: .any).matching(identifier: "shiftPauseEditorRefusal").firstMatch
        XCTAssertTrue(refusal.appears(), "Nothing is suggested")
        XCTAssertTrue(refusal.label.contains("A pause has to end after it started"), "Showed: \(refusal.label)")
        XCTAssertFalse(app.buttons["shiftPauseEditorSaveButton"].isEnabled)
        setTime(minute: "50", ofPicker: "shiftPauseStartPicker", in: app)
        setTime(minute: "55", ofPicker: "shiftPauseEndPicker", in: app)
        let summary = app.descendants(matching: .any)["shiftPauseEditorSummary"]
        XCTAssertTrue(summary.appears())
        XCTAssertTrue(summary.label.hasPrefix("5 minutes paused"), "Showed: \(summary.label)")
        app.buttons["shiftPauseEditorSaveButton"].tap()
        let added = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(added.appears())
        XCTAssertTrue(added.label.contains("5 minutes"), "First, because it began first: \(added.label)")
        XCTAssertTrue(pauseRow(containing: "Pause 2", in: app).exists, "Two of them now")

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailPausedTime"], toContain: "over 2 pauses"))
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailWorkingTime"].label, "3 hours, 35 minutes working time")
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time", "The shift's own times did not move")
    }

    /// The real recovery, end to end. The delivery's completion and the shift's
    /// end were both recorded late; correcting the end is refused naming the
    /// delivery and event; the delivery's times say what they will not touch,
    /// refuse an order that breaks the lifecycle, and once corrected move the
    /// two figures derived from them while the route stays as recorded; and
    /// the same end correction is then accepted and trims the route.
    ///
    /// Was three journeys. The rules are `DeliveryTimeCorrectionTests`.
    @MainActor
    func testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs() throws {
        let app = launchWithLateDeliveryHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app))
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time")
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("6.7 miles"), "Showed: \(mileage.label)")
        let row = app.descendants(matching: .any)["shiftDetailDeliveryRow"].firstMatch
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(row.label.contains("Accepted to delivered 1 hour, 30 minutes"), "Showed: \(row.label)")
        XCTAssertTrue(row.label.contains("$8.00 earned per recorded delivery hour"), "Showed: \(row.label)")

        // 1. The end is refused, naming the delivery and the event.
        let correctEnd = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app))
        correctEnd.tap()
        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].appears())
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        let endRefusal = app.descendants(matching: .any).matching(identifier: "shiftEndCorrectionRefusal").firstMatch
        XCTAssertTrue(endRefusal.appears())
        XCTAssertTrue(endRefusal.label.hasPrefix("Delivery 1 has Delivered recorded at "), "Showed: \(endRefusal.label)")
        XCTAssertTrue(endRefusal.label.contains("Open that delivery and correct its times"), "Showed: \(endRefusal.label)")
        XCTAssertFalse(app.buttons["shiftEndCorrectionSaveButton"].isEnabled)
        app.buttons["shiftEndCorrectionCancelButton"].tap()

        // 2. The delivery's times: what they will not touch, and an order that
        //    breaks the lifecycle refused.
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        let correctTimes = app.buttons["shiftDetailCorrectDeliveryTimesButton"]
        XCTAssertTrue(scrollUntilHittable(correctTimes, in: app, maxSwipes: 15))
        XCTAssertTrue(correctTimes.label.hasPrefix("Correct the times Delivery 1 recorded"), correctTimes.label)
        correctTimes.tap()
        let summary = app.descendants(matching: .any)["deliveryTimeCorrectionSummary"]
        XCTAssertTrue(summary.appears())
        XCTAssertTrue(summary.label.contains("1 hour, 30 minutes"), "Showed: \(summary.label)")
        let note = app.descendants(matching: .any).matching(identifier: "deliveryTimeCorrectionRouteNotice").firstMatch
        XCTAssertTrue(note.appears())
        XCTAssertTrue(note.label.contains("recorded mileage are not changed"), "Showed: \(note.label)")
        setTime(minute: "02", ofPicker: "deliveryTimeCorrectionPicker.pickedUp", in: app)
        let timeRefusal = app.descendants(matching: .any).matching(identifier: "deliveryTimeCorrectionRefusal").firstMatch
        XCTAssertTrue(timeRefusal.appears())
        XCTAssertTrue(timeRefusal.label.hasPrefix("Picked up cannot be earlier than arrived at the pickup"), timeRefusal.label)
        XCTAssertTrue(timeRefusal.label.contains("correct arrived at the pickup as well"), timeRefusal.label)
        XCTAssertFalse(app.buttons["deliveryTimeCorrectionSaveButton"].isEnabled)
        setTime(minute: "10", ofPicker: "deliveryTimeCorrectionPicker.pickedUp", in: app)

        // 3. The completion corrected: the derived figures move, nothing else.
        setTime(minute: "15", ofPicker: "deliveryTimeCorrectionPicker.delivered", in: app)
        XCTAssertTrue(waitForLabel(summary, toContain: "1 hour, 15 minutes"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("$9.60"), "Showed: \(summary.label)")
        app.buttons["deliveryTimeCorrectionSaveButton"].tap()
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(waitForLabel(row, toContain: "Accepted to delivered 1 hour, 15 minutes"), "Showed: \(row.label)")
        XCTAssertTrue(row.label.contains("$9.60 earned per recorded delivery hour"), "Showed: \(row.label)")
        XCTAssertTrue(row.label.contains("Gross earnings for Delivery 1, $12.00"), "The amount did not move")
        XCTAssertTrue(row.label.contains("Waited at pickup 5 minutes"), "Nor the wait's two ends")
        XCTAssertTrue(row.label.hasPrefix("Delivery 1, delivered"), "Still terminal the same way")
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("6.7 miles"), "Not one metre of route moved with the times")

        // 4. The same end correction, now accepted, trims the route.
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app))
        correctEnd.tap()
        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].appears())
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertFalse(endRefusal.exists, "No longer refused")
        app.buttons["shiftEndCorrectionSaveButton"].tap()
        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.appears())
        tapClosingDialog(confirm)
        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(elapsed, toContain: "3 hours, 20 minutes"))
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(waitForLabel(hourlyRate, toContain: "$30.00"), "Showed: \(hourlyRate.label)")
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(waitForLabel(mileage, toContain: "4.5 miles"), "Measured again: \(mileage.label)")
    }

    /// A pickup place named on a running delivery advances nothing; a second
    /// delivery reuses it from the recent list with no typing; a place put on
    /// the wrong delivery is changed; and removing it leaves the delivery
    /// exactly where it was in its lifecycle.
    ///
    /// Was four journeys, each starting a shift and a delivery. Matching is
    /// `PickupPlaceNameTests`.
    @MainActor
    func testAPickupPlaceIsNamedReusedChangedAndRemoved() throws {
        let app = launchWithEmptyStore()
        startShiftAndDelivery(in: app)

        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark arrived at pickup"))
        let pickup = deliveryButton("pickupPlaceButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(pickup, in: app), "The card offers a pickup place control")
        XCTAssertEqual(pickup.label, "Add pickup place for Delivery 1")
        tapWithinReach(pickup, in: app)
        typePickupPlace(Self.noodles, in: app)
        app.buttons["savePickupPlaceButton"].tap()
        let status = deliveryStatus(containing: "Delivery 1", in: app)
        XCTAssertTrue(waitForLabel(status, toContain: Self.noodles), "The card names the place: \(status.label)")
        XCTAssertTrue(waitForLabel(pickup, toContain: "Change pickup place"))
        XCTAssertEqual(action.label, "Delivery 1. Mark arrived at pickup", "Naming a pickup advances nothing")

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app))
        startDelivery.tap()
        let second = deliveryButton("pickupPlaceButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(second.appears())
        tapWithinReach(second, in: app)
        let recent = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "recentPickupPlaceButton", Self.noodles))
            .firstMatch
        XCTAssertTrue(recent.appears(), "The place used moments ago is offered")
        recent.tap()
        XCTAssertTrue(waitForLabel(deliveryStatus(containing: "Delivery 2", in: app), toContain: Self.noodles))

        XCTAssertTrue(scrollTo(pickup, in: app))
        tapWithinReach(pickup, in: app)
        let field = app.textFields["pickupPlaceNameField"]
        XCTAssertTrue(field.appears())
        XCTAssertEqual(field.value as? String, Self.noodles, "The editor opens on what was recorded")
        clear(field, in: app)
        enter(Self.diner, into: field, in: app)
        app.buttons["savePickupPlaceButton"].tap()
        XCTAssertTrue(waitForLabel(status, toContain: Self.diner), "Showed: \(status.label)")
        XCTAssertFalse(status.label.contains(Self.noodles), "The old place is gone from the card")

        tapWithinReach(action, in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark order picked up"))
        XCTAssertTrue(waitForLabel(pickup, toContain: "Change pickup place"))
        tapWithinReach(pickup, in: app)
        let remove = app.buttons["removePickupPlaceButton"]
        XCTAssertTrue(remove.appears())
        remove.tap()
        XCTAssertTrue(waitForLabel(status, toContain: "waiting at the pickup"), "Showed: \(status.label)")
        XCTAssertFalse(status.label.contains(Self.diner), "The place is gone")
        XCTAssertEqual(action.label, "Delivery 1. Mark order picked up", "Exactly where it was in its lifecycle")
        XCTAssertTrue(waitForLabel(pickup, toContain: "Add pickup place"))
    }

    // MARK: Same pickup and same drop-off

    /// The real correction from October 3 2026: two deliveries started one at a
    /// time, so two offers, turn out to share a pickup. Edit Stack marks them
    /// without cancelling, recreating or advancing either, and takes it back.
    ///
    /// The combinations (larger stacks, finished members, relaunch, Park) are in
    /// `StackEditTests`; this proves the control is where a driver at a counter
    /// finds it and that both cards say what was recorded.
    @MainActor
    func testEditStackMarksSeparateDeliveriesSamePickupWithoutRecreatingThem() throws {
        let app = launchWithActiveDelivery()

        let edit = app.buttons["editStackButton"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app), "Offered while two deliveries are in progress")
        edit.tap()

        func row(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "stackDeliveryRow", name))
                .firstMatch
        }
        XCTAssertTrue(row("Delivery 2").appears())
        XCTAssertEqual(
            app.buttons.matching(identifier: "stackDeliveryRow").count, 2,
            "Only the deliveries in progress; Delivery 1 has been delivered"
        )
        let markPickup = app.buttons["markSamePickupButton"]
        XCTAssertFalse(markPickup.isEnabled, "Nothing chosen yet")
        row("Delivery 2").tap()
        XCTAssertFalse(markPickup.isEnabled, "One delivery shares a stop with nobody")
        row("Delivery 3").tap()
        XCTAssertEqual(row("Delivery 3").value as? String, "Chosen")
        XCTAssertTrue(markPickup.isEnabled)
        markPickup.tap()

        let message = app.descendants(matching: .any)["stackEditMessage"]
        XCTAssertTrue(waitForLabel(message, toContain: "Delivery 2 and Delivery 3 marked same pickup"), "Showed: \(message.label)")
        XCTAssertTrue(waitForLabel(row("Delivery 2"), toContain: "same pickup as Delivery 3"))
        app.buttons["doneEditingStackButton"].tap()
        XCTAssertTrue(waitForDisappearance(of: markPickup))

        // Both cards say it, and neither moved: still two deliveries, still the
        // steps they had.
        let second = deliveryCard("Delivery 2", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(waitForLabel(second, toContain: "same pickup as Delivery 3"), "Showed: \(second.label)")
        XCTAssertTrue(second.label.contains("Next step, mark arrived at pickup"), "No arrival was recorded: \(second.label)")
        let third = deliveryCard("Delivery 3", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("same pickup as Delivery 2"), "Showed: \(third.label)")
        XCTAssertTrue(third.label.contains("Next step, mark delivery completed"), "Showed: \(third.label)")

        // Taken back the same way.
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        XCTAssertTrue(row("Delivery 2").appears())
        row("Delivery 2").tap()
        app.buttons["separatePickupButton"].tap()
        XCTAssertTrue(waitForLabel(message, toContain: "no longer marked same pickup"), "Showed: \(message.label)")
        XCTAssertFalse(row("Delivery 3").label.contains("same pickup"), "A pair left with one shares nothing")
        app.buttons["doneEditingStackButton"].tap()
    }

    // MARK: The Live Activity card

    /// Launches over an empty throwaway store with the Live Activity's card
    /// drawn on the main screen, clipped to the Lock Screen's height.
    @MainActor
    private func launchWithLiveActivityPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [Self.inMemoryStoreArgument, "-dashpilot-live-activity-preview"]
        launchInPortrait(app)
        return app
    }

    /// The card's controls, in the order they are drawn: row by row, left to
    /// right.
    @MainActor
    private func activityControls(in app: XCUIApplication) -> [String] {
        let card = app.descendants(matching: .any)["liveActivityPreview"]
        XCTAssertTrue(card.appears())
        let controls = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activityControl."))
        return controls.allElementsBoundByIndex
            .sorted { lhs, rhs in
                abs(lhs.frame.minY - rhs.frame.minY) < 4 ? lhs.frame.minX < rhs.frame.minX : lhs.frame.minY < rhs.frame.minY
            }
            .map(\.identifier)
    }

    /// Asserts the card draws `identifier` wholly inside the 160 points a Lock
    /// Screen shows, which is the property the real-device defect lost.
    @MainActor
    private func assertInsideTheCard(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.descendants(matching: .any)["liveActivityPreview"]
        let control = card.buttons[identifier]
        XCTAssertTrue(control.appears(), "\(identifier) is on the card", file: file, line: line)
        XCTAssertLessThanOrEqual(
            control.frame.maxY, card.frame.maxY + 0.5,
            "\(identifier) is inside the card: \(control.frame) in \(card.frame)", file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(control.frame.minY, card.frame.minY - 0.5, file: file, line: line)
    }

    /// The driver's setting decides which control leads: the delivery step with
    /// the workflow off, Park Vehicle with it on, and Resume Driving once parked.
    @MainActor
    func testLiveActivityLeadsWithParkOnlyUnderTheWorkflow() throws {
        let app = launchWithLiveActivityPreview()
        startShiftAndDelivery(in: app)

        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["liveActivityPreview"], in: app))
        XCTAssertEqual(
            activityControls(in: app),
            ["activityControl.deliveryStep", "activityControl.startDelivery", "activityControl.park"],
            "Workflow off: the delivery step leads, as it always did"
        )

        setPickupWorkflow(true, in: app)
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["liveActivityPreview"], in: app))
        XCTAssertEqual(
            activityControls(in: app),
            ["activityControl.park", "activityControl.deliveryStep", "activityControl.startDelivery"],
            "Workflow on: Park leads, and the step stays on the card"
        )
        for control in ["activityControl.park", "activityControl.deliveryStep", "activityControl.startDelivery"] {
            assertInsideTheCard(control, in: app)
        }

        pressPark(in: app)
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["liveActivityPreview"], in: app))
        XCTAssertEqual(activityControls(in: app).first, "activityControl.resumeDriving")
        assertInsideTheCard("activityControl.resumeDriving", in: app)
        assertInsideTheCard("activityControl.deliveryStep", in: app)
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
        XCTAssertTrue(banner.appears(), "The offer to take it back is on screen")
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

        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].appears(), "The seeded shift is running")

        // Nothing was marked delivered in this session, so there is no offer to
        // catch: this is the path for a mistake noticed later.
        XCTAssertFalse(app.buttons["undoDeliveredButton"].exists)

        let reopen = app.buttons["reopenDeliveryButton"]
        XCTAssertTrue(scrollTo(reopen, in: app), "The deliberate way back is one control under the panel")
        reopen.tap()

        let row = app.descendants(matching: .any)["deliveryRecoveryRow"]
        XCTAssertTrue(row.appears(), "The shift's delivered delivery is listed")
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
        XCTAssertTrue(alert.appears(), "Reopening from history is confirmed")
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
        tapClosingDialog(confirm)

        XCTAssertTrue(
            app.staticTexts["deliveryRecoveryUnavailable"].appears(),
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

    // MARK: Correcting a historical completion to a cancellation

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

    /// What a running shift does **not** offer, checked through the states one
    /// shift passes through, in one launch.
    ///
    /// Five journeys used to launch an empty store each to assert one absence
    /// apiece: no pause correction, no end correction, no export, no reopening
    /// and no regrouping while a shift runs. Each absence is a rule a driver at
    /// a wheel depends on, and each is cheap to read on a screen the journey is
    /// already on, so they share this launch. The one positive case stays: two
    /// deliveries are a grouping and do offer the correction.
    @MainActor
    func testARunningShiftOffersOnlyWhatItsStateAllows() throws {
        let app = launchWithEmptyStore()

        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(start.appears())
        XCTAssertFalse(app.buttons["exportAllHistoryButton"].exists, "No completed shift, so no history export")
        start.tap()

        XCTAssertTrue(app.buttons["pauseShiftButton"].appears(), "The shift is running")
        let neverWhileRunning = [
            "editShiftPauseButton", "deleteShiftPauseButton", "addMissedPauseButton",
            "correctShiftEndButton", "exportShiftButton", "exportAllHistoryButton",
            "reopenDeliveryButton", "correctOffersButton",
            "shiftDetailCorrectDeliveryTimesButton", "shiftDetailCorrectToCancelledButton"
        ]
        for identifier in neverWhileRunning {
            XCTAssertFalse(app.buttons[identifier].exists, "\(identifier) is not offered on a running shift")
        }
        app.buttons["pauseShiftButton"].tap()
        XCTAssertTrue(app.buttons["resumeShiftButton"].appears(), "and now it is paused")
        for identifier in ["editShiftPauseButton", "deleteShiftPauseButton", "addMissedPauseButton"] {
            XCTAssertFalse(
                app.buttons[identifier].exists,
                "\(identifier) is not offered on a paused shift either: the open pause is Resume's and End's"
            )
        }
        app.buttons["resumeShiftButton"].tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(startDelivery.appears())
        startDelivery.tap()
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1))
        XCTAssertFalse(
            app.buttons["reopenDeliveryButton"].exists,
            "A delivery in progress has a card of its own; nothing delivered can be reopened"
        )
        XCTAssertFalse(app.buttons["correctOffersButton"].exists, "One delivery is not a grouping")

        XCTAssertTrue(scrollToTop(reaching: startDelivery, in: app))
        startDelivery.tap()
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2))
        XCTAssertTrue(scrollTo(app.buttons["correctOffersButton"], in: app), "Two deliveries can be regrouped")
    }

    // MARK: Delivery earnings, from detail

    /// Money is recorded against a delivery only after the driving: the
    /// running shift offers no amount or tip control at any step, and once it
    /// has ended the delivery's amount is recorded, named for its delivery,
    /// replaced rather than added to by an edit, and joined by a tip recorded
    /// outside it, with the three figures read back in the order they add up.
    ///
    /// Was two journeys, each driving the same delivery to completion first.
    /// Independence from the shift's amount, missing versus zero and the tip
    /// arithmetic are `DeliveryEarningsTests` and the tip suites.
    @MainActor
    func testAddsAndEditsDeliveryEarningsAndATipFromDetail() throws {
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
        XCTAssertTrue(field.appears())
        XCTAssertEqual(field.value as? String, "14.75", "The editor opens on the stored amount")
        clear(field, in: app)
        enter("10.00", into: field, in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "$10.00"), "The edited amount replaces the previous one")
        XCTAssertFalse(row.label.contains("$14.75"))

        // A tip received outside the platform's amount is its own record.
        let tipsButton = app.buttons["shiftDetailDeliveryTipsButton"].firstMatch
        XCTAssertTrue(tipsButton.appears())
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

    // MARK: Helpers

    /// Invented pickup-place names, matching `PreviewSupport.SyntheticPickupPlace`;
    /// a UI test target cannot link the app target, so they are repeated here.
    /// No real business is named anywhere in this repository.
    private static let noodles = "Nowhere Noodles"
    private static let diner = "Example Diner"

    /// Starts a shift and one delivery on it, which is the state three of the
    /// pickup journeys begin from.
    @MainActor
    private func startShiftAndDelivery(in app: XCUIApplication) {
        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.appears())
        startShift.tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(scrollTo(startDelivery, in: app))
        startDelivery.tap()
    }

    /// Types a name into the pickup-place sheet's only field.
    @MainActor
    private func typePickupPlace(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["pickupPlaceNameField"]
        XCTAssertTrue(field.appears())
        enter(name, into: field, in: app)
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
        XCTAssertTrue(picker.appears(), "\(identifier) is on screen")
        XCTAssertTrue(picker.buttons.count > 1, "\(identifier) shows a date and a time")
        let timeButton = picker.buttons.element(boundBy: picker.buttons.count - 1)
        let before = timeButton.label
        timeButton.tap()

        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.appears(), "The time wheels are showing")
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

        XCTAssertTrue(
            waitUntil { picker.buttons.element(boundBy: picker.buttons.count - 1).label != before },
            "\(identifier) records the time that was chosen rather than the one it opened on"
        )

        // A tap on the bar's own frame rather than on the bar as an element.
        // Tapping the element asks XCUITest for a hit point first, and with the
        // wheels' popover over the form that can come back as {-1, -1}: the tap
        // then lands nowhere and the wheels stay up, which is how this failed on
        // a CI runner. A coordinate inside the bar is outside the popover either
        // way, and a touch there is what closes it.
        //
        // The bar is the **sheet's**, the lowest on screen. `firstMatch` was
        // the presenting screen's bar, which the sheet covers, so where that
        // point landed depended on the sheet's geometry: CI run 36947255282
        // tapped (201, 89), the centre of the shift detail's bar behind the
        // editor, and the wheels stayed up.
        let bars = app.navigationBars.allElementsBoundByIndex
        let sheetBar = bars.max { $0.frame.minY < $1.frame.minY } ?? app.navigationBars.firstMatch
        sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            waitForDisappearance(of: app.pickerWheels.firstMatch),
            "The wheels close, so the rest of the form can be reached"
        )
    }

    // MARK: Settings, vehicles and fuel defaults

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
        XCTAssertTrue(civic.appears(), "The vehicle is listed")
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
        XCTAssertTrue(camry.appears())
        XCTAssertFalse(camry.label.contains("Selected"), "Adding a vehicle is not choosing one: \(camry.label)")

        // Correcting the first one moves neither the list nor the selection.
        let edit = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        XCTAssertTrue(economyField.appears())
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
        XCTAssertTrue(field.appears())
        let existing = (field.value as? String) ?? ""
        field.doubleTap()
        field.typeText(text)
        XCTAssertTrue(
            waitForFieldValue(field, toEqual: text),
            "The field should hold what was typed, not \(existing) with it prepended or appended"
        )
    }

    // MARK: Settings helpers

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["settingsLink"]
        XCTAssertTrue(settings.appears())
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears())
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
        XCTAssertTrue(nameField.appears())
        enter(name, into: nameField, in: app)

        let economyField = app.textFields["vehicleMilesPerGallonField"]
        enter(milesPerGallon, into: economyField, in: app)

        app.buttons["saveVehicleButton"].tap()
        assertVehicleSheetClosed(in: app)
    }

    /// Waits for the vehicle sheet to be **gone**, and then for Settings.
    ///
    /// Waiting for the `Settings` bar alone is not enough: the bar exists behind
    /// the sheet the whole time it animates away, so a journey that proceeds on
    /// it taps a row the sheet is still covering, the tap does nothing, and the
    /// journey fails on the assertion after it. That is the race `addTip`
    /// already closes, and it failed a CI run here once.
    @MainActor
    private func assertVehicleSheetClosed(in app: XCUIApplication) {
        XCTAssertTrue(
            waitForDisappearance(of: app.textFields["vehicleMilesPerGallonField"]),
            "The vehicle sheet closes back to Settings"
        )
        XCTAssertTrue(app.navigationBars["Settings"].appears())
    }

    @MainActor
    private func setCurrentGasPrice(_ price: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["currentGasPriceRow"]
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        row.tap()

        replaceTappedField(app.textFields["currentGasPriceField"], with: price, in: app)
        app.buttons["saveCurrentGasPriceButton"].tap()
        // Gone, not merely behind: see `assertVehicleSheetClosed(in:)`.
        XCTAssertTrue(
            waitForDisappearance(of: app.textFields["currentGasPriceField"]),
            "The gas price sheet closes back to Settings"
        )
        XCTAssertTrue(app.navigationBars["Settings"].appears())
    }

    /// History's completed shift rows, queried as the buttons they are.
    ///
    /// Each row is a `NavigationLink`, which XCTest reports as a `Button` in
    /// every journey that resolved one (33 of them, the largest text size
    /// included, across runs 37406553911, 37418449153 and 37478065976). It was
    /// queried as `.any`, which makes XCTest fault in every element on the
    /// screen one at a time, and under a loaded runner that walk is the
    /// slowest query in the suite: 17 of the 27 queries of 5 s or more in
    /// those three runs, up to 48 s for one evaluation, while a typed button
    /// query in the same second took 0.24 s.
    @MainActor
    private func rows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "completedShiftRow")
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
        settleWhollyOnScreen(history.element(boundBy: count - 1), in: app)
        return history
    }

    /// Runs one shift start-to-finish.
    ///
    /// Also asserts the safety rule the earnings flow depends on: nothing offers
    /// earnings entry while a shift is running.
    @MainActor
    private func completeAShift(in app: XCUIApplication) {
        let startButton = app.buttons["startShiftButton"]
        XCTAssertTrue(startButton.appears())
        // Back to the top first: returning from a pushed screen keeps the
        // list where it was, which can leave Start under the navigation bar.
        XCTAssertTrue(scrollToTop(reaching: startButton, in: app))
        startButton.tap()

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(
            app.descendants(matching: .any)["activeShiftStatus"].appears(),
            "The shift is running"
        )
        XCTAssertFalse(
            app.buttons["editShiftEarningsButton"].exists,
            "Earnings entry must not be offered while the driver may be driving"
        )
        // End is below the delivery section, so it is searched for.
        XCTAssertTrue(reachShiftControl(endButton, in: app))
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
        XCTAssertTrue(start.appears(), "The shift has ended")
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
            if element.isHittable { return revealAboveEntryBar(element, in: app) }
            // Already in the list but off screen: move it by the distance it
            // is away rather than by a whole swipe, which can carry it past
            // the top, after which a downward search never finds it again.
            let window = app.windows.firstMatch.frame
            if element.exists, element.frame.minY > window.midY {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                let distance = min(element.frame.maxY - window.maxY * 0.6 + 24, window.height * 0.45)
                start.press(
                    forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.3
                )
            } else {
                app.swipeUp()
            }
        }
        return element.isHittable && revealAboveEntryBar(element, in: app)
    }

    /// Taps a control on the running shift's panel once it is inside the band
    /// a tap reaches, clear of the navigation bar and of the pinned delivery
    /// entry. `tap()` alone scrolls a control only until it is on screen, which
    /// can leave it under the entry bar, and the tap then lands on the bar.
    @MainActor
    private func tapWithinReach(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.appears(), "The control is on the panel")
        XCTAssertTrue(revealAboveEntryBar(element, in: app), "The control is clear of the bars")
        element.tap()
    }

    /// A frame dimension rounded to the screen's pixel grid. A list scrolled to
    /// a fractional offset reports a 44-point control as 43.999999999999886,
    /// which is the same control on the same pixels; the 44-point minimum is
    /// asserted on what the screen can draw.
    @MainActor
    private func onPixelGrid(_ value: CGFloat) -> CGFloat {
        (value * 3).rounded() / 3
    }

    /// The top of the running shift's pinned delivery-entry bar, or `nil` where
    /// none is drawn (no shift, a paused one, or another screen on top).
    ///
    /// Read off the bar's own `Start Delivery` button, which is its tallest
    /// control, less the bar's padding. The bar is in the list's bottom safe
    /// area, so the list can always be scrolled clear of it, but a row that
    /// has scrolled partly beneath it is still reported hittable, and a tap at
    /// its centre lands on the bar: the same trap ``revealAboveBottomBar``
    /// handles for the Undo line.
    ///
    /// The Undo line, while one is offered, sits on the bar and is part of it
    /// for this purpose: its top is read off its sentence, which is the line's
    /// tallest part, less the line's padding. A Park line in the shift's panel
    /// shares one of those identifiers and is ignored unless it happens to sit
    /// directly on the bar, which only costs an extra drag.
    @MainActor
    private func entryBarTop(in app: XCUIApplication) -> CGFloat? {
        let start = app.buttons["startDeliveryButton"]
        guard start.exists, start.isHittable else { return nil }
        var top = start.frame.minY - 8
        for identifier in ["undoDeliveredBanner", "parkedProgressNotice", "pickupWorkflowNotice"] {
            for line in app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
            where line.exists {
                let frame = line.frame
                if frame.maxY <= top + 4, frame.maxY > top - 160 {
                    top = min(top, frame.minY - 20)
                }
            }
        }
        return top
    }

    /// Drags the list until `element` sits wholly inside the band a tap can
    /// reach: below the navigation bar and above the delivery-entry bar and any
    /// Undo line on it. XCUITest reports a control under either edge hittable
    /// and sends the tap to the bar instead. Each drag moves the list by the
    /// distance still needed and holds before lifting, so no momentum carries
    /// the control past the other edge. The bar's own controls, and anything
    /// already inside the band, return at once.
    @MainActor
    @discardableResult
    private func revealAboveEntryBar(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard !["startDeliveryButton", "startOfferButton"].contains(element.identifier) else { return true }
        // Only where the bar is drawn: elsewhere a control is reached exactly
        // as it always was, and a large-title bar or a row taller than the
        // band at the largest text sizes would otherwise be chased back and
        // forth without ever settling.
        guard entryBarTop(in: app) != nil else { return true }
        let navigationBar = app.navigationBars.firstMatch
        for _ in 0..<5 {
            guard element.exists else { return false }
            let frame = element.frame
            let top = navigationBar.exists ? navigationBar.frame.maxY : 0
            guard let bottom = entryBarTop(in: app) else { return true }
            guard frame.height < bottom - top else { return true }
            let offset: CGFloat
            if frame.maxY > bottom {
                offset = -min(frame.maxY - bottom + 24, 360)
            } else if frame.minY < top {
                offset = min(top - frame.minY + 24, 360)
            } else {
                return true
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(
                forDuration: 0.1,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        }
        guard let bottom = entryBarTop(in: app) else { return true }
        let frame = element.frame
        let top = navigationBar.exists ? navigationBar.frame.maxY : 0
        return frame.minY >= top && frame.maxY <= bottom
    }

    /// Drags the list until `element` sits clear of the line below it.
    ///
    /// ``TransientUndoBar`` floats over the bottom of the list rather than
    /// pushing it, so that its arriving and leaving move no card. A control
    /// partly under it is still reported hittable, and a tap at its centre
    /// lands on the bar. Small drags, so the control is not carried off the top.
    @MainActor
    @discardableResult
    private func revealAboveBottomBar(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let limit = app.windows.firstMatch.frame.maxY * 0.65
        for _ in 0..<6 {
            guard element.exists, element.frame.maxY > limit else { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        }
        return element.isHittable && element.frame.maxY <= limit
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
        return element.appears()
    }

    /// Answers an app alert with one of its buttons and waits for it to close.
    ///
    /// The screen behind an alert stays in the hierarchy while the alert is up,
    /// so a journey that goes on to read or scroll that screen proves nothing
    /// about the alert having gone. In CI run 37418449153
    /// `testCorrectingAHistoricalCompletionToACancellation` tapped Cancel (the
    /// recording shows the button take the press), the row behind still
    /// "existed", and the journey failed ten drags later on a control the
    /// alert was still covering. Waiting here names the step that went wrong.
    @MainActor
    private func dismiss(_ alert: XCUIElement, tapping title: String) {
        alert.buttons[title].firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(of: alert), "The alert closes on \(title)")
    }

    /// Taps a button in an alert or confirmation dialog and waits for the
    /// dialog to close, so a tap iOS never acted on fails here, by name.
    ///
    /// PR run 37525485173 tapped `Cancel Delivery 2` at the centre of its
    /// frame on a dialog that had been up for twenty seconds, and the
    /// recording shows the dialog still up to the end of the journey: nothing
    /// was cancelled, and the journey failed later on a status line that had
    /// rightly not moved. It is not tapped again here, because a second tap
    /// would hide the very thing the run should report.
    @MainActor
    private func tapClosingDialog(_ button: XCUIElement) {
        let title = button.label
        button.tap()
        XCTAssertTrue(
            waitForDisappearance(of: button),
            "The dialog closes on \(title); still on screen means the tap was not acted on"
        )
    }

    /// Waits for `element` to be gone, returning the moment it is.
    ///
    /// It waits ``conditionTimeout`` for the reason every other condition here
    /// does. It was 5 s, and CI run 37418449153 showed the same failure that
    /// constant was raised for: right after a launch,
    /// `testACompletedShiftsDeliveriesPlacesAndGrouping` asked whether the
    /// delivery-entry bar was gone, the first snapshot took 4.2 s and its retry
    /// 5.7 s more, and the wait expired with the recording showing Home, no
    /// shift running and no bar from the first frame to the last.
    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = conditionTimeout) -> Bool {
        waitUntil(timeout: timeout) { !element.exists }
    }

    @MainActor
    /// Opens History's first shift, scrolling down to it first: the week's
    /// summary sits above the rows, so on a phone the first row is below the
    /// fold and a `List` has not rendered it until it is scrolled to.
    private func openFirstShift(in app: XCUIApplication) {
        // A shift ended a moment ago takes the delivery-entry bar with it, and
        // the list moves as its bottom inset goes: a row tapped during that
        // move is tapped where it was. Wait for the bar to go and the row to
        // stop moving, both conditions rather than a pause.
        XCTAssertTrue(waitForDisappearance(of: app.buttons["startDeliveryButton"]), "No shift is still running")
        let row = rows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app, maxSwipes: 12), "History lists a completed shift")
        settleWhollyOnScreen(row, in: app)
        row.tap()
    }

    /// Brings a list row wholly on screen and waits for the list to stop
    /// moving before it is tapped.
    ///
    /// Wholly on screen, not merely touching it: a row whose frame only
    /// reaches into the home indicator's strip is reported hittable, and the
    /// tap lands below the list (seen in two recordings, the first row of a
    /// short history and the second of a longer one, tapped while still
    /// settling and leaving Home on screen).
    @MainActor
    private func settleWhollyOnScreen(_ row: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(waitForStillFrame(of: row), "The list has laid out")
        let limit = app.windows.firstMatch.frame.maxY - 60
        for _ in 0..<3 where row.frame.maxY > limit {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(
                forDuration: 0.1,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(row.frame.maxY - limit + 24, 300))),
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        }
        XCTAssertTrue(waitForStillFrame(of: row), "The list has settled")
    }

    /// Waits until an element's frame has read the same for a whole second of
    /// consecutive readings, so a tap is not computed against a list that is
    /// still laying out. Two quick readings were not enough: a list rebuilding
    /// after a shift ended reported the same stale frame twice, and the row was
    /// tapped below the screen.
    ///
    /// The timeout bounds how long the element may keep **moving**, not how
    /// long XCTest takes to read it. A reading that ends past the deadline is
    /// still compared: once the deadline has passed, a change fails at once
    /// and a still frame gets its one-second window and its hittability
    /// check. It used to stop at the deadline, and CI run 37478065976 showed
    /// why that is wrong: in `testDeletingACompletedShiftIsConfirmed` the
    /// first reading took 25 s, the 8 s budget was gone before a second one
    /// was taken, and the wait failed with the recording showing both rows
    /// still and wholly on screen from 53 s to the end.
    @MainActor
    private func waitForStillFrame(of element: XCUIElement, timeout: TimeInterval = conditionTimeout) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        var previous = element.frame
        var stableSince = Date.now
        while true {
            let current = element.frame
            if current != previous {
                if Date.now >= deadline { return false }
                previous = current
                stableSince = .now
            } else if Date.now.timeIntervalSince(stableSince) >= 1 {
                if element.isHittable { return true }
                if Date.now >= deadline { return false }
            }
        }
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["DashPilot"].appears())
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
            tapWithinReach(action, in: app)
        }

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(reachShiftControl(endButton, in: app))
        XCTAssertFalse(
            app.buttons["shiftDetailDeliveryEarningsButton"].exists,
            "Not even once the delivery has finished, while the shift is still running"
        )
        XCTAssertFalse(app.buttons["shiftDetailDeliveryTipsButton"].exists)
        endButton.tap()

        assertTheShiftReachedHistory(in: app)
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
        XCTAssertTrue(add.appears())
        add.tap()

        let field = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(field.appears())
        enter(amount, into: field, in: app)

        let option = app.buttons[method]
        XCTAssertTrue(option.appears(), "The method picker offers \(method)")
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
        XCTAssertTrue(app.buttons["addDeliveryTipButton"].appears())
    }

    @MainActor
    private func typeDeliveryAmount(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.appears())
        enter(text, into: field, in: app)
    }

    @MainActor
    private func type(_ text: String, into app: XCUIApplication) {
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.appears())
        enter(text, into: field, in: app)
    }

    /// Types `text` into a text field, tapping it first only when it does not
    /// already hold the keyboard, and checks the field then says what was
    /// typed.
    ///
    /// Most of this app's editors focus their own field. Tapping a field that
    /// is already focused opens iOS's edit menu (AutoFill, Paste) under the
    /// finger, and keystrokes sent while it appears are lost: CI run
    /// 36963465798 typed `10.00` into the delivery earnings sheet, the result
    /// bundle's recording shows the menu appear after the `1`, and the delivery
    /// recorded $1.00, so the journey failed three steps later on a row that
    /// did not say $10.00. Asserting the field's contents here fails at the
    /// cause instead.
    @MainActor
    private func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.appears(), "The field is on screen")
        if !hasKeyboardFocus(field) {
            field.tap()
            XCTAssertTrue(waitUntil { hasKeyboardFocus(field) }, "The field took the keyboard")
        }
        // An empty field reports its placeholder as its value.
        let shown = (field.value as? String) ?? ""
        let before = shown == field.placeholderValue ? "" : shown
        field.typeText(text)
        XCTAssertTrue(
            waitForFieldValue(field, toEqual: before + text),
            "Every keystroke reached the field: \((field.value as? String) ?? "")"
        )
    }

    /// Waits for a text field to hold `expected`, where an empty expectation
    /// also accepts the placeholder an empty field reports as its value.
    ///
    /// A condition rather than one read, because keystrokes are still being
    /// delivered when `typeText` returns on a loaded host. CI run 37088088371
    /// failed `testChangesAPickupPlace` reading `Now` out of a field whose
    /// result-bundle recording shows it emptied a moment later: the deletes had
    /// all arrived, the assertion had simply looked first.
    @MainActor
    private func waitForFieldValue(_ field: XCUIElement, toEqual expected: String) -> Bool {
        waitUntil {
            let value = (field.value as? String) ?? ""
            if expected.isEmpty { return value.isEmpty || value == field.placeholderValue }
            return value == expected
        }
    }

    @MainActor
    private func hasKeyboardFocus(_ field: XCUIElement) -> Bool {
        (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Deletes what a field holds, by the rule ``enter(_:into:in:)`` follows:
    /// tapping a field that already has the keyboard raises the edit menu and
    /// loses keystrokes, which in CI runs 37007996270 and 37007976466 left
    /// `34` in the vehicle economy field and made `38` read `3438`.
    @MainActor
    private func clear(_ field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.appears(), "The field is on screen")
        if !hasKeyboardFocus(field) {
            field.tap()
            XCTAssertTrue(waitUntil { hasKeyboardFocus(field) }, "The field took the keyboard")
        }
        let shown = (field.value as? String) ?? ""
        let existing = shown == field.placeholderValue ? "" : shown
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        XCTAssertTrue(
            waitForFieldValue(field, toEqual: ""),
            "The field was emptied: \((field.value as? String) ?? "")"
        )
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
    private func waitForLabel(
        _ element: XCUIElement,
        toContain text: String,
        timeout: TimeInterval = DashPilotUITests.conditionTimeout
    ) -> Bool {
        waitUntil(timeout: timeout) { element.exists && element.label.contains(text) }
    }

    /// The same wait, on an element's spoken **value** rather than its label.
    ///
    /// A row whose label names the metric and whose value carries the figure is
    /// the arrangement this app uses everywhere a number is spoken, so a journey
    /// that waits for a figure has to wait on the value.
    @MainActor
    private func waitForLabelValue(_ element: XCUIElement, toEqual text: String) -> Bool {
        waitUntil { element.exists && (element.value as? String) == text }
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, toEqual count: Int) -> Bool {
        waitUntil { query.count == count }
    }

    /// The number of the offer the grouping correction screen lists `delivery`
    /// under, read from its row's `Move Delivery 2 out of Offer 1` label, or
    /// `nil` when no row names it.
    @MainActor
    private func offerNumber(of delivery: String, in app: XCUIApplication) -> Int? {
        let prefix = "Move \(delivery) out of Offer "
        let row = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                  "offerCorrectionDeliveryButton", prefix))
            .firstMatch
        guard row.appears() else { return nil }
        return Int(row.label.dropFirst(prefix.count))
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
    private func launchWithPeriodSummary(atTextSize category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededPeriodSummaryArgument)
        if let category {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        launchInPortrait(app)
        return app
    }

    @MainActor
    private func openPeriodSummary(in app: XCUIApplication) {
        let link = app.buttons["periodSummaryLink"]
        XCTAssertTrue(link.appears(), "History offers a way into the summaries")
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["periodTitle"].appears())
    }

    @MainActor
    private func selectPeriod(_ title: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["periodUnitPicker"]
        XCTAssertTrue(picker.appears())
        picker.buttons[title].tap()
    }

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
            app.descendants(matching: .any)["exportFileName"].appears(),
            "The sheet writes the file when it opens"
        )
    }

    @MainActor
    private func selectExportFormat(_ title: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["exportFormatPicker"]
        XCTAssertTrue(picker.appears())
        picker.buttons[title].tap()
    }

    @MainActor
    private func exportFileName(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["exportFileName"].label
    }

    // MARK: Month and chosen ranges

    /// The number a period's summary reports, or `nil` if it is showing an
    /// empty state instead.
    @MainActor
    private func shiftCount(in app: XCUIApplication) -> Int? {
        let element = app.descendants(matching: .any)["periodShiftCount"]
        guard element.appears() else { return nil }
        // The spoken label is "4 completed shifts".
        return Int(element.label.prefix(while: \.isNumber))
    }

    @MainActor
    private func periodTitle(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["periodTitle"].label
    }

    /// Whether today's week starts and ends in today's month, by the device's
    /// own calendar, which is the one Period Summary's weeks use (unlike
    /// History, which is Monday to Sunday). The journey runs on the same
    /// simulator as the app, so both read the same calendar.
    private static func currentWeekIsInsideCurrentMonth(now: Date = .now) -> Bool {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let month = calendar.dateInterval(of: .month, for: now) else { return false }
        return week.start >= month.start && week.end <= month.end
    }

    // MARK: Expenses

    /// Opens the expense list from the root screen.
    @MainActor
    private func openExpenses(in app: XCUIApplication) {
        // In the navigation bar, so it is reachable wherever the list has been
        // scrolled to and costs the shift history no room.
        let link = app.buttons["expensesLink"].firstMatch
        XCTAssertTrue(link.appears(), "The root screen offers a way into recorded expenses")
        link.tap()
        XCTAssertTrue(app.buttons["addExpenseButton"].appears())
    }

    /// Records one expense through the editor, leaving the category and date at
    /// their defaults.
    @MainActor
    private func recordExpense(_ amount: String, in app: XCUIApplication) {
        app.buttons["addExpenseButton"].tap()

        let field = app.textFields["expenseAmountField"]
        XCTAssertTrue(field.appears())
        enter(amount, into: field, in: app)

        app.buttons["saveExpenseButton"].tap()
        // The list is behind a sheet until the save dismisses it, and a tap
        // synthesised during that animation lands on nothing.
        XCTAssertTrue(
            app.buttons["saveExpenseButton"].disappears(),
            "The editor closes once the expense is recorded"
        )
    }

}

/// Waits for `condition` to hold, returning the moment it does.
///
/// Every condition wait in this target comes through here, because the
/// verdict has to rest on **readings**, not on the clock alone. On a loaded
/// runner one reading of the screen can take longer than the whole budget: in
/// regression run 37614136154 `testDeletingAndAddingPauses` asked whether the
/// time wheels had gone, the one reading took 14.3 s of a 15 s wait, and the
/// wait failed with the recording showing the wheels gone before the reading
/// began. `XCTNSPredicateExpectation` gave that wait a single reading; this
/// gives it at least two, the second begun after the first returned, so a
/// timeout means the condition was false when looked at again, not that one
/// look was slow. It only reads the screen: nothing is tapped again, and a
/// condition that keeps failing still fails, about 15 s later.
@MainActor
func waitUntil(
    timeout: TimeInterval = DashPilotUITests.conditionTimeout,
    _ condition: () -> Bool
) -> Bool {
    let deadline = Date.now.addingTimeInterval(timeout)
    var readings = 0
    while true {
        if condition() { return true }
        readings += 1
        if readings >= 2, Date.now >= deadline { return false }
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.2))
    }
}

extension XCUIElement {
    /// Waits for the element to exist, by ``waitUntil(timeout:_:)``'s rule.
    ///
    /// Replaces `waitForExistence(timeout: 5)`, which shares the single-reading
    /// problem and gave a condition a third of the budget every other wait has.
    @MainActor
    func appears(timeout: TimeInterval = DashPilotUITests.conditionTimeout) -> Bool {
        waitUntil(timeout: timeout) { exists }
    }

    /// Waits for the element to be gone, by the same rule.
    @MainActor
    func disappears(timeout: TimeInterval = DashPilotUITests.conditionTimeout) -> Bool {
        waitUntil(timeout: timeout) { !exists }
    }
}
