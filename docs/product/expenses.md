# Recorded expenses

DashPilot records the operating costs a driver enters, so a period's gross
earnings can be read beside what the work cost. Every figure in this page is
built out of records the driver typed, and nothing else.

> Every amount and note in this documentation is synthetic.

## What an expense is

Four facts, all entered by the driver:

| Fact | Required | Notes |
| --- | --- | --- |
| Amount | Yes | Decimal, never negative. A recorded `$0.00` is allowed and means the driver recorded that this cost nothing. |
| Date and time | Yes | When the cost was incurred, not when it was typed. |
| Category | Yes | One of five: fuel, parking and tolls, maintenance, supplies, other. |
| Note | No | A short reminder, up to 120 characters. |

## What DashPilot does not do

**It observes no purchase.** There is no card, bank, receipt, email or
delivery-platform connection anywhere in the app, and no network access at all.

**It estimates nothing.** There is no fuel-consumption model, no cost per mile,
no vehicle wear and no depreciation. A cost that was not entered does not exist.

**There are no tax features.** No deduction, no mileage allowance, no
classification of a cost as claimable, and no figure in the app is a tax figure.
The categories are a driver's own labels and deliberately do not resemble a tax
form.

## An expense belongs to a date, not to a shift

This is the substantive decision behind the whole feature.

An expense carries the moment it happened and has **no relationship to a shift or
a delivery**. A period contains an expense if that moment falls inside the
period, by exactly the rule that puts a shift in a period.

The reasons are the facts of the work:

- A tank of fuel is burned across several shifts and several days.
- A set of tyres is spread over thousands of miles and hundreds of deliveries.
- A parking charge might belong to one delivery, but the driver did not say which
  one and the app cannot know.

Attaching a cost to whichever shift happened to be running when it was typed
would record an attribution the driver never made, and no later screen or export
could tell it apart from one they did. That is the same failure DashPilot refuses
when it declines to divide a shift's earnings among its deliveries.

Two consequences follow, and both are deliberate:

- **There is no per-shift or per-delivery cost anywhere**, and no shift-level net
  figure.
- **There is no cost per hour, per mile or per delivery.** The numerator would
  come from records dated to a period and the denominator from work recorded on
  shifts, which is the numerator-from-one-population figure this project refuses
  to publish everywhere else.

## Categories

Five, and no more:

| Category | What it holds |
| --- | --- |
| Fuel | Fuel or charging. |
| Parking and tolls | The cost of getting the vehicle to and through the work. |
| Maintenance | Servicing, tyres, repairs, a wash. |
| Supplies | Bags, mounts, cables and the like. |
| Other | Everything else. Claims nothing about what the money was for. |

The set is closed on purpose. Custom categories would need naming,
normalisation, renaming and merging, the apparatus that pickup identity needs, and would turn a
four-tap record into a filing exercise.

A stored category a build cannot recognise reads as **other**. That is reachable
only by running an older build against a store a newer one wrote; the amount, the
date and the note are still the driver's records, and losing the row to an
unknown label would be the worse failure.

## Recorded expenses in a period summary

The period summary reports what was recorded and what it comes to, with the
number of records behind it:

```
$48.60 recorded
Across 2 recorded expenses

Fuel                 $42.10
Parking and tolls     $6.50
```

**A recorded total is not the period's costs.** DashPilot holds the rows the
driver typed and nothing else, so the total is a floor in exactly the way
recorded mileage is a floor on the miles driven.

There is **no coverage pair** on an expense total, and its absence is deliberate.
A coverage pair needs a denominator, the records that *could* have contributed, and expenses have
none: nothing on the device knows how many costs a driver
incurred and did not enter. Writing "3 of 3 expenses" would state a completeness
the app cannot observe. A count of what was entered is the whole of what can
honestly be said.

A category with nothing recorded in it is **left out**, never listed at `$0.00`.
A driver who has never entered a maintenance cost has not recorded that
maintenance was free.

## Net after recorded expenses

```
Net after recorded expenses                                  $37.65
Recorded gross earnings across 1 of 2 shifts, less 2 recorded expenses.
Both halves are what you recorded: shifts with no amount are not counted, and
costs you did not enter are not subtracted. This is not profit, and it is not a
tax figure.
```

