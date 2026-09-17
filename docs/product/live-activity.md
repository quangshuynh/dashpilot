# The shift on the Lock Screen

While a shift is running, DashPilot puts one Live Activity on the Lock Screen and, on the hardware
that has one, in the Dynamic Island. It shows what the shift has recorded so far and offers the few
controls that apply, so a driver with the phone in a cradle can see where they stand and act without
unlocking it.

One activity represents **the shift**, never an individual delivery. A driver working three stacked
orders is working one shift, and three cards competing for the same glance would be three chances to
act on the wrong one.

## What it shows

| Line | What it is |
| --- | --- |
| `Shift in Progress` / `Shift Paused` | Which of the two states the shift is in, in colour and in a symbol |
| The large figure | **Working** time so far: elapsed time less the time the shift has been paused |
| `4.5 mi recorded · partial route` | What the retained route supports, with the marker that qualifies it |
| `2 in progress · 5 delivered` | How the shift's deliveries stand |
| `Waiting at the pickup` | What the one delivery in progress is doing, and only when there is exactly one |
| `Delivery 1 · 18:04` | How long that delivery has been open, counting, one line per delivery in progress |

Every one of those is the app's own figure rather than a second calculation. The working duration is
`Shift.workingDuration(asOf:)`, the same one every hourly rate divides by and the same one a spoken
confirmation reports. The mileage sentence is `RouteQuality`'s, so the Lock Screen and the app cannot
drift into describing the same route differently, and the partial marker travels with the figure
wherever the figure goes. See [Recorded mileage](recorded-mileage.md).

## How long a delivery has been open

Under the delivery counts, each delivery in progress gets a line of its own:

> `Delivery 1 · 18:04`

