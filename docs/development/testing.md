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
| Shift Live Activity content | What the shift's Lock Screen card is told, pinned to the app's own figures and wording: working rather than elapsed time, `RouteQuality`'s mileage sentence, the partial marker travelling with the figure, the lifecycle titles, and every delivery step named exactly as the app's own control names it. The controls are asserted against the refusals the services actually raise rather than against a list written in the test, and a sweep checks everything the card can print for an amount, a rate, a place name or a coordinate. The delivery clocks are pinned the same way: each counted from its own `acceptedAt` and named by the app's own numbering, an anchor that does not move as the snapshot is rebuilt, a delivered, cancelled or reopened delivery leaving or rejoining the list rather than freezing, two stacked orders counted separately and never as their sum, the remainder stated past three, and the control list unchanged in every shape |
| Shift Live Activity synchronisation | A shift driven from running through paused, resumed and ended as one card and then none, plus what a Lock Screen makes invisible: a relaunch adopting the card its shift already has, a card left behind by a shift that is gone, one describing a different shift, one the driver dismissed, a system that refuses the request, and Live Activities turned off entirely |
| Shift Live Activity update policy | The cadence, including the one that matters most: time passing is not a change, because the card's anchor has not moved and the system is already drawing the right clock. The delivery clocks follow the same rule and add one case: an order finishing as another is accepted moves no count on the card, so the list of anchors is compared directly |
| Shift lifecycle, Shift service | Start, end, single-active-shift, clamped clocks, rollback, relaunch recovery |
| Shift pause domain | The union of a shift's pauses: overlap, touching, order independence, clipping to the shift, a malformed row counted rather than dropped, and an open pause measured to the moment it is read at, so working time stops growing. Plus working duration never going negative, and the three lifecycle states |
| Shift pause service | Pause, resume, the refusals for each, the delivery rule in both directions, ending a paused shift closing its pause at the end time, a clock that moved backwards still letting a shift be ended, and a refused pause leaving the store untouched |
| Shift pause persistence | The v8 to v9 migration with every shift's duration unchanged and nothing read as a break, the schema shape asserting a relationship rather than a paused flag, the plan's version and stage counts asserted here once, a paused shift recovered from a reopened store by the unchanged unfinished-shift query, and deletion cascading to pauses |
| Shift pause correction | The rules a proposed correction is checked against, with no store: the bounds, positive length, touching allowed and overlapping refused for another pause and for delivery work, an open or malformed stored row blocking nothing because it measures nothing, and every refusal having a sentence that says what would make the stretch acceptable |
| Shift pause correction service | The three writes through the store and mostly what must not move: a start, an end and both together, deletion renumbering nothing it should not, a missed pause added without making the shift paused, the running-shift and open-pause refusals, an overlap refused rather than merged, a delivery kept rather than shortened, elapsed time, delivery active time, mileage, route sessions and both amounts unchanged, the period's working hours and rate following, a pre-existing overlap still unioned and a malformed row repairable, three refused saves read back through a fresh context, the export carrying it through the fields it already had at format version 3, and three daylight-saving cases measured in real seconds |
| Shift pause metrics, reporting and export | The hourly rate dividing by working time, a break not lowering it, a shift paused throughout having no rate rather than a rate of zero, delivery active time unchanged while non-delivery time moves inside working time, the period total and its rate, the comparison's working-time row, and the three exported duration fields with zero meaning measured |
| Persistence, Route sample persistence, Shift earnings persistence | Store round trips and the v1, v2 and v3 migrations |
| Delivery lifecycle, Delivery service | Every transition and refusal, concurrent deliveries and their isolation, deterministic ordering and numbering, clamped clocks, the shift-end policy and cascade |
| Delivery persistence | The v4 to v5 migration, and several active deliveries recovered independently from a reopened store |
| Pickup place name | The normalisation policy: what is folded, and what is conservatively left alone |
| Pickup place service | Reuse of an equivalent name, the first-spelling-wins policy, assign, change, remove, recent ordering, and deletion sparing a shared place |
| Pickup place persistence | The v5 to v6 migration, a shared place surviving a reopened store, a place's wait metrics being identical either side of a reopen, and a rename and a merge each surviving one |
| Delivery earnings, Delivery earnings service, Delivery earnings input | The terminal-only and non-negative rules, a cancelled delivery allowed an amount, missing distinct from zero, the shared parser reaching a delivery, and a refused save rolled back to what the store holds |
| Delivery and shift earnings are independent | Neither amount moving when the other changes, delivery amounts allowed to fall short of or exceed the shift total, either allowed to exist alone, and recorded, missing and explicit zero staying three distinguishable states |
| Stacked delivery earnings | Two overlapping deliveries holding independent amounts, editing or removing one leaving the other, and each rate dividing by its own duration only |
| Earned per recorded delivery hour | A delivered delivery's own rate, zero earnings, missing earnings, a zero duration, a cancelled delivery, a delivery still running, rounding identical to the shift's hourly rates, recording and then correcting and removing a tip each moving the figure at once, and an expectation contributing nothing to a rate that exists or to one that does not |
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
| History weeks | The week History is scoped to, and the split that decides which screen a shift is drawn on: a week starting on Monday whatever the device's own first weekday is, Sunday closing the working week rather than opening the next one, a shift at Monday midnight in the week beginning, a week across New Year and one across a daylight-saving change, the time zone deciding which week a moment is in, older shifts grouped newest week first with two in one week under one heading and an unworked week absent rather than empty, a current week present but empty, the Monday transition moving a shift between the two sides, a shift dated after this week still listed rather than hidden, every shift claimed by exactly one side, and the wording following the Monday week rather than the device's |
| Period comparison | The span a period is compared against — a calendar unit back, a month keeping its own length, an equal-length range before a chosen one, whole days across a daylight saving change, and a chosen range still having no selection to step to — then the comparison itself: two period results and never an average of the periods inside them, a missing figure subtracted from nothing, the five reasons a percentage is withheld, expenses never carrying one, coverage printed for both sides, differing lengths stated rather than scaled, non-neighbouring periods refused, and the words a change may be described in |
| Period expenses | Totals and category subtotals, missing distinct from an explicit zero, membership by the expense's own timestamp across a half-open boundary and a 23-hour day, a month totalled from its own records, a day holding costs but no shift, the net's two refusals and its negative case, the gross figures unchanged by any of it, no coverage pair invented for expenses, and the words the net may and may not use |
| Expense persistence | The v7 to v8 migration with every earlier record intact and no expense fabricated from mileage or earnings, the plan's version and stage counts asserted here once, an expense with no relationship to a shift, a round trip through a reopened store, deleting a shift leaving expenses alone, and the service's refusals |
| Intent lifecycle service | Every action performed off screen: the shift and delivery refusals carried through unchanged, a step recorded only while exactly one delivery is in progress, the refusal naming two and three, neither delivery moving under it, the refusal lifting once one remains, a cancelled delivery neither reachable nor counted, and no amount, place or cancellation reachable at all |
| App intents | The six intents performed end to end against a throwaway store, the ambiguous step recording nothing, and the metadata the system reads: no intent opening the app, every one runnable on a locked device, and each carrying a title and a description that states its rule |
| Intent wording | What a driver hears back: the recorded event named as history names it, the route caution on every shift start, an unknown number left out rather than invented, no figure claimed in any sentence, and a refusal repeating the service's own words rather than a second version of them |
| Delivery grouping | An offer's shape and its wording: an offer of one and of several, the refusals below one delivery and on an ended shift, siblings advancing independently, an offer terminal only once every delivery is, cancellation per delivery with the wholly cancelled and partly completed cases apart, the empty offer deliberately not complete, shift-wide numbering beside the `Offer 1` label, the spoken grouping naming the siblings, and a screen's cards arranged by offer including a delivery that records none |
| Delivery offer service | One tap recording one delivery in an offer of one, a grouped offer recorded in one write, an add-on offer staying its own, offers overlapping without merging, siblings at different lifecycle points, completing one leaving the rest, amounts staying on the delivery they were recorded against, and a refused save leaving neither the offer nor any of its deliveries while an earlier offer stays whole |
| Delivery offer persistence | The v11 to v12 custom migration giving every historical delivery a one-delivery offer of its own, including two accepted a second apart that end up in two offers; the plan's version and stage counts asserted here once; the frozen v11 shape holding no offer; every figure a migrated shift reports unmoved; a grouped offer surviving a reopened store with one delivery still running; deletion cascading to offers; and a rollback leaving no delivery pointing at a discarded offer, read through a fresh context |
| Delivery offer surfaces | The negative claims, gathered: active time unioned identically whether two overlapping deliveries share an offer or not, unioned across offers, the Live Activity counting deliveries rather than offers and withholding the step within an offer exactly as it does across two, the card carrying no offer wording, an intent's Start Delivery recording one delivery in an offer of one, and a spoken step refused over a grouped offer without moving either delivery |
| Delivery offer export | The grouping key on each delivery in both forms, no offer object or total anywhere, an explicit null for a delivery recording none, the CSV column appended so no existing column moves, an empty cell rather than a zero, and the format version unmoved by offers |
| Delivery additional tips | The arithmetic of platform pay plus tips, exact to the cent; a missing platform amount having no total while the tips it holds are still stated; a tip of nothing and a negative one refused where a recorded gross of zero is still allowed; an active delivery refused and a cancelled one allowed; several tips staying several records, including two of identical amount; a correction moving neither the moment nor a sibling; the platform amount never touched; an expectation untouched and counted by nothing; and the wording, including an unrecognised method spoken as one rather than as either |
| Delivery additional tip service | Recording, correcting and removing a tip through the store, each read back through a fresh context; three refused saves leaving exactly what the store already held; a finished shift being where a tip is recorded rather than a refusal; deleting a shift cascading through its deliveries to their tips; and both delivery corrections keeping every tip on a delivery they leave terminal or reopen |
| Delivery tip metrics | The delivery's own rate dividing what it actually paid rather than the platform amount alone, reading every recorded tip rather than the first or the largest, and having no rate at all when that amount is missing; the shift's list and the period's subtotal reading effective earnings; coverage unmoved, so a delivery holding only tips still counts as uncovered; and no shift rate moving, because those divide the shift's own amount |
| Delivery tip persistence | The v12 to v13 lightweight step with every migrated delivery holding no tip and reporting exactly the figures a v12 build reported; the plan's version and stage counts asserted here once; the frozen v12 shape holding no tip; and tips surviving a reopened store with their methods and moments |
| Delivery tip export | Each tip as its own JSON record with its method and moment, an empty array rather than a missing key, `grossEarnings` meaning exactly what it always did, no total where the platform amount is missing, the renamed per-delivery rate, the period subtotal following, the three appended CSV columns leaving every existing one where it was, no individual tip amount or method reaching the CSV, and the format version at 4 |
| Offer correction | The rules the model owns: the ordering rule an offer keeps, a move that leaves both acceptance timestamps where they were, refusals for an offer accepted later, another shift's offer and the offer a delivery is already in, the offer left behind returned rather than emptied here, a regrouped offer taking the earliest acceptance among its deliveries, regrouping allowed on a finished shift where recording new work is not, numbering renumbering what a removed offer leaves, and every confirmation sentence including the one that says an offer is removed and the sweep proving none of them carries an identifier |
| Offer correction service | The four corrections as the store applies them: a move leaving both offers standing, a move out of a two-delivery offer leaving its sibling, the last delivery leaving removing the emptied offer read through a fresh store, a split of one and of several, a split of every delivery refused as the no-op it is, deliveries from two offers refused in one operation, a merge moving every delivery and removing the source without taking a delivery with it, the wrong merge direction refused before anything moves with the truthful direction then working, separating a grouped offer, and rollbacks during a move, a split and a merge each read through a fresh context |
| Offer correction invariance | What must not move: every lifecycle timestamp, pickup place, amount and terminal state on an active and a terminal delivery under all four corrections; shift gross, delivery gross, the three rates, the active-time union and the delivery summary; the Live Activity's active count and its withheld step; pickup waits and their per-place samples; a period's whole `PeriodMetrics`; the export's `offerNumber` following the grouping while every other field and the format version stay put; renumbering after a merge; the one-tap Start Delivery path; a migrated one-delivery offer as both subject and destination; and an offer holding no deliveries read, offered and merged away without taking a delivery with it |
| Delivery recovery | The rule a reopening applies before anything is written: the state each remaining chain of timestamps restores, a completion recorded straight from an arrival taken back while a pickup with no arrival is refused, a cancellation and a second invocation each refused with their own case, contradictory times refused rather than blessed, and every confirmation sentence naming its subject and carrying no identifier, timestamp or amount |
| Delivery recovery service | Reopening through the store: one timestamp removed and the rest asserted unchanged, the money and the expectation preserved, the ended-shift and paused-shift refusals, and a refused save leaving the delivery delivered read through a fresh context |
| Historical delivery cancellation | The rule a historical correction applies before anything is written: the recorded completion reused as the cancellation to the instant, a delivery still in progress and one already cancelled each refused with their own case, contradictory times refused rather than blessed, the model moving one timestamp to the other with every earlier event asserted as a value, both amounts preserved, the offer re-derived for each mix of cancelled and delivered children, and every confirmation sentence naming its subject while saying nothing about editing and carrying no figure |
| Historical delivery cancellation service | The correction through the store, and mostly what must not move: the shift staying ended with nothing in progress, the active-time union, working duration, mileage, recorded pickup wait and whole period metrics unchanged, delivery-earnings coverage unable to outnumber its eligible records, the running-shift and paused-shift refusals sending the driver to the reopening instead, a second invocation writing nothing, route capture and the Live Activity both left alone, a refused save leaving the delivery delivered read through a fresh context, and JSON and CSV carrying the correction through fields they already had at format version 3 |
| Historical delivery recovery investigation | Evidence for a refusal, not a specification. Builds the row the services refuse to create (a completed shift holding a reopened delivery) and measures what every existing reader does with it: the delivery stuck beyond finishing, cancelling or reopening; the shift's end, route capture and Live Activity all correctly untouched; delivery active time unmeasurable alone and silently short beside a sibling; the offer permanently in progress; a finished period reporting work in progress and printing more delivery-earnings contributors than eligible records; and an export written rather than refused, carrying an active state and a shift whose two counts no longer reach its delivery count |
| Expense export | Expenses selected by their own dates, none in a single shift's file, a period of costs alone exported rather than refused, the summary's totals and net, the JSON key set and its explicit nulls, a round trip, the CSV carrying no expense whatever its column count, and expenses adding one top-level key without redefining any |

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

