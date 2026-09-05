# Architecture

DashPilot is a single-target SwiftUI app with no third-party runtime dependencies. The structure is
kept flat and explicit; layers are introduced when a concrete problem calls for one.

## Source layout

```
DashPilot/
  App/           SwiftUI entry point, root screen, failure state, preview fixtures
  Domain/        Framework-independent value types and calculations
  Models/        SwiftData @Model types
  Persistence/   Versioned schema, migration plan, container construction
  Services/      Application services that own state transitions and platform adapters
  Support/       Cross-cutting utilities (logging, launch arguments)
DashPilotTests/  Swift Testing suites
DashPilotUITests/ XCUITest journeys
```

Domain types are deliberately free of SwiftUI and SwiftData so calculations can be tested without a
container or a rendered view.

## Persistence

`ModelContainerFactory` builds every container from the current schema and passes
`DashPilotMigrationPlan`. Wiring the plan up front from v1 meant adding v2 was an ordinary change
rather than a store reset.

Container creation throws instead of trapping. `DashPilotApp` builds the container once at launch
and renders `PersistenceUnavailableView` on failure. The failure screen intentionally offers no
"reset the database" action: recorded shifts cannot be reconstructed from memory, so destroying them
is not an acceptable one-tap recovery.

Tests and previews use `makeInMemoryContainer()`, which shares the same schema and migration plan as
the shipping store, so a schema mistake fails in tests rather than only on device.

### Schema versions

| Version | Shape |
| --- | --- |
| 1.0.0 | `Shift` only: id, start, optional end |
| 2.0.0 | adds `RouteSample`, and a `Shift.routeSamples` relationship |

`DashPilotSchemaV1` holds a frozen copy of the v1 `Shift` rather than reusing the file-scope type,
which has moved on. The plan then describes where a store is coming from as truthfully as where it
is going; the copy is never used at runtime outside migration.

**V1 → V2 is a lightweight stage.** The change is purely additive — a new entity and a new empty
relationship — and SwiftData can apply that without being told how. There is nothing to derive or
backfill either: a shift recorded before route capture existed genuinely has no route. A custom
stage would be code with nothing to do, and a `willMigrate`/`didMigrate` pair that walks every shift
for no reason is a way to lose data, not a way to protect it. It becomes a custom stage the first
time a version step actually has to transform something.

`ModelContainerFactory.makeContainer(versionedSchema:at:)` is a test seam that opens a store under a
historical version without the plan, so a test can write a store shaped the way an older build would
have left it and then open it normally. That is how "a v1 store keeps its shifts" is proven rather
than assumed.

## Money

Delivery earnings are small amounts summed many times, which is exactly where binary floating point
drifts. `Money` wraps `Decimal`, stores amounts unrounded, and rounds only when a caller asks.
Division returns an optional because a zero divisor is a normal state for rate calculations — a
shift may have no elapsed time or no recorded distance — and the app must show "no rate" rather than
invent one.

## Shift model

`Shift` owns its own transitions. `end(at:)` rejects ending a shift twice or ending it before it
started, and elapsed time clamps at zero so a backwards device clock cannot produce a negative
duration. Later features (deliveries, earnings) attach to a shift rather than replacing this shape.

`RouteSample` is the first thing to attach. It stores a timestamp, a latitude, a longitude and a
horizontal accuracy, and nothing else: `CLLocation` also reports speed, course, altitude and their
accuracies, but nothing implemented reads them, and a coordinate history is sensitive enough that
each field needs a reason rather than an availability.

The relationship's delete rule is `.cascade`. A shift's route describes that shift and nothing else,
so deleting the shift takes the samples with it; the orphans would otherwise be exactly the
sensitive rows the app promises to keep accountable to a shift.

## Shift lifecycle

`ShiftService` is the only place shifts start and end. It holds one `ModelContext` and nothing else:
no cached shift, no "is a shift running" flag, no state that could disagree with the store.

**At most one shift may be unfinished at a time.** The rule is enforced in the service, by fetching
for a shift without an end timestamp before inserting a new one. A disabled button is presentation,
not protection, so the UI's start control is simply absent while a shift runs *and* the service
still refuses the operation.

