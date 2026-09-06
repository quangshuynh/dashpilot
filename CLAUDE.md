# CLAUDE.md

This file defines the operating rules for Claude when working in the DashPilot repository.

Read this file completely before making changes.

Also read:

1. `AGENTS.md`
2. `context.md`

Then inspect the repository, relevant implementation, tests, documentation, and recent Git history before modifying code.

Do not treat `context.md` as a substitute for inspecting the current source.

---

# Project

DashPilot is a native iOS companion for delivery drivers.

It records driver-entered and device-observed information such as:

* shifts
* delivery lifecycle events
* route samples
* recorded mileage
* gross earnings
* delivery active time
* pickup places
* recorded pickup waits
* historical period metrics

The product direction is to turn trustworthy local historical records into increasingly useful decision support for delivery work.

DashPilot is not affiliated with DoorDash or another delivery platform.

Do not describe it as an official integration.

---

# Technology

Primary stack:

* Swift
* SwiftUI
* SwiftData
* Swift Testing
* minimal XCTest UI coverage
* Core Location
* MapKit where justified
* Core Motion where justified
* ActivityKit where justified
* App Intents where justified
* UserNotifications where justified
* Charts where justified
* OSLog

Core ML or Create ML may be considered later only if enough real data exists, the problem genuinely benefits from ML, and a model can be compared against simpler statistical baselines.

Do not introduce third-party runtime dependencies without a concrete reason.

Prefer Apple and Foundation frameworks.

---

# Product boundaries

DashPilot is a general delivery-driver companion.

Do not:

* scrape delivery-platform applications or websites
* reverse-engineer private APIs
* intercept private network traffic
* store delivery-platform credentials
* automate offer acceptance or rejection
* control another delivery application
* claim official delivery-platform integration
* imply access to private platform data

Any platform-specific data currently recorded by DashPilot must come from explicit user entry or legitimate device-observed information.

---

# Local-first architecture

DashPilot is local-first.

Unless an interval explicitly changes this architecture:

* no backend
* no account system
* no cloud database
* no analytics
* no telemetry
* no advertising
* no automatic uploads
* no network dependency for core functionality

Sensitive records remain on device.

This includes:

* GPS history
* route history
* pickup-place names
* normalized pickup-place identities
* gross earnings
* delivery history
* shift history
* historical performance metrics

Export is explicit and user initiated.

Once a user chooses a destination through the system share interface, the exported file may leave the device. DashPilot itself does not automatically upload it.

---

# Privacy

Treat the following as sensitive:

* coordinates
* addresses
* pickup-place names
* normalized pickup-place keys
* earnings
* routes
* exact historical work patterns
* exported records

Do not place sensitive values in logs.

Structural logs are acceptable.

Examples:

Good:

`Shift started`

`Delivery earnings updated`

`Pickup places merged`

Bad:

`Shift earned $86.25`

`Pickup place Example Diner renamed`

`Route started at 43.123,-77.456`

Do not log values merely because they are useful for debugging.

Use synthetic data only in:

* tests
* previews
* screenshots
* documentation
* fixtures
* examples

Never introduce real customer, merchant, address, earnings, route, or personal data into the repository.

---

# Driving safety

DashPilot is used around driving activity.

Design for minimal interaction while driving.

Prefer:

* passive collection
* large controls
* glanceable state
* explicit lifecycle actions
* voice/App Intents where appropriate
* stopped-vehicle workflows
* post-delivery editing

Avoid:

* dense forms during an active shift
* repeated typing during driving workflows
* small interaction targets
* workflows requiring sustained visual attention

Historical editing and analysis should generally live outside the active-driving surface.

---

# Claims

Repository-facing prose must remain accurate.

Do not claim:

* guaranteed increased earnings
* guaranteed profitability
* tax compliance
* tax accuracy
* official delivery-platform data
* complete driven mileage when capture may be partial
* guaranteed continuous background tracking
* security properties the implementation does not establish
* predictive intelligence that does not exist
* AI or ML merely because statistics are computed

Prefer precise language such as:

* recorded mileage
* recorded pickup wait
* gross earnings
* recorded delivery active time
* historical performance
* partial route
* measured route
* local-first

