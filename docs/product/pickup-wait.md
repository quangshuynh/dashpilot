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

A pickup recorded by [Pick up orders with Park & Resume](settings.md#pick-up-orders-with-park-resume) is an ordinary `pickedUpAt`, taken at
the moment the driver pressed Resume Driving, and its arrival is an ordinary `arrivedAtPickupAt`,
taken when they pressed Park. That delivery's wait therefore runs from parking to driving away. It
is recorded like any other, and left out of typical waits for the reason given under
[Pickups recorded automatically](#pickups-recorded-automatically). The two steps are separate
presses, so the workflow never records an arrival and a pickup at one instant.

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

## Pickups recorded automatically

With [Pick up orders with Park & Resume](settings.md#pick-up-orders-with-park-resume) on, Park records
`Arrived at Pickup` and Resume Driving records `Picked Up`. The wait between them is recorded exactly,
and it runs from **parking** to **driving away**: the walk in, the wait inside, the walk back, and
however long the driver sat in the vehicle before pressing Resume Driving. A wait recorded with the
card's own buttons ends when the driver says the order is in hand. DashPilot records **how** each
pickup was recorded, with the event:

| How the pickup was recorded | Stored as | In a typical or median wait |
| --- | --- | --- |
| The driver's own `Picked Up` step, on the card, by voice or from the Lock Screen | `manual` | Counted |
| Resume Driving, under the workflow | `resumeAutomation` | **Left out, and counted apart** |
| Park, under the retired `Pick up order when parking` setting | `parkAutomation` | **Left out, and counted apart** |
| Before DashPilot kept this (a store from before schema v18) | nothing: unknown | Counted, as it always was |

Which waits count is decided by how the **pickup** was recorded. A wait that Park began and the
driver's own `Picked Up` step ended counts: parking is when a driver taps Arrived too.

Why Resume Driving's are left out, measured rather than assumed, through the app's own median over
the synthetic waits `4, 6, 7, 9, 12` minutes (median 7:00), with a minute's walk each way:

| What is in the sample | Median |
| --- | --- |
| The five waits, recorded by hand | 7:00 |
| The same five visits recorded by Park and Resume, leaving at once | 9:00 |
| The same, with five minutes in the vehicle before resuming | 14:00 |
| The five by hand plus one by Park and Resume | 8:00 |
| Half and half, leaving at once / after a minute / after five minutes | 8:30 / 9:00 / 11:30 |
| Two waits, `8` by hand and `10` by Park and Resume | 9:00 |

The workflow's waits are never short, and they are long by exactly the walks and the time spent in
the vehicle, which DashPilot does not know. Mixed in, the median climbs with the share of pickups
recorded this way, so it would describe how often the driver uses the setting rather than the place.
The retired Park-when-parking setting had the same effect in the other direction (its waits ended
before the handover and halved a median at half the sample). Neither is adjusted, and neither is
estimated.

Left out is never silent. Wherever a figure leaves waits out, it says how many beside it, on screen
and to VoiceOver, naming which control recorded them:

```
Typical recorded wait
7 min
Median of 2 recorded pickups
1 pickup recorded when you resumed driving is not counted: it ends when you drove off, not at the handover.
```

A place whose only waits were recorded automatically shows **no** typical wait, never a zero, with
the same sentence. The list of waits under a place's summary lists the waits the figure is taken
over, and says "counted" rather than "recorded" when it leaves any out. The wait itself is kept
exactly as recorded: it still appears on its delivery, in the export, and in the place's own history
of deliveries. Nothing is scaled, corrected or replaced, and nothing estimates when the order was
actually handed over.

**Unknown is counted, and is never relabelled.** A pickup recorded before schema v18 has no
provenance, and migration deliberately did not write `manual` into it. The one build that could
already record a pickup by parking left no trace of which pickups it recorded that way, so those stay
unknown and stay counted; see [Limitations](../reference/limitations.md#automated-pickups).

**Corrections and settings.** Correcting a pickup's recorded time moves the instant and rederives
every figure at once, and **keeps** its provenance: an automated pickup corrected to the real
handover is still automated, and still left out. Turning the setting on or off changes the next
press and nothing already recorded.

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
