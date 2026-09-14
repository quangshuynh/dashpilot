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

    /// Must match `LaunchArgument.seededStackedOffer`, for the same reason.
    private static let seededStackedOfferArgument = "-dashpilot-seeded-stacked-offer"

    /// Must match `LaunchArgument.seededMalformedOffer`, for the same reason.
    private static let seededMalformedOfferArgument = "-dashpilot-seeded-malformed-offer"

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
            rows(in: app).firstMatch.waitForExistence(timeout: 5),
            "The finished shift should appear in history"
        )
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
            rows(in: app).firstMatch.waitForExistence(timeout: 5),
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
    @MainActor
    func testCompletedDeliveryOffersEveryCorrectionWithRoomToReadIt() throws {
        let app = launchWithSeededHistory()
        openFirstShift(in: app)

        // The fixture's first delivery is the one with the whole set: it names a
        // place, that place has recorded history, and it carries an amount.
        let card = deliveryCard(containing: "Delivery 1, delivered", in: app)
        XCTAssertTrue(scrollTo(card, in: app), "The delivery should be listed")

        let place = card.buttons["shiftDetailPickupPlaceButton"]
        let history = card.buttons["shiftDetailPickupHistoryButton"]
        let earnings = card.buttons["shiftDetailDeliveryEarningsButton"]

        // Reaching the last of the three brings the other two with it: they are
        // the two directly above it in the same card.
        XCTAssertTrue(scrollUntilHittable(earnings, in: app), "Every action is reachable by scrolling")

        // Each one still names the delivery it acts on, which is what makes it
        // usable with several cards on screen and nothing to look at.
        XCTAssertEqual(place.label, "Change pickup place for Delivery 1")
        XCTAssertEqual(history.label, "Recorded pickup waits at \(Self.noodles)")
        XCTAssertEqual(earnings.label, "Edit gross earnings for Delivery 1")

        let width = app.windows.element(boundBy: 0).frame.width
        for action in [place, history, earnings] {
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

        // The odd one out keeps its column rather than being stretched across
        // the card, so the left edge is the same down every delivery.
        XCTAssertGreaterThan(earnings.frame.minY, place.frame.maxY - 1, "The third action is on the next line")
        XCTAssertEqual(
            earnings.frame.width,
            place.frame.width,
            accuracy: 1,
            "A line holding one action still holds it in a column"
        )
        XCTAssertEqual(earnings.frame.minX, place.frame.minX, accuracy: 1, "Aligned with the column above it")

        // And the controls still do what they did: the grid changed where they
        // are, not what they open.
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

        XCTAssertTrue(
            scrollUntilHittable(place, in: app, maxSwipes: 30),
            "The actions are reachable at an accessibility size too"
        )

        let width = app.windows.element(boundBy: 0).frame.width
        for action in [place, history, earnings] {
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
        XCTAssertTrue(scrollUntilHittable(earnings, in: app, maxSwipes: 10), "And every action is still tappable")
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

        // The identifier is mirrored onto the label's icon as well as its text,
        // and the icon's label is "Warning", so the sentence is read off the
        // static text rather than off whichever element matches first.
        let message = app.staticTexts.matching(identifier: "expenseValidationMessage").firstMatch
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
