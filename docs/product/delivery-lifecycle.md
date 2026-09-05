# Delivery lifecycle

A shift answers *when were you working*. A delivery answers *what were you doing inside it*. This
page describes what DashPilot records about a delivery, what it deliberately does not, how several
deliveries worked at once are kept apart, and what happens to a delivery that is still running when
the app is closed.

!!! warning "Nothing here is detected"

    Every timestamp on a delivery exists because the driver tapped a control. DashPilot has no
    integration with DoorDash or any other delivery platform: it does not read an order, watch
    another app, scrape a screen, intercept traffic or infer a pickup from movement. A delivery the
    driver did not record is not in the app, and a state they did not tap is not claimed.

## The five states

```mermaid
stateDiagram-v2
    [*] --> accepted: Start Delivery
    accepted --> arrivedAtPickup: Arrived at Pickup
    arrivedAtPickup --> pickedUp: Picked Up
    pickedUp --> delivered: Delivered
    accepted --> cancelled: Cancel Delivery
    arrivedAtPickup --> cancelled: Cancel Delivery
    pickedUp --> cancelled: Cancel Delivery
    delivered --> [*]
    cancelled --> [*]
```

| State | What it means | Recorded by |
| --- | --- | --- |
| `accepted` | The driver took the offer and is heading to the pickup | Creating the delivery |
| `arrivedAtPickup` | They reached the pickup and are waiting | `arrivedAtPickupAt` |
| `pickedUp` | The order is in the car | `pickedUpAt` |
| `delivered` | The delivery was completed. Terminal | `deliveredAt` |
| `cancelled` | It ended without being completed. Terminal | `cancelledAt` |

Acceptance is the delivery's creation rather than a separate optional timestamp. A delivery that
has not been accepted is a delivery that does not exist, so an optional `acceptedAt` would describe
a state the app can never be in.

## State is the timestamps

There is no stored `state` column and no `isPickedUp`-style flags. The state is derived from which
timestamps exist, so there is exactly one authoritative answer to what a delivery is doing, and it
is the same data that forms the historical record. A stored state could drift out of step with the
events it claims to summarise; a derived one cannot.

## Cancellation is history, not deletion

Real delivery work ends without a delivery: an order is cancelled, unassigned or returned.
Cancelling is available from every active state and keeps whatever genuinely happened first — a
delivery cancelled after twenty minutes at a pickup still records that the driver arrived there.

A cancelled delivery is never deleted, never counted as completed, and never folded into a single
total. It is work the driver did that did not end in a delivery.

## The rules, and where they live

These are enforced in `Delivery` and `DeliveryService` against the store, not by disabling a
button. A disabled control is presentation and cannot protect data.

- A delivery belongs to **exactly one shift** and can only begin while that shift is running. A
  delivery is never moved to another shift.
- **Any number of deliveries may be active at once.** Starting one changes nothing about the
  others.
- Every lifecycle event is applied to **exactly one delivery, named by the caller**. Nothing infers
  which delivery a tap meant.
- A delivery can only be advanced while the shift it belongs to is still running.
- Transitions happen **in lifecycle order, once each**, and never after the delivery has finished.
- A timestamp that precedes the last recorded event is **clamped forward**, which is the rule
  `ShiftService` already applies to a shift end when the device clock moves backwards. A driver must
  always be able to record what just happened, and a clamped event produces a zero-length interval
  rather than a negative one.
- Deleting a shift deletes its deliveries, through the relationship's cascade rule.

## Stacked deliveries

Delivery work is routinely stacked: a driver accepts a second order before the first is finished,
sometimes a third. **DashPilot supports any number of concurrent deliveries**, and each one advances
on its own.

Two deliveries are two records. They are never merged, never paired, and never summarised into a
single "stack" with one state — a shared state would have to answer "what is this stack doing" when
the honest answer is that one order is waiting at a counter and another is in the car.

Because several can be active, every lifecycle event names the delivery it belongs to. There is no
API and no control that resolves "the active delivery" and applies an event to whatever it finds,
because with two in progress there is no such thing, and picking one — the newest, the oldest,
whatever a fetch returned first — would attach a driver's tap to a record they did not mean.

!!! info "This is not a platform stack"

    DashPilot does not know that two orders were offered together, batched, or grouped by a delivery
    platform. It knows only that the driver started two deliveries and has not finished them. Nothing
    infers a relationship between them.

### Ordering and numbering

Deliveries are ordered by **acceptance time, earliest first**, with the record's identity breaking a
tie so that two accepted in the same instant cannot swap places between two reads. SwiftData's own
fetch order is never relied on.

The interface labels concurrent deliveries `Delivery 1`, `Delivery 2`, `Delivery 3`, numbered by that
order over the whole shift. This is **presentation only**:

- It is **not persisted**, and it is not a platform order number, a batch identifier, or anything
  anyone outside the app would recognise.
- It exists because two cards on screen have to be told apart, and the alternatives — a restaurant
  name, an address, an order ID — are data DashPilot deliberately does not collect.
- Numbering runs over every delivery in the shift, so finishing one does not renumber the others.
- Every control acts on the **persisted delivery**, not on its number or its row, so even a
  renumbering could not send an event to the wrong record.

## Ending a shift with deliveries running

