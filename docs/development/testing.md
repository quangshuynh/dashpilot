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
| Live Activity control priority | The exact ordered control set for each important state, built through the one content path the app uses: the delivery step first with the pickup workflow off, Park Vehicle first and emphasised with it on at every step of an order, Resume Driving first whenever parked, the switch followed on the next snapshot, no settings row reading off and creating none, never more than four controls and always exactly one of the parked pair; and deliveries recorded as sharing a stop drawn as one row with one clock only when they are also in one state |
| Live Activity card layout | The card's own view laid out in the test host and measured: every state, at 370 and 343 points wide and at every text size including the accessibility sizes, under the 160-point Lock Screen limit with a margin (it measured 242 to 296 points with an order in progress before the redesign); sizes past `xLarge` measuring the same as `xLarge`; the Dynamic Island's bottom region within what the island leaves; and the plan itself: controls in the app's order in at most two rows of two, an order outranking the mileage line, the footnote stating the orders without a line and the withheld step, the mileage never drawn without its qualifier, and parked said in the header and never as paused |
| Shift Live Activity synchronisation | A shift driven from running through paused, resumed and ended as one card and then none, plus what a Lock Screen makes invisible: a relaunch adopting the card its shift already has, a card left behind by a shift that is gone, one describing a different shift, one the driver dismissed, a system that refuses the request, and Live Activities turned off entirely |
| Shift Live Activity update policy | The cadence, including the one that matters most: time passing is not a change, because the card's anchor has not moved and the system is already drawing the right clock. The delivery clocks follow the same rule and add one case: an order finishing as another is accepted moves no count on the card, so the list of anchors is compared directly |
| Shift lifecycle, Shift service | Start, end, single-active-shift, clamped clocks, rollback, relaunch recovery |
| Shift pause domain | The union of a shift's pauses: overlap, touching, order independence, clipping to the shift, a malformed row counted rather than dropped, and an open pause measured to the moment it is read at, so working time stops growing. Plus working duration never going negative, and the three lifecycle states |
| Shift pause service | Pause, resume, the refusals for each, the delivery rule in both directions, ending a paused shift closing its pause at the end time, a clock that moved backwards still letting a shift be ended, and a refused pause leaving the store untouched |
| Shift pause persistence | The v8 to v9 migration with every shift's duration unchanged and nothing read as a break, the schema shape asserting a relationship rather than a paused flag, the plan's version and stage counts asserted here once, a paused shift recovered from a reopened store by the unchanged unfinished-shift query, and deletion cascading to pauses |
| Shift pause correction | The rules a proposed correction is checked against, with no store: the bounds, positive length, touching allowed and overlapping refused for another pause and for delivery work, an open or malformed stored row blocking nothing because it measures nothing, and every refusal having a sentence that says what would make the stretch acceptable |
| Shift pause correction service | The three writes through the store and mostly what must not move: a start, an end and both together, deletion renumbering nothing it should not, a missed pause added without making the shift paused, the running-shift and open-pause refusals, an overlap refused rather than merged, a delivery kept rather than shortened, elapsed time, delivery active time, mileage, route sessions and both amounts unchanged, the period's working hours and rate following, a pre-existing overlap still unioned and a malformed row repairable, three refused saves read back through a fresh context, the export carrying it through the fields it already had at format version 3, and three daylight-saving cases measured in real seconds |
| Shift end correction | The rules a proposed end is checked against, with no store: after the start with zero refused, a pause reaching past it and an open one, everything a delivery recorded including an out-of-order chain, a later shift with touching allowed, which refusal wins when two hold, the boundary route is judged against and the fact that a later end has none, the delivery refusal naming the right delivery among two and the latest instant rather than the latest stage, every refusal and the destructive confirmation having a sentence that names what it is about, and every refusal having a structural log name that cannot carry an instant |
| Delivery time correction | The rules a proposed set of delivery times is checked against, with no store: each of the four stages corrected on its own and several in one proposal, a no-op accepted, the duration and the recorded pickup wait following the stages that feed them, every ordering collision refused **naming both halves** and resolved only by correcting the other fact too, touching instants allowed, the shift's two bounds with touching allowed and judged before the ordering inside them, a stage never recorded refused rather than created and a recorded one refused rather than removed, the terminal outcome reported as the removal it would be, an unfinished delivery and a running shift refused, and every refusal having a sentence, a structural log name and both halves of what it collided with |
| Shift end correction service | The write through the store, and the claim the whole suite exists for: a fixture of three equal capture sessions, so a mileage measured from what remains and a mileage scaled by the time removed cannot be mistaken for each other. Plus the position exactly on the boundary kept, the endpoint never interpolated, the partial capture session keeping its identity, a later end adding no position and no metre while its missing coverage stays visible, the durations and both rates following, the amounts, tips, delivery timestamps and pause timestamps unchanged, the five refusals through the store with the route read only after the proposal is accepted, a refused save leaving the end **and** the whole route as they were read through a fresh context, a repeated correction idempotent and two steps matching one, deleted positions not returning when the end moves back, the period the shift does not leave, and the export carrying it through the fields it already had |
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
| Pickup wait provenance measurement | What pickups recorded by Park under the retired setting did to the median before it left them out, as exact synthetic figures: manual-only odd and even samples, one Park pickup at the two-sample threshold, among five and among many, Park pickups as half and as most of a sample, zero waits, and a correction rederiving through the store |
| Pickup wait measurement under Park and Resume | What pickups recorded by Resume Driving do to the median, as exact synthetic figures through the app's calculator: the workflow alone long by exactly the walks and the linger, one among five, at the two-sample threshold, as half the sample, the median climbing with the workflow's share, lingering before walking in or before resuming, immediate Park and Resume, long waits, stacked orders at one place, the policy holding the figure at every share, and the same end to end through the store |
| Pickup provenance | Written with the pickup by the one control that wrote it: the card, Resume Driving under the workflow, none from Park, none with the workflow off, none on a refused pickup or a refused save read through a fresh context; kept through delivering, reopening, cancelling, a historical cancellation and a time correction; the recovery an automated pickup has after Undo; structural log wording |
| Pickup provenance persistence | v18 frozen with the column on the delivery, each kind (manual, Park's, Resume's) surviving a reopen, and v17 pickups migrating to unknown rather than manual whatever the setting and a coincident parked stretch say |
| Pickup wait provenance policy | Automated waits (Resume's and Park's) out of every figure and counted apart by kind, unknown counted, a wait Park began and the driver ended counted, zero still a sample, an automated-only place showing no figure, the exclusion wording for each kind and both spoken with its figure, the place and the period applying one rule, settings changes rewriting nothing, corrections rederiving without changing the population, and both export forms with a migrated pickup exported as `unknown` |
| Park pickup selection | The pure rule for which delivery Park works on: one delivery heading to or at its pickup, never one in the car or finished, D3 before D4 in every combination of states, three orders, input order never mattering, and stacked orders off choosing nothing among two in progress |
| Park and Resume pickup workflow | Off by default and with no row, the stacked answer inert alone, Park marking Arrived and Resume marking Picked Up at the recorded instants, no duplicate arrival, a customer stop saying nothing, clamping, stacked off and on, the D3 then D4 sequence, three orders, a delivery cancelled or picked up by hand between Park and Resume, the workflow turned off while parked, refusals, an arrival or a pickup whose save fails leaving the vehicle state standing (read through a fresh context), the save order observed, and wording that claims no detection |
| Automated pickup step undo | Undo after Park keeping the vehicle parked and after Resume keeping it driving, the card working afterwards, no other delivery moving, refusal after a later event, after delivery or cancellation, twice, after re-recording, for a manual pickup and for a missing delivery, a refused save, the step judged against the store from another context, and the spoken labels |
| Shared stops | Independent by default, both switches recorded with an offer as two identities, a shared stop refused on an offer of one, a subset recorded and replaced with a fresh identity and taken back, one alone refused with both kinds judged before either is written, the offer screen naming only its own offer, nothing else moving, allowed on a finished shift, a refused save leaving the store as it was, membership corrections (move, split, separate, merge) keeping the stops deliveries share, and captions that name siblings and claim no customer, address or place |
| Resume driving after delivery progress | Off by default and with no row, persisted, changing it rewriting nothing; a parked pickup or Delivered resuming only when its stop has nothing left, a shared pickup or drop-off half done staying parked, Same drop-off never joining a pickup nor Same pickup a drop-off, an unmarked stacked order keeping it parked and left untouched, a paused or unparked shift untouched; one recorded pickup and one transition under Park and Resume, Resume's own pickup never recursing, a stretch chosen for a pickup still at Arrived holding the stop; a failed resume leaving the step and the parked vehicle, a failed step inventing no resume; working time unchanged; a new capture session after an automatic resume with nothing measured across the stretch; one Undo of step and driving that reopens the same stretch and drops the positions since, refused whole after a later event or parking again, leaving other deliveries alone, and a refused save changing nothing; the Siri and Lock Screen path |
| Stack edits | The planner over every combination (joining two, joining additively through an existing group, two pickups in one stack, separating from a pair and from three, separating nothing, a finished member kept whole, each refusal named), restating one offer keeping other offers' statements; through the store: two separate offers marked Same pickup with no offer, number, instant or amount moving and no arrival manufactured, a larger stack regrouped, Same drop-off apart from the pickup, a picked-up delivery joinable with nothing recorded, delivered and cancelled deliveries refused with nothing written, a finished member kept, survival across a reopened on-disk store, a refused save, Park and Resume moving a cross-offer pair together, an edit while parked changing the next Park and not this Resume, captions naming cross-offer siblings, and export numbering one cross-offer group |
| Hourly target comparison | Above, near and below a $25.00 target with the 2% band inclusive at both edges, the rate compared at the cent it is shown at, missing rate or target and a zero target giving no comparison, the three statements and their spoken forms, no judgement in any wording, and a period counting each shift against its own target apart from shifts with no target or no rate |
| Hourly target snapshot | A shift keeping the target it started with when the setting moves or is removed, read back through a fresh context; no target recorded as none, a target set mid-shift reaching the next shift only, one writer on a running shift refusing zero, a second write and a finished shift, settings refusing zero and keeping the previous target, a week's count through the period calculator, and the export field with the format version unchanged |
| Hourly target persistence | v22 as the current version with its plan counts, frozen v21 with no target column and v22 with it on the shift and the settings row only, v21 and v20 stores migrating with no target anywhere and nothing recorded moved, and the default and a snapshot surviving a reopen |
| Onboarding policy | Welcomed only on a new install with no history, a driver with history recorded as having seen it, never shown twice, a newer welcome shown once, and the four screens' words, with platforms named only to disclaim an integration and no dollar figure anywhere |
| Resume after delivery progress persistence | The one settings column on the settings row only (frozen v20 without it), v20 and v19 stores migrating with it off and everything else kept, and the answer surviving a reopen |
| Shared stop persistence | v20 frozen with eleven models, the two delivery columns and the suspension's new list joining nothing, v19 frozen, v19 and v18 stores migrating with every delivery independent however alike, a migrated stretch resuming only the delivery it named, and shared stops surviving a reopen |
| Shared pickup workflow | Same pickup moving both at Park and at Resume in one write, a shared drop-off alone moving only the lowest number, unrelated stacked orders unchanged, a lower unrelated order first, mixed states, a member already in the car, stacked orders off with one shared stop and with an unrelated order beside it, the workflow off, a delivery cancelled inside, a regrouping while parked not changing what Resume picks up, the stored set surviving a relaunch, a refused save at Park and at Resume recording none (read through a fresh context), a shared advance judged whole before writing, one Undo for both events, Undo never cascading, refused whole after later evidence and after a refused save, and wording |
| Shared stop export | Two local grouping keys in JSON with explicit nulls, numbered within the shift, no stored identity or customer field in the bytes, the CSV unchanged at 42 columns, and the format version unchanged |
| Pickup workflow persistence | v19 frozen, the settings columns and the suspension's identifier joining nothing, v18 frozen, v18 and v17 stores migrating with the workflow off and no stretch associated, both answers persisting, and a stretch parked before a relaunch resumed after it for the delivery Park chose |
| Period summary explanations | Each section footer's surviving qualifications, a length bound per footer and in total, and no em dash |
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
| History fetch scope | The two store reads History is drawn from, asserted against the partition they replaced: the week's own completed shifts newest first, a running shift in neither read, Monday 00:00 opening the week and Sunday 23:59:59 closing the one before, a 169-hour week across the autumn clock change, the rollover moving a shift from one read to the other, a shift dated after the week reachable under the other weeks, both reads equal to the partition's two sides row for row over nearly three years, the other weeks counted as Monday weeks, a week summarised through a context of its own equal to one summarised directly and skipping a deleted shift, a week's one off-main pass giving each row exactly its own route's distance and none for a shift with no route, a route fetched by the relationship's key whole, in order and without another shift's positions, and Export All History still carrying every completed shift whatever the screen reads |
| History week summaries | What a week says above its shifts, derived twice to show it is the period calculator's own figures: the three primary figures and the secondary lines in reading order, the shift and delivery counts on one line, missing earnings and unmeasured miles never read as zero, complete fuel coverage stated, partial coverage never scaled up to the week, a partial route making the fuel a floor and the net a ceiling, a recorded zero gas price counted, the estimated net over its paired subset rather than week earnings less week fuel, recorded expenses reaching neither net so fuel is never subtracted twice, the spoken form naming its week first, the card bounded at eight lines, the two rates taken from the period's own paired subsets rather than one line divided by another and absent rather than zero where no shift carries both halves, only the fuel lines classified as estimates, the shifts and deliveries read as one line, and a figure that was never recorded marked as words so it is never drawn as a number |
| History week refresh after an edit | An older week follows an edit to one of its shifts: an amount, an end correction (with the route after it gone), a missed pause, fuel assumptions, a completion corrected to a cancellation and a deletion each move the week's revision and the summary worked out through the same off-main path; an edit to another week, a running shift's route batch and a save changing nothing leave it alone |
| Delivery time in state | How long a delivery has been at its current step, from that step's own recorded instant, for each active state; no clock for a contradictory chain or a clock reading earlier than the instant; and the reminder's evidence equal to the same span |
| Dash typography | The text roles: only the two figure roles ask for tabular digits and the condensed width, the condensed system figures equal width on request so a ticking clock keeps its length, a condensed figure measurably narrower than the standard one on DashPilot's own figures, figures heavier than their medium labels, and every role anchored to a Dynamic Type style |
| Font bundle invariants | What a font change must not disturb, read off the bundle the app launches with: no `UIAppFonts` entry, no font file and no font license in the app, the widget extension still embedded and carrying no font, and `NSSupportsLiveActivities`, the location background mode and the When In Use usage description still declared with no Always key |
| Project file invariants | The project file itself, read through `#filePath` and disabled where the checkout is not readable: no file reference is an absolute path on one machine, and the widget target compiles only its own folder and the shared activity folder, never a font folder |
| Recorded shift vehicle | What a completed shift says it was worked in: its own name, economy and price; renaming, repricing, reselecting and deleting in Settings rewriting nothing, read back through a fresh context; a shift that recorded no vehicle staying unnamed while one is selected today; an economy typed by hand naming nothing even when a profile matches it; a recorded zero price said as zero; a missing half left out rather than zero; and wording that stays true of a name recorded after the start |
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
| Delivery tip persistence | The v12 to v13 lightweight step with every migrated delivery holding no tip and reporting exactly the figures a v12 build reported; the frozen v12 shape holding no tip; and tips surviving a reopened store with their methods and moments. The plan's version and stage counts moved to the fuel suite when v14 became current |
| Fuel estimate | The arithmetic, and the one mistake the type exists to make impossible: two cases compute `recordedMiles * gasPricePerGallon` explicitly and assert the estimate is not it. Plus an inexact quotient staying exact at the working scale, a price binary floating point cannot hold, a fractional fuel economy, each missing half naming itself, a fuel economy of zero refused, a recorded gas price of zero producing `$0.00` rather than nothing, no route against positions that no continuous stretch joins against a measured distance of zero, a partial and a legacy route carried through, the gallons formatted and spelled out, and a sweep of every reason and every sentence for `$0`, "zero", "expense", "deduct", "profit" and "tax" |
| Miles per gallon input | The parser: a plain figure, zero and a negative both refused by the one rule that explains itself, an empty field, a word, two separators and a third decimal place each with their own refusal, the shared magnitude bound, another locale's decimal separator read and written, a field seeded and read back unchanged, and trailing zeroes dropped |
| Fuel assumptions | What the store keeps: each half independently optional, a running shift refused, zero and negative fuel economies refused and a zero gas price recorded, a refused edit leaving **both** halves as they were and leaving nothing pending, removal leaving no estimate rather than one of nothing, a newer shift's fuel economy and gas price each leaving an older shift's estimate exactly where it was, correcting one shift moving only it, the default being the last completed shift that recorded a pair with running and unrecorded shifts skipped, the service's write and refusal read back through a fresh context, and an end correction moving the mileage with the estimate following while neither assumption moves |
| Fuel assumption persistence | The v13 to v14 lightweight step with every migrated shift recording nothing and reporting no estimate rather than one of `$0.00`, while its mileage, durations, rates, amounts and tips are the figures they were; the plan's version and stage counts asserted here once; the frozen v13 shape holding neither column; a store stepped up from v12 through both stages; and a recorded pair, including a gas price of zero, surviving a reopened store |
| Next shift vehicle context | What the start panel says the next shift will record, built the way the screen builds it and compared with the snapshot the start actually wrote: the selected vehicle, a selection changed before the start, none selected, profiles with none selected, a price with no vehicle, a vehicle with no price, a recorded zero price, a deleted selection and a selection naming no profile, Settings changed after the start leaving the snapshot alone, reading writing nothing and creating no shift, and still no relationship from a shift to a profile |
| Shift profitability | The subtraction and the shared working-time denominator reached two ways, a pause moving the hourly net while the net itself stays put, an end correction moving the mileage and the net following, a negative net stated rather than clamped, each missing half naming itself, a running shift saying so rather than reporting no earnings, a shift kept paused throughout having a net and no hourly figure, a tip moving what its delivery paid and no figure on the shift, an expense moving no shift figure while deriving a net creates none, changes none and writes nothing at all, the period's net after recorded expenses asserted beside the shift's estimated net as two different statements, and a sweep of every reason for `$0`, "zero", "profit", "take-home", "deduct" and "tax" |
| Delivery tip export | Each tip as its own JSON record with its method and moment, an empty array rather than a missing key, `grossEarnings` meaning exactly what it always did, no total where the platform amount is missing, the renamed per-delivery rate, the period subtotal following, the three appended CSV columns leaving every existing one where it was, no individual tip amount or method reaching the CSV, and the current format version |
| Offer correction | The rules the model owns: the ordering rule an offer keeps, a move that leaves both acceptance timestamps where they were, refusals for an offer accepted later, another shift's offer and the offer a delivery is already in, the offer left behind returned rather than emptied here, a regrouped offer taking the earliest acceptance among its deliveries, regrouping allowed on a finished shift where recording new work is not, numbering renumbering what a removed offer leaves, and every confirmation sentence including the one that says an offer is removed and the sweep proving none of them carries an identifier |
| Offer correction service | The four corrections as the store applies them: a move leaving both offers standing, a move out of a two-delivery offer leaving its sibling, the last delivery leaving removing the emptied offer read through a fresh store, a split of one and of several, a split of every delivery refused as the no-op it is, deliveries from two offers refused in one operation, a merge moving every delivery and removing the source without taking a delivery with it, the wrong merge direction refused before anything moves with the truthful direction then working, separating a grouped offer, and rollbacks during a move, a split and a merge each read through a fresh context |
| Offer correction invariance | What must not move: every lifecycle timestamp, pickup place, amount and terminal state on an active and a terminal delivery under all four corrections; shift gross, delivery gross, the three rates, the active-time union and the delivery summary; the Live Activity's active count and its withheld step; pickup waits and their per-place samples; a period's whole `PeriodMetrics`; the export's `offerNumber` following the grouping while every other field and the format version stay put; renumbering after a merge; the one-tap Start Delivery path; a migrated one-delivery offer as both subject and destination; and an offer holding no deliveries read, offered and merged away without taking a delivery with it |
| Delivery recovery | The rule a reopening applies before anything is written: the state each remaining chain of timestamps restores, a completion recorded straight from an arrival taken back while a pickup with no arrival is refused, a cancellation and a second invocation each refused with their own case, contradictory times refused rather than blessed, and every confirmation sentence naming its subject and carrying no identifier, timestamp or amount |
| Delivery recovery service | Reopening through the store: one timestamp removed and the rest asserted unchanged, the money and the expectation preserved, the ended-shift and paused-shift refusals, and a refused save leaving the delivery delivered read through a fresh context |
| Delivery time correction service | The write through the store, and mostly what must not move: each stage corrected in turn and all of them surviving each other, a correction read back through a fresh store instant by instant, the completed duration, the recorded pickup wait, the per-delivery hourly figure and the shift's delivery active union all following with no invalidation step, a tip still in the numerator afterwards, stacked deliveries staying independent with the union not the sum, the route, its capture session, the mileage, the money, the pickup place, the offer, the terminal outcome and the shift's own boundary all unchanged, a cancelled delivery corrected and a stage it never recorded refused, the three bound and ordering refusals leaving nothing pending, a refused save leaving **every** original instant read through a fresh context, a stale proposal refused rather than written over newer times, and the real recovery end to end: a shift end refused and identified, the delivery corrected, the same end then accepted |
| Historical delivery cancellation | The rule a historical correction applies before anything is written: the recorded completion reused as the cancellation to the instant, a delivery still in progress and one already cancelled each refused with their own case, contradictory times refused rather than blessed, the model moving one timestamp to the other with every earlier event asserted as a value, both amounts preserved, the offer re-derived for each mix of cancelled and delivered children, and every confirmation sentence naming its subject while saying nothing about editing and carrying no figure |
| Historical delivery cancellation service | The correction through the store, and mostly what must not move: the shift staying ended with nothing in progress, the active-time union, working duration, mileage, recorded pickup wait and whole period metrics unchanged, delivery-earnings coverage unable to outnumber its eligible records, the running-shift and paused-shift refusals sending the driver to the reopening instead, a second invocation writing nothing, route capture and the Live Activity both left alone, a refused save leaving the delivery delivered read through a fresh context, and JSON and CSV carrying the correction through fields they already had at format version 3 |
| Historical delivery recovery investigation | Evidence for a refusal, not a specification. Builds the row the services refuse to create (a completed shift holding a reopened delivery) and measures what every existing reader does with it: the delivery stuck beyond finishing, cancelling or reopening; the shift's end, route capture and Live Activity all correctly untouched; delivery active time unmeasurable alone and silently short beside a sibling; the offer permanently in progress; a finished period reporting work in progress and printing more delivery-earnings contributors than eligible records; and an export written rather than refused, carrying an active state and a shift whose two counts no longer reach its delivery count |
| Delivery progress assistance | The rule a reminder is offered under, as plain values: each state it speaks about and the one it deliberately does not, the threshold checked on both sides of it, the arrival measured from the arrival rather than from the acceptance, both terminal states and a cancellation from a stale pickup, a contradictory chain and a pickup with no arrival refused as evidence, a future instant, stacked deliveries judged one at a time with each offered its own step, and a sweep of every sentence for `you arrived`, `you picked up`, `detected` and `confirmed`. Against a store: deriving one leaves every instant where it was with nothing pending, confirming one runs the ordinary lifecycle action and moves no sibling, and a finished shift's deliveries are offered nothing at all |
| Stacked delivery state | The combinations a stacked driver meets, asserted against rules that already existed: accepted beside arrived, arrived beside picked up, two accepted, two picked up, a completion and a cancellation each leaving the active set while numbering holds, a group surviving one of its deliveries advancing past its sibling and then finishing, two offers keeping their own membership, and every active card exposing exactly the step its state allows |
| Route suspension | What recording the vehicle as parked stops and what it deliberately does not: working duration and the paused figure untouched while the parked figure is stated, no lifecycle timestamp created or moved, the filter rejecting by its own rule with paused and ended each outranking it, two capture sessions measured separately with the kilometre between them never bridged, the coverage wording changing only where a suspension exists and never claiming a correspondence with the gaps, four refusals, pausing and ending each closing an open stretch at their own instant, one vehicle across two open deliveries with a pickup not resuming it, an end correction refused through a recorded stretch and accepted past it with the mileage measured again, and a shift left parked coming back parked from a reopened store |
| Route suspension persistence | The v15 to v16 lightweight step with a real two-session route migrated and **no suspension read out of its gap**, the schema shape asserting the relationship to `Shift` and its absence from `Delivery`, the cascade, the frozen v15 shape holding no suspension, a store stepped up from v14, and the plan's version and stage counts asserted here once |
| Route suspension export | Both additive fields with the route rather than with the durations, `0` rather than `null` for a shift never parked, the working seconds and pause count unmoved, nothing about it on a shift or a delivery object, no instant anywhere in the bytes, the two appended CSV columns leaving all 39 earlier ones where they were and repeated on every row of a shift, and the current format version |
| Expense export | Expenses selected by their own dates, none in a single shift's file, a period of costs alone exported rather than refused, the summary's totals and net, the JSON key set and its explicit nulls, a round trip, the CSV carrying no expense whatever its column count, and expenses adding one top-level key without redefining any |

