# Money and metrics

Delivery earnings are small amounts summed many times, which is exactly where binary floating point
drifts. Every monetary value in DashPilot is decimal, and every rate derived from one is built on
demand rather than stored.

## `Money`

`Money` wraps `Decimal`, stores amounts unrounded, and rounds only when a caller asks. Division
returns an optional because a zero divisor is a normal state for rate calculations: a shift may have
no elapsed time or no recorded distance, and the app must show "no rate" rather than invent one.

`Money.formatted(currencyCode:locale:)` is the only place a monetary string is built. No view
assembles one from a symbol and a number, and no view configures a formatter. It rounds to
`displayScale` there and only there, which keeps rounding a **display** decision: the store holds
what the driver typed, exactly.

The currency is one fixed code (`Money.displayCurrencyCode`, `"USD"`), not the device locale's.
Nothing in the app converts between currencies or records which currency an amount was earned in, so
reading the currency from the locale would relabel a US driver's earnings as euros the moment they
set their phone to another region. Locale still decides how the amount is *written*, meaning symbol
placement and separators. It does not decide what the money is.

## Reading what a driver types

`MoneyInput` is the locale-aware layer `Money(exact:)` deliberately is not. `Money(exact:)` reads one
canonical form for fixtures and stored values, while a driver types whatever their keyboard offers.

Nothing in it reinterprets input to make it work, which is the reason it exists at all.
`Decimal(string:)` stops at the first character it cannot read, so `"12abc"` would silently become
`12` and `"1.2.3"` would become `1.2`. Every candidate is therefore validated in full: a currency
symbol and surrounding whitespace are removed, then digits, one decimal separator, and grouping
separators only in positions this locale actually writes them, before any number is built from it.

Internal whitespace is rewritten as the grouping separator rather than deleted, because several
locales group thousands with a space, and deleting it would read `"125 50"` as twelve thousand.

The rejections are separate cases because each is a different sentence the interface has to say:
nothing entered, not a number, more precision than the currency has, negative, or beyond the bound.

- **More than two fraction digits is refused, not rounded.** Rounding at the point of entry would
  store a number the driver did not type. Rounding belongs to display.
- **Negative is refused.** Gross earnings are what a shift paid; a shift that cost money is an
  expense, and expenses are not recorded anywhere yet. Zero is allowed, and meaningful.
- **`MoneyInput.maximumAmount` (1,000,000) is a guard against pathological input**, such as a pasted
  page of digits or a stuck key, not a judgement about what a driver can earn. `Decimal` holds 38
  significant digits, so without a bound a shift could store an amount no formatting in the app is
  meaningful for. It is checked in one place and documented so it can be raised if it is ever wrong.

`MoneyInput` takes its `Locale`, and the editor passes the environment's, so every parsing and
formatting test states the locale it is asserting about instead of inheriting whichever region the
machine running the suite happens to be set to.

## Completed-shift metrics

A completed shift is read as three rates and two derived durations. Every rate is gross, every figure
is derived, and each says in its own wording what it divides by. The product-level definitions are on
[Earnings and metrics](../product/earnings-and-metrics.md).

### The interval union

`DeliveryActiveTimeCalculator` turns a shift's deliveries into the time at least one of them was
open. It takes plain `DeliveryActiveInterval` values — `acceptedAt`, and `deliveredAt ?? cancelledAt`
— imports neither SwiftUI nor SwiftData and queries no store, so every case is tested without a
container or a rendered view.

It collects the usable intervals, sorts by start, sweeps once merging each interval into the open
stretch when it begins at or before that stretch's end, and adds the merged lengths: `O(n log n)` on
the sort, linear on the sweep. Nothing walks a timeline second by second or buckets the shift, both
of which would trade exactness for work.

Two properties follow and are asserted rather than assumed. **The result is order-independent** —
the sort is the only thing that reads order, and merging takes the later of two ends. **Touching
intervals leave no gap** — the merge condition is `start <= end`, because one delivery ending as the
next begins is a continuous stretch of delivery activity.

### Anomalies are counted, never repaired

The lifecycle cannot produce an interval with no end, an end before its start, or an interval outside
the shift it belongs to. A damaged or unexpected store can. None of them is filled in, reversed or
pulled into range, and none becomes a zero-length contribution that would look like a measurement:
each is left out and counted on `DeliveryActiveTime`, so a total short of its sources is visible
rather than silent.

Usable intervals are **clipped** to the completed shift's own window before merging, which is what
guarantees active time never exceeds the shift's elapsed duration and keeps the figure honest to its
name — time within *this* shift. Clipping applies to the derived reading only; stored timestamps are
never rewritten.

A running shift has no window and no final figure. Active-time metrics describe finished shifts.

### Nothing is persisted

There is no schema change behind the metrics, and the current version is still v5. A stored
`hourlyRate`, `earningsPerMile` or `activeDuration` would be a second answer to a question the store
can already answer: it would keep the old number after the calculation improved, and it would have to
be recomputed and rewritten every time a driver edited an amount or recorded a delivery.
`ShiftMetrics` is built on demand from the shift's own timestamps, its recorded amount, its
deliveries and its measured route, exactly like `RouteDistance` is.

