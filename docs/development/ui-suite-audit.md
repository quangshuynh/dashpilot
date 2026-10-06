# UI suite audit and CI tiers

The v0.1.0 merge (October 3, 2026) ran a UI suite of 242 journeys plus four launch-configuration runs
for **2h31m**, 2h23m of it in the UI step, on every pull request and every push to `main`, and both
runs were red. This page records what the failures were, how every journey was classified, what
moved where in two passes, why each remaining journey needs the interface, and the CI shape that came
out of it. The rules for writing journeys are on
[Testing](testing.md#ui-journeys).

## The two red runs, diagnosed

Both runs used the runner image's newest Xcode, **26.6** (17F113), on an **iPhone 17, iOS 26.5**
simulator. Each failed exactly one journey, and a different one.

| Run | Journey | What the result bundle showed | Cause |
| --- | --- | --- | --- |
| `main` 37088088371 | `testChangesAPickupPlace` | The helper read `Now` out of the field after deleting 15 characters; the recording shows the field empty, placeholder back, a moment later | The helper read the field **once**, while the delete keystrokes were still arriving |
| PR 37088082650 | `testChangingSettingsMidShiftLeavesTheRunningShiftsVehicleAlone` | The tap selected the vehicle (the recording shows `Default` on it by 73 s); finding the row took 5.3 s and the tap 8.8 s; the 5-second wait for `Selected` expired after a single stale evaluation | One accessibility query on the loaded runner took longer than the wait |

Neither is a product regression, a stale assumption or toolchain drift: both are journeys reading
the screen at one instant on a runner under load. The fix is in the shared helpers, not the journeys:

- `enter`, `clear` and `replaceTappedField` **wait for the field's final value** instead of reading
  it once (`waitForFieldValue`).
- Condition waits use `conditionTimeout`, **15 s**: three of the slowest snapshots measured. A wait
  returns the moment its condition holds, so a passing run pays nothing for it. It is not a sleep and
  not a retry.

The `IDELaunchParametersSnapshot ... DebuggerVersionStore.StoreError` / `no debugger version` lines
and the WebKit/WebCore accessibility duplicate-class warnings appear **252 times in each log, once
per app launch, in passing journeys as much as failing ones**. They are toolchain noise and nothing
in the product was changed for them.

### Xcode is not pinned

The workflow takes the newest installed Xcode whose iOS simulator SDK meets the deployment target,
and prints its version; local validation uses Xcode 27.0 with the same iOS 26.5 simulator runtime.
Neither failure involved the toolchain, so pinning would have changed nothing and would have to be
maintained against the runner image. Revisit if a failure is ever traced to an Xcode change.

## Classification

Every journey was put in one of six classes, using its body, its launch fixture, the domain tests
that already cover its rule, and its duration in run 37088088371.

| Class | Meaning | What happened to it |
| --- | --- | --- |
| 1. Critical end-to-end journey | A regression here stops a driver working | Kept, and listed in the smoke tier |
| 2. Unique interaction behaviour | Only the interface can show it: navigation, focus, text size, reach, VoiceOver labels | Kept in the full suite |
| 3. Better tested below the UI | A figure or rule the domain suite already pins exactly | Consolidated into one journey per screen that reads wording and coverage, not arithmetic |
| 4. Redundant with another journey | Same launch, same screen, one assertion each | Merged |
| 5. Low-value detail | No assertion, or a measurement nothing reads | Removed |
| 6. Expensive setup | Spends most of its time reaching the state it tests | Given a seeded fixture |

## First pass: repetition and template tests

| Change | Journeys | Why |
| --- | --- | --- |
| **Removed** `DashPilotUITestsLaunchTests.testLaunch` (four runs, one per appearance and orientation) | 4 runs, 26 s | Xcode template: screenshots only, no assertion. `testLaunchesIntoShiftScreen` proves the real store opens |
| **Removed** `testLaunchPerformance` | 1, 32 s | Xcode template: `measure` with no baseline, which never fails |
| **Consolidated** the Day period summary journeys into `testTheDaySummaryStatesEachFigureWithItsCoverage` | 8 → 1 | Each launched the same fixture to read one figure; the figures are pinned in `PeriodMetricsTests`, `PeriodExpenseMetricsTests` and `PeriodFuelMetricsTests`. Every assertion kept, read top to bottom |
| **Consolidated** the Week period journeys into `testTheWeekSummaryStatesItsEarningsAndPickupWaitWithTheirBasis` | 2 → 1 | Same |
| **Consolidated** completed-shift detail journeys into `testTheRecordedShiftsDetailStatesItsTimesRatesAndRoute` and `testAShiftThatRecordedNothingInventsNoFigures` | 7 → 2 | Same screen, one section each; arithmetic in `DeliveryActiveTimeTests` and `ShiftMetricsTests` |
| **Consolidated** the running-shift absences into `testARunningShiftOffersOnlyWhatItsStateAllows` | 5 → 1 | Five launches each to assert one control is absent; one walk through running, paused and stacked states asserts all of them |
| **Seeded** the earnings and tip journeys with `-dashpilot-seeded-finished-delivery` | 9 | Each drove a whole shift through the interface (about 40 s locally, 70 to 98 s on the runner) before its first assertion. `testAddsAndEditsEarningsFromDetail` and `testAddsAnAdditionalTipToAFinishedDelivery` still drive it end to end and assert no amount can be entered while the shift runs |
| **Added** | 4 | The Edit Stack correction, the first-launch welcome and its reopening at the largest text size, and a target compared with the shifts that started under it |

Nothing was weakened to pass: every assertion of a merged journey is in the journey that replaced
it, and no journey was removed because it failed.

**Before:** 246 executed tests (242 journeys and four launch runs), 8,420 s of UI step in run
37088088371. **After:** 228 journeys in the full suite (including the four new ones), and **34 in the
smoke tier**. The removed, merged and seeded journeys took about **1,040 s** of that run between
them (322 s merged away, 26 s of launch runs, 693 s of seeded journeys). Their replacements measure
**454 s** locally, about 570 s at the runner's pace (35 s a journey against 28 locally), so the full
suite is expected to be about 8 minutes shorter, less the 2 to 3 minutes the four new journeys add.
That pass moved cost out of every pull request but left the full suite almost as large, so a second
pass audited what remained.

## Second pass: one launch per screen or flow

The 228 journeys left after the first pass were read again, one at a time, against six questions:
does the domain suite already pin this; does it repeat another journey's setup; does it cross several
screens to read one label; does it duplicate another journey; is it a static copy check; is it one
permutation of a rule tested elsewhere; and is its runtime worth what only it can catch. The answer
for most of them was the same: the behaviour was real and worth driving, but a launch, a seeded
fixture and a navigation were being paid again for every single assertion. The fix was to read each
screen or flow once, in order, with every refusal, cancellation and confirmation on the way, and to
move to the domain suite the few journeys that asserted nothing the interface adds.

### Counts

| | Journeys |
| --- | --- |
| Before this interval | **242**, plus 4 launch-template runs (246 executed) |
| Removed as low value (no assertion, or a `measure` with no baseline) | **1**, plus the 4 launch-template runs |
| Migrated to the domain suite and removed from the UI suite | **6** (2 new domain tests; 4 already pinned) |
| Merged into consolidated journeys | **210**, into **54** journeys (5 in the first pass, 52 in the second, 3 of the first pass's rewritten again) |
| Kept as they were (seeding aside) | **25** |
| New UI journeys written for this interval's features | **4** (Edit Stack, the welcome twice, the hourly target; the target's was later merged into the defaults journey) |
| **After** | **82** journeys: **26** in the smoke tier, **56** more in the regression tier |

Every assertion of a merged journey is in the journey that replaced it, or is named below as moved to
the domain suite. Nothing was removed because it failed, and nothing was weakened to pass.

### Migrated to the domain suite

| Removed journey | Now pinned by |
| --- | --- |
| `testStackedOrdersArePickedUpInOrder` | `ParkResumePickupWorkflowTests` (stacked orders take the first eligible delivery, then the next) |
| `testParkingWithPickupSettingOffLeavesDeliveriesAlone` | `ParkResumePickupWorkflowTests` (the workflow off records nothing on Park) |
| `testLiveActivityKeepsResumeDrivingWithSeveralOrders` | `ShiftActivityControlPriorityTests` |
| `testLiveActivityOffersDeliveredInOrderForStackedOrders` | `ShiftActivityCardLayoutTests` and `StackedDeliveredTests` |
| `testACompletedParkedShiftExplainsItsShortRoute` | **New** `ParkedHistoryRouteTests`: the parked-history fixture's route through `RouteQuality`, its stretch parked and duration, the partial sentence that claims no extra driving, and working time untouched |
| `testTheComparisonStatesNoEstimatedFigure` | **New** `PeriodComparisonTests.noEstimatedFigureIsCompared`: no comparable metric's identifier, title or spoken title is a fuel, estimate or net figure |

`testDeliveryTimeCorrectionIsNotOfferedOnARunningShift` was folded into
`testARunningShiftOffersOnlyWhatItsStateAllows`, which now lists the delivery-time and
correct-to-cancelled controls among those a running shift never offers.

### Merged, journey by journey

| New journey | Replaces |
| --- | --- |
| `testTheShiftPanelReadsInOrderAndBorrowsNothing` | `testPreShiftHomeWithNoVehicleNeverBlocksTheStart`, `testActiveShiftHomeLeadsWithStateThenTheWorkingClock`, `testTheRunningShiftCountsItsDeliveries`, `testAnEmptyHistorySaysWhereShiftsWillAppear`, `testShowsLocationAuthorizationState`, `testAShiftStartedWithNoVehicleBorrowsNothingFromSettings`, `testFillsMissingVehicleAssumptionsOnAFreshShift`, `testHomeSaysNoVehicleIsSelectedAndStillStarts` |
| `testParkAndPauseAreDistinctStatesOfTheRunningShift` | `testPausesAndResumesAShift`, `testAPausedShiftSaysRecordingHasStopped`, `testAPausedShiftIsStillTheShiftInProgress`, `testParkedAndPausedAreDistinctStates`, `testTheEntryBarFollowsParkedAndPaused` |
| `testTheRunningShiftAtTheLargestTextSize` | `testActiveShiftHomeAtTheLargestTextSize`, `testADeliveryCardAtTheLargestTextSize` |
| `testRecoveredStackedDeliveriesStayDistinctAndSurviveLeavingTheApp` | `testRecoversEveryActiveDeliveryOnLaunch`, `testStackedWorkSurvivesLeavingAndReturningToTheApp`, `testStackedDeliveriesInDifferentStatesStayDistinct`, `testADeliveryCardLeadsWithItsStateThenItsNextStep`, `testCompletingOneDeliveryLeavesTheOtherRunning` |
| `testARecordedRouteGrowsFreezesWhilePausedAndLeavesTheBreakOut` | `testRecordedMileageGrowsWhileAShiftIsRecording`, `testRecordedMileageAndWorkingTimeFreezeWhilePaused`, `testResumingDoesNotRecordTheDistanceCoveredWhilePaused`, `testARunningShiftShowsNoEarningsOrRates`, `testTheVehicleCorrectionClosesOnceDrivingIsRecorded`, `testARunningShiftWithNoRouteSaysSoRatherThanShowingNoMiles` |
| `testRecordingParkingAndResumingSayWhatTheyDo` | `testParkingStopsTheRouteAndLeavesTheShiftRunning`, `testResumingDrivingStartsRecordingAgain`, `testRunningShiftSaysWhatRecordingDoesAndDoesNotPromise`, `testRecordingSurvivesLeavingAndReturningToTheApp`, `testLocationPanelStatesTheScopeAndItsLimit` |
| `testHistoryShowsThisWeekWithItsOwnFiguresAndFollowsAnEdit` | `testHistoryShowsThisWeekOnly`, `testTheCurrentWeekOpensWithItsOwnFigures`, `testEditingACurrentWeekShiftRefreshesTheWeek`, `testExportAllHistoryIsNotScopedToTheWeekOnScreen`, `testExportsAllHistory`, `testTheCurrentWeekSummaryStatesItsWork` |
| `testOlderWeeksAreGroupedSummarisedAndOpen` | `testOlderWeeksAreGroupedAndReachable`, `testAnOlderShiftOpensItsOwnDetail`, `testOlderWeeksAreSummarisedBeforeTheirShifts`, `testAWeekOfSeveralShiftsIsTotalled`, `testTheWeeklySummarySpeaksItsUnitsAndCoverage`, `testTheWeeklySummaryNamesItsWeekThenItsFigures` |
| `testOlderWeekSummariesStateTheirFuelCoverageInOrder` | `testAWeekWithoutFuelShowsNoFuelFigure`, `testAWeeksFuelEstimateStatesItsCoverage`, `testAnOlderWeekWithCompleteFuelCoverageSaysSo` |
| `testAHistoricalShiftKeepsTheVehicleItRecorded` | `testAHistoricalShiftShowsTheVehicleItRecorded`, `testAShiftThatRecordedNoVehicleStaysUnnamed`, `testSettingsChangesDoNotReachAHistoricalShift` |
| `testHistoryAtTheLargestTextSize` | `testTheWeeklySummarySurvivesLargeText`, `testTheFullWeeklySummarySurvivesLargeText`, `testTheCurrentWeekSurvivesTheLargestTextSize`, `testTheHistoricalVehicleSurvivesLargeText`, `testALongHistoryIsNavigableAtTheLargestTextSize` |
| `testEditingAndDeletingAnOlderShiftRefreshesItsWeek` | `testEditingAnOlderShiftRefreshesItsWeek`, `testDeletingAnOlderShiftRefreshesItsWeek` |
| `testTheRecordedShiftsDetailStatesItsTimesRatesAndRoute` | itself (from the first pass), `testTheDetailLeadsWithWhatTheShiftPaidThenTimeAndDistance`, `testTheDetailStatesAPartialRouteBesideItsDistance`, `testAShiftWithNoPausesStillOffersToRecordOne` |
| `testACompletedShiftsDeliveriesPlacesAndGrouping` | `testCompletedShiftDetailShowsDeliveryLifecycles`, `testCompletedShiftDetailShowsPickupPlaces`, `testCorrectingGroupingFromACompletedShift` |
| `testShiftEarningsRefuseWhatCannotBeReadAndInventNoPerMileRate` | `testInvalidEarningsAreNotSaved`, `testEarningsWithoutARouteShowNoPerMileRate` |
| `testADeliveryAmountCancelledOrRemovedLeavesNothingInvented` | `testCancellingADeliveryEarningsEditKeepsTheAmount`, `testRemovesDeliveryEarnings` |
| `testTheTipsSheetKeepsEachTipItsOwnRecord` | `testADeliveryCanHoldSeveralAdditionalTips`, `testEditsAndRemovesAnAdditionalTip`, `testATipOfNothingIsRefused`, `testTipsWithoutAPlatformAmountStateNoTotal`, `testTheEarningsEditorSaysTheTipsAreAlreadyRecorded` |
| `testEachDeliveryKeepsItsOwnAmountAndRate` | `testStackedDeliveriesKeepIndependentAmounts`, `testACompletedDeliveryStatesItsOwnEffectiveHourlyRate`, `testRecordingATipMovesThatDeliverysHourlyRate`, `testEditingADeliveryAmountLeavesTheShiftTotalUnchanged` |
| `testExpectedPayIsAnExpectationUntilTheDriverRecordsEarnings` | `testRecordsExpectedPayOnARunningDelivery`, `testDeliveringWithExpectedPayOffersItAndRecordsNothingWhenDismissed` |
| `testDeletingACompletedShiftIsConfirmed` | `testDeletesACompletedShift`, `testCancellingDeletionKeepsTheShift` |
| `testFuelAssumptionsOnAFinishedShift` | `testAddsAndEditsFuelAssumptionsFromDetail`, `testFuelEstimateNamesTheMissingHalf`, `testFuelEstimateKeepsThePartialRouteWording`, `testInvalidFuelAssumptionsAreNotSaved`, `testRemovingFuelAssumptionsLeavesNoEstimate`, `testEstimatedNetShowsTheSubtractionItPerformed`, `testEstimatedNetStatesWhichWayAPartialRouteIsWrong`, `testShiftWithoutAFuelEstimateKeepsItsFinancialFigures` |
| `testFuelAssumptionsSeedTheNextShiftAndItsNetNamesMissingEarnings` | `testFuelAssumptionsSeedFromTheLastShiftThatRecordedThem`, `testEstimatedNetNamesMissingEarnings` |
| `testACompletedShiftAtTheLargestTextSize` | `testCompletedDeliveryActionsStackAtAnAccessibilityTextSize`, `testTheDetailSurvivesTheLargestTextSize` |
| `testPickupAndParkingSettingsAreOffAndKeptAsChosen` | `testPickupWorkflowSettingsParentAndChild`, `testResumeAfterProgressSettingIsOffAndIndependent` |
| `testParkAndResumeRecordThePickupAndUndoTakesEachBack` | `testParkAndResumePickUpTheOneDelivery`, `testUndoAfterAutomatedArrivalKeepsTheVehicleParked`, `testUndoAfterAutomatedPickupKeepsTheVehicleDriving` |
| `testAStackedOfferReadsAsOneOfferOfIndependentDeliveries` | `testEveryStackedDeliverySaysWhatItIsWaitingFor`, `testAdvancingOneStackedDeliveryMovesOnlyItsNextStep`, `testDeliveriesAcceptedTogetherAreShownAsOneOffer`, `testGroupedDeliveriesSayWhatTheyWereAcceptedWith`, `testAdvancingOneOfATwoDeliveryOfferLeavesItsSibling` |
| `testRemindersStateTheirEvidenceAndAnswerOnlyTheirOwnDelivery` | `testTheRestyledReminderStillClaimsNoObservation`, `testStaleDeliveriesEachGetTheirOwnReminder`, `testAReminderStatesItsEvidenceAndClaimsNoObservation`, `testConfirmingAReminderAdvancesOnlyThatDelivery`, `testDismissingAReminderChangesNothing` |
| `testTheOfferSheetRecordsOneOfferOrNothing` | `testStartingAnOfferOfTwoRecordsTwoDeliveries`, `testCancellingTheOfferSheetRecordsNothing`, `testTheOfferSheetKeepsStartPinnedAndRecordsOnce` |
| `testCorrectingGroupingOnARunningShift` | `testCorrectingGroupingCombinesTwoOffers`, `testCorrectingGroupingSeparatesAnOffer`, `testSplittingOneDeliveryIntoItsOwnOffer`, `testDismissingTheCorrectionSheetChangesNothing` |
| `testActiveDeliveriesBlockEndingUntilEachIsResolved` | `testActiveDeliveriesBlockEndingTheShift`, `testCancellingOneDeliveryKeepsItAsHistoryAndSparesTheOther` |
| `testCorrectingAHistoricalCompletionToACancellation` | itself, `testDismissingTheCancellationConfirmationChangesNothing`, `testTheHistoricalCorrectionIsOfferedNowhereElse` |
| `testCorrectingAndRefusingAPauseInTheEditor` | `testCorrectingARecordedPauseFromAFinishedShift`, `testCancellingAPauseCorrectionChangesNothing`, `testAPauseCannotBeCorrectedOverADelivery` |
| `testDeletingAndAddingPauses` | `testDeletingAPauseRecordedByMistake`, `testCancellingAPauseDeletionKeepsThePause`, `testAddingAPauseThatWasNeverRecorded` |
| `testCorrectingAShiftThatDashPilotRecordedAsEndingLate` | itself, `testDecliningTheRouteWarningKeepsTheShiftAsRecorded`, `testAnEndCannotBeCorrectedOverRecordedDeliveryWork`, `testALaterEndAddsTimeAndNoMileage` |
| `testTheShiftEndIsCorrectedOnceTheDeliveryBlockingItIs` | itself, `testCorrectingADeliveryRecordedAfterTheAppCameBack`, `testADeliveryTimeThatBreaksTheLifecycleOrderIsRefused` |
| `testAPickupPlaceIsNamedReusedChangedAndRemoved` | `testAssignsAPickupPlaceToARunningDelivery`, `testSecondDeliveryReusesARecentPickupPlace`, `testChangesAPickupPlace`, `testRemovesAPickupPlace` |
| `testPickupWaitHistoryIsPerPlaceAndStatesItsSample` | `testCompletedDeliveryShowsItsOwnPickupWait`, `testPickupPlaceHistoryShowsAMedianAndItsSampleCount`, `testOneRecordedPickupIsNotPresentedAsATypicalWait`, `testTwoPickupPlacesDoNotShareAHistory`, `testDeliveryWithoutAPickupPlaceHasNoHistoryToOpen` |
| `testCorrectingPickupPlacesRenamesRefusesAndMerges` | `testRenamesAPickupPlaceFromItsHistory`, `testRenamingOntoAnExistingPlaceIsRefusedAndOffersMerge`, `testMergesTwoPickupPlacesIntoOneHistory` |
| `testHomeNamesTheNextShiftsVehicleAndTheShiftKeepsItsOwn` | `testPreShiftHomeLeadsWithWhatTheNextShiftRecords`, `testTheRunningShiftNamesTheVehicleItRecorded`, `testChangingSettingsMidShiftLeavesTheRunningShiftsVehicleAlone`, `testHomeNamesTheVehicleTheNextShiftWillRecord`, `testHomeFollowsTheSelectionUntilAShiftStarts`, `testStartingAShiftSwitchesHomeToTheShiftsOwnVehicle`, `testHomeSaysOnlyWhatIsKnownAboutTheNextShift` |
| `testCorrectingTheRunningShiftsVehicle` | `testCorrectsTheRunningShiftsVehicleBeforeAnyDriving`, `testCancellingTheVehicleCorrectionRecordsNothing` |
| `testALongVehicleNameAtTheLargestTextSize` | `testTheNextShiftsVehicleWrapsAtLargeTextSizes`, `testSettingsSurvivesTheLargestTextSizeWithALongName` |
| `testSettingsStatesItsDefaultsAndRecordsTheGasPrice` | `testSettingsIsReachableFromHome`, `testSettingsLeadsWithTheDefaultVehicle`, `testRecordsCorrectsAndRemovesTheCurrentGasPrice`, `testAcknowledgementsNameTheLicenseAndTheSystemTypeface` |
| `testTheVehicleEditorLabelsItsFieldsAndRefusesWhatItCannotDivideBy` | `testRefusesAVehicleWithNoNameOrNoFuelEconomy`, `testTheVehicleEditorLabelsItsFieldsAndStatesARefusal` |
| `testDefaultsAreRecordedAtStartAndNeverReachARecordedShift` | `testANewShiftRecordsTheCurrentDefaultsAndAnOlderOneDoesNot`, `testChangingSettingsLeavesARecordedShiftAlone`, `testUseCurrentDefaultsFillsAnOlderShiftOnlyWhenAsked`, `testATargetIsComparedWithTheShiftsThatStartedUnderIt` |
| `testTheDaySummaryStatesEachFigureWithItsCoverage` | itself (from the first pass), `testDeliveryAmountsAreShownSeparatelyFromTheShiftTotal` |
| `testTheWeekSummaryStatesItsEarningsAndPickupWaitWithTheirBasis` | itself (from the first pass), `testEmptyPeriodShowsARealEmptyState`, `testSwitchingBetweenDayAndWeekChangesTheShiftsCounted` |
| `testADayIsComparedWithTheDayBeforeIt` | `testADayIsComparedWithTheDayBeforeItAndBothCoveragesAreShown`, `testAFinishedDayWithCompleteRecordsStatesThePercentageChange`, `testAnEmptyPreviousDayIsStatedRatherThanShownAsNoEarnings` |
| `testMonthsHoldTheirDaysStepBackAndSurviveLeavingTheApp` | `testMonthSummaryIncludesTheWholeWeekAndMore`, `testPreviousMonthChangesTheRecordsIncluded`, `testCurrentMonthCannotStepForward`, `testSummarySurvivesLeavingAndReturningToTheApp` |
| `testACustomRangeIsChosenCancelledAndKept` | `testCustomRangeSummarisesTheChosenDates`, `testCancellingTheRangePickerChangesNothing`, `testTheChosenRangeSurvivesSwitchingAway` |
| `testAShiftExportsAsJSONOrCSV` | `testCompletedShiftExportsJSON`, `testCompletedShiftExportsCSV` |
| `testEachPeriodExportsItsOwnRecords` | `testPeriodSummaryExportsTheSelectedPeriod`, `testDayAndWeekExportDifferentPeriods`, `testEmptyPeriodOffersNoExport`, `testExportMonthOpensTheExportFlow`, `testExportCustomRangeOpensTheExportFlow` |
| `testExpensesAreRecordedRefusedCorrectedAndSummarised` | `testRecordsAnExpense`, `testInvalidExpenseAmountIsNotSaved`, `testEditsAndDeletesAnExpense`, `testExpenseOnADayWithoutAShiftIsStillSummarised` |

### Why each remaining journey needs the interface

Every one of the 82 drives something the domain suite cannot observe. Grouped by what that is:

| What only the interface shows | Journeys |
| --- | --- |
| **A whole flow across screens and sheets**: a control opens a sheet, a confirmation guards a write, cancelling writes nothing, and the screen behind it follows | Start and end a shift; record a delivery through its lifecycle; a second delivery; the offer sheet; grouping corrections on a running and a finished shift; Edit Stack; same pickup moving together; an offer independent unless marked; the pickup workflow and its undo; picked up while parked; delivered undo leaving no card; undoing and reopening a delivery; active deliveries blocking the end; every historical correction (cancellation, pauses twice, the late end, the blocking delivery); pickup places and their corrections; earnings, tips and expected pay; fuel assumptions twice; deleting a shift; vehicles created, edited and selected; correcting the running shift's vehicle; expenses; exports twice; the welcome |
| **State surviving the app's lifecycle**: leaving and returning, relaunch, recovery of running work | Recovered stacked deliveries; the recorded route through pause and park; months surviving the app; the running shift's vehicle; first launch persisting the welcome |
| **Reading order and what VoiceOver hears**: the order a screen is drawn in, labels, values and that no glyph stands in for a sentence | The shift panel; park and pause; parking and resuming saying what they do; reminders; a stacked offer; the day, week and comparison summaries; history this week, older weeks and their fuel coverage; the recorded shift's detail and its deliveries; a shift that recorded nothing; Settings and the vehicle editor |
| **Reach, layout and the largest text size**: a control hittable, nothing covered, a long name wrapping | The running shift, history, a completed shift, the period summary, the welcome and a long vehicle name, each at AX5; the entry bars covering nothing; delivery entry staying reachable; every completed-delivery correction readable |
| **Settings reaching the right shift**: a choice reaching the next shift and never the one already recorded, across Settings, Home, the running shift and history | The next shift's vehicle; the defaults snapshot; a historical shift's vehicle; the pickup and parking settings; the running shift offering only what its state allows |
| **Wiring a preview to the real path**: the Live Activity card built through the activity's own content path | Live Activity leading with Park |

What they do **not** do is prove a figure: every amount, rate, median, coverage count and refusal rule
a journey reads is pinned in the domain suite it names in its documentation comment, and the journey's
job is to show that the figure reaches the screen with its wording.

### Runtime

All local figures are serial runs on the same machine, simulator (iPhone 17, iOS 26.5) and Xcode
27.0; CI figures are GitHub's runner with Xcode 26.6. A local journey runs at about 28 s to the
runner's 35, and a host under load runs slower still, so each figure says where it came from.

| Tier | Before this interval | After the first pass | After the second pass |
| --- | --- | --- | --- |
| Full UI suite | 246 tests: **7,990 s** locally (2h13m), **8,420 s** of UI step on CI (run 37088088371) | 228 journeys, not run whole | 82 journeys: **4,745 s** locally (1h19m; one journey failed, see below), **5,287 s** in the all-green run, which started while the host was still loaded |
| Smoke tier (every pull request) | none: every pull request ran the full suite | 34 journeys, **1,036 s** locally | 26 journeys, **1,121 s** locally (1,134 s wall, all green) |

The full suite is about **40 percent shorter** for **a third of the journeys**. It did not shrink in
proportion because a merged journey still reads everything its predecessors read: the time that went
was the repeated launches, fixtures and navigation, not the assertions. The smoke tier stays at
roughly the same length because its journeys are now the merged, broader ones; it covers more for
the same cost. A pull request run is the build, about two minutes of domain suite and the smoke
tier.

The slowest journeys are the ones that do the most: the defaults snapshot (263 s, two launches,
because the seeded history holds a shift dated after today and a new shift has to be the only row to
open), the four period exports (200 s), history at the largest text size (194 s) and the real
recovery of a late shift end (182 s).

The full run that found one failure found a real one. Settings' **reopened welcome** was a
full-screen cover attached to the About row of a lazily loaded list, and at the largest text size,
reached at the end of a nine-page list, it stalled halfway up for more than 15 s in two of three
runs. The cover now sits on the list beside the sheets and opened in eight of eight; the journey's
5-second wait is unchanged.

## CI tiers

| Workflow | When | What | Budget |
| --- | --- | --- | --- |
| `ci.yml` | Every pull request and push to `main` | Build, the **whole** domain suite, then the journeys in `.github/ui-smoke-journeys.txt` | 75 min |
| `ui-regression.yml` | Push to `main`, Mondays 07:00 UTC, `v*` tags, manual dispatch | Build, then **every** UI journey, serially | 210 min |

Both share `.github/actions/prepare-simulator` (Xcode and simulator selection) and upload their
result bundles under `if: always()`. Neither skips, retries or excuses a failure.

The smoke list is plain text, one journey per line, read by the workflow's shell and by
`ContinuousIntegrationWorkflowTests`, which fails the domain suite if a listed name has no journey,
is listed twice, or the list grows past 30 or past half the suite, and fails it if the suite itself
grows past 90 journeys. Add a journey to it only when a regression in it would
stop a driver working and nothing faster would catch it.

The smoke tier's measured length is in [Runtime](#runtime). The first `ui-regression.yml` run on
the runner is the number still to record for the full suite.