Running one suite:

```bash
xcodebuild test \
  -project DashPilot.xcodeproj \
  -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DashPilotTests
```

### Measuring History against a long store

`HistoryFetchScopeMeasurementTests` is off by default, like the route-capture profile, because its
numbers depend on the machine. It seeds on-disk stores holding one week to five years of synthetic
work and writes what History's two screens cost, before and after the week-scoped read, to a report
file. `olderWeeksCostByPhase` measures Older Weeks with routes the size a real shift records (1,500
positions), phase by phase on the actor each runs on, and `routeFetchProbe` splits one row's cost
into the route fetch (which grows with the store) and the walk (which does not):

```bash
TEST_RUNNER_DASHPILOT_HISTORY_PROFILE=1 xcodebuild test -scheme DashPilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  -only-testing:DashPilotTests/HistoryFetchScopeMeasurementTests
find ~/Library/Developer/CoreSimulator/Devices -name 'dashpilot-history-fetch-profile.md'
```

The `TEST_RUNNER_` prefix has to be an environment variable of `xcodebuild`, and the run has to be
serial, or it silently measures nothing.

### Screenshots kept for review

A few journeys keep a full-screen screenshot in the result bundle with `attachScreenshot(_:)`, named
for the state it shows (`home-pre-shift`, `home-active-no-deliveries`, `home-parked`,
`home-paused`, `home-one-delivery`, `home-two-stacked-deliveries`, `home-reminder`,
`history-current-week`, `older-week-full-fuel`, `older-week-partial-fuel`, `older-weeks-after-edit`,
`detail-summary`, `detail-partial-route`, `settings-default-vehicle`, `settings-no-vehicle`,
`vehicle-editor`, and the largest-text variants, `history-xxxl` and `detail-xxxl` among them). They assert nothing and compare nothing; they are
the record a reviewer reads after a run:

