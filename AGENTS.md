# AGENTS.md

This file defines repository-wide engineering rules for automated coding agents working on DashPilot.

Read this file before modifying the repository.

Agent-specific workflow instructions may exist separately. `context.md`, when present, contains the current local project handoff.

---

# Project

DashPilot is a native iOS companion for delivery drivers.

It records and analyzes local driver history such as:

* shifts
* delivery lifecycle events
* route samples
* recorded mileage
* gross earnings
* delivery active time
* pickup places
* recorded pickup waits
* historical period metrics

The long-term product direction is trustworthy, explainable decision support based on the driver's own recorded history.

DashPilot is not an official client or integration for DoorDash or another delivery platform.

---

# Stack

Primary technologies:

* Swift
* SwiftUI
* SwiftData
* Swift Testing
* XCTest UI testing where justified
* Core Location
* MapKit where justified
* Core Motion where justified
* ActivityKit where justified
* App Intents where justified
* UserNotifications where justified
* Charts where justified
* OSLog

Prefer first-party Apple frameworks.

Do not introduce third-party runtime dependencies without a concrete architectural need.

---

# Engineering priorities

Optimize for:

1. correctness
2. explicit semantics
3. preservation of user data
4. privacy
5. testability
6. accessibility
7. recoverability
8. maintainability
9. performance supported by evidence
10. feature breadth

Do not manufacture feature work merely to make the project look larger.

---

# Local-first

DashPilot is local-first.

Unless explicitly changed by a scoped feature:

* no backend
* no accounts
* no cloud persistence
* no analytics
* no telemetry
* no advertising
* no automatic upload
* no required network service for core behavior

Sensitive work history stays on device unless the user explicitly exports it.

---

# Platform boundaries

Do not:

* scrape delivery platforms
* reverse-engineer private delivery APIs
* intercept private application traffic
* store delivery-platform credentials
* automate acceptance or rejection of offers
* control another delivery application
* claim official platform integration

DashPilot should remain a general delivery-driver companion.

---

# Privacy

Treat as sensitive:

* GPS coordinates
* routes
* addresses
* pickup-place names
* normalized pickup-place keys
* earnings
* exact work schedules
* historical performance data

Do not log sensitive values.

Logs should describe structural events only.

Use synthetic information in:

* tests
* fixtures
* previews
* screenshots
* documentation
* examples

Never commit real user, customer, merchant, route, earnings, or address data.

---

# Driving safety

DashPilot may be used during delivery work.

Active-driving workflows should minimize interaction.

Prefer:

* passive collection
* large controls
* glanceable information
* short explicit lifecycle actions
* voice interaction where appropriate
* post-delivery editing

Avoid requiring substantial typing or sustained visual attention during active work.

---

# Domain truth over presentation convenience

The domain model defines what a fact means.

Do not weaken semantics to make UI implementation easier.

Presentation should expose uncertainty or missing coverage when it materially changes interpretation.

Do not replace:

* missing with zero
* partial with complete
* recorded with total
* gross with profit
* historical association with prediction

---

# Derived state

Prefer deriving values from authoritative facts.

Do not persist a value merely because the UI displays it.

Persist only when:

* it is an authoritative user/device fact, or
* recomputation has been demonstrated to be inappropriate and invalidation semantics are defined

Avoid duplicated persisted state that can disagree.

---

# Money

Use the existing Decimal-backed `Money` representation.

Do not use `Double` or `Float` as authoritative monetary storage.

Missing money and explicit zero are distinct.

Never silently replace missing money with zero.

Use existing input and rounding policies.

Do not create parallel money parsing rules for individual features.

---

# Earnings

Shift gross earnings and delivery gross earnings are independent recorded facts.

Never:

* infer one from the other
* allocate shift earnings among deliveries
* require them to reconcile
* label their difference as missing earnings
* automatically modify one when the other changes

Period headline gross earnings use shift-level gross earnings under the current domain model.

Delivery-level amounts remain separately recorded facts.

---

# Delivery lifecycle

Delivery state is derived from lifecycle timestamps.

Preserve lifecycle invariants.

Do not persist redundant state if existing timestamps already establish it.

Stacked deliveries are supported.

Multiple deliveries may overlap.

Do not assume individual delivery durations can be summed to obtain shift active time.

---

# Time

Shift elapsed time and delivery active time are different metrics.

Delivery active time unions overlapping delivery intervals within a shift.

Non-delivery time must not be mislabeled as idle time.

Do not invent interpretations that the recorded lifecycle does not support.

---

# Pickup identity

Pickup-place matching is intentionally conservative.

Reuse the existing pickup-name normalization policy.

Do not add:

* fuzzy matching
* automatic duplicate detection
* automatic merges
* aliases

without an explicit feature requiring them.

Incorrectly merging different places is worse than preserving a duplicate.

Rename and merge operations must preserve delivery history according to existing domain rules.

---

# Pickup waits

Recorded pickup wait is based on valid recorded lifecycle timestamps.

Missing or malformed endpoints do not produce zero or estimated waits.

Use individual qualifying samples for aggregate medians.

Do not aggregate medians as a substitute for aggregating the underlying samples.

Long but valid samples remain factual observations unless an explicit statistical policy says otherwise.

---

# Location

Location history is sensitive.

Respect the existing authorization and tracking architecture.

Do not add stronger authorization, background tracking, or new location entitlements casually.

Recorded mileage is mileage supported by accepted route samples.

It is not necessarily total driven mileage.

Preserve:

* capture sessions
* continuity boundaries
* gap semantics
* partial-route semantics
* route filtering

Do not bridge missing capture periods with invented distance.

---

# Historical periods

Historical summaries operate on completed shifts.

