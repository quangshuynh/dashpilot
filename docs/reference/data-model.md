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
| `routeSuspensions` | `[RouteSuspension]` | Cascade delete, inverse of `RouteSuspension.shift`. The stretches the driver recorded the vehicle as parked. Read by nothing that measures time |
| `grossEarningsAmount` | `Decimal?` | Private. `nil` means no amount recorded, which is not zero |
| `fuelMilesPerGallonValue` | `Decimal?` | The vehicle fuel economy this shift's fuel estimate is worked out under, as the driver typed it. A **snapshot**, never a reference to a current figure. Always greater than zero where present, because it is the divisor. `nil` means none recorded |
| `fuelGasPricePerGallonAmount` | `Decimal?` | What a gallon cost, as the assumption this shift is estimated under. `nil` means none recorded; `0` means the fuel was recorded as costing nothing |
| `fuelVehicleName` | `String?` | What the vehicle this shift's fuel economy came from was called, as recorded when the shift started. A **label**, never an input: no figure reads it. A copy rather than a reference, so a shift stays intelligible when the profile is renamed or deleted. `nil` where the economy was typed by hand |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `isActive` | `endedAt == nil`. Unchanged by pausing: a paused shift is unfinished |
| `lifecycleState` | `running`, `paused` or `ended`, derived from `endedAt` and the open pause |
| `openPause` | The pause with no end, or `nil`. What "paused" means |
| `isPaused` | `lifecycleState == .paused` |
| `pausesInOrder` | This shift's pauses sorted by start |
| `pauseIntervals` | One `ShiftPauseInterval` per pause |
| `openRouteSuspension` | The stretch parked with no end, or `nil`. What "parked" means |
| `isRouteSuspended` | Whether the vehicle is recorded as parked right now. False for an ended shift and for a paused one, in both cases because those close an open stretch |
| `routeSuspensionsInOrder` | This shift's stretches parked, sorted by start |
| `routeSuspensionIntervals` | One `RouteSuspensionInterval` per stretch |
| `suspendedTime(asOf:)` | A `RouteSuspendedTime` unioning those stretches within the window. **Subtracted from nothing** |
| `completedSuspendedTime` | The same for a finished shift, `nil` while unfinished |
| `completedDuration` | Elapsed seconds for a finished shift, clamped at zero |
| `elapsed(asOf:)` | Elapsed seconds for a running shift, clamped at zero |
| `measuredWindow(asOf:)` | `startedAt` to the shift's end, or to the moment being read at |
| `pausedTime(asOf:)` | A `ShiftPausedTime` unioning the pauses within that window |
| `completedPausedTime` | The same for a finished shift, `nil` while unfinished |
| `workingDuration(asOf:)` | `elapsed − paused`, clamped at zero. Stops growing while paused |
| `completedWorkingDuration` | The same for a finished shift, `nil` while unfinished |
| `routeSamples()` | This shift's retained positions, fetched, oldest first. Not a stored collection |
| `routeSampleCount` | How many positions the route holds, counted rather than loaded |
| `routeSamples(after:)` | The positions fixed strictly after an instant, which an end-time correction removes |
| `routeSampleCount(after:)` | How many those are, counted rather than loaded, for the confirmation that states it |
| `recordedDistance(...)` | A `RouteDistance` measured from the retained route |
| `grossEarnings` | The stored decimal as a `Money`, or `nil` |
| `fuelAssumptions` | The two stored columns as a `FuelAssumptions`, which is the only place they become one |
| `fuelEstimate(for:)` | A `FuelEstimate` over a recorded distance and this shift's own assumptions, or the reason there is none |
| `profitability(for:)` | A `ShiftProfitability`: recorded earnings less the estimated fuel, and that over the shift's working hours |
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
`end(at:)` rejects ending a shift twice or ending it before it started. `apply(_:)` is the only thing
that rewrites `endedAt` afterwards, taking a `ShiftEndCorrection` that has already been checked and
rejecting a shift whose recorded end is not the one that correction was built against;
`endCorrection(to:nextShiftStartedAt:)` is the adapter that gathers the shift's start, its recorded
end, its pauses and every lifecycle instant its deliveries record for that check. Both are reached
through `ShiftEndCorrectionService`, which refuses a running shift, deletes the route positions an
earlier end puts outside the shift, and commits **once** for the two together, so no ordering exists
in which the end moves while the positions survive. `setGrossEarnings(_:)`
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

`end(at:)` rejects closing a pause twice or closing it before it began. `apply(_:)` rewrites both
timestamps to a correction that `ShiftPauseCorrection` has already checked, and rejects an **open**
pause: a pause with no end is the state the driver is in, and it is closed by resuming or by ending
the shift, which reconcile route capture and the Live Activity as they go.

`Shift.pauseCorrection(from:to:replacing:)` is the adapter that gathers the shift's window, its other
pauses and its delivery intervals for that check; `Shift.addMissedPause(_:)` is the only thing that
creates a pause outside the live lifecycle, and like `beginPause(at:)` it leaves the context insert
to the caller. Both are reached through `ShiftPauseCorrectionService`, which refuses a running shift
outright and commits once per correction.

