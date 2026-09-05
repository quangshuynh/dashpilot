# Earnings and metrics

A completed shift may hold one optional gross earnings amount, and from it DashPilot derives three
rates. It also derives two durations from the deliveries recorded during the shift. Everything on
this page is arithmetic over data the driver already has: nothing is imported, predicted or
estimated.

## Gross earnings

The amount on a shift is the figure the driver chose to associate with it, and nothing more.
DashPilot holds no delivery-platform account and imports nothing, so it cannot know whether the
number includes tips, bonuses, promotions, adjustments or reimbursements. The word used throughout
the code and the interface is therefore *gross earnings*, never profit, take-home, net or taxable
income.

Entering an amount is optional. A shift with no amount recorded is a complete shift, and that is a
**different fact** from a shift recorded as paying `$0.00`. Nothing in the app collapses one into
the other: no amount produces no rates, while a recorded zero produces a real `$0.00/hr`.

Amounts are entered in the driver's own locale. A decimal pad may produce a whole number, one or two
decimal places, a currency symbol or grouping separators, and all of those are read. Anything that
cannot be read is refused with the reason rather than reinterpreted, and more than two fraction
digits is refused rather than rounded, because rounding at the point of entry would store a number
the driver did not type.

## Delivery active time

**Delivery active time is the part of a completed shift during which at least one recorded delivery
had not yet reached a terminal state.** A delivery becomes active at `acceptedAt` and stops being
active at `deliveredAt` if it was completed, or at `cancelledAt` if it was not.

!!! warning "It is not driving time, working time or productive time"

    DashPilot has no idea what the driver was doing during those minutes. They may have been driving,
    waiting at a counter, shopping, parked, or doing something else entirely. "Delivery active" means
    exactly one thing: a delivery the driver recorded had not yet been marked delivered or cancelled.
    Nothing derives effort, productivity or a wage from it.

### Overlapping deliveries are counted once

Stacked work is ordinary work, and two deliveries open at once are two records of the same minutes.
The figure is the **union** of the delivery intervals, not the sum of their durations:

| Delivery | Active from | Active until |
| --- | --- | --- |
| A | 10:00 | 10:30 |
| B | 10:10 | 10:40 |

Delivery active time is **40 minutes**, not 60. A driver cannot be in two places at once, and adding
the two durations would let "active time" exceed the shift it happened in.

One delivery ending exactly as the next begins is one continuous stretch, not two with a
zero-length gap between them.

### Cancelled deliveries count until they were cancelled

A cancelled delivery contributes from acceptance to cancellation. The driver really was working that
delivery until it fell through, and dropping the interval would erase time they spent. It is still
not counted as a *completed* delivery anywhere — the two facts are separate.

### Non-delivery time

`Non-delivery time = elapsed shift time − delivery active time`, clamped at zero.

!!! warning "Non-delivery time is not idle time"

    It is the part of the shift no recorded delivery covers, and it routinely holds real work:
    waiting for an offer, repositioning, breaks, a delivery the driver never recorded, and any
    stretch the app was simply not told about. DashPilot does not know which, so it names the
    duration for what it is and derives nothing from it.

Both durations are shown only for **completed** shifts, and only when the shift has a delivery
interval that can be measured. A shift with no deliveries recorded shows neither, because "no
deliveries were recorded" is not the same statement as "no time was spent on deliveries".

## The three rates

| Metric | Definition | Shown as |
| --- | --- | --- |
| Gross earnings per shift hour | The recorded amount divided by the shift's elapsed wall-clock hours | `$28.75/hr` |
| Gross earnings per active delivery hour | The recorded amount divided by the shift's delivery active hours | `$79.62 per active delivery hour` |
| Gross earnings per recorded mile | The recorded amount divided by the miles the shift's route measured | `$19.30 / recorded mi` |