**`IntentLifecycleService.testContext`** (debug builds only) is the store the App Intents perform
against when a test sets one. An intent is created by the system with no arguments, so there is
nowhere for a test to hand it a context, and without the seam the only store a `perform()` could
reach is the device's own. The suite that uses it is serialised, and a shipped intent has exactly one
store it can reach.

**`StubLocationTrackingProvider`** (debug builds only) replaces Core Location's position updates and
nothing else. The capture pipeline has to be verifiable: that a good sample is retained, that a
duplicate, a stale fix, a wild jump or a sample from outside the shift window is not, and that
nothing at all is kept once a shift has ended. None of that can be demonstrated against a simulator
location feed, which delivers whatever it likes when it likes.

`LocationTrackingService` also takes its clock and its save batch size, so staleness and batching are
decided by the test rather than by how long the test took to run.

The stub also reports whether the build may keep updates running off screen, which is settable, and
that is what makes both halves of the background behaviour provable. With it on, a route driven
through a backgrounding is one capture session and its distance is counted, because it was recorded.
With it off, the capture tests drive two kilometres through a sixty-second interruption that is
shorter than the mileage gap threshold, so only the recorded break in capture can exclude it, and
then assert the distance is not counted.

`RealWorldRecoveryTests` reads the app bundle a hosted unit test runs inside, which is how the
shipped capability itself is asserted: the location background mode is declared and is the only one,
and neither Always usage description exists, which is the structural reason the app cannot ask for
that scope whatever its code does.

