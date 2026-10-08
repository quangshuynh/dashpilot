# UI suite audit and CI

DashPilot's UI suite is **36 essential journeys**, and every pull request runs all of them after the
build and the whole domain suite. This page records why the suite has that shape: what the red runs
before it had in common, how each of the 82 journeys it replaced was classified, which product risk
each remaining journey covers and which domain or integration suite covers the rest, and the CI that
runs it. The rules for writing a journey are on [Testing](testing.md#ui-journeys).

## What the red runs had in common

Every full run of the previous 82-journey suite failed one journey, and never the same one:

| Run | Journey | What the result bundle showed | Cause |
| --- | --- | --- | --- |
| PR #72 (CI 37406553879) | `testCorrectingGroupingOnARunningShift` | The split-out delivery's offer was assumed to be Offer 2; offers renumber by acceptance time, so a tie decided it | Incorrect test assumption, fixed by reading the number |
| `main` after #73 (37418449153) | two History journeys | A 5 s wait spent on one 4.2 s reading and its retry; an alert's Cancel tapped and the screen behind it read before the alert had closed | One slow accessibility reading against a short budget |
| `main` after #74 (37478065976) | `testDeletingACompletedShiftIsConfirmed` | One reading of the History row took 25 s of an 8 s still-frame wait | One slow reading against a short budget |
| PR #75 (CI 37525485173) | `testActiveDeliveriesBlockEndingUntilEachIsResolved` | `Cancel Delivery 2` tapped at the centre of its frame (201, 489) on a dialog up for twenty seconds; the recording shows the dialog still up to the end. The query before the tap took 16.6 s | A synthesized tap the app never received, under load |
| `v0.1.1` tag (37614136154) | `testDeletingAndAddingPauses` | The time wheels' popover closed at the first tap (recording), then the wait's only reading of it took 14.3 s of its 15 s budget, and the wait failed | One slow reading against a short budget |

The same commit, `df08e48`, ran the full suite green on `main` (37525515201, 6,268 s) and red on the
tag (37614136154, 5,895 s). Nothing in the product differed between them.

**The systemic cause is the simulator's own background work, multiplied by the number of steps.** In
run 37614136154 the 82 journeys made 8,849 XCTest steps, of which 93 took 5 s or more; the stalls
clustered at run positions 1 to 10 and 31 to 40, and the failing journey was position 33. The
bundle's system log shows `mediaanalysisd` busy from 12:19 to 12:24 UTC, which is exactly the
failing journey's 12:18:56 to 12:23:13; in the PR run, `searchd` and `mediaanalysisd` were busy from
20:34 to 20:37, around that failure. The app answered every request promptly throughout: the time
went between the runner and the simulator. Each previous fix strengthened the one helper that
happened to be on screen during a stall, and the next stall found another. The two levers that do
not depend on where the next stall lands are fewer steps, and waits whose verdict cannot rest on one
slow reading.

What was ruled out, on the same evidence: a product regression (every recording shows the app doing
the right thing), fixture contamination (each launch builds its own in-memory store), accumulated
simulator state (no degradation with run length; failures at positions 2, 22, 32 and 33), and test
ordering (XCTest runs alphabetically, and no journey depends on another). Sharding across fresh
simulators was rejected: each fresh simulator starts its own first-boot indexing, which is when the
first journeys stall.

### What changed in the helpers

- **Every condition wait comes through `waitUntil`**, whose verdict rests on at least two readings,
  the second begun after the first returned. A slow reading no longer fails a wait; a condition that
  is still false when looked at again still does. It only reads the screen and never taps again.
  `waitForExistence(timeout: 5)` became `appears()`, under the same rule and the same
  `conditionTimeout` every other condition wait already had.
- **Every confirmation tap goes through `tapClosingDialog`**, which waits for the dialog to close and
  fails there, naming the button, when iOS did not act on the tap. It does not tap again: a second tap
  would hide the thing the run has to report.
- **A failing assertion attaches the screen at that moment** to the issue itself, so a red run is
  read at the failing step rather than by scrubbing a recording.

None of these is a sleep, a retry of an action, or a looser assertion.

## How each journey was classified

| Class | Meaning | What happened to it |
| --- | --- | --- |
| A. Essential UI automation | Needs a running app: a flow across screens and sheets, a confirmation guarding a write, navigation, persistence across a relaunch, onboarding, the Live Activity, the largest text size on a critical surface | Kept, or merged where two journeys drove the same setup |
| B. Better tested below the UI | A figure, rule, wording or state transition a domain or integration test pins | Removed, with the suite that pins it named below; added to the domain suite where nothing did |
| C. Redundant or low-value | Repeats another journey's navigation or interaction, or measures a layout detail of one screen | Removed, with the journey that still exercises the interaction named |

A journey's duration is its median over the last four full runs on the runner (37418449153,
37478065976, 37525515201, 37614136154).

