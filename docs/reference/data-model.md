# Data model

Two persisted entities, and a small set of value types derived from them. Current schema version:
**v4**.

## `Shift`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Unique attribute |
| `startedAt` | `Date` | Recorded when the shift starts, and never rewritten |
| `endedAt` | `Date?` | `nil` means the shift is still running. This is the only definition of "active" |
| `routeSamples` | `[RouteSample]` | Cascade delete, inverse of `RouteSample.shift` |
| `grossEarningsAmount` | `Decimal?` | Private. `nil` means no amount recorded, which is not zero |

Derived, never stored:

| Member | Meaning |
| --- | --- |
| `isActive` | `endedAt == nil` |
| `completedDuration` | Elapsed seconds for a finished shift, clamped at zero |
| `elapsed(asOf:)` | Elapsed seconds for a running shift, clamped at zero |
| `recordedDistance(...)` | A `RouteDistance` measured from the retained route |
| `grossEarnings` | The stored decimal as a `Money`, or `nil` |

`end(at:)` rejects ending a shift twice or ending it before it started. `setGrossEarnings(_:)`
rejects a negative amount and an amount on an unfinished shift. `clearGrossEarnings()` removes the
amount, which is a distinct operation from recording zero.

## `RouteSample`

| Field | Type | Notes |
| --- | --- | --- |
| `timestamp` | `Date` | When the platform fixed the position, not when the app received it |
| `latitude` | `Double` | Degrees |
| `longitude` | `Double` | Degrees |
| `horizontalAccuracy` | `Double` | Radius of uncertainty in metres, as reported when the fix was taken |
| `captureSessionID` | `UUID?` | The uninterrupted period of capture this sample belongs to. `nil` for samples written before v3 |
| `shift` | `Shift?` | Optional only because SwiftData models the inverse that way. The initializer requires a shift |

Nothing else is stored. Core Location also reports speed, course, altitude and their accuracies;
none are kept, because nothing implemented reads them.

## Schema versions

| Version | Change |
| --- | --- |
| 1.0.0 | `Shift`: id, start, optional end |
| 2.0.0 | Adds `RouteSample` and `Shift.routeSamples` |
| 3.0.0 | Adds `RouteSample.captureSessionID` |
| 4.0.0 | Adds `Shift.grossEarningsAmount` |

Every step so far is a lightweight stage, and none backfills a value. See
[Migrations](../architecture/migrations.md).

## Domain value types

| Type | Purpose |
| --- | --- |
| `Money` | `Decimal`-backed monetary value. Unrounded in memory, rounded only for display |
| `MoneyInput` | Locale-aware parsing of what a decimal pad produces, with typed rejections |
| `RoutePoint`, `LocationSample` | Framework-free position values used by the filter and calculator |
| `RouteSampleFilter` | The capture acceptance policy and its rejection reasons |
| `RouteCaptureState` | Active, paused in background, permission required, unavailable |
| `RouteDistance` | Metres, segments, gaps, usable positions, inferred continuity, `isMeasured`, `isPartial` |
| `RouteMileageCalculator` | Splits a route into continuous segments and sums within them |
| `RouteQuality` | The tested vocabulary describing a measured route |
| `GeographicDistance` | One haversine implementation, shared by capture and measurement |
| `ShiftMetrics`, `ShiftMetricsCalculator` | Both derived rates and their precision rules |
| `ShiftRate`, `ShiftRateUnavailability` | An available rate, or the reason there is none |
| `LocationAuthorization` and its enums | Permission facts, condition precedence and recovery |
| `ShiftLifecycleError` | Refused start, end and delete transitions |

## What is not in the store

Durations, distances, rates, route quality wording and capture state are all computed when they are
needed. The store holds timestamps, positions and one optional amount, and nothing that could
disagree with them.