**`StubLocationAuthorizationProvider`** (debug builds only) satisfies `LocationAuthorizationProviding`
with caller-supplied state, so every authorization, accuracy and services combination is exercised
without the real permission database or a tapped system alert. It also counts permission requests,
which is how "asks exactly once, and only when the prompt can be shown" is verified.

**`MoneyInput` takes its `Locale`**, and the editor passes the environment's, so every parsing test
states the locale it is asserting about instead of inheriting the machine's region. The suites cover
a period locale and a comma locale side by side.

## Launch arguments

Debug builds accept twelve arguments, all used only by UI tests and screenshots:

| Argument | Effect |
| --- | --- |
| `-dashpilot-in-memory-store` | Starts from a known empty state, so a journey never writes into the store a real driver's history would live in |
| `-dashpilot-seeded-history` | Opens an in-memory store already holding synthetic history: one completed shift with an amount, a route recorded in two capture sessions and three deliveries (two delivered, one cancelled), and one shift with none of those |
| `-dashpilot-seeded-active-delivery` | Opens an in-memory store holding a running shift whose delivery has already been picked up, which is the state a relaunch recovers into |
| `-dashpilot-seeded-pickup-history` | Opens an in-memory store holding one completed shift whose deliveries give two pickup places deliberately different amounts of recorded history |
| `-dashpilot-seeded-period-summary` | Opens an in-memory store holding a week of synthetic completed shifts and three synthetic expenses, anchored to today rather than to a fixed instant, so the period summary opens on a period that holds something |
| `-dashpilot-seeded-period-comparison` | Opens an in-memory store holding three consecutive days, also anchored to today: a today still in progress with one of two shifts unpaid, two complete days before it, and nothing before those |
| `-dashpilot-seeded-expected-pay` | Opens an in-memory store holding a running shift with two deliveries waiting at their pickups, alike except that one records what it is expected to pay |
| `-dashpilot-seeded-stacked-offer` | Opens an in-memory store holding a running shift with one offer of two deliveries and a later add-on offer of one |
| `-dashpilot-seeded-malformed-offer` | Opens an in-memory store holding a running shift with one offer of two deliveries and one offer holding no deliveries at all, which is a row the app cannot produce |
| `-dashpilot-seeded-older-weeks` | Opens an in-memory store holding completed shifts in three different weeks: one in the current one, one in the week before it and two in the week three back, so History's scope can be asserted end to end |
| `-dashpilot-seeded-older-weeks-only` | The same store without its current-week shift, which is the empty-current-week state |
| `-dashpilot-stubbed-location` | Replaces Core Location with the stub providers, reporting When In Use at full accuracy and producing no positions |
| `-dashpilot-simulated-route` | Replaces Core Location with a synthetic vehicle driving in a straight line, so a journey can watch a live mileage figure move; it implies the permission stub above |

