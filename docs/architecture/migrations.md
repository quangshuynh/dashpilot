# Migrations

The store has been versioned since v1, and the migration plan was wired up before there was
anything to migrate. That decision is why every version step since has been an ordinary change
rather than a store reset.

## Versions

| Version | Change |
| --- | --- |
| 1.0.0 | `Shift` only: id, start, optional end |
| 2.0.0 | Adds `RouteSample`, and a `Shift.routeSamples` relationship |
| 3.0.0 | Adds `RouteSample.captureSessionID`, an optional marker of capture continuity |
| 4.0.0 | Adds `Shift.grossEarningsAmount`, an optional `Decimal` holding manually entered earnings |
| 5.0.0 | Adds the `Delivery` entity and a `Shift.deliveries` relationship |
| 6.0.0 | Adds the `PickupPlace` entity and an optional `Delivery.pickupPlace` reference |
| 7.0.0 | Adds `Delivery.grossEarningsAmount`, an optional `Decimal` holding manually entered per-delivery earnings |
| 8.0.0 | Adds the `Expense` entity. No existing entity changes, and no relationship is added |
| 9.0.0 | Adds the `ShiftPause` entity and a `Shift.pauses` relationship. No existing attribute changes |
| 10.0.0 | Removes the `Shift.routeSamples` relationship. `RouteSample.shift` is unchanged, and no stored value moves |
| 11.0.0 | Adds `Delivery.expectedEarningsAmount`, an optional `Decimal` holding what the driver expects an active delivery to pay |
| 12.0.0 | Adds the `Offer` entity, an optional `Delivery.offer` reference and a `Shift.offers` relationship. Backfills one offer per existing delivery |

The current version is **v12**. Field-level detail is on [Data model](../reference/data-model.md).

`DashPilotSchemaV1` through `DashPilotSchemaV11` hold frozen copies of their models rather than
reusing the file-scope types, which have moved on. The plan then describes where a store is coming
from as truthfully as where it is going, and the copies are never used at runtime outside
migration.

`DashPilotSchemaV11` was frozen in the interval that added v12, and the freeze was forced the way
v10's was: v12 adds an entity and a reference to it on `Delivery`, so reusing the file-scope types
under v11 would describe every pre-v12 store as one that already recorded which deliveries were
accepted together. It did not, and a version that claims otherwise cannot be used to prove a
migration preserved anything. Each version gets its copies as the plan moves past it.

## Every stage but the last is lightweight, deliberately

Every step up to v11 is purely additive, and each time the decision not to backfill was the
substantive one. v10 is the only one that removes anything, and it removes a relationship rather
than any stored value. v12 is the first custom stage, and it is custom because it has something to
transform rather than because it has something to tidy.

### v1 to v2

A new entity and a new empty relationship. SwiftData can apply that without being told how, and
there is nothing to derive: a shift recorded before route capture existed genuinely has no route. A
custom stage would be code with nothing to do, and a `willMigrate` and `didMigrate` pair that walks
every shift for no reason is a way to lose data, not a way to protect it.

### v2 to v3

One new optional attribute on an existing entity. Nothing is backfilled, and that is the point: a
capture session identifier states that two samples were recorded without an interruption, and a v2
store holds no evidence of that either way. Grouping legacy samples into invented sessions would
produce exactly what the attribute exists to prevent, which is a gap presented as a continuous
stretch of driving.

Migrated samples keep `nil`, and the mileage calculation treats their continuity as inferred rather
than proven, which is why such a route is always reported as partial.

### v3 to v4

One new optional attribute on `Shift`. A v3 store records no earnings at all, which is not the same
statement as "these shifts paid nothing". Writing `0` into every existing shift would turn the
absence of a figure into a claim about every shift a driver has ever recorded, and there would be no
way afterwards to tell a fabricated zero from one they typed.

Migrated shifts keep `nil`, and the interface offers to add an amount rather than showing one.

### v4 to v5

A new entity and a new empty relationship — the same shape as v1 to v2, and with the same nothing to
derive. A shift recorded before delivery recording existed genuinely has no deliveries: DashPilot
observes no delivery platform, so there is no source anywhere in the store from which a past
delivery could be reconstructed. Inventing one per hour, per route segment or per anything else
would write work into a driver's history that they never recorded, and nothing afterwards could
tell it from work they did.

Existing shifts migrate with zero deliveries, and their route samples, capture session identifiers
and recorded amounts are untouched.

### v5 to v6

A new entity and a new optional reference to it, which SwiftData can add without being told how.
Every existing delivery migrates with no pickup place, and the catalogue of places starts empty.

That emptiness is the substantive decision, in the same shape as v4 to v5. A v5 store records nothing
about which business any delivery came from, and DashPilot has no source from which to recover one:
it reads no delivery platform, resolves no address, and holds no merchant data of any kind.
Attributing a past delivery to a place by its route, its timing or its resemblance to another would
write a business's name into a driver's history on the app's authority rather than theirs, and no
later screen could tell that apart from a place the driver named themselves.

