# Data model

Six persisted entities, and a small set of value types derived from them. Current schema
version: **v10**.

## `Shift`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `startedAt` | `Date` | Recorded when the shift starts, and never rewritten |
| `endedAt` | `Date?` | `nil` means the shift is still running. This is the only definition of "active" |
| `deliveries` | `[Delivery]` | Cascade delete, inverse of `Delivery.shift` |
| `offers` | `[Offer]` | Cascade delete, inverse of `Offer.shift` |
| `pauses` | `[ShiftPause]` | Cascade delete, inverse of `ShiftPause.shift` |
| `grossEarningsAmount` | `Decimal?` | Private. `nil` means no amount recorded, which is not zero |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `isActive` | `endedAt == nil`. Unchanged by pausing: a paused shift is unfinished |
| `lifecycleState` | `running`, `paused` or `ended`, derived from `endedAt` and the open pause |
| `openPause` | The pause with no end, or `nil`. What "paused" means |
| `isPaused` | `lifecycleState == .paused` |
| `pausesInOrder` | This shift's pauses sorted by start |
| `pauseIntervals` | One `ShiftPauseInterval` per pause |
| `completedDuration` | Elapsed seconds for a finished shift, clamped at zero |
| `elapsed(asOf:)` | Elapsed seconds for a running shift, clamped at zero |
| `measuredWindow(asOf:)` | `startedAt` to the shift's end, or to the moment being read at |
| `pausedTime(asOf:)` | A `ShiftPausedTime` unioning the pauses within that window |
| `completedPausedTime` | The same for a finished shift, `nil` while unfinished |
| `workingDuration(asOf:)` | `elapsed − paused`, clamped at zero. Stops growing while paused |
| `completedWorkingDuration` | The same for a finished shift, `nil` while unfinished |
| `routeSamples()` | This shift's retained positions, fetched, oldest first. Not a stored collection |
| `routeSampleCount` | How many positions the route holds, counted rather than loaded |
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
| `offersInOrder` | This shift's offers sorted by acceptance, with identity breaking a tie |
| `activeOffers` | The offers still holding at least one delivery in progress |
| `numberedOffers` | The same list paired with the local `Offer 1`, `Offer 2` labels, each carrying its deliveries under their shift-wide numbers |
| `numberedOffer(containing:)` | The numbered offer a delivery arrived in, or `nil` for one recording none |

`beginOffer(deliveryCount:at:)` is the only thing in the app that creates a delivery, and the only
thing that records a new acceptance. It rejects a count below one, an offer on an ended shift, and an
acceptance before the shift began, and returns the offer and its deliveries for the caller to insert,
so a refused write leaves nothing behind. There is deliberately no maximum: how much work a driver
accepted is a fact about their work, and the stepper on screen bounds a control rather than the model.

`makeOffer(regrouping:)` is the only other thing that creates an offer, and it creates no delivery: it
records deliveries the shift already holds as an offer of their own, for a driver correcting which
deliveries arrived together. It requires the deliveries up front, rejects an empty group and a
delivery from another shift, and takes the **earliest acceptance among them** as the new offer's own,
which is a moment the driver really recorded. Unlike `beginOffer` it is allowed on a shift that has
ended, because restating a grouping is not recording new work.

`beginPause(at:)` rejects a pause on an ended shift, a second open pause, and a start before the
shift's. `endOpenPause(at:)` rejects a resume with nothing open and one on an ended shift; the
returned pause is inserted by the caller, so a refused write leaves nothing behind.
`end(at:)` rejects ending a shift twice or ending it before it started. `setGrossEarnings(_:)`
rejects a negative amount and an amount on an unfinished shift. `clearGrossEarnings()` removes the
amount, which is a distinct operation from recording zero.

## `ShiftPause`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `startedAt` | `Date` | When the driver recorded pausing |
| `endedAt` | `Date?` | `nil` while the driver has not resumed. An open pause is what "paused" means |
| `offer` | `Offer?` | The accepted offer this delivery arrived in. Optional because SwiftData models a reference that way, and because a pre-v12 store had none until the migration gave each delivery its own. It groups and does not govern: no timestamp, figure, fetch or delete rule reads it |
| `shift` | `Shift?` | The only place the relationship is declared; `Shift` holds no matching collection. Optional only because SwiftData models a reference that way. The initializer requires a shift. Carries no delete rule, so `ShiftService.deleteCompletedShift(_:)` removes a shift's positions explicitly |