```bash
xcrun xcresulttool export attachments --path <path>.xcresult --output-path <folder>
```

A journey inherits the simulator's own text size unless it passes one, so reset it after checking a
screen by hand (`xcrun simctl ui booted content_size large`), or journeys that read an unscrolled row
fail for a reason that has nothing to do with the change under test.

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

Debug builds accept twenty-two arguments, all used only by UI tests and screenshots:

| Argument | Effect |
| --- | --- |
| `-dashpilot-in-memory-store` | Starts from a known empty state, so a journey never writes into the store a real driver's history would live in |
| `-dashpilot-live-activity-preview` | Used beside a throwaway store. Draws the running shift's Live Activity card at the top of the main screen, built through the same content path the activity uses and clipped to the Lock Screen's 160 points, so a journey can read the controls in order and check each is inside the card. It is the extension's own view, not the system's rendering of it |
| `-dashpilot-seeded-history` | Opens an in-memory store already holding synthetic history: one completed shift with an amount, a route recorded in two capture sessions and three deliveries (two delivered, one cancelled), and one shift with none of those |
| `-dashpilot-seeded-active-delivery` | Opens an in-memory store holding a running shift whose delivery has already been picked up, which is the state a relaunch recovers into |
| `-dashpilot-seeded-pickup-history` | Opens an in-memory store holding one completed shift whose deliveries give two pickup places deliberately different amounts of recorded history |
| `-dashpilot-seeded-period-summary` | Opens an in-memory store holding a week of synthetic completed shifts and three synthetic expenses, anchored to today rather than to a fixed instant, so the period summary opens on a period that holds something. **Exactly one of its shifts records fuel assumptions**, so the period's estimated fuel is partially covered and a coverage defect cannot pass unnoticed |
| `-dashpilot-seeded-period-comparison` | Opens an in-memory store holding three consecutive days, also anchored to today: a today still in progress with one of two shifts unpaid, two complete days before it, and nothing before those |
| `-dashpilot-seeded-expected-pay` | Opens an in-memory store holding a running shift with two deliveries waiting at their pickups, alike except that one records what it is expected to pay |
| `-dashpilot-seeded-stacked-offer` | Opens an in-memory store holding a running shift with one offer of two deliveries and a later add-on offer of one |
| `-dashpilot-seeded-malformed-offer` | Opens an in-memory store holding a running shift with one offer of two deliveries and one offer holding no deliveries at all, which is a row the app cannot produce |
| `-dashpilot-seeded-paused-history` | Opens an in-memory store holding one completed shift that was paused twice, with one delivery between the two pauses, which is what the pause corrections are checked against |
| `-dashpilot-seeded-late-end-history` | Opens an in-memory store holding one completed shift whose recorded end is twenty minutes later than the driver stopped, with a whole capture session and a delivery recorded before it |
| `-dashpilot-seeded-late-delivery-history` | The same shift whose one delivery recorded its completion two hours after the order was handed over, which is the real recovery case: the shift end correction refuses and names it, and the same correction is accepted once the delivery is corrected |
| `-dashpilot-seeded-finished-delivery` | Opens an in-memory store holding one finished shift in the current week with one delivered delivery that records no amount, tip, place or route: the state the earnings and tip journeys used to reach by driving a whole shift through the interface first |
| `-dashpilot-onboarding-fresh` | Forgets that the welcome was finished and lets it show over a throwaway store. Every other throwaway-store launch never shows it |
| `-dashpilot-onboarding-observe` | Lets the welcome show over a throwaway store **without** forgetting it was finished, which is how a relaunch proves completion persists |
| `-dashpilot-onboarding-completed` | Treats the welcome as finished, for a journey over the real store whose subject is the store opening |
| `-dashpilot-seeded-older-weeks` | Opens an in-memory store holding completed shifts in three different weeks: one in the current one, one in the week before it and two in the week three back, so History's scope can be asserted end to end |
| `-dashpilot-seeded-older-weeks-only` | The same store without its current-week shift, which is the empty-current-week state |
| `-dashpilot-seeded-long-history` | Opens an in-memory store holding about two and a half years of completed shifts, the latest week of three with measured routes and fuel recorded for two of them (one at a gas price of zero), a week three back whose one shift has its fuel estimated in full, and the oldest shift recording no vehicle, so a long History, partial and complete weekly fuel coverage and historical vehicle context can be reached end to end |
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

