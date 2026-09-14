<p align="center">
  <img src="docs/images/dashpilot-logo.png" alt="DashPilot" width="160">
</p>

<h1 align="center">DashPilot</h1>

<p align="center">
  A native, local-first iOS companion that measures a delivery driver's shifts, deliveries, routes,
  recorded mileage and gross earnings on device.
</p>

<p align="center">
  <a href="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml"><img src="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/quangshuynh/dashpilot/actions/workflows/docs.yml"><img src="https://github.com/quangshuynh/dashpilot/actions/workflows/docs.yml/badge.svg" alt="Docs"></a>
  <img src="https://img.shields.io/badge/platform-iOS%2026.5%2B-lightgrey" alt="Platform: iOS 26.5+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20SwiftData-orange" alt="Swift, SwiftUI, SwiftData">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

---

DashPilot records what a shift actually did: when it ran, which deliveries the driver recorded
inside it, how much of its route was captured, what they say it paid, and the three rates that follow
from those facts. Everything stays on the device.

It is a general delivery-driver tool. It has no integration with DoorDash or any other delivery
platform, it does not observe, automate or interfere with those apps, and anything that cannot be
derived legitimately from device sensors and stored history is typed by the driver or left out.

## Capabilities

- **Shift lifecycle** with a single-active-shift rule enforced against the store, refusals reported
  rather than swallowed, and relaunch recovery for a shift that was still running.
- **Pause and resume**, so a driver can stop for a meal or an errand without ending the shift.
  Paused time is a recorded row rather than a screen state, it survives termination, it is excluded
  from the shift's working duration and from every hourly figure derived from it, and route
  recording stops for its whole length. Resuming starts a new recording, so no distance is measured
  across the break. Pausing is refused while a delivery is in progress; ending a paused shift is
  allowed and closes the pause at the end time.
- **Correcting a recorded pause**, from a finished shift's own record: a pause recorded at the wrong
  moment can have either end or both moved, one recorded by mistake can be deleted, and a pause the
  driver took and never recorded can be added. A stretch is refused rather than nudged if it ends
  before it starts, reaches outside the shift, overlaps another pause or overlaps a stretch a
  delivery was open for, and no delivery timestamp is ever moved to make a pause fit. The shift's own
  start and end, its route and every amount it records are untouched; the working duration, the
  hourly rate and the period totals over it follow. The open pause of a shift that is paused right
  now stays Resume's and End's alone, and nothing anywhere detects or suggests a pause.
- **Route capture** that starts and stops with the shift, carries on while the driver is in another
  app or the phone is locked, states whether it is active, stopped because the shift is paused,
  paused because a session could not start off screen, or unavailable, and never ends a shift
  because location was lost.
- **Sample filtering** with one acceptance policy covering invalid coordinates, poor accuracy, stale
  fixes, duplicate and out-of-order timestamps, negligible movement and implausible jumps.
- **Recorded mileage** derived from the retained route, summing only what was captured continuously
  and excluding the distance across detected gaps.
- **Delivery lifecycle** — accepted, arrived at pickup, picked up, delivered, or cancelled — with
  one primary control per delivery, **several deliveries recordable at once** for stacked orders,
  every event targeted at one delivery, transitions enforced against the store, relaunch recovery for
  each of them, and a shift end refused while any delivery is running.
- **Taking back a delivery marked delivered by mistake**: an undo offered on the panel for the first
  few seconds after the tap, and a deliberate `Reopen a Delivered Delivery` control for the mistake
  noticed later. Reopening removes the delivered time and nothing else, and the delivery returns to
  the state its remaining timestamps already describe. No timestamp is edited, moved or invented, the
  amounts recorded against it stay, and it is refused while the shift is paused and after the shift
  has ended, because a shift cannot hold a delivery nothing could finish.
- **Correcting a completion after the shift has ended**, from the finished shift's own record: a
  delivery recorded as delivered that never completed is recorded as cancelled instead, and stays
  terminal. The instant it recorded as its completion becomes the cancellation, so no time is typed
  or invented and the shift's delivery active time, working duration, recorded mileage and period
  figures are all unchanged. The shift is not reopened, no delivery becomes active in it, and the
  pickup place and recorded amounts stay.
- **Offers**, recording which deliveries the driver accepted together, with a correction for the
  grouping afterwards: move a delivery between offers, split one out, combine two offers or separate
  one, on a running shift or from history. A correction changes membership only. No lifecycle time,
  pickup place, amount or terminal state moves with it, neither acceptance time is rewritten, and an
  offer holds no money, duration or distance of its own.
