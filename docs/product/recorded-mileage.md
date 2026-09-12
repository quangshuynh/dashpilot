# Recorded mileage

DashPilot reports the distance it actually recorded. That is a different number from the distance
the driver actually drove, and the whole design of this feature is about keeping the two apart.

## What the figure means

A completed shift's mileage is measured from the positions retained during it. Positions recorded
without an interruption are joined and summed; wherever capture stopped, the distance across the
break is left out rather than bridged with a straight line.

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
- **Not shown live.** Mileage appears when a shift is finished.

The rules behind the numbers are documented under
[Route measurement](../architecture/route-measurement.md).