A UI test cannot make a simulator record a route, so a measured, partial route and the
per-recorded-mile rate over it would otherwise be unreachable end to end. Nor can it terminate and
reopen the in-memory store the other journeys use, so an already-running delivery is seeded at
launch instead; that the *store* recovers one is proved against a real reopened store in
`DeliveryPersistenceTests`. The fixture is invented
amounts and offsets from a round-number origin, the same data `SyntheticRoute` builds for the unit
tests.

The two location arguments are the ones that are not store fixtures. A simulator cannot be told to
grant location from a journey, so without it the running shift's status line is only ever reachable
in its "permission required" state, and every existing journey asserts its presence and nothing
else. With it, three journeys read what a driver actually reads: that recording is active, that the
line says recording continues off screen *and* that iOS can still stop it, that the permission panel
names the limit of the scope, and that returning from the home screen does not come back describing
a pause. It stubs permission and the position feed and nothing else, so the scene phase, `RootView`'s
reaction to it and `LocationTrackingService`'s own decisions are the real ones. Whether a capture
session was continuous across the transition is a fact about stored samples and stays in the domain
suites, where it can be read.

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

The period-summary and period-comparison fixtures are anchored to **today**: the summary shows the
period the driver is actually in, so a fixture pinned to a fixed instant would open on an empty one.
Their offsets stay fixed and only the anchor moves.