Because active state is derived — "unfinished" means `endedAt == nil` — relaunch recovery needs no
recovery code. A shift left running when the app was killed is still the only unfinished row when a
new service reads the store, so the same record resumes with its original `startedAt`. Nothing
synthesises a replacement shift.

The service is `@MainActor` isolated. Each operation runs to completion without suspending, so two
concurrent callers cannot interleave the check with the insert that follows it; that is the whole
concurrency story for a single-user on-device app, and no locking is added beyond it. Tests race
eight callers at `startShift` and assert one shift exists afterwards.

Failure handling:

- Starting while a shift runs, or ending with none running, throw `ShiftLifecycleError` cases the
  root view turns into an alert. A rejected tap is never silently dropped.
- A failed `save()` is followed by `rollback()`, so an in-memory shift never claims to be started or
  ended when the store does not record it.
- If the device clock has moved behind the recorded start, `endActiveShift(at:)` clamps the end to
  the start and logs it. Recording a zero length shift is preferable to leaving a driver unable to
  end their shift until the clock catches up.
- Finding more than one unfinished shift is treated as a damaged store: the most recent is reported
  as active, the anomaly is logged as a fault, and starting another shift is still refused.

The root view reads both lists through `@Query` (unfinished shifts, completed shifts) and calls the
service to mutate, so SwiftData stays the single source of truth for what is displayed. Elapsed time
is rendered by a `TimelineView` that recomputes `Shift.elapsed(asOf:)` each second; no changing
duration is stored, and VoiceOver reads the value to the minute rather than announcing seconds.

## Location authorization

This layer answers one question: what is DashPilot allowed to do with location? It never reads a
position — that is the tracking layer's job, described under [Route capture](#route-capture) — and no
background location capability is enabled anywhere in the app.

Three layers, each with one job:

- `LocationAuthorization` (Domain) — the permission facts as plain values: whether system-wide
  Location Services is on, the app's own `LocationAuthorizationStatus`, and the granted
  `LocationAccuracyAuthorization`. Core Location is not imported here.
- `LocationAuthorizationProviding` (Services) — the seam. Four members: read the facts, be notified
  when they change, request When In Use permission, re-read. It is not a general Core Location
  wrapper; location updates, regions and accuracy escalation will get their own seams when a feature
  needs them, so this type does not grow into an object that owns permission, recording, mileage and
  analytics at once.
- `CoreLocationAuthorizationProvider` (Services) — one of only two files that import Core Location
  (the other is `CoreLocationTrackingProvider`). It owns a `CLLocationManager` used solely to read
  authorization and request permission, maps `CLAuthorizationStatus` and `CLAccuracyAuthorization`
  onto the domain enums, and is its own `CLLocationManagerDelegate`. The root view is deliberately
  not the delegate: delegate callbacks are an adapter concern, not a view's.

`LocationAuthorizationService` is the `@Observable` type SwiftUI reads. It holds the current
`LocationAuthorization`, applies provider changes, logs transitions and gates the permission request.
`DashPilotApp` owns one instance and puts it in the environment, so one location manager exists per
process.

### Authorization and accuracy are separate

A driver can grant permission and still withhold precise location. Collapsing the two into one enum
would hide a state that is authorized but not accurate enough to measure distance, so
`LocationAuthorizationStatus` and `LocationAccuracyAuthorization` are independent. `grantedAccuracy`
returns `nil` unless a grant is held, because Core Location reports full accuracy by default before
the user has been asked and surfacing that would claim precision the app does not have.

Both enums carry an `unrecognised(rawValue:)` case. A future platform value maps there rather than
being forced into a known case, and `grantsAccess` is false for it, so a value this app has never
seen can never be read as permission.

### Condition precedence

`LocationAuthorization.condition` reduces the three facts to the one thing the interface should
explain, in this order:

1. **Restricted** outranks everything. Enabling Location Services or opening Settings will not give
   the app permission, so offering either would be a false promise.
2. **Location Services off** outranks the app's own grant. An authorized app still cannot read
   location while the system switch is off, and that has to be said plainly.
