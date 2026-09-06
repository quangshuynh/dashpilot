# Pickup wait

[Pickup identity](pickup-identity.md) gave a driver's recurring pickups one thing to group by. This
page is what is grouped: **how long the wait at a place has actually been**, drawn entirely from
lifecycle events the driver already recorded.

!!! warning "A record, not a forecast"

    Every figure here describes pickups that already happened. Nothing predicts the next one, ranks
    one place against another, scores a merchant or advises whether to take an offer. A place that
    usually takes eleven minutes is free to take forty tomorrow, and DashPilot has no way to know
    which it will be.

## The definition

For one delivery:

```
pickup wait = pickedUpAt - arrivedAtPickupAt
```

Both ends are events the driver tapped. **Nothing else is consulted** — not the accepted time, not
the delivered time, not route samples and not how long the phone sat still somewhere. Standing near
a pickup is not the same as waiting for an order, and DashPilot cannot tell the two apart, so it does
not try.

### When a delivery contributes a wait

A delivery contributes exactly one recorded wait when **all** of these hold:

| Condition | Why |
| --- | --- |
| It names a pickup place | A wait with nothing to attribute it to belongs to no place's history |
| It recorded `arrivedAtPickupAt` | Without the start there is no interval, and acceptance is not a substitute |
| It recorded `pickedUpAt` | Without the end the wait either has not finished or never did |
| The pickup is not earlier than the arrival | An impossible interval is not an observation |

Everything else contributes nothing. Not a zero, not an estimate, not a partial figure — nothing.

### Cancelled deliveries

The rule above already decides them, and it decides them deliberately:

- **Cancelled before pickup: contributes nothing.** The driver may well have stood there for forty
  minutes, and that arrival *is* kept on the delivery. But the app was never told the order was
  collected, and time spent before giving up is not a pickup wait. Counting it would put "how long
  until I got the food" and "how long until I gave up" in the same column.
- **Cancelled after pickup: contributes normally.** Both ends exist. Whatever went wrong afterwards,
  the wait at the pickup happened and was recorded.

### Anomalous data

A pickup recorded before the arrival it followed cannot be produced by the app — every transition
refuses a timestamp earlier than the last recorded event. If one ever existed in a store, the sample
is **excluded**, not clamped to zero and not repaired. A zero standing in for an impossible interval
would enter a place's history as a real wait of no length.

## Renaming and merging a place

Both figure here because a place's history is derived from its deliveries and stored nowhere.

- **Renaming a place changes nothing.** The sample count, the median, the shortest and longest waits
  and the most recent sample are all what they were. Only the name above them changes.
- **Merging one place into another combines their histories**, because the merged deliveries now
  reference one place and the figures are recomputed from that relationship. Nothing is added up, no
  stored total is adjusted and no sample is counted twice — a wait belongs to the delivery that
  recorded it, and each delivery still has exactly one.

A wait excluded before a merge is excluded after it, by the same rule. See
[Correcting a place](pickup-identity.md#correcting-a-place).

!!! info "Two spellings split a history until you merge them"

    A place typed two ways is two places, so its waits sit in two histories with two medians.
    DashPilot does not detect that and will not merge them on its own. The correction is explicit and
    lives on the place's own screen.

## What a place's history says

For each pickup place, derived from the deliveries that reference it:

| Figure | Meaning |
| --- | --- |
| Sample count | How many recorded waits are behind the figures. Always shown |
| Median | The middle recorded wait — the headline, and named as the median wherever it appears |
| Shortest and longest | What the middle value is the middle *of* |
| Most recent | When the last recorded wait ended |

### Why the median

One forty-minute evening among five ordinary ones drags a mean somewhere no evening actually was.
The median stays where most of the pickups were, which is the question being asked.

There is **no average**, because there is no screen that needs one and two competing "usual waits"
would be worse than one.

### Nothing is trimmed

No outlier rejection, no winsorisation, no "unusually long" filter. If the two timestamps are in
order, the wait is a recorded observation and it stays — a place that occasionally costs forty
minutes is exactly the fact worth knowing, and quietly deleting it would make a slow place look fast.
That long wait is shown outright, next to the shortest one.

## Small histories are said to be small

A median of one number is that number. Presenting it as a *typical* wait would dress one evening up
as a pattern, so the wording changes with how much history there is:

| Recorded waits | What is shown |
| --- | --- |
| 0 | `No recorded pickup waits`, with what a wait is measured from |
| 1 | `Recorded wait 20 min` · `1 recorded pickup` · `Not enough history for a typical wait.` |
| 2 or more | `Typical recorded wait 11 min` · `Median of 3 recorded pickups` |

Two is the smallest count at which the median is a midpoint between distinct observations rather
than a rename of one of them. It is **not** a claim that two pickups are enough to predict a third,
which is why the sample count is shown beside the figure at every size.

Where the interface says **Typical**, it means the median, and says so in the line underneath.
Nothing anywhere is described as reliable, accurate or predictable on the strength of a sample count.

## Where it appears

| Surface | Shows |
| --- | --- |
| A delivery in a completed shift's log | `Waited at pickup — 6 min`, that delivery's own recorded wait |
| The pickup-place history sheet | The median, the sample count, the spread, and the individual waits |

The sheet is reached from a small secondary control on a delivery that names a place, beside the
control that corrects the place. A delivery naming none is offered no history rather than an empty
one.

**Nothing on a running shift shows any of this.** A historical figure offered mid-shift invites a
decision at exactly the moment a driver should not be reading statistics, and decision support during
an offer or a pickup is a thing to design deliberately rather than to arrive at by accident.

Per-delivery and per-place are kept apart on purpose: `Waited at pickup 6 min` is a fact about one
delivery, and `Median of 3 recorded pickups` is a summary of several. Neither is written where the
other belongs.

## Nothing is stored

None of this is persisted. `PickupPlace` gains no median, no count, no average and no last-wait
date, and the store stays at [schema version 6](../architecture/migrations.md) — **this work needed
no migration**.

Every figure is recomputed from the deliveries that reference the place, which is the rule mileage,
rates and delivery state already follow. A stored aggregate is a second answer, free to drift away
from the events it claims to summarise, and there is nothing here expensive enough to be worth that
risk.

## Accessibility

VoiceOver hears complete claims, never a duration floating beside a count:

- "Typical recorded pickup wait, 11 minutes, median of 3 recorded pickups. Shortest recorded wait 6
  minutes, longest 41 minutes."
- "1 recorded pickup, 20 minutes. Not enough history for a typical wait."
- "No recorded pickup waits. A wait is measured between a recorded arrival and a recorded pickup. No
  delivery here recorded both."

The qualification travels with the figure, so nothing depends on having seen the smaller text
underneath it.

## Privacy

Where a driver picks up and how long they wait is work-performance data about a real person, and it
is treated the way coordinates and earnings are. It stays on the device, and **none of it is
logged** — not a place name, not an individual wait, not a median, not a sample count and not a
sample's timestamp. Deriving a place's history writes nothing and records nothing.

Every figure and every name in this documentation is invented.

## What this is not

- Not a merchant ranking, score or grade. No place is compared to another anywhere.
- Not a prediction. No estimate of the next wait, no confidence interval, no model.
- Not a recommendation. Nothing suggests taking, declining or repositioning.
- Not an earnings figure. Waits and money are not divided into each other.
- Not a period aggregate. There is still no weekly or all-time view — see
  [Limitations](../reference/limitations.md).