The fixtures holding a **running** shift moved for a less obvious reason, and then moved again. A
running shift is not in History, so their dates look irrelevant; they stop being irrelevant the
moment a journey **ends** one, because the shift it finalises carries the fixture's start date. Three
journeys did exactly that and read an empty list. They hung from the history anchor **or now,
whichever was earlier**, which fixed those three and left a subtler problem: on any day but a Monday
or a Tuesday the anchor is the earlier value, so a suite run on a Thursday opened them on a shift
that had been "running" for two days, with deliveries accepted two days ago. Nothing read those ages,
so nothing failed — until a reminder derived from a delivery's own age went on screen.

They now hang from **now**, which is the determinism they actually needed: the same shift length, the
same delivery ages and the same lifecycle spacing every run, inside the current week by definition,
never in the future, and with no window in the first 90 minutes of a Monday. Their delivery offsets
were compressed to sit inside the assistance thresholds at the same time, so that a journey about
grouping or expected pay stays a journey about grouping or expected pay rather than becoming one
about reminders.

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

The late-end fixture is the one no other fixture and no sequence of taps reaches, for both of the
reasons the paused-history one is unreachable: ending a shift records the clock, and a simulator
cannot be driven into recording a route. It describes a driver who stopped at `3 hr 20 min` and a
DashPilot that recorded the end at `3 hr 40 min`, with a whole capture session recorded in between —
the drive home. Its three capture sessions are deliberately **equal**, so the journey that corrects
the end can assert `4.5 mi` and state, in the same breath, that a figure scaled by the time removed
would have been about `5.6 mi`. Its one delivery finishes ten minutes before the corrected end, which
is what makes the delivery refusal reachable from the same launch. It shares the paused-history
fixture's whole-hour anchor for the same reason.