The three seeded-history fixtures now follow the same rule, for the same reason: History is scoped to
the current Monday-to-Sunday week, so the instant in 2025 they used to hang from would open the app
on an empty week with everything they seed behind View Older Weeks. Their offsets are unchanged and
their anchor is 09:00 on the **Tuesday** of the current week, which is far enough into it that the
30-hour offset the general fixture reaches back with still lands inside. The anchor is derived from
the week rather than from the clock, so a fixture holds the same shape whichever day the suite is run
on; one consequence, accepted deliberately, is that a run in the first hours of a Monday seeds
synthetic shifts a little way into the future.

The older-weeks fixture is the one thing none of them can be. A journey cannot tap its way to a shift
dated last month, because ending a shift records the clock, so three weeks are seeded at launch: one
shift this week, one last week, and two three weeks back. The gap is part of the shape, because a
week nobody worked must not appear as an empty group, and the two shifts in one week must appear
under one heading rather than two. The summary fixture's three expenses are dated
rather than attached to its shifts, which is what makes a recorded total, a category split and a net
after recorded expenses reachable end to end without typing.

The comparison fixture is separate because the summary one is pinned by the journeys asserting its
exact day and week figures and holds nothing before this week. Its three days are chosen so that each
answers a comparison differently: a day still in progress whose records do not cover it, two complete
days whose difference is a quarter, and an empty day before those.

