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
  Services/      Application services that own state transitions
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

## Logging

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

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