Do not turn historical association into causal claims.

---

# Writing style

Repository-facing prose should be concise, professional, and technically accurate.

Do not use em dashes.

Use ordinary punctuation instead.

Avoid:

* marketing hype
* exaggerated adjectives
* fake precision
* unsupported performance claims
* vague "AI-powered" language
* unnecessary jargon

Documentation should explain important limitations near the capability they qualify.

---

# Architecture principles

Prefer:

* explicit domain types
* pure calculations
* dependency injection at system boundaries
* small services with clear mutation ownership
* SwiftUI as presentation rather than business logic
* derived values instead of duplicated persisted state
* one authoritative definition for each calculation
* deterministic tests
* conservative failure behavior

Avoid:

* calculations directly in SwiftUI views
* duplicate business rules
* convenience state that can disagree with authoritative persisted facts
* broad service abstractions without multiple genuine use cases
* speculative infrastructure
* premature caching
* hidden fallback behavior

Inspect existing conventions before introducing a new abstraction.

---

# Money

Money is authoritative as `Decimal` through the existing `Money` domain type.

Do not use binary floating point as the authoritative representation of money.

Do not introduce:

* `Double` monetary storage
* `Float` monetary storage
* `Decimal(Double(...))` shortcuts for authoritative amounts

Reuse the existing `Money` and `MoneyInput` rules.

Missing and zero are different facts.

For example:

* `nil` means no amount was recorded
* `$0.00` means the user explicitly recorded zero

Never silently convert missing money to zero.

Round only at defined boundaries.

---

# Earnings semantics

DashPilot currently has independent monetary facts.

Shift gross earnings and delivery gross earnings are not interchangeable.

Never:

* allocate shift earnings among deliveries
* infer delivery earnings from shift earnings
* infer shift earnings from delivery earnings
* require delivery earnings to sum to shift earnings
* report the difference as missing or unallocated money
* reconcile the two automatically

A difference may legitimately represent:

* incomplete delivery-level entry
* bonuses
* adjustments
* stacked-order payout behavior
* compensation not attributable to one delivery

Period headline earnings use recorded shift gross earnings unless the architecture is explicitly changed.

Delivery earnings may be summarized separately with explicit coverage.

---

# Time semantics

Use existing domain definitions rather than inventing new interpretations.

Shift elapsed time is not automatically equivalent to productive or active work.

Delivery active time is derived from delivery lifecycle intervals and unions overlapping intervals within a shift.

Do not sum overlapping delivery durations as though they were independent shift time.

Non-delivery time is not called idle time.

Do not union activity across different shifts unless an interval explicitly introduces and justifies that behavior.

---

# Delivery lifecycle

Delivery state is derived from lifecycle timestamps.

Do not add redundant persisted state when timestamps already establish the state.

Preserve lifecycle invariants.

Stacked deliveries are supported.

Multiple deliveries may be active concurrently.

Any calculation involving delivery duration must account for the fact that concurrent deliveries can overlap.

Do not assume:

sum(delivery durations) == shift delivery-active duration

---

# Pickup places

Pickup-place identity is deliberately conservative.

Use the existing `PickupPlaceName` normalization policy.

Do not introduce a second normalization implementation.

Do not add fuzzy matching or automatic duplicate merging without an explicit interval.

A duplicate place is preferable to incorrectly merging two different places.

Rename:

* changes authoritative display spelling and normalized key
* preserves identity and delivery history
* must not silently merge collisions

Merge:

* explicitly moves source deliveries to the destination
* destination identity wins
* source is removed
* no aliases or redirects currently exist

Do not log pickup-place names or normalized keys.

---

# Pickup waits

A recorded pickup wait is derived from:

`pickedUpAt - arrivedAtPickupAt`

A sample requires valid recorded lifecycle endpoints.

Missing or malformed endpoints are excluded.

Do not:

* replace missing waits with zero
* estimate missing waits
* trim long waits merely because they are outliers
* calculate a place metric from fabricated samples

Historical typical pickup wait currently uses the median of individual qualifying samples.

Do not average already-derived place medians to produce a broader median.

---

# Location and route semantics

Location capture is privacy-sensitive.

