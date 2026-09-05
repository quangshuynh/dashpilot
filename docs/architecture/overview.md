# Architecture overview

DashPilot is a single-target SwiftUI app with no third-party runtime dependencies. The structure is
kept flat and explicit; layers are introduced when a concrete problem calls for one.

## Layers

| Layer | Rule |
| --- | --- |
| `Domain` | Framework-independent value types and calculations. No SwiftUI, no SwiftData, and Core Location only as a value the caller supplies |
| `Models` | SwiftData `@Model` types, which own the invariants of their own transitions |
| `Persistence` | The versioned schema, the migration plan and container construction |
| `Services` | Application services that own state transitions, plus thin adapters over platform frameworks |
| `App` | SwiftUI entry point, screens and preview fixtures |
| `Support` | Cross-cutting utilities: logging and launch arguments |

Domain types are deliberately free of SwiftUI and SwiftData so calculations can be tested without a
container or a rendered view. The file-by-file layout is under
[Project structure](../development/project-structure.md).

Only two files import Core Location: `CoreLocationAuthorizationProvider` and
`CoreLocationTrackingProvider`. Everything above them works in the app's own vocabulary, which is
what lets authorization states, capture states and sample filtering be exercised without a device.

## Shift lifecycle

`ShiftService` is the only place shifts start, end and are deleted. It holds one `ModelContext` and
nothing else: no cached shift, no "is a shift running" flag, no state that could disagree with the
store.

**At most one shift may be unfinished at a time.** The rule is enforced in the service by fetching
for a shift without an end timestamp before inserting a new one. A disabled button is presentation,
not protection, so the start control is absent while a shift runs *and* the service still refuses
the operation.

Because active state is derived, where "unfinished" means `endedAt == nil`, relaunch recovery needs
no recovery code. A shift left running when the app was killed is still the only unfinished row when
a new service reads the store, so the same record resumes with its original `startedAt`.

`Shift` owns its own transitions. `end(at:)` rejects ending a shift twice or ending it before it
started, and elapsed time clamps at zero so a backwards device clock cannot produce a negative
duration.

### Failure handling

- Starting while a shift runs, ending with none running, and deleting a shift that is still running
  all throw `ShiftLifecycleError` cases that the view turns into an alert. A rejected tap is never
  silently dropped.
- A failed `save()` is followed by `rollback()`, so an in-memory object never claims a state the
  store does not record.
- If the device clock has moved behind the recorded start, `endActiveShift(at:)` clamps the end to
  the start and logs it.
- Finding more than one unfinished shift is treated as a damaged store: the most recent is reported
  as active, the anomaly is logged as a fault, and starting another shift is still refused.

The root view reads both lists through `@Query` (unfinished shifts, completed shifts) and calls the
service to mutate, so SwiftData stays the single source of truth for what is displayed. Elapsed time
is rendered by a `TimelineView` that recomputes `Shift.elapsed(asOf:)` each second; no changing
duration is stored, and VoiceOver reads the value to the minute rather than announcing seconds.

## Delivery lifecycle

`DeliveryService` is the only place deliveries start, advance and finish. It is shaped exactly like
`ShiftService`: one `ModelContext`, no cached state, every rule checked against the store.

**At most one delivery is active at a time**, where active means `deliveredAt == nil &&
cancelledAt == nil`. The service resolves the active delivery itself rather than accepting one as a
parameter, which is what makes an out-of-order transition unrepresentable rather than merely
refused: there is no way to address a finished delivery, or a second active one, through the API.

`Delivery` owns its own transitions and refuses a skipped step, a repeated event, any transition
after a terminal state, and a timestamp earlier than the last recorded event. Its `state` is derived
from which timestamps exist, so nothing persisted can disagree with the events it summarises.

The two services meet at exactly one point: `endActiveShift(at:)` refuses to end a shift whose
`activeDelivery` is not `nil`. That is the whole coupling. `DeliveryService` does not know about
route capture, and `ShiftService` does not know how a delivery advances.

### Failure handling

- Starting a delivery outside a running shift, starting a second one, advancing when none is
  running, and every refused transition throw `DeliveryLifecycleError` cases the view turns into an
  alert.
- A failed `save()` is followed by `rollback()`, so an in-memory delivery never claims an event the
  store does not record.
- An event timestamped before the previous one is clamped forward and logged, the same rule
  `endActiveShift(at:)` applies to a backwards clock. A clamped event produces a zero-length
  interval, never a negative one.
- Finding more than one unfinished delivery is treated as a damaged store: the most recently
  accepted is reported as active, the anomaly is logged as a fault, and nothing is closed, cancelled
  or deleted to tidy it up. Starting another delivery and ending the shift both stay refused, which
  is visible rather than silent.

## Nothing derived is stored

Recorded mileage, both rates, a delivery's state, its two derived intervals and the wording that
qualifies all of them are computed on demand from the shift's timestamps, its recorded amount, its
retained route and its deliveries. A stored `hourlyRate`, a stored distance or a stored delivery
state would be a second answer to a question the store can already answer: it would keep the old
number after the calculation improved, and it would have to be rewritten every time the driver
edited an amount or recorded an event.

If measuring a long route ever proves too slow to do on demand, caching is a deliberate change to
make then, with a measurement behind it.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so views and view state are
main-actor isolated without annotation.

Domain types (`Money`, `MoneyInput`, `Shift`, `RouteSample`, `Delivery`, `DeliveryState`,
`DeliveryAction`, `DeliverySummary`, `LocationSample`, `RoutePoint`, `RouteSampleFilter`,
`RouteCaptureState`, `RouteDistance`, `RouteMileageCalculator`, `GeographicDistance`,
`ShiftMetrics`, `ShiftMetricsCalculator`, the error enums) and infrastructure
(`AppLog`, `ModelContainerFactory`, `LaunchArgument`) are explicitly `nonisolated`. They carry no UI
state, they are used from tests that are not main-actor bound, and background persistence work will
need them off the main actor.

`ShiftService` and `DeliveryService` are deliberately the opposite. Both are `@MainActor` because
they drive the main context the views observe, and that isolation is what serialises lifecycle
operations: each operation runs to completion without suspending, so two concurrent callers cannot
interleave the check with the insert that follows it. That is the whole concurrency story for a single-user on-device app, and no
locking is added beyond it. `LocationTrackingService` is main-actor isolated for the same reason,
which is what keeps a location callback from interleaving with a shift transition.

Core Location delivers delegate callbacks on the run loop its manager was created on. Both providers
create their manager on the main actor and use `MainActor.assumeIsolated` in the callback: a
documented guarantee rather than a proof, and the same assumption throughout the location layer.

## Failure is a state, not a crash

Container creation throws instead of trapping. `DashPilotApp` builds the container once at launch
and renders `PersistenceUnavailableView` on failure. That screen intentionally offers no "reset the
database" action: recorded shifts cannot be reconstructed from memory, so destroying them is not an
acceptable one-tap recovery.
