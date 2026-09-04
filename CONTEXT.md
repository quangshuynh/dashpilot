# DashPilot Local Context

## Current objective

Build DashPilot incrementally as a serious native iOS portfolio project and a tool I can personally use while doing delivery work.

## Current development phase

Foundation.

Do not jump directly into prediction, Core ML, complicated maps, or optimization algorithms.

First establish reliable shift, persistence, location, mileage, and earnings primitives.

## Product goal

Reduce the amount of manual bookkeeping required during delivery shifts.

The application should gradually automate everything that can legitimately and reliably be derived from:

- device location
- timestamps
- motion
- stored shift history
- user-defined preferences

Interactions should be minimized while driving.

## Primary workflow target

Eventually:

1. Open DashPilot.
2. Tap Start Shift.
3. DashPilot records the shift.
4. Location and time collection occur automatically where iOS permits.
5. The driver performs delivery work in their normal delivery app.
6. Minimal manual input is used for information DashPilot cannot legitimately obtain automatically.
7. Tap End Shift.
8. DashPilot produces a useful shift summary.
9. Historical data improves future recommendations.

## Initial milestones

### Milestone 1
Project foundation and basic architecture.

### Milestone 2
Shift lifecycle:
- start
- active
- end
- persisted history

### Milestone 3
Location permission and tracking service.

### Milestone 4
Route sample persistence and mileage calculation.

### Milestone 5
Shift summary:
- duration
- distance
- earnings
- earnings per hour
- earnings per mile

### Milestone 6
Historical shift browser.

### Milestone 7
Delivery records and pickup wait tracking.

### Milestone 8
Location analytics and MapKit visualization.

### Milestone 9
App Intents and Live Activity.

### Milestone 10
Explainable repositioning recommendations.

Do not build all milestones at once.

## Architectural preferences

Keep the project native and understandable.

Preferred:
- SwiftUI
- SwiftData
- Apple frameworks
- testable domain services
- explicit state
- dependency injection where useful
- local persistence
- OSLog
- Swift Testing

Avoid:
- unnecessary packages
- backend
- account system
- analytics
- telemetry
- ads
- speculative protocols
- giant manager classes

## Git preferences

Claude and other coding agents may:
- create branches automatically
- switch branches automatically
- create commits automatically

They may not:
- push
- merge main
- force push
- tag
- release
- create pull requests

without explicit instruction.

I want development performed in intervals.

At the end of each interval:
- build
- test
- inspect diff
- commit
- summarize
- stop

## Repository presentation

Treat this as a real engineering project, not a tutorial project.

README and portfolio language should emphasize concrete implementation and engineering decisions.

Do not inflate claims.

Do not describe planned functionality as completed functionality.

## Delivery platform restriction

Do not implement unauthorized DoorDash integration.

No:
- scraping
- credentials
- reverse engineering
- private API use
- automated accepting
- automated declining
- controlling the Dasher application

The project should remain useful across delivery platforms.

## Privacy

Never commit personal routes, earnings, customer information, or exact private location history.

Synthetic data only in the repository.