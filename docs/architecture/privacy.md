# Privacy and logging

DashPilot is local-first by construction, not by policy. There is no network code in the project, so
there is nothing to configure, disable or trust.

## What that means concretely

- All data stays on device. There are no accounts, no sync, no analytics, no telemetry and no ads.
- There is no third-party SDK of any kind, so nothing is collected on anyone else's behalf.
- Recorded route samples never leave the device.
- Precise coordinates, routes, earnings, recorded costs and the notes written on them, delivery
  history, pickup-place names and the waits recorded at them are treated as sensitive: they are not logged, and they are never committed to the
  repository. For a driver who
  works a small area, the places they pick up from are close to a description of where they are.
- Pickup places are typed by the driver. There is no geocoding, no place search and no directory
  lookup, so no name here was obtained from, or sent to, anywhere off the device.
- A route sample belongs to exactly one shift and is deleted with it, including when the driver
  deletes the shift themselves, so no coordinate is left behind belonging to a shift that no longer
  exists.
- Deletion is local and permanent. A deleted shift is removed from the device's store, and there is
  no copy anywhere else to remove it from.
- Location permission is requested at the When In Use scope only, and only when the driver taps.
- **Export is the one way data leaves, and it is a user action.** DashPilot writes a JSON or CSV file
  into a temporary directory on the device when the driver taps an export control, and hands it to
  the system share sheet. Nothing exports on a schedule, on shift end or at launch, and there is
  still no network code for anything to be uploaded through. Where the file goes next is whatever the
  driver picks in the share sheet — once it is in another app, a drive or a message, it is outside
  DashPilot. See [History export](../product/history-export.md).
- **A standard export contains no coordinates.** A shift's route appears in it as a measurement and a
  description of its coverage, never a latitude, a longitude, a timestamped position or a
  capture-session identifier. Exporting raw positions would be a separate, explicit feature with its
  own consent; there is a test asserting they are absent.
- **Expense notes are exported**, because they are the driver's own record and a file that dropped
  them would hand back less than they entered. They are free text and are treated exactly as a place
  name is: never logged, and out of the app only through an export the driver started.
- **Pickup place names are exported**, because they are part of the driver's own recorded history and
  the file would be much less useful without them. They can reveal where someone works. The
  normalised matching key is never exported.
- **Exports do not accumulate.** The temporary export directory is emptied before each new export and
  once at launch, so the app never holds a growing pile of copies of a driver's history.
- **A file name carries no content.** `DashPilot-Week-2026-08-31.csv` — a scope and a date, never a
  place, a merchant or an amount. A name shows up in share sheets, notifications and folder listings,
  often on someone else's screen.

## The logging rule

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

| Category | Records | Never records |
| --- | --- | --- |
| `shift` | A shift started, ended or was deleted; a transition refused; a failed store read or write | When a shift ran, what it earned, how far it went |
| `location` | Authorization transitions, Location Services availability, accuracy changes, unrecognised platform values | Any position, because this layer never reads one |
| `route-capture` | Capture started or stopped, why it could not start, how many samples were retained and persisted, and the *name* of the rule that rejected a candidate | Latitude, longitude, address or route geometry |
| `earnings` | That an amount was added, updated or removed, or that a save failed | The amount |
| `pickup-place` | That a place was assigned, changed, removed, reused, created, renamed or merged; that a name, rename or merge was refused, by rule; that a save failed | The name typed, the normalised key derived from it, and how many deliveries a merge moved |
| `expenses` | That an expense was recorded, updated or deleted, which **category** it was, whether a note exists, and that a write was refused by rule or failed | The amount, the date the money was spent, and any word of the note |
| `export` | That a file was written, for which scope and in which format, and how many shifts went into it; that an export was refused, by rule; that a write failed | Anything in the file — a date worked, an amount, a place, a distance — and the path it was written to |

Seven deliberate silences are worth stating.

**Mileage is not logged at all.** The calculation reads coordinates and produces a trip metric, and
neither belongs in a log. There is no failure it can report, because an unmeasurable route is a
normal result shown to the driver, so a log line would only record how far somebody drove.

**Derived rates are not logged**, for the same reason. An hourly rate is an earnings figure and a
per-mile rate is an earnings figure over a trip metric, and an unavailable rate is a normal result
rather than a failure.

**Pickup waits are not logged either** — not an individual wait, not a median, not a sample count and
not when a sample was recorded. How long a named driver waits at a named place is work-performance
data about a real person, and there is no failure to report: a place with too little history is a
normal result the screen states in words. Deriving a place's history writes nothing and records
nothing.

**A deletion records nothing about the shift.** Not when it ran, not what it earned, not how far it
went. A deletion is the last moment to start writing a driver's history into a log.

**An export records nothing about what it exported, and no path.** The log says a week was exported
as CSV and how many shifts it held. It does not say which week, what those shifts earned, how far
they went, or where on the device the file landed — a path names a location on someone's phone and
tells a reader nothing they can act on.

**A recorded cost is logged only as a category.** Not the amount, not the day money was spent, and
not a word of the note — a note is free text the driver typed, and a date and an amount together are
a description of their spending. The category is a fixed word from a closed set, chosen in code, so
it cannot accidentally become the value. Nothing about a period's expense total, its split by
category or the net after it is logged at all: every one of those is a derived figure that is a
normal result rather than a failure, exactly as a rate is.

**A merge records nothing about what it moved.** The log says two pickup places were merged, and not
which two or how many deliveries changed hands. A count of a driver's pickups at one place is work
history, which is the thing this category exists to keep out.

The word naming an earnings or pickup-place operation is a `StaticString` chosen in code, so it
cannot accidentally become the value; where a pickup log line has two forms, they are two literals
rather than one interpolated word. A test asserts that every capture rejection reason is a plain rule
name rather than a candidate position.

## Synthetic data everywhere

Every coordinate, amount, route and business name in this repository is invented. Tests, previews,
fixtures, documentation and screenshots use `SyntheticRoute`, which builds offsets from a
round-number origin rather than from anywhere anyone has driven, amounts chosen to be obviously
fictional, pickup places — `Nowhere Noodles`, `Example Diner` — that name no real business, and
expense notes describing nothing that happened.

The debug-only `-dashpilot-seeded-history` launch argument opens an in-memory store holding that
same synthetic history, which is how a measured route and the rates over it are reachable in a UI
test and in a screenshot without recording a real drive.

Real user data is never committed, and `context.md`, the owner's local working notes, is excluded
from Git for the same reason.

## What is not claimed

DashPilot does not claim encryption beyond what iOS provides for app storage, does not claim
anonymisation, and does not claim that any of this has been independently audited. It claims exactly
one thing: the data is on the device, because there is nowhere else for it to go.
