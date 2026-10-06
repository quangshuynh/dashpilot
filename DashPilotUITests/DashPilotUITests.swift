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

    /// Must match `OnboardingRecord.fresh`: forget the welcome was finished and
    /// let it show over a throwaway store.
    private static let onboardingFreshArgument = "-dashpilot-onboarding-fresh"

    /// Must match `OnboardingRecord.observe`: let it show over a throwaway
    /// store without forgetting.
    private static let onboardingObserveArgument = "-dashpilot-onboarding-observe"

    /// Must match `OnboardingRecord.completed`.
    private static let onboardingCompletedArgument = "-dashpilot-onboarding-completed"

    /// Must match `LaunchArgument.seededFinishedDelivery`, for the same reason.
    private static let seededFinishedDeliveryArgument = "-dashpilot-seeded-finished-delivery"

    /// About two and a half years of synthetic work; see
    /// `LaunchArgument.seededLongHistory` for its shape.
    private static let seededLongHistoryArgument = "-dashpilot-seeded-long-history"

    /// Must match `LaunchArgument.stubbedLocation`, for the same reason.
    private static let stubbedLocationArgument = "-dashpilot-stubbed-location"

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

    /// Launches against one finished shift holding one delivered, unpaid
    /// delivery: the state ``completeAShiftWithADelivery(in:)`` reaches by
    /// driving the interface, without the minute it costs.
    @MainActor
    private func launchWithFinishedDelivery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.seededFinishedDeliveryArgument)
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
        // The real store, so the welcome would show on a fresh simulator; this
        // journey is about the store opening, so the welcome counts as seen.
        app.launchArguments.append(Self.onboardingCompletedArgument)
        launchInPortrait(app)

        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(step.waitForExistence(timeout: 10), "A new driver is welcomed")
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
        XCTAssertTrue(app.buttons["startShiftButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDisappearance(of: step))

        // Relaunched without forgetting: the welcome stays finished.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments += [Self.inMemoryStoreArgument, Self.onboardingObserveArgument]
        launchInPortrait(again)
        XCTAssertTrue(again.buttons["startShiftButton"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboardingStep"].label, "Step 1 of 4")
        let next = app.buttons["nextOnboardingButton"]
        XCTAssertTrue(next.isHittable, "The primary control is reachable at the largest size")
        XCTAssertGreaterThanOrEqual(onPixelGrid(next.frame.height), 44)
        attachScreenshot("onboarding-largest-text")

        let close = app.buttons["skipOnboardingButton"]
        XCTAssertEqual(close.label, "Close", "Reopened, it closes rather than skips")
        XCTAssertGreaterThanOrEqual(onPixelGrid(close.frame.height), 44)
        close.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(next.waitForExistence(timeout: 5))
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
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
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

    /// A shift started in the wrong vehicle is corrected before any driving:
    /// the sheet saves nothing until something is chosen, cancelling records
    /// nothing, the choice survives leaving the app, and Settings is untouched.
    ///
    /// Was two journeys. The rules are `RunningShiftFuelCorrectionTests`.
    @MainActor
    func testCorrectingTheRunningShiftsVehicle() throws {
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
        XCTAssertEqual(vehicle.value as? String, "2020 Honda Civic, 34 miles per gallon", "The first vehicle added is selected")

        let change = app.buttons["changeShiftVehicleButton"]
        let save = app.buttons["saveShiftVehicleButton"]
        let camry = app.descendants(matching: .any)
            .matching(identifier: "correctionVehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", "2012 Toyota Camry"))
            .firstMatch

        XCTAssertTrue(scrollUntilHittable(change, in: app), "Correction is offered before any driving")
        change.tap()
        XCTAssertTrue(camry.waitForExistence(timeout: 5))
        camry.tap()
        app.buttons["cancelShiftVehicleButton"].tap()
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "2020 Honda Civic, 34 miles per gallon", "Choosing a row is not recording it")

        XCTAssertTrue(scrollUntilHittable(change, in: app))
        change.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Saving the choices already recorded would report a change nobody made")
        XCTAssertTrue(camry.waitForExistence(timeout: 5))
        camry.tap()
        XCTAssertTrue(waitForLabel(camry, toContain: "Chosen"), "The mark is said, not only drawn: \(camry.label)")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let corrected = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(corrected, in: app))
        XCTAssertTrue(
            waitForLabelValue(corrected, toEqual: "2012 Toyota Camry, 28 miles per gallon"),
            "Showed: \(String(describing: corrected.value))"
        )
        XCUIDevice.shared.press(.home)
        app.activate()
        let returned = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(returned, in: app))
        XCTAssertEqual(returned.value as? String, "2012 Toyota Camry, 28 miles per gallon")

        openSettings(in: app)
        let civicRow = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(civicRow.waitForExistence(timeout: 5))
        XCTAssertTrue(civicRow.label.contains("Selected"), "The selection is still the driver's own: \(civicRow.label)")
        XCTAssertTrue(civicRow.label.contains("34 miles per gallon"), "And the profile is unchanged")
        XCTAssertTrue(vehicleRow(containing: "2012 Toyota Camry", in: app).label.contains("28 miles per gallon"))
    }

    /// At the largest accessibility text size a long vehicle name is entered
    /// through the editor's own focus, and wraps whole on the Settings card, in
    /// the list and on Home, with Start Shift still reachable.
    ///
    /// Was two journeys entering the same name at the same size.
    @MainActor
    func testALongVehicleNameAtTheLargestTextSize() throws {
        let app = launchWithEmptyStore(textSize: Self.accessibilityXXXLTextSize)
        let name = "2020 Honda Civic Hatchback Sport Touring"
        openSettings(in: app)

        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app, maxSwipes: 20))
        add.tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        enter(name, into: nameField, in: app)

        // At this size the wrapped name pushes the economy field under the
        // keyboard, where a synthesized tap does not focus it. Saving without
        // an economy is refused, and the refusal focuses that field and scrolls
        // it into view itself.
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(validationMessage("vehicleValidationMessage", in: app).waitForExistence(timeout: 5))
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: economyField
        )
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed)
        enter("34", into: economyField, in: app)
        app.buttons["saveVehicleButton"].tap()
        assertVehicleSheetClosed(in: app)

        let summary = app.descendants(matching: .any)["defaultVehicleSummary"]
        XCTAssertTrue(scrollToTop(reaching: summary, in: app), "The default card is at the top")
        XCTAssertTrue(summary.label.contains(name), "The name is whole: \(summary.label)")
        XCTAssertGreaterThan(onPixelGrid(summary.frame.height), 44)
        attachScreenshot("settings-xxxl")
        XCTAssertTrue(scrollTo(vehicleRow(containing: name, in: app), in: app, maxSwipes: 20), "And in the list below it")
        goBack(in: app)

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(next.value as? String, "\(name), 34 miles per gallon", "The whole name is kept")
        XCTAssertLessThanOrEqual(next.frame.maxX, app.windows.firstMatch.frame.maxX, "The row wraps rather than running off")
        XCTAssertGreaterThan(next.frame.height, 60, "A name this long at this size takes more than one line")
        XCTAssertTrue(scrollUntilHittable(app.buttons["startShiftButton"], in: app))
    }

    /// Settings, from the gear to its foot: reachable and named, an empty
    /// state rather than an empty screen, a default stated in words or stated
    /// as missing, a gas price recorded, corrected, removed and recorded as
    /// zero, each distinct, and the acknowledgements naming the license and the
    /// system typeface.
    ///
    /// Was four journeys, each opening an empty Settings.
    @MainActor
    func testSettingsStatesItsDefaultsAndRecordsTheGasPrice() throws {
        let app = launchWithEmptyStore()

        let gear = app.buttons["settingsLink"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "A gear should be on the main screen")
        XCTAssertEqual(gear.label, "Settings", "A glyph alone says nothing to a listener")
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5),
            "A driver who has entered nothing is told so rather than shown an empty screen"
        )
        let none = app.descendants(matching: .any)["noDefaultVehicleNotice"]
        XCTAssertTrue(none.waitForExistence(timeout: 5), "No selection is stated rather than left empty")
        XCTAssertTrue(none.label.contains("No vehicle selected") && none.label.contains("next shift"), none.label)
        attachScreenshot("settings-no-vehicle")

        let price = app.descendants(matching: .any)["currentGasPriceRow"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(price, toContain: "Current gas price"), "Showed: \(price.label)")
        XCTAssertEqual(price.value as? String, "Not set", "Nothing recorded is stated as nothing recorded")
        price.tap()
        let field = app.textFields["currentGasPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        enter("3.19", into: field, in: app)
        app.buttons["saveCurrentGasPriceButton"].tap()
        XCTAssertTrue(waitForLabelValue(price, toEqual: "$3.19 per gallon"), "The price says its unit to a listener")
        price.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "3.19", "The editor opens on the stored figure")
        replaceTappedField(field, with: "3.35", in: app)
        app.buttons["saveCurrentGasPriceButton"].tap()
        XCTAssertTrue(waitForLabelValue(price, toEqual: "$3.35 per gallon"))
        price.tap()
        let remove = app.buttons["removeCurrentGasPriceButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(waitForLabelValue(price, toEqual: "Not set"), "Removed is not a price of nothing")

        addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
        let summary = app.descendants(matching: .any)["defaultVehicleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The first vehicle becomes the default")
        XCTAssertEqual(summary.label, "Default vehicle: 2020 Honda Civic, 34 miles per gallon. Used for your next shift.")
        XCTAssertFalse(none.exists)
        let row = vehicleRow(containing: "2020 Honda Civic", in: app)
        XCTAssertTrue(row.label.hasPrefix("Selected as the default vehicle."), "Showed: \(row.label)")
        setCurrentGasPrice("0", in: app)
        XCTAssertEqual(price.value as? String, "$0.00 per gallon", "A recorded zero is not Not set")
        attachScreenshot("settings-default-vehicle")
        row.tap()
        XCTAssertTrue(none.waitForExistence(timeout: 5), "Tapping the default again clears it")
        XCTAssertFalse(summary.exists)

        let link = app.buttons["acknowledgementsLink"]
        XCTAssertTrue(scrollUntilHittable(link, in: app), "About is at the foot of Settings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertTrue(elements(containing: "MIT License", in: app).firstMatch.waitForExistence(timeout: 5))
        let typeface = app.descendants(matching: .any)["typefaceAcknowledgement"]
        XCTAssertTrue(scrollTo(typeface, in: app))
        XCTAssertTrue(typeface.label.contains("bundles no font"), "Showed: \(typeface.label)")
    }

    /// The vehicle editor labels each field, refuses a vehicle with no economy
    /// and one with an economy of zero in one sentence each, carried by one
    /// element, and writes nothing it refused.
    ///
    /// Was two journeys over the same sheet. The rules are `VehicleSettingsTests`.
    @MainActor
    func testTheVehicleEditorLabelsItsFieldsAndRefusesWhatItCannotDivideBy() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let add = app.buttons["addVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        add.tap()
        let nameField = app.textFields["vehicleNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.label, "Vehicle name")
        let economyField = app.textFields["vehicleMilesPerGallonField"]
        XCTAssertEqual(economyField.label, "Miles per gallon")
        attachScreenshot("vehicle-editor")

        enter("The van", into: nameField, in: app)
        app.buttons["saveVehicleButton"].tap()
        let message = validationMessage("vehicleValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "A vehicle with no economy is refused")
        XCTAssertTrue(message.label.contains("miles per gallon"), "The sentence, not a glyph: \(message.label)")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "vehicleValidationMessage").count, 1,
            "One element carries the refusal, so no query can find a glyph called Warning instead"
        )
        attachScreenshot("vehicle-editor-validation")

        enter("0", into: economyField, in: app)
        app.buttons["saveVehicleButton"].tap()
        XCTAssertTrue(
            waitForLabel(message, toContain: "more than zero"),
            "Zero is refused because it is what the recorded miles are divided by: \(message.label)"
        )
        app.buttons["cancelVehicleButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5),
            "Nothing refused was written"
        )
    }

    /// The snapshot every default rests on, end to end: an older shift is
    /// filled from the current defaults only when the driver asks and saves; a
    /// shift started afterwards records the vehicle, economy, price and hourly
    /// target with no typing and is compared with that target; and changing
    /// every setting, deleting the vehicle and moving the target leaves it
    /// exactly as it was recorded.
    ///
    /// Two launches: the older shift is the seeded history's, and the new one
    /// is worked on an empty store, where it is the only row to open (the
    /// seeded history holds a shift dated after today, which sorts above it).
    ///
    /// Was four journeys. The snapshot and comparison rules are
    /// `FuelAssumptionPersistenceTests` and `HourlyTargetTests`.
    @MainActor
    func testDefaultsAreRecordedAtStartAndNeverReachARecordedShift() throws {
        var app = launchWithSeededHistory()

        func setTarget(_ amount: String) {
            let row = app.descendants(matching: .any)["hourlyTargetRow"]
            XCTAssertTrue(scrollUntilHittable(row, in: app))
            row.tap()
            let field = app.textFields["hourlyTargetField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            clear(field, in: app)
            enter(amount, into: field, in: app)
            app.buttons["saveHourlyTargetButton"].tap()
            XCTAssertTrue(waitForDisappearance(of: field))
            XCTAssertTrue(waitForLabelValue(row, toEqual: "$\(amount) per working hour"), "Showed: \(String(describing: row.value))")
        }
        func setDefaults() {
            openSettings(in: app)
            addVehicle(named: "2020 Honda Civic", milesPerGallon: "34", in: app)
            setCurrentGasPrice("3.19", in: app)
            setTarget("25.00")
            goBack(in: app)
        }

        setDefaults()

        // 1. An older shift, worked before the defaults existed.
        openFirstShift(in: app)
        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(cost.label.contains("Add your vehicle's miles per gallon"), "Not filled in: \(cost.label)")
        let editor = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(editor, in: app))
        editor.tap()
        let defaults = app.buttons["useCurrentDefaultsButton"]
        XCTAssertTrue(scrollUntilHittable(defaults, in: app), "An older shift is offered the current defaults")
        defaults.tap()
        XCTAssertEqual(app.textFields["fuelMilesPerGallonField"].value as? String, "34", "The fields are filled")
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.19")
        app.buttons["cancelFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "Add your vehicle's miles per gallon"), "Filling a field is not recording it")
        XCTAssertTrue(scrollUntilHittable(editor, in: app))
        editor.tap()
        XCTAssertTrue(scrollUntilHittable(defaults, in: app))
        defaults.tap()
        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "estimated fuel cost, based on recorded mileage"), "Showed: \(cost.label)")
        goBack(in: app)

        // 2. A shift started now records every default with no typing.
        app.terminate()
        app = launchWithEmptyStore()
        setDefaults()
        completeAShift(in: app)
        openFirstShift(in: app)
        app.buttons["editShiftEarningsButton"].tap()
        type("80.00", into: app)
        app.buttons["saveEarningsButton"].tap()
        let economy = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        let target = app.descendants(matching: .any)["shiftDetailHourlyTarget"]
        func assertRecorded(_ why: String) {
            XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["shiftDetailDuration"], in: app))
            XCTAssertTrue(scrollTo(target, in: app))
            XCTAssertTrue(waitForLabel(target, toContain: "Above target"), "\(why): \(target.label)")
            XCTAssertTrue(target.label.contains("target of $25.00 a working hour"), "\(why): \(target.label)")
            XCTAssertTrue(scrollTo(economy, in: app))
            XCTAssertTrue(waitForLabel(economy, toContain: "34 miles per gallon assumed"), "\(why): \(economy.label)")
            XCTAssertTrue(scrollTo(price, in: app))
            XCTAssertTrue(waitForLabel(price, toContain: "$3.19 per gallon assumed"), "\(why): \(price.label)")
            XCTAssertTrue(scrollTo(vehicle, in: app))
            XCTAssertTrue(waitForLabel(vehicle, toContain: "2020 Honda Civic"), "\(why): \(vehicle.label)")
        }
        assertRecorded("Recorded at the start")
        goBack(in: app)

        // 3. Change everything, delete the vehicle, move the target.
        openSettings(in: app)
        let edit = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        replaceTappedField(app.textFields["vehicleMilesPerGallonField"], with: "12", in: app)
        app.buttons["saveVehicleButton"].tap()
        assertVehicleSheetClosed(in: app)
        setCurrentGasPrice("9.99", in: app)
        setTarget("30.00")
        let editAgain = app.buttons["Edit 2020 Honda Civic"]
        XCTAssertTrue(scrollToTop(reaching: editAgain, in: app))
        XCTAssertTrue(scrollUntilHittable(editAgain, in: app))
        editAgain.tap()
        let delete = app.buttons["deleteVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        delete.tap()
        // `.firstMatch`: a confirmation dialog's button renders as an element
        // containing its own text, and both carry the identifier.
        app.buttons.matching(identifier: "confirmDeleteVehicleButton").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["vehiclesEmptyState"].waitForExistence(timeout: 5))
        goBack(in: app)

        openFirstShift(in: app)
        assertRecorded("Unmoved by Settings, and intelligible with no profile behind it")
    }

    /// One day's summary, read top to bottom: every figure states the coverage
    /// behind it, and none claims more than its records.
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
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
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
    }

    /// The week counts the shift the day does not, totals its recorded amounts
    /// with their coverage and states its pickup wait as a median of individual
    /// pickups; the week before it, which nobody drove, shows a sentence
    /// rather than a grid of zeroes.
    ///
    /// Was three journeys over this fixture.
    @MainActor
    func testTheWeekSummaryStatesItsEarningsAndPickupWaitWithTheirBasis() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)

        let shiftCount = app.descendants(matching: .any)["periodShiftCount"]
        XCTAssertTrue(scrollTo(shiftCount, in: app))
        XCTAssertTrue(waitForLabel(shiftCount, toContain: "2 completed shifts"), "Today: \(shiftCount.label)")
        let picker = app.segmentedControls["periodUnitPicker"]
        XCTAssertTrue(scrollToTop(reaching: picker, in: app))
        selectPeriod("Week", in: app)
        XCTAssertTrue(scrollTo(shiftCount, in: app))
        XCTAssertTrue(waitForLabel(shiftCount, toContain: "3 completed shifts"), "The week holds the third: \(shiftCount.label)")

        let earnings = app.descendants(matching: .any)["periodEarnings"]
        XCTAssertTrue(scrollToTop(reaching: earnings, in: app))
        XCTAssertTrue(waitForLabel(earnings, toContain: "$206.25"), "Showed: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("2 of 3 completed shifts"), "Showed: \(earnings.label)")

        let wait = app.descendants(matching: .any)["periodPickupWait"]
        XCTAssertTrue(scrollTo(wait, in: app))
        XCTAssertTrue(waitForLabel(wait, toContain: "Median recorded pickup wait"), "Showed: \(wait.label)")
        XCTAssertTrue(wait.label.contains("5 recorded pickups"), "Showed: \(wait.label)")
        XCTAssertFalse(wait.label.lowercased().contains("typical"), "Showed: \(wait.label)")

        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(scrollToTop(reaching: previous, in: app, swipes: 12))
        previous.tap()
        let empty = app.descendants(matching: .any)["periodEmptyState"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "No completed shifts recorded this week.")
        XCTAssertFalse(earnings.exists, "An empty week shows no earnings figure at all, not $0.00")
        XCTAssertFalse(app.descendants(matching: .any)["periodMileage"].exists)
    }

    /// A day read beside the day before it. Today is unfinished and partly
    /// recorded, so both figures and coverages are printed and a difference is
    /// stated but no percentage, and the screen says why; the finished day
    /// before it, completely recorded, states the percentage; and the day
    /// before that, which holds nothing, is said to hold nothing, with its
    /// earnings missing rather than zero and its counts still compared.
    ///
    /// Was three journeys over this fixture. The rules are
    /// `PeriodComparisonTests`, including that no estimate is compared.
    @MainActor
    func testADayIsComparedWithTheDayBeforeIt() throws {
        let app = launchWithPeriodComparison()
        openPeriodSummary(in: app)

        let earnings = comparisonRow("recordedGrossEarnings", in: app)
        XCTAssertTrue(scrollTo(earnings, in: app), "The comparison is on the summary")
        XCTAssertTrue(earnings.label.contains("$100.00") && earnings.label.contains("$80.00"), "Both figures: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("more recorded"), "More or less recorded, never better or worse: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("1 of 2 shifts") && earnings.label.contains("1 of 1 shift"), earnings.label)
        XCTAssertFalse(earnings.label.contains("%"), "No percentage against a day that has not finished: \(earnings.label)")
        let notes = app.descendants(matching: .any)["periodComparisonNotes"]
        XCTAssertTrue(scrollTo(notes, in: app))
        XCTAssertTrue(notes.label.contains("still in progress"), "And the screen says why: \(notes.label)")

        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(scrollToTop(reaching: previous, in: app, swipes: 12))
        previous.tap()
        XCTAssertTrue(scrollTo(earnings, in: app))
        XCTAssertTrue(waitForLabel(earnings, toContain: "$64.00"), "Yesterday beside the day before it: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("$16.00 more recorded"), "Showed: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("25%"), "Both days complete and finished: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("1 of 1 shift, compared with 1 of 1 shift"), "Showed: \(earnings.label)")

        XCTAssertTrue(scrollToTop(reaching: previous, in: app, swipes: 12))
        previous.tap()
        let before = app.descendants(matching: .any)["periodComparisonPrevious"]
        XCTAssertTrue(scrollTo(before, in: app))
        XCTAssertTrue(
            waitForLabel(before, toContain: "No completed shift and no recorded expense"),
            "The day before this one holds nothing, and the screen says so: \(before.label)"
        )
        XCTAssertTrue(scrollTo(earnings, in: app))
        XCTAssertTrue(earnings.label.contains("Not recorded"), "Showed: \(earnings.label)")
        XCTAssertFalse(earnings.label.contains("$0.00"), "Never a day that earned nothing: \(earnings.label)")
        let shifts = comparisonRow("completedShifts", in: app)
        XCTAssertTrue(scrollTo(shifts, in: app))
        XCTAssertTrue(shifts.label.contains("1 more recorded"), "Counts are still compared: \(shifts.label)")
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
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "A future month holds no records and is not offered")
        previous.tap()
        XCTAssertTrue(next.isEnabled, "Once in the past, the way back to now is open")
        let chosen = periodTitle(in: app)

        // Re-reading the clock on return moves the naming only.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["periodTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(periodTitle(in: app), chosen, "The month the driver stepped to is still selected")
        XCTAssertTrue(next.isEnabled)

        // Two steps back, so the month is empty whichever day the test runs on.
        previous.tap()
        let empty = app.descendants(matching: .any)["periodEmptyState"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "An earlier month holds nothing")
        XCTAssertTrue(empty.label.contains("month"), "The empty state names its period: \(empty.label)")
        XCTAssertNotEqual(periodTitle(in: app), current)
        XCTAssertFalse(app.buttons["exportPeriodButton"].exists, "An empty month offers no export")
    }

    /// A custom range has no chevrons; cancelling its picker changes nothing;
    /// applying it summarises the dates it covers; and the range comes back as
    /// it was left after a trip through the other lengths.
    ///
    /// Was three journeys over this fixture.
    @MainActor
    func testACustomRangeIsChosenCancelledAndKept() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        selectPeriod("Custom", in: app)

        XCTAssertFalse(app.buttons["periodPreviousButton"].exists, "A chosen range is not stepped")
        XCTAssertFalse(app.buttons["periodNextButton"].exists)
        let before = periodTitle(in: app)
        let count = shiftCount(in: app)

        let choose = app.buttons["periodCustomRangeButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "A range is chosen, not stepped to")
        choose.tap()
        XCTAssertTrue(app.buttons["customRangeCancelButton"].waitForExistence(timeout: 5))
        app.buttons["customRangeCancelButton"].tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "Back on the summary")
        XCTAssertEqual(periodTitle(in: app), before, "Cancel is not a quiet Apply")
        XCTAssertEqual(shiftCount(in: app), count)

        choose.tap()
        let summary = app.descendants(matching: .any)["customRangeSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The sheet says what the dates select")
        XCTAssertTrue(summary.label.contains("Custom reporting range"), "Showed: \(summary.label)")
        app.buttons["customRangeApplyButton"].tap()
        XCTAssertNotNil(shiftCount(in: app), "The applied range holds the fixture's recent shifts")
        let chosen = periodTitle(in: app)
        XCTAssertTrue(chosen.contains("selected day"), "The range says how many days it covers: \(chosen)")

        selectPeriod("Week", in: app)
        selectPeriod("Month", in: app)
        selectPeriod("Custom", in: app)
        XCTAssertEqual(periodTitle(in: app), chosen, "The range came back as it was left")
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
        XCTAssertTrue(app.buttons["shareExportButton"].waitForExistence(timeout: 5), "Offered to the share sheet")
        XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists, "Nothing failed")

        selectExportFormat("CSV", in: app)
        let fileName = app.descendants(matching: .any)["exportFileName"]
        XCTAssertTrue(waitForLabel(fileName, toContain: ".csv"), "The CSV file replaces the JSON one: \(fileName.label)")
        XCTAssertTrue(app.buttons["shareExportButton"].exists)
    }

    /// Each period exports its own records, named for it: a day, a week, a
    /// month and a chosen range; and a period with nothing in it offers no
    /// export it would have to refuse.
    ///
    /// Was five journeys over this fixture. Which records each scope selects
    /// is `MonthAndRangeExportTests`.
    @MainActor
    func testEachPeriodExportsItsOwnRecords() throws {
        let app = launchWithPeriodSummary()
        openPeriodSummary(in: app)
        let picker = app.segmentedControls["periodUnitPicker"]

        func export(_ unit: String) -> String {
            // The export control is at the foot of the list, so dismissing leaves
            // the screen scrolled past the picker at its top.
            XCTAssertTrue(scrollToTop(reaching: picker, in: app, swipes: 12), "The summary is back")
            selectPeriod(unit, in: app)
            openExport("exportPeriodButton", in: app)
            let name = exportFileName(in: app)
            XCTAssertTrue(app.buttons["shareExportButton"].exists, "Offered to the share sheet: \(name)")
            XCTAssertFalse(app.descendants(matching: .any)["exportFailureMessage"].exists)
            app.buttons["dismissExportButton"].tap()
            return name
        }

        let day = export("Day")
        XCTAssertTrue(day.contains("DashPilot-Day-") && day.contains("2 shifts"), "Today holds two of the three: \(day)")
        let week = export("Week")
        XCTAssertTrue(week.contains("DashPilot-Week-") && week.contains("3 shifts"), "The week holds all three: \(week)")
        let month = export("Month")
        XCTAssertTrue(month.contains("DashPilot-Month-"), "The file names the month it covers: \(month)")
        let range = export("Custom")
        XCTAssertTrue(range.contains("DashPilot-Range-") && range.contains("-to-"), "Both selected days: \(range)")

        XCTAssertTrue(scrollToTop(reaching: picker, in: app, swipes: 12))
        selectPeriod("Day", in: app)
        let previous = app.buttons["periodPreviousButton"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        for _ in 0..<10 { previous.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["periodEmptyState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exportPeriodButton"].exists, "An empty period offers no export it would refuse")
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
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        enter("-5", into: field, in: app)
        app.buttons["saveExpenseButton"].tap()
        let message = validationMessage("expenseValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The refusal is explained rather than silent")
        XCTAssertTrue(message.label.lowercased().contains("negative"), "It names the rule: \(message.label)")
        app.buttons["cancelExpenseButton"].tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "Nothing refused was written")

        recordExpense("42.10", in: app)
        let row = app.descendants(matching: .any).matching(identifier: "expenseRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(row, toContain: "$42.10"), "The amount entered: \(row.label)")
        XCTAssertTrue(row.label.contains("Fuel"), "And its category: \(row.label)")
        XCTAssertFalse(empty.exists)

        row.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "42.1", "The editor opens on what was recorded")
        clear(field, in: app)
        enter("50.00", into: field, in: app)
        app.buttons["saveExpenseButton"].tap()
        XCTAssertTrue(app.buttons["saveExpenseButton"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(row, toContain: "$50.00"), "The correction is what the list shows")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPeriodSummary(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["periodEmptyState"].waitForExistence(timeout: 5),
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
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let delete = app.buttons["deleteExpenseButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
    }

    /// The shift panel from an empty install to a shift with a delivery, read in
    /// the order it is drawn, and a shift with no vehicle borrowing none.
    ///
    /// Before a shift: nothing selected is said as that and blocks nothing, the
    /// history says where shifts will appear, and the permission panel is on
    /// screen. Running: state, then the working clock, then the figures, then
    /// the vehicle, with no earnings figure invented. A vehicle added in
    /// Settings mid-shift is the next shift's, until the driver corrects this
    /// one explicitly. The delivery count follows what is recorded.
    ///
    /// Eight journeys each launched an empty store for one of these; the rules
    /// behind them are `NextShiftVehicleContextTests`, `ShiftVehicleContextTests`
    /// and `RunningShiftFuelCorrectionTests`.
    @MainActor
    func testTheShiftPanelReadsInOrderAndBorrowsNothing() throws {
        let app = launchWithEmptyStore()

        let next = app.descendants(matching: .any)["nextShiftVehicle"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabelValue(next, toEqual: "No vehicle selected for the next shift"))
        XCTAssertFalse(next.label.contains("0 MPG") || next.label.contains("$0.00"))
        XCTAssertTrue(
            app.descendants(matching: .any)["locationAuthorizationStatus"].exists,
            "The permission panel is on screen from launch"
        )
        let emptyHistory = app.descendants(matching: .any)["emptyHistoryNotice"]
        XCTAssertTrue(scrollUntilHittable(emptyHistory, in: app, maxSwipes: 8), "The empty history states itself")
        XCTAssertTrue(emptyHistory.label.contains("No completed shifts yet"), "Showed: \(emptyHistory.label)")
        XCTAssertFalse(
            app.descendants(matching: .any)["currentWeekSummary"].exists,
            "No summary is drawn over no shifts"
        )

        let start = app.buttons["startShiftButton"]
        XCTAssertTrue(scrollToTop(reaching: start, in: app))
        XCTAssertTrue(start.isEnabled, "Nothing selected blocks nothing")
        start.tap()

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
        XCTAssertEqual(counts.value as? String, "No delivery in progress")
        XCTAssertFalse(
            app.descendants(matching: .any)["liveRecordedGross"].exists,
            "No earnings figure is invented for a shift that cannot record one yet"
        )
        attachScreenshot("home-active-no-deliveries")

        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertEqual(vehicle.value as? String, "No vehicle recorded for this shift", "And invented no vehicle")

        // A vehicle entered after the shift began belongs to the next shift.
        openSettings(in: app)
        addVehicle(named: "The van", milesPerGallon: "18", in: app)
        goBack(in: app)
        let stillEmpty = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(stillEmpty, in: app))
        XCTAssertEqual(
            stillEmpty.value as? String,
            "No vehicle recorded for this shift",
            "Borrowing the current selection would claim a vehicle this shift never recorded"
        )

        // Unless the driver fills it, which a shift with nothing measured allows.
        let change = app.buttons["changeShiftVehicleButton"]
        XCTAssertTrue(scrollUntilHittable(change, in: app))
        change.tap()
        let van = app.descendants(matching: .any)
            .matching(identifier: "correctionVehicleRow")
            .containing(NSPredicate(format: "label CONTAINS %@", "The van"))
            .firstMatch
        XCTAssertTrue(van.waitForExistence(timeout: 5))
        van.tap()
        XCTAssertTrue(waitForLabel(van, toContain: "Chosen"), "The choice is said: \(van.label)")
        let save = app.buttons["saveShiftVehicleButton"]
        XCTAssertTrue(waitForEnabled(save, true))
        save.tap()
        let filled = app.descendants(matching: .any)["activeShiftVehicle"]
        XCTAssertTrue(scrollTo(filled, in: app))
        XCTAssertTrue(
            waitForLabelValue(filled, toEqual: "The van, 18 miles per gallon"),
            "Showed: \(String(describing: filled.value))"
        )

        // The counts follow what the driver records.
        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(startDelivery.waitForExistence(timeout: 5))
        startDelivery.tap()
        XCTAssertTrue(scrollToTop(reaching: counts, in: app))
        XCTAssertTrue(waitForLabelValue(counts, toEqual: "1 delivery in progress"))
        attachScreenshot("home-one-delivery")
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
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertFalse(app.buttons["resumeShiftButton"].exists)
        let entry = app.buttons["startDeliveryButton"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))

        pressPark(in: app)
        let parked = app.descendants(matching: .any)["parkedShiftNotice"]
        XCTAssertTrue(parked.waitForExistence(timeout: 5))
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
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["pausedShiftStatus"].waitForExistence(timeout: 5),
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
        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Resumed: the entry is back")

        let end = app.buttons["endShiftButton"]
        XCTAssertTrue(reachShiftControl(end, in: app))
        end.tap()
        XCTAssertTrue(startShift.waitForExistence(timeout: 5))
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
        XCTAssertTrue(working.waitForExistence(timeout: 10))
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
            app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 10),
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
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 10))
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
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 10))
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

    /// With location granted and no positions, the running shift says what
    /// recording promises and what it does not, says there is no route rather
    /// than zero miles, keeps saying it is recording across leaving the app,
    /// and Park stops recording in two places while the shift keeps running
    /// and Resume Driving starts it again.
    ///
    /// Was six journeys over the stubbed provider.
    @MainActor
    func testRecordingParkingAndResumingSayWhatTheyDo() throws {
        let app = launchWithStubbedLocation()

        let panel = app.descendants(matching: .any)["locationAuthorizationPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollTo(panel, in: app))
        let scope = panel.descendants(matching: .staticText).allElementsBoundByIndex
            .map(\.label).joined(separator: " ").lowercased()
        XCTAssertTrue(scope.contains("another app") || scope.contains("screen is locked"), "Showed: \(scope)")
        XCTAssertTrue(scope.contains("started with dashpilot open"), "The scope's limit is stated: \(scope)")

        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(scrollToTop(reaching: startShift, in: app))
        startShift.tap()

        let mileage = app.descendants(matching: .any)["liveRecordedMileage"]
        XCTAssertTrue(mileage.waitForExistence(timeout: 10))
        let spoken = try XCTUnwrap(mileage.value as? String)
        XCTAssertTrue(spoken.contains("No route recorded"), "Expected an absent route, read: \(spoken)")
        XCTAssertFalse(spoken.contains("0.0"), "An absent route is not a distance of zero: \(spoken)")
        XCTAssertNil(recordedMiles(in: app))

        let status = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(status, toContain: "Location tracking active"), "Showed: \(status.label)")
        let line = status.label.lowercased()
        XCTAssertTrue(line.contains("other apps") && line.contains("locked"), "It carries on off screen: \(line)")
        XCTAssertTrue(line.contains("ios can still stop it"), "And is not guaranteed: \(line)")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 10))
        let returned = app.descendants(matching: .any)["routeCaptureStatus"]
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        XCTAssertTrue(returned.label.contains("Location tracking active"), "Showed: \(returned.label)")
        XCTAssertFalse(returned.label.contains("Route recording paused"), "No break was claimed: \(returned.label)")

        let park = app.buttons["parkShiftButton"]
        XCTAssertTrue(reachShiftControl(park, in: app), "Parking is offered on a running shift")
        XCTAssertTrue(park.label.contains("shift keeps running"), "It says what it does not do: \(park.label)")
        park.tap()
        XCTAssertTrue(waitForLabel(returned, toContain: "Route recording stopped while parked"), "Showed: \(returned.label)")
        XCTAssertTrue(returned.label.contains("is not counted"), "Showed: \(returned.label)")
        XCTAssertFalse(returned.label.contains("still running"), "The notice says that, not the capture line")
        let notice = app.descendants(matching: .any)["parkedShiftNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("shift is still running"), "Showed: \(notice.label)")
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].exists, "Still running")
        XCTAssertFalse(app.descendants(matching: .any)["pausedShiftStatus"].exists, "No pause was recorded")
        XCTAssertTrue(app.descendants(matching: .any)["workingTime"].exists, "Working time is still counting")

        let resume = app.buttons["resumeDrivingButton"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Leaving the state is one tap")
        XCTAssertFalse(park.exists, "Parking is not offered while already parked")
        resume.tap()
        XCTAssertTrue(waitForLabel(returned, toContain: "Location tracking active"), "Recording starts again")
        XCTAssertFalse(app.descendants(matching: .any)["parkedShiftNotice"].exists, "And the notice goes with it")
        XCTAssertTrue(app.buttons["parkShiftButton"].exists, "Parking is offered again")
    }

    // MARK: Active delivery cards

    /// The card of one delivery in progress, found by the name it leads with.
    @MainActor
    private func deliveryCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "activeDeliveryStatus", title)
        ).firstMatch
    }

    // MARK: Live shift figures

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
        XCTAssertTrue(header.waitForExistence(timeout: 5))
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
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(threeWeeksAgo.waitForExistence(timeout: 5), "Two shifts are added up rather than listed")
        XCTAssertTrue(threeWeeksAgo.label.contains("2 completed shifts"), "Showed: \(threeWeeksAgo.label)")
        XCTAssertFalse(threeWeeksAgo.label.contains("$41.00"), "The week states its total, not its parts")
        XCTAssertEqual(elements(containing: "$70.00", in: app).count, 0, "This week is not on this screen")

        let row = rows.matching(NSPredicate(format: "label CONTAINS %@", "$41.00")).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        row.tap()
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5), "The same detail screen opens")
        XCTAssertTrue(earnings.label.contains("$41.00"), "With the tapped shift's own amount: \(earnings.label)")
    }

    /// A week's summary names its week first, then its figures in the order a
    /// listener needs them; a week whose fuel is estimated for some shifts says
    /// which, keeps the estimated net apart from recorded fuel, and a week
    /// estimated in full says so.
    ///
    /// Was three journeys over the long history.
    @MainActor
    func testOlderWeekSummariesStateTheirFuelCoverageInOrder() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let header = app.descendants(matching: .any).matching(identifier: "olderWeekHeader").firstMatch
        let lastWeek = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "3 completed shifts"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(lastWeek.label.hasPrefix(header.label), "The summary names its own week first")
        let order = ["3 completed shifts", "Recorded gross earnings", "working time", "Recorded mileage"]
            .compactMap { lastWeek.label.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 4, "Every figure is spoken: \(lastWeek.label)")
        XCTAssertEqual(order, order.sorted(), "In the order a listener needs them")
        XCTAssertTrue(lastWeek.label.contains("Recorded gross earnings, $185.00"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(
            lastWeek.label.contains("Estimated fuel") && lastWeek.label.contains("across 2 of 3 completed shifts"),
            "The estimate says it covers two of the three shifts: \(lastWeek.label)"
        )
        XCTAssertTrue(lastWeek.label.contains("recorded miles"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(
            lastWeek.label.contains("Estimated net after fuel") && lastWeek.label.contains("never added together"),
            "Showed: \(lastWeek.label)"
        )
        XCTAssertFalse(lastWeek.label.contains("Net after recorded expenses"), "Only one net is on the card")
        attachScreenshot("older-week-partial-fuel")

        let complete = app.descendants(matching: .any).matching(identifier: "olderWeekSummary")
            .matching(NSPredicate(format: "label CONTAINS %@", "$50.03")).firstMatch
        XCTAssertTrue(scrollUntilHittable(complete, in: app, maxSwipes: 16), "Three weeks ago is reachable")
        XCTAssertTrue(
            complete.label.contains("Estimated fuel") && complete.label.contains("across every completed shift"),
            "Complete coverage is stated: \(complete.label)"
        )
        attachScreenshot("older-week-full-fuel")
    }

    /// A finished shift says which vehicle and assumptions it recorded,
    /// including a price recorded as zero, and today's Settings reach neither a
    /// shift that recorded a vehicle nor one that recorded none.
    ///
    /// Was three journeys over the long history.
    @MainActor
    func testAHistoricalShiftKeepsTheVehicleItRecorded() throws {
        let app = launchWithLongHistory()

        openSettings(in: app)
        addVehicle(named: "Synthetic Van", milesPerGallon: "9", in: app)
        setCurrentGasPrice("5.55", in: app)
        goBack(in: app)

        // This week's first shift recorded no vehicle, and borrows none.
        openFirstShift(in: app)
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(vehicle, in: app))
        XCTAssertTrue(waitForLabel(vehicle, toContain: "No vehicle recorded for this shift"), "Showed: \(vehicle.label)")
        XCTAssertFalse(vehicle.label.contains("9 miles per gallon"), "Nothing is borrowed from Settings")
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"].exists, "No economy is invented")
        goBack(in: app)

        // Last week's Friday recorded the van at a gas price of zero.
        openLastWeeksFridayShift(in: app)
        let recorded = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollTo(recorded, in: app))
        XCTAssertTrue(
            waitForLabel(recorded, toContain: "Vehicle recorded with this shift: Synthetic Van"),
            "Showed: \(recorded.label)"
        )
        XCTAssertTrue(recorded.label.contains("20 miles per gallon"), "Showed: \(recorded.label)")
        XCTAssertTrue(recorded.label.contains("gas $0.00 per gallon"), "A recorded zero is said: \(recorded.label)")
        XCTAssertFalse(recorded.label.contains("9 miles per gallon"), "Showed: \(recorded.label)")
        XCTAssertFalse(recorded.label.contains("$5.55"), "Showed: \(recorded.label)")
        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "$0.00 per gallon assumed"), "Showed: \(price.label)")
    }

    /// History at the largest accessibility size: the current week's figures,
    /// an older week's fuller card and a historical shift's vehicle row stack
    /// whole, a shift several weeks down is reachable and opens, and returning
    /// keeps the place in the list.
    ///
    /// Was five journeys, each launching at AX5 and scrolling to one card.
    @MainActor
    func testHistoryAtTheLargestTextSize() throws {
        let app = launchWithLongHistory(textSize: Self.accessibilityXXXLTextSize)

        let current = currentWeekSummary(in: app)
        XCTAssertTrue(scrollUntilHittable(current, in: app, maxSwipes: 25), "The current week's summary is reachable")
        XCTAssertTrue(waitForLabel(current, toContain: "Recorded gross earnings"), "Showed: \(current.label)")
        XCTAssertGreaterThan(onPixelGrid(current.frame.height), 44, "A summary is never a tiny cell")
        attachScreenshot("history-xxxl")
        XCTAssertTrue(scrollUntilHittable(rows(in: app).firstMatch, in: app, maxSwipes: 25), "Its shifts are reachable")

        openOlderWeeks(in: app, maxSwipes: 25)
        let summary = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(summary, toContain: "$185.00"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("Estimated fuel"))
        XCTAssertGreaterThan(onPixelGrid(summary.frame.height), 44)

        openLastWeeksFridayRow(in: app, maxSwipes: 25)
        let vehicle = app.descendants(matching: .any)["shiftDetailFuelVehicle"]
        XCTAssertTrue(scrollUntilHittable(vehicle, in: app, maxSwipes: 40))
        XCTAssertTrue(waitForLabel(vehicle, toContain: "Synthetic Van"), "Showed: \(vehicle.label)")
        XCTAssertGreaterThanOrEqual(onPixelGrid(vehicle.frame.height), 44, "The row is not squeezed to fit")
        goBackToOlderWeeks(in: app)

        let target = olderWeekRows(in: app).matching(NSPredicate(format: "label CONTAINS %@", "$50.06")).firstMatch
        XCTAssertTrue(scrollUntilHittable(target, in: app, maxSwipes: 80), "A shift a few weeks down is reachable")
        target.tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(scrollTo(earnings, in: app, maxSwipes: 20), "The tapped shift's detail opens")
        XCTAssertTrue(earnings.label.contains("$50.06"), "Showed: \(earnings.label)")
        goBackToOlderWeeks(in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Returning keeps the place in the list")
    }

    /// Editing an older shift's amount, then deleting that shift, each update
    /// its week's summary on return, without leaving Older Weeks.
    ///
    /// Was two journeys over the long history.
    @MainActor
    func testEditingAndDeletingAnOlderShiftRefreshesItsWeek() throws {
        let app = launchWithLongHistory()
        openOlderWeeks(in: app)

        let lastWeek = app.descendants(matching: .any).matching(identifier: "olderWeekSummary").firstMatch
        XCTAssertTrue(waitForLabel(lastWeek, toContain: "Recorded gross earnings, $185.00"), "Showed: \(lastWeek.label)")
        XCTAssertTrue(lastWeek.label.contains("3 completed shifts"))

        openLastWeeksFridayRow(in: app)
        let edit = app.buttons["editShiftEarningsButton"]
        XCTAssertTrue(scrollTo(edit, in: app))
        edit.tap()
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        type("50", into: app)
        app.buttons["saveEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailEarnings"], toContain: "$50.00"))
        goBackToOlderWeeks(in: app)
        XCTAssertTrue(
            waitForLabel(lastWeek, toContain: "Recorded gross earnings, $190.00"),
            "The week is worked out again from what the store now says: \(lastWeek.label)"
        )
        attachScreenshot("older-weeks-after-edit")

        let friday = olderWeekRows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(friday, in: app))
        XCTAssertTrue(waitForLabel(friday, toContain: "$50.00"), "Showed: \(friday.label)")
        friday.tap()
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

    // MARK: The current week's own figures

    @MainActor
    private func currentWeekSummary(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "currentWeekSummary").firstMatch
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

    // MARK: A week follows an edit to its own shifts

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

    /// A completed shift's detail, read top to bottom: what it paid, then how
    /// long and how far with the partial route said beside the distance; its
    /// durations told apart in words with overlapping deliveries counted once;
    /// each rate naming what it divides by; a route with a gap called partial;
    /// a shift with no pause still offered one; and the corrections below
    /// every figure, with deletion last.
    ///
    /// The fixture's three deliveries run 5–30, 40–60 and 50–80 minutes into a
    /// three-hour shift, so the union is 65 minutes where their durations sum
    /// to 75; $86.25 over 65 minutes is $79.62. The arithmetic is pinned in
    /// `DeliveryActiveTimeTests` and `ShiftMetricsTests`; this reads that the
    /// screen states it. Was seven journeys opening this same shift.
    @MainActor
    func testTheRecordedShiftsDetailStatesItsTimesRatesAndRoute() throws {
        let app = launchWithSeededHistory()

        let summary = currentWeekSummary(in: app)
        XCTAssertTrue(scrollUntilHittable(summary, in: app, maxSwipes: 12))
        for expected in ["completed shifts", "Recorded gross earnings", "working time", "Recorded mileage"] {
            XCTAssertTrue(waitForLabel(summary, toContain: expected), "The week says \(expected): \(summary.label)")
        }
        app.swipeUp()
        attachScreenshot("history-current-week")

        let row = rows(in: app).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        XCTAssertTrue(row.label.contains("more miles were driven than were recorded"), "Showed: \(row.label)")
        openFirstShift(in: app)

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("Recorded gross earnings, $86.25"), "Showed: \(earnings.label)")
        let summaryWorking = app.descendants(matching: .any)["shiftDetailSummaryWorkingTime"]
        let summaryMileage = app.descendants(matching: .any)["shiftDetailSummaryMileage"]
        XCTAssertTrue(summaryWorking.waitForExistence(timeout: 5))
        XCTAssertTrue(summaryWorking.label.hasSuffix("working time"), "Showed: \(summaryWorking.label)")
        XCTAssertTrue(
            waitForLabel(summaryMileage, toContain: "more miles were driven than were recorded"),
            "The summary's figure carries the partial route: \(summaryMileage.label)"
        )
        XCTAssertLessThan(earnings.frame.minY, summaryWorking.frame.minY, "What the shift paid leads")
        attachScreenshot("detail-summary")

        let active = app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"]
        XCTAssertTrue(scrollTo(active, in: app))
        XCTAssertTrue(active.label.contains("delivery active time"), "Showed: \(active.label)")
        XCTAssertTrue(active.label.contains("1 hour") && active.label.contains("5 minutes"), "Showed: \(active.label)")
        XCTAssertFalse(active.label.contains("15 minutes"), "Summed durations would give 1 hour 15: \(active.label)")
        let nonDelivery = app.descendants(matching: .any)["shiftDetailNonDeliveryTime"]
        XCTAssertTrue(nonDelivery.exists)
        XCTAssertTrue(nonDelivery.label.contains("non-delivery time"), "Not called idle: \(nonDelivery.label)")
        XCTAssertTrue(nonDelivery.label.contains("55 minutes"), "Three hours less 65 minutes: \(nonDelivery.label)")
        XCTAssertTrue(app.descendants(matching: .any)["shiftDetailDuration"].label.contains("elapsed shift time"))

        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(hourly.label.contains("$28.75 gross earnings per shift hour"), "Showed: \(hourly.label)")
        let activeRate = app.descendants(matching: .any)["shiftDetailActiveHourlyRate"]
        XCTAssertTrue(scrollTo(activeRate, in: app))
        XCTAssertTrue(activeRate.label.contains("$79.62 gross earnings per delivery active hour"), "Showed: \(activeRate.label)")
        XCTAssertFalse(activeRate.label.contains("$69.00"))
        for overclaim in ["wage", "true hourly", "net", "working", "driving"] {
            XCTAssertFalse(activeRate.label.lowercased().contains(overclaim), "Not \(overclaim): \(activeRate.label)")
        }
        let perMile = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(perMile, in: app))
        XCTAssertTrue(perMile.label.contains("gross earnings per recorded mile"), "Showed: \(perMile.label)")
        XCTAssertFalse(perMile.label.contains("per mile driven"))

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("Partial route"), "Showed: \(mileage.label)")
        XCTAssertFalse(mileage.label.contains("Coverage"), "No coverage percentage: \(mileage.label)")
        let segments = app.descendants(matching: .any)["shiftDetailCaptureSegments"]
        XCTAssertTrue(scrollTo(segments, in: app))
        XCTAssertEqual(segments.label, "2 capture segments")
        XCTAssertTrue(app.descendants(matching: .any)["shiftDetailCaptureGaps"].label.contains("capture gap"))

        let noPauses = app.staticTexts["shiftDetailNoPauses"]
        XCTAssertTrue(scrollTo(noPauses, in: app, maxSwipes: 15), "The section says the shift recorded no pause")
        XCTAssertEqual(noPauses.label, "No pauses recorded")
        XCTAssertTrue(scrollTo(app.buttons["addMissedPauseButton"], in: app, maxSwipes: 3), "And still offers one")
        XCTAssertFalse(app.buttons["editShiftPauseButton"].exists, "There is nothing to edit")
        XCTAssertFalse(app.buttons["deleteShiftPauseButton"].exists, "and nothing to delete")

        let correctEnd = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correctEnd, in: app, maxSwipes: 15), "The corrections are below the figures")
        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollUntilHittable(delete, in: app, maxSwipes: 6))
        XCTAssertLessThan(correctEnd.frame.minY, delete.frame.minY, "Deletion stands apart, last")
    }

    /// A completed shift's delivery log: each delivery's recorded events with
    /// their times and its pickup place, a cancelled one keeping what happened
    /// and claiming nothing else, overlapping deliveries kept as separate rows;
    /// then grouping corrected from the finished shift, with the rows saying so
    /// and nothing they recorded moving.
    ///
    /// Was three journeys opening this same shift.
    @MainActor
    func testACompletedShiftsDeliveriesPlacesAndGrouping() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let summary = app.descendants(matching: .any)["shiftDetailDeliverySummary"]
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled")

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("Accepted at"), "Each event is spoken with its time: \(first.label)")
        XCTAssertTrue(first.label.contains("Waited at pickup"), "Showed: \(first.label)")
        XCTAssertTrue(first.label.contains("Accepted to delivered"))
        XCTAssertTrue(first.label.contains("Picked up from \(Self.noodles)"), "Showed: \(first.label)")
        XCTAssertFalse(first.label.contains("accepted together"), "No grouping is claimed yet: \(first.label)")

        let cancelled = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(cancelled, in: app), "A cancelled delivery is history, not an omission")
        XCTAssertTrue(cancelled.label.contains("Arrived at pickup at"), "Showed: \(cancelled.label)")
        XCTAssertFalse(cancelled.label.contains("Picked up at"), "Nothing it did not record: \(cancelled.label)")
        XCTAssertFalse(cancelled.label.contains("Waited at pickup"), "A wait with no end is not derived")
        XCTAssertFalse(cancelled.label.contains("Accepted to delivered"))
        XCTAssertTrue(cancelled.label.contains("Picked up from \(Self.diner)"), "Showed: \(cancelled.label)")

        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app), "Every recorded delivery is listed")
        XCTAssertTrue(third.label.contains("Picked up from \(Self.noodles)"), "Two deliveries share one place")
        XCTAssertTrue(app.buttons.matching(identifier: "shiftDetailPickupPlaceButton").firstMatch.exists)

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "History offers the same correction the running shift does")
        correct.tap()
        let combine = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "offerCorrectionMergeButton", "Combine Offer 2"))
            .firstMatch
        XCTAssertTrue(scrollTo(combine, in: app))
        combine.tap()
        let destination = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "offerCorrectionDestinationButton", "into Offer 1"))
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch.tap()
        app.buttons["closeOfferCorrectionButton"].tap()

        goBack(in: app)
        openFirstShift(in: app)
        XCTAssertTrue(scrollTo(summary, in: app))
        XCTAssertEqual(summary.label, "2 deliveries completed. 1 delivery cancelled", "Regrouping moved no count")
        let corrected = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(corrected, in: app))
        XCTAssertTrue(corrected.label.contains("Offer 1, accepted together with Delivery 2"), "Showed: \(corrected.label)")
        XCTAssertTrue(corrected.label.contains("Waited at pickup"), "The recorded wait is untouched")
        XCTAssertTrue(corrected.label.contains("Accepted to delivered"))
    }

    /// A finished shift's earnings refuse what cannot be read and change
    /// nothing; recorded on a shift with no measurable route, they give an
    /// hourly rate and say why there is no per-mile one.
    ///
    /// Was two journeys over this fixture.
    @MainActor
    func testShiftEarningsRefuseWhatCannotBeReadAndInventNoPerMileRate() throws {
        let app = launchWithFinishedDelivery()
        openFirstShift(in: app)

        app.buttons["editShiftEarningsButton"].tap()
        type("1.2.3", into: app)
        app.buttons["saveEarningsButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["earningsValidationMessage"].waitForExistence(timeout: 5),
            "The driver is told why it was refused"
        )
        XCTAssertTrue(app.textFields["earningsAmountField"].exists, "The editor keeps what was typed")
        app.buttons["cancelEarningsButton"].tap()
        XCTAssertTrue(app.buttons["editShiftEarningsButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["editShiftEarningsButton"].label, "Add Earnings", "A refused amount records nothing")
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailEarnings"].label, "No amount recorded")

        app.buttons["editShiftEarningsButton"].tap()
        type("86.25", into: app)
        app.buttons["saveEarningsButton"].tap()
        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(waitForLabel(hourly, toContain: "gross earnings per shift hour"))
        let perMile = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(perMile, in: app))
        XCTAssertTrue(perMile.label.contains("No usable position was recorded"), "Showed: \(perMile.label)")
        XCTAssertFalse(perMile.label.contains("$0.00"))
    }

    /// An edit to a delivery's amount that is cancelled writes nothing, and a
    /// removed amount returns the delivery to having none, which is not a
    /// recorded zero.
    ///
    /// Was two journeys over this fixture.
    @MainActor
    func testADeliveryAmountCancelledOrRemovedLeavesNothingInvented() throws {
        let app = launchWithFinishedDelivery()
        openFirstShift(in: app)

        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        recordDeliveryAmount("14.75", in: app)
        XCTAssertTrue(waitForLabel(row, toContain: "$14.75"))

        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        enter("99.99", into: field, in: app)
        app.buttons["cancelDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "$14.75"), "Cancel writes nothing: \(row.label)")
        XCTAssertFalse(row.label.contains("99.99"))

        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let remove = app.buttons["removeDeliveryEarningsButton"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.label, "Remove gross earnings from Delivery 1")
        remove.tap()
        XCTAssertTrue(app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.label,
            "Add gross earnings for Delivery 1",
            "The delivery is back to having no amount recorded"
        )
        XCTAssertFalse(row.label.contains("Gross earnings"), "Removed is not $0.00: \(row.label)")
    }

    /// The tips sheet keeps each tip its own record: with no platform amount it
    /// states no total; the earnings editor states the tips already recorded
    /// rather than inviting them into the platform amount; a tip of nothing is
    /// refused in a tip's words; two tips of different methods are two rows;
    /// a tip is corrected in place; and removing every tip leaves no total of
    /// tips and the platform amount untouched.
    ///
    /// Was five journeys over this fixture. The arithmetic is the tip suites'.
    @MainActor
    func testTheTipsSheetKeepsEachTipItsOwnRecord() throws {
        let app = launchWithFinishedDelivery()
        openFirstShift(in: app)
        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))

        // A tip on a delivery with no platform amount: there is no total.
        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        addTip("5.00", method: "Cash", in: app)
        XCTAssertTrue(
            waitForLabel(app.descendants(matching: .any)["deliveryTipsPlatformPay"], toContain: "No platform pay recorded for Delivery 1")
        )
        XCTAssertFalse(app.descendants(matching: .any)["deliveryTipsEffectiveTotal"].exists, "No total over half a fact")
        let notice = app.descendants(matching: .any)["deliveryTipsNoPlatformPayNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("no total"), "Showed: \(notice.label)")
        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "1 additional tip for Delivery 1, $5.00"))
        XCTAssertFalse(row.label.contains("Total recorded"), "Showed: \(row.label)")

        // The earnings editor says the tip is already recorded.
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        let stated = app.descendants(matching: .any)["deliveryEarningsAdditionalTips"]
        XCTAssertTrue(stated.waitForExistence(timeout: 5))
        XCTAssertTrue(stated.label.contains("$5.00"), "Showed: \(stated.label)")
        typeDeliveryAmount("10.00", in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.textFields["deliveryEarningsAmountField"]))
        XCTAssertTrue(waitForLabel(row, toContain: "Total recorded for Delivery 1, $15.00"), "Showed: \(row.label)")

        // A tip of nothing is refused, and records nothing.
        app.buttons["shiftDetailDeliveryTipsButton"].firstMatch.tap()
        app.buttons["addDeliveryTipButton"].tap()
        let tipField = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(tipField.waitForExistence(timeout: 5))
        enter("0", into: tipField, in: app)
        app.buttons["saveDeliveryTipButton"].tap()
        let message = app.descendants(matching: .any)["deliveryTipValidationMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.lowercased().contains("more than nothing"), "Showed: \(message.label)")
        app.buttons["cancelDeliveryTipButton"].tap()
        XCTAssertTrue(waitForDisappearance(of: tipField))

        // A second tip by another method is a second record.
        addTip("3.00", method: "Platform", in: app)
        let tipRows = app.descendants(matching: .any).matching(identifier: "deliveryTipRow")
        XCTAssertTrue(waitForCount(tipRows, toEqual: 2), "Two tips are two records rather than one doubled one")
        XCTAssertTrue(tipRows.element(boundBy: 0).label.contains("$5.00") && tipRows.element(boundBy: 0).label.contains("by cash"))
        XCTAssertTrue(tipRows.element(boundBy: 1).label.contains("$3.00") && tipRows.element(boundBy: 1).label.contains("by platform"))
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["deliveryTipsEffectiveTotal"], toContain: "$18.00"))
        let total = app.descendants(matching: .any)["deliveryTipsEffectiveTotal"]
        XCTAssertTrue(total.label.contains("platform pay and tips together"), "Showed: \(total.label)")

        // Corrected in place.
        let editTip = app.buttons["editDeliveryTipButton"].firstMatch
        XCTAssertTrue(editTip.waitForExistence(timeout: 5))
        XCTAssertEqual(editTip.label, "Edit tip 1 for Delivery 1", "The control names which tip it acts on")
        editTip.tap()
        let editField = app.textFields["deliveryTipAmountField"]
        XCTAssertTrue(editField.waitForExistence(timeout: 5))
        XCTAssertEqual(editField.value as? String, "5", "The editor opens on the stored amount")
        clear(editField, in: app)
        enter("4.50", into: editField, in: app)
        app.buttons["saveDeliveryTipButton"].tap()
        XCTAssertTrue(waitForLabel(total, toContain: "$17.50"))
        XCTAssertTrue(waitForDisappearance(of: app.textFields["deliveryTipAmountField"]))

        // Removing every tip takes the records away and leaves the platform pay.
        for _ in 0..<2 {
            app.buttons["editDeliveryTipButton"].firstMatch.tap()
            let remove = app.buttons["removeDeliveryTipButton"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            XCTAssertEqual(remove.label, "Remove this additional tip from Delivery 1")
            remove.tap()
            XCTAssertTrue(waitForDisappearance(of: remove))
        }
        XCTAssertTrue(waitForCount(tipRows, toEqual: 0))
        XCTAssertFalse(
            app.descendants(matching: .any)["deliveryTipsAdditionalTotal"].exists,
            "No tip recorded is not a tip of nothing, so there is no total of them"
        )
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["deliveryTipsPlatformPay"], toContain: "$10.00"))
        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(waitForLabel(row, toContain: "Gross earnings for Delivery 1, $10.00"))
        XCTAssertFalse(row.label.contains("additional tip"), "Showed: \(row.label)")
    }

    /// Each delivery keeps its own amount and its own rate over its own
    /// lifecycle, however far the lifecycles overlap: a cancelled one has none,
    /// a tip moves only its own delivery's rate, an edit to one leaves the
    /// others, and none of it touches the shift's own amount.
    ///
    /// Delivery 1 ran twenty-five minutes for $14.75 ($35.40 an hour; with a
    /// $5.00 tip, $47.40); Delivery 3 thirty minutes for $9.50 ($19.00).
    /// Was four journeys opening this same shift.
    @MainActor
    func testEachDeliveryKeepsItsOwnAmountAndRate() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let shiftEarnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(shiftEarnings.waitForExistence(timeout: 10))
        XCTAssertTrue(shiftEarnings.label.contains("86.25"), "The fixture's shift total: \(shiftEarnings.label)")

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("Gross earnings for Delivery 1, $14.75"), "Showed: \(first.label)")
        XCTAssertTrue(first.label.contains("$35.40 earned per recorded delivery hour"), "Showed: \(first.label)")
        let second = deliveryRow(containing: "Delivery 2, cancelled", in: app)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertFalse(second.label.contains("Gross earnings"), "No amount recorded shows none: \(second.label)")
        XCTAssertFalse(second.label.contains("per recorded delivery hour"), "No cancelled hourly rate: \(second.label)")
        let third = deliveryRow(containing: "Delivery 3, delivered", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("Gross earnings for Delivery 3, $9.50"), "Showed: \(third.label)")
        XCTAssertTrue(third.label.contains("$19.00 earned per recorded delivery hour"), "Its own thirty minutes: \(third.label)")

        // A tip moves Delivery 1's rate and nobody else's.
        XCTAssertTrue(scrollToTop(reaching: shiftEarnings, in: app))
        XCTAssertTrue(scrollTo(first, in: app))
        let tips = deliveryCard(containing: "Delivery 1, delivered", in: app).buttons["shiftDetailDeliveryTipsButton"]
        XCTAssertTrue(scrollUntilHittable(tips, in: app))
        tips.tap()
        addTip("5.00", method: "Cash", in: app)
        app.buttons["closeDeliveryTipsButton"].tap()
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(waitForLabel(first, toContain: "$47.40 earned per recorded delivery hour"), "Showed: \(first.label)")
        XCTAssertTrue(first.label.contains("Total recorded for Delivery 1, $19.75"), "Showed: \(first.label)")
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("$19.00 earned per recorded delivery hour"), "Showed: \(third.label)")

        // Editing Delivery 3 leaves Delivery 1 and the shift's own amount alone.
        let editThird = app.buttons
            .matching(identifier: "shiftDetailDeliveryEarningsButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "Delivery 3"))
            .firstMatch
        XCTAssertTrue(scrollUntilHittable(editThird, in: app))
        editThird.tap()
        let field = app.textFields["deliveryEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        clear(field, in: app)
        enter("20.00", into: field, in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(third, toContain: "$20.00"), "Showed: \(third.label)")
        XCTAssertTrue(scrollToTop(reaching: shiftEarnings, in: app))
        XCTAssertTrue(shiftEarnings.label.contains("86.25"), "A delivery amount never corrects the shift total")
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("$14.75"), "One delivery's amount is its own: \(first.label)")
    }

    /// Expected pay is recorded on a delivery in progress and stated as an
    /// expectation, never as earnings; delivering a delivery that carries one
    /// offers to record what it actually paid, and saying not now records
    /// nothing, in the running shift or in its history.
    ///
    /// Was two journeys over this fixture.
    @MainActor
    func testExpectedPayIsAnExpectationUntilTheDriverRecordsEarnings() throws {
        let app = launchWithExpectedPay()

        let card = deliveryStatus(containing: "Delivery 2", in: app)
        let add = deliveryButton("expectedEarningsButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(add, in: app), "A delivery in progress offers expected pay")
        XCTAssertEqual(add.label, "Add expected pay for Delivery 2")
        XCTAssertFalse(card.label.contains("Expected pay"), "Nothing is expected until recorded: \(card.label)")
        tapWithinReach(add, in: app)
        let field = app.textFields["deliveryExpectedEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(field.value as? String, "8.5", "The editor opens on this delivery's own record")
        XCTAssertFalse(app.buttons["removeDeliveryExpectedEarningsButton"].exists, "There is nothing to remove yet")
        typeExpectedPay("12.25", in: app)
        app.buttons["saveDeliveryExpectedEarningsButton"].tap()
        XCTAssertTrue(waitForLabel(card, toContain: "Expected pay for Delivery 2, $12.25"), "Showed: \(card.label)")
        XCTAssertTrue(card.label.contains("No gross earnings recorded yet"), "Showed: \(card.label)")
        XCTAssertFalse(card.label.contains("Gross earnings for Delivery 2, $12.25"))
        XCTAssertEqual(
            deliveryButton("expectedEarningsButton", containing: "Delivery 2", in: app).label,
            "Change expected pay for Delivery 2"
        )
        XCTAssertTrue(deliveryStatus(containing: "Delivery 1", in: app).label.contains("Expected pay for Delivery 1, $8.50"))
        let notice = app.descendants(matching: .any)["liveRateNotice"]
        XCTAssertTrue(reachShiftControl(notice, in: app))
        XCTAssertEqual(notice.label, "This shift is still running. Rates are worked out once it ends.")
        XCTAssertFalse(app.descendants(matching: .any)["liveRecordedGross"].exists, "No shift figure counts it")

        // Delivering one that carries an expectation offers the real amount.
        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(action, in: app))
        XCTAssertEqual(action.label, "Delivery 1. Mark order picked up")
        tapWithinReach(action, in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark delivery completed"))
        XCTAssertFalse(app.buttons["confirmEarningsRecordButton"].exists, "Nothing is asked before delivery")
        tapWithinReach(action, in: app)
        let expectedRow = app.descendants(matching: .any)["confirmEarningsExpectedAmount"]
        XCTAssertTrue(expectedRow.waitForExistence(timeout: 5), "The confirmation is raised")
        XCTAssertEqual(expectedRow.label, "Expected pay for Delivery 1, $8.50. No gross earnings recorded yet.")
        let amount = app.textFields["confirmEarningsAmountField"]
        XCTAssertEqual(amount.label, "Gross earnings for Delivery 1")
        XCTAssertEqual(amount.value as? String, "8.5")
        XCTAssertTrue(app.navigationBars["Delivery 1 Delivered"].exists)
        let dismiss = app.buttons["confirmEarningsDismissButton"].firstMatch
        XCTAssertEqual(dismiss.label, "Record no earnings for Delivery 1 now")
        dismiss.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["confirmEarningsRecordButton"].firstMatch))
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1))

        // The other delivery carries an expectation now too, and is finished
        // the same way, so the shift can end and its history be read.
        let remaining = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        for expected in ["Mark order picked up", "Mark delivery completed"] {
            XCTAssertTrue(waitForLabel(remaining, toContain: expected), "Showed: \(remaining.label)")
            tapWithinReach(remaining, in: app)
        }
        let secondDismiss = app.buttons["confirmEarningsDismissButton"].firstMatch
        XCTAssertTrue(secondDismiss.waitForExistence(timeout: 5))
        secondDismiss.tap()
        XCTAssertTrue(waitForDisappearance(of: secondDismiss))
        let endShift = app.buttons["endShiftButton"]
        XCTAssertTrue(reachShiftControl(endShift, in: app))
        endShift.tap()
        openFirstShift(in: app)
        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertTrue(row.label.contains("Expected pay for Delivery 1, $8.50. No gross earnings recorded yet."), "Showed: \(row.label)")
        XCTAssertFalse(row.label.contains("Gross earnings for Delivery 1"), "Dismissing recorded no amount")
        let shiftEarnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(scrollToTop(reaching: shiftEarnings, in: app))
        XCTAssertEqual(shiftEarnings.label, "No amount recorded", "No shift figure was invented from an expectation")
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
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["deleteShiftButton"].waitForExistence(timeout: 5), "Backing out deletes nothing")

        app.buttons["deleteShiftButton"].tap()
        let confirm = app.buttons.matching(identifier: "confirmDeleteShiftButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "route positions")).count > 0,
            "The confirmation says the shift's route is deleted with it"
        )
        confirm.tap()
        XCTAssertTrue(app.navigationBars["DashPilot"].waitForExistence(timeout: 5), "Detail returns to history")
        let remaining = rows(in: app)
        XCTAssertTrue(waitForCount(remaining, toEqual: 1), "The deleted shift is gone from history")
        XCTAssertFalse(remaining.firstMatch.label.contains("$86.25"), "And the one that remains is the other")
    }

    /// A finished shift's fuel assumptions: with none, the estimate and the net
    /// say which to add and every gross figure stands; a zero economy is
    /// refused and records neither half; one half alone names the missing half;
    /// both give an estimate that says what it is based on and that the route
    /// is partial, and a net that reads as a ledger and calls itself a ceiling;
    /// a better economy moves the estimate; removing them leaves none.
    ///
    /// Was eight journeys opening this same shift. The arithmetic is
    /// `FuelEstimateTests` and `ShiftProfitabilityTests`.
    @MainActor
    func testFuelAssumptionsOnAFinishedShift() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        let hourlyGross = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyGross, in: app))
        XCTAssertTrue(waitForLabel(hourlyGross, toContain: "gross earnings per shift hour"), "Gross rates stand")
        let cost = app.descendants(matching: .any)["shiftDetailEstimatedFuelCost"]
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(cost.label.contains("Add your vehicle's miles per gallon"), "Showed: \(cost.label)")
        XCTAssertFalse(cost.label.contains("$0.00"))
        let net = app.descendants(matching: .any)["shiftDetailEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(waitForLabel(net, toContain: "Add your miles per gallon and a gas price"), "Showed: \(net.label)")
        XCTAssertFalse(net.label.contains("$0.00"), "An absent net is not a net of nothing")

        // Zero economy is refused, and records neither half.
        let button = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        XCTAssertEqual(button.label, "Add Fuel Assumptions")
        button.tap()
        typeFuelAssumptions(milesPerGallon: "0", gasPrice: "3.50", in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()
        let message = validationMessage("fuelAssumptionsValidationMessage", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("more than zero"), "Showed: \(message.label)")
        XCTAssertTrue(app.textFields["fuelGasPriceField"].exists, "The editor keeps what was typed")
        app.buttons["cancelFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        XCTAssertEqual(button.label, "Add Fuel Assumptions", "Neither half was recorded")

        // One half alone names the other.
        button.tap()
        typeFuelAssumptions(milesPerGallon: "25", gasPrice: nil, in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "Add what a gallon of fuel cost"), "Showed: \(cost.label)")
        let price = app.descendants(matching: .any)["shiftDetailFuelGasPrice"]
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "No gas price recorded"), "Showed: \(price.label)")

        // Both halves: an estimate, its basis, its caveat, and the ledger.
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        XCTAssertEqual(button.label, "Edit Fuel Assumptions")
        button.tap()
        let priceField = app.textFields["fuelGasPriceField"]
        XCTAssertTrue(priceField.waitForExistence(timeout: 5))
        enter("3.50", into: priceField, in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "estimated fuel cost, based on recorded mileage"), "Showed: \(cost.label)")
        XCTAssertTrue(cost.label.contains("This route is partial"), "Showed: \(cost.label)")
        XCTAssertTrue(cost.label.contains("more fuel was used than this estimates"), "Showed: \(cost.label)")
        let firstEstimate = cost.label
        let gallons = app.descendants(matching: .any)["shiftDetailEstimatedGallons"]
        XCTAssertTrue(scrollTo(gallons, in: app))
        XCTAssertTrue(waitForLabel(gallons, toContain: "gallons estimated, from recorded mileage"))
        let economy = app.descendants(matching: .any)["shiftDetailFuelMilesPerGallon"]
        XCTAssertTrue(scrollTo(economy, in: app))
        XCTAssertTrue(waitForLabel(economy, toContain: "25 miles per gallon assumed"))
        XCTAssertTrue(scrollTo(price, in: app))
        XCTAssertTrue(waitForLabel(price, toContain: "$3.50 per gallon assumed"))

        let recorded = app.descendants(matching: .any)["shiftDetailNetRecordedEarnings"]
        XCTAssertTrue(scrollTo(recorded, in: app))
        XCTAssertTrue(waitForLabel(recorded, toContain: "$86.25 recorded gross earnings for this shift"))
        let fuel = app.descendants(matching: .any)["shiftDetailNetEstimatedFuel"]
        XCTAssertTrue(scrollTo(fuel, in: app))
        XCTAssertTrue(waitForLabel(fuel, toContain: "estimated fuel cost, based on recorded mileage"))
        XCTAssertTrue(fuel.label.contains("-$"), "It is subtracted, which the figure shows: \(fuel.label)")
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(waitForLabel(net, toContain: "estimated net after fuel"), "Showed: \(net.label)")
        XCTAssertFalse(net.label.lowercased().contains("profit"))
        let hourlyNet = app.descendants(matching: .any)["shiftDetailEstimatedNetPerWorkingHour"]
        XCTAssertTrue(scrollTo(hourlyNet, in: app))
        XCTAssertTrue(waitForLabel(hourlyNet, toContain: "estimated net after fuel per working hour"))
        let ceiling = app.descendants(matching: .any)["shiftDetailEstimatedNetPartialNotice"]
        XCTAssertTrue(scrollTo(ceiling, in: app))
        XCTAssertTrue(waitForLabel(ceiling, toContain: "this net is a ceiling"), "Showed: \(ceiling.label)")

        // A better economy is less fuel over the same miles.
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        button.tap()
        let economyField = app.textFields["fuelMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        XCTAssertEqual(economyField.value as? String, "25", "The editor opens on the stored figures")
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.5")
        clear(economyField, in: app)
        enter("50", into: economyField, in: app)
        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "estimated fuel cost"))
        XCTAssertNotEqual(cost.label, firstEstimate, "A more economical vehicle uses less fuel")

        // Removing them leaves no estimate, not an estimate of nothing.
        XCTAssertTrue(scrollUntilHittable(button, in: app))
        button.tap()
        let remove = app.buttons["removeFuelAssumptionsButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(scrollTo(cost, in: app))
        XCTAssertTrue(waitForLabel(cost, toContain: "Add your vehicle's miles per gallon"), "Showed: \(cost.label)")
        XCTAssertFalse(cost.label.contains("$0.00"))
    }

    /// Assumptions recorded on one shift fill the next shift's editor, which is
    /// a suggestion until saved, and that shift's net names its missing
    /// earnings rather than its fuel.
    ///
    /// Was two journeys over this fixture.
    @MainActor
    func testFuelAssumptionsSeedTheNextShiftAndItsNetNamesMissingEarnings() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)
        recordFuelAssumptions(milesPerGallon: "25", gasPrice: "3.50", in: app)
        goBack(in: app)

        revealHistoryRows(2, in: app).element(boundBy: 1).tap()
        let net = app.descendants(matching: .any)["shiftDetailEstimatedNetAfterFuel"]
        XCTAssertTrue(scrollTo(net, in: app))
        XCTAssertTrue(waitForLabel(net, toContain: "Add what this shift paid"), "Showed: \(net.label)")
        XCTAssertFalse(net.label.contains("$0.00"))

        let add = app.buttons["editFuelAssumptionsButton"]
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        XCTAssertEqual(add.label, "Add Fuel Assumptions", "This shift has recorded nothing of its own")
        add.tap()
        let economyField = app.textFields["fuelMilesPerGallonField"]
        XCTAssertTrue(economyField.waitForExistence(timeout: 5))
        XCTAssertEqual(economyField.value as? String, "25", "Filled in from the last pair recorded")
        XCTAssertEqual(app.textFields["fuelGasPriceField"].value as? String, "3.5")
        app.buttons["cancelFuelAssumptionsButton"].tap()
        XCTAssertTrue(scrollUntilHittable(add, in: app))
        XCTAssertEqual(add.label, "Add Fuel Assumptions", "A filled field is a suggestion, not a figure")
    }

    /// A completed shift at the largest accessibility size: the summary's
    /// figures stack whole, the delivery's six actions become one full-width
    /// column, every one still tappable, and the end of the screen is reachable.
    ///
    /// Was two journeys at AX5 over this fixture.
    @MainActor
    func testACompletedShiftAtTheLargestTextSize() throws {
        let app = launchWithSeededHistory(atTextSize: Self.accessibilityXXXLTextSize)
        let shift = rows(in: app).firstMatch
        XCTAssertTrue(scrollTo(shift, in: app, maxSwipes: 15), "A completed shift is listed, further down")
        XCTAssertTrue(scrollUntilHittable(shift, in: app, maxSwipes: 5))
        // At this size the row arrives at the very foot of the screen, and a
        // local run's recording shows it tapped there while still sliding up:
        // the tap opened nothing. Settled wholly on screen first, as
        // `openFirstShift` does for the same reason.
        settleWhollyOnScreen(shift, in: app)
        shift.tap()

        let earnings = app.descendants(matching: .any)["shiftDetailEarnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        XCTAssertTrue(earnings.label.contains("$86.25"), "The figure is whole rather than shortened")
        let working = app.descendants(matching: .any)["shiftDetailSummaryWorkingTime"]
        XCTAssertTrue(scrollTo(working, in: app))
        XCTAssertGreaterThan(onPixelGrid(working.frame.height), 44, "A stacked figure is never a tiny cell")
        attachScreenshot("detail-xxxl")

        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app, maxSwipes: 30), "The delivery should be listed")
        let place = card.buttons["shiftDetailPickupPlaceButton"]
        let history = card.buttons["shiftDetailPickupHistoryButton"]
        let deliveryEarnings = card.buttons["shiftDetailDeliveryEarningsButton"]
        let tips = card.buttons["shiftDetailDeliveryTipsButton"]
        let times = card.buttons["shiftDetailCorrectDeliveryTimesButton"]
        let correct = card.buttons["shiftDetailCorrectToCancelledButton"]
        XCTAssertTrue(scrollUntilHittable(place, in: app, maxSwipes: 30))
        let width = app.windows.element(boundBy: 0).frame.width
        for action in [place, history, deliveryEarnings, tips, times, correct] {
            XCTAssertTrue(action.exists, "Nothing is dropped to keep the card short")
            XCTAssertGreaterThan(action.frame.width, width * 0.7, "Full width: \(action.label)")
        }
        XCTAssertGreaterThan(history.frame.minY, place.frame.maxY - 1, "One column rather than two narrow ones")
        XCTAssertEqual(history.frame.minX, place.frame.minX, accuracy: 1)
        XCTAssertTrue(scrollUntilHittable(tips, in: app, maxSwipes: 10))
        XCTAssertGreaterThan(tips.frame.minY, deliveryEarnings.frame.maxY - 1)
        XCTAssertTrue(scrollUntilHittable(times, in: app, maxSwipes: 10))
        XCTAssertGreaterThan(times.frame.minY, tips.frame.maxY - 1)
        XCTAssertTrue(scrollUntilHittable(correct, in: app, maxSwipes: 10))
        XCTAssertGreaterThan(correct.frame.minY, times.frame.maxY - 1)

        let delete = app.buttons["deleteShiftButton"]
        XCTAssertTrue(scrollTo(delete, in: app, maxSwipes: 60), "And so is the end of the screen")
    }

    /// A completed shift that recorded no amount, no delivery and no route
    /// invents none of them: no rate of zero, no active time of zero minutes,
    /// no distance of zero and no counts of nothing. Each absence is stated.
    ///
    /// Three journeys used to open this shift for one absence each.
    @MainActor
    func testAShiftThatRecordedNothingInventsNoFigures() throws {
        let app = launchWithSeededHistory()
        let history = revealHistoryRows(2, in: app)

        let withoutEarnings = history.element(boundBy: 1)
        XCTAssertFalse(withoutEarnings.label.contains("gross earnings per"), "Showed: \(withoutEarnings.label)")
        XCTAssertFalse(withoutEarnings.label.contains("$0.00"))
        withoutEarnings.tap()

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5), "The shift still has an elapsed duration")
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailNonDeliveryTime"].exists)

        let hourly = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourly, in: app))
        XCTAssertTrue(hourly.label.contains("Add what this shift paid"), "Showed: \(hourly.label)")
        XCTAssertFalse(hourly.label.contains("$0.00"))

        let activeRate = app.descendants(matching: .any)["shiftDetailActiveHourlyRate"]
        XCTAssertTrue(scrollTo(activeRate, in: app))
        XCTAssertTrue(
            activeRate.label.contains("No gross earnings per delivery active hour"),
            "An absent rate is stated as absent: \(activeRate.label)"
        )
        XCTAssertFalse(activeRate.label.contains("$"), "Showed: \(activeRate.label)")

        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("No route recorded"))
        XCTAssertFalse(mileage.label.contains("0.0"), "An unmeasurable route is not a distance of zero")
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailCaptureSegments"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["shiftDetailCaptureGaps"].exists)
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
        tapWithinReach(second, in: app)
        XCTAssertTrue(waitForLabel(second, toContain: "Delivery 2. Mark order picked up"))
        XCTAssertEqual(first.label, "Delivery 1. Mark arrived at pickup", "Delivery 1 is untouched")
    }

    // MARK: Parked for a pickup

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
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: toggle)],
                timeout: 5
            ) == .completed,
            "\(identifier) reads \(wanted): \(String(describing: toggle.value))"
        )
    }

    /// Waits for a control to become enabled or disabled.
    @MainActor
    private func waitForEnabled(_ element: XCUIElement, _ isEnabled: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == %@", NSNumber(value: isEnabled)),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
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
            app.buttons["resumeDrivingButton"].waitForExistence(timeout: 5),
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
            app.buttons["parkShiftButton"].waitForExistence(timeout: 5),
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

    /// The pickup and parking settings: the workflow off unless chosen, its
    /// stacked-order child unusable on its own and saying why, both choices
    /// kept and kept inert, and resuming after progress off and independent.
    ///
    /// Was two journeys over the same Settings group.
    @MainActor
    func testPickupAndParkingSettingsAreOffAndKeptAsChosen() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)

        let parent = app.switches["pickupWorkflowToggle"]
        let child = app.switches["stackedOrdersInOrderToggle"]
        let resume = app.switches["resumeAfterProgressToggle"]
        XCTAssertTrue(scrollTo(resume, in: app))
        XCTAssertEqual(parent.value as? String, "0", "A driver who never chose it has it off")
        XCTAssertEqual(child.value as? String, "0")
        XCTAssertEqual(resume.value as? String, "0", "Off unless the driver turns it on")
        XCTAssertTrue(parent.label.contains("Pick up orders with Park & Resume"), parent.label)
        XCTAssertTrue(child.label.contains("Handle stacked orders in order"), child.label)
        XCTAssertTrue(child.label.contains("Needs Pick up orders with Park & Resume on"), "Says why: \(child.label)")
        XCTAssertFalse(child.isEnabled, "Stacked orders cannot be turned on while the workflow is off")
        XCTAssertTrue(resume.label.contains("Resume driving after delivery progress"), resume.label)
        XCTAssertTrue(resume.isEnabled, "It depends on nothing")

        setSwitch("resumeAfterProgressToggle", to: true, in: app)
        XCTAssertEqual(parent.value as? String, "0", "Turning it on turns nothing else on")
        setSwitch("pickupWorkflowToggle", to: true, in: app)
        XCTAssertTrue(waitForEnabled(child, true), "With the workflow on, stacked orders can be chosen")
        setSwitch("stackedOrdersInOrderToggle", to: true, in: app)
        attachScreenshot("settings-pickup-parking")
        setSwitch("pickupWorkflowToggle", to: false, in: app)
        XCTAssertTrue(waitForEnabled(child, false), "And inert again once the workflow is off")
        XCTAssertEqual(child.value as? String, "1", "The stacked choice is kept, and inert")
        goBack(in: app)

        openSettings(in: app)
        XCTAssertTrue(scrollTo(resume, in: app))
        XCTAssertEqual(parent.value as? String, "0", "The choices are kept across leaving the screen")
        XCTAssertEqual(child.value as? String, "1")
        XCTAssertEqual(resume.value as? String, "1")
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

    /// One stacked offer read as one offer of independent deliveries: one
    /// heading over the offer and none over a delivery accepted alone, each
    /// card saying what it is waiting for and naming aloud what it was accepted
    /// with, and advancing one card moving only that card, with the heading
    /// then saying how much of the offer is left.
    ///
    /// Was five journeys over this fixture. Grouping is `DeliveryGroupingTests`.
    @MainActor
    func testAStackedOfferReadsAsOneOfferOfIndependentDeliveries() throws {
        let app = launchWithStackedOffer()
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 15))

        let heading = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(heading, in: app), "The offer that held two deliveries names itself")
        XCTAssertTrue(heading.label.contains("Offer 1") && heading.label.contains("2 deliveries accepted together"))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "offerGroupHeader").count, 1,
            "An offer of one gets no heading"
        )
        XCTAssertEqual(app.buttons.matching(identifier: "deliveryActionButton").count, 3)

        let first = deliveryStatusCard(named: "Delivery 1", in: app)
        let second = deliveryStatusCard(named: "Delivery 2", in: app)
        let third = deliveryStatusCard(named: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("waiting at the pickup"), first.label)
        XCTAssertTrue(first.label.contains("Next step, mark order picked up"), first.label)
        XCTAssertFalse(first.label.contains("Next step, mark arrived at pickup"), "Not offered what it recorded")
        XCTAssertTrue(first.label.contains("Part of Offer 1, accepted together with Delivery 2"), first.label)
        XCTAssertTrue(scrollTo(second, in: app))
        XCTAssertTrue(second.label.contains("heading to the pickup"), second.label)
        XCTAssertTrue(second.label.contains("Next step, mark arrived at pickup"), second.label)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertTrue(third.label.contains("Next step, mark arrived at pickup"), third.label)
        XCTAssertFalse(third.label.contains("accepted together"), "Accepted alone claims no grouping: \(third.label)")

        // Advancing Delivery 2 moves only Delivery 2.
        let firstBefore = first.label
        let step = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollTo(step, in: app))
        tapWithinReach(step, in: app)
        XCTAssertTrue(waitForLabel(second, toContain: "Next step, mark order picked up"), second.label)
        XCTAssertEqual(first.label, firstBefore, "The card beside it says exactly what it said")

        // Delivering one of the offer leaves its sibling and says what is left.
        let firstStep = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["activeShiftStatus"], in: app))
        XCTAssertTrue(scrollUntilHittable(firstStep, in: app))
        firstStep.tap()
        XCTAssertTrue(waitForLabel(firstStep, toContain: "Mark delivery completed"))
        tapWithinReach(firstStep, in: app)
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 2))
        XCTAssertTrue(scrollTo(heading, in: app))
        XCTAssertTrue(heading.label.contains("1 of 2 still in progress"), "Showed: \(heading.label)")
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
        XCTAssertTrue(reminders.firstMatch.waitForExistence(timeout: 10))
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

        XCTAssertTrue(heading.waitForExistence(timeout: 5))
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
        XCTAssertTrue(startDelivery.waitForExistence(timeout: 5))
        let actions = app.buttons.matching(identifier: "deliveryActionButton")

        let offerControl = app.buttons["startOfferButton"]
        XCTAssertTrue(scrollTo(offerControl, in: app), "The control for a several-delivery offer is on the panel")
        offerControl.tap()
        let cancel = app.buttons["cancelStartOfferButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(startDelivery.waitForExistence(timeout: 5))
        XCTAssertEqual(actions.count, 0, "A dismissed sheet records nothing")

        offerControl.tap()
        let confirm = app.buttons["confirmStartOfferButton"]
        let stepper = app.steppers["offerDeliveryCountStepper"]
        let pickup = app.switches["offerSamePickupToggle"]
        let dropOff = app.switches["offerSameDropOffToggle"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 15))
        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app), "Correction is one control, not a button on every card")
        let heading = app.descendants(matching: .any)["offerGroupHeader"]

        correct.tap()
        XCTAssertTrue(app.buttons["offerCorrectionSeparateButton"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "Combine Offer 2 into Offer 1", "The direction is in the control")
        destination.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let confirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertEqual(confirm.label, "Combine into Offer 1")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Delivery 3 moves to Offer 1")).count > 0,
            "The confirmation names what moves"
        )
        confirm.tap()
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
        XCTAssertTrue(split.waitForExistence(timeout: 5), "Splitting is offered apart from moving, not mixed into it")
        XCTAssertEqual(split.label, "Put Delivery 2 in a new offer of its own")
        split.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch.tap()
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
        XCTAssertTrue(separate.waitForExistence(timeout: 5))
        XCTAssertEqual(separate.label, "Separate Offer \(pair) into one offer per delivery")
        separate.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let separateConfirm = alert.buttons.matching(identifier: "confirmOfferCorrectionButton").firstMatch
        XCTAssertEqual(separateConfirm.label, "Separate Offer \(pair)")
        separateConfirm.tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 10))
        XCTAssertTrue(reachShiftControl(endShift, in: app), "End is below the delivery cards")
        endShift.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 deliveries are still in progress"))
                .firstMatch.waitForExistence(timeout: 5),
            "Ending is refused with a reason that counts them"
        )
        app.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["endShiftButton"].waitForExistence(timeout: 5), "The shift is still running")
        XCTAssertTrue(rows(in: app).count == 0, "No completed shift appeared in history")

        // Cancelling one is named, confirmed, and spares the other.
        let cancel = deliveryButton("cancelDeliveryButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(scrollToTop(reaching: app.descendants(matching: .any)["activeShiftStatus"], in: app))
        XCTAssertTrue(scrollTo(cancel, in: app))
        XCTAssertEqual(cancel.label, "Delivery 2. Cancel this delivery", "The control says which delivery it ends")
        tapWithinReach(cancel, in: app)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cancel Delivery 2?"))
                .firstMatch.waitForExistence(timeout: 5),
            "The confirmation names the delivery"
        )
        let confirm = app.buttons.matching(identifier: "confirmCancelDeliveryButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
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
                .firstMatch.waitForExistence(timeout: 5),
            "One remaining delivery still blocks the end, and the wording follows the count"
        )
        app.buttons["OK"].tap()

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
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Confirmed before anything is written")
        dismiss(alert, tapping: "Cancel")
        XCTAssertTrue(deliveryRow(containing: "Delivery 1, delivered", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(deliveryRow(containing: "Delivery 1, cancelled", in: app).exists, "Dismissing wrote nothing")

        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        correct.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
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
        confirm.tap()

        let corrected = deliveryRow(containing: "Delivery 1, cancelled", in: app)
        XCTAssertTrue(corrected.waitForExistence(timeout: 5))
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

    /// Correcting a recorded pause in its editor: cancelling writes nothing; a
    /// stretch over recorded delivery work is refused naming what it collided
    /// with and cannot be saved; a correction states its consequence first and
    /// moves exactly the paused time, the working time and the hourly rate.
    ///
    /// Was three journeys over this fixture. The rules are
    /// `ShiftPauseCorrectionTests`.
    @MainActor
    func testCorrectingAndRefusingAPauseInTheEditor() throws {
        let app = launchWithPausedHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app))
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time")
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailPausedTime"].label, "50 minutes paused time, over 2 pauses")
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailWorkingTime"].label, "3 hours, 10 minutes working time")
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        let perMileRate = app.descendants(matching: .any)["shiftDetailPerMileRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        let hourlyBefore = hourlyRate.label
        XCTAssertTrue(scrollTo(perMileRate, in: app))
        let perMileBefore = perMileRate.label

        // Cancelling writes nothing.
        let edit = pauseButton("editShiftPauseButton", containing: "Pause 1", in: app)
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        XCTAssertEqual(edit.label, "Edit Pause 1. Change when this pause started and ended")
        edit.tap()
        let summary = app.descendants(matching: .any)["shiftPauseEditorSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        setTime(minute: "45", ofPicker: "shiftPauseEndPicker", in: app)
        app.buttons["shiftPauseEditorCancelButton"].tap()
        XCTAssertTrue(pauseRow(containing: "Pause 1", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(pauseRow(containing: "Pause 1", in: app).label.contains("30 minutes"), "As recorded")

        // Over a delivery: refused, named, and not saveable.
        let editTwo = pauseButton("editShiftPauseButton", containing: "Pause 2", in: app)
        XCTAssertTrue(scrollUntilHittable(editTwo, in: app))
        editTwo.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        setTime(minute: "15", ofPicker: "shiftPauseStartPicker", in: app)
        let refusal = app.descendants(matching: .any).matching(identifier: "shiftPauseEditorRefusal").firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5))
        XCTAssertTrue(refusal.label.contains("A delivery was in progress during that time"), "Showed: \(refusal.label)")
        XCTAssertFalse(app.buttons["shiftPauseEditorSaveButton"].isEnabled, "Withheld rather than refused later")
        app.buttons["shiftPauseEditorCancelButton"].tap()
        XCTAssertTrue(pauseRow(containing: "Pause 2", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(pauseRow(containing: "Pause 2", in: app).label.contains("20 minutes"))

        // Corrected: the consequence first, then exactly three figures move.
        XCTAssertTrue(scrollUntilHittable(edit, in: app))
        edit.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasPrefix("30 minutes paused"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("working time becomes 3 hr, 10 min"), "Showed: \(summary.label)")
        setTime(minute: "45", ofPicker: "shiftPauseEndPicker", in: app)
        XCTAssertTrue(waitForLabel(summary, toContain: "45 minutes paused"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("working time becomes 2 hr, 55 min"), "Showed: \(summary.label)")
        app.buttons["shiftPauseEditorSaveButton"].tap()
        let correctedRow = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(correctedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(correctedRow.label.contains("45 minutes"), "Showed: \(correctedRow.label)")

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailPausedTime"], toContain: "1 hour, 5 minutes"))
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailWorkingTime"].label, "2 hours, 55 minutes working time")
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time", "The shift's own start and end did not move")
        XCTAssertEqual(
            app.descendants(matching: .any)["shiftDetailDeliveryActiveTime"].label,
            "30 minutes delivery active time",
            "and neither did the delivery it recorded"
        )
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertNotEqual(hourlyRate.label, hourlyBefore, "The rate over working time follows the correction")
        XCTAssertTrue(scrollTo(perMileRate, in: app))
        XCTAssertEqual(perMileRate.label, perMileBefore, "The rate a pause has nothing to do with is unchanged")
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
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        dismiss(alert, tapping: "Cancel")
        XCTAssertTrue(pauseRow(containing: "Pause 1", in: app).label.contains("30 minutes"), "Backing out keeps it")

        XCTAssertTrue(scrollUntilHittable(delete, in: app))
        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "working time becomes 30 min longer")).count > 0
        )
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "route recorded during it is not changed")).count > 0
        )
        let confirm = alert.buttons.matching(identifier: "confirmDeleteShiftPauseButton").firstMatch
        XCTAssertEqual(confirm.label, "Delete Pause 1")
        confirm.tap()
        let remaining = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
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
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "Nothing is suggested")
        XCTAssertTrue(refusal.label.contains("A pause has to end after it started"), "Showed: \(refusal.label)")
        XCTAssertFalse(app.buttons["shiftPauseEditorSaveButton"].isEnabled)
        setTime(minute: "50", ofPicker: "shiftPauseStartPicker", in: app)
        setTime(minute: "55", ofPicker: "shiftPauseEndPicker", in: app)
        let summary = app.descendants(matching: .any)["shiftPauseEditorSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasPrefix("5 minutes paused"), "Showed: \(summary.label)")
        app.buttons["shiftPauseEditorSaveButton"].tap()
        let added = pauseRow(containing: "Pause 1", in: app)
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(added.label.contains("5 minutes"), "First, because it began first: \(added.label)")
        XCTAssertTrue(pauseRow(containing: "Pause 2", in: app).exists, "Two of them now")

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(app.descendants(matching: .any)["shiftDetailPausedTime"], toContain: "over 2 pauses"))
        XCTAssertEqual(app.descendants(matching: .any)["shiftDetailWorkingTime"].label, "3 hours, 35 minutes working time")
        XCTAssertEqual(elapsed.label, "4 hours elapsed shift time", "The shift's own times did not move")
    }

    /// Correcting the end of a shift DashPilot recorded as ending late: a later
    /// end would add time and no mileage; an end inside recorded delivery work
    /// is refused naming the delivery and event; an earlier end states what it
    /// costs, is confirmed before route is deleted, can be declined with
    /// nothing written, and once confirmed measures the mileage again from the
    /// positions that remain rather than scaling it.
    ///
    /// Was four journeys. The rules are `ShiftEndCorrectionTests`.
    @MainActor
    func testCorrectingAShiftThatDashPilotRecordedAsEndingLate() throws {
        let app = launchWithLateEndHistory()
        openFirstShift(in: app)

        let elapsed = app.descendants(matching: .any)["shiftDetailDuration"]
        XCTAssertTrue(scrollTo(elapsed, in: app))
        XCTAssertEqual(elapsed.label, "3 hours, 40 minutes elapsed shift time")
        let hourlyRate = app.descendants(matching: .any)["shiftDetailHourlyRate"]
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(hourlyRate.label.hasPrefix("$27.27"), "Showed: \(hourlyRate.label)")
        let mileage = app.descendants(matching: .any)["shiftDetailRecordedMileage"]
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(mileage.label.contains("6.7 miles"), "Showed: \(mileage.label)")

        let correct = app.buttons["correctShiftEndButton"]
        XCTAssertTrue(scrollUntilHittable(correct, in: app))
        XCTAssertEqual(correct.label, "Correct the time this shift ended")
        correct.tap()
        let summary = app.descendants(matching: .any)["shiftEndCorrectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasPrefix("3 hours, 40 minutes elapsed"), "Showed: \(summary.label)")
        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionRecordedEnd"].exists)
        let warning = app.descendants(matching: .any).matching(identifier: "shiftEndCorrectionRouteWarning").firstMatch

        // Later: time and no mileage.
        setTime(minute: "50", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(warning, toContain: "No route or mileage is added"), "Showed: \(warning.label)")

        // Inside recorded delivery work: refused, named.
        setTime(minute: "05", ofPicker: "shiftEndCorrectionPicker", in: app)
        let refusal = app.descendants(matching: .any).matching(identifier: "shiftEndCorrectionRefusal").firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5))
        XCTAssertTrue(refusal.label.hasPrefix("Delivery 1 has Delivered recorded at "), "Showed: \(refusal.label)")
        XCTAssertTrue(refusal.label.contains("after the proposed shift end"), "Showed: \(refusal.label)")
        XCTAssertFalse(app.buttons["shiftEndCorrectionSaveButton"].isEnabled)

        // Earlier, clear of the work: its cost is stated, then confirmed.
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertTrue(waitForLabel(summary, toContain: "3 hours, 20 minutes elapsed"), "Showed: \(summary.label)")
        XCTAssertTrue(waitForLabel(warning, toContain: "10 recorded positions"), "Showed: \(warning.label)")
        XCTAssertTrue(warning.label.contains("not reduced by the same share as the time"), "Showed: \(warning.label)")
        app.buttons["shiftEndCorrectionSaveButton"].tap()
        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Destroying recorded route is confirmed first")
        dismiss(app.alerts.firstMatch, tapping: "Cancel")
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Declined, the sheet stays with the chosen time")
        app.buttons["shiftEndCorrectionSaveButton"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(scrollToTop(reaching: elapsed, in: app))
        XCTAssertTrue(waitForLabel(elapsed, toContain: "3 hours, 20 minutes"), "Showed: \(elapsed.label)")
        XCTAssertTrue(scrollTo(hourlyRate, in: app))
        XCTAssertTrue(waitForLabel(hourlyRate, toContain: "$30.00"), "Showed: \(hourlyRate.label)")
        XCTAssertTrue(scrollTo(mileage, in: app))
        XCTAssertTrue(waitForLabel(mileage, toContain: "4.5 miles"), "Measured again: \(mileage.label)")
        XCTAssertFalse(mileage.label.contains("5.6 miles"), "Not scaled by the time removed")
        XCTAssertTrue(waitForLabel(app.staticTexts["shiftDetailCaptureSegments"], toContain: "2"))
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
        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        let endRefusal = app.descendants(matching: .any).matching(identifier: "shiftEndCorrectionRefusal").firstMatch
        XCTAssertTrue(endRefusal.waitForExistence(timeout: 5))
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
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 hour, 30 minutes"), "Showed: \(summary.label)")
        let note = app.descendants(matching: .any).matching(identifier: "deliveryTimeCorrectionRouteNotice").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("recorded mileage are not changed"), "Showed: \(note.label)")
        setTime(minute: "02", ofPicker: "deliveryTimeCorrectionPicker.pickedUp", in: app)
        let timeRefusal = app.descendants(matching: .any).matching(identifier: "deliveryTimeCorrectionRefusal").firstMatch
        XCTAssertTrue(timeRefusal.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.descendants(matching: .any)["shiftEndCorrectionSummary"].waitForExistence(timeout: 5))
        setTime(minute: "20", ofPicker: "shiftEndCorrectionPicker", in: app)
        XCTAssertFalse(endRefusal.exists, "No longer refused")
        app.buttons["shiftEndCorrectionSaveButton"].tap()
        let confirm = app.buttons["confirmShiftEndCorrectionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
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
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        tapWithinReach(second, in: app)
        let recent = app.buttons
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "recentPickupPlaceButton", Self.noodles))
            .firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "The place used moments ago is offered")
        recent.tap()
        XCTAssertTrue(waitForLabel(deliveryStatus(containing: "Delivery 2", in: app), toContain: Self.noodles))

        XCTAssertTrue(scrollTo(pickup, in: app))
        tapWithinReach(pickup, in: app)
        let field = app.textFields["pickupPlaceNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(waitForLabel(status, toContain: "waiting at the pickup"), "Showed: \(status.label)")
        XCTAssertFalse(status.label.contains(Self.diner), "The place is gone")
        XCTAssertEqual(action.label, "Delivery 1. Mark order picked up", "Exactly where it was in its lifecycle")
        XCTAssertTrue(waitForLabel(pickup, toContain: "Add pickup place"))
    }

    /// Pickup waits: a delivery states its own wait, never as the place's; a
    /// place's history is the median of its recorded pickups with the count
    /// and range, claiming nothing more; one recorded pickup is not a typical
    /// wait; two places keep separate histories; and a delivery with no place
    /// has no history to open.
    ///
    /// Was five journeys over this fixture. Medians are `PickupWaitMetricsTests`.
    @MainActor
    func testPickupWaitHistoryIsPerPlaceAndStatesItsSample() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)

        let first = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("Waited at pickup 6 minutes"), "Showed: \(first.label)")
        XCTAssertFalse(first.label.lowercased().contains("typical"), "One wait is not a claim about the place")
        XCTAssertFalse(first.label.contains("median"))

        openPickupHistory(from: "Delivery 1, delivered", in: app)
        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[Self.noodles].exists, "Titled by the place it describes")
        XCTAssertTrue(summary.label.contains("Typical recorded pickup wait, 11 minutes"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("median of 3 recorded pickups"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("longest 41 minutes"), "A long wait is kept: \(summary.label)")
        XCTAssertFalse(summary.label.contains("4 recorded pickups"), "A cancelled arrival contributed nothing")
        for overclaim in ["reliable", "accurate", "predict", "average", "score", "best", "fastest"] {
            XCTAssertFalse(summary.label.lowercased().contains(overclaim), "Must not claim \(overclaim)")
        }
        closePickupHistory(in: app)

        openPickupHistory(from: "Delivery 5, delivered", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[Self.diner].exists)
        XCTAssertTrue(summary.label.contains("1 recorded pickup, 20 minutes"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("Not enough history for a typical wait"), "Showed: \(summary.label)")
        XCTAssertFalse(summary.label.lowercased().contains("typical recorded pickup wait"))
        XCTAssertFalse(summary.label.contains("Median"))
        XCTAssertFalse(summary.label.contains("11 minutes"), "The other place's median does not leak in")
        closePickupHistory(in: app)

        let unattributed = deliveryRow(containing: "Delivery 6, delivered", in: app)
        XCTAssertTrue(scrollTo(unattributed, in: app))
        XCTAssertFalse(unattributed.label.contains("Picked up from"), "It named no place")
        XCTAssertTrue(unattributed.label.contains("Waited at pickup"), "Its own wait is still recorded")
        XCTAssertNil(pickupHistoryButton(near: unattributed, in: app), "A delivery with no place is offered no history")
    }

    /// Correcting pickup places: renaming onto a name another place uses is
    /// refused and points at merging; a rename changes only the name; and
    /// merging two places a driver meant as one moves deliveries, destroys
    /// nothing, and reads their waits together.
    ///
    /// Was three journeys over this fixture. Merging is `PickupPlaceServiceTests`.
    @MainActor
    func testCorrectingPickupPlacesRenamesRefusesAndMerges() throws {
        let app = launchWithPickupHistory()
        openFirstShift(in: app)
        openPickupHistory(from: "Delivery 1, delivered", in: app)
        let summary = app.descendants(matching: .any)["pickupPlaceHistorySummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let before = summary.label

        let rename = app.buttons["renamePickupPlaceButton"]
        XCTAssertTrue(scrollTo(rename, in: app))
        XCTAssertEqual(rename.label, "Rename pickup place, \(Self.noodles)", "The control names its place")
        rename.tap()
        let field = app.textFields["pickupPlaceRenameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, Self.noodles)
        clear(field, in: app)
        enter(Self.diner, into: field, in: app)
        app.buttons["savePickupPlaceRenameButton"].tap()
        let message = app.staticTexts.matching(identifier: "pickupPlaceRenameMessage").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Refused rather than silently merged")
        XCTAssertTrue(message.label.contains(Self.diner) && message.label.lowercased().contains("merge"), message.label)
        XCTAssertTrue(field.exists, "The sheet stays open with what was typed")

        clear(field, in: app)
        enter(Self.renamedNoodles, into: field, in: app)
        app.buttons["savePickupPlaceRenameButton"].tap()
        XCTAssertTrue(app.navigationBars[Self.renamedNoodles].waitForExistence(timeout: 5), "Titled by the new name")
        XCTAssertEqual(summary.label, before, "A rename moves no wait")
        closePickupHistory(in: app)
        let row = deliveryRow(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(waitForLabel(row, toContain: "Picked up from \(Self.renamedNoodles)"))
        XCTAssertTrue(row.label.contains("Waited at pickup 6 minutes"), "Its own record is untouched")

        openPickupHistory(from: "Delivery 5, delivered", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let merge = app.buttons["mergePickupPlaceButton"]
        XCTAssertTrue(scrollTo(merge, in: app))
        XCTAssertEqual(merge.label, "Merge pickup place, \(Self.diner)")
        merge.tap()
        let destination = app.buttons
            .matching(identifier: "pickupPlaceMergeDestinationButton")
            .matching(NSPredicate(format: "label == %@", "Merge \(Self.diner) into \(Self.renamedNoodles)"))
            .firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "The direction is spoken in full")
        destination.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let spoken = confirmation.label + " " + confirmation.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(spoken.contains("will move to"), "The deliveries move: \(spoken)")
        XCTAssertFalse(spoken.lowercased().contains("deliveries will be deleted"), "Nothing is destroyed")
        confirmation.buttons.matching(identifier: "confirmPickupPlaceMergeButton").firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(of: summary), "The merged-away place closes with it")

        let moved = deliveryRow(containing: "Delivery 5, delivered", in: app)
        XCTAssertTrue(waitForLabel(moved, toContain: "Picked up from \(Self.renamedNoodles)"))
        XCTAssertTrue(moved.label.contains("Waited at pickup 20 minutes"), "Keeping its own record")
        openPickupHistory(from: "Delivery 5, delivered", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("median of 4 recorded pickups"), "Showed: \(summary.label)")
        XCTAssertTrue(summary.label.contains("Typical recorded pickup wait, 16 minutes"), "Showed: \(summary.label)")
        XCTAssertTrue(
            summary.label.contains("Shortest recorded wait 6 minutes") && summary.label.contains("longest 41 minutes"),
            "The spread spans both places' waits: \(summary.label)"
        )
    }

    /// Parked at a pickup with the setting on, the driver's own Picked Up
    /// resumes driving, says why, and one Undo takes back the pickup and the
    /// driving together.
    @MainActor
    func testPickedUpWhileParkedResumesDrivingAndUndoParksAgain() throws {
        let app = launchWithEmptyStore()
        openSettings(in: app)
        setSwitch("resumeAfterProgressToggle", to: true, in: app)
        goBack(in: app)

        startShiftAndDelivery(in: app)
        let action = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(action, in: app))
        XCTAssertTrue(waitForLabel(action, toContain: "Mark arrived at pickup"))
        tapWithinReach(action, in: app)
        XCTAssertTrue(waitForLabel(action, toContain: "Mark order picked up"))

        pressPark(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["parkedShiftNotice"].waitForExistence(timeout: 5))

        XCTAssertTrue(scrollUntilHittable(action, in: app))
        action.tap()

        let notice = app.staticTexts["parkedProgressNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "The driver is told what their setting did")
        XCTAssertTrue(notice.label.contains("Delivery 1 picked up. Driving resumed by your"), notice.label)
        XCTAssertFalse(notice.label.lowercased().contains("detected"), notice.label)
        // The shift's header is above the card the journey scrolled to, and a
        // list does not render what is scrolled off its top.
        XCTAssertTrue(
            scrollToTop(reaching: app.buttons["parkShiftButton"], in: app),
            "The vehicle is driving: Park is offered again"
        )
        XCTAssertFalse(app.buttons["resumeDrivingButton"].exists)

        let undo = app.buttons["undoParkedProgressButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertEqual(
            undo.label,
            "Undo Picked Up for Delivery 1, and go back to parked. Route recording stops again."
        )
        undo.tap()

        XCTAssertTrue(app.buttons["resumeDrivingButton"].waitForExistence(timeout: 5), "Parked again")
        XCTAssertTrue(waitForLabel(action, toContain: "Mark order picked up"), "And the pickup is taken back")
        XCTAssertTrue(waitForLabel(notice, toContain: "Undid Picked Up for Delivery 1"), notice.label)
        XCTAssertFalse(app.buttons["undoParkedProgressButton"].exists, "The offer goes once taken")
    }

    /// The Delivered Undo leaves after its window without moving the next
    /// delivery's button: measured on the button's own frame, before and after.
    @MainActor
    func testDeliveredUndoLeavingMovesNoDeliveryCard() throws {
        let app = launchWithActiveDelivery()

        let carrying = deliveryButton("deliveryActionButton", containing: "Delivery 3", in: app)
        XCTAssertTrue(scrollUntilHittable(carrying, in: app))
        carrying.tap()

        let banner = app.staticTexts["undoDeliveredBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let next = deliveryButton("deliveryActionButton", containing: "Delivery 2", in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: 1),
            "Delivery 3's card is gone, so only the movement the Undo causes is left to measure"
        )
        XCTAssertTrue(
            next.isHittable || scrollUpUntilHittable(next, in: app, maxSwipes: 6),
            "The next delivery's step is on screen to be measured"
        )
        let before = next.frame

        XCTAssertTrue(waitForDisappearance(of: banner, timeout: 30), "The Undo leaves after its window")
        XCTAssertEqual(next.frame, before, "Leaving moved the next delivery's button: \(before) to \(next.frame)")
        XCTAssertTrue(next.isHittable)
    }

    // MARK: Same pickup and same drop-off

    /// Starts an offer of `count` from the sheet, with the two switches as
    /// asked, and waits for its cards.
    @MainActor
    private func startOffer(
        of count: Int = 2,
        samePickup: Bool = false,
        sameDropOff: Bool = false,
        expectingCards total: Int,
        in app: XCUIApplication
    ) {
        let offerControl = app.buttons["startOfferButton"]
        XCTAssertTrue(scrollTo(offerControl, in: app))
        XCTAssertTrue(scrollUntilHittable(offerControl, in: app))
        offerControl.tap()

        let confirm = app.buttons["confirmStartOfferButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        // The stepper's second button is its increment; it carries no stable
        // identifier of its own.
        let stepper = app.steppers["offerDeliveryCountStepper"]
        for _ in 2..<max(count, 2) {
            stepper.buttons.element(boundBy: 1).tap()
        }
        XCTAssertEqual(stepper.value as? String, "\(max(count, 2))", "The sheet records the count asked for")
        let pickup = app.switches["offerSamePickupToggle"]
        let dropOff = app.switches["offerSameDropOffToggle"]
        XCTAssertEqual(pickup.value as? String, "0", "Independent unless the driver says otherwise")
        XCTAssertEqual(dropOff.value as? String, "0")
        if samePickup { setSwitch("offerSamePickupToggle", to: true, in: app) }
        if sameDropOff { setSwitch("offerSameDropOffToggle", to: true, in: app) }

        XCTAssertTrue(scrollUntilHittable(confirm, in: app))
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: confirm), "The sheet is gone before the panel is read")
        XCTAssertTrue(waitForCount(app.buttons.matching(identifier: "deliveryActionButton"), toEqual: total))
    }

    /// An offer is recorded as independent by default; saying Same pickup and
    /// Same drop-off on the sheet is shown on the heading and on each card, as
    /// something the driver recorded.
    @MainActor
    func testAnOfferIsIndependentUnlessMarkedSamePickupAndDropOff() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()
        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))

        startOffer(expectingCards: 2, in: app)
        let independent = app.descendants(matching: .any)["offerGroupHeader"]
        XCTAssertTrue(scrollTo(independent, in: app))
        XCTAssertFalse(independent.label.contains("same"), "Accepted together says nothing about a stop: \(independent.label)")
        assertCard("Delivery 1", says: "heading to the pickup", in: app)
        XCTAssertFalse(deliveryStatusCard(named: "Delivery 1", in: app).label.contains("You recorded it as"))

        XCTAssertTrue(scrollToTop(reaching: app.buttons["startDeliveryButton"], in: app))
        startOffer(samePickup: true, sameDropOff: true, expectingCards: 4, in: app)

        let headers = app.descendants(matching: .any).matching(identifier: "offerGroupHeader")
        let shared = headers.matching(NSPredicate(format: "label CONTAINS %@", "Offer 2")).firstMatch
        XCTAssertTrue(scrollTo(shared, in: app))
        XCTAssertTrue(shared.label.contains("same pickup and drop-off"), "Showed: \(shared.label)")
        let card = deliveryStatusCard(named: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(card, in: app))
        XCTAssertTrue(
            card.label.contains("You recorded it as the same pickup and drop-off as Delivery 4"),
            "Showed: \(card.label)"
        )
    }

    /// Two deliveries marked Same pickup move together under Park and Resume
    /// Driving, one Undo takes back both, and each card's own step still works.
    @MainActor
    func testSamePickupMovesTogetherAndUndoesTogether() throws {
        let app = launchWithEmptyStore()
        // Stacked orders off: two deliveries the driver said share one pickup
        // are one stop, so the workflow still acts.
        setPickupWorkflow(true, stackedOrders: false, in: app)
        app.buttons["startShiftButton"].tap()
        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        startOffer(samePickup: true, expectingCards: 2, in: app)

        pressPark(in: app)
        let parked = assertPickupWorkflowNotice(contains: "Deliveries 1 and 2 marked Arrived at Pickup", in: app)
        XCTAssertTrue(parked.label.contains("you marked Same pickup"), parked.label)
        assertCard("Delivery 1", says: "waiting at the pickup", in: app)
        assertCard("Delivery 2", says: "waiting at the pickup", in: app)

        let undo = app.buttons["undoPickupWorkflowStepButton"]
        XCTAssertTrue(scrollUpUntilHittable(undo, in: app, maxSwipes: 6))
        XCTAssertTrue(undo.label.contains("Undo Arrived at Pickup for Deliveries 1 and 2"), undo.label)
        undo.tap()
        assertPickupWorkflowNotice(contains: "Undid Arrived at Pickup for Deliveries 1 and 2", in: app)
        XCTAssertTrue(app.buttons["resumeDrivingButton"].exists, "The vehicle is still parked")
        assertCard("Delivery 1", says: "heading to the pickup", in: app)
        assertCard("Delivery 2", says: "heading to the pickup", in: app)

        pressResumeDriving(in: app)
        pressPark(in: app)
        assertPickupWorkflowNotice(contains: "Deliveries 1 and 2 marked Arrived at Pickup", in: app)
        pressResumeDriving(in: app)
        assertPickupWorkflowNotice(contains: "Deliveries 1 and 2 marked Picked Up", in: app)
        assertCard("Delivery 1", says: "heading to the customer", in: app)
        assertCard("Delivery 2", says: "heading to the customer", in: app)

        let undoPickup = app.buttons["undoPickupWorkflowStepButton"]
        XCTAssertTrue(scrollUpUntilHittable(undoPickup, in: app, maxSwipes: 6))
        undoPickup.tap()
        assertPickupWorkflowNotice(contains: "Undid Picked Up for Deliveries 1 and 2", in: app)
        XCTAssertTrue(app.buttons["parkShiftButton"].exists, "The vehicle is still driving")

        // The manual workflow is untouched: one card's own step moves one
        // delivery and leaves its sibling.
        let first = deliveryButton("deliveryActionButton", containing: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(scrollUntilHittable(first, in: app))
        XCTAssertTrue(revealAboveBottomBar(first, in: app), "The card's step is clear of the Undo line")
        first.tap()
        assertCard("Delivery 1", says: "heading to the customer", in: app)
        assertCard("Delivery 2", says: "waiting at the pickup", in: app)
    }

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
        XCTAssertTrue(row("Delivery 2").waitForExistence(timeout: 5))
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
        XCTAssertTrue(row("Delivery 2").waitForExistence(timeout: 5))
        row("Delivery 2").tap()
        app.buttons["separatePickupButton"].tap()
        XCTAssertTrue(waitForLabel(message, toContain: "no longer marked same pickup"), "Showed: \(message.label)")
        XCTAssertFalse(row("Delivery 3").label.contains("same pickup"), "A pair left with one shares nothing")
        app.buttons["doneEditingStackButton"].tap()
    }

    /// Part of an offer is marked Same pickup in Correct Grouping; one delivery
    /// alone cannot be saved, and the third stays independent.
    @MainActor
    func testCorrectingWhichDeliveriesShareAPickup() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()
        XCTAssertTrue(app.buttons["startDeliveryButton"].waitForExistence(timeout: 5))
        startOffer(of: 3, expectingCards: 3, in: app)

        let correct = app.buttons["correctOffersButton"]
        XCTAssertTrue(scrollTo(correct, in: app))
        correct.tap()
        let sharedStops = app.buttons["offerCorrectionSharedStopsButton"]
        XCTAssertTrue(sharedStops.waitForExistence(timeout: 5))
        XCTAssertEqual(sharedStops.value as? String, "Independent")
        sharedStops.tap()

        func row(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "sharedPickupRow", "\(name),"))
                .firstMatch
        }
        let save = app.buttons["saveSharedStopsButton"]
        XCTAssertTrue(row("Delivery 1").waitForExistence(timeout: 5))
        row("Delivery 1").tap()
        XCTAssertFalse(save.isEnabled, "One delivery shares a stop with nobody")
        XCTAssertTrue(
            app.descendants(matching: .any)["sharedStopsMessage"].label.contains("Choose one more delivery for Same pickup"),
            "Says why Save is not available"
        )
        row("Delivery 2").tap()
        XCTAssertEqual(row("Delivery 2").value as? String, "Chosen")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(sharedStops.waitForExistence(timeout: 5), "Back to the list once saved")
        XCTAssertEqual(sharedStops.value as? String, "Some deliveries share a stop")
        app.buttons["closeOfferCorrectionButton"].tap()
        XCTAssertTrue(waitForDisappearance(of: sharedStops))

        let first = deliveryStatusCard(named: "Delivery 1", in: app)
        XCTAssertTrue(scrollTo(first, in: app))
        XCTAssertTrue(first.label.contains("same pickup as Delivery 2"), "Showed: \(first.label)")
        let third = deliveryStatusCard(named: "Delivery 3", in: app)
        XCTAssertTrue(scrollTo(third, in: app))
        XCTAssertFalse(third.label.contains("You recorded it as"), "Showed: \(third.label)")
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
        XCTAssertTrue(card.waitForExistence(timeout: 5))
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
        XCTAssertTrue(control.waitForExistence(timeout: 5), "\(identifier) is on the card", file: file, line: line)
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

    // MARK: What each stacked delivery is waiting for

    // MARK: Reminders about a lifecycle event that may have gone unrecorded

    // MARK: Offers containing several deliveries

    // MARK: The pinned delivery entry

    /// Recording a newly accepted order is reachable from wherever Home has
    /// been scrolled to, and says Add Delivery once one is already in progress.
    ///
    /// The bar is in the list's bottom safe area, so it is found without any
    /// scrolling back, its two controls read wide one first, and each records
    /// what it says.
    @MainActor
    func testDeliveryEntryStaysReachableWhileHomeScrolls() throws {
        let app = launchWithEmptyStore()
        app.buttons["startShiftButton"].tap()

        let start = app.buttons["startDeliveryButton"]
        let several = app.buttons["startOfferButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertTrue(
            app.descendants(matching: .any)["routeCaptureStatus"].exists,
            "Home was scrolled down to the shift's own context"
        )
        XCTAssertTrue(start.isHittable, "Start Delivery is reachable without scrolling back")
        XCTAssertTrue(several.isHittable, "So is the offer of several")
        XCTAssertEqual(start.label, "Start delivery")
        XCTAssertLessThan(start.frame.minX, several.frame.minX, "One delivery leads, several follows")
        XCTAssertEqual(start.frame.midY, several.frame.midY, accuracy: 4, "Both are one row")
        XCTAssertGreaterThanOrEqual(onPixelGrid(start.frame.height), 44)
        XCTAssertGreaterThanOrEqual(onPixelGrid(several.frame.height), 44)
        attachScreenshot("home-entry-bar-scrolled")

        start.tap()
        assertDeliveriesInProgress("1 delivery in progress", in: app)

        for _ in 0..<8 { app.swipeUp() }
        XCTAssertTrue(start.isHittable, "With a delivery in progress the control is still there")
        XCTAssertEqual(start.label, "Add another delivery", "And says it adds one")
        start.tap()
        assertDeliveriesInProgress("2 deliveries in progress", in: app)
    }

    /// Reads the deliveries panel's own count from the top of Home. Cards
    /// scrolled out of view are not in the hierarchy, so counting their
    /// buttons from wherever the journey has scrolled to undercounts.
    @MainActor
    private func assertDeliveriesInProgress(_ statement: String, in app: XCUIApplication) {
        let status = app.descendants(matching: .any)["deliveryStatus"]
        XCTAssertTrue(scrollToTop(reaching: status, in: app), "The deliveries panel is on screen")
        XCTAssertTrue(waitForLabel(status, toContain: statement), "Showed: \(status.label)")
    }

    /// At the largest accessibility text size the bar still leaves every row
    /// reachable: the last thing on Home can be scrolled wholly above it, and
    /// the sheet's switches stay usable above its own pinned action.
    @MainActor
    func testTheEntryBarsCoverNothingAtTheLargestTextSize() throws {
        let app = launchWithEmptyStore(textSize: Self.accessibilityXXXLTextSize)
        let startShift = app.buttons["startShiftButton"]
        XCTAssertTrue(startShift.waitForExistence(timeout: 10))
        startShift.tap()

        let start = app.buttons["startDeliveryButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let last = app.descendants(matching: .any)["emptyHistoryNotice"]
        for _ in 0..<25 where !(last.exists && last.isHittable && last.frame.maxY <= start.frame.minY) {
            app.swipeUp()
        }
        XCTAssertTrue(last.exists, "Home's last row was reached")
        XCTAssertLessThanOrEqual(
            last.frame.maxY,
            start.frame.minY,
            "The last row scrolls wholly above the bar rather than staying under it"
        )
        XCTAssertTrue(start.isHittable)
        attachScreenshot("home-entry-bar-ax5")

        app.buttons["startOfferButton"].tap()
        let confirm = app.buttons["confirmStartOfferButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        setSwitch("offerSamePickupToggle", to: true, in: app)
        let dropOff = app.switches["offerSameDropOffToggle"]
        setSwitch("offerSameDropOffToggle", to: true, in: app)
        XCTAssertLessThanOrEqual(dropOff.frame.maxY, confirm.frame.minY, "The switch was used above the action")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable, "Start stays reachable at this size")
        attachScreenshot("offer-sheet-ax5")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: confirm))
        assertDeliveriesInProgress("2 deliveries in progress", in: app)
    }

    // MARK: Correcting which deliveries arrived together

    /// A store holding an offer with no deliveries is read, stated, and
    /// corrected around.
    @MainActor
    func testCorrectionReadsAnOfferHoldingNoDeliveries() throws {
        let app = launchWithMalformedOffer()

        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 15), "The seeded shift is running")

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

        XCTAssertTrue(app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 15), "The seeded shift is running")

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
                onPixelGrid(action.frame.height),
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
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["exportAllHistoryButton"].exists, "No completed shift, so no history export")
        start.tap()

        XCTAssertTrue(app.buttons["pauseShiftButton"].waitForExistence(timeout: 5), "The shift is running")
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
        XCTAssertTrue(app.buttons["resumeShiftButton"].waitForExistence(timeout: 5), "and now it is paused")
        for identifier in ["editShiftPauseButton", "deleteShiftPauseButton", "addMissedPauseButton"] {
            XCTAssertFalse(
                app.buttons[identifier].exists,
                "\(identifier) is not offered on a paused shift either: the open pause is Resume's and End's"
            )
        }
        app.buttons["resumeShiftButton"].tap()

        let startDelivery = app.buttons["startDeliveryButton"]
        XCTAssertTrue(startDelivery.waitForExistence(timeout: 5))
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

    // MARK: Correcting a shift's end time

    // MARK: Correcting a completed delivery's recorded times

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
        enter("9.50", into: field, in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()

        XCTAssertTrue(waitForLabel(row, toContain: "$9.50"), "The edited amount replaces the previous one")
        XCTAssertFalse(row.label.contains("$14.75"))
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

    // MARK: Expected pay

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
            tapWithinReach(action, in: app)
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
        tapWithinReach(change, in: app)
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

    // MARK: Pickup wait history

    // MARK: Correcting a pickup place

    // MARK: Deletion

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

    // MARK: Estimated fuel

    // MARK: Estimated net

    // MARK: Period estimated fuel

    /// At the largest accessibility text size the period's figures stack
    /// rather than truncate, each is reachable whole, and each still carries
    /// the qualification that keeps it honest.
    ///
    /// The figures are walked to in screen order, one swipe at a time from the
    /// top, stopping at each as soon as it is hittable, so no fixed number of
    /// swipes is part of the claim. How many it took is recorded as an activity
    /// on the result, which is how the section footers' cost was measured
    /// before and after they were shortened.
    @MainActor
    func testThePeriodSummarySurvivesTheLargestTextSize() throws {
        let app = launchWithPeriodSummary(atTextSize: Self.accessibilityXXXLTextSize)
        // At this size the link sits below the running panel, so it is scrolled
        // to rather than assumed to be on screen.
        let link = app.buttons["periodSummaryLink"]
        XCTAssertTrue(scrollUntilHittable(link, in: app, maxSwipes: 25), "History offers a way into the summaries")
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["periodTitle"].waitForExistence(timeout: 10))

        var swipes = 0
        func reach(_ identifier: String) -> XCUIElement {
            let element = app.descendants(matching: .any)[identifier]
            while !element.isHittable, swipes < 60 {
                app.swipeUp()
                swipes += 1
            }
            XCTContext.runActivity(named: "\(identifier) reached after \(swipes) swipes") { _ in }
            XCTAssertTrue(element.isHittable, "\(identifier) is reachable")
            return element
        }

        let earnings = reach("periodEarnings")
        XCTAssertTrue(waitForLabel(earnings, toContain: "Recorded gross earnings"), "Showed: \(earnings.label)")
        XCTAssertTrue(earnings.label.contains("1 of 2"), "Partial coverage is spoken with the figure: \(earnings.label)")
        XCTAssertGreaterThan(onPixelGrid(earnings.frame.height), 44, "The headline is never a clipped single line")
        attachScreenshot("period-summary-xxxl")

        let rate = reach("periodWorkingHourRate")
        XCTAssertTrue(rate.label.contains("gross earnings per working hour"), "Showed: \(rate.label)")

        let mileage = reach("periodMileage")
        XCTAssertTrue(mileage.label.hasPrefix("Recorded mileage"), "Recorded, never driven: \(mileage.label)")
        XCTAssertTrue(mileage.label.contains("partial"), "Partial capture is spoken with it: \(mileage.label)")

        let wait = reach("periodPickupWait")
        XCTAssertTrue(wait.label.contains("Median recorded pickup wait"), "Showed: \(wait.label)")

        let fuel = reach("periodEstimatedFuel")
        XCTAssertTrue(fuel.label.contains("1 of 2 completed shifts"), "Its coverage survives: \(fuel.label)")
        XCTAssertTrue(fuel.label.localizedCaseInsensitiveContains("estimate"), "And it is an estimate: \(fuel.label)")
    }

    // MARK: The running shift's vehicle

    // MARK: The next shift's vehicle

    // MARK: Correcting the running shift's vehicle

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
        XCTAssertTrue(
            waitForFieldValue(field, toEqual: text),
            "The field should hold what was typed, not \(existing) with it prepended or appended"
        )
    }

    // MARK: Target hourly earnings

    // MARK: The completed shift's hierarchy

    // MARK: Settings hierarchy

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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
            enter(milesPerGallon, into: field, in: app)
        }
        if let gasPrice {
            let field = app.textFields["fuelGasPriceField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            enter(gasPrice, into: field, in: app)
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
        enter(milesPerGallon, into: economyField, in: app)

        let priceField = app.textFields["fuelGasPriceField"]
        clear(priceField, in: app)
        enter(gasPrice, into: priceField, in: app)

        app.buttons["saveFuelAssumptionsButton"].tap()
        XCTAssertTrue(
            app.buttons["editFuelAssumptionsButton"].waitForExistence(timeout: 5),
            "The sheet closes once the pair is recorded"
        )
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
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        // Back to the top first: returning from a pushed screen keeps the
        // list where it was, which can leave Start under the navigation bar.
        XCTAssertTrue(scrollToTop(reaching: startButton, in: app))
        startButton.tap()

        let endButton = app.buttons["endShiftButton"]
        XCTAssertTrue(
            app.descendants(matching: .any)["activeShiftStatus"].waitForExistence(timeout: 5),
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
        XCTAssertTrue(element.waitForExistence(timeout: 5), "The control is on the panel")
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
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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

    /// Records an amount against the first finished delivery on screen.
    @MainActor
    private func recordDeliveryAmount(_ text: String, in app: XCUIApplication) {
        app.buttons["shiftDetailDeliveryEarningsButton"].firstMatch.tap()
        typeDeliveryAmount(text, in: app)
        app.buttons["saveDeliveryEarningsButton"].tap()
        // Gone, not merely saved: a caller reads the row behind the sheet next,
        // and a row read while the sheet is still animating away can be read
        // before it shows what was saved. The same race `addTip` closes.
        XCTAssertTrue(
            waitForDisappearance(of: app.textFields["deliveryEarningsAmountField"]),
            "The earnings sheet closes back to the shift"
        )
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
        enter(amount, into: field, in: app)

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
        enter(text, into: field, in: app)
    }

    /// Types an amount into the expected-pay sheet's only field.
    ///
    /// The editor focuses the field itself, so the tap is about which element
    /// the keystrokes reach rather than about raising a keyboard.
    @MainActor
    private func typeExpectedPay(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["deliveryExpectedEarningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        enter(text, into: field, in: app)
    }

    @MainActor
    private func type(_ text: String, into app: XCUIApplication) {
        let field = app.textFields["earningsAmountField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The field is on screen")
        if !hasKeyboardFocus(field) {
            field.tap()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                object: field
            )
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "The field took the keyboard")
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
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let value = (element.value as? String) ?? ""
            if expected.isEmpty { return value.isEmpty || value == element.placeholderValue }
            return value == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        return XCTWaiter().wait(for: [expectation], timeout: Self.conditionTimeout) == .completed
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
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The field is on screen")
        if !hasKeyboardFocus(field) {
            field.tap()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                object: field
            )
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "The field took the keyboard")
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
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
        return XCTWaiter().wait(for: [expectation], timeout: Self.conditionTimeout) == .completed
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, toEqual count: Int) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count),
            object: query
        )
        return XCTWaiter().wait(for: [expectation], timeout: Self.conditionTimeout) == .completed
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
        guard row.waitForExistence(timeout: 5) else { return nil }
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
        enter(amount, into: field, in: app)

        app.buttons["saveExpenseButton"].tap()
        // The list is behind a sheet until the save dismisses it, and a tap
        // synthesised during that animation lands on nothing.
        XCTAssertTrue(
            app.buttons["saveExpenseButton"].waitForNonExistence(timeout: 5),
            "The editor closes once the expense is recorded"
        )
    }

    // MARK: What a running shift says about recording

}
