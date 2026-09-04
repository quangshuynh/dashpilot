# DashPilot

Local-first iOS companion for delivery drivers. DashPilot measures shifts, mileage, time and
earnings efficiency on device so a driver can see how their work actually performs, without
handing that history to a server.

DashPilot is a general delivery-driver tool. It has no integration with DoorDash or any other
delivery platform, and it does not automate, observe or interfere with those apps. Anything that
cannot be derived legitimately from device sensors and stored history is entered by the driver or
left out.

## Status

The project is early. This section describes what exists, not what is intended.

**Implemented**

- Xcode project targeting iOS 26.5 (SwiftUI lifecycle, Swift Testing, XCUITest).
- Versioned SwiftData schema (`DashPilotSchemaV1`) with a migration plan wired in from v1.
- `Shift` model: start timestamp, optional end timestamp, elapsed and completed duration, with
  guarded end transitions.
- `Money`, a `Decimal`-backed monetary type covering the app's arithmetic, rounding, rate division
  and formatting.
- App shell that surfaces a store-open failure as a visible state instead of crashing.
- Read-only shift list on the root screen.

**Not implemented yet**

Starting and ending shifts from the UI, location authorization, route capture, mileage, earnings
entry, delivery records, wait-time measurement, maps, App Intents, Live Activities and
recommendations. See `AGENTS.md` for the intended order of work.

## Privacy

- All data stays on device. There are no accounts, no sync, no analytics, no telemetry and no ads.
- Precise coordinates, routes, earnings and delivery history are treated as sensitive: they are not
  logged through OSLog and are never committed to this repository.
- Sample data in tests, previews and documentation is synthetic.

## Architecture

See [docs/Architecture.md](docs/Architecture.md).

## Building

Requires Xcode 26.6 or later.

```
xcodebuild build -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Tests:

```
xcodebuild test -project DashPilot.xcodeproj -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## License

See [LICENSE](LICENSE).
