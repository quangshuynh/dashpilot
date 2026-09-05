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
- **No restaurant, customer or address.** A delivery holds timestamps and its shift, and nothing
  that says where it went or who it was for.
- **No per-delivery earnings.** Gross earnings are one figure for the whole shift, and DashPilot has
  no source from which to split it between deliveries.
- **Deliveries are not used in any rate.** The hourly rate still divides by the shift's whole
  elapsed time; nothing derives active-versus-idle time, a per-delivery rate or an average wait.
- **A recorded delivery cannot be edited or deleted individually.** A mis-tapped event stays as
  recorded, and only deleting the whole shift removes it.
- **One delivery at a time.** A driver stacking two orders can record only one lifecycle, so the
  second order's events are either merged into the first or not recorded at all.
- **Ending a shift is blocked by a delivery in progress**, deliberately. It costs one extra tap.

## Earnings and metrics

- **Earnings are typed by the driver.** Nothing is imported, and the app cannot know whether an
  amount includes tips, bonuses, promotions, adjustments or reimbursements.
- **The hourly rate divides by elapsed time.** Recorded deliveries are not used in it, so for a
  driver who idles a lot it understates how the driving itself performed, and the app cannot say by
  how much.
- **The per-recorded-mile rate is biased upward** by exactly the mileage capture missed, so it is
  not comparable to a per-mile figure from an app that records in the background.
- **Both rates are gross.** Nothing subtracts fuel, wear, insurance or tax. Neither is a profit,
  take-home or tax figure, and neither is a mileage deduction.
- **USD only.** Nothing converts currencies or records which currency a shift was earned in.
- **Nothing aggregates.** No weekly or all-time totals, no best or worst shift, no chart and no
  sorting. Figures are read one shift at a time.
- **No live figures.** A running shift shows no mileage and no rate.

## Data and safety

- **Deletion is permanent.** No undo, no trash, no archive and no export before deleting. A mis-tap
  past the confirmation costs the shift and its route.
- **No export.** There is no CSV or JSON output, so the only copy of a driver's history is the one
  on the device.
- **No backup beyond the device.** No accounts, no sync and no cloud copy of any kind.

## Product scope

- **Nothing is built on the delivery records yet.** No restaurant scoring, no wait-time
  recommendation, no offer profitability, no aggregate across shifts and no automatic detection.
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