The figure is the difference between two subtotals of things the driver typed:

- gross earnings recorded on the period's completed shifts, over the shifts that
  carry an amount, and
- the expenses recorded in the period, over the records that exist.

It is called **net after recorded expenses**, in full, everywhere it appears. It
is never shortened to "net", and never called profit, take-home pay, earnings
after costs or a taxable amount. Both halves are floors, so their difference is
an **upper bound** on what the period actually netted.

The figure may be **negative**. A period whose recorded costs exceed its recorded
earnings is a fact, not an error.

### When there is no net figure

The amount is absent unless **both** halves were recorded, and each refusal has a
reason:

| State | What is shown | Why |
| --- | --- | --- |
| No expense recorded | No figure, and a sentence saying nothing was recorded to subtract | The difference would equal the gross exactly, and showing that as a *net* would assert the period cost nothing |
| No shift amount recorded | No figure, and a sentence saying there are no recorded earnings | A "net" of nothing minus recorded costs is a negative number, which beside a period's work reads as a loss the records do not establish |

A driver who genuinely spent nothing can record `$0.00`, which is a recorded
expense and does produce a net.

### The gross figures do not move

Recording an expense changes **nothing** about gross earnings, the three gross
rates, recorded mileage or any other existing figure. The net is a new figure
beside them, never a redefinition of one, and the word *gross* stays on every
figure that is gross.

## A day with costs and no work

A driver can buy fuel on a day they did not drive. Such a day still shows

```
No completed shifts recorded on this day.
```

and, below it, the expenses recorded on it. The record is not hidden behind a
sentence about shifts, and the day can be exported.

## Recording and correcting

Expenses live on their own screen, reached from the **Expenses** button in the
main screen's navigation bar. It is in the bar rather than in the list because an
expense belongs to no shift, so there is no section of that screen it is part of,
and because every row added above the shift history pushes the list a driver
opens the app to read further down. There is no expense control on a shift, and
none inside a delivery.

- **Adding is a draft.** Nothing is written until Save; Cancel writes nothing.
- **Editing replaces every fact at once**, so a refused edit leaves the record
  exactly as it was.
- **Deleting removes only that record.** Nothing else in the app changes, and
  deleting a *shift* never deletes an expense: the two are unrelated rows.
- **A date cannot be in the future.** An expense is something that already
  happened, and a mistyped year would silently drop the record out of every
  period the driver looks at.
- **A negative amount is refused** by the model, not only by the screen.

Typing an amount and a note is a stopped-vehicle task. Nothing in the expense
flow is presented during a shift's driving controls or during a delivery.

## Export

**JSON carries expenses.** A day, week, month, range or all-history export
includes every expense dated inside it, with its note, plus the period's recorded
expense total by category and the net after it.

**A single shift's export carries none**, because no expense belongs to a shift.
Export a period to see costs alongside work.

**CSV carries none either.** Its rows are deliveries, and an expense belongs to a
date rather than to a delivery, so it has no row in that table, and DashPilot
will not invent one. The format picker says so before the file is written.

The export **format version did not change**: the additions are new keys beside
the existing ones, no field was removed, renamed or redefined, and a reader that
ignores unknown keys is unaffected. See
[History export](history-export.md#version-history).

## Privacy

An expense is as sensitive as the rest of a driver's history, and a note is free
text they typed.

- Nothing is logged but the **category** of a change and whether a note exists. Never the amount,
  never the date money was spent, and never a word of a note.
- Expenses stay on the device. They leave only through an export the driver
  started and shared.
- Nothing is uploaded, and there is no network access anywhere in DashPilot.

## Limitations

- **No recurring expenses**, no templates and no reminders.
- **No receipts, photographs or attachments.**
- **No merchant, payment method or vehicle** on a record.
- **No cost per mile, per hour or per delivery**, by decision rather than by
  omission.
- **No shift-level or delivery-level net figure.**
- **No expenses in the CSV export**, and no separate expense export.
- **No import**, so an expense recorded elsewhere cannot be brought in.
- **No tax anything**, at all.
