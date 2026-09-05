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
- **No per-delivery earnings.** Gross earnings are one figure for the whole shift, and DashPilot has
  no source from which to split it between deliveries.
- **Delivery active time is only as good as the tapping.** It is the union of the intervals between
  recorded events, so a delivery marked delivered twenty minutes late reads as twenty minutes longer,
  and a delivery never recorded contributes nothing at all. Nothing detects or corrects either.
- **"Active" says nothing about what the driver was doing.** It means a recorded delivery had not
  reached a terminal state. It is not driving, working, productive or billable time, and
  non-delivery time is not idle time.
- **No per-delivery rate and no average wait.** The one delivery-derived rate is over the whole
  shift's active time.
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
- **The first spelling is permanent.** A place cannot be renamed. Correcting a typo means assigning a
  new place to each delivery that used the old one.
- **Unreferenced places are never collected.** A place whose deliveries have all been deleted stays
  in the local catalogue. It stops appearing in the recent list, and typing the name finds it again.
- **Nothing is derived from a place yet.** No wait statistic, no visit count, no ranking and no
  score — see below.

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

- **Little is built on the delivery records yet.** Delivery active time, the rate over it, and an
  optional pickup place are the whole of it: no wait statistic per place, no merchant scoring, no
  wait-time recommendation, no offer profitability, no per-delivery earnings, no aggregate across
  shifts and no automatic detection.
- **No recommendations, predictions or machine learning.** None is implemented, and none is claimed.
- **No delivery-platform integration**, by design and permanently. See
  [Product overview](../product/overview.md#boundaries-the-project-will-not-cross).

## Engineering

- **Measurement is repeated per view.** The history row and the detail screen each measure a shift's
  route when they appear, so opening a shift walks its route a second time. This is acceptable at
  current route sizes, and caching is a deliberate decision deferred until there is a measurement
  behind it.
- **Test-only app code exists.** The debug-only seeded-history launch path is app code that exists
  for tests. It is in-memory and DEBUG-gated, and it is one more launch path to keep honest.
- **UI tests can fail environmentally.** XCUITest under parallel simulator load has been observed
  failing in the accessibility server rather than on an assertion. See
  [Testing](../development/testing.md#continuous-integration).
- **The documentation site has not been published yet.** The deployment workflow exists; enabling
  GitHub Pages for the repository is a manual step that has not been taken.
