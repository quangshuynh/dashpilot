# Location

Two concerns, kept apart on purpose. Authorization answers "may the app read location". Tracking
answers "here is a position". Merging them produces one type that owns permission, updates,
filtering and everything added afterwards.

## Authorization

Three layers, each with one job:

- **`LocationAuthorization` (Domain)** holds the permission facts as plain values: whether
  system-wide Location Services is on, the app's own `LocationAuthorizationStatus`, and the granted
  `LocationAccuracyAuthorization`. Core Location is not imported here.
- **`LocationAuthorizationProviding` (Services)** is the seam. Four members: read the facts, be
  notified when they change, request When In Use permission, re-read. It is not a general Core
  Location wrapper. Location updates, regions and accuracy escalation get their own seams when a
  feature needs them, so this type does not grow into an object that owns permission, recording,
  mileage and analytics at once.
- **`CoreLocationAuthorizationProvider` (Services)** owns a `CLLocationManager` used solely to read
  authorization and request permission, maps `CLAuthorizationStatus` and `CLAccuracyAuthorization`
  onto the domain enums, and is its own `CLLocationManagerDelegate`. The root view is deliberately
  not the delegate: delegate callbacks are an adapter concern, not a view's.

`LocationAuthorizationService` is the `@Observable` type SwiftUI reads. It holds the current
`LocationAuthorization`, applies provider changes, logs transitions and gates the permission
request. `DashPilotApp` owns one instance and puts it in the environment, so one location manager
exists per process.

### Authorization and accuracy are separate

A driver can grant permission and still withhold precise location. Collapsing the two into one enum
would hide a state that is authorized but not accurate enough to measure distance, so
`LocationAuthorizationStatus` and `LocationAccuracyAuthorization` are independent.

`grantedAccuracy` returns `nil` unless a grant is held, because Core Location reports full accuracy
by default before the user has been asked, and surfacing that would claim precision the app does not
have.

Both enums carry an `unrecognised(rawValue:)` case. A future platform value maps there rather than
being forced into a known case, and `grantsAccess` is false for it, so a value this app has never
seen can never be read as permission.

### Condition precedence

`LocationAuthorization.condition` reduces the three facts to the one thing the interface should
explain, in this order:

1. **Restricted outranks everything.** Enabling Location Services or opening Settings will not give
   the app permission, so offering either would be a false promise.
2. **Location Services off outranks the app's own grant.** An authorized app still cannot read
   location while the system switch is off, and that has to be said plainly.
3. Otherwise the app's own authorization decides.

`recovery` follows from the condition, and only ever offers an action that works: request the prompt
when not determined; open the app's Settings page when denied, since that page holds the app's
location toggle; describe where Location Services lives when it is off, with no deep link, because
iOS exposes a URL for an app's own settings page and not for the system-wide switch; nothing at all
when restricted, unrecognised, or already authorized.

### Permission strategy

**When In Use only**, and route capture is foreground-only precisely so that stays honest.
Requesting Always because background route capture may exist later would ask a driver to grant more
than the app can justify, and iOS does not re-prompt once a scope has been chosen, so escalation is
a deliberate later decision made when background behaviour actually exists.

`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` is set in the app target's build settings, since
the project generates its Info.plist. No Always string and no temporary-accuracy purpose key are
declared, because neither is requested.

The prompt is never triggered at launch. `requestAuthorization()` additionally refuses unless the
status is not determined: re-requesting after a denial does nothing visible, and a button that
appears to do nothing reads as a broken app.

### Staying current

Core Location reports authorization and accuracy through
`locationManagerDidChangeAuthorization(_:)`, which also fires once when the delegate is set. It
reports nothing about the system-wide switch, so `CLLocationManager.locationServicesEnabled()` is
polled: at init, on each authorization callback, and when the app returns to the foreground, which
`RootView` detects through `scenePhase`. That call blocks, so it runs off the main actor and the
result is published back. Until the first result arrives the app assumes the switch is on, rather
than flashing "Location Services off" at every launch.

## Route capture

Three types, each with one job, and the authorization layer is not one of them:

- **`RouteSampleFilter` (Domain)** is the acceptance policy. A pure value holding thresholds; the
  caller supplies the shift window and the last accepted sample. No Core Location, no store, no
  state.
- **`LocationTrackingProviding` and `CoreLocationTrackingProvider` (Services)** are the seam that
  produces candidate positions: start, stop, a stream of `LocationSample`s and a failure channel.
  They make no judgement and write nothing.
- **`LocationTrackingService` (Services)** decides when capture runs, applies the policy, and writes
  what survives.

The tracking service *consults* `LocationAuthorizationService` and never restates it:
`RouteCaptureUnavailableReason.init(_:)` translates that layer's conclusion into capture vocabulary,
so permission is interpreted in exactly one place.

### The invariant

!!! abstract "A retained sample always belongs to exactly one running shift."

SwiftData is the only authority on whether a shift is running. The service keeps no "a shift is
active" flag; it holds the store's own `Shift` object, over the same main context `ShiftService`
uses, and reads `endedAt` from it for every candidate. A shift that has ended, or been deleted,
stops capture instead of being written to, and the filter independently rejects every candidate for
a shift with an end timestamp.