The stacked-offer fixture holds **two offers** rather than one, and the second one is the point.
Recording an offer of two is a single write, so what a journey has to judge is the screen afterwards:
which cards carry a heading and which carry none. One grouped offer alone would leave the heading
looking like part of the panel; with an add-on offer of one beside it, the count of headings is a
real claim. Its two grouped deliveries are left at different lifecycle points, so advancing one and
finding the other where it was is reachable too.

Its deliveries are handed back **in the order the shift numbers them**, not in creation order. The
deliveries of one offer share an acceptance instant, so their order is settled by the identity
tie-break in `Delivery.acceptedBefore`, and a fixture that advanced `deliveries[0]` by creation order
would be advancing a delivery whose number changes from run to run. That cost one flaky journey
before it was noticed on screen.

The expected-pay fixture is a pair rather than a single delivery, and the pair is the point. An
expected amount can only be entered while a delivery is in progress, so no completed-shift fixture
can reach one; and what the feature has to be judged on is the difference between a delivery that
carries an amount and a delivery that does not, at the same moment in the same shift. The two are
left at the same lifecycle point, waiting at their pickups, so that nothing but the amount can
explain a difference in what the app does with them, and so that a lifecycle step still sits in front
of the completion the confirmation belongs to.

The malformed-offer fixture exists for one claim, which is that the grouping-correction screen reads
whatever the store actually holds. An offer is recorded with its deliveries in one write and an offer
emptied by a correction is removed in the same write, so an offer holding nothing reaches a store only
through a fault or a migration this build has not met. An interface that fell over on one would turn
a recoverable fault into a driver who cannot reach their own history. Its empty offer is accepted
**after** the real one, so the real offer is still `Offer 1` and nothing else about the fixture reads
differently from the stacked-offer one.

The paused-history fixture is the one a journey cannot reach by tapping at all. Reaching it would
mean pausing a live shift, waiting a measurable number of minutes and ending it, which measures the
clock rather than the screen. Its shape is chosen for what the pause corrections are checked against:
**two** pauses, so one can be corrected or deleted while the other is watched for not moving; a
delivery **between** them, so a correction that would swallow recorded work can be proposed and
refused; and a stretch at the end with neither, so a missed pause can be added somewhere truthful.