The number is the one the app calls that delivery everywhere else, taken from the order the shift
accepted them in. It is not a platform order number and it names nothing outside the app. See
[Offers and deliveries](delivery-lifecycle.md#offers-and-deliveries).

The clock counts from the delivery's own **accepted** timestamp, which is the instant every other
duration derived from that delivery starts at: the stretch it contributes to the shift's delivery
active time, and the duration a finished delivery reports. Nothing new is measured and nothing is
stored. It is not adjusted for pauses, because a delivery's own elapsed lifecycle never has been and
a shift cannot be paused while a delivery is open.

**Nothing is added together.** A driver carrying two orders has two lifecycles running over the same
minutes, so one combined figure would be longer than the shift has been running and would belong to
neither order. The card therefore counts each of them separately, exactly as the app unions
overlapping deliveries rather than summing them. See
[Delivery lifecycle](delivery-lifecycle.md#stacked-deliveries).

**A delivered or cancelled delivery has no line.** It stops counting by leaving the card, not by
freezing at a number that still looks live, and the duration that delivery finally reports is
unchanged by any of this.

Past three open orders the card states the remainder rather than drawing a fourth line
(`1 more also active`): the controls sit below these lines, and pushing the buttons a driver reaches
for off the bottom of a fixed-height card would be worse than saying how many timers are in the app.

VoiceOver reads the delivery's name as its own element ahead of the figure, as
`How long Delivery 1 has been active`, so the count that follows is heard as a duration of something
rather than as a bare number. The figure itself is left unlabelled for the same reason the shift's
clock is: the system speaks it from the anchor, and a label of ours would replace a live duration
with whatever the snapshot was built at.

## What it never shows

No money in any form: no recorded gross, no hourly figure, no per-mile figure, no total, no
projection. No recommendation, no goal, no target. No address, no pickup place, no coordinate, no
customer, no note.

Half of those are facts DashPilot does not have. The rest are a driver's earnings and whereabouts,
printed on a surface that anyone standing beside them can read without unlocking the phone.

## What it offers

The controls follow the lifecycle rules the app already enforces, and the card offers only what those
rules permit:

| The shift is | The card offers |
| --- | --- |
| Running, with no delivery open | **Start Delivery**, **Pause Shift**, **End Shift** |
| Running, with exactly one delivery open | That delivery's next step (**Arrived at Pickup**, then **Picked Up**, then **Delivered**), and **Start Delivery** |
| Running, with two or more deliveries open | **Start Delivery**, and the reason there is no step |
| Paused | **Resume Shift**, **End Shift** |

A delivery [reopened in the app](delivery-lifecycle.md#taking-back-a-delivery-marked-delivered-by-mistake)
is a delivery in progress, so the card's counts and its controls follow it like any other change: the
snapshot is derived from the store, never from what the card was last told.

Pausing and ending are both refused while a delivery is in progress, so neither is offered then.
Ending a **paused** shift is permitted, and closes the pause at the end instant rather than making a
driver resume work they did not do, so End stays on the card while paused. See
[Shift workflow](shift-workflow.md).

Where three controls do not fit on one line, at the larger text sizes, they wrap to a second row
rather than having their labels cut short. A button a driver has to guess at is how the wrong thing
gets recorded.

### Starting a delivery

**Start Delivery is offered on every running shift**, whether the driver is carrying nothing or
three orders. It is the one control here that names no existing delivery: it creates one, so there is
no order for it to be aimed at by mistake, and the refusal below does not apply to it. A second press
records a second delivery beside the first and changes nothing about the first. Stacked deliveries
are how the app has always modelled this work, and the card now says so. See
[Delivery lifecycle](delivery-lifecycle.md).

It records **one fact**: that a delivery was accepted, at the instant the button was pressed, in an
offer of one. No count, no amount, no expected amount, no pickup place. Those need a keyboard and a
screen the driver is looking at, and the driver can add them later from the app.

**Recording an offer that held several deliveries is deliberately not on the card.** It needs a
number, and a number needs a control that can be got wrong and then corrected; a Lock Screen button
that meant "two deliveries" would be one press away from the button that means one. A driver who
accepted a stacked offer either presses Start Delivery once per dropoff, which records them as
separate offers, or records the offer in the app. See
[Offers and deliveries](delivery-lifecycle.md#offers-and-deliveries).

A **paused** shift does not offer it, because a paused shift is one the driver said they had stopped
working on, and starting a delivery on one is refused by the same rule that refuses it in the app and
by voice. If a card that is a moment out of date is pressed after the shift was paused or ended, the
refusal comes from the store rather than from the card.

A control is a courtesy and never a permission. Pressing one runs the same service the app's own
button runs, which asks the store, so a card that is a moment out of date costs a refusal sentence
rather than a wrong write.

### The refusal that is the point

With two orders in the car there is no "the delivery". A Lock Screen button names no particular
order, and every way of choosing one (the newest, the oldest, the one furthest along) would write a
driver's tap into a record they did not mean. So the card offers no step at all and says so:

> Several deliveries are in progress. Open DashPilot to record a step.

The status line goes too: a card that named one of two orders would be picking one on the driver's
behalf. The refusal lifts by itself once one of them has been delivered or cancelled.

**The timers stay**, and they stay for the same reason Start Delivery does. A step has to know which
order a tap belongs to, and with two open there is no answer; a clock says which delivery it is
counting, so there is nothing for it to be wrong about. This is the
same rule the spoken step follows, from the same place in the code. See
[Voice and system actions](voice-actions.md#the-rule-that-exists-only-off-screen).

**Start Delivery stays**, and the distinction is what the refusal turns on. A step has to know which
order it belongs to, and with two open there is no answer. Starting one has to know nothing about the
orders already running.

Two deliveries of **one offer** are two deliveries, so they withhold the step exactly as two offers
do. The card counts deliveries and never offers: it says `2 deliveries in progress` whether they
arrived in one acceptance or two, and it carries no offer wording at all.

## The clock counts itself

The working figure is not pushed once a second. The card carries the instant the figure was read at,
and the system draws a clock from it: while the shift runs, working time grows at exactly the rate
wall-clock time does, so one anchor stays correct for the length of the shift with no updates at all.
While the shift is paused the figure does not move, so it is drawn once.

**Each delivery's clock is free in the same way.** The card carries the instant that delivery was
accepted rather than how long it has been open, so the system counts it and the app pushes nothing
for as long as the delivery runs.

What is left to update is the route figure, which waits **30 seconds** between changes, and anything
that changes what the card means: pausing, resuming, a delivery starting, advancing or finishing, a
control appearing or disappearing. Those go over at once, because a driver who paused and saw no
acknowledgement would reasonably press it again.

**Which deliveries are being counted is one of those things.** An order finishing at the moment
another is accepted leaves every count on the card where it was, so the list of clocks is compared
directly; without that the card would keep counting an order that had already been delivered.

## It follows the store, never the other way round

SwiftData remains the only place a shift's state lives. The card is a picture of it, and the app
reconciles that picture whenever the store changes: a shift starting, pausing, resuming or ending, a
delivery advancing, a batch of route reaching the store, the app returning to the foreground, and the
first moment a screen appears after a relaunch.

Three consequences worth stating, because a Lock Screen makes them invisible:

- **A relaunch mid-shift adopts the card the shift already has** rather than adding a second.
- **A card left behind by a shift that has ended is removed**, which is the one way termination at
  the wrong moment could leave a Lock Screen claiming work that had stopped.
- **Ending a shift removes the card immediately**, rather than letting the system keep it for its
  usual lingering period. An activity outliving its shift is the one failure this surface must not
  have.

Nothing is ever read back from ActivityKit to decide what happened. The only thing asked of it is
which cards exist and which shift each says it is about, which is what makes the cleanup above
possible.

## The recording claim, stated plainly

A Lock Screen card is a continuous surface, and recording is not continuous. A route capture session
keeps running when the driver locks the phone, but **iOS may suspend or terminate the app at any
point and nothing relaunches it**. The card's mileage figure is what the route supports so far and is
a floor on the miles driven, exactly as it is everywhere else in the app; if capture has stopped, the
figure simply stops growing, and the route carries the gap rather than being measured across it.

The card does not claim that recording is running. It reports what has been recorded. The place that
says whether capture is running right now, and why it is not, is the app's own status line.

## What is not here

- **No notification, and nothing that alerts.** The card never makes a sound, never wakes the screen
  by itself, and never nudges a driver to do anything. Nothing ends a pause by itself and nothing
  reminds a driver of one.
- **No control that cannot be undone from the app.** No cancelling a delivery, no deleting anything,
  no entering an amount. A delivery started by mistake can be cancelled in the app, which keeps it in
  history rather than erasing it, so the start is not one of these. A cancellation cannot be undone and a monetary figure is not an interaction
  to ask for from a moving car, which is the same line the voice surface draws.
- **No Home Screen or Lock Screen widget.** A widget is a periodic summary of stored history, and
  deciding what a driver's earnings look like on a shared screen is a decision this project has not
  made.
- **No push token and no remote update.** The app updates its own card from its own store. Nothing
  about it leaves the device. See [Privacy and logging](../architecture/privacy.md).
- **A Dynamic Island is not assumed.** Every supported device shows the Lock Screen presentation; the
  island is a second reading of the same card on the hardware that has one, and no fact appears only
  there.

## If Live Activities are turned off

Nothing changes about what is recorded. The shift, its route, its deliveries and its pauses are
written exactly as they always were, and the app's own screen is unaffected. The card is a way to see
and control a shift, never a part of recording one.