Running shifts are excluded.

A completed shift belongs to the reporting period containing its `startedAt`.

Do not split overnight shifts across reporting periods under the current model.

Use `Calendar` for calendar boundaries.

Do not assume a day is always 86,400 seconds.

Reporting intervals use half-open semantics.

---

# Aggregate coverage

Coverage is part of a metric.

If only some records contribute, preserve that information.

Missing records must not silently contribute zero.

Explicit zero is a recorded value and therefore counts as coverage.

Rates requiring two facts must use records where both facts are available.

Do not combine a numerator from one population with a denominator from another.

---

# Aggregate rates

Calculate aggregate rates from aggregate numerators and denominators over the same contributing subset.

Do not average already-derived per-record rates unless that is explicitly the intended statistic.

For example:

Correct:

`sum(earnings) / sum(hours)`

Incorrect for a period-wide earnings rate:

`mean(eachShift.earningsPerHour)`

Reuse existing calculator definitions.

---

# SwiftData

Treat persistence changes as compatibility work.

Before changing stored shape:

* inspect the current schema
* inspect frozen historical schemas
* determine whether the new value truly needs persistence
* preserve previous schemas
* add the smallest valid migration
* test migration using real historical shape

Never rewrite frozen historical schemas to match current models.

Do not use destructive reset as normal migration behavior.

---

# Rollback behavior

Do not assume SwiftData rollback makes every already-held model object immediately reflect restored relationship state.

When correctness depends on persisted rollback, verify through a fresh context where necessary.

Distinguish:

* authoritative store correctness
* transient state of cached model objects

Document framework limitations rather than pretending they do not exist.

---

# Export

Export is an external contract, separate from persistence.

Use export-specific value types rather than serializing SwiftData models directly.

Preserve:

* missing values
* Decimal money
* shift/delivery earnings separation
* route quality
* recorded-mileage wording
* coverage information where supported

Standard export must not include raw GPS coordinates or normalized pickup-place keys.

CSV must correctly handle:

* commas
* quotes
* line breaks
* Unicode
* spreadsheet formula injection

Export is explicit and user initiated.

---

# Architecture

Prefer:

* pure domain calculators
* value types for derived results
* small services with clear ownership
* dependency injection at framework boundaries
* SwiftUI views that present rather than define domain rules
* one authoritative implementation for each calculation

Avoid:

* business logic duplicated across views
* global mutable state without necessity
* broad generic frameworks created for one use
* speculative abstractions
* hidden fallback behavior

Follow existing repository conventions before introducing a new pattern.

---

# Concurrency

Do not change Swift language mode or concurrency settings casually.

The project may use explicit `nonisolated` where domain/value semantics need to remain independent of main-actor isolation.

Treat a move to stricter Swift concurrency or Swift 6 language mode as a deliberate hardening task.

Do not scatter annotations solely to silence diagnostics without understanding isolation.

---

# Errors

Prefer explicit failure over silent corruption or data loss.

Do not:

* silently reset persistent stores
* silently discard records
* silently substitute fabricated values
* expose sensitive implementation details in user-facing errors

Errors should be testable and understandable.

---

# Accessibility

Accessibility is required for user-visible features.

Interactive controls should identify their subject.

Metrics should expose relevant meaning and coverage to assistive technologies.

Do not rely exclusively on visual layout to communicate:

* operation direction
* missing coverage
* metric units
* delivery identity

Use reasonable interaction target sizes.

---

# Tests

Use deterministic tests for domain behavior.

Prefer Swift Testing for domain and persistence behavior.

Use XCTest UI tests for important user journeys.

Tests should cover meaningful:

* invariants
* boundaries
* missing-data semantics
* failure paths
* persistence/reopen behavior
* migrations
* accessibility behavior
* regressions

Do not duplicate all domain cases in UI tests.

Do not weaken tests simply to make a feature pass.

Use synthetic fixtures.

---

# Build and warnings

New source warnings are not acceptable interval output.

Distinguish project warnings from SDK/toolchain informational notes.

Perform clean builds when validating substantial changes.

---

# Documentation

Documentation must describe implemented behavior accurately.

Update relevant docs when behavior or limitations change.

Do not claim planned features as implemented.

Keep README concise.

Correct nearby objectively stale documentation when discovered, but do not turn scoped engineering work into unrelated documentation cleanup.

Do not use em dashes in repository-facing prose.

---

# Scope

Keep changes bounded to the requested task.

Do not opportunistically implement unrelated roadmap features.

When another issue is discovered:

* fix it if required for correctness of the current task
* otherwise document it for later

Avoid large refactors unless the current task genuinely requires them.

---

# Git safety

Use conventional branch and commit naming consistent with the repository.

Before committing:

* inspect `git status`
* inspect staged changes
* verify generated artifacts are not staged

Do not commit:

* DerivedData
* `.xcresult`
* generated documentation sites
* temporary export files
* secrets
* local handoff files
* unrelated IDE artifacts

Do not automatically:

* push
* force push
* merge
* create pull requests
* tag
* release
* modify remotes

unless explicitly authorized.

---

# Local context

When `context.md` exists, it is the current local handoff.

Read it before substantial work.

It may contain:

* current schema/export versions
* implemented capabilities
* important current semantics
* known limitations
* verification baseline
* recommended next work

Source code remains authoritative if context and implementation disagree.

Update local context according to the active agent's workflow instructions.

Do not commit `context.md`.

---

# Final engineering principle

DashPilot should become more useful by making trustworthy recorded facts easier to understand and act on.

Do not gain apparent sophistication by weakening semantics.

A smaller feature with explicit assumptions, strong tests, honest coverage, and recoverable persistence is preferable to a larger feature whose claims cannot be defended.
