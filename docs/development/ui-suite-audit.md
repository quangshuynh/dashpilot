# UI suite audit and CI tiers

The v0.1.0 merge (October 3, 2026) ran a UI suite of 242 journeys plus four launch-configuration runs
for **2h31m**, 2h23m of it in the UI step, on every pull request and every push to `main`, and both
runs were red. This page records what the failures were, how every journey was classified, what
moved where, and the CI shape that came out of it. The rules for writing journeys are on
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

## What changed

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
That is a modest cut to the full suite, deliberately: its cost moves out of every pull request rather
than out of the suite. The first `ui-regression.yml` run is the number to record.

### Retained, and why

Most of the suite stays, in the full regression: the largest-text journeys (the slowest single ones,
130 to 205 s, and the only proof a screen survives AX5), the correction flows (pause, end, delivery
times, historical completion), whose value is that a sheet, a picker and a confirmation work
together, the Live Activity preview journeys, and the settings and vehicle journeys whose subject is
that a setting reaches the next shift and not the current one. Each is class 1 or 2 by the table
above. What was cut is repetition, not coverage.

## CI tiers

| Workflow | When | What | Budget |
| --- | --- | --- | --- |
| `ci.yml` | Every pull request and push to `main` | Build, the **whole** domain suite, then the journeys in `.github/ui-smoke-journeys.txt` | 75 min |
| `ui-regression.yml` | Push to `main`, Mondays 07:00 UTC, `v*` tags, manual dispatch | Build, then **every** UI journey, serially | 210 min |

Both share `.github/actions/prepare-simulator` (Xcode and simulator selection) and upload their
result bundles under `if: always()`. Neither skips, retries or excuses a failure.

The smoke list is plain text, one journey per line, read by the workflow's shell and by
`ContinuousIntegrationWorkflowTests`, which fails the domain suite if a listed name has no journey,
is listed twice, or the list grows past 45. Add a journey to it only when a regression in it would
stop a driver working and nothing faster would catch it.

At about 35 s a journey on the runner the smoke tier is about 20 minutes, so a pull request run is
expected at roughly 30 to 35 minutes against 2h28m to 2h54m before. That is an estimate from the
per-journey durations above, not yet a measured run.
