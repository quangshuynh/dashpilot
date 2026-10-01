# Settings: vehicles, fuel defaults, pickup and parking

DashPilot keeps a small set of reusable preferences so that figures a driver
would otherwise retype on every shift are typed once. It is reached from the gear
in the top left of the main screen.

It opens with the **default vehicle** the next shift will record, then the
**vehicles** the driver works in, the **gas price** they last paid, one
**pickup workflow** switch, and an **About** section:

```
Settings

Default Vehicle
  2020 Honda Civic
  34 MPG
  Used for your next shift

Vehicles
  2020 Honda Civic
  34 MPG
  ✓ Default                                   ✎

  2012 Toyota Camry
  28 MPG                                      ✎

  Add Vehicle

Fuel Defaults
  Current gas price               $3.19 / gallon
  Recorded on your next shift

Pickup Workflow
  Pick up orders with Park & Resume          ( off )
  Handle stacked orders in order             ( off )

About
  Acknowledgements
```

With nothing selected the first section says `No vehicle selected` and that the
next shift records no miles per gallon, rather than drawing an empty card.
Starting a shift is never refused over it. Nothing about the vehicle or the gas
price reaches a shift already running. The two pickup switches are the only
preferences that act during a shift, and only at the moment Park or Resume
Driving is pressed.

## The vehicle and the gas price are defaults for the next shift

