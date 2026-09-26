<p align="center">
  <img src="docs/images/dashpilot-logo.png" alt="DashPilot" width="160">
</p>

<h1 align="center">DashPilot</h1>

<p align="center">
  A native, local-first iOS companion that records a delivery driver's shifts, deliveries, routes
  and earnings on device, and reports what that history honestly supports.
</p>

<p align="center">
  <a href="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml"><img src="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/quangshuynh/dashpilot/actions/workflows/docs.yml"><img src="https://github.com/quangshuynh/dashpilot/actions/workflows/docs.yml/badge.svg" alt="Docs"></a>
  <img src="https://img.shields.io/badge/platform-iOS%2026.5%2B-lightgrey" alt="Platform: iOS 26.5+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20SwiftData-orange" alt="Swift, SwiftUI, SwiftData">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

---

DashPilot is for gig and delivery drivers who want a truthful record of their own work: how long a
shift ran, what it paid, how far the recorded route went, and what those facts imply per hour and
per mile. It replaces a notebook and a spreadsheet, not the delivery app.

It is a general driver tool. It has **no integration with DoorDash or any other platform**, never
observes or automates those apps, and asks the driver for anything a phone cannot legitimately
measure.

## What it does

- **Shift tracking.** Start, pause, resume and end a shift, with relaunch recovery if iOS ends the
  app mid-shift. Paused time is excluded from working time and from every hourly figure.
- **Delivery lifecycle.** One large control per delivery for accepted, arrived at pickup, picked
  up, delivered or cancelled, with a live clock for each delivery in progress.
- **Stacked deliveries.** Several deliveries can run at once, grouped by the offer they arrived in.
  Overlapping time is counted once, never summed.
- **Route and recorded mileage.** Route capture runs with the shift, including off screen, and a
  single filtering policy decides which positions count. Mileage is measured only across what was
  captured continuously.
- **Pause and Park.** *Pause* stops the clock and the route. *Park* stops only the route, for the
  walk around a shop, so it never inflates recorded mileage and never subtracts working time.
- **Earnings and additional tips.** Optional gross earnings per shift and per delivery, kept as
  independent facts, plus tips received outside the platform's amount, each with its method.
- **Fuel estimates and vehicle profiles.** Save your vehicles and a gas price. Each shift copies
  the assumptions when it starts, and its fuel cost is estimated over its own recorded miles.
- **Weekly history and profitability.** History shows the current week, with every earlier week a
  tap away, and each week opens with a summary. Day, week, month and custom-range summaries state
  the coverage behind every figure and can be read beside the period before it.
- **Recorded expenses.** Fuel, parking, maintenance and more, with a net after recorded expenses.
- **Corrections for historical mistakes.** Fix a shift's end time, a recorded pause, a delivery's
  times, an accidental Delivered, a delivery that was really cancelled, or how deliveries were
  grouped into offers.
- **Live Activity and App Intents.** The running shift on the Lock Screen and in the Dynamic
  Island, with its lifecycle controls, and eight short voice or Shortcuts actions that work without
  opening the app.
- **Export.** JSON and CSV for one shift, a period or all history, written locally and handed to
  the share sheet.
- **Local-first and private.** No account, no server, no analytics, no network code.

## How DashPilot treats your data

- **It stays on the device.** Nothing is uploaded, synced or logged. Coordinates, earnings and
  place names never appear in logs.
- **Recorded facts and estimates are kept apart.** Recorded earnings, expenses and mileage are
  facts the driver entered or the device observed. Estimated fuel and the estimated net after it
  are arithmetic over the driver's own assumptions and are always labelled as estimates.
- **Missing is not zero.** An amount nobody recorded is shown as not recorded, never as `$0.00`,
  and every period figure states how many shifts are behind it.
- **Corrections rewrite the recorded fact.** A correction changes the authoritative record in
  place and refuses anything that would contradict another recorded fact. Every duration, rate and
  total derived from it follows, because nothing derived is stored.
- **Fuel estimates stay estimates.** An estimate is never added to recorded expenses, because a
  recorded fuel purchase may be the same fuel. Where only some shifts can be estimated, the figure
  says so (`4 of 6 shifts`, `142.3 of 188.9 recorded miles`) rather than scaling up.
- **Route gaps are not invented.** Recorded mileage is a floor. A stretch the phone did not
  capture is reported as a gap, never bridged with a straight line.

## Tech

- Swift and SwiftUI, with SwiftData persistence (versioned schema with tested migrations from v1)
- Core Location for route capture, When In Use authorization only
- ActivityKit and WidgetKit for the Live Activity, App Intents for voice and Shortcuts
- `Decimal` money throughout, never binary floating point
- Swift Testing for the domain suite, XCTest UI tests for journeys
- No third-party runtime dependencies

## Development

Requires Xcode 26.6 or later (the deployment target is iOS 26.5). There is no package manager,
code generation or bootstrap step: clone, open `DashPilot.xcodeproj`, and run the `DashPilot`
scheme on an iPhone simulator.

```bash
xcodebuild build -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
xcodebuild test -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DashPilotTests
```

Drop `-only-testing` to run the UI journeys too. Substitute any installed iPhone simulator; see
[Building](docs/development/building.md) and [Testing](docs/development/testing.md) for the full
details, CI and the documentation toolchain.

## Documentation

The full documentation is published at
[quangshuynh.github.io/dashpilot](https://quangshuynh.github.io/dashpilot/), built from
[`docs/`](docs/index.md):

- [Product overview](docs/product/overview.md), including what is not implemented
- [Shift workflow](docs/product/shift-workflow.md) and
  [delivery lifecycle](docs/product/delivery-lifecycle.md)
- [Earnings and metrics](docs/product/earnings-and-metrics.md),
  [period summaries](docs/product/period-summaries.md) and
  [estimated fuel](docs/product/estimated-fuel.md)
- [Recorded mileage](docs/product/recorded-mileage.md) and
  [route measurement](docs/architecture/route-measurement.md)
- [Architecture](docs/architecture/overview.md), [persistence](docs/architecture/persistence.md)
  and [privacy](docs/architecture/privacy.md)
- [History export](docs/product/history-export.md) and the
  [data model](docs/reference/data-model.md)
- [Design system](docs/development/design-system.md)
- [Limitations](docs/reference/limitations.md)

## License

DashPilot's source code is licensed under the [MIT License](LICENSE).

The app bundles the Manrope typeface, which is licensed separately under the
[SIL Open Font License 1.1](DashPilot/Resources/Fonts/OFL.txt). See
[The typeface and its license](docs/development/building.md#the-typeface-and-its-license).