Respect the existing authorization and capture architecture.

Do not request stronger authorization or add background location modes without an explicit product decision.

Recorded mileage means distance supported by accepted route samples.

It does not necessarily mean total driven mileage.

Route calculations must preserve existing:

* filtering
* capture-session continuity
* gap handling
* partial-route semantics
* inferred legacy continuity semantics

Do not bridge capture gaps with invented straight-line mileage.

Do not describe partial recorded mileage as complete driven distance.

Raw GPS coordinates must not leave the device through standard export unless a future explicit feature introduces that behavior.

---

# Period metrics

Historical period metrics operate on completed shifts.

Running shifts do not enter historical aggregates.

Shift membership is based on `startedAt`.

An overnight shift belongs wholly to the period containing its start unless the established architecture is deliberately changed.

Do not split:

* shift earnings
* shift mileage
* deliveries
* elapsed time

across midnight merely for reporting.

Use `Calendar` for calendar boundaries.

Do not implement day/week/month boundaries using fixed seconds.

Periods use half-open intervals:

`start <= timestamp < end`

When the UI presents an inclusive custom date range, convert it to the corresponding half-open interval internally.

---

# Aggregate coverage

Missing-data semantics are part of the product.

Do not hide incomplete coverage.

A subtotal of known values is valid, but its coverage must remain available.

Example:

`$284.50 recorded across 3 of 4 shifts`

is valid.

Treating the missing fourth shift as `$0` is not.

Explicit zero counts as recorded coverage.

Where numerator and denominator can independently be missing, a rate must use the same paired contributing subset.

For example, period gross per recorded mile must use only shifts with both:

* recorded shift gross earnings
* measurable positive recorded mileage

Never divide earnings from one coverage set by distance from another.

---

# Rate calculations

Do not average already-derived rates unless the metric specifically requires that operation.

For period rates, prefer:

`sum(numerator) / sum(denominator)`

over the same contributing records.

Do not compute:

`mean(per-shift rate)`

when the intended metric is an aggregate rate.

Reuse existing calculator definitions instead of adding another implementation of the same division.

---

# Persistence

SwiftData schema evolution must be deliberate.

Current schema version and migration state are recorded in `context.md`.

Before changing persistent shape:

1. inspect the current schema
2. inspect all frozen historical schemas
3. determine whether persistence is actually required
4. prefer derived values when persistence is unnecessary
5. freeze the previous schema accurately
6. add the smallest valid migration stage
7. add migration tests

Never edit an old frozen schema to make current code easier.

Historical schemas represent historical storage shape.

Do not destructively reset user data as a migration strategy.

Persistence initialization failures must remain visible and recoverable rather than trapping.

---

# SwiftData failure semantics

Be careful with rollback.

A rollback may restore persistent store state without making already-held model object relationship caches immediately reflect the restored store.

When testing persistence rollback:

* verify authoritative persisted state through a fresh context when necessary
* do not claim stronger in-memory rollback semantics than SwiftData provides

Do not paper over framework behavior merely to make a test convenient.

---

# Derived data

Prefer recomputation for values that can be derived reliably from authoritative records.

Do not persist aggregates solely for convenience.

Examples that should generally remain derived:

* mileage totals
* active time
* non-delivery time
* period earnings totals
* rates
* pickup-wait medians
* coverage counts

Persistence may be introduced later if profiling establishes a real need and invalidation semantics are designed explicitly.

---

# Export

Export is a versioned external contract separate from the SwiftData schema.

Do not conflate:

* persistence schema version
* export format version

Standard export is explicit and user initiated.

Current export principles:

* JSON is the canonical structured format
* CSV is spreadsheet-friendly
* money remains decimal-safe
* missing values remain missing
* route quality remains explicit
* recorded mileage remains labeled recorded
* shift and delivery earnings remain separate
* normalized pickup-place keys are internal
* raw GPS coordinates are excluded
* CSV user-entered text must remain protected against spreadsheet formula injection

Do not serialize SwiftData models directly.

Use export-specific value types.

If an interval changes the external export contract, explicitly evaluate compatibility and whether the export format version must change.

---

# Accessibility

Accessibility is part of feature completion.

