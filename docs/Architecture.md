# Architecture

DashPilot is a single-target SwiftUI app with no third-party runtime dependencies. The structure is
kept flat and explicit; layers are introduced when a concrete problem calls for one.

## Source layout

```
DashPilot/
  App/           SwiftUI entry point, root screen, shift detail, failure state, preview fixtures
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
| 3.0.0 | adds `RouteSample.captureSessionID`, an optional marker of capture continuity |
| 4.0.0 | adds `Shift.grossEarningsAmount`, an optional `Decimal` holding manually entered earnings |

`DashPilotSchemaV1`, `DashPilotSchemaV2` and `DashPilotSchemaV3` hold frozen copies of their models
rather than reusing the file-scope types, which have moved on. The plan then describes where a store is coming from as
truthfully as where it is going; the copies are never used at runtime outside migration.

**V1 → V2 is a lightweight stage.** The change is purely additive — a new entity and a new empty
relationship — and SwiftData can apply that without being told how. There is nothing to derive or
backfill either: a shift recorded before route capture existed genuinely has no route. A custom
stage would be code with nothing to do, and a `willMigrate`/`didMigrate` pair that walks every shift
for no reason is a way to lose data, not a way to protect it. It becomes a custom stage the first
time a version step actually has to transform something.

**V2 → V3 is a lightweight stage too.** One new optional attribute on an existing entity. Nothing is
backfilled, and that is the point: a capture session identifier states that two samples were recorded
without an interruption, and a v2 store holds no evidence of that either way. Grouping legacy samples
into invented sessions would produce exactly what the attribute exists to prevent — a gap presented
as a continuous stretch of driving. Migrated samples keep `nil`, and the mileage calculation treats
their continuity as inferred rather than proven.

**V3 → V4 is a lightweight stage as well.** One new optional attribute on `Shift`. Nothing is
backfilled, and the distinction is the whole point: a v3 store records no earnings at all, which is
not the same statement as "these shifts paid nothing". Writing `0` into every existing shift would
turn the absence of a figure into a claim about every shift a driver has ever recorded, and there
would be no way afterwards to tell a fabricated zero from one they typed. Migrated shifts keep
`nil`, and the interface offers to add an amount rather than showing one.

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

`Money.formatted(currencyCode:locale:)` is the only place a monetary string is built. No view
assembles one from a symbol and a number, and no view configures a formatter. It rounds to
`displayScale` there and only there, which is what keeps rounding a *display* decision: the store
holds what the driver typed, exactly.

The currency is one fixed code (`Money.displayCurrencyCode`, `"USD"`), not the device locale's.
Nothing in the app converts between currencies or records which currency an amount was earned in, so
reading the currency from the locale would relabel a US driver's earnings as euros the moment they
set their phone to another region. Locale still decides how the amount is *written* — symbol
placement, separators — it just does not decide what the money is.

### Reading what a driver types

`MoneyInput` is the locale-aware layer `Money(exact:)` deliberately is not: `Money(exact:)` reads one
canonical form for fixtures and stored values, while a driver types whatever their keyboard offers.

Nothing in it reinterprets input to make it work, which is the reason it exists at all.
`Decimal(string:)` stops at the first character it cannot read, so `"12abc"` would silently become
`12` and `"1.2.3"` would become `1.2`. Every candidate is therefore validated in full — a currency
symbol and surrounding whitespace removed, then digits, one decimal separator, and grouping
separators only in positions this locale actually writes them — before any number is built from it.
Internal whitespace is rewritten as the grouping separator rather than deleted, because several
locales group thousands with a space; deleting it would read `"125 50"` as twelve thousand.

The rejections are separate cases because each is a different sentence the interface has to say:
nothing entered, not a number, more precision than the currency has, negative, or beyond the bound.

- **More than two fraction digits is refused, not rounded.** Rounding at the point of entry would
  store a number the driver did not type. Rounding belongs to display.
- **Negative is refused.** Gross earnings are what a shift paid; a shift that cost money is an
  expense, and expenses are not recorded anywhere yet. Zero is allowed, and meaningful.
- **`MoneyInput.maximumAmount` (1,000,000) is a guard against pathological input** — a pasted page of
  digits, a stuck key — not a judgement about what a driver can earn. `Decimal` holds 38 significant
  digits, so without a bound a shift could store an amount no formatting in the app is meaningful
  for. It is checked in one place and documented so it can be raised if it is ever wrong.

## Shift earnings

A completed shift may hold one optional gross earnings amount: the figure the driver chose to
associate with it, and nothing more. DashPilot does not know whether it includes tips, bonuses,
promotions, adjustments or reimbursements, and nothing is imported from a delivery platform, so the
word throughout the code and the interface is *gross earnings* — never profit, take-home, net or
taxable income.

**Stored as a `Decimal`, not as a `Money` and not as a `Double`.** SwiftData persists a `Decimal` as
a decimal attribute, so the exact amount survives a round trip with no binary floating point in the
store and no second monetary type in the app. `Shift.grossEarningsAmount` is private; `grossEarnings`
and `setGrossEarnings(_:)` are the conversion, in one place, and the rest of the app only ever holds
a `Money`.

**`nil` and zero are different facts**, everywhere — in the model, in migration, in the row and in
the editor. `nil` means the driver has not recorded what the shift paid; `0` means they recorded that
it paid nothing. Nothing collapses one into the other, which is why removing an amount is its own
operation (`clearGrossEarnings()`) rather than an empty text field that ambiguously means both
"invalid" and "delete".

Two invariants live on the model rather than in a view, so no screen, test or later caller can set an
amount the app would refuse to display: earnings can be recorded only on a **completed** shift, and
never **negative**. `ShiftService` adds the store write and the same rollback rule the lifecycle
transitions use, so an amount can never be showing in the interface while the store holds something
else.

### What is shown, and when

Earnings appear on completed shifts in history only. A running shift offers nothing to type into —
typing is a task for a parked car, and the model refuses it as well, because a screen that is merely
never presented is not a rule. The history row shows the amount and one button, `Add Earnings` or
`Edit Earnings`; a sheet holds the field, Cancel and Save.

Editing is a **draft**. The typed text is view state and the store is written once, on Save or
Remove — nothing is written per keystroke, and Cancel leaves the recorded amount exactly as it was.
A refused amount keeps the sheet open with what was typed and says which rule it broke, rather than
discarding the driver's work.

The rates derived from the amount are a separate line in a smaller style, so the figure the driver
recorded is never confused with the ones DashPilot worked out — see
[Completed shift metrics](#completed-shift-metrics).

Logging follows the project's rule: `AppLog.earnings` records that an amount was added, updated or
removed, or that a save failed. The amount never reaches a logger.

## Shift model

`Shift` owns its own transitions. `end(at:)` rejects ending a shift twice or ending it before it
started, and elapsed time clamps at zero so a backwards device clock cannot produce a negative
duration. Later features (deliveries, earnings) attach to a shift rather than replacing this shape.

`RouteSample` is the first thing to attach. It stores a timestamp, a latitude, a longitude, a
horizontal accuracy and the capture session it was recorded in, and nothing else: `CLLocation` also
reports speed, course, altitude and their accuracies, but nothing implemented reads them, and a
coordinate history is sensitive enough that each field needs a reason rather than an availability.

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
tracking paused, permission required, or unavailable. No map, no coordinates, no sample count, and
no live distance — a running shift's route is still being recorded, and a figure changing under the
driver as they drive is not what the number is for. It is shown because the alternative is worse: a
driver who assumes their route is being recorded, while permission is off or the app spent the shift
in the background, loses the shift's data and only finds out afterwards. What the route measured
appears once the shift is finished, in history — see [Recorded mileage](#recorded-mileage).

### Concurrency

Core Location delivers delegate callbacks on the run loop the manager was created on, and both
providers create their manager on the main actor, so both use `MainActor.assumeIsolated` in the
callback. It is a documented guarantee rather than a proof, and it is the same assumption the
authorization layer already makes.

Everything downstream is `@MainActor` and synchronous. A candidate is judged and written in one
uninterrupted run, so it cannot arrive part-way through starting or ending a shift, and the
active-shift invariant needs no locking to hold at the boundaries.

## Recorded mileage

DashPilot derives a shift's distance from its retained route. Nothing is stored: `Shift.recordedDistance()`
measures the samples every time it is asked, so a fix to the calculation improves every historical
shift and the store never holds two answers to the same question. If measuring a long route ever
proves too slow to do on demand, caching is a deliberate change to make then.

### Never measure across a gap

**A gap in capture is never counted as driven distance.** A position, an interruption, then another
position is not a straight line somebody drove; it is two pieces of route with an unknown amount of
driving between them. Foreground-only capture means those interruptions are the normal case, so this
is the rule the whole calculation is built around.

`RouteMileageCalculator` splits a route into continuous segments, sums the distance between adjacent
positions *within* each segment, and reports what it left out. Two positions are continuous when
both hold:

1. **They share a capture session.** `LocationTrackingService` mints a `captureSessionID` whenever
   updates start and clears it whenever they stop, so a change of identifier is direct evidence that
   capture was interrupted — backgrounding, a lost permission, a failed save, a new process. This is
   the fact timestamps cannot supply: twenty seconds in another app and twenty seconds at a red
   light look identical in a list of timestamps.
2. **They are no more than `maximumSampleInterval` apart.** The identifier proves the app kept
   recording, not that positions kept arriving. Two minutes is the initial value: while a vehicle is
   moving, accepted positions arrive seconds apart, so ordinary driving is never fragmented, and a
   longer silence means either a stationary vehicle — where the straight line omitted is a few
   metres — or positions that stopped arriving, where a straight line cannot be trusted. It is an
   engineering choice, not a calibration, and it is a property so it can be tuned once there is
   recorded driving to tune it against.

Positions stored before v3 carry no session. Continuity between two of them is inferred from their
timestamps, `RouteDistance.usesInferredContinuity` says so, and such a route is always reported as
partial: its gaps cannot be seen.

When the shift's own window is known — every completed shift — a route that starts long after the
shift did, or stops long before it ended, counts as a gap as well. Without that check a shift whose
capture stopped an hour before it finished would look completely recorded.

### What the result says

`RouteDistance` exists so the answer is not an unexplained `Double`: distance in metres, how many
segments contributed, how many gaps were excluded, how many positions were usable, and whether any
continuity was inferred. From those, `isMeasured` (any distance measured at all) and `isPartial`
(the total is known to be less than the distance driven) are what the interface reads.

Distance is held in metres and converted once, in `RouteDistance.measurement` and
`formattedMiles(locale:)`. No view holds a conversion constant. One decimal place is what the
measurement supports: positions carry error radii of up to 100 m and the gaps are unmeasured.

### Separation from capture

The calculator does not re-judge sample quality. Accuracy, staleness, implausible speed and
negligible movement are `RouteSampleFilter`'s rules, applied once when a sample is captured;
repeating them here would be two policies to keep in agreement. It rejects only positions that could
not describe anywhere on Earth, because stored data should not be assumed to stay perfect forever.
It sorts, breaks ties on coordinates and collapses positions sharing a timestamp, so an imperfect
stored route produces a deterministic number rather than one that depends on fetch order.

Both layers measure two positions the same way, through `GeographicDistance` — one haversine
implementation on a spherical Earth. `CLLocation.distance(from:)` would be marginally more precise
but would put Core Location inside the domain layer, where calculations are deliberately
framework-free and testable without a device; the difference is far smaller than the error already
in the positions.

Idle time is deliberately not inferred from the route. The capture filter drops movement under five
metres, so a parked vehicle records nothing, and a stretch of route with no positions is not
evidence of anything. Idle measurement gets its own data when it gets its own feature.

### What is displayed

A completed shift's row reads `12.4 mi recorded`, with `· partial route` when gaps are known, and
its detail screen adds the segment and gap counts behind that figure. A
route with nothing measurable in it says so instead of showing `0.0 mi`, which a driver would read
as "you did not move" rather than "no distance could be measured". Nothing says total, complete,
tax or deductible mileage: capture is foreground-only, the number is what was recorded, and the app
is not a tax tool. Active shifts show no mileage — a live figure would need a recomputing dashboard
to be worth anything, and the useful moment is when the shift is done.

## Completed shift metrics

A completed shift is read as two rates. Both are **gross**, both are **derived**, and both say in
their own wording what they divide by.

| Metric | Definition | Shown as |
| --- | --- | --- |
| Gross earnings per shift hour | the recorded amount ÷ the shift's elapsed wall-clock hours (`startedAt` to `endedAt`) | `$28.75/hr` |
| Gross earnings per recorded mile | the recorded amount ÷ the miles the shift's retained route measured | `$19.30 / recorded mi` |

**The hourly rate divides by elapsed time, not by working time.** The denominator is the whole shift
— waiting at a restaurant, idling between offers, a break — because that is the only duration
DashPilot knows. It is never called an active, working or delivery hourly rate: the app does not
record when a delivery started or ended, and naming the figure as though it did would claim a
capability that does not exist.

**The per-mile rate divides by recorded mileage.** Capture is foreground-only and distance across a
gap is excluded rather than guessed, so the denominator is normally lower than the miles actually
driven — which makes the rate normally *higher* than earnings per mile driven. The word `recorded`
is in the visible text, not only in this document, and it is spelled out in full for VoiceOver.
Neither figure is a tax, deduction, profit or net number; no expense, fuel cost or tax is subtracted
anywhere in the app.

### Nothing is persisted

There is **no schema change in this work**, and the current version is still v4. A stored
`hourlyRate` or `earningsPerMile` would be a second answer to a question the store can already
answer: it would keep the old number after the calculation improved, and it would have to be
recomputed and rewritten every time a driver edited an amount. `ShiftMetrics` is built on demand
from the shift's own timestamps, its recorded amount and its measured route, exactly like
`RouteDistance` is.

### Explicit unavailable states

`ShiftRate` is `.available(Money)` or `.unavailable(ShiftRateUnavailability)`. A `Money?` would
carry the value and lose the reason, and the reasons are the point of the type:

| Reason | The fact it states |
| --- | --- |
| `shiftNotCompleted` | the shift is still running; finalised rates describe finished shifts |
| `earningsNotRecorded` | no amount has been entered. **Not** an amount of zero |
| `noElapsedTime` | the shift covers no measurable time, including one clamped to zero by a backwards device clock |
| `noRouteRecorded` | the shift retained no usable position at all |
| `routeNotMeasurable` | positions exist, but no two of them were recorded continuously |
| `zeroRecordedDistance` | a distance *was* measured, and it was zero |

The precedence is `shiftNotCompleted` → `earningsNotRecorded` → the denominator's own reason: a
missing numerator is the same absence for both rates, so it is reported once rather than described
twice in the vocabulary of two different denominators.

Two distinctions carry the whole design. **Missing earnings never become zero** — a shift nobody has
entered an amount for produces no rate, while a shift recorded as paying nothing produces a real
`$0.00/hr` and `$0.00 / recorded mi`. **An unmeasurable route never becomes zero miles** — `0.0` in
the denominator is not a small number, it is an absent one, so a shift with no route shows no
per-mile rate rather than a rate divided by nothing.

### Precision

Money stays exact. The numerator is the `Decimal` the driver typed, division goes through
`Money.divided(by:scale:)`, and no monetary value passes through binary floating point.

The **denominators are the boundary**, and it is deliberate. A duration is a `TimeInterval` and a
distance is a `Double` of metres; both are binary before this calculation ever sees them and neither
can be made exact afterwards. Each therefore crosses into `Decimal` exactly once, in
`ShiftMetricsCalculator.decimal(_:scale:)`, rounded to a scale far finer than the result is read at —
a duration to the millisecond, a distance to a millionth of a mile (under two millimetres, against
positions carrying error radii of up to 100 m). `Decimal(_: Double)` is deliberately not used:
scaling to an integer and dividing by a power of ten is an explicit rule stated in one place rather
than a platform's conversion behaviour.

The quotient keeps six fraction digits — four more than the two it is displayed at — so that the
value the display rounds is effectively the exact quotient rather than one already rounded at an
adjacent scale. Rounding to cents happens where every other rounding in the app happens, in
`Money.formatted`.

Miles come from `RouteDistance.miles`, which is the same conversion `formattedMiles(locale:)` uses.
No metres-to-miles constant exists anywhere else, so the rate and the distance beside it cannot
disagree about what a mile is.

### What is displayed

The history row is a compact summary and a single navigation target:

```
Sat, Aug 23                              $86.25
5:46 PM – 8:46 PM · 3 hr
4.5 mi recorded · partial route · $28.75/hr
```

Three lines, no controls. The row carries the one rate that answers "how did this shift go"; the
per-recorded-mile rate needs its denominator explained to be read correctly, and that explanation
belongs on the screen the row opens. Only available figures appear — an unavailable rate leaves
nothing behind, no dash and no `$0.00` — and active shifts show no rates at all, because a live
earnings rate is a different feature with different honesty problems.

At accessibility text sizes the date and the amount stack rather than share a line, and the summary
wraps rather than truncating: the first thing a truncation takes is the end of "recorded", which is
the word that makes the mileage honest.

Both rates, with the reasons behind an absent one, are on [the detail screen](#completed-shift-detail).

### Accessibility

The row is one combined element with an explicit label, so a VoiceOver user hears the shift as a
shift rather than three fragments — and hears sentences rather than the separators and abbreviations
that read well and hear badly:

> Saturday, August 23, 2025. 5:46 PM to 8:46 PM. 3 hr. $86.25 gross earnings recorded. 4.5 miles
> recorded. Partial route: DashPilot was not recording for part of this shift, so more miles were
> driven than were recorded. $28.75 gross earnings per shift hour.

Partiality is a two-word marker beside the figure it qualifies and a full claim when spoken, because
the marker is legible next to the mileage and unintelligible on its own. It is never conveyed by
colour.

## Completed shift detail

Tapping a completed history row pushes `CompletedShiftDetailView` — a standard `NavigationStack`
with a typed `navigationDestination(for: Shift.self)`, and no navigation infrastructure of its own.
Only completed shifts have one; a running shift has no finalised duration, no earnings it may
record and nothing that may be deleted.

The row answers *what shift is this and roughly how did it perform*. The detail screen answers the
two questions the row has no room for: **what exactly happened in this shift**, and **how
trustworthy are these numbers**. It is a summary, not a dashboard: no chart, no map, no gauge, no
score.

| Section | What it holds |
| --- | --- |
| Shift | start time, end time, elapsed duration |
| Earnings | the recorded amount or "No amount recorded", and Add/Edit Earnings |
| Route | recorded mileage, capture segments, capture gaps, and what qualifies them |
| Performance | both derived rates, or the reason each could not be derived |
| — | Delete Shift |

### Route quality

`RouteQuality` holds the vocabulary for a measured route, next to `RouteDistance`, which holds the
measurement. Wording is the part that is easy to get wrong here — a foreground-only capture is a
*floor* on the distance driven, and almost every natural phrase for it claims more — so the phrasing
is one tested type rather than strings spread across two views that can drift apart.

Only what the stored data supports is shown: recorded mileage, how many unbroken stretches of
capture contributed distance, how many stretches of the shift the route does not account for,
whether the route is partial, and whether its continuity was inferred rather than recorded (a route
stored before schema v3, whose short gaps cannot be detected at all). No coordinates, no sample
list, no accuracy diagnostics.

**There is no coverage percentage**, and there will not be one until there is a denominator. The
denominator would have to be the distance actually driven, which is exactly the number DashPilot
does not have. Segments and gaps are counts of what capture did, so they are facts; a percentage
over them would be an invention. For the same reason a gap count of zero reads as "No capture gaps
detected" — a statement about the detection, not a claim that the whole shift was recorded.

An unmeasurable route reports no counts rather than counts of zero, and says which kind of nothing
it is: no usable position was recorded at all, or positions exist but no two of them were captured
continuously.

### Explaining a rate that does not exist

The row shows nothing for an absent rate. The detail screen shows the reason, because a driver who
wonders why there is no per-mile figure should be told — and `ShiftRateUnavailability` already
carries which reason it is. The value reads "Not available" with a sentence under it; nothing is
ever filled in with a zero, and the sentence for a missing amount asks for one ("Add what this shift
paid to see this rate") rather than implying the shift paid nothing.

### Earnings

The same `ShiftEarningsEditor` sheet the history row used to present, moved rather than duplicated:
one parser, one draft, one Cancel semantics, one place that writes. Remove Earnings stays inside the
editor, where it is next to the amount it removes.

### Deletion

`ShiftService.deleteCompletedShift(_:)` owns it, beside the lifecycle transitions, because the rule
it has to keep is a lifecycle rule: **a running shift cannot be deleted.** Deleting one would leave
capture recording against a shift the store no longer holds and would take the driver's current work
with it. The check is made against the model, so a wrong navigation state cannot destroy a running
shift; hiding the button is not the protection.

The shift's route samples go with it through the relationship's existing `.cascade` delete rule
rather than a loop in the service — the same rule that has been in place since v2, now covered by
tests that assert the deleted shift's positions are gone, another shift's positions and recorded
amount are untouched, and a refused delete changes nothing at all. A failed save rolls back, so the
interface cannot show a history the store no longer holds, or hold one it no longer shows.

**No schema change.** The store is still v4: deletion needed a correct delete rule, and the schema
already had one.

Deletion is confirmed in an alert — not a confirmation dialog, which is presented as a popover in
some layouts where iOS drops the explicit Cancel button — and the confirmation names what it
destroys, including the count of route positions, because that is the part a driver is least likely
to have in mind and cannot re-enter by hand. There is no undo, no trash and no archive; adding one
would be a feature with its own retention and privacy questions, not a detail of this screen.

The screen stops reading the shift the moment the store accepts the delete. SwiftUI may rebuild a
destination while the stack pops, and reading a property of a deleted model is not a thing to
discover on a driver's device.

### Accessibility

Each metric is one combined element with an explicit label, so a rate is heard as a claim
("$19.30 gross earnings per recorded mile") rather than as a heading and a number, and an absent one
as "No gross earnings per recorded mile" followed by the reason. Route partiality and gap counts are
plain language in the label, never an icon or a colour. The delete confirmation is a standard
destructive alert with both choices labelled.

## Logging

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

The `location` category records authorization transitions, Location Services availability changes,
accuracy changes and unrecognised platform values — what the app is allowed to do. Since the
authorization layer never reads a position, there is no coordinate available to it to leak.

Derived metrics are not logged either, for the same reasons: an hourly rate is an earnings figure
and a per-mile rate is an earnings figure over a trip metric, and neither has a failure to report —
an unavailable rate is a normal result, shown to the driver.

Mileage is not logged at all. The calculation reads coordinates and produces a trip metric, and
neither belongs in a log: there is no failure it can report — an unmeasurable route is a normal
result, shown to the driver — so a log line would only record how far somebody drove.

The `shift` category records the lifecycle: a shift started, a shift ended, a transition refused,
a store read or write that failed — and now that a completed shift was deleted with its route
samples, that a deletion was refused because the shift was still running, or that the delete could
not be written. It records nothing about the shift itself: not when it ran, not what it earned, not
how far it went. A deletion is the last moment to start writing a driver's history into a log.

The `earnings` category records that an amount was added, updated or removed, and that a save
failed. It never records the amount. There is no diagnostic value in the figure — every failure it
can report is about the store or the rule that refused the entry, not about the number — and what a
driver earns is exactly the kind of value this project keeps out of the logs. The word naming the
operation is a `StaticString` chosen in code, so it cannot accidentally become the value.

The `route-capture` category does read positions, so its rule is explicit: it logs when capture
starts and stops, why it could not start, how many samples were retained, how many were persisted,
and the *name of the rule* that rejected a candidate — `RouteSampleRejection`'s raw value, never the
candidate. No latitude, longitude, address or route geometry is ever passed to a logger, and a test
asserts that every rejection reason is a plain rule name.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so views and view state are
main-actor isolated without annotation. Domain types (`Money`, `Shift`, `RouteSample`,
`LocationSample`, `RoutePoint`, `RouteSampleFilter`, `RouteCaptureState`, `RouteDistance`,
`RouteMileageCalculator`, `GeographicDistance`, `MoneyInput`, `ShiftMetrics`,
`ShiftMetricsCalculator`, the error enums) and infrastructure
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

They also accept `-dashpilot-seeded-history` (`LaunchArgument.seededHistory`), which opens an
in-memory store already holding the synthetic history the previews use: one completed shift with an
amount and a route recorded in two capture sessions, and one with neither. A UI test cannot make a
simulator record a route, so a measured, partial route — and the per-recorded-mile rate over it —
would otherwise be unreachable end to end. The fixture is invented amounts and offsets from a
round-number origin, the same data `SyntheticRoute` builds for the unit tests.

`StubLocationTrackingProvider` (debug builds only) replaces Core Location's position updates and
nothing else. The capture pipeline has to be verifiable — that a good sample is retained, that a
duplicate, a stale fix, a wild jump or a sample from outside the shift window is not, and that
nothing at all is kept once a shift has ended — and none of that can be demonstrated against a
simulator location feed, which delivers whatever it likes when it likes. `LocationTrackingService`
also takes its clock and its save batch size, so staleness and batching are decided by the test
rather than by how long the test took to run. The capture tests use it to drive two kilometres of
route through a sixty second backgrounding — shorter than the mileage gap threshold, so only the
recorded break in capture can exclude it — and assert the distance is not counted. Every coordinate in the tests and previews comes from
`SyntheticRoute`: a round-number origin and explicit offsets, not a place anyone has driven.

`StubLocationAuthorizationProvider` (debug builds only) satisfies `LocationAuthorizationProviding`
with caller-supplied state, so every authorization, accuracy and services combination — including
ones a simulator cannot easily be put into — is exercised without the real permission database or a
tapped system alert. It also counts permission requests, which is how "asks exactly once, and only
when the prompt can be shown" is verified. The UI test asserts only that the panel is on screen;
which state it displays depends on the device, and no test drives the system alert, because
automating it would be brittle and would change the permission state other tests run against.

`MoneyInput` takes its `Locale`, and the editor passes the environment's, so every parsing and
formatting test states the locale it is asserting about instead of inheriting whichever region the
machine running the suite happens to be set to. The suites cover a period locale and a comma locale
side by side, which is how "a separator this locale never writes is refused rather than
reinterpreted" is proven rather than assumed.
