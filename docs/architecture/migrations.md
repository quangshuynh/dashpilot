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

The current version is **v7**. Field-level detail is on [Data model](../reference/data-model.md).

`DashPilotSchemaV1` through `DashPilotSchemaV6` hold frozen copies of their models rather than
reusing the file-scope types, which have moved on. The plan then describes where a store is coming
from as truthfully as where it is going, and the copies are never used at runtime outside
migration.

`DashPilotSchemaV6` was frozen in the interval that added v7: the file-scope `Delivery` gained a
recorded amount of its own, so reusing it would have made v6 claim a shape no store on a device ever
had. Each version gets its copies at the moment the next one moves the models on, exactly as v5 got
its own when v6 added pickup places.

## Every stage so far is lightweight, deliberately

Each step has been purely additive, and each time the decision not to backfill was the substantive
one.

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

It becomes a custom stage the first time a version step actually has to transform something.

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
