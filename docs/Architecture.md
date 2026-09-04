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

`ModelContainerFactory` builds every container from `DashPilotSchemaV1` and passes
`DashPilotMigrationPlan`, even though v1 has no migration stages yet. Wiring the plan up front means
adding v2 is an ordinary change rather than a store reset.

Container creation throws instead of trapping. `DashPilotApp` builds the container once at launch
and renders `PersistenceUnavailableView` on failure. The failure screen intentionally offers no
"reset the database" action: recorded shifts cannot be reconstructed from memory, so destroying them
is not an acceptable one-tap recovery.

Tests and previews use `makeInMemoryContainer()`, which shares the same schema and migration plan as
the shipping store, so a schema mistake fails in tests rather than only on device.

## Money

Delivery earnings are small amounts summed many times, which is exactly where binary floating point
drifts. `Money` wraps `Decimal`, stores amounts unrounded, and rounds only when a caller asks.
Division returns an optional because a zero divisor is a normal state for rate calculations — a
shift may have no elapsed time or no recorded distance — and the app must show "no rate" rather than
invent one.

## Shift model

`Shift` owns its own transitions. `end(at:)` rejects ending a shift twice or ending it before it
started, and elapsed time clamps at zero so a backwards device clock cannot produce a negative
duration. Later features (route samples, deliveries, earnings) attach to a shift rather than
replacing this shape.

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

DashPilot reads its permission to use location. It does not read location. No `CLLocation` is
requested, held or written anywhere in the app, and no background location capability is enabled.

Three layers, each with one job:

- `LocationAuthorization` (Domain) — the permission facts as plain values: whether system-wide
  Location Services is on, the app's own `LocationAuthorizationStatus`, and the granted
  `LocationAccuracyAuthorization`. Core Location is not imported here.
- `LocationAuthorizationProviding` (Services) — the seam. Four members: read the facts, be notified
  when they change, request When In Use permission, re-read. It is not a general Core Location
  wrapper; location updates, regions and accuracy escalation will get their own seams when a feature
  needs them, so this type does not grow into an object that owns permission, recording, mileage and
  analytics at once.
- `CoreLocationAuthorizationProvider` (Services) — the only file that imports Core Location. It owns
  the single `CLLocationManager`, maps `CLAuthorizationStatus` and `CLAccuracyAuthorization` onto the
  domain enums, and is the app's `CLLocationManagerDelegate`. The root view is deliberately not the
  delegate: delegate callbacks are an adapter concern, not a view's.

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

When In Use only. Requesting Always because background route capture may exist later would ask a
driver to grant more than the app can currently justify, and iOS does not re-prompt once a scope has
been chosen — so escalation is a deliberate later decision, made when background behaviour actually
exists. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` is set in the app target's build
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

## Logging

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

The `location` category records authorization transitions, Location Services availability changes,
accuracy changes and unrecognised platform values — what the app is allowed to do. Since the
authorization layer never reads a position, there is no coordinate available to it to leak.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so views and view state are
main-actor isolated without annotation. Domain types (`Money`, `Shift`, `ShiftError`,
`ShiftLifecycleError`) and infrastructure (`AppLog`, `ModelContainerFactory`, `LaunchArgument`) are
explicitly `nonisolated`: they carry no UI state, they are used from tests that are not main-actor
bound, and background persistence work will need them off the main actor. `ShiftService` is
deliberately the opposite — it is `@MainActor` because it drives the main context that the views
observe, and that isolation is what serialises lifecycle operations.

## Testing seams

`ModelContainerFactory.makeContainer(at:)` opens a store at an explicit URL. Tests use it to close a
store and reopen it, which is the only way to show that a running shift survives termination; an
in-memory store disappears with its container.

Debug builds accept `-dashpilot-in-memory-store` (`LaunchArgument.inMemoryStore`) so the UI journey
test starts from a known empty state and never writes into the store a real driver's history would
live in.

`StubLocationAuthorizationProvider` (debug builds only) satisfies `LocationAuthorizationProviding`
with caller-supplied state, so every authorization, accuracy and services combination — including
ones a simulator cannot easily be put into — is exercised without the real permission database or a
tapped system alert. It also counts permission requests, which is how "asks exactly once, and only
when the prompt can be shown" is verified. The UI test asserts only that the panel is on screen;
which state it displays depends on the device, and no test drives the system alert, because
automating it would be brittle and would change the permission state other tests run against.
