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
  Support/       Cross-cutting utilities (logging)
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

## Logging

`AppLog` defines the OSLog subsystem and categories. Logs record lifecycle, state transitions,
counts and errors. Coordinates, addresses and earnings amounts are never logged.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so views and view state are
main-actor isolated without annotation. Domain types (`Money`, `Shift`, `ShiftError`) and
infrastructure (`AppLog`, `ModelContainerFactory`) are explicitly `nonisolated`: they carry no UI
state, they are used from tests that are not main-actor bound, and background persistence work will
need them off the main actor.