It is also the one fixture anchored to a **whole hour** rather than to the round-ish epoch the others
share, so every pause lands on a clean clock minute and a journey can set a minute wheel to a round
value and know exactly what the corrected pause is.

The seeded paths are app code that exists only for tests. They are DEBUG-only and in-memory, and
they are eight more launch paths to keep honest.

## UI journeys

The UI target covers a handful of paths: launching, starting and ending a shift, pausing a running
shift and resuming it, reading what a paused shift says about its stopped recording and its
unavailable delivery control, a paused shift still being the shift in progress and still finishing as
one shift in history, recording a delivery through its whole lifecycle, cancelling one, being refused a shift end while a delivery is
running, recovering an already-running delivery at launch, opening a completed shift, adding and
editing a shift's amount, adding, editing, cancelling an edit of and removing one delivery's amount,
two stacked deliveries keeping independent amounts while the shift total stays untouched, reading the
detail screen's delivery, route and rate statements, a finished delivery stating what it paid per
hour of its own lifecycle while the delivery it overlapped states its own and the cancelled one
states none, a tip moving that figure on the row as soon as it is recorded and moving nobody
else's, opening a pickup place's recorded wait history,
renaming a place and being refused a colliding rename, merging two places into one history,
exporting a shift as JSON and as CSV, exporting a selected day and week, an empty period offering no
export, exporting all history, a running shift offering none, switching between the four period
lengths, stepping back to an empty month, being refused a step past the current month, choosing and
applying a custom date range, cancelling that sheet without changing the period, a chosen range
surviving a switch to another period length, exporting a month and a chosen range, recording an
expense and finding it in the list, being refused a negative one, editing and deleting one, reading a
period's recorded costs, its categories and the net after them, that net never calling itself profit,
gross earnings unchanged beside it, an expense recorded on a day with no shift still being
summarised, recording what a running delivery is expected to pay and reading it back on the card as
expected rather than as earnings, delivering a delivery that carries an expectation and being offered
the final amount, dismissing that offer and finding the delivery terminal with the expectation kept
and no gross recorded, delivering one that carries no expectation and being asked nothing, reading a shift whose
deliveries arrived in one offer and seeing exactly one heading over them with none over the add-on
offer's card, hearing a card name the deliveries it was accepted with, advancing one delivery of an
offer and finding its sibling where it was, recording an offer of two from the sheet and then a
single delivery beside it, dismissing that sheet and recording nothing, combining two offers the
driver recorded separately and finding one heading over all three deliveries afterwards, separating a
grouped offer back into one offer per delivery, putting one delivery of a grouped offer into an offer
of its own, combining two offers from a finished shift's history and finding both rows saying so with
every recorded time kept, leaving the correction screen without changing anything, a shift of one delivery offering
no correction at all, a store holding an offer with no deliveries being stated rather than crashed
on, recording a tip a finished delivery received outside the platform's own amount and reading the three
figures back off both the sheet and the row, a delivery holding two tips of different methods and
reporting all three figures, correcting one tip and then removing it while the platform amount stays
exactly as it was, a tip of nothing refused in the words of a tip, a delivery carrying tips and no
platform amount saying there is no total rather than showing the tips as one, the earnings editor
stating the tips already recorded beside a field that still holds the platform amount alone,
correcting a recorded pause from a finished shift and watching the paused, working and hourly
figures move while the elapsed, delivery and mileage figures do not, leaving that editor without
writing anything, being refused a pause corrected over a recorded delivery and told which fact it
collided with, deleting a pause recorded by mistake after a confirmation that states which way the
working time moves, cancelling that confirmation, adding a pause that was never recorded and finding
it opens refused rather than pre-filled, a shift with no pauses still offering to record one, none of
those corrections being offered on a running or a paused shift, reading a
day beside the day before it with both figures and both coverages on screen,
the percentage a finished and fully recorded pair of days states, the absence of one while a day is
still in progress, an empty previous day said to hold nothing rather than shown as no earnings,
finding every correction a completed delivery offers laid out in columns wide enough to read and
each one hittable, the same controls becoming a single column at the largest accessibility text
size, and
deleting a shift through its confirmation.

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
- Proving a sheet does **not** appear needs an ordering argument rather than a sleep. The
  expected-pay confirmation is raised by the same state change that removes the delivered card, so
  waiting for the card to go and then finding no sheet is a real negative; the journey then opens
  another card's own sheet, which a presented confirmation would have swallowed. Forcing the
  confirmation to be raised unconditionally fails that journey on the assertion itself rather than
  on a timeout.
