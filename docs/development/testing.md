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
| Delivery lifecycle, Delivery service | Every transition and refusal, concurrent deliveries and their isolation, deterministic ordering and numbering, clamped clocks, the shift-end policy and cascade |
| Delivery persistence | The v4 to v5 migration, and several active deliveries recovered independently from a reopened store |
| Pickup place name | The normalisation policy: what is folded, and what is conservatively left alone |
| Pickup place service | Reuse of an equivalent name, the first-spelling-wins policy, assign, change, remove, recent ordering, and deletion sparing a shared place |
| Pickup place persistence | The v5 to v6 migration, a shared place surviving a reopened store, a place's wait metrics being identical either side of a reopen, and a rename and a merge each surviving one |
| Delivery earnings, Delivery earnings service, Delivery earnings input | The terminal-only and non-negative rules, a cancelled delivery allowed an amount, missing distinct from zero, the shared parser reaching a delivery, and a refused save rolled back to what the store holds |
| Delivery and shift earnings are independent | Neither amount moving when the other changes, delivery amounts allowed to fall short of or exceed the shift total, either allowed to exist alone, and recorded, missing and explicit zero staying three distinguishable states |
| Stacked delivery earnings | Two overlapping deliveries holding independent amounts, editing or removing one leaving the other, and each rate dividing by its own duration only |
| Gross per recorded delivery hour | A delivered delivery's own rate, zero earnings, missing earnings, a zero duration, a cancelled delivery, and rounding identical to the shift's hourly rates |
| Delivery earnings persistence | The v6 to v7 migration, every earlier version reaching v7, a shift total never divided among its deliveries, and amounts surviving a reopened store including an explicit zero |
| Pickup place rename | The normalisation it reuses, case-only and Unicode renames, empty and oversized input refused, a collision refused without moving a delivery, and identity, waits and recency all unchanged |
| Pickup place merge | Deliveries moved, the destination unchanged, the source removed only after success, self-merge and stale models refused, empty, cancelled and active sources, and a refused save rolled back in full |
| Pickup wait history after a merge, Recent places after a merge | Two histories becoming one, a recomputed median, exclusions still excluded, no duplicated sample, nothing written to the store, and recency following the reassigned deliveries |
| Pickup wait samples | Which lifecycles yield a wait: both ends present and in order, and the cancelled-before-pickup and cancelled-after-pickup rules |
| Pickup wait median | Zero, one, two, odd and even counts, unsorted input, repeats, an exact fractional midpoint, a long wait retained, and a hundred samples |
| Pickup wait aggregation by place | Isolation between places, a place reused across shifts, deliveries excluded for naming no place or recording no pickup, and that nothing is written back |
| Pickup wait history wording | What may be said at each sample count, and the words no history may use at any |
| Delivery wording | The one action each state offers, its spoken label, and the delivery counts |
| Location authorization state, Location authorization service | Condition precedence, accuracy independence, unrecognised values, request gating |
| Route capture, Route sample filter | The capture invariant and every acceptance rule |
| Route mileage | Segments, gaps, inferred continuity, unmeasurable routes |
| Money, Money input | Decimal arithmetic, rounding, division, and locale-aware parsing in more than one locale |
| Completed shift metrics, Shift metrics from the model | All three rates, non-delivery time, every unavailable reason, precedence and precision |
| Delivery active time, Delivery active time of a shift | The interval union — overlap, nesting, chains, touching, shared starts and ends, zero length, malformed, unfinished, unsorted, a thousand at a time — order independence over every permutation, clipping to the shift window, and cancelled deliveries counting until cancellation |
| Route quality wording, Unavailable rate explanations | The exact sentences the interface is allowed to say |
| Completed shift deletion | Cascade, refusal for a running shift, and that a refused delete changes nothing |
| Shift export records | A completed shift's facts mapped, a running shift refused, missing amounts still missing and explicit zero still zero, shift and delivery earnings independent with no reconciliation field in the file, lifecycle timestamps and cancellations preserved, a pickup place only where recorded, the wait matching the domain, active time unioned rather than summed, and every route state kept apart |
| Shift export JSON | The format version and its distinctness from the schema version, sorted keys giving identical bytes, explicit nulls, decimal-string money round-tripping exactly for the amounts a double loses, ISO 8601 timestamps, Unicode names, and a whole document decoded back unchanged. Period summaries keep every paired coverage count, including a rate no shift could contribute to |
| Shift export CSV | One row per delivery and a row for a shift with none, empty cells for missing values, an explicit zero written, route partiality as its own columns, and the period summary deliberately absent. Parsed by an independent RFC 4180 reader, so a round trip through the writer cannot prove itself |
| CSV field quoting, CSV spreadsheet safety, CSV records | Commas, quotes, CRLF, edge whitespace and Unicode; the formula guard for `=`, `+`, `-`, `@`, tab and CR, asserted both in the file and after a parser strips the quotes; and that nothing DashPilot generates is altered by it |
| Shift export service | Every scope, an overnight shift counted once, empty scopes and running shifts refused, file names and their absence of content, exports replacing rather than accumulating, an existing file never overwritten, a write failure surfaced, and errors that name no path |
| Shift export privacy | No coordinate in either format, the route reduced to a measurement and its coverage, no normalised pickup key, no catalogue bookkeeping and no store internals |
| Expense record | What an expense accepts and refuses, a recorded zero distinct from none, an edit replacing every fact at once and a refused edit changing nothing, the note's trimming and length rule counted in characters, the closed category set and its stored words, no category implying a tax treatment, and an unrecognised stored word reading as `other` |
| Period expenses | Totals and category subtotals, missing distinct from an explicit zero, membership by the expense's own timestamp across a half-open boundary and a 23-hour day, a month totalled from its own records, a day holding costs but no shift, the net's two refusals and its negative case, the gross figures unchanged by any of it, no coverage pair invented for expenses, and the words the net may and may not use |
| Expense persistence | The v7 to v8 migration with every earlier record intact and no expense fabricated from mileage or earnings, the plan's version and stage counts asserted here once, an expense with no relationship to a shift, a round trip through a reopened store, deleting a shift leaving expenses alone, and the service's refusals |
| Expense export | Expenses selected by their own dates, none in a single shift's file, a period of costs alone exported rather than refused, the summary's totals and net, the JSON key set and its explicit nulls, a round trip, the CSV unchanged at 32 columns with no expense in it, and the format version deliberately unmoved |

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