The pickup place's own uniqueness is enforced in `PickupPlaceService`, not by a `.unique` attribute.
That is partly a migration decision: a unique constraint would bind the store's shape to a
normalisation policy that is allowed to improve, and improving it would then become a schema change
rather than a code change. See [Pickup identity](../product/pickup-identity.md#reuse-and-which-spelling-wins).

### v6 to v7

One new optional attribute on `Delivery`, the same shape as v3 to v4 one entity along. Every
existing delivery migrates with no amount recorded, and every shift keeps the amount it already had.

The temptation this stage refuses is the one thing it could plausibly have done. A v6 store often
holds a completed shift with a recorded total *and* the deliveries performed during it, so a number
and a set of rows to spread it over are both sitting right there. Spreading it — evenly, by
duration, by pickup wait, by anything — would put a figure against each delivery that the driver
never typed, and no later screen, calculation or export could tell it apart from one they did.

The two amounts are **independent facts entered separately**, and neither is evidence for the other:
deliveries go unrecorded, stacked orders are paid together, and adjustments post at shift level. A
migrated delivery keeps `nil`, which the app reads as "not recorded" and never as `0.00`, and the
interface offers to add an amount rather than showing one. See
[Earnings and metrics](../product/earnings-and-metrics.md#per-delivery-gross-earnings).

### v7 to v8

A new entity with **no relationship to anything**, which SwiftData can add without being told how.
Not one existing entity changes shape, so there is nothing to rewrite, reinterpret or walk: every
shift, route sample, capture session identifier, delivery, lifecycle timestamp, pickup place and
recorded amount carries over untouched, and the expense table starts empty.

Empty is the only honest state for it. A v7 store records what a driver's work paid and nothing about
what it cost, and DashPilot has no source from which a past cost could be recovered: it observes no
purchase, reads no card, receipt or platform, and models no fuel consumption or vehicle wear.
Deriving fuel from recorded mileage, or a per-mile vehicle charge from anything at all, would write
costs the driver never entered into their history, and this fabrication would be worse than an
invented earnings figure, because every net figure the app shows would then be built on it.

The absence of a relationship is itself the modelling decision, not a shortcut: an expense carries
its own date, and a period contains it by that date. See
[Recorded expenses](../product/expenses.md).

### v8 to v9

A new entity and a new empty relationship, which SwiftData can add without being told how. It is the
same shape as v1 to v2 and v4 to v5. No existing attribute moves, and in particular `Shift.endedAt` is
untouched, so `endedAt == nil` still means the shift has not finished and every fetch, invariant and
relaunch-recovery path written against that definition keeps working.

**Every migrated shift keeps the duration it has always had.** Working duration is elapsed time less
recorded pause time, a shift with no pauses has zero pause time, and zero here is a measurement
rather than a missing value: a build that could not pause a shift did not leave the question
unanswered, it made the answer none. So a pre-v9 shift's working duration is exactly its elapsed
duration, and every hourly rate, period total and exported figure derived from it is unchanged by
this version.

What this stage refuses is the inference that looks reasonable. A gap in a route, a long stretch with
no delivery recorded, an unusually long shift: each resembles a break, and none is evidence of one.
DashPilot observes nothing about why a driver was not moving, so reading any of them as a pause would
shorten a shift the driver recorded as whole, raise every rate derived from it, and leave no way
afterwards to tell an invented pause from one they tapped. See
[Pausing a shift](../product/shift-workflow.md#pausing-a-shift).

### v9 to v10

A relationship declared from one side instead of two, which SwiftData can apply without being told
how. Nothing is added, removed, retyped or rewritten: the column saying which shift a position
belongs to lives on `RouteSample` and is untouched, so every stored route keeps every one of its
samples, every sample keeps its shift, its timestamp, its coordinate, its accuracy and its capture
session identifier, and every recorded mileage figure measures exactly what it measured before.

**This is a version rather than a quiet edit, and the distinction is worth stating.** A v9 store does
open against the v10 models with every sample still resolving to its shift, because the foreign key
never moves. That is not the same as the store being unchanged: reopening a v9 store under v10
rewrites the recorded version hashes of both `Shift` and `RouteSample`, which is SwiftData saying the
model is a different one and that it has migrated the store. The surviving foreign key is exactly
what makes it tempting to treat this as no change at all.

What the stage must **not** become is a cleanup. A route sample whose shift is missing is not
something this version creates, and deleting rows here on the theory that some might be orphaned
would destroy recorded history to tidy a table.

Why the collection went at all is a performance finding, not a modelling preference. See
[Persistence](persistence.md#a-shift-does-not-hold-its-route).

### v10 to v11

One new optional attribute on an existing entity, which SwiftData can add without being told how. It
is the same shape as v3 to v4 and v6 to v7, and it has the same nothing to derive: a delivery
recorded before the app could ask what an order was expected to pay has no expectation, because none
was ever entered. Every migrated delivery keeps `nil`, which the app reads as "not recorded" and
never as `0.00`.

**The inference this stage refuses is sitting in plain sight.** A v10 store often holds a delivered
delivery with a recorded gross amount, and copying that figure into the new column would produce,
for most deliveries, exactly the number the driver would have typed. It would also be the app
asserting on its own authority that they expected what they were paid, in the one column whose whole
purpose is to be distinguishable from the amount beside it. Nothing afterwards could tell an
invented expectation from an entered one, and the first screen to show *expected $8.50 · recorded
$8.50* would be stating a coincidence the migration manufactured.

No figure a driver has already recorded changes value, and nothing derived from one moves: shift
gross, period gross, every rate, the delivery-earnings subtotal and every exported summary are built
from `grossEarningsAmount` alone, before this version and after it. See
[Expected pay](../product/delivery-lifecycle.md#expected-pay).

### v11 to v12

**The first custom stage in the app's history.** Adding the `Offer` entity and the reference to it
would migrate lightweight on its own, and that is exactly what must not be left to happen: it would
leave every delivery a driver has ever recorded holding no offer, in a build where a delivery
holding no offer is a row the app cannot produce. Every screen, every grouping and every exported
record would then carry a second reading for history, forever.

So `didMigrate` walks the deliveries and gives **each one its own one-delivery offer**, taking that
delivery's own acceptance timestamp. That is the truthful reconstruction and the whole of it: a v11
store records one acceptance per delivery, because that is how the driver recorded them.

**The inference this stage refuses is the one that looks like free information.** Two deliveries
accepted a second apart, or sharing a pickup place, or overlapping completely, all look like a
stacked offer, and none of them is evidence of one: a driver tapping Start Delivery twice in a row
produces exactly that shape, and so does a driver accepting two separate orders outside the same
restaurant. Grouping them would invent platform metadata the store has never held, on the app's
authority rather than the driver's.

No figure moves. An offer holds no money, no duration and no distance, so shift gross, delivery
gross, expected pay, delivery active time, every rate, every period total and every exported summary
are derived from exactly what they were derived from before. See
[Offers](../product/delivery-lifecycle.md#offers-and-deliveries).

Two rows are left alone rather than repaired: a delivery already holding an offer, which a v11 store
cannot contain but a re-entrant migration could present, and a delivery attached to no shift at all,
which has no shift for an offer to belong to.

## Proving a migration rather than assuming it

`ModelContainerFactory.makeContainer(versionedSchema:at:)` is a test seam that opens a store under a
historical version **without** the plan. A test can therefore write a store shaped the way an older
build would have left it, close it, and then open it normally through the shipping factory.

That is how "a v1 store keeps its shifts" is proven. The suite covers each step:

- A v1 store's shifts survive, with their start and end timestamps intact and no route.
- A v2 store's shifts and route samples survive, and the migrated samples carry no capture session.
- A v3 store's shifts, samples and sessions survive, and their earnings are absent rather than zero.
- A v4 store's shifts, samples, sessions and recorded amounts survive, and no delivery is
  fabricated for any of them.
- A v5 store's shifts, samples, sessions, amounts and every delivery timestamp survive, and no
  delivery is attributed to a pickup place that was never named.
- A v6 store's shifts, samples, sessions, shift amounts, deliveries, pickup places and the
  relationships between them survive — with the pickup waits and the delivery active time they
  produce identical afterwards — and no delivery is given an amount. One case is built specifically
  to make dividing a round shift total by four deliveries look reasonable, and asserts that it does
  not happen.

- A v7 store's shifts, samples, sessions, shift amounts, deliveries, pickup places, per-delivery
  amounts and the derived results over them survive, and the new expense table is empty. One case
  presents a store holding an amount, a route and deliveries, which is everything a plausible cost
  could have been derived from, and asserts that no expense is fabricated from any of it.

- A v8 store's shifts, samples, sessions, amounts, deliveries, pickup places and expenses survive
  with **their durations unchanged**, and the new pause table is empty. One case drives a long shift
  with a single early delivery and a route that stops after it, which is the shape that most
  resembles a break, and asserts that it keeps a working duration equal to its elapsed one.

- A v11 store's shifts, samples, sessions, amounts, deliveries, pickup places, expected amounts,
  pauses and expenses survive, and **every delivery comes out inside a one-delivery offer of its
  own**. One case holds two deliveries accepted a second apart on the same shift, which is the shape
  a grouping inference would seize on, and asserts that they end up in two different offers. Another
  asserts that a shift's unioned delivery active time, its delivery-earnings coverage and its hourly
  rate are the figures they were before the step.

Each step is also walked from every earlier version, so a device that skipped several releases is
covered by the same suite rather than by assumption.

## Rules for the next schema change

- Consider compatibility before adding or renaming anything.
- Preserve existing user data. A destructive reset is not a substitute for a migration.
- Add coverage for the new step in the same interval that adds the step.
- When a version step has to transform data, write a custom stage and test the transformation, not
  just the fact that the store opens.
- Do not invent a value to fill a column that older data genuinely does not answer. Optional and
  absent is a truthful migration; a fabricated default is not.