A row rather than a flag on `Shift`. A boolean could say a shift is paused now but not for how long
or how many times; an accumulated "paused seconds" would be a running sum the app had to keep correct
across every crash and failed save, which is the kind of derived value this project does not persist.

`Shift.endedAt` is untouched by pausing, so `endedAt == nil` is still the only definition of
"unfinished" and a paused shift is recovered after a relaunch by the same fetch as a running one.

`end(at:)` rejects closing a pause twice or closing it before it began.

## `RouteSample`

| Field | Type | Notes |
| --- | --- | --- |
| `timestamp` | `Date` | When the platform fixed the position, not when the app received it |
| `latitude` | `Double` | Degrees |
| `longitude` | `Double` | Degrees |
| `horizontalAccuracy` | `Double` | Radius of uncertainty in metres, as reported when the fix was taken |
| `captureSessionID` | `UUID?` | The uninterrupted period of capture this sample belongs to. `nil` for samples written before v3 |
| `offer` | `Offer?` | The accepted offer this delivery arrived in. Optional because SwiftData models a reference that way, and because a pre-v12 store had none until the migration gave each delivery its own. It groups and does not govern: no timestamp, figure, fetch or delete rule reads it |
| `shift` | `Shift?` | The only place the relationship is declared; `Shift` holds no matching collection. Optional only because SwiftData models a reference that way. The initializer requires a shift. Carries no delete rule, so `ShiftService.deleteCompletedShift(_:)` removes a shift's positions explicitly |

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
| `offer` | `Offer?` | The accepted offer this delivery arrived in. Optional because SwiftData models a reference that way, and because a pre-v12 store had none until the migration gave each delivery its own. It groups and does not govern: no timestamp, figure, fetch or delete rule reads it |
| `shift` | `Shift?` | The only place the relationship is declared; `Shift` holds no matching collection. Optional only because SwiftData models a reference that way. The initializer requires a shift. Carries no delete rule, so `ShiftService.deleteCompletedShift(_:)` removes a shift's positions explicitly |
| `pickupPlace` | `PickupPlace?` | Optional and often absent. A reference, so two deliveries from one place share a row. Nullify on delete |
| `grossEarningsAmount` | `Decimal?` | Private. What this one delivery paid, as the driver typed it. `nil` means no amount recorded, which is not zero. Unrelated to `Shift.grossEarningsAmount` |
| `expectedEarningsAmount` | `Decimal?` | Private. What the driver expects this delivery to pay, entered while it was active. **Not earnings**: nothing counts it, and it never becomes the column above. `nil` means none recorded, which is not zero |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `state` | A `DeliveryState`, read from which timestamps exist. There is no stored state column |
| `isActive` | Neither delivered nor cancelled |
| `lastEventAt` | The most recent recorded event, which the next one may not precede |
| `pickupWait` | `pickedUpAt - arrivedAtPickupAt`, or `nil` if either end is missing or the pickup precedes the arrival |
| `completedDuration` | `deliveredAt - acceptedAt`, or `nil` unless the delivery was delivered |
| `grossEarnings` | The stored decimal as a `Money`, or `nil` |
| `expectedEarnings` | The stored expected decimal as a `Money`, or `nil`. No rate is derived from it, here or anywhere |
| `hasUnconfirmedExpectedEarnings` | An expectation is recorded and no gross amount is. The state the completion confirmation and the history screen offer to resolve |
| `grossPerDeliveryHour` | A `DeliveryEarningsRate`: the amount over this delivery's own `completedDuration`, or the reason there is none |
| `acceptedBefore(_:_:)` | The total, repeatable order over deliveries: acceptance ascending, identity breaking a tie |
| `makeHistoricalOffer()` | The v11 to v12 migration's one write: the one-delivery offer a delivery recorded before offers existed belongs in. `nil`, changing nothing, for a delivery that already holds one or belongs to no shift |
| `move(into:)` | The one place a delivery's grouping changes. Returns the offer it left, so the caller can decide what happens to an offer left holding nothing. Refuses another shift's offer, the offer it is already in, and an offer accepted after this delivery was |