Controls should identify their subject.

Prefer labels such as:

`Edit gross earnings for Delivery 2`

rather than:

`Edit`

Metrics should communicate relevant context and coverage to VoiceOver.

Do not rely on nearby visual captions to make an otherwise ambiguous accessibility value meaningful.

Use appropriately sized interaction targets.

---

# Error handling

Prefer explicit errors over silent fallback.

User-visible failures should be understandable without exposing implementation details.

Do not expose:

* raw filesystem paths
* database internals
* sensitive values
* raw framework errors

Do not silently discard user data to recover from an error.

---

# OSLog

Use structured OSLog categories where useful.

Never log sensitive values.

Logging should describe lifecycle or structural events, not user content.

Avoid logging purely because a test or debugger would find a value convenient.

---

# Testing

New semantics require deterministic tests.

Prefer Swift Testing for domain and integration behavior.

Use XCTest UI tests only for high-value user journeys.

Do not duplicate every domain edge case in UI tests.

Tests should prove:

* invariants
* boundary conditions
* missing-data behavior
* persistence/reopen behavior where relevant
* migration behavior where relevant
* failure behavior
* accessibility-critical user journeys
* regression-sensitive semantics

Do not weaken an existing test simply because new functionality makes it inconvenient.

If an existing assertion is no longer correct, establish why the product semantics changed before modifying it.

Use synthetic fixtures only.

---

# Migration testing

When persistent shape changes, migration tests should prove preservation of relevant historical data, not merely that the store opens.

Where applicable verify:

* shifts
* route samples
* capture-session identifiers
* earnings
* deliveries
* pickup places
* relationships
* lifecycle timestamps
* existing derived results

New optional fields should not be backfilled from unrelated data unless the product explicitly defines such a migration.

---

# UI testing

UI tests should cover important journeys, not implementation details.

Prefer a few strong journeys over broad brittle duplication.

If a lower section is lazily rendered in a `List`, scroll to it intentionally rather than assuming it already exists in the accessibility hierarchy.

Run the complete UI suite before declaring an interval complete.

---

# Build quality

An interval is not complete with new source warnings.

SDK/toolchain informational notes that are outside the project's control should be distinguished from source warnings.

Prefer a clean build from deleted DerivedData for final verification.

---

# Documentation

Documentation is part of implementation.

When behavior changes, update the relevant MkDocs pages.

Run:

`mkdocs build --strict`

Keep README concise.

README should describe the product and major capabilities, not duplicate all technical documentation.

Check README links when README or linked documentation changes.

Do not leave stale schema numbers, unsupported capabilities, or obsolete limitations in documentation.

Small nearby corrections to objectively stale documentation are allowed when discovered during an interval.

Do not use documentation cleanup as an excuse for unrelated rewrites.

---

# Scope discipline

Every development interval is bounded.

Before implementing, identify:

* what the interval owns
* what it explicitly does not own
* the stop condition

Do not opportunistically start the next roadmap item.

If implementation reveals a separate problem:

* fix it only if necessary for correctness of the current interval
* otherwise record it in `context.md` as a limitation or recommended follow-up

Prefer one completed coherent interval over several partially implemented features.

---

# Inspection before modification

At the beginning of every interval:

1. Read `CLAUDE.md`.
2. Read `AGENTS.md`.
3. Read `context.md`.
4. Inspect Git status.
5. Inspect recent Git history.
6. Inspect the relevant implementation.
7. Inspect relevant tests.
8. Inspect relevant documentation.
9. Confirm current schema/export versions when relevant.
10. Only then modify code.

Do not rely solely on filenames or `context.md`.

The source is authoritative for what is actually implemented.

---

# Git workflow

Development happens on bounded feature branches.

Branch naming:

* `feat/...`
* `fix/...`
* `refactor/...`
* `test/...`
* `docs/...`
* `chore/...`

Use conventional commit prefixes:

* `feat:`
* `fix:`
* `refactor:`
* `test:`
* `docs:`
* `chore:`
* `ci:`

Claude may:

* create a local branch
* switch local branches
* create coherent local commits

Claude must not automatically:

* push
* force push
* merge to `main`
* open a pull request
* tag
* create a release
* modify remotes