### Explicit unavailable states

`ShiftRate` is `.available(Money)` or `.unavailable(ShiftRateUnavailability)`. A `Money?` would carry
the value and lose the reason, and the reasons are the point of the type.

| Reason | The fact it states |
| --- | --- |
| `shiftNotCompleted` | The shift is still running; finalised rates describe finished shifts |
| `earningsNotRecorded` | No amount has been entered. **Not** an amount of zero |
| `noElapsedTime` | The shift covers no measurable time, including one clamped to zero by a backwards device clock |
| `noDeliveriesRecorded` | No delivery was recorded. **Not** a delivery active time of zero |
| `deliveryActiveTimeNotMeasurable` | Deliveries exist, but none describes a usable interval within the shift |
| `zeroDeliveryActiveTime` | Delivery intervals *were* measured, and they covered no time |
| `noRouteRecorded` | The shift retained no usable position at all |
| `routeNotMeasurable` | Positions exist, but no two of them were recorded continuously |
| `zeroRecordedDistance` | A distance *was* measured, and it was zero |

The precedence is `shiftNotCompleted`, then `earningsNotRecorded`, then the denominator's own reason.
A missing numerator is the same absence for all three rates, so it is reported once rather than
described three times in the vocabulary of three different denominators.

The enum is `CaseIterable`, and the wording suite iterates `allCases`: a reason added without a
sentence fails a test rather than reaching a driver as an empty line.

Three distinctions carry the whole design. **Missing earnings never become zero**: a shift nobody has
entered an amount for produces no rate, while a shift recorded as paying nothing produces a real
`$0.00/hr` and `$0.00 / recorded mi`. **An unmeasurable route never becomes zero miles**: `0.0` in
the denominator is not a small number, it is an absent one, so a shift with no route shows no
per-mile rate rather than a rate divided by nothing. **No recorded deliveries never becomes zero
active time**: the shift section shows neither duration at all, rather than `0 min` beside a figure
that would read as a measurement.

`ShiftRateUnavailability.explanation` gives each case one sentence, none of them implying zero, and
the sentence for a missing amount asks for one ("Add what this shift paid to see this rate").

### Precision

Money stays exact. The numerator is the `Decimal` the driver typed, division goes through
`Money.divided(by:scale:)`, and no monetary value passes through binary floating point.

The **denominators are the boundary**, and it is deliberate. A duration is a `TimeInterval` and a
distance is a `Double` of metres; both are binary before this calculation ever sees them and neither
can be made exact afterwards. Each therefore crosses into `Decimal` exactly once, in
`ShiftMetricsCalculator.decimal(_:scale:)`, rounded to a scale far finer than the result is read at:
a duration to the millisecond, a distance to a millionth of a mile, which is under two millimetres
against positions carrying error radii of up to 100 m.

Both hourly rates — over elapsed time and over delivery active time — divide through one shared
helper, so they cannot drift apart in the last cent. A unioned active duration crosses the boundary
by exactly the same rule an elapsed one does.

`Decimal(_: Double)` is deliberately not used. Scaling to an integer and dividing by a power of ten
is an explicit rule stated in one place rather than a platform's conversion behaviour.

The quotient keeps six fraction digits, four more than the two it is displayed at, so the value the
display rounds is effectively the exact quotient rather than one already rounded at an adjacent
scale. Rounding to cents happens where every other rounding in the app happens, in
`Money.formatted`.

Miles come from `RouteDistance.miles`, which is the same conversion `formattedMiles(locale:)` uses.
No metres-to-miles constant exists anywhere else, so the rate and the distance beside it cannot
disagree about what a mile is.

### Accessibility

Each metric is one combined element with an explicit label, so a rate is heard as a claim
("$19.30 gross earnings per recorded mile") rather than as a heading and a number, and an absent one
as "No gross earnings per recorded mile" followed by the reason. The active-hour rate spells out its
denominator for the same reason: "$79.62 gross earnings per delivery active hour", never a spoken
abbreviation.

The three durations on a completed shift are told apart in words rather than by position —
"3 hours elapsed shift time", "1 hour, 5 minutes delivery active time", "1 hour, 55 minutes
non-delivery time". `CompletedShiftDetailView.durationText(_:width:)` takes a unit width for the
reason `RouteDistance.formattedMiles(width:)` does: `hr` reads well and hears badly, so the spoken
form asks for `.wide` and gets its words from the same units and the same rule. Nothing rewrites the
abbreviated string. The history row is one combined
element too, read as sentences rather than as the separators and abbreviations that look right and
sound wrong:

> Saturday, August 23, 2025. 5:46 PM to 8:46 PM. 3 hr. $86.25 gross earnings recorded. 4.5 miles
> recorded. Partial route: DashPilot was not recording for part of this shift, so more miles were
> driven than were recorded. $28.75 gross earnings per shift hour.
