# Settings: vehicles and fuel defaults

DashPilot keeps a small set of reusable preferences so that figures a driver
would otherwise retype on every shift are typed once. It is reached from the gear
in the top left of the main screen.

There are two things in it: the **vehicles** the driver works in, and the **gas
price** they last paid.

```
Settings

Vehicles
  ✓ 2020 Honda Civic
    34 MPG

  2012 Toyota Camry
    28 MPG

  Add Vehicle

Fuel
  Current gas price          $3.19 / gallon
```

## Everything here is a default for the next shift

This is the one sentence the screen exists to get across, and both of its footers
say it in as many words.

Nothing derived reads these preferences. Not an estimated fuel cost, not a rate,
not a total, not a coverage count, not a period figure and not an exported value.
They are read at exactly one moment — **when a shift starts** — and copied onto
that shift, which owns its copy from then on.

So:

- Changing the gas price tomorrow does not restate what last week's shifts cost.
- Correcting a vehicle's miles per gallon does not re-cost the shifts worked
  under the old figure.
- Deleting a vehicle leaves every shift worked in it exactly as it was, still
  naming that vehicle.
- Selecting a different vehicle changes the next shift and nothing before it.

That is structural rather than a rule somebody has to keep: a finished shift holds
the facts it was estimated under, and there is nothing for it to follow. See
[Estimated fuel and net](estimated-fuel.md).

## Why the snapshot is taken at the start of a shift

The assumptions a shift is estimated under should be the ones that were true
while it was being worked. A driver who changes vehicle at lunchtime, or who
notices the price has gone up, has not changed what the shift has already
consumed — and reading the defaults when a shift *ended* would let a change made
mid-shift silently rewrite the assumptions the whole shift was worked under.

Starting a shift is also the last moment those facts cannot have moved, which is
what makes the snapshot honest rather than merely convenient.

Two consequences worth knowing:

- A shift started while nothing is set records **nothing**, which is exactly what
  every shift recorded before Settings existed carries. It reports which half of
  its estimate is missing, never an estimate of `$0.00`.
- A shift already carrying assumptions is never overwritten by a default. The
  snapshot may only ever fill an empty pair.

## Vehicles

A vehicle profile is two facts: a **name** the driver recognises and its **miles
per gallon**.

The list of what a vehicle deliberately is **not** is the point. There is no VIN,
no plate, no make, model or trim lookup, no odometer, no service schedule, no
insurance record and no purchase price anywhere in DashPilot. A vehicle exists to
hold the number a fuel estimate divides by.

- **Several vehicles are supported**, listed in the order they were added so the
  list does not reorder under a rename.
- **One is selected**, marked with a check, and is the one new shifts are
  recorded under. The first vehicle added is selected automatically, because a
  driver who has entered exactly one vehicle has said which one they work in.
  Tapping the selected vehicle again clears the selection, which is the way back
  to recording no economy at all.
- **A name is required**, trimmed, and kept short. A profile with no name cannot
  be picked out of a list.
- **A fuel economy of zero or less is refused**, because it is the divisor of
  every estimate a shift started under this profile will carry.
- **An edit moves both facts or neither.** Correcting a name and mistyping the
  economy in the same edit leaves the profile with the pair it already had.
- **Deleting is safe.** The confirmation says so: shifts worked in the vehicle
  keep their own miles per gallon, their estimated fuel and the vehicle's name.

## Current gas price

One figure: what a gallon costs the driver now.

- It is a **convenience, not a price history**. DashPilot keeps one current
  figure, not a series, and nothing anywhere records when it changed.
- **Nothing is looked up.** There is no network request, no station search and no
  use of where the device is. The only source of a gas price is the driver typing
  one.
- **Zero and unrecorded are different facts.** A recorded `$0.00` says the fuel
  is recorded as costing nothing; removing the price leaves DashPilot with none,
  so a shift that starts records none.
- A negative price is refused.

## Applying the defaults to a shift already recorded

A shift worked before the defaults existed records nothing, and nothing fills it
in on the driver's behalf.

What is offered instead is one explicit control. Opening that shift's fuel editor
shows `Use Current Defaults` under the two fields, with the figures it would fill
in named. Tapping it fills the fields; the shift records them only when the
driver taps Save. Abandoning the sheet writes nothing.

## Accessibility

- A vehicle row is one element that speaks its name, its economy with the unit
  spelled out — "34 miles per gallon", not "34 MPG" — and whether it is selected,
  because a check mark is not a statement to a listener.
- The gas price row states its figure as a value with the unit spoken in full,
  and its hint says that changing it affects the next shift rather than a
  recorded one.
- Both footers carry the historical-stability sentence, so the rule is readable
  rather than something a driver has to infer from behaviour.

## Privacy

Vehicle names are free text the driver typed and are treated exactly as pickup
place names and expense notes are: they stay on the device and are **never
logged**. The fuel economy and the gas price are never logged either. The log
records only that a vehicle was added, changed or removed, that the selection
changed, that a price was recorded or removed, and which rule refused one.

Nothing here reaches the network, because there is no network code in DashPilot.

## In an export

The driver's current preferences are **not** exported. Not the vehicle list, not
the selection, not the gas price. An export is a record of work done, and what a
driver has selected today says nothing about the shifts in it.

What is exported is the shift's own snapshot: the fuel economy, the gas price and
the vehicle name it recorded, each an explicit `null` where it recorded none. See
[History export](history-export.md).
