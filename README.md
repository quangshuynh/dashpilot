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
- Shift lifecycle: start a shift, end the running shift, and a single-active-shift rule enforced in
  `ShiftService` against the store rather than by disabling a button. Rejected and failed
  transitions are reported to the driver instead of being swallowed.
- Relaunch recovery: a shift still running when the app was terminated is picked up on the next
  launch with its original start time, because the store is the only place shift state lives.
- Root screen: start/end controls, an elapsed timer derived from the start timestamp, and a list of
  completed shifts.
- Location authorization: DashPilot models Core Location's permission and accuracy states
  separately — not determined, denied, restricted, When In Use, Always, plus the system-wide
  Location Services switch and full versus reduced accuracy — and shows the current state on the
  root screen with the one recovery that actually applies to it. Permission is requested only when
  the driver taps, and only at the When In Use scope.
- `Money`, a `Decimal`-backed monetary type covering the app's arithmetic, rounding, rate division
  and formatting.
- App shell that surfaces a store-open failure as a visible state instead of crashing.

**Not implemented yet**

Route capture, mileage, earnings entry, delivery records, wait-time measurement, maps, App Intents,
Live Activities and recommendations. Nothing about a shift is recorded beyond its start and end
times. DashPilot reads its location *permission* but does not read, record or store any location:
there is no tracking, no background location and no route history. See `AGENTS.md` for the intended
order of work.

## Privacy

- All data stays on device. There are no accounts, no sync, no analytics, no telemetry and no ads.
- Precise coordinates, routes, earnings and delivery history are treated as sensitive: they are not
  logged through OSLog and are never committed to this repository.
- Location logging records permission and accuracy state only — what the app is allowed to do, never
  where the device is.
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
