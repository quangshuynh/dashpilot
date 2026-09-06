# Limitations

Everything on this page is a current, known limitation of the implemented app. It is kept explicit
rather than implied, because most of these are the difference between a number a driver can trust
and one they cannot.

## Route capture

- **Foreground only.** No background location mode, no Always authorization, no
  significant-location-change or region monitoring, and no background task. Capture stops whenever
  DashPilot is not in front, and iOS guarantees no background execution in any case.
- **Recorded mileage is a floor with no upper bound.** Nothing states how much is missing, because
  nothing can.
- **Gaps have counts but no location in the shift.** DashPilot says a route has two gaps, not
  whether the missing miles were the commute or the deliveries.
- **Thresholds are choices, not calibrations.** Accuracy, staleness, movement, speed and the
  two-minute continuity interval are defensible engineering values, not values tuned against
  recorded driving.
- **Routes recorded before schema v3 carry no capture sessions.** Their continuity is inferred from
  timestamps and they are always reported as partial.
- **Nothing is drawn.** There is no map and no route visualisation.

## Deliveries

- **Nothing is detected.** Every delivery timestamp exists because the driver tapped a control.
  DashPilot cannot see an order, a restaurant handover or a customer receipt, so a delivery that was
  not recorded is not in the app, and an event recorded late is recorded late.
- **No customer or address.** A delivery holds timestamps, its shift and an optional pickup place,
  and nothing that says where it went or who it was for.
- **Per-delivery earnings are entirely manual, and often absent.** A delivery holds an amount only
  because the driver typed one against it, after the delivery finished. DashPilot never splits a
  shift total between deliveries, never adds a shift total up from them, and never reads a missing
  amount as zero.
- **The shift total and the delivery amounts are not reconciled.** They may differ in either
  direction — unrecorded deliveries, stacked orders paid together, shift-level adjustments — and the
  app reports no shortfall, warning or error about the difference. It also offers no screen that
  compares them.
- **Delivery active time is only as good as the tapping.** It is the union of the intervals between
  recorded events, so a delivery marked delivered twenty minutes late reads as twenty minutes longer,
  and a delivery never recorded contributes nothing at all. Nothing detects or corrects either.
- **"Active" says nothing about what the driver was doing.** It means a recorded delivery had not
  reached a terminal state. It is not driving, working, productive or billable time, and
  non-delivery time is not idle time.
- **The one per-delivery rate is gross per recorded delivery hour**, over that delivery's own
  accepted-to-delivered interval. It is not a wage, it exists only for a delivered delivery with a
  recorded amount, and because stacked lifecycles overlap it is never summed, averaged or ranked
  across a shift.
- **No per-delivery mileage, and so no per-delivery cost.** Route distance is measured for a shift
  and never assigned to an individual delivery.
- **No cancelled hourly rate.** A cancelled delivery may hold an amount, and showing that amount is
  all DashPilot claims about it.
- **A delivery's recorded pickup wait is only as good as the tapping**, like every other interval. An
  arrival marked late shortens it and one marked early lengthens it, and nothing detects either.
- **A recorded delivery's timestamps cannot be edited, and a delivery cannot be deleted
  individually.** A mis-tapped lifecycle event stays as recorded, and only deleting the whole shift
  removes it. The pickup place is the one exception, because it is not an event: it can be added,
  changed or removed at any time, including on a finished delivery.
- **Overlapping deliveries are unioned, never summed.** A 30-minute delivery and a 25-minute one
  overlapping by 20 minutes is 35 minutes of delivery active time. The per-delivery durations in the
  shift's delivery list are still separate figures and are never added together.
- **Nothing analyses stacking.** DashPilot records that two deliveries overlapped. It does not know
  they were offered together, does not group or pair them, and derives nothing from the fact that
  they overlapped.
- **Delivery numbers are local presentation.** `Delivery 1` and `Delivery 2` are counted from the
  order the shift accepted them. They are not persisted, and they are not a delivery platform's
  order numbers.
- **Ending a shift is blocked while any delivery is in progress**, deliberately. It costs one extra
  tap per unfinished delivery.

## Pickup identity

- **Entirely manual, and usually absent.** A pickup place exists only because the driver typed it.
  Nothing detects a pickup, and a delivery they did not name has no place — so the catalogue is a
  record of what they chose to record, not of where they actually went.
- **No lookup of any kind.** No geocoding, no place search, no address, no coordinate, no phone
  number and no store number. A place is a name and nothing else, and it would not be recognised
  outside this app.
- **Matching is exact after normalisation, not fuzzy.** Whitespace, case, Unicode composition and
  apostrophe style are folded; punctuation, diacritics and abbreviations are not. `McDonald's` and
  `McDonalds` are two places, and so are `Cafe Rio` and `Café Rio`. The rule errs toward duplicates,
  which a driver can see and avoid, over merges, which they cannot undo.
- **The normalisation key is persisted.** If a future OS changes how case folding behaves, a name
  typed afterwards could fail to match a place stored before it, producing a duplicate. Nothing
  re-keys the catalogue.
- **Correcting a place is manual and explicit.** A place can be renamed, and one place can be merged
  into another, from the place's own history screen. Neither happens automatically: there is no
  similarity matching, no edit distance, no duplicate suggestion and no background scan, so two
  spellings of one business stay two places — with two separate wait histories — until the driver
  merges them.
