# The shift on the Lock Screen

While a shift is running, DashPilot puts one Live Activity on the Lock Screen and, on the hardware
that has one, in the Dynamic Island. It shows what the shift has recorded so far and offers the few
controls that apply, so a driver with the phone in a cradle can see where they stand and act without
unlocking it.

One activity represents **the shift**, never an individual delivery. A driver working three stacked
orders is working one shift, and three cards competing for the same glance would be three chances to
act on the wrong one.

## What it shows

The card is laid out in a fixed order, most important first, and the controls are never what gives
way:

| In order | What it is |
| --- | --- |
| `Shift in Progress` / `Shift Paused` / `Parked · route not recording`, beside the clock | Which state the shift is in, in colour and in a symbol, and **working** time so far: elapsed time less the time the shift has been paused |
| `Delivery 1 · At pickup · 18:04` | What each delivery in progress is doing and how long it has been open, one line each, as many as fit |
| The controls | In the order the app chose; see [What it offers](#what-it-offers) |
| `4.5 mi recorded · partial route · 5 delivered` | What the retained route supports, with the marker that qualifies it, and how many deliveries are done; drawn only when the card has room |

### Why the card has a height budget

The system cuts a Lock Screen Live Activity off at **160 points** tall, from the bottom. The card used
to draw a parked line, the mileage, the delivery counts, a status line and a line per order **above**
its controls, and measured in the app's own test host it was 242 points with one order in progress
and 266 once parked. On a real shift that cut off the controls, and after parking the one lost was
`Resume Driving`.

The card now gives each state a fixed number of lines between the header and the controls, decided by
how many rows of controls it has and the text size, and fills them in order: the orders, then the
sentence explaining a withheld step, then the mileage line. Whatever does not fit is left out rather
than drawn and cut: a count of the orders without a line (`2 more · Open DashPilot for steps`) takes
the last line, and the mileage is never drawn without its `partial route` marker. Measured the same
way, the tallest state is now 154 points. Text larger than `xLarge` is drawn at `xLarge` on the card,
because past it two control labels no longer fit side by side on the narrowest supported phone; the
app's own screens follow every text size.

Parked is said **in the header**, in place of `Shift in Progress`, rather than on a line of its own.
The clock beside it keeps counting, which is what says the shift is still running.

Every one of those is the app's own figure rather than a second calculation. The working duration is
`Shift.workingDuration(asOf:)`, the same one every hourly rate divides by and the same one a spoken
confirmation reports. The mileage sentence is `RouteQuality`'s, so the Lock Screen and the app cannot
drift into describing the same route differently, and the partial marker travels with the figure
wherever the figure goes. See [Recorded mileage](recorded-mileage.md).

## How long a delivery has been open

Under the header, each delivery in progress gets a line of its own:

> `Delivery 1 · At pickup · 18:04`

The **state** in the middle says what each order is doing; with one order it is the whole of the
delivery's status, and with two it is the only place each one's is said, because with two there is
no "the delivery" for a single status to be about. It is a shortened form of the
app's own vocabulary — `To pickup`, `At pickup`, `To customer` — derived in the app and drawn by the
extension, never a second set of words. It gives way first when the row is too narrow; the live
figure keeps its place.

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

Past the lines the card has room for, it states the remainder rather than drawing another line
(`2 more · Open DashPilot for steps`): pushing the buttons a driver reaches for off the bottom of a
fixed-height card would be worse than saying how many timers are in the app.

Deliveries the driver recorded as [sharing a pickup or a drop-off](delivery-lifecycle.md#same-pickup-and-same-drop-off),
in the same state since the same acceptance, are **one line**: `Deliveries 3 and 4 · At pickup ·
18:04`. One clock and one state are then true of both. Deliveries that share nothing the driver said
keep a line each, however alike they look.

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

| The shift is | The card offers, in order |
| --- | --- |
| Running, with no delivery open | **Start Delivery**, **Park Vehicle**, **Pause Shift**, **End Shift** |
| Running, with exactly one delivery open | That delivery's next step (**Arrived at Pickup**, then **Picked Up**, then **Delivered**), **Start Delivery**, **Park Vehicle** |
| Running, with two or more deliveries open, at least one picked up | **Delivered N** for the lowest-numbered picked-up delivery, **Start Delivery**, **Park Vehicle** |
| Running, with two or more deliveries open, none picked up | **Start Delivery**, **Park Vehicle**, and the reason there is no step |
| Parked | **Resume Driving** first, then whatever the row above offers, with **Park Vehicle** replaced |
| Paused | **Resume Shift**, **End Shift** |

**With [Pick up orders with Park & Resume](settings.md#pick-up-orders-with-park-resume) on, Park
Vehicle moves to the front** of every running row and takes the emphasis: `Park Vehicle`, then the
delivery's next step and `Start Delivery`, or `Park Vehicle`, `Start Delivery`, `Pause Shift`,
`End Shift` with nothing open. That driver records their pickups by parking and driving off, so the
parked pair is the control they reach for. Nothing is removed to make room: the delivery's step stays
on the card behind it, so a pickup recorded by hand, or a Delivered, is still one tap. Parked rows
are unchanged, with `Resume Driving` first either way. With the setting off the rows are exactly the
ones above.

`Resume driving after delivery progress` changes no row. When a `Picked Up` or `Delivered` resumes
driving under it, from the app, Siri or the card's own step control, the card is rebuilt at once and
is the driving card: `Resume Driving` goes and the next step is first again.

The setting is read **by the app** when it builds the card, and reaches the card as the order of its
controls; the extension reads no setting and holds no rule. Turning the switch in Settings updates a
running shift's card at once. No state offers more than four controls, which is two rows.

A delivery [reopened in the app](delivery-lifecycle.md#taking-back-a-delivery-marked-delivered-by-mistake)
is a delivery in progress, so the card's counts and its controls follow it like any other change: the
snapshot is derived from the store, never from what the card was last told.

Pausing and ending are both refused while a delivery is in progress, so neither is offered then.
Ending a **paused** shift is permitted, and closes the pause at the end instant rather than making a
driver resume work they did not do, so End stays on the card while paused. See
[Shift workflow](shift-workflow.md).

Where the controls do not fit on one line, at the larger text sizes, they wrap to further rows of two
rather than having their labels cut short. A button a driver has to guess at is how the wrong thing
gets recorded.

### Parked, and it is never the pause button

**Exactly one of the parked pair is on the card at a time**: `Park Vehicle` while the shift is
driving, `Resume Driving` while it is parked. Which one is read from the shift rather than chosen, so
the control shown is always the transition the store would accept, and the two are never together
because one of them would always be refused.

`Resume Driving` leads the card and carries the emphasis, which is the judgement the app's own panel
makes: leaving the state is the tap that matters, because forgetting to leave it costs the rest of
the shift's route. `Park Vehicle` carries the emphasis only where the pickup workflow puts it first;
otherwise a delivery step or `Start Delivery` comes before it and keeps the emphasis.

**Parking is not pausing, and the card must never let it read as one.** A parked shift keeps running,
its working clock keeps counting from the shift's own start and its deliveries stay open; what has
stopped is the route. The two controls sit on the same card and are told apart by their words and
their symbols: `Park vehicle` and `Resume driving` are what a listener hears, and neither ever says
*pause*.

The parked control is offered whatever the shift is carrying, including two orders open, because
whether the vehicle is moving is a fact about the driver and their vehicle rather than about any one
order. The ambiguity that withholds the step has nothing to bite on, and the rule that withholds
Pause and End is about time nobody worked rather than about a vehicle nobody moved. A **paused** shift
offers neither, because a paused shift is never parked. See
[Parked for a pickup](recorded-mileage.md#parked-for-a-pickup).

`Park Vehicle` and `Resume Driving` here run the same operations as the app's buttons and the spoken
actions, so with [Pick up orders with Park & Resume](settings.md#pick-up-orders-with-park-resume) on, Park also records `Arrived at Pickup`
and Resume Driving records `Picked Up` for the delivery Park chose, and for the others the driver
marked [Same pickup](delivery-lifecycle.md#same-pickup-and-same-drop-off) with it, including when the
app was closed in between. The card has no sentence to say it in and no Undo; the delivery's own row moving from
`To pickup` to `At pickup`, and then to `To customer`, is the report. No business rule runs in the
widget extension: the control asks the app to perform the action.

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

With two orders in the car there is no "the delivery". A "next step" button names no particular
order, and every way of choosing one (the newest, the oldest, the one furthest along) would write a
driver's tap into a record they did not mean. So the card offers no next step.

**Delivered is the exception, because it names its step.** Only a picked-up order can be delivered,
so when at least one is, the card offers `Delivered 3`: the lowest-numbered picked-up delivery, by the
same rule as [Mark Delivered](voice-actions.md#mark-delivered-names-its-step). The number is printed so
the driver sees which order the press records, and VoiceOver says `Mark delivery 3 delivered`. The
button carries that delivery's identifier: if the card is out of date when it is pressed, so that the
rule would now choose another delivery, nothing is recorded and the card is rebuilt. Pressing it again
offers the next one, and once one delivery is left the card shows that delivery's own step. It takes
the place a single delivery's step would take, so the card's height and the parked pair's lead are
unchanged: under the pickup workflow `Park Vehicle` still comes first, and while parked
`Resume Driving` does. One press records one delivery, Same drop-off or not.

With nothing picked up, the card offers no step at all and says so:

> Open DashPilot to record a step

VoiceOver hears the longer form, `Several deliveries are in progress. Open DashPilot to record a
step.` No single status is drawn either: a card that named one of two orders would be picking one on
the driver's behalf. The refusal lifts by itself once one of them has been delivered or cancelled.

**The timers stay**, and they stay for the same reason Start Delivery does. A step has to know which
order a tap belongs to, and with two open there is no answer; a clock says which delivery it is
counting, so there is nothing for it to be wrong about. This is the
same rule the spoken step follows, from the same place in the code. See
[Voice and system actions](voice-actions.md#the-rule-that-exists-only-off-screen).

**Start Delivery stays**, and the distinction is what the refusal turns on. A step has to know which
order it belongs to, and with two open there is no answer. Starting one has to know nothing about the
orders already running.

Two deliveries of **one offer** are two deliveries, so they withhold the next step exactly as two
offers do. The card counts deliveries and never offers: it says `2 deliveries in progress` whether they
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
  there. Its expanded presentation draws the same header, the orders as far as its smaller region has
  room, and the same controls in the same order, and no mileage line. Its compact and minimal
  presentations carry no control. Their glyph is the recording dot (red) while driving, the pause
  symbol (orange) while paused, and **the parking sign (blue) while parked**, read aloud as the parked
  sentence. That glyph is what a driver sees with another app in front, so a forgotten Resume Driving
  no longer looks like recording.
- **Nothing about the vehicle.** The card carries no vehicle name, no miles per gallon and no gas
  price. Parking is a statement about whether the vehicle is moving, and it needed none of them.

## If Live Activities are turned off

Nothing changes about what is recorded. The shift, its route, its deliveries and its pauses are
written exactly as they always were, and the app's own screen is unaffected. The card is a way to see
and control a shift, never a part of recording one.