This is the one sentence the screen exists to get across: the default vehicle
says `Used for your next shift`, the gas price says `Recorded on your next shift`,
and both footers say it in as many words.

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
- Selecting a different vehicle changes the next shift and nothing before it. The
  root screen says which vehicle that is, above `Start Shift`. See
  [Which vehicle the next shift will record](shift-workflow.md#which-vehicle-the-next-shift-will-record).
- None of the above reaches the shift **currently running** either. Its panel goes
  on naming the vehicle it recorded when it started, which is the question a
  driver mid-shift is actually asking. See
  [Which vehicle the shift is using](shift-workflow.md#which-vehicle-the-shift-is-using).

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
- **One is the default**, marked `Default` with a check beside the word, and is
  the one new shifts are recorded under. The first vehicle added is selected automatically, because a
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

## Correcting the shift in progress

A driver who started a shift in the wrong vehicle can correct **that shift's own
snapshot**, from the running shift's panel, and only while its route has recorded
no distance. Choosing a vehicle there copies that vehicle's current name and
miles per gallon onto the shift; nothing in Settings is written, the selection is
not moved, and a later change to either does not follow. The correction closes
once driving has been recorded.

That is the only way a preference ever reaches a shift after it has started, and
it only ever happens because the driver saved. See
[Correcting the vehicle](shift-workflow.md#correcting-the-vehicle-before-any-driving-is-recorded).

The three switches below sit together under **Pickup & Parking**. Each says in one line under its
name what it does, and the one that depends on another says on screen why it is unavailable.

## Pick up orders with Park & Resume

**Off unless the driver turns it on.** A driver who never opens this switch parks and resumes
exactly as they always have.

It is for the stop a driver makes at a pickup: park, walk in, wait, collect the order, walk back,
drive off. With it on:

- **Park** records the vehicle as parked, then records `Arrived at Pickup` for the delivery being
  picked up.
- **Resume Driving** records the vehicle as driving, then records `Picked Up` for **that same
  delivery**.

Both steps go through the same operations the buttons on the delivery's card run, with the same
refusals, and both surfaces behave identically: the app's buttons, `Park my vehicle in DashPilot`
and its Resume counterpart, and the Lock Screen's `Park Vehicle` and `Resume Driving`.

### Which delivery

| Deliveries in progress when Park is pressed | What Park records |
| --- | --- |
| One, heading to its pickup | Parked, and that delivery `Arrived at Pickup` |
| One, already at `Arrived at Pickup` | Parked only; Resume Driving will record its pickup |
| One, already picked up | Parked only, and nothing more is said (this is a stop at a customer) |
| Two or more, `Handle stacked orders in order` off | Parked only, and the panel says why |
| Two or more, `Handle stacked orders in order` on | Parked, and the lowest-numbered delivery still waiting for its pickup `Arrived at Pickup` (or nothing new, if it already was) |
| Two or more that all share one pickup the driver marked [`Same pickup`](delivery-lifecycle.md#same-pickup-and-same-drop-off), either answer | Parked, and every one still waiting for its pickup `Arrived at Pickup`, together |
| The chosen delivery shares a pickup with others, `Handle stacked orders in order` on | Parked, and it and the others sharing its pickup `Arrived at Pickup`, together |

"Lowest-numbered" is the delivery number its card shows, which is the order the deliveries were
accepted in. With Delivery 3 and Delivery 4 both heading to their pickups, the first Park and Resume
work on Delivery 3, and the next on Delivery 4. A delivery already picked up, delivered or cancelled
is never chosen and never moved. Nothing else is consulted: not distance, location, pickup place,
expected pay or the order of the cards on screen. The one thing that joins deliveries is the
driver's own `Same pickup`; a shared **drop-off** never does, because one customer can order from
two restaurants.

**Resume Driving does not choose again.** It records the pickup of the delivery Park chose for that
stop, which is stored with the parked stretch so it survives the app being closed while the driver
is inside, and it does so only if that delivery is still at `Arrived at Pickup`. For a shared pickup
it is every delivery Park stored, recorded together. A delivery cancelled
while the driver was inside is not replaced by the next one; one whose pickup the driver already
recorded by hand is left alone.

### Handle stacked orders in order

**Off unless the driver turns it on, and it does nothing while the workflow is off.** It is drawn
under the workflow switch and is disabled until that switch is on, with `Needs Pick up orders with
Park & Resume on` under its name while it is; its own answer is kept either way. It is a separate choice because with two or more orders the one Park acts on is chosen by a
rule rather than being the only one there is, and parking at a customer's door with another order
still to collect would mark that order `Arrived at Pickup`. Undo is the way back from exactly that.

### Undo

Beside a step the workflow has just recorded, the panel offers **Undo** for the same short window
the app's immediate undo of a `Delivered` uses (20 seconds on screen). It takes back **exactly what
that press recorded and nothing else**, one delivery's step or the same step for every delivery of a
shared pickup, all of them or none: after Park, the delivery goes back to `Accepted` and the vehicle stays
parked; after Resume Driving, the delivery goes back to `Arrived at Pickup`, its pickup is no
longer recorded, and the vehicle stays driving. It is refused, and says why, if anything has been
recorded for that delivery since. It is offered only in the app, only by the screen that made the
press, and not after the app is closed. After that, the delivery's ordinary controls and the
finished shift's [time correction](delivery-lifecycle.md#correcting-the-times-a-delivery-recorded) are the way to change what was recorded.

### What it will not do

- **It never detects anything.** DashPilot does not know where the vehicle stopped, or
  when an order was handed over. The panel says a step was recorded **automatically when you
  parked** or **when you resumed driving**, and its spoken form names this setting.
- **It never records Picked Up from Park**, and never records either step for a delivery the rule did
  not name.
- **It never lets a delivery step undo the vehicle.** The vehicle state is saved first. If the
  delivery step is then refused or cannot be saved, the vehicle stays parked (or driving) and the
  panel says the step was not recorded.

**The steps are recorded at the moments the vehicle was.** One consequence is worth knowing: the
delivery's [recorded pickup wait](pickup-wait.md) then runs from parking to driving away, which
includes the walks and any time spent in the vehicle before pressing Resume Driving. So DashPilot
records that **Resume Driving** recorded the pickup, and that wait is
[left out of typical and median waits](pickup-wait.md#pickups-recorded-automatically), with a
sentence beside the figure saying how many were. The footer says so.

Unlike the vehicle and the gas price, these switches are not copied onto anything. They are read at
the moment Park or Resume Driving is pressed and nowhere else, and changing them changes the next
press and no delivery already recorded.

**The earlier `Pick up order when parking` switch was retired.** It let Park record `Picked Up`,
which this workflow replaces. Because the new switch records different steps at different moments,
turning the old one on is not taken as agreeing to this one: after updating, the workflow is off
until the driver turns it on.

## Resume driving after delivery progress

**Off unless the driver turns it on, and independent of the two switches above.** It answers a
different question: not what Park records when the driver arrives, but whether the driver's own
`Picked Up` or `Delivered`, recorded while the vehicle is parked, may also record driving again.

With it on, a `Picked Up` or `Delivered` recorded while parked resumes driving **only when that stop
has nothing left to record**:

| Just recorded | The vehicle stays parked while |
| --- | --- |
| `Picked Up` | another order marked [`Same pickup`](delivery-lifecycle.md#same-pickup-and-same-drop-off) with it is still to collect, or any other order in progress is still to collect |
| `Delivered` | another order marked `Same drop-off` with it is still to hand over, or any other order already in the car is still to hand over |
| Either | an order Park chose for this stretch (under the pickup workflow) is still at `Arrived at Pickup` |

Otherwise driving resumes, through the same operation the `Resume Driving` button runs, at the
instant the step was recorded: a new route recording starts, nothing is measured across the parked
stretch, and working time is unchanged, exactly as after the button.

**Orders the driver did not mark are not assumed to be elsewhere.** DashPilot cannot tell two orders
from one restaurant from two orders from two restaurants, so with an unmarked order still needing
the same kind of stop, it stays parked rather than guess that the driver has left; `Resume Driving`
is one tap. `Same pickup` never counts as `Same drop-off`, nor the other way round.

It **never** resumes a paused shift, never touches a running one that is not parked, reads no
position or speed, and never records a pickup itself. The line under the list says what happened, for
example `Delivery 3 picked up · driving resumed`, and that it was this setting; it never says the
vehicle moved or the driver left. When it keeps the vehicle parked it says which order is still
waiting. Siri and the Lock Screen's step control follow the same rule, and say it aloud.

**Undo** beside that line, for the same 20 seconds as every other immediate Undo, takes back **both**
the step and the driving: the delivery returns to where it was, the parked stretch reopens as if it
had never closed, and the route positions recorded since are removed, because they were recorded
during what the driver now says was still the parked stretch. It is refused whole, with the reason,
if anything was recorded for that delivery since, or if the vehicle was parked again, the shift
paused or ended. It is offered only in the app.

## Accessibility

- The default vehicle is one element: "Default vehicle: 2020 Honda Civic, 34
  miles per gallon. Used for your next shift."
- A vehicle row is one element that speaks its name, its economy with the unit
  spelled out ("34 miles per gallon", not "34 MPG") and whether it is the
  default, because a check mark is not a statement to a listener. The edit
  control beside it names the vehicle and keeps a 44-point target.
- In the vehicle editor each label sits above its field, so a long name and the
  largest text sizes get the whole width of the row. A refusal is a sentence
  beside a warning symbol, and the symbol is hidden from VoiceOver so the
  sentence is what is heard.
- The gas price row states its figure as a value with the unit spoken in full,
  and its hint says that changing it affects the next shift rather than a
  recorded one.
- Both footers carry the historical-stability sentence, so the rule is readable
  rather than something a driver has to infer from behaviour.
- `Pick up orders with Park & Resume` and `Handle stacked orders in order` are
  standard switches whose spoken hints say what each records. The second is
  announced as dimmed while the first is off. The line Park or Resume Driving
  adds carries a symbol and words, never a tint alone, names the delivery, and
  its Undo control says which step it takes back and that the vehicle stays as
  it is.

## Acknowledgements

`About` → `Acknowledgements` states the two licenses DashPilot ships under: its
own source code is MIT, and the one typeface it bundles, Manrope, is under the
SIL Open Font License 1.1, whose full text is bundled beside the font files and
shown there. See [Building](../development/building.md#the-typeface-and-its-license).

## Privacy

Vehicle names are free text the driver typed and are treated exactly as pickup
place names and expense notes are: they stay on the device and are **never
logged**. The fuel economy and the gas price are never logged either. The log
records only that a vehicle was added, changed or removed, that the selection
changed, that a price was recorded or removed, and which rule refused one.

Correcting a running shift's snapshot logs the same way: that a correction
happened, and which rule refused one. Never the vehicle, never the economy and
never the price.

Parking with the pickup setting on logs only that the automation was applied, that
no delivery was at a pickup, or how many were when it declined to choose. Never
which delivery, never when, and never where.

Nothing here reaches the network, because there is no network code in DashPilot.

## In an export

The driver's current preferences are **not** exported. Not the vehicle list, not
the selection, not the gas price, and not the pickup-when-parking switch. An export is a record of work done, and what a
driver has selected today says nothing about the shifts in it.

A delivery picked up by the parking setting exports exactly as one picked up
from its card: its `pickedUpAt` is the instant recorded, and nothing marks which
control recorded it.

What is exported is the shift's own snapshot: the fuel economy, the gas price and
the vehicle name it recorded, each an explicit `null` where it recorded none. See
[History export](history-export.md).
