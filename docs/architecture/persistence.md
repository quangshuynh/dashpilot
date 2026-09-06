# Persistence

SwiftData is the only store. There is no cache, no file export, no defaults-backed copy of shift
data and no remote database.

## Container construction

`ModelContainerFactory` builds every container from the current schema and passes
`DashPilotMigrationPlan`. Wiring the plan up front from v1 meant adding v2 was an ordinary change
rather than a store reset.

Container creation throws instead of trapping. `AppModelContainer` opens the process's container
once, lazily, and is the one place the app's own store is chosen; `DashPilotApp` renders
`PersistenceUnavailableView` on failure, which is a visible state a driver can act on rather than a
crash. The scene and the App Intents share that single container, so a write made without a screen is
visible to the screen when there is one.

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

Five entities. Their fields are listed under [Data model](../reference/data-model.md).

`Shift` holds a start timestamp, an optional end timestamp and an optional gross earnings amount.
Everything else about a shift, including its duration, its distance and its rates, is derived when
it is asked for.

`Delivery` stores five timestamps and its shift. Its state is derived from which of those
timestamps exist rather than stored beside them, so nothing in the store can disagree with the
events it summarises. Nothing identifying a restaurant, a customer or an address is stored, and no
amount is attributed to a delivery.

`Expense` stores when a cost was incurred, its amount, its category and an optional short note.
It has **no relationship to anything**. See below.

`RouteSample` stores a timestamp, a latitude, a longitude, a horizontal accuracy and the capture
session it was recorded in, and nothing else. `CLLocation` also reports speed, course, altitude and
their accuracies, but nothing implemented reads them, and a coordinate history is sensitive enough
that each field needs a reason rather than an availability.

## The delete rules

`Shift.routeSamples` uses `deleteRule: .cascade`, and has since v2. `Shift.deliveries` uses it too,
since v5. A shift's route and its deliveries describe that shift and nothing else, so deleting the
shift takes both with it. The orphans would otherwise be exactly the sensitive rows the app promises
to keep accountable to a shift.

A delivery's own optional amount, added in v7, is an attribute rather than a relationship, so it
goes with the delivery under the same cascade — which is why the delete confirmation names every
amount recorded on a shift *and* on its deliveries.

`Delivery.pickupPlace`, added in v6, deliberately does **not** cascade, in either direction. A pickup
place is shared between deliveries and between shifts, so deleting a delivery — or the shift that
cascades to it — must leave the place standing for everything else that still names it, and deleting
a place must never take deliveries with it. The inverse `PickupPlace.deliveries` nullifies. A place
left referenced by nothing is kept rather than collected: it stops being *recent*, and typing the
name again finds it. Deleting a driver's own vocabulary as a side effect of deleting a shift would
widen the one operation this project keeps deliberately narrow.

When a driver deletes a completed shift, all of this goes through the existing rules rather than
through a loop in the service. Tests assert that the deleted shift's positions and deliveries are
gone, that another shift's rows and recorded amount are untouched, that no delivery is left without a
shift, that a pickup place another delivery still names survives, and that a refused delete changes
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

## An expense is stored unattached

`Expense` has no `shift` and no `delivery`, and nothing anywhere in the store relates one to the
other. That is the modelling decision behind the feature rather than a simplification: a tank of fuel
is burned across several shifts, a set of tyres across thousands of miles, and attaching a cost to
whichever shift happened to be running when it was typed would record an attribution the driver never
made. It is the same fabrication the app refuses when it declines to divide a shift's amount among
its deliveries.

Membership is by date. A period contains an expense if its `occurredAt` falls in the period, by the
same half-open rule that puts a shift in one. Two consequences follow directly from the shape: there
is no shift-level or delivery-level cost, and deleting a shift cascades to nothing, because an
expense has no relationship to be cascaded along, and the cost happened whether or not the shift's record is
still there.

The amount is a `Decimal` for the reason a shift's is, and it is **required**: an expense with no
amount is not a record of anything. A recorded `0.00` is still a recorded amount. The category is
stored as a plain string rather than as the enum, so a stored word a build cannot name reads as
`other` rather than failing a fetch, which is the same reason `PickupPlace` stores plain strings.

## Delivery state is not a column

`Delivery` has no persisted `state` and no `isPickedUp`-style booleans. `state` is computed from
`arrivedAtPickupAt`, `pickedUpAt`, `deliveredAt` and `cancelledAt`, so there is one authoritative
answer to what a delivery is doing and it is the same data that forms the historical record.

"Active" is likewise a query, not a flag: `deliveredAt == nil && cancelledAt == nil`. That is what
makes relaunch recovery ordinary rather than a code path — a delivery left running when the app was
terminated is simply still running when a new `DeliveryService` reads the store, with its original
timestamps, all of them, each with its own state. Several unfinished deliveries are ordinary rather
than an anomaly; what the same fetch reports as a structural fault is an active delivery attached to
a shift that has already ended. The rule holds across a
relaunch as well as within a session.

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