- **Voice and system actions** for the six short lifecycle steps (start a shift, pause it, resume it,
  end it, start a delivery, record that delivery's next event) through App Intents, with the app
  never coming to the screen. Each calls the same service the button calls, and a spoken delivery step is recorded only
  while exactly one delivery is in progress; with more, DashPilot records nothing and says so. No
  intent takes a dictated value.
- **A Live Activity for the shift in progress**, on the Lock Screen and in the Dynamic Island: the
  working time, what the route has recorded, how the deliveries stand, and the controls the shift's
  own lifecycle rules permit, including starting one more delivery. Pressing one runs the same
  service the app's button runs; with two deliveries in progress it offers no step, because no button
  there can say which order it meant. No amount, rate, place or coordinate appears on it.
- **Optional pickup identity**: a delivery can name the place it was collected from, typed by the
  driver and reused across deliveries when the same name is entered again, with no address, no
  lookup and no platform involved. A place can be renamed, and one place explicitly merged into
  another, without moving a delivery or a recorded time.
- **Manual gross earnings**, optional, locale-aware, refused rather than reinterpreted when it
  cannot be read — one amount for a shift, and optionally one for each finished delivery. The two are
  independent facts: no shift total is ever split between deliveries, added up from them or
  reconciled against them.
- **Expected pay on a delivery in progress**, entered from its card while waiting at a pickup and
  kept strictly apart from earnings. Nothing counts it: no total, rate, period figure or export
  summary is derived from it, and marking a delivery delivered finalizes nothing. A delivery that
  carries one instead offers it back for the driver to confirm or correct, and dismissing that
  leaves the delivery with no gross earnings recorded.
- **Delivery active time**: the union of a shift's delivery intervals, so deliveries worked at the
  same time are counted once rather than summed, plus the non-delivery time left over.
- **Completed-shift metrics and detail**: gross earnings per working hour, per active delivery hour and
  per recorded mile, with the reason stated whenever a rate cannot be derived, its deliveries listed
  with their recorded events and any amount recorded against them, and a confirmed delete that
  removes the shift's route positions and deliveries with it.
- **Recorded operating expenses**: fuel, parking and tolls, maintenance, supplies or other, each
  with an amount, a date, and an optional short note. An expense belongs to a **date** rather than to
  a shift, so nothing is attributed to work the driver did not attribute it to and no cost is divided
  across shifts, deliveries or miles. A period reports what was recorded, its split by category, and
  **net after recorded expenses**, which is one recorded subtotal less another and is never called
  profit.
- **Day, week, month and custom-range summaries with explicit data coverage**: periods built by
  `Calendar` rather than by fixed 24-hour or 30-day arithmetic, a chosen range picked as inclusive
  dates and held internally as a half-open interval, completed shifts only, every figure shown with
  the shifts behind it, missing values excluded rather than counted as zero, and each rate divided
  over the one subset of shifts carrying both halves of it.
- **Portable JSON and CSV history export** of one shift, a day, a week, a month, a chosen date range
  or all completed shifts, written locally and offered to the system share sheet, with a format
  version of its own, coverage counts preserved, spreadsheet formula injection guarded against, and
  no raw coordinates.

## Technology

Swift, SwiftUI, SwiftData, Core Location, App Intents, ActivityKit, WidgetKit, OSLog, Swift Testing
and XCUITest. **No third-party runtime dependencies.** One application target, plus a widget
extension that draws the shift's Live Activity and holds no logic of its own.

Versioned schema at v12 with migrations from v1, tested by opening stores written under each older
version. Domain calculations import neither SwiftUI nor SwiftData, so every rule is
tested without a container or a rendered view. Money is `Decimal` throughout: no monetary value
passes through binary floating point, in memory or in the store. Nothing derived is stored, so
mileage, active time and all three rates are recomputed from the stored data every time they are
shown.

## Privacy

All data stays on device. There are no accounts, no sync, no analytics, no telemetry, no ads and no
network code in the project. Coordinates, routes and earnings are never logged: the location logs
record what the app was allowed to do and which rule rejected a sample, never where the device was.
A shift's route positions and deliveries are deleted with the shift, and a delivery stores no
restaurant, customer or address. Every example in the tests, previews and documentation is
synthetic.

## Build and test

Requires Xcode 26.6 or later.

```bash
xcodebuild build -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
xcodebuild test -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Documentation

The full product and architecture documentation is an MkDocs Material site whose sources live in
[`docs/`](docs/). Build it locally with:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-docs.txt
mkdocs serve
```

Python is only needed for the documentation. It is never required to build or run the app.

Once GitHub Pages is enabled for this repository, the deployment workflow publishes the site to
`https://quangshuynh.github.io/dashpilot/`. It is not published yet.

Start with [`docs/index.md`](docs/index.md), or go straight to
[product overview](docs/product/overview.md),
[delivery lifecycle](docs/product/delivery-lifecycle.md),
[voice and system actions](docs/product/voice-actions.md),
[the shift on the Lock Screen](docs/product/live-activity.md),
[architecture](docs/architecture/overview.md),
[building](docs/development/building.md),
[testing](docs/development/testing.md), the
[data model](docs/reference/data-model.md) or
[history export](docs/product/history-export.md).

## Limitations

The short version, with the full list in [`docs/reference/limitations.md`](docs/reference/limitations.md):

- **Recording is not guaranteed.** It continues off screen, but iOS may suspend or end the app and
  nothing relaunches it, and a recording can only be started with the app open. A route can still
  have a gap, so **recorded mileage is a floor** that can be lower than the miles actually driven.
  It is not a tax or deduction figure.
- **Gross earnings are what the driver typed.** Nothing is imported, no amount is a profit,
  take-home or taxable figure, and no amount recorded is a different state from `$0.00`.
- **Recorded expenses are only what the driver entered.** DashPilot observes no purchase and
  estimates no cost, so a period's recorded expenses are a floor and a period with none recorded is
  not one that cost nothing. Net after recorded expenses is one recorded subtotal less another: it is
  not profit, not take-home pay and not a tax figure, and there is no cost per shift, per delivery,
  per hour or per mile anywhere.
- **All three rates are gross.** The per-working-hour rate divides by working time; the
  per-active-delivery-hour rate divides by the time a recorded delivery was open, which is not a
  measure of work and not a wage; the per-mile rate divides by recorded miles, which makes it
  normally higher than earnings per mile driven.
- **Deliveries are what the driver tapped.** Nothing is detected, imported or inferred, and an
  amount on a delivery is there only because the driver typed it for that delivery. Delivery active
  time is only as good as the tapping, overlapping deliveries are unioned rather than summed, their
  hourly figures are never added together, and non-delivery time is not idle time.
- **Voice actions cover six lifecycle steps and nothing else.** No cancelling, no amounts, no costs,
  no pickup names, nothing read back, and a shift started by voice records no route until the app is
  opened.
- **The shift's Live Activity shows and controls, and never alerts.** It carries the working time,
  the recorded mileage and the delivery counts, and no amount, rate, place or coordinate. Its
  controls are the app's own lifecycle actions and are refused by the same rules; with two deliveries
  open it offers no step, because no button on a Lock Screen can say which order it meant. It has
  been run on the simulator only.
- **No delivery-platform integration**, permanently and by design.
- **Local only.** No backup, no sync, no import, and deleting a shift is permanent. Export writes a
  file on the device and hands it to the share sheet; where it goes after that is the driver's
  choice, and the file is not a tax statement or a platform record.
- **A pickup place's recorded waits are summarised, not predicted.** The median is shown beside the
  number of pickups behind it, one recorded wait is never called typical, long waits are never
  trimmed away, and nothing forecasts the next pickup or ranks one place against another.
- **Places are never merged automatically.** Two spellings of one business stay two places, with two
  separate wait histories, until the driver merges them deliberately. There is no similarity
  matching, and a merge cannot be undone.
- **A period summary reports what was recorded, not what happened.** Day, week, month and
  custom-range totals cover completed shifts only, count a shift whole on the period it started in,
  exclude missing values rather than reading them as zero, and state the shifts behind every figure.
  Each rate divides aggregate by aggregate over one paired subset of shifts — never an average of the
  shifts' own rates, and never an average of a shorter period's rates — and nothing forecasts or
  ranks days.
- **A period may be read beside the equivalent period before it.** Both figures are shown with the
  records behind each side, a total moves by "more" or "less recorded" rather than by better or
  worse, and a percentage is stated only when both figures exist, the previous one is not zero, the
  selected period has finished and both sides cover all of their records. Differences in length and
  in coverage are stated rather than scaled away, and nothing here is a goal, a trend or a
  prediction.
- Not implemented yet: most things built on the delivery records (merchant scoring, merchant
  profitability, offer profitability, per-delivery mileage), any tax feature, recurring expenses or
  receipts, aggregates longer than a month or a chosen range, maps, home-screen widgets,
  notifications, recommendations, and importing an exported file back.

## License

[MIT](LICENSE).
