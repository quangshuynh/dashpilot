# Data model

Five persisted entities, and a small set of value types derived from them. Current schema
version: **v8**.

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
| `completedWindow` | `startedAt...endedAt` for a finished shift, `nil` while running or if the stored end precedes the start |
| `deliveryActiveIntervals` | One `DeliveryActiveInterval` per delivery: `acceptedAt`, and `deliveredAt ?? cancelledAt` |
| `deliveryActiveTime(...)` | A `DeliveryActiveTime` unioning those intervals within `completedWindow` |

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
| `pickupPlace` | `PickupPlace?` | Optional and often absent. A reference, so two deliveries from one place share a row. Nullify on delete |
| `grossEarningsAmount` | `Decimal?` | Private. What this one delivery paid, as the driver typed it. `nil` means no amount recorded, which is not zero. Unrelated to `Shift.grossEarningsAmount` |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `state` | A `DeliveryState`, read from which timestamps exist. There is no stored state column |
| `isActive` | Neither delivered nor cancelled |
| `lastEventAt` | The most recent recorded event, which the next one may not precede |
| `pickupWait` | `pickedUpAt - arrivedAtPickupAt`, or `nil` if either end is missing or the pickup precedes the arrival |
| `completedDuration` | `deliveredAt - acceptedAt`, or `nil` unless the delivery was delivered |
| `grossEarnings` | The stored decimal as a `Money`, or `nil` |
| `grossPerDeliveryHour` | A `DeliveryEarningsRate`: the amount over this delivery's own `completedDuration`, or the reason there is none |
| `acceptedBefore(_:_:)` | The total, repeatable order over deliveries: acceptance ascending, identity breaking a tie |

`markArrivedAtPickup(at:)`, `markPickedUp(at:)` and `markDelivered(at:)` refuse a skipped step, a
repeated event, a transition after a terminal state, and a timestamp earlier than the last recorded
event. `cancel(at:)` is allowed from every active state. `setGrossEarnings(_:)` rejects a negative
amount and an amount on a delivery that is still in progress; a cancelled delivery may carry one, and
is never forced to zero. `clearGrossEarnings()` removes the amount, which is a distinct operation
from recording zero. `setPickupPlace(_:)` is deliberately
unconditional: a pickup place is not an event, so correcting one changes no interval and is allowed
on a finished delivery. Nothing identifying a customer or an address is stored.

The amount is a **second independent fact**, not a share of anything. It is what the driver typed
against this one delivery; it is never derived from `Shift.grossEarningsAmount`, never checked
against it, and no total is ever divided among a shift's deliveries. See
[Earnings and metrics](../product/earnings-and-metrics.md).

## `PickupPlace`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `displayName` | `String` | The driver's own spelling. The first accepted one wins against matching, and only `rename(to:)` rewrites it |
| `normalizedName` | `String` | The comparison key from `PickupPlaceName`. Never shown, spoken or logged |
| `createdAt` | `Date` | When the place was first named on this device. Used for ordering, not analysis |
| `deliveries` | `[Delivery]` | Nullify delete, inverse of `Delivery.pickupPlace` |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `lastUsedAt` | The latest `acceptedAt` among the deliveries naming this place, or `nil` if none do |
| `pickupWaitSamples` | Each referencing delivery's recorded wait, oldest first. Deliveries missing either end are skipped |
| `pickupWaitMetrics(using:)` | A `PickupWaitMetrics`: sample count, median, shortest, longest and most recent. See [Pickup wait](../product/pickup-wait.md) |
| `namedBefore(_:_:)` | The total, repeatable order over places: creation ascending, identity breaking a tie |
| `displayedBefore(_:_:)` | Alphabetical presentation order: `localizedStandardCompare` on the display name, `namedBefore` breaking a tie. Used for merge destinations |

Mutating:

| Member | Meaning |
| --- | --- |
| `rename(to:)` | Writes `displayName` and `normalizedName` together from one `PickupPlaceName`. Leaves `id`, `createdAt` and `deliveries` alone. Collision detection is the service's, not the model's |

No aggregate is stored. There is no `medianWait`, `averageWait` or `pickupCount` column, and adding
one is what a test in `PickupWaitMetricsTests` exists to fail on.

`normalizedName` is deliberately **not** a `.unique` attribute: a unique constraint in SwiftData
resolves a collision by upserting, which would overwrite the row the reuse rule exists to preserve.
Uniqueness is enforced in `PickupPlaceService` instead. **No counter, visit total, last-used date,
median wait or score is stored on a place** — every such figure is derived from its deliveries when
asked, and a stored copy could drift away from them. There is no address, coordinate, phone number, store
number or platform identifier, and nothing here came from anywhere but the driver's keyboard. See
[Pickup identity](../product/pickup-identity.md).

Renaming a place and merging one place into another are **relationship and attribute mutations
only** — no version of the store records an alias, a merge history, a redirect identifier or a
tombstone, and neither operation changed the schema. A merge reassigns `Delivery.pickupPlace` for
every delivery on the source and then deletes the source, in one commit.

A delivery is independent of every other delivery: it derives its state from its own timestamps
alone, so several can be active at once with overlapping lifecycles, and nothing here records a
relationship between them. See [Delivery lifecycle](../product/delivery-lifecycle.md).

