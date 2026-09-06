# Period summaries

DashPilot summarises completed shifts over one **day** or one **week**. The
summary answers one question:

> What do the records DashPilot actually has say about this period?

It never answers *"what happened during this period"*. The app sees only what the
driver recorded, and an aggregate is where that gap is easiest to forget: four
shifts with three amounts between them still produce a total, and the total looks
like a week's earnings unless the screen refuses to let it. Every figure is
therefore shown with the count of shifts it came from.

## Which shifts are counted

**Only completed shifts.** A running shift is excluded from every figure. Its
elapsed time is still growing and its amount is not final, so including it would
make a historical total change every second the driver worked.

**A shift belongs to the period containing its `startedAt`.** That is the whole
membership rule.

A shift that begins at 22:00 and ends at 02:00 belongs entirely to the day it
began on. Its money, its mileage and its deliveries are counted there, whole, and
nothing is counted again in the day it ended. Nothing is split at midnight:
those figures describe one working session, and cutting them at a boundary would
invent a division the records do not contain.

## Calendar semantics

Periods are built by `Calendar`, never by arithmetic on a fixed number of
seconds.

- **A day is not always 24 hours.** It is 23 on the day the clocks go forward and
  25 on the day they go back, and the summary's day boundaries follow that.
- **A week starts on the driver's own first weekday**, taken from their device
  settings, rather than on an ISO Monday the app chose for them. This is a
  consumer app, and a driver's week starts where their calendar says it does.
- **Time zone matters, and comes from the same calendar.** Which day a shift
  belongs to is decided in the driver's own zone.
- **A week spanning a month or year boundary is one week.**

Period spans are half-open: `[start, end)`. A shift starting at exactly midnight
belongs to the day that is beginning, and to that day only.

## Nothing is stored

Every figure is derived from the period's shifts each time it is asked for, like
recorded mileage, delivery active time and the per-shift rates. No weekly total,
count, rate or median is persisted. The schema is untouched by this feature, and
improving a calculation improves every past period at once.

## Coverage: the rule the whole screen exists for

**A missing input is never a zero.**

If four completed shifts exist and three have amounts recorded, the total of
those three is a real subtotal — and it is shown as one:

```
$284.50 recorded
3 of 4 shifts
```

The fourth shift is **not** counted as `$0.00`. A shift with no amount recorded
is a shift the driver has not told the app about, which is a different fact from
a shift that paid nothing.

An explicit `$0.00` **does** count as recorded coverage. A shift really can pay
nothing, and recording that is an answer.

The same rule runs through every figure:

| Figure | What is excluded | What is counted |
| --- | --- | --- |
| Gross earnings | Shifts with no amount recorded | Shifts with an amount, `$0.00` included |
| Elapsed time | Shifts with no usable duration | Completed shifts with one |
| Delivery active time | Shifts whose deliveries describe no usable interval | Shifts with a measurable union |
| Non-delivery time | Shifts missing either half of the subtraction | Shifts with both |
| Recorded mileage | Shifts whose route measured nothing | Shifts whose route measured a distance, partial ones included |

## Gross earnings are the period's earnings source

The headline total is the sum of the amounts recorded **on shifts**.

Amounts recorded against individual deliveries are never added into it. They are
optional and routinely absent, a stacked pair may be paid as one, and bonuses and
adjustments post at shift level — so summing them would silently read every
unrecorded delivery as one that paid nothing.

There is also **no fallback**. A period whose shifts carry no amount shows no
total, even if its deliveries carry amounts.

### The delivery subtotal is reported separately

The amounts recorded against deliveries appear as their own labelled fact:

```
Recorded on deliveries
$24.25 recorded across 2 of 4 deliveries
```

It is never called the period's earnings, and **nothing derives a shortfall**.
`shift total − delivery subtotal` is not computed and not shown: the difference
between the two is ordinary rather than an error, and presenting it as a gap
would call an ordinary difference a discrepancy.

## Rates

A period rate divides a **sum of numerators** by a **sum of denominators**.

!!! warning "Never an average of the shifts' own rates"

    Two shifts each paying `$100`, one over an hour and one over nine hours, are
    `$100.00/hr` and `$11.11/hr`. Their mean is `$55.56`. The period earned `$200`
    over 10 hours, so the rate is **`$20.00/hr`**.

    Averaging shift rates would weight a 30-minute shift the same as an
    eight-hour one and would answer a question nobody asked.

### Each rate uses one paired subset

A rate's numerator and denominator always come from the **same** shifts: the ones
carrying both halves of it.

