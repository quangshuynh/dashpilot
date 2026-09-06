# AGENTS.md

Repository-wide engineering rules for DashPilot.

Read `context.md` for the current implementation state, schema/export versions, active limitations, and verification baseline. Inspect the source before assuming context is current.

## Product

DashPilot is a native, local-first iOS companion for delivery drivers. It records driver-entered and device-observed history and uses trustworthy historical data to support better delivery decisions.

It is not affiliated with DoorDash or another delivery platform.

Do not:

* scrape or reverse-engineer delivery platforms
* intercept private traffic
* store platform credentials
* automate offer acceptance/rejection
* control another delivery app
* claim official platform integration

## Stack

Prefer the existing first-party stack:

* Swift
* SwiftUI
* SwiftData
* Swift Testing
* minimal XCTest UI tests
* Core Location
* MapKit, Core Motion, ActivityKit, App Intents, UserNotifications, Charts, and Core ML only where justified
* OSLog

Do not add third-party runtime dependencies without a concrete need.

Do not enable Swift 6 language mode or broadly change concurrency settings as incidental work.

## Engineering priorities

Prioritize:

1. correctness
2. explicit semantics
3. user-data preservation
4. privacy
5. testability
6. accessibility
7. recoverability
8. maintainability
9. measured performance
10. feature breadth

Prefer a smaller defensible feature over a larger feature with ambiguous claims.

Inspect existing conventions before adding abstractions.

Keep business logic out of SwiftUI when it can live in domain types, calculators, or focused services.

Avoid duplicate implementations of the same rule.

## Local-first and privacy

Unless explicitly changed by a scoped feature:

* no backend
* no accounts
* no cloud persistence
* no analytics
* no telemetry
* no ads
* no automatic uploads
* no required network service for core behavior

Treat as sensitive:

* coordinates and routes
* addresses
* pickup-place names and normalized keys
* earnings and expenses
* work schedules
* historical performance data

Never log sensitive values.

Structural logs are acceptable.

Use synthetic data only in tests, fixtures, previews, screenshots, documentation, and examples.

Never commit real personal, customer, merchant, route, address, earnings, or expense data.

## Driving safety

Minimize interaction during active driving.

Prefer passive collection, large controls, glanceable state, short lifecycle actions, voice interaction where appropriate, and post-delivery editing.

Avoid workflows requiring substantial typing or sustained visual attention while driving.

## Domain truth

Do not weaken domain semantics for presentation convenience.

Preserve distinctions such as:

* missing vs explicit zero
* recorded vs total
* partial vs complete
* gross vs net/profit
* historical observation vs prediction

Do not fabricate unavailable values.

Do not silently substitute estimates.

## Money

Use the existing Decimal-backed `Money` representation and `MoneyInput` rules.

Never use `Double` or `Float` as authoritative money.

Missing money and explicit zero are different facts.

Do not introduce parallel parsing or rounding policies.

## Earnings

Shift gross earnings and delivery gross earnings are independent facts.

Do not:

* infer one from the other
* allocate shift earnings across deliveries
* require reconciliation
* label their difference as missing/unallocated earnings
* automatically modify one when the other changes

Use the current domain definition for period headline earnings.

## Delivery and time semantics

Delivery state is derived from lifecycle timestamps.

Stacked deliveries are supported, so delivery intervals may overlap.

Shift delivery-active time uses the union of qualifying delivery intervals within that shift.

Do not sum overlapping delivery durations to obtain shift active time.

Do not call non-delivery time idle time.

## Pickup places and waits

Reuse the existing pickup-name normalization policy.

Matching is intentionally conservative. Do not add fuzzy matching, automatic merging, aliases, or duplicate detection without explicit scope.

A recorded pickup wait is derived from valid lifecycle endpoints.

Missing/malformed endpoints do not become zero or estimates.

Aggregate medians use qualifying individual samples, not medians of already-aggregated groups.

## Location and mileage

Location history is sensitive.

Respect the existing authorization and tracking architecture. Do not add stronger authorization or background modes incidentally.

Recorded mileage means distance supported by accepted route samples. It is not necessarily total driven mileage.

Preserve existing filtering, capture-session continuity, gap, partial-route, and legacy-continuity semantics.

Do not bridge capture gaps with invented distance.

## Historical periods and aggregation

Historical summaries use completed shifts. Running shifts are excluded.

A shift belongs to the reporting period containing its `startedAt`. Do not split overnight shifts under the current model.

Use `Calendar` for calendar boundaries, not fixed-second assumptions.

Periods use half-open intervals internally.

Missing-data coverage is part of a metric.

Explicit zero counts as recorded coverage. Missing does not.