`synchronize()` is the only way capture starts or stops. It derives what should be happening from
the store rather than from what happened last, which makes it idempotent and safe to call from
anywhere: a missed call costs a delay, never a wrong state. It runs when a shift starts or ends,
when the app becomes active, when permission changes, and once when the root view appears. That last
one is how a shift still running when the app was terminated resumes capture, with no replacement
shift and no recovery code.

Ordering at the end of a shift is deliberate. `RootView` calls `prepareForShiftEnd()`, which stops
updates and writes pending samples, *before* recording the end, so there is no window in which a
candidate is judged against a shift the store has already closed. It then calls `synchronize()`
whether the end succeeded or not, so a failed end restarts capture rather than latching it off.

Losing location never ends a shift. Shift lifecycle and tracking availability are separate concerns:
capture goes to `.unavailable(...)`, the shift keeps running, and the driver decides when it ends.

### Foreground only

There is no background location mode, no Always authorization, no significant-location-change or
region monitoring, and no background task. `allowsBackgroundLocationUpdates` is never set and the
generated Info.plist declares no `UIBackgroundModes`.

When the app leaves the foreground, `enterBackground()` stops updates and flushes, so the pause is
the app's own decision with its samples written rather than a side effect of iOS suspending the
process, and the state becomes `.pausedInBackground`. `.inactive` is deliberately **not** treated as
leaving: the app switcher, a call banner and the notification shade would otherwise chop the route
into fragments for interruptions the driver never left the app for. `enterForeground()` reconciles,
resuming capture if the shift is still running and location is still usable.

The route therefore has a gap whenever DashPilot is not in front. iOS guarantees no background
execution, the app claims none, and the running shift says plainly when capture is paused.

The one pause the app does **not** accept is the system's own. `CLLocationManager` pauses updates by
default once iOS decides a device has stopped moving, which on a delivery shift is a driver waiting
at a pickup, and it does not resume them by itself. With no background location mode there is
nothing for the system to wake, so the rest of the shift would go unrecorded while the screen still
said tracking. `CoreLocationTrackingProvider.configure(_:)` therefore sets
`pausesLocationUpdatesAutomatically` to `false`, alongside best accuracy, the automotive activity
type and no distance filter. Capture is still stopped deliberately whenever the app leaves the
foreground, so nothing keeps the hardware running behind the driver's back.

### The acceptance policy

Core Location hands back whatever the hardware produced: cached fixes from minutes ago, positions
with a kilometre of uncertainty, repeated identical callbacks while parked, and occasional jumps to
somewhere the vehicle cannot have reached. Every rule that judges them lives in `RouteSampleFilter`,
in this order. A sample is described by the first rule it breaks, so the reported reason is
deterministic.

| Rule | Rejects |
| --- | --- |
| `invalidCoordinate` | Non-finite or out-of-range latitude or longitude, and `(0, 0)` |
| `invalidAccuracy` | Negative or non-finite horizontal accuracy, which is how Core Location reports an invalid fix |
| `poorAccuracy` | Horizontal accuracy worse than 100 m |
| `shiftEnded` | Anything at all, once the shift has an end timestamp |
| `beforeShiftStart` | A fix taken before the shift started |
| `stale` | A fix more than 30 s old when it is judged |
| `duplicateTimestamp` and `outOfOrder` | A timestamp equal to or earlier than the last accepted sample |
| `negligibleMovement` | Less than 5 m from the last accepted sample |
| `implausibleSpeed` | Separation the error radii cannot explain, faster than 62 m/s |

The thresholds are an initial, defensible choice for delivery driving on a phone in a vehicle, not a
calibration. 100 m keeps an urban-canyon fix and drops an approximate-authorization fix reported in
kilometres; 5 m is under a second of travel at any driving speed, so no real movement is lost while
a stationary phone's wander is; 62 m/s is about 139 mph, far above any delivery driving, so the rule
only fires on a genuinely broken position rather than on fast driving. They are stored as properties
precisely so they can be tuned once there is recorded data to tune them against.

Two details keep the rules from misfiring. The speed check subtracts both fixes' error radii from
the distance before dividing, so two uncertain positions 60 m apart with 50 m accuracy each are
noise rather than a jump; and it floors the interval at one second, so fixes arriving a fraction of
a second apart do not turn ordinary noise into an enormous apparent speed.

Reduced accuracy is **not** rejected as a category. Samples are judged by the accuracy actually
reported, so an approximate fix precise enough to be useful is kept.

A rejection is only ever a rejection. It never stops capture, so one bad fix cannot cost a driver
the rest of the route.

### What the driver sees

`RouteCaptureStatusView` is one line inside the running shift's panel: tracking active, foreground
tracking paused, permission required, or unavailable. No map, no coordinates, no sample count, and
no live distance.

It is shown because the alternative is worse. A driver who assumes their route is being recorded,
while permission is off or the app spent the shift in the background, loses the shift's data and
only finds out afterwards.

What the route measured appears once the shift is finished. See
[Route measurement](route-measurement.md).