Debug builds accept five arguments, all used only by UI tests and screenshots:

| Argument | Effect |
| --- | --- |
| `-dashpilot-in-memory-store` | Starts from a known empty state, so a journey never writes into the store a real driver's history would live in |
| `-dashpilot-seeded-history` | Opens an in-memory store already holding synthetic history: one completed shift with an amount, a route recorded in two capture sessions and three deliveries (two delivered, one cancelled), and one shift with none of those |
| `-dashpilot-seeded-active-delivery` | Opens an in-memory store holding a running shift whose delivery has already been picked up, which is the state a relaunch recovers into |
| `-dashpilot-seeded-pickup-history` | Opens an in-memory store holding one completed shift whose deliveries give two pickup places deliberately different amounts of recorded history |
| `-dashpilot-seeded-period-summary` | Opens an in-memory store holding a week of synthetic completed shifts and three synthetic expenses, anchored to today rather than to a fixed instant, so the period summary opens on a period that holds something |

A UI test cannot make a simulator record a route, so a measured, partial route and the
per-recorded-mile rate over it would otherwise be unreachable end to end. Nor can it terminate and
reopen the in-memory store the other journeys use, so an already-running delivery is seeded at
launch instead; that the *store* recovers one is proved against a real reopened store in
`DeliveryPersistenceTests`. The fixture is invented
amounts and offsets from a round-number origin, the same data `SyntheticRoute` builds for the unit
tests.

Pickup-wait history needs its own fixture rather than a fourth delivery on the general one: the
seeded history's three deliveries are pinned by the journeys asserting exact active-time and rate
figures over them. Its own shift gives one place three recorded waits including a long one, another
place exactly one, a delivery that arrived and cancelled without picking up, and a delivery naming no
place at all — so a median, a sample count, the insufficient-history wording and the absence of any
history are all reachable end to end.

The general seeded history also gives two of its three deliveries an invented amount and leaves the
third with none, so a recorded amount, a delivery with none, and a per-delivery hourly figure are all
reachable without typing — and so is the claim that editing one delivery's amount leaves the other
delivery and the shift total alone. The amounts deliberately do not add up to the shift's `$86.25`,
because nothing reconciles them.

The period-summary fixture is the only one anchored to **today**: the summary shows the period the
driver is actually in, so a fixture pinned to a fixed instant would open on an empty one. Its
offsets stay fixed and only the anchor moves. Its three expenses are dated rather than attached to
its shifts, which is what makes a recorded total, a category split and a net after recorded expenses
reachable end to end without typing.

The seeded paths are app code that exists only for tests. They are DEBUG-only and in-memory, and
they are four more launch paths to keep honest.

## UI journeys

The UI target covers a handful of paths: launching, starting and ending a shift, recording a
delivery through its whole lifecycle, cancelling one, being refused a shift end while a delivery is
running, recovering an already-running delivery at launch, opening a completed shift, adding and
editing a shift's amount, adding, editing, cancelling an edit of and removing one delivery's amount,
two stacked deliveries keeping independent amounts while the shift total stays untouched, reading the
detail screen's delivery, route and rate statements, opening a pickup place's recorded wait history,
renaming a place and being refused a colliding rename, merging two places into one history,
exporting a shift as JSON and as CSV, exporting a selected day and week, an empty period offering no
export, exporting all history, a running shift offering none, switching between the four period
lengths, stepping back to an empty month, being refused a step past the current month, choosing and
applying a custom date range, cancelling that sheet without changing the period, a chosen range
surviving a switch to another period length, exporting a month and a chosen range, recording an
expense and finding it in the list, being refused a negative one, editing and deleting one, reading a
period's recorded costs, its categories and the net after them, that net never calling itself profit,
gross earnings unchanged beside it, an expense recorded on a day with no shift still being
summarised, and deleting a shift through its confirmation.

The share sheet itself is never opened. `ShareLink` presents a system surface XCUITest cannot inspect
reliably, and what the export journeys are for is proving DashPilot wrote a file and offered it — not
that iOS can share one. The file's name and the count of shifts in it are read off the sheet
instead.

The permission panel is asserted only to be on screen. Which state it displays depends on the
device, and no test drives the system alert, because automating it would be brittle and would change
the permission state other tests run against.

Two lessons are worth repeating when adding journeys:

- A `List` only renders rows near the viewport, so anything below the fold does not exist until it
  is scrolled to. This bites again whenever a section above grows: adding one sentence to the
  earnings footer pushed the route section off the first screen and failed two journeys that had
  been reading it without scrolling.
- SwiftUI mirrors an `accessibilityIdentifier` onto a button's label element as well, so an alert
  button matches twice. Use `.firstMatch`.
- A `.sheet` attached to a conditionally rendered section goes away with the section. The period
  summary rebuilds its sections whenever it re-measures routes, which dismissed the export sheet
  before it had written anything; the modifier belongs on the `List`.

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