- An editor seeds its field through `MoneyInput.text(for:)`, which drops trailing zeroes, so an
  expected `$8.50` seeds `8.5`. Assert the seeded text, not the formatted amount.
- A claim about one delivery's own controls has to start from the list cell that contains them.
  `shiftDetailDeliveryRow` is the combined element holding the facts and is a **sibling** of the
  controls, and two deliveries picked up at the same place carry two controls with identical labels.
- A journey that sets `-UIPreferredContentSizeCategoryName` reaches a screen several times longer
  than the default one: history is below the fold on launch, so the shift row has to be scrolled to
  before it is tapped, and the scrolling helpers need a larger `maxSwipes`.
- A `.sheet` attached to a conditionally rendered section goes away with the section. The period
  summary rebuilds its sections whenever it re-measures routes, which dismissed the export sheet
  before it had written anything; the modifier belongs on the `List`.

### A red UI run is a measurement, not a verdict

The UI suite is sensitive to how busy the **host** is, and that was measured rather than inferred.
`investigate/ui-suite-instability` ran the full serial suite three times and then re-ran the failing
journeys in isolation.

What it found:

- The suite ran **clean on `main`** in one full serial run, and produced **1 and 2 failures** in two
  full serial runs of a feature branch, with a **failing set that did not overlap** and every failed
  journey passing in the other run. At those counts the difference is not significant
  (Fisher exact `p = 0.55` for 3 failures in 224 executions against 0 in 109), so a single clean run
  settles nothing either way.
- The cost of one synthesized swipe, measured between consecutive swipe events inside a test, had a
  **median of 3 to 6 seconds, a 90th percentile near 12 seconds and a maximum of 63 seconds**. It
  should be well under a second. Most of each gap is XCUITest waiting for the app to go idle.
- The host's load average during those runs was between **15 and 79**. The clean baseline this
  project records was taken "on a machine doing nothing else".

So **`xcrun simctl erase` is necessary but not sufficient**. It resets simulator state, which is a
real cause of a different failure mode (a run that fails dozens of untouched journeys at once), and
it does nothing at all about host CPU contention. Erase before a baseline run *and* run it on an idle
machine; a suite run beside a busy desktop is not a baseline.

**How to read a red run.** Compare the failing set against the previous run's. A set that does not
repeat is contention, not a regression. Confirm by re-running the journeys in isolation, and by
checking whether the same journeys pass on `main`; a branch is only implicated if the failures
concentrate on what it changed.

### One journey races a product deadline, and that is arithmetic

`testUndoingADeliveryMarkedDeliveredByMistake` is the one failure that reproduces. The undo banner is
offered for **20 seconds** (`DeliveryControlPanel.undoSeconds`), and the journey needs roughly that
long to reach and press it: the measured interval from the completion tap to the undo tap was
**20.34 s and 19.72 s on the two runs that passed**. On a clean checkout of `main`, in isolation,
under host load, it failed **3 times out of 6**.

The budget goes on about six accessibility round trips, and the largest single item is one
`app.swipeDown()` to bring the banner back into view, measured at up to 13 seconds under contention.
Nothing on the test side recovers enough of that to matter: removing the label assertions inside the
window buys about 1.3 seconds against a swipe that can cost ten times as much.

It is therefore **not fixable from the test target alone**, and it was deliberately left alone rather
than papered over with a longer timeout, a retry or a sleep. The options, in the order they should be
considered, are to run the suite on an idle machine, or to give the undo window a debug-only launch
argument so a journey can ask for a longer one, in the family of the seams above. The second is a
production change and needs its own scope.

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
