# Project structure

```text
DashPilot/
  App/            SwiftUI entry point, root screen, delivery controls, editors, shift detail, failure state, preview fixtures
  Domain/         Framework-independent value types and calculations
  Export/         The external file contract: export records, encoders, file writing
  Intents/        App Intents: the six lifecycle actions performable with no screen
  Models/         SwiftData @Model types
  Persistence/    Versioned schema, migration plan, container construction
  Services/       Application services that own state transitions, and platform adapters
  Support/        Cross-cutting utilities: logging and launch arguments
DashPilotActivity/ Value types shared by the app and the widget extension: the Live Activity snapshot,
                   its control vocabulary and its four intent declarations
DashPilotWidgets/ The widget extension: the Live Activity's Lock Screen and Dynamic Island views
DashPilotTests/   Swift Testing suites
DashPilotUITests/ XCUITest journeys
docs/             This documentation site
.github/workflows CI, documentation validation and Pages deployment
```

## Where a new file goes

| If it | Put it in |
| --- | --- |
| Is a calculation or a value type with no framework imports | `Domain/` |
| Is persisted | `Models/`, and add a schema version |
| Owns a state transition or talks to a platform framework | `Services/` |
| Is part of the exported file contract | `Export/` |
| Is an App Intent, or the wording one says back | `Intents/` |
| Is drawn on the Lock Screen or in the Dynamic Island | `DashPilotWidgets/` |
| Has to be understood by the app **and** the widget extension | `DashPilotActivity/` |
| Is a screen or part of one | `App/` |
| Is logging, a launch argument or similar plumbing | `Support/` |

Domain types must not import SwiftUI or SwiftData. That is what makes every calculation testable
without a container or a rendered view, and it is the constraint that keeps wording, filtering and
measurement out of view bodies.

`Intents/` is a layer with a rule of its own too: **it owns no lifecycle logic.** The intents call
`IntentLifecycleService`, which calls `ShiftService` and `DeliveryService` and adds only the rule
about which delivery a spoken step meant. A rule written there that disagreed with the app would make
the app wrong by voice and right by tap, so there is no rule there to disagree with. See
[Voice and system actions](../product/voice-actions.md).

`DashPilotActivity/` is compiled into the app **and** into the widget extension, which is how
ActivityKit matches what one requests to what the other draws. It holds value types only: no
SwiftData, no services, and nothing that would drag the model layer into the extension. A
`LiveActivityIntent` is performed in the app's process, so the extension compiles the intent
declarations and a body that cannot run, and refuses if it somehow does, rather than a body that
would report success having written nothing.

`DashPilotWidgets/` is a renderer, and that is the whole of its rule. It has no store, no services
and no lifecycle logic: which controls a shift may offer is decided by the app from the shift's own
rows, and pressing one runs `IntentLifecycleService`. A second copy of a lifecycle rule compiled into
the extension is exactly the drift this project designs against. See
[The shift on the Lock Screen](../product/live-activity.md).

`Export/` is a layer rather than a folder of helpers, and it has one rule of its own: **no SwiftData
model is ever encoded.** A file a driver keeps must not be tied to the store's shape, so the records,
the encoders and the CSV writer are plain values, and exactly one type — `ShiftExportService` —
fetches, measures and adapts models into them. `ExportDocumentEncoder` never touches a context, and
no view builds a CSV string. See [History export](../product/history-export.md).

## Naming and conventions

- Views are nouns describing what they show (`CompletedShiftDetailView`, `RouteCaptureStatusView`).
- A service owns transitions, not data (`ShiftService`, `DeliveryService`, `LocationTrackingService`).
- A "Providing" protocol is a seam over a platform framework, and its Core Location implementation
  is the only file on that side allowed to import it.
- Vocabulary the interface says out loud lives in a tested domain type (`RouteQuality`,
  `ShiftRateUnavailability`, `DeliveryAction`, `DeliverySummary`, `PickupWaitMetrics`,
  `ExpenseCategory`), never as strings in a view. The phrase *net after recorded expenses* and the
  caution under it are `PeriodMetrics` wording for the same reason: a figure's name is a claim, and
  the words a period may be compared in — *more recorded*, *less recorded*, and every reason a
  percentage is withheld — are `PeriodComparison` wording rather than strings in the summary.
  `DurationText` holds the one rule for writing and speaking a duration, so the shift, delivery and
  pickup-place surfaces cannot drift apart. `IntentLifecycleOutcome` holds what a voice surface says
  back, for the same reason and with more at stake: it is the driver's only report of what was
  recorded.

## Repository conventions

Branches are narrow and prefixed: `feat/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`.

Commits use the matching conventional prefixes and represent coherent changes. Work proceeds in
bounded intervals, each covering one capability, ending with tests, a build, a reviewed diff and a
commit. `CLAUDE.md` and `AGENTS.md` in the repository root hold the full working agreement for
contributors and coding agents.

## Files that are not in Git

| Path | Why |
| --- | --- |
| `context.md` | The owner's local working notes: temporary decisions, current priorities and local observations |
| `site/` | Generated by `mkdocs build` |
| `.venv/` | A local Python environment for the documentation toolchain |
| `xcuserdata/`, `.DS_Store` | Per-user Xcode and macOS noise |

Nothing derived from a real drive, a real amount or a real address is ever committed. See
[Privacy and logging](../architecture/privacy.md).