`markArrivedAtPickup(at:)`, `markPickedUp(at:)` and `markDelivered(at:)` refuse a skipped step, a
repeated event, a transition after a terminal state, and a timestamp earlier than the last recorded
event. `cancel(at:)` is allowed from every active state. `setGrossEarnings(_:)` rejects a negative
amount and an amount on a delivery that is still in progress; a cancelled delivery may carry one, and
is never forced to zero. `clearGrossEarnings()` removes the amount, which is a distinct operation
from recording zero. `setExpectedEarnings(_:)` is the mirror of it and rejects a negative amount and
an amount on a delivery that has **finished**; `clearExpectedEarnings()` is unconditional, because
removing a figure claims nothing. `setPickupPlace(_:)` is deliberately
unconditional: a pickup place is not an event, so correcting one changes no interval and is allowed
on a finished delivery. Nothing identifying a customer or an address is stored.

The amount is a **second independent fact**, not a share of anything. It is what the driver typed
against this one delivery; it is never derived from `Shift.grossEarningsAmount`, never checked
against it, and no total is ever divided among a shift's deliveries. See
[Earnings and metrics](../product/earnings-and-metrics.md).

The **expected** amount is a third independent fact, and two columns rather than one flagged column
is the substantive decision. A flag would have left every existing reader of `grossEarningsAmount`
free to report an expectation as earnings, and each reader that was missed would have done so
silently. A separate column fails the other way: a reader that has not been taught about
expectations cannot see them, which is exactly what every aggregate in the app wants. Finishing a
delivery never moves a value from one column to the other.

## `Offer`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute. Local to the device, and not an identifier any delivery platform would recognise |
| `acceptedAt` | `Date` | Acceptance is the offer's creation, not an optional event |
| `shift` | `Shift?` | Optional only because SwiftData models the inverse of a to-many that way. The initializer requires a shift |
| `deliveries` | `[Delivery]` | Cascade delete, inverse of `Delivery.offer` |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `deliveriesInOrder` | The offer's deliveries in the order the shift numbers them |
| `deliveryCount` | How many deliveries the driver said this offer contained |
| `isGrouped` | More than one delivery, which is the only case the interface shows a grouping for |
| `couldHaveContained(_:)` | Whether a delivery accepted at that instant could have arrived in this offer, which is the one ordering rule correction keeps |
| `earliestDeliveryAcceptance` | The earliest acceptance among this offer's deliveries, or `nil` for one holding none |
| `activeDeliveries` | The offer's deliveries that are neither delivered nor cancelled |
| `state` | An `OfferState`, read from the states of the deliveries it holds |
| `isTerminal` | Every delivery has finished. An offer holding none is deliberately not terminal |
| `deliverySummary` | A `DeliverySummary` over the offer's own deliveries |
| `acceptedBefore(_:_:)` | The total, repeatable order over offers, the same rule deliveries use |

An **offer** is one acceptance event; a **delivery** is one dropoff with its own lifecycle. One offer
may contain several deliveries, and an offer accepted later is a different offer even if its
deliveries overlap in time with an earlier one's. Nothing merges two offers on its own: that happens
only where the driver says the grouping they recorded was wrong, through `OfferCorrectionService`,
which moves membership and never a lifecycle fact, an amount or an acceptance timestamp. An offer
left holding no deliveries by a correction is removed in the same write, so `OfferState.empty`
describes a store the app cannot produce rather than an outcome of ordinary use.

**It holds no money, no duration and no distance.** Expected pay and recorded gross earnings stay on
the delivery, and no total, rate or coverage figure anywhere is derived from an offer. Cancelling is
per delivery: there is no control that cancels an offer, and an offer whose deliveries all ended
cancelled is `cancelled` while one with a mix is `partiallyCompleted`, which is neither.

