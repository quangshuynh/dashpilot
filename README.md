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
- **Foreground route capture** that starts and stops with the shift, states whether it is active,
  paused or unavailable, and never ends a shift because location was lost.
- **Sample filtering** with one acceptance policy covering invalid coordinates, poor accuracy, stale
  fixes, duplicate and out-of-order timestamps, negligible movement and implausible jumps.
- **Recorded mileage** derived from the retained route, summing only what was captured continuously
  and excluding the distance across detected gaps.
- **Delivery lifecycle** — accepted, arrived at pickup, picked up, delivered, or cancelled — with
  one primary control per delivery, **several deliveries recordable at once** for stacked orders,
  every event targeted at one delivery, transitions enforced against the store, relaunch recovery for
  each of them, and a shift end refused while any delivery is running.
- **Optional pickup identity**: a delivery can name the place it was collected from, typed by the
  driver and reused across deliveries when the same name is entered again, with no address, no
  lookup and no platform involved. A place can be renamed, and one place explicitly merged into
  another, without moving a delivery or a recorded time.
- **Manual gross earnings**, optional, locale-aware, refused rather than reinterpreted when it
  cannot be read — one amount for a shift, and optionally one for each finished delivery. The two are
  independent facts: no shift total is ever split between deliveries, added up from them or
  reconciled against them.
- **Delivery active time**: the union of a shift's delivery intervals, so deliveries worked at the
  same time are counted once rather than summed, plus the non-delivery time left over.
- **Completed-shift metrics and detail**: gross earnings per shift hour, per active delivery hour and
  per recorded mile, with the reason stated whenever a rate cannot be derived, its deliveries listed
  with their recorded events and any amount recorded against them, and a confirmed delete that
  removes the shift's route positions and deliveries with it.
- **Day and week summaries with explicit data coverage**: calendar periods built by `Calendar` rather
  than by fixed 24-hour arithmetic, completed shifts only, every figure shown with the shifts behind
  it, missing values excluded rather than counted as zero, and each rate divided over the one subset
  of shifts carrying both halves of it.
- **Portable JSON and CSV history export** of one shift, a day, a week or all completed shifts,
  written locally and offered to the system share sheet, with a format version of its own, coverage
  counts preserved, spreadsheet formula injection guarded against, and no raw coordinates.

## Technology

Swift, SwiftUI, SwiftData, Core Location, OSLog, Swift Testing and XCUITest. **No third-party
runtime dependencies.**

Versioned schema at v7 with lightweight migrations from v1, tested by opening stores written under
each older version. Domain calculations import neither SwiftUI nor SwiftData, so every rule is
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
[architecture](docs/architecture/overview.md),
[building](docs/development/building.md),
[testing](docs/development/testing.md), the
[data model](docs/reference/data-model.md) or
[history export](docs/product/history-export.md).

## Limitations

The short version, with the full list in [`docs/reference/limitations.md`](docs/reference/limitations.md):

- **Route capture is foreground only.** A route has a gap whenever the app was not open, so
  **recorded mileage is a floor**, normally lower than the miles actually driven. It is not a tax or
  deduction figure.
- **Gross earnings are what the driver typed.** Nothing is imported, no amount is a profit,
  take-home or taxable figure, and no amount recorded is a different state from `$0.00`.
- **All three rates are gross.** The per-shift-hour rate divides by elapsed time; the
  per-active-delivery-hour rate divides by the time a recorded delivery was open, which is not a
  measure of work and not a wage; the per-mile rate divides by recorded miles, which makes it
  normally higher than earnings per mile driven.
- **Deliveries are what the driver tapped.** Nothing is detected, imported or inferred, and an
  amount on a delivery is there only because the driver typed it for that delivery. Delivery active
  time is only as good as the tapping, overlapping deliveries are unioned rather than summed, their
  hourly figures are never added together, and non-delivery time is not idle time.
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
- **A period summary reports what was recorded, not what happened.** Day and week totals cover
  completed shifts only, count a shift whole on the period it started in, exclude missing values
  rather than reading them as zero, and state the shifts behind every figure. Each rate divides
  aggregate by aggregate over one paired subset of shifts — never an average of the shifts' own
  rates — and nothing forecasts, compares periods or ranks days.
- Not implemented yet: most things built on the delivery records (merchant scoring, merchant
  profitability, offer profitability, per-delivery mileage), expenses, aggregates longer than a week,
  maps, App Intents, Live Activities, recommendations, and importing an exported file back.

## License

[MIT](LICENSE).