## `Expense`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `occurredAt` | `Date` | When the cost was incurred, as the driver recorded it, never when the row was typed. This is what period membership is decided by |
| `amountValue` | `Decimal` | Private. **Required**: an expense with no amount is not a record of anything. Never negative; a recorded `0.00` is a recorded amount |
| `categoryRawValue` | `String` | Private. `ExpenseCategory`'s raw value. A stored word this build cannot name reads as `other` |
| `note` | `String?` | The driver's own short reminder, trimmed, up to 120 characters. `nil` when they wrote none |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `amount` | The stored decimal as a `Money` |
| `category` | The stored word as an `ExpenseCategory`, through `ExpenseCategory.stored(_:)` |
| `expenseRecord` | An `ExpenseRecord` for aggregation: date, amount and category, and deliberately not the note |
| `recordedBefore(_:_:)` | The total, repeatable order over expenses: most recent first, identity breaking a tie |

`init(...)` and `update(...)` reject a negative amount and a note over the length limit, and
`update(...)` validates every value before writing any of them, so a refused edit leaves the record
exactly as it was.

**There is no relationship to `Shift` and none to `Delivery`, and that is the substantive decision
in this entity.** An expense carries the moment it happened; a period contains it if that moment
falls inside the period, by the same rule that puts a shift in a period. Attaching a cost to
whichever shift happened to be running when it was typed would record an attribution the driver
never made. Deleting a shift therefore removes no expense, and no cost is ever divided across
shifts, deliveries, days or miles. See [Recorded expenses](../product/expenses.md).

## Schema versions

| Version | Change |
| --- | --- |
| 1.0.0 | `Shift`: id, start, optional end |
| 2.0.0 | Adds `RouteSample` and `Shift.routeSamples` |
| 3.0.0 | Adds `RouteSample.captureSessionID` |
| 4.0.0 | Adds `Shift.grossEarningsAmount` |
| 5.0.0 | Adds `Delivery` and `Shift.deliveries` |
| 6.0.0 | Adds `PickupPlace` and `Delivery.pickupPlace` |
| 7.0.0 | Adds `Delivery.grossEarningsAmount` |
| 8.0.0 | Adds `Expense`. No existing entity changes, and no relationship is added |

Every step so far is a lightweight stage, and none backfills a value. See
[Migrations](../architecture/migrations.md).

Two capabilities needed no version of their own. Supporting several concurrent deliveries changed no
persisted shape: `Shift.deliveries` was already a to-many relationship, so the store could always
describe more than one unfinished delivery for a shift, and "at most one active delivery" was an
application invariant rather than a constraint the database imposed. Delivery active time changed
none either — it is unioned from timestamps already stored, every time it is shown.

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
| `ShiftRate`, `ShiftRateUnavailability` | An available shift rate, or the reason there is none |
| `DeliveryEarningsRate`, `DeliveryRateUnavailability` | One delivery's gross per recorded delivery hour, or the reason there is none |
| `LocationAuthorization` and its enums | Permission facts, condition precedence and recovery |
| `ShiftLifecycleError` | Refused start, end and delete transitions |
| `DeliveryState`, `DeliveryAction` | The five lifecycle states, the one action each offers next, and the wording |
| `DeliverySummary` | How many deliveries a shift recorded, how they ended, and how many are in progress |
| `NumberedDelivery` | A delivery with the local number the interface labels it with. Presentation only, never persisted |
| `DeliveryError`, `DeliveryLifecycleError` | Refused delivery transitions, and why |
| `PickupPlaceName` | The normalisation policy: a display spelling and the key identity is decided by |
| `PickupPlaceNameError`, `PickupPlaceError` | Refused pickup names, rename collisions, refused merges and failed pickup writes, and why |
| `PickupPlaceIdentity` | A place's id and spelling as a `Sendable` value, so a rename collision can name what it collided with without a thrown error holding a model |
| `ExpenseCategory` | The five conservative categories, their wording, and how a stored word is read back |
| `ExpenseNote` | The optional note's rule: trimmed, absent when empty, bounded in length |
| `ExpenseRecord` | One recorded cost reduced to date, amount and category, for aggregation without a store |
| `ExpenseTotalsCalculator` | The one definition of a recorded-expense total, its categories, and the net after it |
| `PeriodExpenseTotals`, `ExpenseCategoryTotal` | A period's recorded costs, the count behind them, and their split by category |
| `PeriodNetAfterExpenses` | Recorded gross earnings less recorded expenses, with the counts behind both halves, and the rules for when there is no figure |
| `ExpenseError`, `ExpenseNoteError`, `ExpenseRecordingError` | Refused expense values and failed expense writes, and why |

## What is not in the store

Durations, distances, rates, route quality wording and capture state are all computed when they are
needed. A delivery's state is derived the same way, and so is the `Delivery 1` / `Delivery 2`
numbering the interface shows for concurrent deliveries — it is counted from the acceptance
timestamps rather than stored beside them. A pickup place's recency is derived from the deliveries
that reference it, for the same reason. A delivery's gross per recorded delivery hour is derived from
its own amount and its own two timestamps, every time it is shown, and is never added to another
delivery's. A period's recorded expense total, its split by category and the net
after it are derived from the expense rows the same way, and no cost per hour, per mile or per
delivery exists at all. The store holds timestamps, positions, the optional amounts a driver typed
against a shift and against individual deliveries, the costs they entered, and the names and notes
they typed, and nothing that could disagree with them.