The seeded paths are app code that exists only for tests. They are DEBUG-only and in-memory, and
every one of them is another launch path to keep honest.

## UI journeys

Testing is layered, and a behaviour is pinned at the lowest layer that can show it:

1. **Domain and unit tests** (`DashPilotTests`, Swift Testing) prove every rule, figure, refusal,
   wording and export field. They are fast, run whole on every pull request, and are where a new
   behaviour is pinned first.
2. **Integration tests** in the same target run the services against a real SwiftData store,
   migrations from every frozen schema, and the seeded fixtures the journeys launch.
3. **A smoke tier of UI journeys** (`.github/ui-smoke-journeys.txt`, at most 30) drives the critical
   paths a driver's day depends on, on every pull request.
4. **The rest of the UI suite** runs in the regression workflow and holds only what needs the
   interface: navigation between screens, sheets and confirmations working together, focus and
   keyboard behaviour, scroll reach, the largest accessibility text size, VoiceOver labels and
   values, and state surviving leaving the app.

A journey reads a whole screen or flow in one launch rather than one figure per launch: one pass
down the screen in the order it is drawn, every refusal and cancellation on the way, and the
arithmetic left to the domain suite it names in its documentation comment. The audit that brought
the suite to this shape, the exact journeys it merged, removed and migrated, and why each remaining
journey needs the interface, is on [UI suite audit](ui-suite-audit.md).

