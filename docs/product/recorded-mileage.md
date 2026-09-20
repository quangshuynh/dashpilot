# Recorded mileage

DashPilot reports the distance it actually recorded. That is a different number from the distance
the driver actually drove, and the whole design of this feature is about keeping the two apart.

## What the figure means

A shift's mileage is measured from the positions retained during it. Positions recorded without an
interruption are joined and summed; wherever capture stopped, the distance across the break is left
out rather than bridged with a straight line.

So the figure is a **floor**. The driver drove at least this far. How much further is unknown, and
DashPilot does not estimate it.

!!! example "A synthetic shift"

    A three-hour shift where recording ran for the first hour, was interrupted for forty minutes,
    then ran again reports the distance of the first stretch plus the distance of the last one. The
    driving during the forty minutes is missing from the total, and the shift is labelled a partial
    route.

## When recording runs

Recording starts when a shift starts with DashPilot open, and **carries on** while the driver uses
the delivery app, follows a route in Maps, or locks the phone. That is what most of a shift looks
like, so it is the case the feature is built around.

Two halves of one rule make it work: recording can only be **started** with DashPilot open, and once
started it **continues** off screen. DashPilot asks for location while in use and nothing more.

## Why recording stops

- **The shift ends.** Recording stops with it.
- **Location permission is lost**, or Location Services is switched off for the device.
- **iOS suspends or ends the app.** It gives no guarantee of background execution, and DashPilot
  does nothing to be relaunched: no significant-location-change monitoring, no region monitoring.
  Recording resumes the next time the driver opens the app.
- **The driver force quits DashPilot**, which is the same case.
- **A shift was started by voice with DashPilot behind another app.** There was no recording to
  continue, and one cannot begin off screen, so that shift records nothing until the app is opened.

The running shift says which of these is happening at the time, so a driver is not left assuming
their route is being recorded when it is not, and the active line says plainly that recording is not
guaranteed.

## While the shift is still running

A running shift reports the same figure, in the same words, for the route recorded so far, with its
segment and gap counts beneath it. It is the finished shift's calculation applied to the positions
stored up to now, not a preview or an estimate, and it is subject to every rule on this page: it
grows only while positions are being accepted, it stops the moment the driver pauses, and resuming
never adds the distance covered during the break — that stretch was not recorded, so it is not
measured.

One difference, and it is a consequence of the shift being unfinished. A completed shift's route is
also checked against the shift's own start and end, so a route that begins long after the shift did
or stops long before it ended counts that as a gap. A running shift has no such window: its end is
still moving, and measuring against the moment the figure is read would count every red light as an
unrecorded stretch. Gaps *between* recorded positions are counted exactly as they are afterwards, so
a pause always shows as one and the shift reads as a partial route from then on.

The figure is read from the store every couple of seconds and extended with the positions recorded
since the last reading, rather than measured from the beginning each time. Nothing about it is saved:
when the shift ends, its mileage is measured from the stored route in one pass, as it always was.

## Gaps, segments and partial routes

The detail screen describes a route with three facts, all of them counts of what capture did rather
than claims about the drive:

| Term | Meaning |
| --- | --- |
| Recorded mileage | The distance summed inside continuous stretches of capture |
| Capture segments | How many unbroken stretches of capture contributed distance |
| Capture gaps | How many stretches of the shift the route does not account for |
| Partial route | The total is known to be less than the distance driven |

A gap count of zero reads as "No capture gaps detected". That is a statement about the detection,
not a promise that the whole shift was recorded.

There is **no coverage percentage**, and there will not be one until there is a denominator. The
denominator would have to be the distance actually driven, which is exactly the number DashPilot
does not have. A percentage over segments and gaps would be an invention.

A shift whose route was recorded before schema v3 carries no evidence of capture continuity. Its
continuity is inferred from timestamps, the detail screen says so, and such a route is always
reported as partial, because its short gaps cannot be seen at all.

## Correcting a shift's end re-measures it

Recorded mileage belongs to the shift that recorded it, so correcting a shift's end time to an
earlier moment removes the positions fixed after it and measures the distance again from what
remains. **It is never scaled by the time removed**: a shift that loses a quarter of its length
loses whichever positions were in that quarter, which may be all of its route or none of it. Nothing
is interpolated to the corrected end, so the stretch between the last retained position and the new
boundary is a capture gap like any other. Correcting an end **later** adds no position and no mile,
and the shift reports the stretch it did not record as a gap. See
[Correcting a shift's end time](shift-workflow.md#correcting-a-shifts-end-time).

## When there is nothing to report

A route with nothing measurable in it says so rather than showing `0.0 mi`, which a driver would
read as "you did not move" rather than "no distance could be measured". Two kinds of nothing are
distinguished: no usable position was recorded at all, or positions exist but no two of them were
captured continuously.

## What it is not

- **Not a tax or deduction figure.** DashPilot is not a tax tool, and a mileage deduction needs a
  complete log, which capture that iOS can interrupt cannot produce.
- **Not per-delivery mileage.** Deliveries are not recorded yet, so no distance is attributed to
  one.
- **Not calibrated.** The thresholds behind capture and measurement are defensible engineering
  choices for driving with a phone in a vehicle, not values tuned against recorded driving.
- **Not a live odometer.** The running figure advances in tenths of a mile as the store is read, and
  it is what was recorded rather than what was driven, exactly as the finished figure is.

The rules behind the numbers are documented under
[Route measurement](../architecture/route-measurement.md).
