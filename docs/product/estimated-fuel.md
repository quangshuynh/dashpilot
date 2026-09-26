# Estimated fuel and net

DashPilot can estimate what a completed shift's **recorded mileage** consumed in
fuel, and what was left of the shift's recorded earnings once that estimate is
taken off. Both figures are estimates, they are built from two assumptions the
driver enters, and the app is careful to say so everywhere they appear.

> Every amount, figure and route in this documentation is synthetic.

## The calculation

```
estimated gallons   = recorded miles / miles per gallon
estimated fuel cost = estimated gallons * gas price per gallon
```

and then, on the same screen:

```
estimated net after fuel       = recorded shift earnings - estimated fuel cost
estimated net per working hour = estimated net after fuel / working hours
```

The middle step of the first pair is the whole point. Multiplying recorded miles
by a price per gallon prices a mile as though a mile were a gallon, and is wrong
by whatever the vehicle's fuel economy is. DashPilot works out the gallons first,
in one place, and every surface that shows an estimate comes through it.

## What is recorded, and what is assumed

| Input | Where it comes from |
| --- | --- |
| Recorded mileage | Measured from the shift's retained route, exactly as everywhere else in the app |
| Miles per gallon | A figure the driver enters, recorded on the shift |
| Gas price per gallon | A figure the driver enters, recorded on the shift |
| Shift earnings | The amount the driver recorded for the shift |

Three of those four are recorded facts. The vehicle's fuel economy and the price
of a gallon are **assumptions**: DashPilot observes no vehicle, reads no pump and
has no network access at all.

## An assumption is recorded with the shift it was used for

This is the substantive decision behind the whole feature.

Each completed shift keeps **its own copy** of the fuel economy and the gas price
its estimate was worked out under. A driver who changes vehicle in March has not
changed what February's shifts consumed, and a fill-up next month at a higher
price did not make last month's driving more expensive. If those two figures
lived in one global place, every shift ever worked would be silently re-costed
the moment either changed, and a history screen would show different numbers
today than it showed yesterday.

So:

- **Entering different figures later leaves every earlier shift exactly where it
  is.**
- A shift's estimate can always be reproduced from what that shift itself
  records.

The convenience is separate from the truth, and it is what
[Settings](settings.md) is for. A shift **takes its copy when it starts**, from
the vehicle the driver selected and the gas price they last entered. From that
moment the shift owns its copy: editing the vehicle, deleting it, selecting
another or changing the price all change what the **next** shift records and
nothing that has already been recorded.

When the fuel editor opens on a shift that recorded nothing, it **fills its
fields** from those current defaults, or failing those from the most recent shift
that did record a pair, and says so. A filled field is a suggestion: nothing is
recorded against the shift until the driver taps Save, and no earlier shift
changes because a later one, or a setting, records something else.

A shift worked before the defaults existed is **not** filled in for the driver.
It keeps recording nothing until they open its fuel editor and tap
`Use Current Defaults`, which fills the fields from Settings for them to save.
Writing today's figures into last month's work would put an assumption the driver
never made into their history.

### The one correction to a shift still being worked

A shift's assumptions are otherwise editable only once it has finished, and that
rule has one deliberate exception. While the **running** shift's route has
recorded no distance, the driver can correct its snapshot from the running
shift's own panel: a driver who started in the wrong vehicle should not have to
work a whole shift under a figure they can already see is wrong.

It is narrow on purpose:

- **Only before any driving is recorded.** Once the route has measured a
  distance, changing what a mile is assumed to cost would restate what those
  miles are estimated to have consumed, with nothing to point at, so the
  correction closes. The rule is measured distance and never elapsed time.
- **No route evidence is touched.** Nothing is deleted or rewritten to make a
  correction possible.
- **It copies, it does not link.** The vehicle's current name and economy, and
  the current gas price, are copied as facts. Settings is not written and a later
  change to it does not follow.
