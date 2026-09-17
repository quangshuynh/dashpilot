# Product overview

DashPilot is early. This page describes what exists and has been verified, not what is intended.
The [suggested order of later work](https://github.com/quangshuynh/dashpilot/blob/main/AGENTS.md)
lives in the repository rather than here, so this page cannot quietly become a roadmap.

## Implemented

**Shift lifecycle.** Start a shift, pause it, resume it, end the running shift, and at most one
unfinished shift at a time. The rule is enforced in `ShiftService` against the store rather than by
disabling a button, and a rejected or failed transition is reported to the driver instead of being
swallowed. A shift still running when the app was terminated is picked up on the next launch with
its original start time, because the store is the only place shift state lives.

**Pause and resume.** A pause is a recorded row with its own timestamps, not something a screen
remembers, so a paused shift survives termination and is still the unfinished shift throughout. Time
the driver paused is excluded from the shift's **working duration**, which is what every hourly
figure divides by; route recording stops for the pause's whole length and resuming starts a new
recording, so no distance is measured across the break. Pausing is refused while a delivery is in
progress, and a delivery cannot be started while the shift is paused. Once the shift has ended, its
pauses can be corrected, deleted or added to from its own detail screen, within rules that refuse a
stretch reaching outside the shift, overlapping another pause or overlapping recorded delivery work,
and without touching the shift's own times, its route or any amount. See
[Shift workflow](shift-workflow.md#pausing-a-shift) and
[Correcting a recorded pause](shift-workflow.md#correcting-a-recorded-pause).

**Location authorization.** Core Location's permission and accuracy states are modelled separately:
not determined, denied, restricted, When In Use, Always, plus the system-wide Location Services
switch and full versus reduced accuracy. The root screen shows the current state with the one
recovery that actually applies to it. Permission is requested only when the driver taps, and only
at the When In Use scope.

**Route capture.** While a shift is running, accepted positions are recorded against that shift and
stored on device, and recording started with DashPilot open carries on while the driver is in
another app or the phone is locked. Capture starts and stops with the shift, resumes for a shift
that was still running when the app was terminated, and stops when permission is lost without ending
the shift. The running shift shows whether recording is active, stopped because the driver paused
the shift, paused because a recording could not be started off screen, or unavailable, and says that
recording is not guaranteed.

**Sample filtering.** One acceptance policy judges every candidate position: invalid coordinates,
invalid or poor accuracy, cached stale fixes, duplicate and out-of-order timestamps, movement too
small to be movement, and jumps too fast to be real. A rejected sample is dropped and capture
continues.

**Recorded mileage.** A shift's distance is derived from its retained route, summing only what was
captured continuously and excluding the distance across detected capture gaps. The figure is
recomputed from the stored route every time rather than saved as a second total.

**Live shift figures.** A running shift reports its working time, the mileage its route has recorded
so far, the segment and gap counts behind that figure, and how many deliveries are open and
finished. The mileage uses the finished shift's calculation and wording, grows only while positions
are accepted, stops while the shift is paused, and never includes the distance covered during a
break. It is extended a few positions at a time rather than remeasured, and nothing derived from it
is written to the store. No earnings and no rates appear on a running shift, because a shift's gross
earnings cannot be recorded until it has finished; the screen says that rather than showing a zero.
See [Shift workflow](shift-workflow.md#while-a-shift-runs).

**Delivery lifecycle.** A delivery belongs to one shift and moves through accepted, arrived at
pickup, picked up and delivered, or ends cancelled from any of those. Every event is recorded
because the driver tapped one large control; nothing is detected, imported or inferred. A delivery
belongs to exactly one shift, transitions must happen in order, and a shift cannot be ended while any
of its deliveries is still running. Several deliveries can be in progress at once, as they
are in stacked work: each advances independently, and every event is recorded against one named
delivery. Deliveries left in progress when the app was terminated are
picked up on the next launch at the step it had reached.

One accepted **offer** can hold more than one delivery, and the driver can say so when they record
it. Grouping never governs a lifecycle: each delivery in an offer advances on its own, and an offer
holds no money, no duration and no distance. A grouping recorded wrongly can be corrected afterwards,
on a running shift or from history, by moving a delivery between offers, splitting one out, combining
two offers or separating one. A correction moves membership only: no timestamp, pickup place, amount
or terminal state changes with it. See
[Delivery lifecycle](delivery-lifecycle.md).

**Voice and system actions.** Starting a shift, ending it, pausing and resuming it, starting a
delivery and recording that delivery's next event can be performed by voice, from Shortcuts or from
Spotlight, without the app coming to the screen. Each one calls the same service the on-screen control calls, so every rule that
refuses a tap refuses a sentence. A spoken delivery step is recorded only while exactly one delivery
is in progress; with more, DashPilot records nothing and says which screen can say it unambiguously.
No intent takes a dictated value, and nothing offers to cancel a delivery or record an amount. See
[Voice and system actions](voice-actions.md).

**The shift on the Lock Screen.** A running shift puts one Live Activity on the Lock Screen, and in
the Dynamic Island on the hardware that has one. It shows the working time, what the route has
recorded, how the deliveries stand and the controls that apply, and it carries no amount, no rate,
no place and no coordinate. Pressing a control runs the same service the app's own button runs, so a
shift paused from the Lock Screen is refused by the same rule. **Start Delivery** is offered on every
running shift, because it names no existing order and always means record one more; with two
deliveries open the card offers no step at all, because there is no "the delivery" to offer one for.
See
[The shift on the Lock Screen](live-activity.md).

**Pickup identity.** A delivery can optionally name the place it was collected from. The name is
typed by the driver — there is no geocoding, no place search and no address — and a name equivalent
to one already recorded reuses that place rather than creating a second, so a recurring pickup has
one stable identity. It is added or corrected from a small sheet, on a running shift or afterwards
from history, and the lifecycle never waits for one. See [Pickup identity](pickup-identity.md).

**Manual gross earnings.** A completed shift can store one optional amount the driver types,
through a locale-aware input layer that reads what a decimal pad produces and refuses anything it
cannot read rather than reinterpreting it. Amounts are added, edited and removed from the shift's
detail screen, never during a running shift.

**Manual per-delivery gross earnings.** A finished delivery can store one optional amount of its
own, through the same input layer and from the same completed-shift screen. It is an independent
fact: DashPilot never splits the shift's amount between deliveries, never adds one up from them, and
never treats a difference between the two as an error. A delivered delivery with an amount also
shows what it earned per recorded delivery hour: its effective earnings, platform pay and every
recorded tip together, over its own accepted-to-delivered interval. That figure is never summed
across deliveries, because stacked lifecycles overlap. See
[Earnings and metrics](earnings-and-metrics.md#per-delivery-gross-earnings).

**Completed-shift metrics.** Gross earnings per working shift hour, per active delivery hour and per
recorded mile, all derived from what is already stored, alongside the delivery active time and
non-delivery time the second of them divides by. A rate that cannot be derived is never shown as
zero.

**Completed-shift detail and deletion.** Tapping a shift in history opens a screen for that shift
alone: when it ran and for how long, how much of it a delivery was active for, the deliveries
recorded during it, where each was picked up from and what each paid if the driver said, what the
shift paid, what its route recorded, and all three rates with an explanation
for any that are missing. A finished shift can be
deleted from there behind a confirmation that names what goes with it. Deleting a shift also deletes
the route positions and the deliveries recorded during it. A running shift cannot be deleted, and
deletion is not undoable.

**Recorded expenses.** The driver can record what the work cost: an amount, a date and time, one of
five conservative categories (fuel, parking and tolls, maintenance, supplies, other) and an optional
short note. An expense belongs to a **date rather than to a shift**, so nothing attributes a
cost to work the driver did not attribute it to and nothing divides one across shifts, deliveries or
miles. A period summary reports what was recorded, its split by category, and *net after recorded
expenses*, which is one recorded subtotal less another and is never called profit. See
[Recorded expenses](expenses.md).

**Persistence.** Schema v8, with lightweight migrations from every earlier version, covered by tests
that open stores written under each older version. A store that fails to open is surfaced as a
visible state rather than a crash, and the failure screen deliberately offers no "reset the
database" action.

## Not implemented

Taxes and mileage deductions, estimated or recurring costs, receipts, a tips-versus-base breakdown,
per-delivery mileage, customer identity, merchant scoring, ranking or profitability, offer
profitability, automatic delivery or pickup detection, geocoding, maps, route visualisation,
quarterly, yearly or all-time totals, trends or comparisons across more than two periods, importing
an exported file, backup, sync, home-screen widgets and recommendations.

Deliveries are recorded, and three things are built on them. One is the shift time at least one
delivery was active, with overlapping deliveries counted once, and gross earnings over it. Another
is a pickup place's recorded waits, summarised as a median beside the number of pickups behind it —
see [Pickup wait](pickup-wait.md). The third is an optional amount the driver types against one
delivery, and the single hourly figure over that delivery's own lifecycle. Beyond that the app
derives a delivery duration for presentation and stops. There is no restaurant rating, no ranking,
no earnings grouped by place, no comparison between shifts and no prediction.

Shifts are aggregated over a day, a week, a calendar month or a chosen date range, and no further;
see [Period summaries](period-summaries.md). A period may be read beside the equivalent period
immediately before it, as two sets of records and the differences between them, with no judgement,
score or trend attached. A period, a shift or the whole history can be written to
a JSON or CSV file the driver shares themselves, see [History export](history-export.md). No route is drawn on a map, and no mileage or live rate is
shown while a shift is still running. There is no undo for a deleted shift and no backup of any
kind.

## What the numbers are not

These five statements are the product, not a disclaimer appended to it. Each one is enforced in
the wording the app itself uses.

!!! warning "Earnings are what the driver typed"

    DashPilot is not connected to a delivery platform, holds no account credentials and imports
    nothing. The amount on a shift is one number a driver chose to associate with it. The app does
    not know whether it includes tips, bonuses, promotions, adjustments or reimbursements, so it is
    labelled gross earnings and never profit, take-home or a taxable amount. Entering an amount is
    optional, and a shift with none recorded is a different state from a shift recorded as paying
    `$0.00`.

!!! warning "Recorded mileage is what was recorded, not what was driven"

    Recording carries on off screen, but iOS can still suspend or end the app, permission can be
    lost, and a shift started by voice records nothing until the app is opened. Distance across a
    gap is left out rather than guessed at with a straight line, which means the figure can be lower
    than the miles actually driven. A shift with known gaps is labelled a partial route. It is not a
    tax or deduction figure, no mileage is separated per delivery, and nothing here is calibrated
    against real driving yet.

!!! warning "The rates are gross, and each says what it divides by"

    The per-working-hour figure is gross earnings over the shift's working time, waiting
    included. The per-active-delivery-hour figure is gross earnings over the time a recorded delivery
    was open, with deliveries worked at once counted once — it is not a wage, and it says nothing
    about what the driver was doing in that time. The per-mile figure is gross earnings over
    *recorded* miles, which are normally fewer than the miles driven, so the rate is normally higher
    than earnings per mile driven. None of them subtracts expenses, fuel, wear or tax.

!!! warning "Deliveries are what the driver tapped"

    DashPilot cannot see another delivery application, so it cannot know that an order was offered,
    that a restaurant handed it over, or that a customer received it. Every delivery timestamp
    exists because the driver recorded it, which means a delivery they did not record is not in the
    app and a wait they recorded late reads as shorter than it was. An amount against a delivery is
    there only because the driver typed it for that delivery, and no restaurant, customer or address
    is stored at all.

!!! warning "Recording continues off screen, and is still not guaranteed"

    A recording started with DashPilot open carries on while the driver is in another app or the
    phone is locked. That is what When In Use authorization plus the location background mode
    permits, and it is all DashPilot asks for. It does not make recording continuous: iOS may
    suspend or end the app at any time and there is no significant-location-change or region
    monitoring to relaunch it, so a route can still have a gap in it. A recording can only be
    *started* with DashPilot open, so a shift begun by voice with the app off screen records nothing
    until it is opened. iOS does not guarantee uninterrupted background execution, and the app does
    not claim it.

## Boundaries the project will not cross

DashPilot must remain independent of unauthorized delivery-platform integration. The following are
out of scope by design, not merely unbuilt: credential collection, private API access, reverse
engineering, network interception, scraping, automatic offer acceptance or rejection, simulated
interaction with another delivery app, and anything intended to circumvent another platform's
restrictions. Delivery-platform information that cannot be obtained through legitimate public
mechanisms stays manual or absent.
