# Testing

Tests exist to hold the claims this project makes. The rules that matter (a route never measured
across a gap, a missing amount never becoming zero, a running shift never deleted, an older store
never losing data) are each asserted somewhere that fails loudly.

## Two targets

| Target | Framework | Covers |
| --- | --- | --- |
| `DashPilotTests` | Swift Testing | Domain calculations, model invariants, services, persistence and migrations |
| `DashPilotUITests` | XCUITest | A small number of end-to-end journeys through the real interface |

The domain suite is where behaviour is proven. The UI journeys exist to catch the failures a unit
test cannot see, such as a screen that renders a sentence the model never claimed.

## Domain suites

| Suite | What it holds |
| --- | --- |
| Shift lifecycle, Shift service | Start, end, single-active-shift, clamped clocks, rollback, relaunch recovery |
| Persistence, Route sample persistence, Shift earnings persistence | Store round trips and the v1, v2 and v3 migrations |
| Location authorization state, Location authorization service | Condition precedence, accuracy independence, unrecognised values, request gating |
| Route capture, Route sample filter | The capture invariant and every acceptance rule |
| Route mileage | Segments, gaps, inferred continuity, unmeasurable routes |
| Money, Money input | Decimal arithmetic, rounding, division, and locale-aware parsing in more than one locale |
| Completed shift metrics, Shift metrics from the model | Both rates, every unavailable reason, precedence and precision |
| Route quality wording, Unavailable rate explanations | The exact sentences the interface is allowed to say |
| Completed shift deletion | Cascade, refusal for a running shift, and that a refused delete changes nothing |

Running one suite:

```bash
xcodebuild test \
  -project DashPilot.xcodeproj \
  -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DashPilotTests
```

## Testing seams

The seams exist because the alternative is an untestable claim, not because an abstraction looked
tidy.

**`ModelContainerFactory.makeContainer(at:)`** opens a store at an explicit URL. Tests use it to
close a store and reopen it, which is the only way to show that a running shift survives
termination; an in-memory store disappears with its container.

**`ModelContainerFactory.makeContainer(versionedSchema:at:)`** opens a store under a historical
version without the migration plan, so a test can write a store shaped the way an older build would
have left it. See [Migrations](../architecture/migrations.md).

**`StubLocationTrackingProvider`** (debug builds only) replaces Core Location's position updates and
nothing else. The capture pipeline has to be verifiable: that a good sample is retained, that a
duplicate, a stale fix, a wild jump or a sample from outside the shift window is not, and that
nothing at all is kept once a shift has ended. None of that can be demonstrated against a simulator
location feed, which delivers whatever it likes when it likes.

`LocationTrackingService` also takes its clock and its save batch size, so staleness and batching are
decided by the test rather than by how long the test took to run. The capture tests drive two
kilometres of route through a sixty-second backgrounding, which is shorter than the mileage gap
threshold, so only the recorded break in capture can exclude it, and then assert the distance is not
counted.

**`StubLocationAuthorizationProvider`** (debug builds only) satisfies `LocationAuthorizationProviding`
with caller-supplied state, so every authorization, accuracy and services combination is exercised
without the real permission database or a tapped system alert. It also counts permission requests,
which is how "asks exactly once, and only when the prompt can be shown" is verified.

**`MoneyInput` takes its `Locale`**, and the editor passes the environment's, so every parsing test
states the locale it is asserting about instead of inheriting the machine's region. The suites cover
a period locale and a comma locale side by side.

## Launch arguments

Debug builds accept two arguments, both used only by UI tests and screenshots:

| Argument | Effect |
| --- | --- |
| `-dashpilot-in-memory-store` | Starts from a known empty state, so a journey never writes into the store a real driver's history would live in |
| `-dashpilot-seeded-history` | Opens an in-memory store already holding synthetic history: one completed shift with an amount and a route recorded in two capture sessions, and one with neither |

A UI test cannot make a simulator record a route, so a measured, partial route and the
per-recorded-mile rate over it would otherwise be unreachable end to end. The fixture is invented
amounts and offsets from a round-number origin, the same data `SyntheticRoute` builds for the unit
tests.

The seeded-history path is app code that exists only for tests. It is DEBUG-only and in-memory, and
it is one more launch path to keep honest.

## UI journeys

The UI target covers a handful of paths: launching, starting and ending a shift, opening a completed
shift, adding and editing an amount, reading the detail screen's route and rate statements, and
deleting a shift through its confirmation.

The permission panel is asserted only to be on screen. Which state it displays depends on the
device, and no test drives the system alert, because automating it would be brittle and would change
the permission state other tests run against.

Two lessons are worth repeating when adding journeys:

- A `List` only renders rows near the viewport, so anything below the fold does not exist until it
  is scrolled to.
- SwiftUI mirrors an `accessibilityIdentifier` onto a button's label element as well, so an alert
  button matches twice. Use `.firstMatch`.

## Continuous integration

`ci.yml` runs on pull requests and pushes to `main`, on a GitHub-hosted `macos-26` runner, with
`contents: read` and nothing more. Obsolete runs on the same ref are cancelled through a concurrency
group.

The workflow does four things in order:

1. **Selects an Xcode.** It reads `IPHONEOS_DEPLOYMENT_TARGET` out of the project and picks the
   newest installed Xcode whose iOS simulator SDK is at least that version, rather than hardcoding
   one. If none qualifies, it fails with a message naming what it found.
2. **Prints tool versions**, so a failure can be read against the exact toolchain that produced it.
3. **Selects a simulator.** It queries `simctl` for available iPhone simulators on runtimes at or
   above the deployment target and uses the newest, by UDID. `iPhone 17` exists on today's runner
   image, but the workflow does not depend on that.
4. **Builds and tests.** One `build-for-testing` produces the app and both test bundles; two
   `test-without-building` steps then run the domain suite and the UI journeys separately.

Both test targets run in CI. The split into two steps is deliberate and visible: XCUITest under a
virtualised simulator is the part most likely to fail for reasons that are not the code, so a red
run says which kind of failure it was rather than reporting "tests failed". Nothing is excluded, and
no test is retried to make a run pass.

!!! warning "Known flakiness"

    Under parallel simulator load, XCUITest has been observed locally failing with
    `Failed to get matching snapshot(s): Error getting main window kAXErrorServerNotFound`, an
    accessibility-server failure rather than an assertion. Re-running the UI target alone has been
    green every time. If this proves reproducible on GitHub-hosted runners, the honest fix is to
    move the UI journeys into a clearly named separate job, not to drop them.

The documentation workflows are described under [Building](building.md#continuous-integration).