The share sheet itself is never opened. `ShareLink` presents a system surface XCUITest cannot inspect
reliably, and what the export journeys are for is proving DashPilot wrote a file and offered it — not
that iOS can share one. The file's name and the count of shifts in it are read off the sheet
instead.

The permission panel is asserted only to be on screen. Which state it displays depends on the
device, and no test drives the system alert, because automating it would be brittle and would change
the permission state other tests run against.

Three lessons are worth repeating when adding journeys:

- **A synthesized tap does not move the caret.** A field the screen did not focus for itself is
  entered with the caret at position zero, so backspaces delete nothing and the text typed next is
  *prepended*: `34` became `3834`, which reads on screen as a wrong figure rather than as a broken
  step. `clear(_:in:)` is right for a field a screen focuses on appearance;
  `replaceTappedField(_:with:in:)` double-taps to select and types over the selection, which needs no
  caret. The double tap selects a **word**, so it is wrong for multi-word text, and a rule better
  reached without a tap belongs in the domain suite.

- A `List` only renders rows near the viewport, so anything below the fold does not exist until it
  is scrolled to. This bites again whenever a section above grows: adding one sentence to the
  earnings footer pushed the route section off the first screen and failed two journeys that had
  been reading it without scrolling. It bit again when the start panel gained the next shift's
  vehicle line: the seeded fixture's second history row went below the fold and eight journeys
  indexing into it failed. Reach history rows through `revealHistoryRows(_:in:)`, which scrolls until
  the last wanted row is hittable, so `count` and `element(boundBy:)` describe the fixture rather
  than the screen.
