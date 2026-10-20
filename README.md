<p align="center">
  <img src="docs/images/dashpilot-logo.png" alt="DashPilot" width="160">
</p>

<h1 align="center">DashPilot</h1>

<p align="center">
  A native, local-first iOS companion for recording delivery work and understanding your time, earnings and expenses.
</p>

<p align="center">
  <a href="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml"><img src="https://github.com/quangshuynh/dashpilot/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platform-iOS%2026.5%2B-lightgrey" alt="Platform: iOS 26.5+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

<p align="center">
  <img src="docs/images/screenshots/home-workspace.png" alt="Home with completed-week earnings and explicit coverage" width="220">
  <img src="docs/images/screenshots/work-workspace.png" alt="Work with an active shift and stacked delivery controls" width="220">
  <img src="docs/images/screenshots/money-workspace.png" alt="Money with recorded earnings, expenses and qualified net" width="220">
</p>

*Current simulator captures with synthetic records. [Screenshot details](https://quangshuynh.github.io/dashpilot/development/release-readiness/#documentation-and-screenshots).*

## Your work, clearly recorded

- **Home:** start or continue a shift and review this week's completed work.
- **Work:** record deliveries, including stacked offers, with separate Park and Pause controls.
- **Money:** review recorded earnings and expenses, explore weekly Insights, and open historical reports.
- **Your history:** correct records and export them explicitly as JSON or CSV.

DashPilot has no delivery-platform integration. Recorded mileage can be partial; missing amounts
stay missing. Recorded expenses and fuel estimates remain distinct, and neither net figure is a
claim of profit. See [how earnings and coverage work](https://quangshuynh.github.io/dashpilot/product/earnings-and-metrics/).

## Local first

No account, backend, analytics or automatic uploads. Records stay on device until you choose to
export them. Read the [privacy details](https://quangshuynh.github.io/dashpilot/architecture/privacy/)
and [current limitations](https://quangshuynh.github.io/dashpilot/reference/limitations/).

## Build and run

Use Xcode with the iOS 26.5 SDK or newer. Open `DashPilot.xcodeproj`, select the `DashPilot` scheme,
and run on an installed iPhone simulator. There are no third-party runtime dependencies or setup scripts.

```sh
xcodebuild build -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

See [building and running](https://quangshuynh.github.io/dashpilot/development/building/)
and [testing and development](https://quangshuynh.github.io/dashpilot/development/testing/)
for test commands, simulator selection and the separate documentation toolchain.

## Documentation

- [First shift](docs/product/first-shift.md) and
  [product overview](https://quangshuynh.github.io/dashpilot/product/overview/)
- [Delivery lifecycle](https://quangshuynh.github.io/dashpilot/product/delivery-lifecycle/),
  [expenses](https://quangshuynh.github.io/dashpilot/product/expenses/) and
  [Insights](https://quangshuynh.github.io/dashpilot/product/insights/)
- [Data export](https://quangshuynh.github.io/dashpilot/product/history-export/) and
  [architecture](https://quangshuynh.github.io/dashpilot/architecture/overview/)

The documentation source is in [`docs/`](docs/index.md).

## License

[MIT](LICENSE).