## `RouteSuspension`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `startedAt` | `Date` | When the driver recorded parking |
| `endedAt` | `Date?` | `nil` while the driver has not recorded driving again. An open row is what "parked" means |
| `shift` | `Shift?` | The shift this belongs to, and **never a delivery**. Optional only because SwiftData models the inverse of a to-many that way |

A row rather than a flag, for the reason `ShiftPause` is one: a boolean could say the vehicle is
parked now and not for how long, how many times or when, and a route's coverage has to be able to say
all three. It also means a shift left parked when the app is terminated comes back parked with no
recovery code, because the row is the only place the state lives.

**It joins the shift and nothing else, at any version.** Whether the vehicle is moving is a fact
about the driver and their vehicle: a driver shopping for one order while carrying another has one
vehicle and it is parked. So there is at most one open row however many deliveries are in progress,
and no delivery owns, starts or ends one.

**It is not a pause, and the two are separate entities so that they cannot become one.** A
`ShiftPause` says the driver stopped working and is subtracted from the shift's working duration;
this says they are working on foot and is subtracted from nothing. A single entity with a kind column
would be one `if` away from a pause subtracting a shopping trip from somebody's hours. No duration,
rate, period figure or exported total reads a suspension as time not worked.

What it does change is the **route**: capture is stopped for its whole length, so a walk is never
written into a coordinate history, and driving again mints a new capture session, so
`RouteMileageCalculator` refuses to measure across the stretch by the rule it already had.

`beginRouteSuspension(at:)` refuses an ended shift, a paused one and a second open row, and leaves
the context insert to the caller like `beginPause(at:)`. `endOpenRouteSuspension(at:)` is allowed on
an ended or paused shift, unlike opening one, because both of those close an open row as part of
their own write. `ShiftService.parkActiveShift(at:)` and `resumeDrivingOnActiveShift(at:)` are the
only callers, and nothing anywhere ends a row because a speed changed or a delivery advanced.

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
| `deliveredAt` | `Date?` | Terminal. Cleared by exactly two corrections: reopening a delivery on a running shift, and correcting a historical completion to a cancellation |
| `cancelledAt` | `Date?` | Terminal. Set without erasing the events that preceded it. A historical correction sets it to the delivery's own former `deliveredAt` rather than to a new instant |
| `offer` | `Offer?` | The accepted offer this delivery arrived in. Optional because SwiftData models a reference that way, and because a pre-v12 store had none until the migration gave each delivery its own. It groups and does not govern: no timestamp, figure, fetch or delete rule reads it |
| `shift` | `Shift?` | The only place the relationship is declared; `Shift` holds no matching collection. Optional only because SwiftData models a reference that way. The initializer requires a shift. Carries no delete rule, so `ShiftService.deleteCompletedShift(_:)` removes a shift's positions explicitly |
| `pickupPlace` | `PickupPlace?` | Optional and often absent. A reference, so two deliveries from one place share a row. Nullify on delete |
| `grossEarningsAmount` | `Decimal?` | Private. What this one delivery paid, as the driver typed it. `nil` means no amount recorded, which is not zero. Unrelated to `Shift.grossEarningsAmount` |
| `expectedEarningsAmount` | `Decimal?` | Private. What the driver expects this delivery to pay, entered while it was active. **Not earnings**: nothing counts it, and it never becomes the column above. `nil` means none recorded, which is not zero |
| `additionalTips` | `[DeliveryTip]` | Tips received **outside** `grossEarningsAmount`. Cascades on delete, so deleting a shift reaches its deliveries and on to their tips. Empty is the ordinary case |

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
| `additionalTipsInOrder` | The tips oldest first, with identity breaking a tie, so the list's numbering is repeatable |
| `effectiveEarnings` | An `EffectiveDeliveryEarnings`: the platform amount, the tips, and what the two come to. The total is `nil` whenever the platform amount is, tips or no tips |
| `hasRecordedMoney` | A platform amount **or** a tip. Asked by the corrections that promise not to touch what the driver recorded |
| `effectiveEarningsPerDeliveryHour` | A `DeliveryEarningsRate`: the **effective** earnings over this delivery's own `completedDuration`, or the reason there is none |
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

## `DeliveryTip`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `amountValue` | `Decimal` | Private. Always more than zero: a tip of nothing is refused on the way in, so there is no missing-versus-zero question to ask about it |
| `methodRawValue` | `String` | Private. `DeliveryTipMethod`'s raw value. Read back through `stored(_:)`, which returns **no method** for a word this build cannot name, because both cases are substantive claims and neither may stand in for an unknown one |
| `recordedAt` | `Date` | When the driver wrote the tip down. Never edited, and **not** when the money changed hands |
| `delivery` | `Delivery?` | The delivery this tip was received for. Optional only because SwiftData models the inverse of a to-many that way; the initializer requires one |