- SwiftUI mirrors an `accessibilityIdentifier` onto a button's label element as well, so an alert
  button matches twice. Use `.firstMatch`.
- A validation message drawn as a `Label` carries its identifier on its warning icon as well as on
  its text, and the icon's own label is `Warning`. **`.firstMatch` over an `.any` query is then not
  enough**: which of the two comes first is decided by the runtime's accessibility tree, and iOS
  27.0 puts the text first while iOS 26.5 puts the icon first, so a journey reading the sentence
  that way passed locally and read `Warning` in CI. Read it through `validationMessage(_:in:)`, which
  queries static texts only and so can never resolve to the icon.
- **Query an element by its type when its type is known.** `descendants(matching: .any)` filtered
  by identifier makes XCTest fault in every element on the screen one at a time, each with its own
  round trip, so its cost grows with the screen and multiplies whatever slows a round trip. History's
  rows were queried that way: in three regression runs that query made up 17 of the 27 queries
  taking 5 s or more, up to 48 s for one evaluation, while a typed button query in the same second
  took 0.24 s. They are `NavigationLink`s, reported as buttons in every journey, and are now queried
  through `app.buttons`. Keep `.any` for elements whose type really varies.
- A wait's timeout bounds the **condition**, not the time XCTest takes to read it. A reading that
  returns after the deadline is still evaluated; `waitForStillFrame(of:)` once discarded it and
  failed with the row still and wholly on screen.
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
- Type with `enter(_:into:in:)`, never `tap()` then `typeText(_:)`. Most editors focus their own
  field, and tapping a focused field raises iOS's edit menu (AutoFill, Paste) under the finger; the
  keystrokes sent while it appears are lost. `enter` taps only a field without the keyboard and
  asserts the field then holds what was typed, so a lost keystroke fails where it happened rather
  than on a row three steps later.
- The running shift's delivery entry is a bar pinned in Home's bottom safe area, and an Undo line
  sits on it. XCUITest reports a control beneath either one hittable and taps the bar instead, so
  reach a control with `scrollUntilHittable`, which drags it clear of both. Cards scrolled out of
  view are not in the hierarchy, so count deliveries from the panel's `deliveryStatus` line at the
  top rather than by counting `deliveryActionButton` from wherever the journey has scrolled to.
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

Two workflows run the tests, on a GitHub-hosted `macos-26` runner with `contents: read` and nothing
more, and share `.github/actions/prepare-simulator` for the first three steps:

