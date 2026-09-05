# Route measurement

DashPilot derives a shift's distance from its retained route. Nothing is stored:
`Shift.recordedDistance()` measures the samples every time it is asked, so a fix to the calculation
improves every historical shift and the store never holds two answers to the same question.

## Never measure across a gap

!!! abstract "A gap in capture is never counted as driven distance."

A position, an interruption, then another position is not a straight line somebody drove. It is two
pieces of route with an unknown amount of driving between them. Foreground-only capture means those
interruptions are the normal case, so this is the rule the whole calculation is built around.

`RouteMileageCalculator` splits a route into continuous segments, sums the distance between adjacent
positions *within* each segment, and reports what it left out. Two positions are continuous when
both of the following hold.

**They share a capture session.** `LocationTrackingService` mints a `captureSessionID` whenever
updates start and clears it whenever they stop, so a change of identifier is direct evidence that
capture was interrupted: backgrounding, a lost permission, a failed save, a new process. This is the
fact timestamps cannot supply, because twenty seconds in another app and twenty seconds at a red
light look identical in a list of timestamps.

**They are no more than `maximumSampleInterval` apart.** The identifier proves the app kept
recording, not that positions kept arriving. Two minutes is the initial value: while a vehicle is
moving, accepted positions arrive seconds apart, so ordinary driving is never fragmented, and a
longer silence means either a stationary vehicle, where the straight line omitted is a few metres,
or positions that stopped arriving, where a straight line cannot be trusted. It is an engineering
choice, not a calibration, and it is a property so it can be tuned once there is recorded driving to
tune it against.

Positions stored before v3 carry no session. Continuity between two of them is inferred from their
timestamps, `RouteDistance.usesInferredContinuity` says so, and such a route is always reported as
partial, because its gaps cannot be seen.

When the shift's own window is known, which is true of every completed shift, a route that starts
long after the shift did, or stops long before it ended, counts as a gap as well. Without that check
a shift whose capture stopped an hour before it finished would look completely recorded.

## What the result says

`RouteDistance` exists so the answer is not an unexplained `Double`. It carries the distance in
metres, how many segments contributed, how many gaps were excluded, how many positions were usable,
and whether any continuity was inferred. From those, `isMeasured` (any distance measured at all) and
`isPartial` (the total is known to be less than the distance driven) are what the interface reads.

Distance is held in metres and converted once, in `RouteDistance.measurement` and
`formattedMiles(locale:)`. No view holds a conversion constant. One decimal place is what the
measurement supports: positions carry error radii of up to 100 m and the gaps are unmeasured.

## Separation from capture

The calculator does not re-judge sample quality. Accuracy, staleness, implausible speed and
negligible movement are `RouteSampleFilter`'s rules, applied once when a sample is captured;
repeating them here would be two policies to keep in agreement. It rejects only positions that could
not describe anywhere on Earth, because stored data should not be assumed to stay perfect forever.

It sorts, breaks ties on coordinates and collapses positions sharing a timestamp, so an imperfect
stored route produces a deterministic number rather than one that depends on fetch order.

Both layers measure two positions the same way, through `GeographicDistance`, one haversine
implementation on a spherical Earth. `CLLocation.distance(from:)` would be marginally more precise
but would put Core Location inside the domain layer, where calculations are deliberately
framework-free and testable without a device. The difference is far smaller than the error already
in the positions.

Idle time is deliberately not inferred from the route. The capture filter drops movement under five
metres, so a parked vehicle records nothing, and a stretch of route with no positions is not
evidence of anything. Idle measurement gets its own data when it gets its own feature.

## The wording is a tested type

`RouteQuality` holds the vocabulary for a measured route, next to `RouteDistance`, which holds the
measurement. Wording is the part that is easy to get wrong here, because a foreground-only capture
is a floor on the distance driven and almost every natural phrase for it claims more. The phrasing
is therefore one tested type rather than strings spread across two views that can drift apart.

Only what the stored data supports is stated: recorded mileage, how many unbroken stretches of
capture contributed distance, how many stretches of the shift the route does not account for,
whether the route is partial, and whether its continuity was inferred rather than recorded. No
coordinates, no sample list, no accuracy diagnostics.

**There is no coverage percentage**, and there will not be one until there is a denominator. The
denominator would have to be the distance actually driven, which is exactly the number DashPilot
does not have. Segments and gaps are counts of what capture did, so they are facts; a percentage
over them would be an invention. For the same reason a gap count of zero reads as "No capture gaps
detected", a statement about the detection rather than a claim that the whole shift was recorded.

An unmeasurable route reports no counts rather than counts of zero, and says which kind of nothing
it is: no usable position was recorded at all, or positions exist but no two of them were captured
continuously.

A route with nothing measurable in it is never shown as `0.0 mi`, which a driver would read as "you
did not move" rather than "no distance could be measured".

## What is displayed

A completed shift's row reads `12.4 mi recorded`, with `· partial route` when gaps are known, and
its detail screen adds the segment and gap counts behind that figure, plus the sentences that
qualify them. Nothing says total, complete, tax or deductible mileage.

Active shifts show no mileage. A live figure would need a recomputing dashboard to be worth
anything, and the useful moment is when the shift is done.

## Accessibility

Partiality is a two-word marker beside the figure it qualifies and a full claim when spoken, because
the marker is legible next to the mileage and unintelligible on its own. It is never conveyed by
colour or by an icon. VoiceOver hears miles spelled out in full, and the detail screen uses the bare
spoken mileage because it reads the caveats separately, which otherwise spoke the partial sentence
twice.