`Delivery.recordAdditionalTip(_:method:at:)` is the **only** thing that creates one, so the two rules
it keeps cannot be bypassed: the delivery has to be finished, and the amount has to be more than
nothing. `update(amount:method:)` replaces both values together and moves no timestamp. There is no
"when it arrived" field and no picker for one: correcting a historical timestamp is its own decision
with its own rules, and a field that looked like the moment money changed hands while holding the
moment it was typed would be the worst of both.

A tip is a **separate recorded fact**, never a rewrite of `Delivery.grossEarningsAmount`. That column
stays the platform-recorded pay, including whatever the platform already folded into it. What the
delivery actually paid is the two added on demand by `EffectiveDeliveryEarnings`, and no total is
stored anywhere. See [Earnings and metrics](../product/earnings-and-metrics.md).

It is **not** cash-on-delivery accounting: no order total, no cash collected, no platform deduction,
no reimbursement and no customer balance is stored anywhere in DashPilot.

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

## `VehicleProfile`

One vehicle the driver works in, kept so its fuel economy is typed once rather than on every shift.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `UUID` | Unique. What `DriverSettings.selectedVehicleID` points at |
| `name` | `String` | What the driver calls this vehicle. Trimmed, non-empty and length-limited |
| `milesPerGallonValue` | `Decimal` | The vehicle's fuel economy. Always greater than zero |
| `createdAt` | `Date` | When the profile was created, which is the order the list is drawn in. A stable order that does not move under a rename |

**It is a preference, not history, and nothing joins it to a `Shift`.** When a shift starts, the
selected profile's name and fuel economy are copied onto that shift, and every estimate and exported
value is derived from the copy. Editing this row afterwards changes no figure the driver has already
seen, and deleting it leaves every shift it ever started exactly as it was. There is deliberately no
relationship in either direction, so the delete cascades nowhere.

What it deliberately does not hold: a VIN, a plate, a make, a model, a trim, an odometer reading, a
service schedule, an insurance record or a purchase price. See
[Settings and vehicles](../product/settings.md).

## `DriverSettings`

The driver's current preferences. **At most one row**, by construction: the identifier is a constant
and is unique, so two attempts to create it resolve to one row rather than to two sets of
preferences.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `UUID` | Unique, and always `DriverSettings.singletonID` |
| `gasPricePerGallonAmount` | `Decimal?` | What the driver says a gallon currently costs. `nil` means none recorded; `0` means the fuel is recorded as costing nothing |
| `selectedVehicleID` | `UUID?` | The `VehicleProfile.id` new shifts are recorded under, or `nil` when none is selected |

**Nothing derived reads this row.** It is read at exactly one moment, when a shift starts, and copied
onto that shift. Changing a setting tomorrow changes nothing recorded today.

The selected vehicle is an **identifier rather than a relationship**, so a deleted profile leaves a
selection that resolves to nothing, which reads as *no vehicle selected*. The service clears it in
the same save as the delete, so the ordinary path never leaves one dangling.

The row is created the first time the driver opens Settings. A migration never creates one.

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
| 13.0.0 | Adds `DeliveryTip` and `Delivery.additionalTips`. Lightweight, and nothing is backfilled: a delivery holding no tip is the ordinary shape in this build too, so every figure a migrated store derives is the figure it already was |
| 14.0.0 | Adds `Shift.fuelMilesPerGallonValue` and `Shift.fuelGasPricePerGallonAmount`. Lightweight, and nothing is backfilled: a shift recording no assumptions reports which half is missing rather than an estimate of `$0.00` |
| 15.0.0 | Adds `VehicleProfile`, `DriverSettings` and `Shift.fuelVehicleName`. Lightweight, and nothing is backfilled: a v14 store holds no evidence of which vehicle any shift was worked in, so no profile is invented, no settings row is created and no shift is given a name |
| 16.0.0 | Adds `RouteSuspension` and a cascading `Shift.routeSuspensions`. Lightweight, and nothing is backfilled: a gap in a v15 route is left by a pause, a lost permission or a terminated process just as readily as by a driver walking into a shop, and the route holds no evidence of which |

Every step but 12.0.0 is a lightweight stage, and none but that one writes a value. See
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
| `DeliveryTipMethod` | `cash` or `platform`, and a closed set. A stored word this build cannot name reads as **no method**, because there is no neutral third case for one to fall back on |
| `EffectiveDeliveryEarnings` | A delivery's platform amount plus its recorded tips. The total is absent whenever the platform amount is |
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
| `DeliveryEarningsRate`, `DeliveryRateUnavailability` | What one delivery earned per recorded delivery hour, or the reason there is none |
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
that reference it, for the same reason. What a delivery earned per recorded delivery hour is derived
from its own effective earnings and its own two timestamps, every time it is shown, and is never
added to another delivery's. A period's recorded expense total, its split by category and the net
after it are derived from the expense rows the same way, and no cost per hour, per mile or per
delivery exists at all. The store holds timestamps, positions, the optional amounts a driver typed
against a shift and against individual deliveries, the costs they entered, and the names and notes
they typed, and nothing that could disagree with them.
