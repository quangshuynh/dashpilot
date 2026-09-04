# CLAUDE.md

## Project

DashPilot is a native, local-first iOS companion for delivery drivers.

Its purpose is to reduce manual bookkeeping and help drivers understand mileage, time, earnings efficiency, pickup delays, location patterns, and repositioning decisions.

This is a general delivery-driver tool. It must not depend on unauthorized access to DoorDash or another delivery platform.

## Core stack

Prefer first-party Apple technologies:

* Swift
* SwiftUI
* SwiftData
* Core Location
* MapKit
* Core Motion when justified
* ActivityKit when justified
* App Intents when justified
* UserNotifications when justified
* Charts
* OSLog
* Swift Testing
* XCTest UI tests where appropriate

Do not add third-party runtime dependencies without a concrete engineering reason.

## Product boundaries

Do not implement:

* DoorDash credential collection
* private DoorDash API access
* reverse engineering
* network interception
* scraping
* automatic offer acceptance
* automatic offer rejection
* simulated interaction with another delivery app
* mechanisms intended to circumvent another platform's restrictions

Do not claim capabilities that have not been implemented and verified.

Delivery-platform information that cannot be obtained through legitimate public mechanisms should remain manual or absent.

## Local-first rule

User data should remain on-device by default.

Do not introduce:

* accounts
* cloud synchronization
* analytics
* telemetry
* advertising
* tracking SDKs
* remote databases

unless the product requirements are explicitly changed.

## Sensitive data

Treat the following as sensitive:

* precise coordinates
* route history
* earnings
* customer locations
* pickup and dropoff history
* driver routines
* personally identifying notes

Never commit real user data.

Use synthetic examples in:

* tests
* previews
* screenshots
* documentation
* fixtures

Do not log exact coordinates through OSLog.

## Driving safety

Design workflows to minimize interaction while a vehicle is moving.

Prefer:

* automatic collection
* one-tap controls
* large targets
* glanceable interfaces
* Siri and App Intents
* actions performed while stopped
* deferred data entry

Do not design interfaces that encourage typing while driving.

## Engineering principles

Prefer simple, explicit architecture.

Keep domain logic separate from presentation when practical.

Important calculations should be testable without launching the UI.

Avoid:

* giant views
* giant manager classes
* unnecessary protocols
* speculative abstraction
* dependency injection frameworks
* premature Core ML
* premature networking
* premature backend work

Use abstractions when they solve a current problem.

## Monetary calculations

Do not rely on binary floating-point for calculations where monetary precision matters.

Use appropriate precise representations and centralize money-related calculations.

## Location engineering

Location behavior must account for:

* authorization state
* denied permission
* restricted permission
* reduced accuracy
* unavailable location services
* background execution limitations
* application lifecycle transitions
* battery consumption
* interrupted tracking
* duplicate samples
* inaccurate samples
* implausible GPS jumps

Never imply that iOS guarantees uninterrupted background execution.

Tracking state must be clearly visible to the user.

## Persistence

SwiftData is the default persistence layer.

Treat schema evolution seriously.

When models change:

* consider compatibility
* preserve existing user data
* add migration coverage where appropriate
* avoid destructive resets as a substitute for migration

## Testing

Tests should focus on meaningful behavior.

Prioritize testing:

* shift lifecycle
* duration calculation
* distance calculation
* earnings calculations
* delivery metrics
* state transitions
* location filtering
* recommendation logic
* migration behavior
* failure handling

UI tests should cover a small number of important user journeys rather than duplicating unit tests.

## Logging

Use OSLog for useful diagnostics.

Logs should help diagnose:

* lifecycle
* persistence
* permissions
* location tracking
* route processing
* recommendations
* exports
* failures

Do not log sensitive user data unnecessarily.

## Git authorization

Claude is authorized to create local branches and local commits automatically.

Claude may:

* create branches
* switch branches
* make commits
* make multiple coherent commits during an interval

Claude must not automatically:

* push
* force push
* merge into main
* open pull requests
* tag releases
* publish releases
* modify remote repository settings

These actions require explicit user instruction.

## Branch naming

Use:

* `feat/<name>`
* `fix/<name>`
* `refactor/<name>`
* `test/<name>`
* `docs/<name>`
* `chore/<name>`

Keep branch scope narrow.

## Commit naming

Use conventional prefixes:

* `feat:`
* `fix:`
* `refactor:`
* `test:`
* `docs:`
* `chore:`

Commits should represent coherent changes.

Do not create filler commits.

Do not rewrite unrelated history.

## Interval workflow

Development happens in bounded intervals.

At the beginning of every interval:

1. Read `CLAUDE.md`.
2. Read `AGENTS.md`.
3. Read `context.md` if it exists.
4. Inspect Git status.
5. Inspect recent commits.
6. Inspect the relevant implementation before modifying it.
7. Define one coherent interval objective.
8. Create or switch to the appropriate branch.

During the interval:

1. Implement the objective.
2. Keep scope controlled.
3. Add or update tests.
4. Build frequently enough to catch integration failures.
5. Investigate failures instead of bypassing them.
6. Preserve unrelated work.

At the end:

1. Run relevant tests.
2. Run the appropriate build.
3. Review `git diff`.
4. Check `git status`.
5. Update documentation if behavior changed.
6. Commit completed work.
7. Stop.

Report:

* interval objective
* branch
* commits
* files or systems changed
* tests executed
* build result
* known limitations
* recommended next interval

Do not automatically begin the next major interval.

## Scope discipline

A normal interval should cover one coherent capability.

Good examples:

* shift persistence
* location permission flow
* route recording
* mileage calculation
* shift dashboard
* historical shift browser
* delivery entry workflow
* wait-time tracking
* map visualization
* App Intent support
* Live Activity support
* recommendation engine
* export
* accessibility
* performance
* migration safety

Avoid giant branches containing multiple unrelated capabilities.

## Documentation

Keep repository documentation accurate.

Do not advertise planned behavior as implemented behavior.

Distinguish clearly between:

* implemented
* experimental
* planned

Do not use exaggerated security, privacy, intelligence, or optimization claims.

## Context file

`context.md` contains local working context for the owner and agents.

It is intentionally excluded from Git.

It may contain temporary decisions, current priorities, experiments, local testing observations, or private development notes.

Do not copy sensitive information from `context.md` into committed files unless it is explicitly appropriate for the public repository.
