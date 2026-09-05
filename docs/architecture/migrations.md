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

The current version is **v5**. Field-level detail is on [Data model](../reference/data-model.md).

`DashPilotSchemaV1` through `DashPilotSchemaV4` hold frozen copies of their models rather than
reusing the file-scope types, which have moved on. The plan then describes where a store is coming
from as truthfully as where it is going, and the copies are never used at runtime outside
migration.

`DashPilotSchemaV4` was frozen in the interval that added v5: the file-scope `Shift` gained a
`deliveries` relationship, so reusing it would have made v4 claim a shape no store on a device ever
had. Each version gets its copies at the moment the next one moves the models on.

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

## Rules for the next schema change

- Consider compatibility before adding or renaming anything.
- Preserve existing user data. A destructive reset is not a substitute for a migration.
- Add coverage for the new step in the same interval that adds the step.
- When a version step has to transform data, write a custom stage and test the transformation, not
  just the fact that the store opens.
- Do not invent a value to fill a column that older data genuinely does not answer. Optional and
  absent is a truthful migration; a fabricated default is not.