| Rate | Uses shifts with |
| --- | --- |
| Gross per elapsed hour | An amount **and** a positive elapsed duration |
| Gross per delivery active hour | An amount **and** a positive measurable delivery active time |
| Gross per recorded mile | An amount **and** a positive measurable recorded route |

A shift missing either half contributes **neither**. An amount from a shift with
no measurable route never lands on another shift's mileage denominator, because
that would produce a figure describing no period at all.

Each rate carries the count it was worked out from:

```
$2.18 / recorded mi
Based on 4 of 6 shifts with both earnings and a measurable route
```

A recorded `$0.00` is a valid numerator over a real denominator. A denominator of
zero is not a denominator: that shift leaves the rate entirely, taking its amount
with it. No rate is ever fabricated as zero or infinity.

The numerator is always the **shift** amount, for all three rates. Per-delivery
amounts never enter one.

## Recorded mileage

The period's mileage is the sum of the distances its shifts' routes measured.

**It is recorded mileage, not miles driven.** Capture is foreground-only and the
distance across a gap is left out rather than guessed at, so the total is a floor
in exactly the way a single shift's is — see
[Recorded mileage](recorded-mileage.md).

A shift whose route measured nothing contributes **no distance at all**. It is
never counted as zero miles.

A **partial** route does contribute, because its distance is factual. What it may
not do is disappear, so the count of partial routes is shown beside the total:

```
42.6 mi recorded
5 of 6 shifts measured · 3 partial
```

Those are three different statements — 5 shifts measured something, 1 measured
nothing, and 3 of the 5 are known to be missing part of their shift — and the
screen keeps them apart.

## Delivery active time

Each shift's delivery active time is already the **union** of that shift's own
delivery intervals, so deliveries worked at the same time are counted once. The
period adds those per-shift answers together.

**Nothing is unioned across shifts.** Two shifts are two recorded work sessions;
merging their clock times would silently repair a store holding overlapping
shifts instead of leaving the anomaly visible.

### Non-delivery time

Non-delivery time is derived **per shift** (`elapsed − delivery active`, clamped
at zero) and then summed.

It is deliberately not `period elapsed − period active`. Those two sums can come
from different sets of shifts — a shift can contribute elapsed time while having
no measurable active time — and subtracting one from the other would produce a
duration belonging to neither.

It is still not idle time. See
[Earnings and metrics](earnings-and-metrics.md#non-delivery-time).

## Deliveries and pickup waits

Delivered and cancelled deliveries are counted **apart** and never added into a
single "completed" figure.

The period's pickup wait is the **median of the individual recorded waits** in
it:

```
Median recorded pickup wait
9 min
Based on 12 recorded pickups
```

It is not an average of each place's median: that would weight a place visited
once the same as one visited twenty times, and would be the middle of nothing the
driver experienced. Which place a wait happened at stops mattering once the
sample qualifies.

Nothing is trimmed, and nothing is predicted. The word *typical* is deliberately
not used at period level, and no figure describes the next pickup.

A period may also state how many distinct pickup places its deliveries named.
That is a count and nothing else — **no ranking, no scoring, no earnings per
place**.

## Empty and partial periods

A day or week with no completed shift shows a sentence:

```
No completed shifts recorded this week.
```

Not a grid of zeroes. A week nobody drove is a week with no records, not a week
of no earnings and no miles.

A period still in progress is simply named — `Today`, `This Week` — and never
described as complete, final or projected. There is **no forecasting** of any
kind: nothing extrapolates a partial week to its end, and no figure is a target,
a pace or a comparison against another period.

## What is deliberately absent

- **No charts.** Figures are read as text.
- **No comparison between periods.** No "up 12% on last week", no best or worst
  day, no streaks and no trend.
- **No merchant ranking or profitability by place.** The pickup-place count is a
  count.
- **No tax summaries, expenses or fuel cost.** Every figure is gross, and none is
  a deduction figure.
- **No export.** See [Limitations](../reference/limitations.md).
- **No projection, target or goal.**

## Accessibility

Every aggregate is spoken with the denominator that qualifies it, rather than
leaving VoiceOver to infer it from a caption nearby:

- *"Recorded gross earnings, 284 dollars and 50 cents, across 3 of 4 completed
  shifts."*
- *"Recorded mileage, 42.6 miles, measured across 5 of 6 completed shifts, 3 with
  partial route capture."*
- *"2 dollars and 18 cents gross earnings per recorded mile, based on 4 of 6
  shifts with both earnings and a measurable route."*

## Privacy

Aggregation happens entirely on device, in memory, from data already stored.
Nothing is logged: no period total, no mileage, no rate, no median and no
selected date. There is no networking and no analytics anywhere in the project.