3. Otherwise the app's own authorization decides.

`recovery` follows from the condition, and only ever offers an action that works: request the prompt
when not determined; open the app's Settings page when denied (that page holds the app's location
toggle); describe where Location Services lives when it is off, with no deep link, because iOS
exposes a URL for an app's own settings page and not for the system-wide switch; nothing at all when
restricted, unrecognised, or already authorized.

### Permission strategy

When In Use only, and route capture is foreground-only precisely so that stays honest. Requesting
Always because background route capture may exist later would ask a driver to grant more than the app
can justify, and iOS does not re-prompt once a scope has been chosen — so escalation is a deliberate
later decision, made when background behaviour actually exists. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` is set in the app target's build
settings (the project generates its Info.plist); no Always string and no temporary-accuracy purpose
key are declared, because neither is requested.

The prompt is never triggered at launch. iOS shows it once, and a prompt that appears before the
driver has any reason to grant it is the surest way to have it declined permanently, so the request
is always a tap. `requestAuthorization()` additionally refuses unless the status is not determined:
re-requesting after a denial does nothing visible, and a button that appears to do nothing reads as
a broken app.

### Staying current

Core Location reports authorization and accuracy through
`locationManagerDidChangeAuthorization(_:)`, which also fires once when the delegate is set. It
reports nothing about the system-wide switch, so `CLLocationManager.locationServicesEnabled()` is
polled — at init, on each authorization callback, and when the app returns to the foreground
(`RootView` watches `scenePhase`). That call blocks, so it runs off the main actor and the result is
published back; until the first result arrives the app assumes the switch is on, rather than
flashing "Location Services off" at every launch.

## Route capture

DashPilot records a shift's route while it is in the foreground. Three types, each with one job, and
the authorization layer above is not one of them:

- `RouteSampleFilter` (Domain) — the acceptance policy. A pure value holding thresholds; the caller
  supplies the shift window and the last accepted sample. No Core Location, no store, no state.
- `LocationTrackingProviding` / `CoreLocationTrackingProvider` (Services) — the seam that produces
  candidate positions. Start, stop, a stream of `LocationSample`s and a failure channel. It makes no
  judgement and writes nothing.
- `LocationTrackingService` (Services) — decides when capture runs, applies the policy, and writes
  what survives.

`LocationTrackingProviding` is deliberately separate from `LocationAuthorizationProviding`.
Authorization answers "may the app read location"; tracking answers "here is a position". Merging
them produces one type that owns permission, updates, filtering and everything added afterwards.
The tracking service *consults* `LocationAuthorizationService` and never restates it:
`RouteCaptureUnavailableReason.init(_:)` translates that layer's conclusion into capture vocabulary,
so permission is still interpreted in exactly one place.

### The invariant

**A retained sample always belongs to exactly one running shift.**

SwiftData is the only authority on whether a shift is running. The service keeps no "a shift is
active" flag; it holds the store's own `Shift` object, over the same main context `ShiftService`
uses, and reads `endedAt` from it for every candidate. A shift that has ended, or been deleted,
stops capture instead of being written to, and the filter independently rejects every candidate for
a shift with an end timestamp.

`synchronize()` is the only way capture starts or stops. It derives what should be happening from
the store rather than from what happened last, which makes it idempotent and safe to call from
anywhere — a missed call costs a delay, never a wrong state. It runs when a shift starts or ends,
when the app becomes active, when permission changes, and once when the root view appears. That last
one is how a shift still running when the app was terminated resumes capture, with no replacement
shift and no recovery code, for the same reason relaunch recovery falls out of the lifecycle.

Ordering at the end of a shift is deliberate: `RootView` calls `prepareForShiftEnd()` — which stops
updates and writes pending samples — *before* recording the end, so there is no window in which a
candidate is judged against a shift the store has already closed. It then calls `synchronize()`
whether the end succeeded or not, so a failed end restarts capture rather than latching it off.
Everything is `@MainActor` and runs to completion without suspending, so a delegate callback cannot
interleave with a lifecycle transition in the first place; the ordering closes the window that
remains between the two operations, and the tests assert the invariant holds even without it.

Losing location never ends a shift. Shift lifecycle and tracking availability are separate concerns:
capture goes to `.unavailable(...)`, the shift keeps running, and the driver decides when it ends.

### Foreground only

There is no background location mode, no Always authorization, no significant-location-change or
region monitoring, and no background task. `allowsBackgroundLocationUpdates` is never set and the
generated Info.plist declares no `UIBackgroundModes`.

When the app leaves the foreground, `enterBackground()` stops updates and flushes — so the pause is
the app's own decision, with its samples written, rather than a side effect of iOS suspending the
process — and the state becomes `.pausedInBackground`. `.inactive` is deliberately *not* treated as
leaving: the app switcher, a call banner and the notification shade would otherwise chop the route
into fragments for interruptions the driver never left the app for. `enterForeground()` reconciles,
resuming capture if the shift is still running and location is still usable.

The route therefore has a gap whenever DashPilot is not in front. iOS guarantees no background
execution, the app claims none, and the running shift says plainly when capture is paused.
Background continuity is a later decision, made when there is behaviour that justifies asking a
driver for Always.

### The acceptance policy

Core Location hands back whatever the hardware produced: cached fixes from minutes ago, positions
with a kilometre of uncertainty, repeated identical callbacks while parked, and occasional jumps to
somewhere the vehicle cannot have reached. Every rule that judges them lives in `RouteSampleFilter`,
in this order — a sample is described by the first rule it breaks, so the reported reason is
deterministic:

| Rule | Rejects |
| --- | --- |
| `invalidCoordinate` | non-finite or out-of-range latitude/longitude, and `(0, 0)` |
| `invalidAccuracy` | negative or non-finite horizontal accuracy, which is how Core Location reports an invalid fix |
| `poorAccuracy` | horizontal accuracy worse than 100 m |
| `shiftEnded` | anything at all, once the shift has an end timestamp |
| `beforeShiftStart` | a fix taken before the shift started |
| `stale` | a fix more than 30 s old when it is judged |
| `duplicateTimestamp` / `outOfOrder` | a timestamp equal to or earlier than the last accepted sample |
| `negligibleMovement` | less than 5 m from the last accepted sample |
| `implausibleSpeed` | separation the error radii cannot explain, faster than 62 m/s |

The thresholds are an initial, defensible choice for delivery driving on a phone in a vehicle, not a
calibration: 100 m keeps an urban-canyon fix and drops an approximate-authorization fix reported in
kilometres; 5 m is under a second of travel at any driving speed, so no real movement is lost while a
stationary phone's wander is; 62 m/s is about 139 mph, far above any delivery driving, so the rule
only fires on a genuinely broken position rather than on fast driving. They are stored as properties
precisely so they can be tuned once there is recorded data to tune them against.

Two details keep the rules from misfiring. The speed check subtracts both fixes' error radii from
the distance before dividing, so two uncertain positions 60 m apart with 50 m accuracy each are
noise rather than a jump; and it floors the interval at one second, so fixes arriving a fraction of a
second apart do not turn ordinary noise into an enormous apparent speed. Reduced accuracy is *not*
rejected as a category — samples are judged by the accuracy actually reported, so an approximate fix
precise enough to be useful is kept.

A rejection is only ever a rejection. It never stops capture, so one bad fix cannot cost a driver
the rest of the route.

### Writing samples

Accepted samples are inserted immediately and saved in batches of ten. Saving on every callback
would mean a store write roughly once a second for the length of a shift; building a batching
subsystem without measurement would be solving a problem nobody has demonstrated. Ten is the
smallest step that removes the per-callback write, and every deliberate stop — backgrounding, ending
a shift, losing permission — flushes first, so the exposure is a few seconds of route to an abrupt
kill and nothing more.

A failed save rolls back, as in the shift lifecycle: memory must not claim what the store does not
hold. The last accepted sample is cleared with it, because the row it referred to no longer exists,
and the next candidate is then judged as the first of the route — which is what it is. Capture stops
and the state says the store is unavailable, rather than continuing to collect samples that cannot
be kept.

When capture is (re)pointed at a shift, the newest already-stored sample is read back with a
one-row fetch, so capture resumed after a relaunch, a backgrounding or a permission interruption
still judges candidates against the route as it stands instead of accepting a duplicate or a jump.
Walking `shift.routeSamples` to find it would load an entire shift's route to look at one row.

### What is shown

`RouteCaptureStatusView` is one line inside the running shift's panel: tracking active, foreground
tracking paused, permission required, or unavailable. No map, no distance, no coordinates, no sample
count — nothing implemented can be shown as a measurement yet, and a screen implying otherwise would
claim a capability the app does not have. It is shown because the alternative is worse: a driver who
assumes their route is being recorded, while permission is off or the app spent the shift in the
background, loses the shift's data and only finds out afterwards.

### Concurrency

Core Location delivers delegate callbacks on the run loop the manager was created on, and both
providers create their manager on the main actor, so both use `MainActor.assumeIsolated` in the
callback. It is a documented guarantee rather than a proof, and it is the same assumption the
authorization layer already makes.

Everything downstream is `@MainActor` and synchronous. A candidate is judged and written in one
uninterrupted run, so it cannot arrive part-way through starting or ending a shift, and the
active-shift invariant needs no locking to hold at the boundaries.

## Logging

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

The `location` category records authorization transitions, Location Services availability changes,
accuracy changes and unrecognised platform values — what the app is allowed to do. Since the
authorization layer never reads a position, there is no coordinate available to it to leak.

The `route-capture` category does read positions, so its rule is explicit: it logs when capture
starts and stops, why it could not start, how many samples were retained, how many were persisted,
and the *name of the rule* that rejected a candidate — `RouteSampleRejection`'s raw value, never the
candidate. No latitude, longitude, address or route geometry is ever passed to a logger, and a test
asserts that every rejection reason is a plain rule name.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so views and view state are
main-actor isolated without annotation. Domain types (`Money`, `Shift`, `RouteSample`,
`LocationSample`, `RouteSampleFilter`, `RouteCaptureState`, the error enums) and infrastructure
(`AppLog`, `ModelContainerFactory`, `LaunchArgument`) are
explicitly `nonisolated`: they carry no UI state, they are used from tests that are not main-actor
bound, and background persistence work will need them off the main actor. `ShiftService` is
deliberately the opposite — it is `@MainActor` because it drives the main context that the views
observe, and that isolation is what serialises lifecycle operations. `LocationTrackingService` is
main-actor isolated for the same reason, and that is what keeps a location callback from interleaving
with a shift transition.

## Testing seams

`ModelContainerFactory.makeContainer(at:)` opens a store at an explicit URL. Tests use it to close a
store and reopen it, which is the only way to show that a running shift survives termination; an
in-memory store disappears with its container.

Debug builds accept `-dashpilot-in-memory-store` (`LaunchArgument.inMemoryStore`) so the UI journey
test starts from a known empty state and never writes into the store a real driver's history would
live in.

`StubLocationTrackingProvider` (debug builds only) replaces Core Location's position updates and
nothing else. The capture pipeline has to be verifiable — that a good sample is retained, that a
duplicate, a stale fix, a wild jump or a sample from outside the shift window is not, and that
nothing at all is kept once a shift has ended — and none of that can be demonstrated against a
simulator location feed, which delivers whatever it likes when it likes. `LocationTrackingService`
also takes its clock and its save batch size, so staleness and batching are decided by the test
rather than by how long the test took to run. Every coordinate in the tests and previews comes from
`SyntheticRoute`: a round-number origin and explicit offsets, not a place anyone has driven.

`StubLocationAuthorizationProvider` (debug builds only) satisfies `LocationAuthorizationProviding`
with caller-supplied state, so every authorization, accuracy and services combination — including
ones a simulator cannot easily be put into — is exercised without the real permission database or a
tapped system alert. It also counts permission requests, which is how "asks exactly once, and only
when the prompt can be shown" is verified. The UI test asserts only that the panel is on screen;
which state it displays depends on the device, and no test drives the system alert, because
automating it would be brittle and would change the permission state other tests run against.