- **A merge cannot be undone, and leaves no trace.** The source place is removed, no alias or
  redirect is kept, and nothing records that it ever existed. Its deliveries and their recorded times
  survive under the destination; the name does not. Merging the wrong pair means re-creating a place
  and reassigning each delivery to it by hand.
- **A rename leaves no alias either.** The old spelling stops matching, so typing it afterwards
  creates a new place rather than finding the renamed one.
- **A failed save leaves the store correct and the screen possibly stale.** A rename or merge the
  store refuses is rolled back in full, and nothing is half-applied. But SwiftData does not reliably
  restore the relationship arrays cached on objects a screen is already holding, so a sheet left open
  after such a failure may show a figure the store does not agree with until it is reopened.
- **A place nothing references cannot be renamed or merged away.** Both controls are reached from a
  delivery that names the place, so a place whose deliveries were all deleted can still be chosen as
  a merge destination but cannot itself be corrected or removed.
- **Unreferenced places are never collected.** A place whose deliveries have all been deleted stays
  in the local catalogue. It stops appearing in the recent list, and typing the name finds it again.
- **No visit count, ranking or score.** A place's recorded pickup waits are summarised — see below —
  and nothing else is derived from it.

## Pickup wait

- **Only two events are counted.** A wait is `pickedUpAt - arrivedAtPickupAt` and nothing else. A
  delivery missing either end contributes nothing, so a place's history covers the pickups the driver
  tapped through completely, not the times they went there.
- **A delivery cancelled before pickup contributes nothing**, however long the driver stood there.
  That is a deliberate rule, not an oversight: the app was never told the order was collected.
- **A single recorded wait is not a typical wait**, and is presented as one observation. Two is the
  threshold for offering a median, which is a wording decision, not evidence that two pickups predict
  a third.
- **The median describes the past only.** It is not a forecast, a confidence interval or an
  estimate, and a place's next pickup is free to be nothing like its recorded ones.
- **Nothing is trimmed.** A forty-minute wait with valid timestamps stays in the history and in the
  median's input. No outlier rejection of any kind is applied.
- **No merchant comparison.** Places are never ranked, scored, graded or coloured against each other.
  The one screen that lists places is the merge destination picker, which is alphabetical and shows
  no figures.
- **Waits are per place, not per hour or per day.** Nothing splits a place's history by time of day,
  weekday or shift, so a place that is quick at lunch and slow at nine has one median covering both.
- **No live use.** A running shift shows no historical wait, so nothing informs a decision at the
  moment an offer arrives.
- **Nothing links waits to earnings.** No figure divides one into the other.

## Earnings and metrics

- **Earnings are typed by the driver.** Nothing is imported, and the app cannot know whether an
  amount includes tips, bonuses, promotions, adjustments or reimbursements.
- **The per-shift-hour rate divides by elapsed time**, waiting included, and the per-active-delivery-hour
  rate divides by unioned delivery time. Neither is a wage: the first ignores what the driver was
  doing, the second measures only when deliveries were open, and both are gross.
- **The per-recorded-mile rate is biased upward** by exactly the mileage capture missed, so it is
  not comparable to a per-mile figure from an app that records in the background.
- **Every rate is gross.** Nothing subtracts fuel, wear, insurance or tax. None is a profit,
  take-home or tax figure, and none is a mileage deduction.
- **USD only.** Nothing converts currencies or records which currency a shift was earned in.
- **Nothing aggregates.** No weekly or all-time totals, no best or worst shift, no chart and no
  sorting. Figures are read one shift at a time.
- **No live figures.** A running shift shows no mileage, no rate and no active time. Active-time
  figures are finalised only once a shift ends.

## Data and safety

- **Deletion is permanent.** No undo, no trash, no archive and no export before deleting. A mis-tap
  past the confirmation costs the shift and its route.
- **No export.** There is no CSV or JSON output, so the only copy of a driver's history is the one
  on the device.
- **No backup beyond the device.** No accounts, no sync and no cloud copy of any kind.

## Product scope

- **Little is built on the delivery records yet.** Delivery active time, the rate over it, an
  optional pickup place, that place's recorded pickup waits and an optional manually entered amount
  per delivery are the whole of it: no merchant scoring, no merchant profitability, no earnings per
  pickup place, no wait-time recommendation, no offer profitability, no tips-versus-base breakdown,
  no aggregate across shifts and no automatic detection.
- **No recommendations, predictions or machine learning.** None is implemented, and none is claimed.
- **No delivery-platform integration**, by design and permanently. See
  [Product overview](../product/overview.md#boundaries-the-project-will-not-cross).

## Engineering

- **Measurement is repeated per view.** The history row and the detail screen each measure a shift's
  route when they appear, so opening a shift walks its route a second time. This is acceptable at
  current route sizes, and caching is a deliberate decision deferred until there is a measurement
  behind it.
- **Test-only app code exists.** The debug-only seeded-history and seeded-pickup-history launch
  paths are app code that exists for tests. Both are in-memory and DEBUG-gated, and each is one more launch path to keep honest.
- **UI tests can fail environmentally.** XCUITest under parallel simulator load has been observed
  failing in the accessibility server rather than on an assertion. See
  [Testing](../development/testing.md#continuous-integration).
- **The documentation site has not been published yet.** The deployment workflow exists; enabling
  GitHub Pages for the repository is a manual step that has not been taken.
