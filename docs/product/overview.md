# Product overview

DashPilot is early. This page describes what exists and has been verified, not what is intended.
The [suggested order of later work](https://github.com/quangshuynh/dashpilot/blob/main/AGENTS.md)
lives in the repository rather than here, so this page cannot quietly become a roadmap.

## Implemented

**Shift lifecycle.** Start a shift, end the running shift, and at most one unfinished shift at a
time. The rule is enforced in `ShiftService` against the store rather than by disabling a button,
and a rejected or failed transition is reported to the driver instead of being swallowed. A shift
still running when the app was terminated is picked up on the next launch with its original start
time, because the store is the only place shift state lives.

**Location authorization.** Core Location's permission and accuracy states are modelled separately:
not determined, denied, restricted, When In Use, Always, plus the system-wide Location Services
switch and full versus reduced accuracy. The root screen shows the current state with the one
recovery that actually applies to it. Permission is requested only when the driver taps, and only
at the When In Use scope.

**Foreground route capture.** While a shift is running and DashPilot is open, accepted positions
are recorded against that shift and stored on device. Capture starts and stops with the shift,
resumes for a shift that was still running when the app was terminated, and stops when permission
is lost without ending the shift. The running shift shows whether capture is active, paused because
the app is in the background, or unavailable.

**Sample filtering.** One acceptance policy judges every candidate position: invalid coordinates,
invalid or poor accuracy, cached stale fixes, duplicate and out-of-order timestamps, movement too
small to be movement, and jumps too fast to be real. A rejected sample is dropped and capture
continues.

**Recorded mileage.** A completed shift's distance is derived from its retained route, summing only
what was captured continuously and excluding the distance across detected capture gaps. The figure
is recomputed from the stored route every time rather than saved as a second total.

**Manual gross earnings.** A completed shift can store one optional amount the driver types,
through a locale-aware input layer that reads what a decimal pad produces and refuses anything it
cannot read rather than reinterpreting it. Amounts are added, edited and removed from the shift's
detail screen, never during a running shift.

**Completed-shift metrics.** Gross earnings per elapsed shift hour and gross earnings per recorded
mile, both derived from what is already stored. A rate that cannot be derived is never shown as
zero.

**Completed-shift detail and deletion.** Tapping a shift in history opens a screen for that shift
alone: when it ran and for how long, what it paid, what its route recorded, and both rates with an
explanation for either one that is missing. A finished shift can be deleted from there behind a
confirmation that names what goes with it. Deleting a shift also deletes the route positions
recorded during it. A running shift cannot be deleted, and deletion is not undoable.

**Persistence.** Schema v4, with lightweight migrations from v1, v2 and v3, covered by tests that
open stores written under each older version. A store that fails to open is surfaced as a visible
state rather than a crash, and the failure screen deliberately offers no "reset the database"
action.

## Not implemented

Expenses, fuel, taxes, mileage deductions, a tips-versus-base breakdown, per-delivery earnings,
active-versus-idle time, delivery records, wait-time measurement, maps, route visualisation, weekly
or all-time totals, export, App Intents, Live Activities and recommendations.

Nothing is aggregated across shifts, no route is drawn on a map, and no mileage or live rate is
shown while a shift is still running. There is no undo for a deleted shift and no backup of any
kind.

## What the numbers are not

These four statements are the product, not a disclaimer appended to it. Each one is enforced in
the wording the app itself uses.

!!! warning "Earnings are what the driver typed"

    DashPilot is not connected to a delivery platform, holds no account credentials and imports
    nothing. The amount on a shift is one number a driver chose to associate with it. The app does
    not know whether it includes tips, bonuses, promotions, adjustments or reimbursements, so it is
    labelled gross earnings and never profit, take-home or a taxable amount. Entering an amount is
    optional, and a shift with none recorded is a different state from a shift recorded as paying
    `$0.00`.

!!! warning "Recorded mileage is what was recorded, not what was driven"

    Capture is foreground-only, so a shift's route has a gap whenever DashPilot was not open.
    Distance across a gap is left out rather than guessed at with a straight line, which means the
    figure is normally lower than the miles actually driven. A shift with known gaps is labelled a
    partial route. It is not a tax or deduction figure, no mileage is separated per delivery, and
    nothing here is calibrated against real driving yet.

!!! warning "The rates are gross, and each says what it divides by"

    The hourly figure is gross earnings over the shift's whole elapsed time, waiting and idling
    included, because DashPilot does not know how much of a shift was spent on a delivery. It is
    not an active or working hourly rate. The per-mile figure is gross earnings over *recorded*
    miles, which are normally fewer than the miles driven, so the rate is normally higher than
    earnings per mile driven. Neither subtracts expenses, fuel, wear or tax.

!!! warning "Route capture is foreground only"

    There is no background location mode, no Always authorization, no significant-location-change
    or region monitoring and no background task. When DashPilot is not in the foreground, capture
    stops and the route has a gap in it. iOS does not guarantee uninterrupted background execution,
    and the app does not claim it: the running shift says plainly when capture is paused.

## Boundaries the project will not cross

DashPilot must remain independent of unauthorized delivery-platform integration. The following are
out of scope by design, not merely unbuilt: credential collection, private API access, reverse
engineering, network interception, scraping, automatic offer acceptance or rejection, simulated
interaction with another delivery app, and anything intended to circumvent another platform's
restrictions. Delivery-platform information that cannot be obtained through legitimate public
mechanisms stays manual or absent.