Rates requiring multiple facts must use the same paired contributing subset.

Period rates generally use:

`sum(numerator) / sum(denominator)`

over that subset.

Do not average already-derived rates unless that is explicitly the intended statistic.

Aggregate medians from underlying samples, not smaller-period medians.

## Persistence

Treat SwiftData changes as compatibility work.

Before changing stored shape:

1. inspect the current schema and frozen historical schemas
2. determine whether persistence is necessary
3. prefer derived values when appropriate
4. preserve frozen schemas
5. add the smallest valid migration
6. add migration tests that prove relevant historical data survives

Never rewrite a frozen historical schema to match current code.

Do not use destructive store reset as normal migration behavior.

Be careful with `ModelContext.rollback()`: authoritative store state and already-held model relationship caches may differ after rollback. Verify persisted rollback through a fresh context when necessary.

## Derived data

Prefer recomputing values that are reliably derived from authoritative records.

Do not persist aggregates solely for UI convenience or speculative performance.

Introduce caching/persistence only when profiling establishes a need and invalidation semantics are clear.

## Export

Export is an external contract separate from the SwiftData schema.

Use export-specific value types rather than serializing SwiftData models directly.

Preserve domain semantics in exported data, including missing values, Decimal money, earnings separation, route quality, recorded-mileage wording, and coverage where supported.

Standard export must not expose raw GPS coordinates or normalized pickup-place keys.

CSV must correctly handle quoting, line breaks, Unicode, and spreadsheet formula injection.

Export remains explicit and user initiated.

Evaluate export-format compatibility deliberately whenever the external contract changes.

## Claims and documentation

Do not claim:

* guaranteed increased earnings
* guaranteed profitability
* tax compliance or tax accuracy
* complete driven mileage when capture can be partial
* guaranteed continuous tracking
* official platform integration
* predictive intelligence that does not exist
* AI/ML merely because statistics are used

Prefer precise terms such as:

* recorded mileage
* recorded pickup wait
* gross earnings
* recorded expenses
* delivery active time
* historical performance
* partial route

Keep README concise and documentation accurate.

Update relevant docs when behavior or limitations change.

Correct nearby objectively stale documentation when discovered, but do not expand scoped work into unrelated cleanup.

Do not use em dashes in repository-facing prose.

## Accessibility

Accessibility is part of feature completion.

Controls should identify their subject.

Metrics should communicate units, meaning, and important coverage to assistive technologies rather than relying only on nearby visual captions.

Use appropriate interaction targets.

## Testing

Use deterministic tests for new domain semantics.

Prefer Swift Testing for domain/persistence behavior and focused XCTest UI tests for important user journeys.

Test meaningful:

* invariants
* boundaries
* missing-data behavior
* failure paths
* persistence/reopen behavior
* migrations when applicable
* regression-sensitive semantics

Do not duplicate every domain edge case in UI tests.

Do not weaken tests merely to make new functionality pass.

Use synthetic fixtures.

## Validation

For substantial feature intervals, unless explicitly scoped otherwise:

* run the full domain test suite
* run the full UI suite
* perform a clean build
* resolve new source warnings
* run `mkdocs build --strict`
* verify README links when relevant
* update affected documentation

Distinguish project warnings from SDK/toolchain informational notes.

## Scope discipline

Keep work bounded to the requested interval.

Do not opportunistically begin adjacent roadmap features.

Fix discovered issues during the interval only when required for current correctness or when they are tiny, objectively safe corrections. Otherwise record them in `context.md`.

Do not perform broad refactors without a demonstrated need.

## Git safety

Use repository branch and conventional commit conventions.

Before committing, inspect `git status` and staged changes.

Never commit generated or local artifacts such as:

* DerivedData
* `.xcresult`
* generated documentation sites
* temporary exports
* secrets
* `context.md`
* unrelated IDE artifacts

Agents may create/switch local branches and create coherent local commits when authorized by their agent-specific instructions.

Never automatically push, force push, merge, open a PR, tag, release, or modify remotes unless explicitly authorized.

## Context handoff

`context.md` is the concise current-state handoff and must remain ignored.

At the end of a development interval, update it by replacing stale information rather than appending an interval diary.

Keep:

* current schema/export versions
* implemented capabilities
* important current semantics
* active limitations
* latest verification baseline
* recommended next interval

Remove:

* resolved limitations
* obsolete recommendations
* superseded test counts
* lengthy historical narratives
* rules already defined here

Source code is authoritative if `context.md` is stale.

## Final principle

Make DashPilot's claims increasingly difficult for an experienced iOS engineer to dismiss.

Correctness, explicit semantics, privacy, recoverability, accessibility, testing, and honest limitations matter more than feature count.
