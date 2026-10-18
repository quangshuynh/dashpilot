# Product overview

DashPilot is a native, local-first companion for delivery drivers. It records work you enter and
route samples your device captures, then explains what those records support. Start with
[Your first shift](first-shift.md) for a practical walkthrough.

## Implemented

**Home, Work and Money.** Home starts or continues a shift, shows current-week completed work and
recent shifts, and links to History and Money. Work keeps active delivery controls and History
together. Money shows a selected week's recorded earnings, expenses and qualified net, with Insights
and detailed reports. Settings is in each workspace toolbar. Cold launch opens Work for an unfinished
shift, otherwise Home. Ordinary tab changes preserve each navigation stack.

**Shift tracking.** Start, pause, resume and end one shift at a time. Working time excludes pauses.
Park stops route recording while working time continues; Pause stops both. Optional pickup and
resume-after-progress settings act on recorded actions, never inferred movement. Unfinished shifts
and deliveries survive relaunch. See [Shift workflow](shift-workflow.md).

**Delivery tracking.** Record accepted, arrived at pickup, picked up, delivered or cancelled states.
Several deliveries may overlap and belong to one or several offers. Drivers can explicitly mark
shared pickups or drop-offs, edit active stacks, and correct supported historical mistakes.
Overlapping delivery-active intervals count once. See [Delivery lifecycle](delivery-lifecycle.md).

**Recorded mileage.** Accepted route samples support distance only within capture continuity.
Foreground-started recording can continue off screen, but gaps and interrupted capture remain
possible. The app requests When In Use location access contextually and shows the current recording
state. See [Recorded mileage](recorded-mileage.md).

**Money.** Shift gross and delivery gross are independent entered facts. Additional delivery tips
remain separate records. Money includes dated expenses in five categories, confirmed correction and
deletion, and category filters that do not change period totals. Fuel estimates use saved vehicle
and price assumptions and are kept separate from recorded expenses. See
[Earnings and metrics](earnings-and-metrics.md), [Expenses](expenses.md) and
[Estimated fuel](estimated-fuel.md).

**History and reports.** Completed shifts belong to the period containing their start. All reporting
weeks run Monday through Sunday in the reporting Calendar's timezone. Reports cover days, weeks,
months and custom ranges, with coverage and supported comparisons. Home excludes active shifts.
Expenses belong to their own dates. See [Period summaries](period-summaries.md).

**Optional settings.** Vehicles, fuel assumptions and an hourly gross target are defaults copied
when a new shift starts. Existing shifts keep their snapshots. USD is the only monetary presentation.
The welcome can be replayed from Settings. See [Settings](settings.md).

**System actions.** Nine App Shortcuts and the shift's Live Activity call the same lifecycle services
as the app. The generic delivery next-step action requires one active delivery; Mark Delivered
supports stacked work by selecting the lowest-numbered picked-up delivery, one at a time. See
[Voice actions](voice-actions.md) and [Live Activity](live-activity.md).

**Pickup history.** Optional driver-entered place names use conservative normalization. Typical
pickup waits are medians of qualifying individual samples, with counts and provenance exclusions.
See [Pickup identity](pickup-identity.md) and [Pickup waits](pickup-wait.md).

**Explicit export.** JSON and CSV files are generated locally and shared only by user action.
Export v6 excludes raw coordinates and normalized pickup keys; JSON supports expense records,
while CSV remains shift/delivery oriented. Export is not an importable backup. See
[History export](history-export.md).

## Not implemented

No platform import, accounts, cloud sync, bank connection, receipts, taxes, currency conversion,
expense-to-shift associations, maps, automatic delivery detection, predictive analytics or restore
from export. No other work types are presented as supported. The full current constraints are in
[Limitations](../reference/limitations.md).

## What the numbers are not

- Gross earnings are entered amounts, not verified platform totals, take-home pay or taxable income.
- Missing is not zero. Explicit zero counts as a record; each aggregate reports its contributing coverage.
- Net after recorded expenses and estimated net after fuel are different qualified figures. Neither
  proves profit, and the app never subtracts both costs together.
- Recorded mileage is not total driven mileage. Gaps are excluded, not filled with invented distance.
- Rates use the same qualifying numerator and denominator subset. A shift with missing earnings
  does not silently contribute time to an earnings rate.
- Historical records describe past work. They do not guarantee or predict future earnings.

The detailed rules live with [earnings](earnings-and-metrics.md),
[coverage](period-summaries.md#coverage-the-rule-the-whole-screen-exists-for) and
[route measurement](recorded-mileage.md).

## Boundaries the project will not cross

DashPilot has no official platform integration. It does not collect delivery-platform credentials,
access private APIs, scrape, intercept traffic, automate acceptance or rejection, or control another
delivery app. There is no backend, telemetry, analytics, advertising or automatic upload.
See [Privacy](../architecture/privacy.md).

## Weekly Insights

[Insights](insights.md) lives inside Money and shows eight consecutive weekly earnings and hourly-rate
points, exact values with coverage, recorded expense categories and a comparison with the preceding
week. Missing amounts remain missing. Current weeks are explicitly in progress. Exact values are
available through ordinary controls and an expandable list, including at AX5, without chart gestures.