`Delivery.shift` is kept beside `Delivery.offer` rather than replaced by it. A delivery's shift could
be read through its offer, but that column is what every existing fetch, aggregate, export figure and
delete rule is built on, and moving the membership would rewrite a stored foreign key across a
driver's whole history to express something the store already holds. Since `beginOffer` is the only
thing that creates either, the two cannot be recorded disagreeing.

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
| 2.0.0 | Adds `RouteSample` and `Shift.routeSamples`, removed again in 10.0.0 |
| 3.0.0 | Adds `RouteSample.captureSessionID` |
| 4.0.0 | Adds `Shift.grossEarningsAmount` |
| 5.0.0 | Adds `Delivery` and `Shift.deliveries` |
| 6.0.0 | Adds `PickupPlace` and `Delivery.pickupPlace` |
| 7.0.0 | Adds `Delivery.grossEarningsAmount` |
| 8.0.0 | Adds `Expense`. No existing entity changes, and no relationship is added |
| 9.0.0 | Adds `ShiftPause` and `Shift.pauses` |
| 10.0.0 | Removes `Shift.routeSamples`. `RouteSample.shift` is unchanged, and no stored value moves |
| 11.0.0 | Adds `Delivery.expectedEarningsAmount`. No existing attribute moves, and no delivery gains one |
| 12.0.0 | Adds `Offer`, `Delivery.offer` and `Shift.offers`. The first custom stage: every existing delivery is given a one-delivery offer of its own, and no two are grouped together |

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
| `RouteCaptureState` | Active, stopped because the driver paused the shift, paused because a session could not start off screen, permission required, unavailable |
| `RouteDistance` | Metres, segments, gaps, usable positions, inferred continuity, `isMeasured`, `isPartial` |
| `RouteMileageCalculator` | Splits a route into continuous segments and sums within them |
| `RouteQuality` | The tested vocabulary describing a measured route |
| `GeographicDistance` | One haversine implementation, shared by capture and measurement |
| `ShiftLifecycleState` | Running, paused or ended, derived from a shift's own rows |
| `ShiftPauseInterval` | One recorded pause as a value: its bounds, its clipping and its malformed case |
| `ShiftPausedTime`, `ShiftPausedTimeCalculator` | The union of a shift's pauses, with the counts behind it |
| `DateRangeUnion` | The one sweep that merges overlapping stretches, shared by paused time and delivery active time |
| `ShiftMetrics`, `ShiftMetricsCalculator` | The three derived rates, working duration, and their precision rules |
| `ShiftRate`, `ShiftRateUnavailability` | An available shift rate, or the reason there is none |
| `DeliveryEarningsRate`, `DeliveryRateUnavailability` | One delivery's gross per recorded delivery hour, or the reason there is none |
| `LocationAuthorization` and its enums | Permission facts, condition precedence and recovery |
| `ShiftLifecycleError` | Refused start, pause, resume, end and delete transitions |
| `DeliveryState`, `DeliveryAction` | The five lifecycle states, the one action each offers next, and the wording |
| `DeliverySummary` | How many deliveries a shift recorded, how they ended, and how many are in progress |
| `NumberedDelivery` | A delivery with the local number the interface labels it with. Presentation only, never persisted |
| `NumberedOffer` | An offer with the local `Offer 1` number, its deliveries under their shift-wide numbers, and the grouping wording |
| `DeliveryGroup` | The deliveries on one screen arranged by the offer they arrived in. Presentation only |
| `OfferState`, `OfferError` | Where an offer has reached, read from its deliveries, and the refusals when recording one |
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
needed. A shift's lifecycle state is derived from its end timestamp and its open pause rather than
stored as a word, and its working duration is derived by subtracting the union of its pauses from its
elapsed time, for the same reason: a stored answer can disagree with the rows beside it after a
crash, a failed save or a migration, and a derived one cannot. A delivery's state is derived the same way, and so is the `Delivery 1` / `Delivery 2`
numbering the interface shows for concurrent deliveries — it is counted from the acceptance
timestamps rather than stored beside them. A pickup place's recency is derived from the deliveries
that reference it, for the same reason. A delivery's gross per recorded delivery hour is derived from
its own amount and its own two timestamps, every time it is shown, and is never added to another
delivery's. A period's recorded expense total, its split by category and the net
after it are derived from the expense rows the same way, and no cost per hour, per mile or per
delivery exists at all. The store holds timestamps, positions, the optional amounts a driver typed
against a shift and against individual deliveries, the costs they entered, and the names and notes
they typed, and nothing that could disagree with them.
