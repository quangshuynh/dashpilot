# Persistence

SwiftData is the only store. There is no cache, no file export, no defaults-backed copy of shift
data and no remote database.

## Container construction

`ModelContainerFactory` builds every container from the current schema and passes
`DashPilotMigrationPlan`. Wiring the plan up front from v1 meant adding v2 was an ordinary change
rather than a store reset.

Container creation throws instead of trapping. `DashPilotApp` builds the container once at launch
and renders `PersistenceUnavailableView` on failure, which is a visible state a driver can act on
rather than a crash.

Tests and previews use `makeInMemoryContainer()`, which shares the same schema and the same
migration plan as the shipping store, so a schema mistake fails in tests rather than only on a
device.

| Entry point | Used by | Behaviour |
| --- | --- | --- |
| `makeContainer()` | The app | Current schema, migration plan, on-disk store |
| `makeContainer(at:)` | Tests | The same, at an explicit URL, so a store can be closed and reopened |
| `makeContainer(versionedSchema:at:)` | Tests | A store opened under a historical version *without* the plan, so a test can write a store shaped the way an older build would have left it |
| `makeInMemoryContainer()` | Tests, previews | Current schema and plan, nothing on disk |

## What is stored

Two entities. Their fields are listed under [Data model](../reference/data-model.md).

`Shift` holds a start timestamp, an optional end timestamp and an optional gross earnings amount.
Everything else about a shift, including its duration, its distance and its rates, is derived when
it is asked for.

`RouteSample` stores a timestamp, a latitude, a longitude, a horizontal accuracy and the capture
session it was recorded in, and nothing else. `CLLocation` also reports speed, course, altitude and
their accuracies, but nothing implemented reads them, and a coordinate history is sensitive enough
that each field needs a reason rather than an availability.

## The delete rule

`Shift.routeSamples` uses `deleteRule: .cascade`, and has since v2. A shift's route describes that
shift and nothing else, so deleting the shift takes its positions with it. The orphans would
otherwise be exactly the sensitive rows the app promises to keep accountable to a shift.

When a driver deletes a completed shift, the samples go through this existing rule rather than
through a loop in the service. Tests assert that the deleted shift's positions are gone, that
another shift's positions and recorded amount are untouched, and that a refused delete changes
nothing at all.

## Earnings are stored as a decimal

`Shift.grossEarningsAmount` is a `Decimal`, not a `Money` and not a `Double`. SwiftData persists a
`Decimal` as a decimal attribute, so the exact amount survives a round trip with no binary floating
point in the store and no second monetary type in the app. The property is private;
`grossEarnings` and `setGrossEarnings(_:)` are the conversion, in one place, and the rest of the app
only ever holds a `Money`.

`nil` and zero are different facts everywhere: in the model, in migration, in the interface and in
the metrics. `nil` means the driver has not recorded what the shift paid; `0` means they recorded
that it paid nothing. Removing an amount is therefore its own operation (`clearGrossEarnings()`)
rather than an empty text field that ambiguously means both "invalid" and "delete".

Two invariants live on the model rather than in a view, so no screen, test or later caller can set
an amount the app would refuse to display: earnings can be recorded only on a **completed** shift,
and never **negative**. `ShiftService` adds the store write and the same rollback rule the lifecycle
transitions use, so an amount can never be showing in the interface while the store holds something
else.

## Writes during capture

Accepted route samples are inserted immediately and saved in batches of ten. Saving on every
callback would mean a store write roughly once a second for the length of a shift; building a
batching subsystem without measurement would be solving a problem nobody has demonstrated. Ten is
the smallest step that removes the per-callback write, and every deliberate stop (backgrounding,
ending a shift, losing permission) flushes first, so the exposure to an abrupt kill is a few seconds
of route.

A failed save rolls back. The last accepted sample is cleared with it, because the row it referred
to no longer exists, and the next candidate is judged as the first of the route, which is what it
is. Capture stops and the state says the store is unavailable, rather than continuing to collect
samples that cannot be kept.

When capture is pointed at a shift again, the newest already-stored sample is read back with a
one-row fetch, so capture resumed after a relaunch, a backgrounding or a permission interruption
still judges candidates against the route as it stands. Walking `shift.routeSamples` to find it
would load an entire shift's route to look at one row.

## Schema evolution

Schema versions and the reasoning behind each migration step are on
[Migrations](migrations.md).
