# Earnings and metrics

A completed shift may hold one optional gross earnings amount, and from it DashPilot derives two
rates. Everything on this page is arithmetic over data the driver already has: nothing is imported,
predicted or estimated.

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

## The two rates

| Metric | Definition | Shown as |
| --- | --- | --- |
| Gross earnings per shift hour | The recorded amount divided by the shift's elapsed wall-clock hours | `$28.75/hr` |
| Gross earnings per recorded mile | The recorded amount divided by the miles the shift's route measured | `$19.30 / recorded mi` |

Both are recomputed from the stored amount, timestamps and route every time they are shown. Neither
is stored, so improving a calculation improves every historical shift and the store never holds a
stale second answer.

### The hourly rate divides by elapsed time

The denominator is the whole shift: waiting at a restaurant, idling between offers, a break. That is
the only duration DashPilot knows, because it does not record when a delivery started or ended. The
figure is never called an active, working or delivery hourly rate, since naming it that way would
claim a capability that does not exist.

For a driver who idles a lot, the rate understates how the driving itself performed, and the app
cannot say by how much.

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
- Nothing is aggregated. There is no weekly or all-time rate, no best or worst shift and no chart.
  Rates are read one shift at a time.
- Amounts are held in a single fixed currency (`USD`). Nothing converts between currencies or
  records which currency a shift was earned in.
