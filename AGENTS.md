# AGENTS.md

## Purpose

This file defines repository-wide instructions for coding agents working on DashPilot.

Read this file before modifying the repository.

Also read:

* `CLAUDE.md` when using Claude
* `context.md` when it exists locally

## Product

DashPilot is a native iOS companion for delivery drivers.

The application helps drivers measure and understand:

* shifts
* mileage
* driving time
* idle time
* earnings
* earnings per hour
* earnings per mile
* delivery efficiency
* pickup delays
* geographic performance
* repositioning decisions

The project is local-first and privacy-conscious.

## Platform

Primary target:

* iOS

Primary implementation:

* Swift
* SwiftUI
* SwiftData

Prefer first-party Apple frameworks.

## External platform boundary

DashPilot must remain independent of unauthorized delivery-platform integrations.

Agents must not implement:

* credential capture for DoorDash or similar platforms
* scraping
* reverse engineering
* private API access
* network interception
* automated acceptance or rejection of delivery offers
* UI automation intended to control another delivery application
* techniques intended to bypass platform restrictions

If a requested feature would require one of these mechanisms, stop that portion of the implementation and identify a legitimate alternative.

## Privacy

Keep personal driver data local unless requirements explicitly change.

Never commit:

* real earnings
* real customer addresses
* personal routes
* exact personal GPS history
* authentication secrets
* API credentials
* personally identifying delivery records

Committed sample data must be synthetic.

## Safety

The product must minimize required interaction while driving.

Prefer passive data collection and actions suitable for use while stopped.

Do not build flows that require sustained typing or visual attention while driving.

## Code quality

Prefer readable code over clever code.

Avoid unnecessary architecture.

Keep:

* views focused
* domain logic testable
* persistence behavior explicit
* state transitions understandable
* error states visible
* permissions handled deliberately

Use comments to explain why, not to narrate obvious code.

Remove dead code rather than leaving large commented-out sections.

## Dependencies

Do not introduce a third-party dependency when Apple frameworks or a small internal implementation reasonably solve the problem.

Before adding any dependency, consider:

* maintenance
* privacy
* binary size
* licensing
* long-term compatibility
* whether the dependency is actually necessary

## Tests

New domain behavior should normally include tests.

Bug fixes should include a regression test when practical.

Tests should validate behavior, not implementation trivia.

Do not weaken tests merely to make a build pass.

## Build health

Before completing an interval:

* run relevant tests
* build the relevant target
* inspect warnings introduced by the change
* inspect Git status
* inspect the final diff

Do not report success if the relevant build or tests are known to fail.

## Git workflow

Agents are authorized to create local branches and commits.

Agents are not authorized to push or publish changes unless explicitly instructed.

Branch conventions:

* `feat/...`
* `fix/...`
* `refactor/...`
* `test/...`
* `docs/...`
* `chore/...`

Commit conventions:

* `feat: ...`
* `fix: ...`
* `refactor: ...`
* `test: ...`
* `docs: ...`
* `chore: ...`

Do not mix unrelated work into the same commit.

Do not delete or overwrite unrelated uncommitted user work.

## Development intervals

Work should proceed through small, reviewable intervals.

Each interval should:

1. establish current repository state
2. choose one coherent objective
3. create or use a focused branch
4. implement that objective
5. test it
6. build it
7. review the diff
8. commit coherent completed work
9. summarize the result
10. stop before starting a substantially different objective

Agents should not attempt to implement the complete roadmap in a single run.

## Suggested product progression

Prefer approximately this order unless the current repository state establishes another priority:

1. application foundation
2. shift lifecycle
3. persistence
4. location authorization
5. route capture
6. mileage calculation
7. shift summaries
8. earnings input
9. shift history
10. analytics
11. delivery records
12. pickup wait measurement
13. geographic visualization
14. App Intents
15. Live Activities
16. repositioning recommendations
17. advanced prediction only when enough data exists
18. accessibility
19. performance
20. migration hardening

## Recommendations and prediction

Do not label basic heuristics as artificial intelligence.

Start with explainable calculations and historical statistics.

A recommendation should expose enough reasoning to understand why it was produced.

Examples:

* historical median wait
* historical earnings per active hour
* average idle duration
* distance required to reposition
* sample size
* confidence or insufficient-data state

Core ML should only be introduced when:

* sufficient training data exists
* there is a measurable prediction target
* a simpler statistical approach is insufficient
* evaluation methodology is defined

## Honest product claims

Repository-facing prose must accurately describe the application.

Do not claim:

* guaranteed increased earnings
* guaranteed mileage accuracy
* continuous location tracking guarantees
* tax compliance
* official DoorDash integration
* autonomous delivery decisions
* machine learning capabilities that are not implemented

Describe limitations explicitly where relevant.

## Definition of done

A feature is not complete merely because code was written.

It should normally include:

* integrated implementation
* appropriate failure handling
* appropriate tests
* successful relevant build
* documentation updates when needed
* coherent commit history