All three are recomputed from the stored amount, timestamps, deliveries and route every time they are
shown. None is stored, so improving a calculation improves every historical shift and the store never
holds a stale second answer.

### The hourly rate divides by elapsed time

The denominator is the whole shift: waiting at a restaurant, waiting between offers, a break, and
every stretch a delivery was open. This figure is never called an active, working or delivery hourly
rate — the rate below is the one with a delivery-time denominator, and neither of them is a wage.

For a driver who waits a lot between offers, this rate reads lower than the delivery work itself
did. It is kept because it is the figure that does not depend on how diligently the driver recorded
their deliveries: a shift with half its deliveries unrecorded still has a truthful elapsed hourly
rate, and would have a badly inflated active-hour one.

### The active-hour rate divides by unioned delivery time

The same shift can therefore show `$28.75/hr` over its elapsed time and `$79.62 per active delivery
hour` over the time a delivery was open. They are not competing answers — they divide by different
denominators and answer different questions.

Because the denominator is a union, stacking raises this rate rather than diluting it: two overlapping
deliveries add less to the denominator than two consecutive ones would.

!!! warning "It is still gross earnings"

    It is **not** an active wage, a true hourly rate, a working hourly rate or a net one. The
    numerator is the one amount the driver typed for the whole shift, with nothing subtracted, and no
    amount is attributed to an individual delivery anywhere in DashPilot. The denominator measures
    when deliveries were open, not what the driver was doing.

    It depends entirely on manually recorded lifecycle events. A driver who forgets to mark a
    delivery delivered until much later has a longer active time and a lower rate; one who records
    nothing has no rate at all.

### The per-mile rate divides by recorded mileage

Capture is foreground-only and distance across a gap is excluded rather than guessed, so the
denominator is normally lower than the miles actually driven. That makes the rate normally
**higher** than earnings per mile driven. The word "recorded" is in the visible text, not only in
this documentation, and it is spelled out in full for VoiceOver.

The figure is honest about its own denominator, but it is not comparable to a per-mile figure from
an app that records in the background.

## When a rate cannot be derived

A missing rate is never filled in with a zero and never shown as a dash on the history row. The
detail screen states the reason:

| Reason | The fact it states |
| --- | --- |
| Shift not completed | The shift is still running; finalised rates describe finished shifts |
| No earnings recorded | No amount has been entered. This is not an amount of zero |
| No elapsed time | The shift covers no measurable time, including one clamped to zero by a backwards device clock |
| No deliveries recorded | No delivery was recorded during the shift. This is not a delivery active time of zero |
| Delivery active time not measurable | Deliveries exist, but none describes a usable interval within the shift |
| Zero delivery active time | Delivery intervals *were* measured, and they covered no time |
| No route recorded | The shift retained no usable position at all |
| Route not measurable | Positions exist, but no two of them were recorded continuously |
| Zero recorded distance | A distance was measured, and it was zero |

A missing amount is reported once rather than described twice in the vocabulary of two different
denominators, and the sentence for it asks for an amount rather than implying the shift paid
nothing.

## Precision

Money is held as a decimal, unrounded, and rounded only for display. No monetary value passes
through binary floating point in memory or in the store, and every monetary string in the app is
built in one place. The details, including where a duration and a distance cross into decimal
arithmetic, are under [Money and metrics](../architecture/money-and-metrics.md).

## What these numbers are not

- Neither rate subtracts fuel, wear, insurance, phone costs or tax. Neither is a profit, net or
  take-home figure.
- Neither is a tax figure, and the per-mile rate is not a mileage deduction.
- Delivery active time is not a measure of work, effort or productivity, and non-delivery time is
  not a measure of idleness. Both are read entirely from lifecycle events the driver tapped.
- Nothing is aggregated. There is no weekly or all-time rate, no best or worst shift and no chart.
  Rates are read one shift at a time.
- Amounts are held in a single fixed currency (`USD`). Nothing converts between currencies or
  records which currency a shift was earned in.