**A shift cannot be ended while any of its deliveries are in progress.** The end is refused and the
driver is told to mark each one delivered or cancel it; the refusal counts them ("2 deliveries are
still in progress"). Finishing one of three does not unblock the shift — the other two still
happened.

The alternatives were all dishonest. Marking them delivered would record completions the driver
never made; discarding them would erase deliveries they did make. Nothing is auto-completed,
auto-cancelled or deleted.

## Relaunch recovery

The store is the only place delivery state lives, so recovery is not a code path. **Every** delivery
left active when the app was terminated is still active on the next launch: the same records, their
original timestamps, each with its own next step. None is collapsed into another, none is duplicated,
and none is picked as the authoritative one. Nothing synthesises a replacement, and no recovery step
is asked of the driver.

## During a shift

The running shift shows one card per delivery being worked. Each card names its delivery, says what
that delivery is doing, and offers exactly one lifecycle action — its own next step:

| That delivery's state | Its button says | VoiceOver hears |
| --- | --- | --- |
| `accepted` | Arrived at Pickup | Delivery 1. Mark arrived at pickup |
| `arrivedAtPickup` | Picked Up | Delivery 1. Mark order picked up |
| `pickedUp` | Delivered | Delivery 1. Mark delivery completed |

So a driver holding one order waiting at a counter and another already in the car sees
`Arrived at Pickup` on one card and `Delivered` on the other. Neither the lifecycle step nor the
delivery it applies to is ever chosen from a menu.

`Start Delivery` sits below the cards and is available the whole time the shift runs, because
accepting another order is ordinary work rather than an exception. It is the prominent control only
when nothing is in progress; while deliveries are running, the prominent controls are the ones
advancing them.

Each card also carries a bordered `Cancel Delivery 2` control — named, never a global "Cancel
Delivery" that picks its own target — behind a confirmation that repeats which delivery it will end
and says the delivery is kept as cancelled rather than deleted.

Deliberately absent: any field to type into. No restaurant, no customer, no address, no note and no
amount is asked for at any point, so a lifecycle event is one tap that can be made while stopped.
`End Shift` is bordered rather than prominent, because emphasising the once-a-shift, hard-to-undo
button over the ones tapped many times a shift is how a shift gets ended by mistake.

## On a completed shift

The shift's detail screen lists what each delivery recorded: its outcome, the lifecycle events that
happened with their times, and the two intervals both of whose ends exist. Deliveries appear in
acceptance order, under the same numbers they had on the running shift. It sits below the earnings,
route and performance sections, because it is the only one that grows with the shift.

| Derived interval | Definition | Shown when |
| --- | --- | --- |
| Waited at pickup | `pickedUpAt - arrivedAtPickupAt` | Both events were recorded |
| Accepted to delivered | `deliveredAt - acceptedAt` | The delivery was completed |

An interval with a missing end is left out rather than filled in with zero or with the shift's own
times. A cancelled delivery therefore shows the arrival it recorded and no wait, because the wait
never ended.

**Deliveries worked at the same time show overlapping times, and that is not a fault in the
record.** Each delivery's intervals are its own, measured between its own timestamps, and nothing
adds two of them together.

### Delivery active time

The shift section states how much of the shift at least one delivery was active for, and how much of
it was not:

| Duration | Definition |
| --- | --- |
| Delivery active time | The **union** of every delivery's `acceptedAt` to terminal-event interval |
| Non-delivery time | Elapsed shift time less delivery active time, clamped at zero |

A delivery active for 30 minutes and another active for 25, overlapping by 20, is **35 minutes** of
delivery active time — not the 55 their durations sum to. The overlapping minutes are counted once,
because a driver cannot be in two places at once and summing them would let active time exceed the
shift it happened in. A cancelled delivery contributes from acceptance until it was cancelled.

Non-delivery time is **not idle time**: it holds waiting for an offer, repositioning, breaks and any
work that was not recorded. Neither duration says anything about what the driver was doing, and
neither is presented as work, driving or productive time. The full definitions, and the gross
earnings per active delivery hour derived from them, are on
[Earnings and metrics](earnings-and-metrics.md#delivery-active-time).

## What a delivery does not hold

- **No restaurant or business name.** Naming a pickup introduces typing while driving,
  normalisation, duplicate matching and a privacy question, none of which the lifecycle needs.
- **No customer, address or note.** DashPilot stores nothing that identifies who received an order.
- **No per-delivery earnings.** A shift's gross earnings are one number the driver typed for the
  whole shift, and DashPilot has no source from which to split it between deliveries. Inventing an
  allocation would produce a per-delivery figure nobody recorded.
- **No editing or deleting one delivery.** A recorded delivery is what happened. If mis-taps prove
  to be a real problem, correction is its own design decision rather than a general editing
  framework added speculatively.
- **No relationship between concurrent deliveries.** Two deliveries active at once are two
  independent records. Nothing pairs them, groups them, or claims they were offered together.

## What is not built on this yet

The lifecycle records events, derives two factual intervals per delivery, and unions those intervals
into a shift's delivery active time and the one rate over it. Beyond that, nothing: no restaurant
rating, no wait-time recommendation, no offer-profitability figure, no per-delivery earnings, no
aggregate across shifts, no analysis of *why* deliveries overlapped, and no prediction of any kind.
See [Limitations](../reference/limitations.md).

## Schema

Neither concurrent deliveries nor delivery active time **changed the persisted shape**, and there is
no version 6. Active time is derived from the timestamps already stored, every time it is shown; no
`activeDuration`, `nonDeliveryDuration` or `activeHourlyRate` column exists, for the reason no
mileage or rate column does.

Supporting concurrent deliveries did not change the shape either.
The store has held `Delivery` as its own entity with a to-many `Shift.deliveries` relationship since
[version 5](../architecture/migrations.md) — it could always describe several unfinished deliveries
for one shift. "At most one active delivery" was an application invariant enforced by a service, not
a shape the database imposed, so removing it changed behaviour and nothing about storage. A
migration would have had nothing to migrate.