1. **Selects an Xcode.** It reads `IPHONEOS_DEPLOYMENT_TARGET` out of the project and picks the
   newest installed Xcode whose iOS simulator SDK is at least that version, rather than hardcoding
   one. If none qualifies, it fails with a message naming what it found. It is deliberately not
   pinned; see [UI suite audit](ui-suite-audit.md#xcode-is-not-pinned).
2. **Prints tool versions**, so a failure can be read against the exact toolchain that produced it.
3. **Selects a simulator.** It queries `simctl` for available iPhone simulators on runtimes at or
   above the deployment target and uses the newest, by UDID.

| Workflow | When | Tests | Budget |
| --- | --- | --- | --- |
| `ci.yml` | Pull requests and pushes to `main` | One `build-for-testing`, the **whole** domain suite, then the UI journeys named in `.github/ui-smoke-journeys.txt` | 75 min |
| `ui-regression.yml` | Pushes to `main`, Mondays 07:00 UTC, `v*` tags, manual dispatch | One `build-for-testing`, then **every** UI journey | 210 min |

The UI journeys run serially in both, and nothing is skipped, retried or excused. The split exists
because the whole UI suite took two to three hours and made feedback on every change slower than the
change: a pull request now runs the critical paths, and the broad regression runs after a merge,
weekly and before a release tag, still in full. How the journeys were classified and which moved is
on [UI suite audit](ui-suite-audit.md). Obsolete runs on the same ref are cancelled through each
workflow's concurrency group, and both upload their result bundles under `if: always()`.

### How long a run takes, and the budget it is given

`ui-regression.yml`'s `timeout-minutes` is **210**, and the number is measured rather than chosen
for comfort; `ci.yml`'s is **75**, sized for a build, the domain suite and the smoke journeys at about
35 s each on the runner.

The latest measured runs, with 238 to 242 tests, took **2h28m to 2h42m** end to end (runs
36963445708, 36947255282, 36946410015, 36916384792, 36916358022 and 36963465798): 2 to 4 minutes of
`build-for-testing`, 5 to 8 of domain tests and 2h17m to 2h26m of UI journeys, about 35 seconds a
journey on the runner against about 28 locally. Main's run 37007996270, on the same 242 tests, then
took **2h54m**, with the UI journeys alone at 2h34m: six minutes inside the previous budget of 180,
while runs of one tree vary by about a quarter of an hour. That is what raised it to 210, which
leaves about half an hour over the slowest measured run. It is still a ceiling a healthy run stays
under, not a target, and it is raised again only by a run that was making progress and reached it.

The first `ui-regression.yml` run over the 82 audited journeys (run 37418449153, two journeys red)
spent **97.7 minutes** in XCTest and **101.4 minutes** in the whole test step. The next (run
37478065976, one journey red) spent **108.9 minutes** (6,534 s) in XCTest and **113.5 minutes**
(6,809 s) in the whole test operation. The budget stays at 210 until an all-green run gives a
measurement to size it from, with headroom for the variance above.

### What the red regression runs had in common

Runs 37418449153 and 37478065976 each failed a different History journey, and the journey before
had been fixed, which looks like a suite degrading over two hours. The result bundles say otherwise:

- **Nothing degrades with run length.** Launch time and the gaps between XCTest steps are slightly
  *shorter* in the last third of each run than in the first, and the failures came at positions 2,
  22 and 32 of 82.
- **The slow stretches are the simulator's own background work.** The bundle's system log shows
  Spotlight's on-device embedding pipeline (`spotlightknowledged`), scheduled by `dasd` about every
  40 minutes on a fresh simulator, running through the worst stretch of both runs (positions 30 to
  33). The app's main thread answered every XCTest request at once throughout; the time went
  between the runner and the app.
- **Each failure was a fixed short budget overlapping such a stretch**: a 5 s wait in
  `openFirstShift`, an alert's Cancel read before the alert had closed, and an 8 s still-frame wait
  spent entirely on one 25 s reading of the History row. Every journey is isolated (each launch
  builds its own in-memory store, and only the welcome's flag lives in `UserDefaults`, which
  throwaway launches ignore), and none of the three reproduced locally alone, in sequence, or in CI
  order.

Sharding the suite across fresh simulators would not help: each fresh simulator starts its own
first-boot indexing, which is when the first journeys stall. The remedy is in the helpers: typed
queries, and waits bounded by their condition rather than by how long one reading takes.

The figures below are the history that set the number.

`main` run 35553963157 was cancelled by an earlier 60-minute budget with the UI journeys still
executing. It had spent 3m25s on `build-for-testing`, 5m43s on the domain suite and 50m37s on the UI
journeys, in which **87 of the 151 journeys had passed and none had failed**. Finishing the rest at
that rate projects a UI step of about 88 minutes and a whole job of about 100. A virtualised runner
is slower and more variable than a developer's machine, so the budget is set well above the
projection rather than beside it, and stays far inside the six hours a GitHub-hosted job is capped
at.

Two things follow from this and are worth stating, because a cancelled run reads like a failing one:

- **The budget is a ceiling for a hung run, not a target.** A healthy run finishes well inside it.
  If a run reaches the budget, read the result bundle first: a run that had stopped making progress
  is a defect to find, and only one that was still passing journeys is evidence for a larger number.
- **A cancelled run's last log line is not a diagnosis.** Run 35553963157 was cancelled while a
  journey naming `fuelMilesPerGallonField` was on screen, and that journey was not failing; it was
  simply the one the clock landed on. Read the result bundle, which is uploaded on cancellation as
  well as on failure. That run's upload step ran and succeeded after the job was cancelled, which is
  what `if: always()` is there for.

`ContinuousIntegrationWorkflowTests` in the domain suite reads both workflows and the smoke list and
pins what a cancelled run cannot: both budgets inside their ranges, the pull-request stages in order
in one job with the domain suite never narrowed, every UI journey in the regression workflow and the
triggers it runs on, parallel testing off for the UI journeys, nothing skipped, retried or allowed to
fail, the result bundles uploaded under `if: always()`, and every smoke entry naming a real journey,
once, in a list of at most 30 that is at most half the suite, and the suite itself at most 90
journeys. It finds the checkout through its own `#filePath` and disables itself
where that checkout is not readable.

!!! warning "Known flakiness"

    Under parallel simulator load, XCUITest has been observed locally failing with
    `Failed to get matching snapshot(s): Error getting main window kAXErrorServerNotFound`, an
    accessibility-server failure rather than an assertion. Re-running the UI target alone has been
    green every time. If this proves reproducible on GitHub-hosted runners, the honest fix is to
    move the UI journeys into a clearly named separate job, not to drop them.

The documentation workflows are described under [Building](building.md#continuous-integration).
