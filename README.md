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
inside it, how much of its route was captured, what they say it paid, and the two rates that follow
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
  one primary control per state, one active delivery at a time, transitions enforced against the
  store, relaunch recovery, and a shift end refused while a delivery is running.
- **Manual gross earnings**, optional, locale-aware, refused rather than reinterpreted when it
  cannot be read.
- **Completed-shift metrics and detail**: gross earnings per shift hour and per recorded mile, with
  the reason stated whenever a rate cannot be derived, its deliveries listed with their recorded
  events, and a confirmed delete that removes the shift's route positions and deliveries with it.

## Technology

Swift, SwiftUI, SwiftData, Core Location, OSLog, Swift Testing and XCUITest. **No third-party
runtime dependencies.**

Versioned schema at v5 with lightweight migrations from v1, tested by opening stores written under
each older version. Domain calculations import neither SwiftUI nor SwiftData, so every rule is
tested without a container or a rendered view. Money is `Decimal` throughout: no monetary value
passes through binary floating point, in memory or in the store. Nothing derived is stored, so
mileage and both rates are recomputed from the stored data every time they are shown.

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
[testing](docs/development/testing.md) or the
[data model](docs/reference/data-model.md).

## Limitations

The short version, with the full list in [`docs/reference/limitations.md`](docs/reference/limitations.md):

- **Route capture is foreground only.** A route has a gap whenever the app was not open, so
  **recorded mileage is a floor**, normally lower than the miles actually driven. It is not a tax or
  deduction figure.
- **Gross earnings are what the driver typed.** Nothing is imported, no amount is a profit,
  take-home or taxable figure, and no amount recorded is a different state from `$0.00`.
- **Both rates are gross.** The hourly rate divides by elapsed shift time, not working time; the
  per-mile rate divides by recorded miles, which makes it normally higher than earnings per mile
  driven.
- **Deliveries are what the driver tapped.** Nothing is detected, imported or inferred, no amount is
  attributed to a delivery, and only one delivery can be recorded at a time.
- **No delivery-platform integration**, permanently and by design.
- **Local only.** No export, no backup, no sync, and deleting a shift is permanent.
- Not implemented yet: anything built on the delivery records (restaurant scoring, wait-time
  analysis, offer profitability), active-versus-idle time, expenses, aggregates over a period, maps,
  App Intents, Live Activities and recommendations.

## License

[MIT](LICENSE).