unless the user explicitly instructs it to do so.

Never rewrite history outside the current local feature branch without explicit authorization.

Be especially careful with bulk staging.

Before committing, inspect what is staged.

Do not blindly commit:

* `.xcresult`
* DerivedData
* generated site output
* temporary exports
* local context files
* secrets
* IDE artifacts

---

# context.md

`context.md` is the authoritative local handoff between development intervals.

It is intentionally ignored by Git and must never be committed.

At the start of each interval, read it.

At the end of each interval, update it.

Do not turn it into an append-only diary.

Replace stale information.

Keep only information that is useful to the next development interval.

It should remain concise enough to read at the beginning of every fresh Claude session.

## context.md should contain

At minimum:

### Current state

* current schema version
* current export format version
* latest completed interval
* major implemented capabilities

### Current architecture

* persistence
* shifts
* routes
* deliveries
* earnings
* pickup places
* metrics
* export
* other major systems

### Important semantics

* authoritative definitions
* missing-data rules
* aggregation rules
* privacy decisions
* lifecycle invariants

### Known limitations

Only current limitations that still matter.

Remove limitations after they are resolved.

### Verification baseline

* domain test status
* UI test status
* clean build status
* docs build status

Exact test counts are useful but may be replaced by newer counts.

### Recommended next interval

* branch name
* objective
* important constraints

---

# Keeping context small

When updating `context.md`:

* replace old test counts with current counts
* remove completed roadmap items from "next"
* remove limitations that were fixed
* summarize old implementation history into current-state facts
* avoid copying entire interval reports
* avoid storing commit-by-commit history unless a commit is important to future work
* avoid repeating rules already present in `CLAUDE.md` or `AGENTS.md`

`context.md` should explain where the project is now, not narrate everything that happened.

---

# Standard interval completion contract

Unless the interval prompt explicitly says otherwise, every development interval must:

1. inspect before changing code
2. create/use the requested local feature branch
3. preserve existing architectural boundaries
4. keep work within interval scope
5. use the smallest justified persistence change
6. preserve historical schemas when migration is required
7. keep derived data unpersisted unless persistence is justified
8. keep sensitive data local and out of logs
9. use synthetic data in repository artifacts
10. add deterministic domain tests for new semantics
11. add focused UI journeys for meaningful user-visible behavior
12. preserve existing tests
13. run the full domain test suite
14. run the full UI test suite
15. perform a clean build
16. resolve new source warnings
17. run `mkdocs build --strict`
18. check README links when relevant
19. update documentation
20. update `context.md`
21. verify `context.md` remains ignored
22. inspect staged files before commits
23. create coherent local commits
24. leave the working tree clean
25. stop before the next roadmap interval

---

# Interval report

At completion, report:

## Objective

What the interval was intended to accomplish.

## Branch

Local branch name and whether anything was pushed.

## Commits

Commit subjects, optionally hashes when useful.

## Persistence

Schema decision and migration behavior.

## Architecture and semantics

Important implementation decisions and invariants.

## UI and accessibility

User-visible behavior and accessibility decisions.

## Privacy

Anything relevant to sensitive data, logging, networking, or export.

## Verification

* domain tests
* UI tests
* clean build
* source warnings
* docs build
* README links when checked

## Issues discovered

Unexpected bugs, framework behavior, or corrections found during the interval.

## Known limitations

Only real remaining limitations.

## Recommended next interval

One recommended bounded next step and why.

Do not begin that next interval.

---

# Fresh-session workflow

Prefer a fresh Claude conversation for each major development interval.

The repository carries durable context.

A normal future interval prompt should not need to repeat this file.

A short prompt containing:

* branch name
* objective
* interval-specific rules
* stop condition

is normally sufficient.

If a short prompt conflicts with this file, follow the explicit current prompt for that interval unless doing so would violate a higher-priority safety or user instruction.

---

# Final rule

Do not optimize for producing the largest diff.

Optimize for making DashPilot's existing and new claims increasingly difficult for an experienced iOS engineer to dismiss.

Correctness, explicit semantics, privacy, recoverability, testability, accessibility, and honest limitations matter more than feature count.