## Journey by journey

| Journey | Class | CI s | Outcome | Unique risk, or where it is covered |
| --- | --- | --- | --- | --- |
| `testAPickupPlaceIsNamedReusedChangedAndRemoved` | A | 76 | Kept | Pickup place entry, reuse, change and removal |
| `testARecordedRouteGrowsFreezesWhilePausedAndLeavesTheBreakOut` | A | 111 | Kept | The real capture pipeline wired to the panel, through a pause |
| `testARunningShiftOffersOnlyWhatItsStateAllows` | A | 28 | Kept | No correction, export or deletion offered while driving |
| `testAShiftExportsAsJSONOrCSV` | A | 43 | Kept | The user-initiated export flow; file contents are `ShiftExportJSONTests` and `ShiftExportCSVTests` |
| `testActiveDeliveriesBlockEndingUntilEachIsResolved` | A | 145 | Kept | Ending refused while work runs; cancelling one delivery |
| `testAddsAnAdditionalTipToAFinishedDelivery` | A | 133 | Merged | Into `testAddsAndEditsDeliveryEarningsAndATipFromDetail` |
| `testAddsAndEditsDeliveryEarningsFromDetail` | A | 99 | Merged | Into `testAddsAndEditsDeliveryEarningsAndATipFromDetail`, which drives the delivery once |
| `testAddsAndEditsEarningsFromDetail` | A | 90 | Kept | Shift money recorded only after driving |
| `testCorrectingAHistoricalCompletionToACancellation` | A | 54 | Kept | A historical correction behind a confirmation |
| `testCorrectingGroupingOnARunningShift` | A | 50 | Kept | Grouping corrections and their confirmations |
| `testCreatesEditsAndSelectsVehicles` | A | 70 | Kept | Settings navigation and vehicle create, edit and select |
| `testDeletingACompletedShiftIsConfirmed` | A | 96 | Kept | The destructive confirmation and backing out |
| `testDeletingAndAddingPauses` | A | 143 | Kept | Deleting a pause behind a confirmation, and adding one |
| `testEditStackMarksSeparateDeliveriesSamePickupWithoutRecreatingThem` | A | 45 | Kept | Editing a stack: the October 3 correction |
| `testExpensesAreRecordedRefusedCorrectedAndSummarised` | A | 66 | Kept | Expense create, refuse, edit and delete, and the cost reaching a day with no shift |
| `testFirstLaunchShowsTheWelcomeOnceAndFinishingItPersists` | A | 25 | Kept | First-launch onboarding and its persistence across a relaunch; when it is shown is `OnboardingPolicyTests` |
| `testHistoryShowsThisWeekWithItsOwnFiguresAndFollowsAnEdit` | A | 100 | Kept | History's week, its figures following an edit, and Export All History |
| `testHomeNamesTheNextShiftsVehicleAndTheShiftKeepsItsOwn` | A | 98 | Kept | Settings reach the next shift and never the running one, read off the screen; snapshot rules are `ShiftVehicleContextTests` and `NextShiftVehicleContextTests` |
| `testLaunchesIntoShiftScreen` | A | 9 | Kept | The on-disk store opens and the app does not land on the persistence failure screen; only a real launch shows it |
| `testLiveActivityLeadsWithParkOnlyUnderTheWorkflow` | A | 78 | Kept | The Live Activity's controls through the activity's own content path |
| `testMonthsHoldTheirDaysStepBackAndSurviveLeavingTheApp` | A | 28 | Kept | Switching and stepping periods, and the selection surviving leaving the app |
| `testOlderWeeksAreGroupedSummarisedAndOpen` | A | 31 | Kept | Navigation into Older Weeks and to an older shift |
| `testOpensTheDetailOfTheTappedShift` | A | 29 | Kept | Tapping a row opens that shift |
| `testParkAndPauseAreDistinctStatesOfTheRunningShift` | A | 87 | Kept | Park against Pause on the running shift |
| `testParkAndResumeRecordThePickupAndUndoTakesEachBack` | A | 86 | Kept | The Park and Resume pickup workflow and its Undo |
| `testRecordsADeliveryThroughItsLifecycle` | A | 54 | Kept | The delivery lifecycle, one tap per event |
| `testRecoveredStackedDeliveriesStayDistinctAndSurviveLeavingTheApp` | A | 27 | Kept | Relaunch recovery of stacked work and its cards |
| `testRemindersStateTheirEvidenceAndAnswerOnlyTheirOwnDelivery` | A | 25 | Kept | A reminder answered from its own card advances only that delivery; staleness is `DeliveryProgressAssistanceTests` |
| `testReopeningADeliveredDeliveryFromTheShiftsRecord` | A | 18 | Kept | Reopening behind a confirmation |
| `testStartsASecondDeliveryWhileTheFirstIsRunning` | A | 21 | Kept | Stacked deliveries as separate cards |
| `testStartsAndEndsAShift` | A | 16 | Kept | The shift lifecycle from Home to History |
| `testTheDaySummaryStatesEachFigureWithItsCoverage` | A | 29 | Kept, and now also exports the day | The period summary reached and read with its coverage wording; the period export check replaces `testEachPeriodExportsItsOwnRecords` |
| `testTheOfferSheetRecordsOneOfferOrNothing` | A | 46 | Kept | The several-delivery sheet records one offer or nothing |
| `testTheRunningShiftAtTheLargestTextSize` | A | 54 | Kept | The driving surface at AX5 |
| `testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs` | A | 198 | Kept | The real recovery: delivery times, then the end, with the route trimmed |
| `testTheWelcomeReopensFromSettingsAtTheLargestTextSize` | A | 54 | Kept | Reopening the welcome at AX5; found a real presentation defect (a cover on a lazily loaded row) |
| `testUndoingADeliveryMarkedDeliveredByMistake` | A | 18 | Kept | The immediate Undo of Delivered |
| `testACompletedShiftsDeliveriesPlacesAndGrouping` | B | 119 | Removed | `DeliveryWordingTests`, `OfferCorrectionServiceTests` (finished shifts allowed); the grouping sheet stays in `testCorrectingGroupingOnARunningShift` |
| `testADayIsComparedWithTheDayBeforeIt` | B | 80 | Removed | `PeriodComparisonTests` (percentage rules, an empty previous period stated, no estimate compared) |
| `testADeliveryAmountCancelledOrRemovedLeavesNothingInvented` | B | 59 | Removed | `DeliveryEarningsTests` (removed is missing, not zero) |
| `testAHistoricalShiftKeepsTheVehicleItRecorded` | B | 75 | Removed | `RecordedShiftVehicleTests`, `FuelAssumptionPersistenceTests` |
| `testALongHistoryIsNewestFirstAndItsOldestShiftIsReachable` | B | 176 | Removed | `HistoryFetchScopeTests` (order and partition); performance is `HistoryFetchScopeMeasurementTests`, which a simulator journey cannot measure. 176 s |
| `testAShiftThatRecordedNothingInventsNoFigures` | B | 22 | Removed | `CompletedShiftWordingTests`, `ShiftMetricsTests` (every unavailable reason) |
| `testAStackedOfferReadsAsOneOfferOfIndependentDeliveries` | B | 46 | Removed | `DeliveryGroupingTests`, `StackedDeliveryStateTests` |
| `testAnEmptyCurrentWeekSaysSoAndKeepsTheOlderWeeksReachable` | B | 23 | Removed | `HistoryWeekTests` (a current week holding nothing is still the current week) |
| `testAnOfferIsIndependentUnlessMarkedSamePickupAndDropOff` | B | 49 | Removed | `SharedStopTests`; the offer sheet stays in `testTheOfferSheetRecordsOneOfferOrNothing` |
| `testCorrectingAShiftThatDashPilotRecordedAsEndingLate` | B | 118 | Removed | `ShiftEndCorrectionTests`, `ShiftEndCorrectionServiceTests`; the end editor and its route confirmation stay in `testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs` |
| `testCorrectingAndRefusingAPauseInTheEditor` | B | 115 | Removed | `ShiftPauseCorrectionTests`, `ShiftPauseCorrectionServiceTests`; the pause editor stays in `testDeletingAndAddingPauses` |
| `testCorrectingPickupPlacesRenamesRefusesAndMerges` | B | 101 | Removed | `PickupPlaceCorrectionTests`, `PickupPlaceServiceTests` |
| `testCorrectingTheRunningShiftsVehicle` | B | 79 | Removed | `RunningShiftFuelCorrectionTests` (one correction, before any distance, Settings untouched) |
| `testCorrectingWhichDeliveriesShareAPickup` | B | 31 | Removed | `SharedStopTests` (one alone refused); Edit Stack stays |
| `testCorrectionReadsAnOfferHoldingNoDeliveries` | B | 16 | Removed | `OfferCorrectionInvarianceTests`, `DeliveryGroupingTests` (an empty offer read and stated) |
| `testDefaultsAreRecordedAtStartAndNeverReachARecordedShift` | B | 420 | Removed | `FuelAssumptionPersistenceTests`, `HourlyTargetTests` (snapshot at start, settings never reach a recorded shift), `VehicleSettingsTests` (use current defaults); the editor's seed order is **new** `FuelAssumptionsSeedTests`. The slowest journey (420 s) |
| `testDeliveringWithoutExpectedPayRaisesNoConfirmation` | B | 30 | Removed | `ExpectedDeliveryEarningsTests` (no expectation, nothing unconfirmed) |
| `testEachDeliveryKeepsItsOwnAmountAndRate` | B | 109 | Removed | `DeliveryEarningsTests` (stacked deliveries' independent amounts and rates), `DeliveryEarningsRate` suites |
| `testEachPeriodExportsItsOwnRecords` | B | 212 | Removed | `MonthAndRangeExportTests` (records per scope); the day export moved into the day summary journey. 212 s |
| `testEditingAndDeletingAnOlderShiftRefreshesItsWeek` | B | 54 | Removed | `HistoryWeekRefreshTests`; a week following an edit stays in `testHistoryShowsThisWeekWithItsOwnFiguresAndFollowsAnEdit` |
| `testExpectedPayIsAnExpectationUntilTheDriverRecordsEarnings` | B | 133 | Removed | `ExpectedDeliveryEarningsTests` (`hasUnconfirmedExpectedEarnings`, counted by nothing). The confirmation sheet itself is no longer driven; see the limitations |
| `testFuelAssumptionsOnAFinishedShift` | B | 90 | Removed | `FuelEstimateTests`, `FuelAssumptionTests`, `ShiftProfitabilityTests` |
| `testFuelAssumptionsSeedTheNextShiftAndItsNetNamesMissingEarnings` | B | 69 | Removed | **New** `FuelAssumptionsSeedTests` (the seed order, which lived only in the view), `FuelAssumptionTests` (`mostRecentFuelAssumptions`) |
| `testOlderWeekSummariesStateTheirFuelCoverageInOrder` | B | 27 | Removed | `HistoryWeekSummaryTests`, `PeriodFuelMetricsTests` |
| `testPickedUpWhileParkedResumesDrivingAndUndoParksAgain` | B | 63 | Removed | `ParkedProgressTests`, `ParkedProgressPersistenceTests` |
| `testPickupAndParkingSettingsAreOffAndKeptAsChosen` | B | 39 | Removed | `ParkResumePickupWorkflowTests`, `ParkedProgressTests` (off by default, inert alone); the switch is driven by `testParkAndResumeRecordThePickupAndUndoTakesEachBack` |
| `testPickupWaitHistoryIsPerPlaceAndStatesItsSample` | B | 57 | Removed | `PickupWaitMetricsTests` and the pickup wait wording suite |
| `testRecordingParkingAndResumingSayWhatTheyDo` | B | 40 | Removed | `LocationTrackingServiceTests`, `RouteSuspensionTests`, `ActiveShiftRouteServiceTests`; Park and Resume stay in `testParkAndPauseAreDistinctStatesOfTheRunningShift` |
| `testSamePickupMovesTogetherAndUndoesTogether` | B | 114 | Removed | `SharedPickupWorkflowTests` (one write, one Undo) |
| `testSettingsStatesItsDefaultsAndRecordsTheGasPrice` | B | 73 | Removed | `VehicleSettingsTests` (price recorded, corrected, removed, zero not missing); the wording is now `CurrentGasPriceWording` in **new** `FuelAssumptionsSeedTests`; Settings navigation stays in `testCreatesEditsAndSelectsVehicles` |
| `testShiftEarningsRefuseWhatCannotBeReadAndInventNoPerMileRate` | B | 38 | Removed | `MoneyInputTests`, `ShiftEarningsTests`, `ShiftMetricsTests` |
| `testTheRecordedShiftsDetailStatesItsTimesRatesAndRoute` | B | 50 | Removed | `ShiftMetricsTests`, `DeliveryActiveTimeTests`, `CompletedShiftWordingTests` |
| `testTheShiftPanelReadsInOrderAndBorrowsNothing` | B | 78 | Removed | `NextShiftVehicleContextTests`, `ShiftVehicleContextTests`, `ActiveShiftMetricsTests`; the panel is read by every running-shift journey |
| `testTheTipsSheetKeepsEachTipItsOwnRecord` | B | 121 | Removed | `DeliveryTipTests`, `DeliveryTipServiceTests`, `DeliveryTipMetricsTests`; the tips sheet stays in the merged money journey |
| `testTheVehicleEditorLabelsItsFieldsAndRefusesWhatItCannotDivideBy` | B | 28 | Removed | `VehicleSettingsTests` (no economy and zero refused, nothing written) |
| `testTheWeekSummaryStatesItsEarningsAndPickupWaitWithTheirBasis` | B | 57 | Removed | `PeriodMetricsTests`, `PickupWaitMetricsTests`; switching periods stays in `testMonthsHoldTheirDaysStepBackAndSurviveLeavingTheApp` |
| `testACompletedShiftAtTheLargestTextSize` | C | 243 | Removed | AX5 layout of the detail (243 s); represented by the running shift and the welcome |
| `testACustomRangeIsChosenCancelledAndKept` | C | 39 | Removed | `MonthAndCustomPeriodTests` holds the range; cancelling a sheet is exercised by every editor journey |
| `testALongVehicleNameAtTheLargestTextSize` | C | 59 | Removed | Text wrapping of one name at AX5; AX5 is represented by the running shift and the welcome |
| `testCompletedDeliveryOffersEveryCorrectionWithRoomToReadIt` | C | 89 | Removed | Width measurements of one grid; each control in it is tapped by the journey for its own correction |
| `testDeliveredUndoLeavingMovesNoDeliveryCard` | C | 37 | Removed | A layout measurement of one transition; Undo itself stays in `testUndoingADeliveryMarkedDeliveredByMistake` |
| `testDeliveryEntryStaysReachableWhileHomeScrolls` | C | 63 | Removed | Every delivery journey reaches the pinned entry bar from a scrolled Home |
| `testHistoryAtTheLargestTextSize` | C | 198 | Removed | Five AX5 cards and a long scroll (198 s); AX5 is represented by the running shift and the welcome |
| `testTheEntryBarsCoverNothingAtTheLargestTextSize` | C | 79 | Removed | AX5 layout; the running shift at AX5 stays |
| `testThePeriodSummarySurvivesTheLargestTextSize` | C | 66 | Removed | AX5 layout; the footers' length is bounded by `PeriodSummaryExplanationTests` |
**New domain coverage.** Two rules lived only in SwiftUI views and were read only by removed journeys,
so they moved into the domain and are pinned by the new `FuelAssumptionsSeedTests`: the order a
finished shift's fuel editor is seeded in (`FuelAssumptionsSeed`: the shift's own pair, then the
current defaults, then the most recent shift's pair, and only the first is not a suggestion), and how
Settings states the current gas price (`CurrentGasPriceWording`: `Not set` for none, `$0.00` for a
recorded zero). Both views now call them; neither behaviour changed.

## Traceability

Each product risk, the journey that drives it through the interface, and the suites that pin its
rules. `ContinuousIntegrationWorkflowTests` fails if a journey is missing from this section or the
section names one that no longer exists.

### Launch, onboarding and persistence

| Risk | Journey | Below the UI |
| --- | --- | --- |
| The real store opens rather than the failure screen | `testLaunchesIntoShiftScreen` | `PersistenceTests`, every migration suite |
| A new driver is welcomed once, and finishing it persists across a relaunch | `testFirstLaunchShowsTheWelcomeOnceAndFinishingItPersists` | `OnboardingPolicyTests` |
| The welcome reopens from Settings and is usable at the largest text size | `testTheWelcomeReopensFromSettingsAtTheLargestTextSize` | `OnboardingPolicyTests` |
| Running work survives leaving and relaunching the app | `testRecoveredStackedDeliveriesStayDistinctAndSurviveLeavingTheApp`, `testMonthsHoldTheirDaysStepBackAndSurviveLeavingTheApp` | `DeliveryPersistenceTests`, `ShiftServiceTests` (relaunch recovery), `RealWorldRecoveryTests` |

### The shift: start, Park, Pause, end

| Risk | Journey | Below the UI |
| --- | --- | --- |
| A shift starts, runs and ends into History | `testStartsAndEndsAShift` | `ShiftTests`, `ShiftServiceTests` |
| Park and Pause stay distinct: parked still runs and takes offers, paused stops working time and deliveries | `testParkAndPauseAreDistinctStatesOfTheRunningShift` | `RouteSuspensionTests`, `ShiftPauseServiceTests`, `ShiftPauseTests` |
| The live route grows, freezes while paused, and records no distance from the break | `testARecordedRouteGrowsFreezesWhilePausedAndLeavesTheBreakOut` | `ActiveShiftRouteServiceTests`, `LocationTrackingServiceTests`, `RouteMileageCalculatorTests` |
| Nothing a driver should not do at the wheel is offered while a shift runs | `testARunningShiftOffersOnlyWhatItsStateAllows` | `ShiftPauseCorrectionServiceTests`, `ShiftEndCorrectionServiceTests`, `HistoricalDeliveryCancellationServiceTests` |
| The driving surface is whole and reachable at the largest text size | `testTheRunningShiftAtTheLargestTextSize` | `DashTypographyTests` |
| Settings reach the next shift and never the one already running | `testHomeNamesTheNextShiftsVehicleAndTheShiftKeepsItsOwn` | `ShiftVehicleContextTests`, `NextShiftVehicleContextTests`, `RecordedShiftVehicleTests`, `FuelAssumptionPersistenceTests`, `HourlyTargetTests` |

### Deliveries and stacked work

| Risk | Journey | Below the UI |
| --- | --- | --- |
| A delivery is recorded through its lifecycle, one named step at a time | `testRecordsADeliveryThroughItsLifecycle` | `DeliveryTests`, `DeliveryServiceTests`, `DeliveryWordingTests` |
| A second delivery runs beside the first as its own card | `testStartsASecondDeliveryWhileTheFirstIsRunning` | `StackedDeliveryStateTests`, `DeliveryActiveTimeTests` |
| The several-delivery sheet records one offer or nothing | `testTheOfferSheetRecordsOneOfferOrNothing` | `DeliveryOfferServiceTests`, `SharedStopTests` |
| An immediate Undo of Delivered, and a reopening behind a confirmation | `testUndoingADeliveryMarkedDeliveredByMistake`, `testReopeningADeliveredDeliveryFromTheShiftsRecord` | `DeliveryRecoveryTests`, `DeliveryRecoveryServiceTests`, `StackedUndoTests` |
| Ending is refused while work runs; a cancellation is confirmed and spares the other delivery | `testActiveDeliveriesBlockEndingUntilEachIsResolved` | `DeliveryServiceTests` (shift-end policy and cancellation) |
| A reminder advances only its own delivery and claims no observation | `testRemindersStateTheirEvidenceAndAnswerOnlyTheirOwnDelivery` | `DeliveryProgressAssistanceTests` |
| Park and Resume record the pickup, and Undo takes each step back | `testParkAndResumeRecordThePickupAndUndoTakesEachBack` | `ParkResumePickupWorkflowTests`, `SharedPickupWorkflowTests`, `AutomatedPickupStepUndoTests`, `ParkedProgressTests` |
| Grouping is corrected on a running shift behind named confirmations | `testCorrectingGroupingOnARunningShift` | `OfferCorrectionServiceTests`, `OfferCorrectionInvarianceTests` |
| Separate deliveries are marked as one stack without being recreated | `testEditStackMarksSeparateDeliveriesSamePickupWithoutRecreatingThem` | `StackEditTests`, `SharedStopTests` |
| The Live Activity's controls follow the driver's setting | `testLiveActivityLeadsWithParkOnlyUnderTheWorkflow` | `ShiftActivityControlPriorityTests`, `ShiftActivityCardLayoutTests`, `ShiftActivityContentTests` |
| A pickup place is named, reused, changed and removed without moving the lifecycle | `testAPickupPlaceIsNamedReusedChangedAndRemoved` | `PickupPlaceServiceTests`, `PickupPlaceNameTests`, `PickupPlaceCorrectionTests`, `PickupWaitMetricsTests` |

### History, detail, corrections and deletion

| Risk | Journey | Below the UI |
| --- | --- | --- |
| History shows this week, follows an edit, and exports everything | `testHistoryShowsThisWeekWithItsOwnFiguresAndFollowsAnEdit` | `HistoryFetchScopeTests`, `HistoryWeekRefreshTests`, `HistoryWeekSummaryTests` |
| Older weeks are reachable and open their own shifts | `testOlderWeeksAreGroupedSummarisedAndOpen` | `HistoryWeekTests`, `HistoryFetchScopeTests` |
| A row opens the shift it names | `testOpensTheDetailOfTheTappedShift` | `ShiftMetricsTests`, `CompletedShiftWordingTests` |
| Deleting a shift is confirmed, and backing out deletes nothing | `testDeletingACompletedShiftIsConfirmed` | `CompletedShiftDeletionTests` |
| A historical completion is corrected to a cancellation behind a confirmation | `testCorrectingAHistoricalCompletionToACancellation` | `HistoricalDeliveryCancellationTests`, `HistoricalDeliveryCancellationServiceTests` |
| A recorded pause is deleted behind a confirmation, and a missed one added | `testDeletingAndAddingPauses` | `ShiftPauseCorrectionTests`, `ShiftPauseCorrectionServiceTests` |
| Delivery times and then the shift's end are corrected, and the route is trimmed only once confirmed | `testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs` | `DeliveryTimeCorrectionTests`, `DeliveryTimeCorrectionServiceTests`, `ShiftEndCorrectionTests`, `ShiftEndCorrectionServiceTests` |

### Money, settings, summaries and export

| Risk | Journey | Below the UI |
| --- | --- | --- |
| Shift earnings are offered only after driving, recorded and edited | `testAddsAndEditsEarningsFromDetail` | `ShiftEarningsTests`, `MoneyInputTests`, `ShiftEarningsPersistenceTests` |
| A delivery's amount and a tip are offered only after driving and keep their own records | `testAddsAndEditsDeliveryEarningsAndATipFromDetail` | `DeliveryEarningsTests`, `DeliveryTipTests`, `DeliveryTipServiceTests`, `DeliveryTipMetricsTests` |
| Expenses are recorded, refused, corrected, deleted and reach the day they belong to | `testExpensesAreRecordedRefusedCorrectedAndSummarised` | `ExpenseTests`, `PeriodExpenseMetricsTests`, `ExpensePersistenceTests` |
| Vehicles are created, edited and selected in Settings | `testCreatesEditsAndSelectsVehicles` | `VehicleSettingsTests`, `VehicleSettingsPersistenceTests`, `FuelAssumptionsSeedTests` |
| A period summary states each figure with its coverage, and exports its own records | `testTheDaySummaryStatesEachFigureWithItsCoverage` | `PeriodMetricsTests`, `PeriodFuelMetricsTests`, `PeriodComparisonTests`, `MonthAndRangeExportTests` |
| A shift exports as JSON or CSV | `testAShiftExportsAsJSONOrCSV` | `ShiftExportJSONTests`, `ShiftExportCSVTests`, `ShiftExportPrivacyTests` |

## What the suite no longer drives

These are covered below the UI but no journey opens their screen, so a defect in the view alone (a
sheet that fails to present, a button wired to the wrong action) would reach a pull request
unnoticed. Each was judged worth that trade against its runtime and its rules' domain coverage; add
a journey back if one of them changes:

- the expected-pay confirmation raised when a delivery carrying an expected amount is delivered;
- the fuel assumptions editor on a finished shift;
- the pickup wait history sheet and the rename and merge screens;
- the running shift's vehicle correction sheet;
- the custom range picker;
- the largest text size on History, the completed shift and the period summary.

## Counts and runtime

| | Before | After |
| --- | --- | --- |
| UI journeys | 82 (26 on every pull request, 56 more after merge) | **36**, all on every pull request |
| Kept as they were | | 35 (one now also exports the day) |
| Merged | | 2 into 1 |
| Removed, covered below the UI (B) | | 36, with 7 new domain tests where nothing pinned the rule |
| Removed as redundant or low-value (C) | | 9 |
| XCTest steps in a full run (run 37614136154) | 8,849 | about 3,600 |
| Full UI suite on the runner, sum of journey medians | 6,257 s (104 min) | about 2,290 s (38 min) |

The essential suite's measured duration is in [Testing](testing.md#how-long-a-run-takes-and-the-budget-it-is-given).

## CI

| Workflow | When | What | Budget |
| --- | --- | --- | --- |
| `ci.yml` | Every pull request, pushes to `main`, Mondays 07:00 UTC, `v*` tags, manual dispatch | Build, the **whole** domain suite, then **every** UI journey, serially | 90 min |

There is no second UI workflow. The previous `ui-regression.yml` existed to run the journeys too
slow for every pull request; every journey that was worth that time is now in the suite every pull
request runs, and the rest are pinned below the UI, so a separate regression run would only repeat
it. The weekly and tag runs keep the reason it ran on a schedule: an image or runtime change is
noticed without a pull request.

`ContinuousIntegrationWorkflowTests` pins the shape: one job, build then the whole domain suite then
the whole UI target, serial, the five triggers, no skip, retry or `continue-on-error`, the bundles
uploaded under `if: always()`, a budget above 60 and at most 120 minutes, the suite at most 40
journeys, and this page's traceability naming exactly the suite.

### Adding a journey

Add one only for a risk the domain suite cannot see: a flow across screens, a confirmation guarding a
write, navigation, state surviving the app's lifecycle, the Live Activity, or a critical surface at
the largest text size. Pin its rules in the domain suite first, add a row to the traceability table,
and raise the ceiling in `ContinuousIntegrationWorkflowTests` deliberately if it is reached.
