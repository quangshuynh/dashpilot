# Privacy and logging

DashPilot is local-first by construction, not by policy. There is no network code in the project, so
there is nothing to configure, disable or trust.

## What that means concretely

- All data stays on device. There are no accounts, no sync, no analytics, no telemetry and no ads.
- There is no third-party SDK of any kind, so nothing is collected on anyone else's behalf.
- Recorded route samples never leave the device.
- Precise coordinates, routes, earnings and delivery history are treated as sensitive: they are not
  logged, and they are never committed to the repository.
- A route sample belongs to exactly one shift and is deleted with it, including when the driver
  deletes the shift themselves, so no coordinate is left behind belonging to a shift that no longer
  exists.
- Deletion is local and permanent. A deleted shift is removed from the device's store, and there is
  no copy anywhere else to remove it from.
- Location permission is requested at the When In Use scope only, and only when the driver taps.

## The logging rule

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

| Category | Records | Never records |
| --- | --- | --- |
| `shift` | A shift started, ended or was deleted; a transition refused; a failed store read or write | When a shift ran, what it earned, how far it went |
| `location` | Authorization transitions, Location Services availability, accuracy changes, unrecognised platform values | Any position, because this layer never reads one |
| `route-capture` | Capture started or stopped, why it could not start, how many samples were retained and persisted, and the *name* of the rule that rejected a candidate | Latitude, longitude, address or route geometry |
| `earnings` | That an amount was added, updated or removed, or that a save failed | The amount |

Three deliberate silences are worth stating.

**Mileage is not logged at all.** The calculation reads coordinates and produces a trip metric, and
neither belongs in a log. There is no failure it can report, because an unmeasurable route is a
normal result shown to the driver, so a log line would only record how far somebody drove.

**Derived rates are not logged**, for the same reason. An hourly rate is an earnings figure and a
per-mile rate is an earnings figure over a trip metric, and an unavailable rate is a normal result
rather than a failure.

**A deletion records nothing about the shift.** Not when it ran, not what it earned, not how far it
went. A deletion is the last moment to start writing a driver's history into a log.

The word naming an earnings operation is a `StaticString` chosen in code, so it cannot accidentally
become the value. A test asserts that every capture rejection reason is a plain rule name rather
than a candidate position.

## Synthetic data everywhere

Every coordinate, amount and route in this repository is invented. Tests, previews, fixtures,
documentation and screenshots use `SyntheticRoute`, which builds offsets from a round-number origin
rather than from anywhere anyone has driven, and amounts chosen to be obviously fictional.

The debug-only `-dashpilot-seeded-history` launch argument opens an in-memory store holding that
same synthetic history, which is how a measured route and the rates over it are reachable in a UI
test and in a screenshot without recording a real drive.

Real user data is never committed, and `context.md`, the owner's local working notes, is excluded
from Git for the same reason.

## What is not claimed

DashPilot does not claim encryption beyond what iOS provides for app storage, does not claim
anonymisation, and does not claim that any of this has been independently audited. It claims exactly
one thing: the data is on the device, because there is nowhere else for it to go.
