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
- Versioned SwiftData schema with a migration plan wired in from v1 and exercised by tests.
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
- Foreground route capture: while a shift is running and DashPilot is open, accepted positions are
  recorded against that shift and stored on device. Capture starts and stops with the shift, resumes
  for a shift that was still running when the app was terminated, and stops when permission is lost
  — without ending the shift. The running shift shows whether capture is active, paused because the
  app is in the background, or unavailable.
- Sample filtering: one acceptance policy (`RouteSampleFilter`) judges every candidate position —
  invalid coordinates, invalid or poor accuracy, cached stale fixes, duplicate and out-of-order
  timestamps, movement too small to be movement, and jumps too fast to be real. A rejected sample is
  dropped and capture continues.
- Capture continuity: every retained position records the uninterrupted stretch of capture it
  belongs to, which is what lets mileage tell a recorded route apart from the gaps in it.
- Recorded mileage: DashPilot derives a completed shift's distance from its retained route, summing
  only what was captured continuously and excluding the distance across detected capture gaps. The
  figure is derived from the stored route every time rather than saved as a second total, and a
  shift's history row shows it as recorded — and as partial when the route is known not to cover the
  whole shift.
- Manual gross earnings: a completed shift can store one optional amount the driver types, with a
  locale-aware input layer that reads what a decimal pad produces — a whole number, one or two
  decimal places, a currency symbol, grouping separators — and refuses anything it cannot read
  rather than reinterpreting it. Amounts are added, edited and removed from a sheet on the shift's
  history row, never during a running shift, and the row shows the recorded amount.
- Completed-shift metrics: gross earnings per elapsed shift hour and gross earnings per recorded
  mile, derived from what is already stored and shown on the shift's history row. Nothing is saved
  as a second total, and a rate that cannot be derived is absent rather than shown as zero — a shift
  with no amount recorded, a shift with no measurable route and a shift that covered no time each
  say nothing rather than something false.
- Schema v4, with lightweight migrations from v1, v2 and v3, covered by tests that open stores
  written under each older version and check their shifts, positions and absent earnings survive.
- `Money`, a `Decimal`-backed monetary type covering the app's arithmetic, rounding, rate division
  and formatting. No monetary value passes through binary floating point, in memory or in the store.
- App shell that surfaces a store-open failure as a visible state instead of crashing.

**Not implemented yet**

Expenses, fuel, taxes, mileage deductions, a tips-versus-base breakdown, per-delivery earnings,
active-versus-idle time, delivery records, wait-time measurement, maps, App Intents, Live Activities
and recommendations. A shift records its start time, its end time, its route and — if the driver
types one — a single gross earnings figure. Rates are shown only on completed shifts, no route is
drawn, and no mileage or live rate is shown while a shift is still running. See `AGENTS.md` for the
intended order of work.

**Earnings are what the driver typed.** DashPilot is not connected to a delivery platform, holds no
account credentials and imports nothing: the amount on a shift is one number a driver chose to
associate with it. The app does not know whether it includes tips, bonuses, promotions, adjustments
or reimbursements, so it is labelled gross earnings and never profit, take-home or a taxable amount.
Entering an amount is optional — a shift with none recorded is a complete shift, and that is a
different state from a shift recorded as paying `$0.00`.

**The rates are gross, and each says what it divides by.** The hourly figure is gross earnings over
the shift's whole elapsed time — waiting and idling included — because DashPilot does not know how
much of a shift was spent on a delivery; it is not an active or working hourly rate. The per-mile
figure is gross earnings over *recorded* miles, which are normally fewer than the miles driven, so
the rate is normally higher than earnings per mile driven. Neither subtracts expenses, fuel, wear or
tax, and neither is a profit, net earnings or tax figure.

**Recorded mileage is what was recorded, not what was driven.** Capture is foreground-only, so a
shift's route has a gap whenever DashPilot was not open. Distance across a gap is left out rather
than guessed at with a straight line, which means the figure is normally lower than the miles
actually driven, and a shift with known gaps is labelled a partial route. It is not a tax or
deduction figure, no mileage is separated per delivery, and nothing here is calibrated against real
driving yet.

**Route capture is foreground only.** There is no background location mode, no Always authorization,
no significant-location-change or region monitoring and no background task. When DashPilot is not in
the foreground, capture stops and the route has a gap in it. iOS does not guarantee uninterrupted
background execution, and the app does not claim it: the running shift says plainly when capture is
paused. Background route continuity is a separate, later decision.

## Privacy

- All data stays on device. There are no accounts, no sync, no analytics, no telemetry and no ads.
- Precise coordinates, routes, earnings and delivery history are treated as sensitive: they are not
  logged through OSLog and are never committed to this repository.
- Recorded route samples never leave the device. There is no network code in the project.
- Location logging records permission state, accuracy state, capture state, sample counts and the
  name of the rule that rejected a sample — what the app is allowed to do and what the pipeline did,
  never where the device is.
- A route sample belongs to exactly one shift and is deleted with it.
- Mileage is calculated on device and never logged: distance is a trip metric, and the logs record
  what the app did, not where the driver went or how far.
- Derived rates are calculated on device and never logged, for the same reason as the amounts and
  the mileage they come from.
- Earnings are stored on device and never logged. The earnings log records that an amount was added,
  changed or removed, or that a save failed — never the amount itself.
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
