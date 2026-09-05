# Data model

Three persisted entities, and a small set of value types derived from them. Current schema
version: **v5**.

## `Shift`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `startedAt` | `Date` | Recorded when the shift starts, and never rewritten |
| `endedAt` | `Date?` | `nil` means the shift is still running. This is the only definition of "active" |
| `routeSamples` | `[RouteSample]` | Cascade delete, inverse of `RouteSample.shift` |
| `deliveries` | `[Delivery]` | Cascade delete, inverse of `Delivery.shift` |
| `grossEarningsAmount` | `Decimal?` | Private. `nil` means no amount recorded, which is not zero |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `isActive` | `endedAt == nil` |
| `completedDuration` | Elapsed seconds for a finished shift, clamped at zero |
| `elapsed(asOf:)` | Elapsed seconds for a running shift, clamped at zero |
| `recordedDistance(...)` | A `RouteDistance` measured from the retained route |
| `grossEarnings` | The stored decimal as a `Money`, or `nil` |
| `activeDeliveries` | This shift's deliveries that are neither delivered nor cancelled, in acceptance order |
| `deliveriesInOrder` | This shift's deliveries sorted by acceptance, with identity breaking a tie |
| `numberedDeliveries` | The same list paired with the local `Delivery 1`, `Delivery 2` labels |
| `numberedActiveDeliveries` | The unfinished ones, keeping the numbers they have everywhere else |
| `deliverySummary` | A `DeliverySummary` counting completed, cancelled and in-progress |

`end(at:)` rejects ending a shift twice or ending it before it started. `setGrossEarnings(_:)`
rejects a negative amount and an amount on an unfinished shift. `clearGrossEarnings()` removes the
amount, which is a distinct operation from recording zero.

## `RouteSample`

| Field | Type | Notes |
| --- | --- | --- |
| `timestamp` | `Date` | When the platform fixed the position, not when the app received it |
| `latitude` | `Double` | Degrees |
| `longitude` | `Double` | Degrees |
| `horizontalAccuracy` | `Double` | Radius of uncertainty in metres, as reported when the fix was taken |
| `captureSessionID` | `UUID?` | The uninterrupted period of capture this sample belongs to. `nil` for samples written before v3 |
| `shift` | `Shift?` | Optional only because SwiftData models the inverse that way. The initializer requires a shift |

Nothing else is stored. Core Location also reports speed, course, altitude and their accuracies;
none are kept, because nothing implemented reads them.

## `Delivery`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `acceptedAt` | `Date` | Acceptance is the delivery's creation, not an optional event |
| `arrivedAtPickupAt` | `Date?` | `nil` until the driver records reaching the pickup |
| `pickedUpAt` | `Date?` | `nil` until the driver records collecting the order |
| `deliveredAt` | `Date?` | Terminal |
| `cancelledAt` | `Date?` | Terminal. Set without erasing the events that preceded it |
| `shift` | `Shift?` | Optional only because SwiftData models the inverse that way. The initializer requires a shift |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `state` | A `DeliveryState`, read from which timestamps exist. There is no stored state column |
| `isActive` | Neither delivered nor cancelled |
| `lastEventAt` | The most recent recorded event, which the next one may not precede |
| `pickupWait` | `pickedUpAt - arrivedAtPickupAt`, or `nil` if either end is missing |
| `completedDuration` | `deliveredAt - acceptedAt`, or `nil` unless the delivery was delivered |
| `acceptedBefore(_:_:)` | The total, repeatable order over deliveries: acceptance ascending, identity breaking a tie |

`markArrivedAtPickup(at:)`, `markPickedUp(at:)` and `markDelivered(at:)` refuse a skipped step, a
repeated event, a transition after a terminal state, and a timestamp earlier than the last recorded
event. `cancel(at:)` is allowed from every active state. Nothing identifying a restaurant, a
customer or an address is stored, and no amount is attributed to a delivery.

A delivery is independent of every other delivery: it derives its state from its own timestamps
alone, so several can be active at once with overlapping lifecycles, and nothing here records a
relationship between them. See [Delivery lifecycle](../product/delivery-lifecycle.md).

## Schema versions

| Version | Change |
| --- | --- |
| 1.0.0 | `Shift`: id, start, optional end |
| 2.0.0 | Adds `RouteSample` and `Shift.routeSamples` |
| 3.0.0 | Adds `RouteSample.captureSessionID` |
| 4.0.0 | Adds `Shift.grossEarningsAmount` |
| 5.0.0 | Adds `Delivery` and `Shift.deliveries` |

Every step so far is a lightweight stage, and none backfills a value. See
[Migrations](../architecture/migrations.md).

Version 5 is still current. Supporting several concurrent deliveries changed no persisted shape:
`Shift.deliveries` was already a to-many relationship, so the store could always describe more than
one unfinished delivery for a shift, and "at most one active delivery" was an application invariant
rather than a constraint the database imposed. Removing it needed no migration.

## Domain value types

| Type | Purpose |
| --- | --- |
| `Money` | `Decimal`-backed monetary value. Unrounded in memory, rounded only for display |
| `MoneyInput` | Locale-aware parsing of what a decimal pad produces, with typed rejections |
| `RoutePoint`, `LocationSample` | Framework-free position values used by the filter and calculator |
| `RouteSampleFilter` | The capture acceptance policy and its rejection reasons |
| `RouteCaptureState` | Active, paused in background, permission required, unavailable |
| `RouteDistance` | Metres, segments, gaps, usable positions, inferred continuity, `isMeasured`, `isPartial` |
| `RouteMileageCalculator` | Splits a route into continuous segments and sums within them |
| `RouteQuality` | The tested vocabulary describing a measured route |
| `GeographicDistance` | One haversine implementation, shared by capture and measurement |
| `ShiftMetrics`, `ShiftMetricsCalculator` | Both derived rates and their precision rules |
| `ShiftRate`, `ShiftRateUnavailability` | An available rate, or the reason there is none |
| `LocationAuthorization` and its enums | Permission facts, condition precedence and recovery |
| `ShiftLifecycleError` | Refused start, end and delete transitions |
| `DeliveryState`, `DeliveryAction` | The five lifecycle states, the one action each offers next, and the wording |
| `DeliverySummary` | How many deliveries a shift recorded, how they ended, and how many are in progress |
| `NumberedDelivery` | A delivery with the local number the interface labels it with. Presentation only, never persisted |
| `DeliveryError`, `DeliveryLifecycleError` | Refused delivery transitions, and why |

## What is not in the store

Durations, distances, rates, route quality wording and capture state are all computed when they are
needed. A delivery's state is derived the same way, and so is the `Delivery 1` / `Delivery 2`
numbering the interface shows for concurrent deliveries — it is counted from the acceptance
timestamps rather than stored beside them. The store holds timestamps, positions and one optional
amount, and nothing that could disagree with them.
