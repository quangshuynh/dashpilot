# The shift on the Lock Screen

While a shift is running, DashPilot puts one Live Activity on the Lock Screen and, on the hardware
that has one, in the Dynamic Island. It shows what the shift has recorded so far and offers the one
or two controls that apply, so a driver with the phone in a cradle can see where they stand and act
without unlocking it.

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

Every one of those is the app's own figure rather than a second calculation. The working duration is
`Shift.workingDuration(asOf:)`, the same one every hourly rate divides by and the same one a spoken
confirmation reports. The mileage sentence is `RouteQuality`'s, so the Lock Screen and the app cannot
drift into describing the same route differently, and the partial marker travels with the figure
wherever the figure goes. See [Recorded mileage](recorded-mileage.md).

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
| Running, with no delivery open | **Pause Shift**, **End Shift** |
| Running, with exactly one delivery open | That delivery's next step: **Arrived at Pickup**, then **Picked Up**, then **Delivered** |
| Running, with two or more deliveries open | Nothing, and the reason |
| Paused | **Resume Shift**, **End Shift** |

Pausing and ending are both refused while a delivery is in progress, so neither is offered then.
Ending a **paused** shift is permitted, and closes the pause at the end instant rather than making a
driver resume work they did not do, so End stays on the card while paused. See
[Shift workflow](shift-workflow.md).

A control is a courtesy and never a permission. Pressing one runs the same service the app's own
button runs, which asks the store, so a card that is a moment out of date costs a refusal sentence
rather than a wrong write.

### The refusal that is the point

With two orders in the car there is no "the delivery". A Lock Screen button names no particular
order, and every way of choosing one (the newest, the oldest, the one furthest along) would write a
driver's tap into a record they did not mean. So the card offers nothing and says so:

> Several deliveries are in progress. Open DashPilot to record a step.

The status line goes too: a card that named one of two orders would be picking one on the driver's
behalf. The refusal lifts by itself once one of them has been delivered or cancelled. This is the
same rule the spoken step follows, from the same place in the code. See
[Voice and system actions](voice-actions.md#the-rule-that-exists-only-off-screen).

## The clock counts itself

The working figure is not pushed once a second. The card carries the instant the figure was read at,
and the system draws a clock from it: while the shift runs, working time grows at exactly the rate
wall-clock time does, so one anchor stays correct for the length of the shift with no updates at all.
While the shift is paused the figure does not move, so it is drawn once.

What is left to update is the route figure, which waits **30 seconds** between changes, and anything
that changes what the card means: pausing, resuming, a delivery starting or advancing, a control
appearing or disappearing. Those go over at once, because a driver who paused and saw no
acknowledgement would reasonably press it again.

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
  no entering an amount. A cancellation cannot be undone and a monetary figure is not an interaction
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