- **It is not a default being reapplied.** The snapshot taken when a shift starts
  may only ever fill an empty pair and happens without anybody asking; this
  replaces a recorded pair and only ever happens because the driver saved.

Correcting the assumptions of shifts already recorded, as a group, is not a
feature DashPilot has. The remedy for one finished shift is its own fuel editor.
See [Correcting the vehicle](shift-workflow.md#correcting-the-vehicle-before-any-driving-is-recorded).

### Which vehicle a shift says it was worked in

A shift that took its economy from a vehicle also records **what that vehicle was
called**, and shows it under the two figures. It is a label and never an input:
no estimate, rate or total reads it, and a shift with an economy but no name
produces exactly the same figures.

It is a copy rather than a link, so a shift stays intelligible when the profile
behind it is renamed or deleted. The name is recorded beside an economy only when
it **is** that vehicle's economy: a driver who types a different figure by hand
records no vehicle, because DashPilot does not know which vehicle covers that
many miles on a gallon.

The **running** shift shows the same two facts on its own panel, so a driver with
two vehicles who forgot to switch can see it without opening Settings. See
[Which vehicle the shift is using](shift-workflow.md#which-vehicle-the-shift-is-using).

## Missing is not zero

A shift with **no fuel economy** recorded is not a shift that used no fuel, and
one with **no gas price** recorded is not one whose fuel was free. Each absence
produces a sentence naming the half that is missing, never `$0.00` and never a
dash. The same holds for the route: a shift that retained no usable position has
no recorded mileage to estimate over, which is a different statement from a shift
that recorded no distance.

Two things are deliberately **not** treated as missing:

- A recorded gas price of **zero** is a fact. It means the fuel was recorded as
  having cost nothing, and it produces an estimate of `$0.00`.
- A route that was measured and covered **no distance** is a measurement. It
  consumed no fuel, and the estimate says so.

A fuel economy of zero is refused outright, because it is the divisor and there is
no truthful reading of a vehicle that covers nothing on a gallon.

## It follows the recorded mileage, including when that changes

The estimate is derived, never stored. It divides the same recorded mileage every
other figure on the screen divides, so anything that changes what the route
measures changes the estimate with it. Correcting a shift's end time is the case
that matters: moving the end earlier deletes the route recorded after it, the
distance is measured again from the positions that remain, and the estimate
follows, with both assumptions untouched. See
[Correcting a shift's end time](shift-workflow.md#correcting-a-shifts-end-time).

**Recorded mileage is a floor.** Capture can be interrupted, and the distance
across a gap is left out rather than guessed, so where the route is partial the
screen says what that means in both directions:

- the estimated fuel is a **floor**: more miles were driven than were recorded,
  so more fuel was used than this estimates;
- the estimated net is therefore a **ceiling**: less was left than is shown.

See [Recorded mileage](recorded-mileage.md).

## An estimate is not a recorded expense

DashPilot records operating expenses, including a `fuel` category, and those
records are a completely separate fact. See [Recorded expenses](expenses.md).

- Nothing on this page creates, changes or reads an expense, and recording fuel
  assumptions inserts no expense row.
- No expense total anywhere has an estimate added to it, and no estimate has a
  recorded cost taken off it.
- Recorded expenses are **not** part of a shift's estimated net, because an
  expense belongs to a date rather than to a shift. Net after recorded expenses
  remains a period figure: see
  [Period summaries](period-summaries.md).

### The overlap the app states rather than resolves

A driver who records the fill-up that paid for these miles now has two figures
that describe overlapping money, in two places: a recorded fuel expense dated to
a day, and an estimated fuel cost derived for a shift.

DashPilot **does not reconcile them**, and this is deliberate. It does not know
which shifts a tank of fuel was burned on, so any automatic matching would be an
attribution the driver never made, and no later screen or export could tell it
apart from one they did. That is the same refusal behind an expense having no
shift in the first place. The two figures are kept in separate sections, are
never added together and are never netted against each other, and the screen says
so.

## What the screen shows

On a completed shift's detail, in the **Costs** section, under the recorded
figures, the gross rates and the route:

- `Estimated fuel cost`, with `Based on recorded mileage` under it, or a sentence
  naming the half that is missing
- `Estimated gallons`
- `Vehicle`, `Miles per gallon` and `Gas price per gallon`, as recorded for this
  shift
- `Add Fuel Assumptions` / `Edit Fuel Assumptions`
- then the net, as a ledger in the order the subtraction happens:
  `Recorded earnings`, `Estimated fuel cost` as the amount being subtracted,
  `Estimated net after fuel` (drawn heavier, as the result) and
  `Estimated net per working hour`

The section sits after everything recorded, deliberately. What the driver
recorded and what the route measured are the trustworthy part of the screen, and
reading down it should go from the recorded to the estimated rather than mix
them.

**A shift with no estimate is still fully readable.** Every recorded amount,
duration, count and gross rate is exactly where it was, and only the Costs
section says what is unavailable and why. A fuel estimate is never a
precondition for reading a completed shift.

## Working time is the app's existing definition

`Estimated net per working hour` divides by **working duration**: the shift's
elapsed time less the stretches the driver paused it. That is the same
denominator the shift's gross hourly rate uses and the same division, so the two
hourly figures on one screen cannot disagree. See
[Earnings and metrics](earnings-and-metrics.md#the-hourly-rate-divides-by-working-time).

A shift with no measurable working time has no hourly figure, and is told so
rather than shown a zero.

## The estimated net may be negative

A shift whose estimated fuel came to more than it recorded being paid produces a
negative estimated net, and it is shown as one. That is a real outcome of a bad
shift over a long drive, not an error to clamp to zero.

## Accessibility

Each figure speaks what it is and what it rests on, rather than relying on the
caption beside it:

- the fuel cost speaks `based on recorded mileage`, and the partial-route
  sentence where it applies
- the gallons speak the unit as a word, because `gal` reads well and hears badly
- each assumption speaks what it is assumed to be, or that it was not recorded
- the net speaks `estimated net after fuel`, and the hourly figure names its
  denominator

## Privacy

Nothing here leaves the device, because nothing in DashPilot does. There is no
gas-price lookup, no station search, no vehicle service and no network access at
all.

The log records that a pair was recorded, changed, removed or refused, and
**never a figure**: not the miles per gallon, not the gas price, not the estimate
and not the net. A gas price is also a statement about where and when somebody
fills up, which is the kind of value this project keeps out of its logs
everywhere. See [Privacy](../architecture/privacy.md).

## In an export

A shift's JSON record carries `fuelMilesPerGallon` and `fuelGasPricePerGallon`,
each an explicit `null` where the driver recorded none. The **estimate itself is
deliberately not exported**: the file carries the recorded facts and the
assumptions, and a reader who wants the estimate applies the rule at the top of
this page to the recorded mileage already in the same record. The export format
version is unchanged. See [History export](history-export.md).

## Over a period

A day, a week, a month or a chosen range states what its shifts are estimated to have spent on fuel,
and what they are estimated to have been left with after it. Both are on the period summary, under
every recorded figure, and both come from the same per-shift arithmetic above rather than from a
second one.

### Partial coverage is the whole problem

A week can hold six shifts of which four recorded a fuel economy, a gas price and a measurable route.
Adding those four estimates gives a real figure. Presenting it as *what this week cost in fuel* is a
claim about six shifts made from four, and that is what the coverage exists to prevent.

So the estimate never travels without the counts behind it, in **two** units, because either alone
can mislead:

```
Estimated fuel                     $24.81
4 of 6 shifts · 142.3 of 188.9 recorded miles · 75% of recorded miles
```

- **Shifts** says how much of the week's *work* is behind the figure.
- **Recorded miles** says how much of its *driving* is. Two short shifts missing their assumptions
  cost less coverage than one long one, and only the mileage says so.

A percentage is derived from the mileage, because fuel is consumed over distance, and it is never
the only thing said: a percentage cannot say which shifts are missing or how long they were. Where
every shift is covered the screen says so in as many words, because "no coverage stated" and
"complete coverage" must not look the same. Where none is covered it says the estimate is
unavailable, never `$0.00`.

### The estimated net is worked out over the shifts that record both halves

The tempting arithmetic is `period earnings - period estimated fuel`, and it is wrong whenever the
two have different coverage: it takes a fuel figure from four shifts off an earnings figure from six
and labels the result as the period's.

So the subtraction is performed over the **paired subset** — the shifts that recorded an amount *and*
have an estimate — which is the rule every rate in DashPilot already follows. Both halves are shown
under the figure, so a reader can see what it was worked out from, and when the subset is not the
whole period the screen says so:

```
Estimated net after fuel           $92.00
$100.00 recorded less $8.00 estimated fuel
Worked out over the 1 of 2 shifts that record both an amount and enough to estimate their fuel.
It is not this period's earnings less this period's fuel.
```

It may be negative, which is a real outcome. Where a contributing route is partial the fuel is a
floor and the net is therefore a **ceiling**, and the screen says that too.

### Estimated fuel and recorded expenses are never combined

This is the screen where the overlap [documented above](#the-overlap-the-app-states-rather-than-resolves)
becomes visible for the first time: a recorded `fuel` expense and an estimated fuel cost can appear a
few rows apart, and they may describe the same money.

DashPilot keeps them in **two sections**, each labelled for what it is, and adds them nowhere:

- **Net after recorded expenses** is recorded gross earnings less the costs the driver entered.
- **Estimated net after fuel** is recorded earnings less an estimate, over the paired subset.

Neither has the other taken off it, and no figure anywhere subtracts both. Subtracting both under one
label would count the same fuel twice, and DashPilot does not know which shifts a tank was burned on.
The reconciliation rule does not exist, so the app shows two honest figures rather than one invented
one.

### Two periods are not compared on an estimate

The period comparison states no estimated figure. Two periods whose fuel coverage differs are not
like with like, and two estimated under different assumptions — a different vehicle, a different
price — are answers to two different questions. Nothing ranks periods, scores them or declares one
more profitable than another.

### In History

Each week in History carries the same two figures above its shifts, with the same coverage, and
only when the week has them. They sit last on the card, in a surface of their own headed `Estimated
from fuel assumptions`, below every recorded figure and both gross rates, and no rate on the card
reads from them. The fuel line states both coverages (`2 of 3 shifts ·
59.6 of 89.4 recorded miles`) and the net line is labelled as coming before recorded expenses; a
partial route in the week makes the fuel a floor and the net a ceiling, and the card says so. Each
shift is estimated under the assumptions **it** recorded, so a week is never restated by today's gas
price. Net after recorded expenses is deliberately not on that card: it stays on the period summary,
so the two nets never sit side by side on a small card where they could be read as one. A week where
no shift recorded assumptions simply does not carry the lines, because a summary above a list is not
the place to explain an absent estimate: the shift's own detail screen is, because that is where it
can be acted on.

## What these figures are not

- **Not a recorded expense**, and not proof that any fuel was bought.
- **Not proof of fuel consumed**, or of what this vehicle costs to operate.
- **Not profit, net income or take-home pay.** Nothing for wear, insurance,
  maintenance, depreciation, phone costs or tax is subtracted anywhere in
  DashPilot.
- **Not a tax figure.** There is no deduction, no mileage allowance and no
  classification of anything as claimable.
- **Not a measurement of the vehicle.** The fuel economy is whatever the driver
  typed, and the app neither checks it nor learns it.
- **Not a total for the driving that was done**, where the route is partial. It
  covers the miles that were recorded, and says so.
