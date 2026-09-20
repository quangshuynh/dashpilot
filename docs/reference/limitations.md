# Limitations

Everything on this page is a current, known limitation of the implemented app. It is kept explicit
rather than implied, because most of these are the difference between a number a driver can trust
and one they cannot.

## Route capture

- **Recording continues off screen, and is still not guaranteed.** A session started with the app
  open carries on while the driver is in another app or the phone is locked. iOS may suspend or end
  the app at any time, and DashPilot does nothing to be relaunched: no significant-location-change
  monitoring, no region monitoring, no background task. iOS guarantees no background execution in
  any case.
- **A recording can only be started with DashPilot open.** When In Use authorization continues a
  session that began in the foreground; it does not deliver one that did not. A shift begun by voice
  with the app off screen records nothing until the app is opened.
- **Nothing is verified on hardware yet.** The background behaviour is proved against a stubbed
  Core Location in the domain and UI suites. A simulator cannot lock a screen, be driven, or have
  its app evicted under memory pressure, so how long a real shift keeps recording, and what it costs
  in battery, are unmeasured.
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

## Voice and system actions

- **Six actions only.** Start a shift, pause it, resume it, end it, start a delivery, record that
  delivery's next event. Nothing else DashPilot does is reachable without the screen.
- **A spoken delivery step needs exactly one delivery in progress.** With two or more, nothing is
  recorded and the refusal names the count. This is a refusal, not a gap: a sentence names no
  particular order, and guessing one would write an event into a delivery the driver did not mean.
- **A shift started or resumed by voice records no route until the app is opened**, because a
  recording can only be *started* in the foreground. The shift's own times are recorded exactly as
  they would be from the screen, and both spoken confirmations say so.
- **No cancellation, no amount, no cost, no pickup name and nothing about location** can be asked for
  by voice. Every one of them either cannot be undone or would have to be dictated.
- **Nothing is read back.** No summary, rate or total is spoken; a confirmation states only what was
  just recorded.
- **No performed intent is donated to the system**, so nothing suggests these actions at a time of
  day. App Shortcuts are the only discovery.
- **No widget, control, watch app or notification.** The intents and the shift's Live Activity are
  the whole off-screen surface.

## Shift end-time correction

- **Only the end, and only on a finished shift.** A shift's start is not correctable anywhere, and a
  delivery's own lifecycle times are corrected on the delivery rather than here. A running shift has
  no recorded end to correct: `End` is what records one, and it stops route recording and reconciles
  the Lock Screen card as it does.
- **Route recorded after the corrected end is deleted, permanently.** Moving the end earlier removes
  those positions from the store. Moving the end later again does not bring them back, and there is
  no undo, trash or archive. The confirmation states the count before anything is deleted.
- **Recorded mileage is measured again, never scaled.** No distance is ever derived from a duration.
  The retained positions are measured from their own coordinates against the corrected shift, so the
  share of the mileage a shift keeps has nothing to do with the share of the time it keeps.
- **No endpoint is invented.** Nothing is interpolated from the last retained position to the
  corrected end. The stretch between them is counted as a capture gap, exactly as it would be for any
  other shift whose recording stopped early.
- **Moving the end later adds no route and no mileage.** The added stretch has no recording behind
  it, and DashPilot reports that as one more capture gap and a partial route rather than inventing
  coverage. There is no separate "this part of the shift was never recorded" marker, and the gap
  count does not say *where* in the shift the missing stretch is.
- **A correction is refused rather than resolved.** An end before the shift's start, before anything
  a delivery recorded, past a recorded pause's own end, or reaching into a later shift is named and
  refused. Nothing is clamped, and no pause or delivery timestamp is moved to make an end fit. The
  delivery refusal names the blocking delivery and event so the driver can go and correct it, and
  that is the whole of the help it gives: the shift editor corrects no delivery.
- **A shift holding a pause that was never ended cannot be corrected at all.** That row is a store
  DashPilot cannot write — ending a shift closes its open pause — and the pause editor refuses it
  too, so such a shift has no remedy here. Deleting the shift is the only one.
- **Shifts that already overlap are not repaired.** The editor will not create an overlap with a
  later shift, but nothing merges, flags or corrects a pair a store already holds.
- **No end time is suggested.** DashPilot does not infer when a driver stopped from the last position
  it recorded, the last delivery they completed, or a stationary stretch. The instant is the
  driver's.
- **Nothing is logged about a correction beyond that one happened.** The instant, the direction and
  the number of positions removed are all absent from the log, for the reason no coordinate or amount
  is ever written to it.

## Correcting a completed delivery's recorded times

- **Only instants that already exist, and only on a finished shift.** A lifecycle stage the delivery
  never recorded gets no picker and is never created, a recorded one is never removed, and the
  terminal outcome cannot be changed here. A delivery on a running shift is refused: the shift's own
  window is what bounds the correction, and a mis-tapped completion there is reopened and finished
  properly instead.
- **A collision is refused, never resolved.** A time that would run behind another recorded event is
  named and refused, together with the event it collided with. Nothing cascades: DashPilot will not
  move a pickup back to make room for a completion, so a driver who meant to move both moves both.
- **Nothing is suggested.** DashPilot does not infer when a delivery really finished from the route,
  a stationary stretch or the next delivery's acceptance. Every instant was typed by the driver, and
  a correction is as true as their memory of the shift.
- **The route and the recorded mileage do not follow.** Correcting a delivery's times changes what
  the driver recorded about the delivery, not where the phone recorded being, so a shift can record
  mileage in minutes a corrected delivery no longer covers. That is honest rather than a defect: the
  positions are evidence and the times are a record.
- **There is no correction history.** Nothing stores what the times used to be or how many of them
  moved, in the store, in the export or in the log: the log records only that a correction happened,
  never which delivery, which stage, when, or how many stages went with it. A corrected delivery is
  indistinguishable from one recorded correctly at the time.
- **A correction cannot be taken back.** The previous times are gone once the save succeeds, and the
  only way back is to correct them again from memory.

## Shift pause

- **A pause is only what the driver recorded.** DashPilot observes nothing during one: it does not
  know whether the vehicle moved, and it never ends a pause by itself because something happened. A
  driver who forgets to resume has a shift that records no working time until they do.
- **Pausing is refused while a delivery is in progress**, and a delivery cannot be started while the
  shift is paused. Both are refusals rather than gaps: a shift holding a pause and an open delivery
  at once would report delivery active time running through hours it also reports as not worked.
- **A pause puts a gap in the route**, which is the intended consequence and not a defect. Nothing
  was recorded between pausing and resuming, so no distance is measured across it, and the shift's
  recorded mileage is a floor as it always is. The shift's route quality reports the break the same
  way it reports any other, so a paused shift usually reads as a partial route.
- **Only a finished shift's pauses are correctable, and only its completed ones.** The pauses of a
  shift that has ended can be corrected, deleted or added to from its detail screen. While a shift is
  running none of that is offered, and the open pause of a paused shift is never editable: it is
  ended by resuming or by ending the shift, both of which reconcile route capture and the Lock Screen
  card as they close it, and the editor does neither. A driver who mis-tapped the pause they are in
  resumes out of it and corrects the row afterwards.
- **A correction is refused rather than resolved.** A stretch that ends before it starts, that has no
  length, that reaches outside the shift, that overlaps another pause or that overlaps a stretch a
  delivery was open for is named and refused. Nothing is clamped, swapped, merged or nudged, and no
  delivery timestamp is ever moved to make a pause fit.
- **A pause added or corrected afterwards does not change the route**, which is the one place the
  feature leaves an inconsistency and does so deliberately. A pause recorded live stopped recording,
  so the route carries a real gap; a pause added later does not, because DashPilot never deletes
  positions it recorded to make a correction fit. A shift can therefore record mileage inside a
  stretch it also records as paused. The detail screen's route section states this rather than
  smoothing it over; the alternatives were deleting real positions or claiming a gap that never
  happened.
- **A pause's number is not stable.** Pauses are called `Pause 1`, `Pause 2` and so on by the order
  they began, so deleting one renumbers the rest and correcting a start can reorder two. The number
  is presentation only and nothing acts on a pause by it.
- **An overlapping pair of stored pauses is measured but not repaired.** The editor will not create
  an overlap, and the paused total has always unioned rather than summed, so a store that holds one
  is still measured as the stretch it covers. Nothing merges the two rows or tells the driver they
  overlap; correcting one out of the other is the repair.
- **No pause is suggested, timed or limited.** Nothing prompts a driver to pause, nothing warns that
  a pause has run long, and there is no maximum. A pause open for nine hours is recorded as a pause
  open for nine hours.
- **Nothing reminds a driver of a pause.** The shift's Live Activity does show `Shift Paused` with a
  figure that has stopped moving, which is more than the app could say before; but it never alerts,
  never makes a sound and never nudges, so a driver who is not looking at the phone is not told.
- **Paused time is not broken out in a period summary.** A period reports the working time of its
  shifts; how much of the span was paused is on each shift rather than aggregated.
- **Paused stretches are not shown against the route.** The detail screen lists the pauses and lists
  the capture segments and gaps, and nothing lines the two up or says which gap belongs to which
  pause.

## The shift's Live Activity

- **It is a picture of the store, and it can be a moment out of date.** Pressing a control runs the
  same service the app's own button runs, so a stale card costs a refusal sentence rather than a
  wrong write; but a driver can see a control that the store would now refuse.
- **A Lock Screen is a continuous surface and recording is not continuous.** The card reports what the
  route has recorded, which is a floor as it is everywhere else, and it does not claim that recording
  is running. If capture has stopped, the figure simply stops growing. The place that says whether
  capture is running, and why it is not, is the app's own status line.
- **Nothing is rendered by a test.** The card's contents, its controls, its refusals and its
  synchronisation with the store are covered by unit tests over the same snapshot the extension
  draws; what the extension makes of that snapshot is verified by running it, not by an assertion.
  XCUITest cannot reach a Lock Screen.
- **It has never run on a physical device.** The behaviour described here was verified on the iOS
  26.5 simulator, which has no battery, cannot be carried and cannot evict an app under real memory
  pressure.
- **No delivery cancellation, amount or expense can be reached from it**, and there is no Home
  Screen or Lock Screen widget of any kind. A delivery started from the card by mistake is cancelled
  in the app, which keeps it in history.
- **Past three open deliveries, the card stops drawing a clock per order** and states how many more
  are running. The controls sit below those lines on a card of fixed height, and pushing them off
  the bottom would be worse than sending a driver to the app for the fourth timer.
- **A delivery's clock is its elapsed lifecycle, and nothing more.** It counts from the moment the
  driver recorded accepting the order, which says nothing about whether they were driving, waiting
  or parked during it, and it is not reduced by a shift pause. A shift cannot be paused while a
  delivery is open, so the case does not arise in data the app can produce.
- **A paused figure is written `19:57` where the app writes `0:19:57`.** The system draws the running
  clock without an hour field until there is one, and the two figures share a place on the card, so
  the paused one follows the system rather than the app.

## Deliveries

- **Nothing is detected.** Every delivery timestamp exists because the driver tapped a control.
  DashPilot cannot see an order, a restaurant handover or a customer receipt, so a delivery that was
  not recorded is not in the app, and an event recorded late is recorded late.
- **No customer or address.** A delivery holds timestamps, its shift, the offer it arrived in and an
  optional pickup place, and nothing that says where it went or who it was for.
- **An offer is a grouping the driver recorded, and nothing more.** DashPilot reads no delivery
  platform, so an offer holds no platform identifier, no pay figure, no distance estimate and no
  customer. Whether two deliveries arrived together is recorded only because the driver said so at
  the moment they accepted them: nothing infers it from their timing, their pickup place or their
  overlap, and deliveries recorded before offers existed are each in a one-delivery offer of their
  own whether or not they really arrived together.
- **Grouping can be corrected; what a delivery recorded cannot be corrected through it.** A delivery
  can be moved between offers, split into an offer of its own, and two offers can be combined or an
  offer separated, on a running shift and on a finished one. A correction moves membership only: it
  never changes a lifecycle timestamp, a pickup place, an amount or a terminal state, and it never
  moves a delivery to another shift. There is still no control that cancels an offer as a unit,
  because cancelling is a statement about one delivery.
- **A correction cannot make an offer older than it is.** A delivery cannot be moved into an offer
  accepted after that delivery was, because an offer is an acceptance and work cannot have arrived in
  one that had not happened yet. Such an offer is not offered as a destination, and combining the two
  offers the other way round, or splitting the delivery into a new offer, is what the driver does
  instead. Neither acceptance timestamp is ever rewritten to make a grouping fit.
- **Nothing verifies a correction either.** DashPilot cannot tell which two of a driver's offers were
  really one, so nothing is suggested, highlighted or ordered by how close two acceptances are. A
  correction is as true as the driver's memory of the shift, exactly as the original grouping was.
- **No offer holds money, time or distance.** There is no offer total, no per-offer rate and no
  per-offer duration anywhere in the app or its exports. Amounts stay on the delivery they were
  recorded against, and a sum over the deliveries of an offer would read every one with no amount as
  having paid nothing.
- **Per-delivery earnings are entirely manual, and often absent.** A delivery holds an amount only
  because the driver typed one against it, after the delivery finished. DashPilot never splits a
  shift total between deliveries, never adds a shift total up from them, and never reads a missing
  amount as zero.
- **Additional tips are manual too, and nothing checks them.** DashPilot cannot tell whether a tip
  was already inside what the platform recorded paying, so nothing detects a tip recorded twice. The
  screens say plainly that a tip already in the platform's amount must not be recorded again, and
  that is the whole of the protection.
- **A delivery carrying tips and no platform amount has no total**, and one is not invented from the
  tips. Such a delivery paid the tips plus an amount nobody wrote down, so it contributes nothing to
  any subtotal and counts as uncovered, exactly as a delivery with no amount at all does.
- **A tip records when it was written down, not when it arrived.** There is no editable "when the
  money changed hands" field, and correcting a tip never moves the moment it was recorded.
- **There is no cash-on-delivery accounting.** DashPilot stores no order total, no cash collected for
  an order, no platform deduction, no reimbursement and no customer balance. A tip is money that
  reached the driver, and nothing anywhere describes money that passed through them.
- **Expected pay may only be recorded while a delivery is in progress**, and cannot be added
  afterwards. Once a delivery is delivered or cancelled the fact worth recording is what it paid, so
  the model refuses a late expectation; an existing one can still be removed. A delivery that
  finished before this existed has none and will never have one.
- **An expected amount is never turned into earnings.** Marking a delivery delivered records no
  gross amount, and neither does cancelling one. The app offers the figure back for confirmation and
  writes nothing unless the driver presses the control that says it will.
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
- **The one per-delivery rate is what it earned per recorded delivery hour**, its effective earnings
  over that delivery's own accepted-to-delivered interval. It is not a wage, it exists only for a
  delivered delivery whose platform amount was recorded, and because stacked lifecycles overlap it is
  never summed, averaged or ranked across a shift.
- **No per-delivery mileage, and so no per-delivery cost.** Route distance is measured for a shift
  and never assigned to an individual delivery.
- **No cancelled hourly rate.** A cancelled delivery may hold an amount, and showing that amount is
  all DashPilot claims about it.
- **A delivery's recorded pickup wait is only as good as the tapping**, like every other interval. An
  arrival marked late shortens it and one marked early lengthens it, and nothing detects either.
- **A delivery cannot be deleted individually**, and no lifecycle event can be created or removed by
  correcting one. Only deleting the whole shift removes a delivery. What can be corrected is narrow
  and deliberate. The pickup place can be added, changed or removed at any time, because it is not an
  event. A delivery marked delivered by mistake can be **reopened** while its shift is running, which
  removes the delivered timestamp and writes none. Once the shift has ended it can be **corrected to
  cancelled**, which reuses the recorded completion as the cancellation rather than writing a new
  time. And on a finished shift the instants it **already records** can be corrected in place. See
  the next section.
- **A delivery can only be reopened while its shift is running.** It is refused on a shift that has
  ended, and refused while the shift is paused, because a delivery cannot run through time the app
  reports as not worked. Reopening the shift itself is a separate decision DashPilot does not make.
  **The ended-shift refusal is permanent, and it was re-examined rather than inherited.** Reopening
  removes the delivered timestamp and writes none, and on an ended shift nothing can ever write it
  back: the delivery could never be delivered, cancelled or reopened again, so the correction would
  destroy a recorded fact one way and give nothing in return. It would also leave the app claiming in
  the present tense that a delivery is being worked, an offer is in progress and a finished period
  holds work in progress; and it would shorten or remove that shift's delivery active time with
  nothing on screen saying so. See
  [Why the ended-shift refusal is permanent](../product/delivery-lifecycle.md#why-the-ended-shift-refusal-is-permanent).
- **A historical completion is corrected to a cancellation without moving a time.** A `Delivered`
  recorded after the shift ended is wrong in one of two ways: the delivery never completed, or the
  time is off. `Correct to Cancelled` fixes the first, recording the cancellation at the instant the
  completion held, so every duration and period figure stays exactly where it was. The second is
  `Correct Times`, which is a different action on the same row.
- **A correction to cancelled cannot be taken back.** A cancelled delivery is terminal and nothing
  reopens one, so a driver who corrects the wrong row has no remedy but deleting the shift. The
  correction is confirmed by a sentence naming the delivery for exactly that reason.
- **Correcting a completion removes the two figures that needed one.** The delivery's accepted to
  delivered duration and what it earned per recorded delivery hour both go, because each needs a
  completion to measure to. That is their existing definition rather than a decision this correction
  made, and it means a driver who corrects a delivery loses a figure they may have been reading.
- **A historical correction is in the app only**, on the finished shift's own record. Not on the
  Live Activity, not in a shortcut and not by voice, for the reason reopening is not.
- **A cancelled delivery cannot be reopened.** Only a delivery recorded as delivered can. Taking back
  a cancellation is a different statement with different consequences, and it has deliberately not
  been decided rather than assumed to work the same way.
- **Reopening is refused rather than guessed at over a store it cannot read.** A delivery recording a
  pickup with no arrival before it, or timestamps that run backwards, is left exactly as it is: the
  row says two contradictory things and does not say which is the mistake. Neither is reachable
  through the app.
- **Reopening is in the app only.** Not on the Live Activity, not in a shortcut and not by voice,
  because a correction aimed at one of several deliveries needs a screen that can name them.
- **The immediate undo is short lived by design, and names the most recent completion only.** It is
  offered for a few seconds after the tap and then goes, and marking a second delivery delivered
  replaces it rather than queueing both. The deliberate control has no deadline and lists every
  delivered delivery of the shift, so nothing is lost, but a driver who expects the undo to still be
  there minutes later will not find it.
- **Reopening a delivery does not restore what the mis-tap already set off.** If the delivery carried
  an expected amount, the confirmation it raised was raised; dismissing or answering that is a
  separate action with its own record.
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
  take-home or tax figure, and none is a mileage deduction. Recorded expenses are a separate record
  and are subtracted in exactly one place, a period's net after recorded expenses, which is also not
  profit.
- **USD only.** Nothing converts currencies or records which currency a shift was earned in.
- **Aggregates cover a day, a week, a calendar month or a chosen date range.** No quarter, no year,
  no all-time total, no best or worst shift, no chart and no sorting. A period may be read beside the
  equivalent period immediately before it, and no further back than that.
  See [Period summaries](../product/period-summaries.md).
- **Expected pay is entered by the driver too, and nothing checks it.** DashPilot reads no offer,
  so an expected amount is what the driver typed and no more. It is never counted into any figure,
  and a delivery carrying one has recorded no earnings.
- **There is no expected total on a running shift, by decision.** Each delivery shows its own
  expected amount and nothing sums them. A shift-level total would read every delivery with no
  expected amount as one expected to pay nothing, which is the same mistake as summing recorded
  delivery amounts into a shift figure. There is also no expected-versus-recorded difference
  anywhere: the app states both amounts and draws no conclusion from the gap.
- **Confirming an expected amount is a driver action and can be missed.** Nothing chases an
  unconfirmed one. A delivery can sit in history indefinitely with an expected amount and no gross
  recorded, which the screen says plainly rather than resolving, and which every earnings figure
  correctly treats as a delivery that recorded nothing.
- **A running shift shows recorded mileage, working time and delivery counts, and nothing derived
  from money.** Shift gross earnings cannot be recorded until a shift has finished, so no rate is
  derived for one in progress and the screen says so. The expected amounts on a shift's own delivery
  cards are the one place money appears on that screen, and no figure is derived from them. Delivery active time is finalised only once a
  shift ends, and is not shown live either.
- **Live mileage is a reading, not a second record.** It is measured from the same stored positions,
  by the same calculation, and nothing derived from it is written to the store. A route that already
  held positions out of order would be measured correctly by the finished shift and only
  approximately while it runs; capture cannot produce one, because a candidate that duplicates or
  precedes the last retained sample is rejected.
- **Live mileage moves in steps, not continuously.** The store is read every couple of seconds and
  the figure is written to a tenth of a mile, so a driver watching it sees it advance in tenths
  rather than climb.

## Period summaries

- **Day, week, month and a chosen date range.** No quarter, no year and no all-time period.
- **A chosen range is not persisted.** It survives switching between period lengths while the screen
  is open, and is gone at the next launch. There are no saved or named reports.
- **A chosen range cannot reach into the future**, and has no previous or next to step to.
- **A reversed range is refused rather than corrected.** An end date before the start date will not
  apply, and the dates are never silently swapped.
- **A shift is assigned by where it started**, whole. A shift running past midnight counts entirely
  in the day it began, so a driver who works overnight will see their nights land on the day they
  clocked on rather than split across two.
- **A period total is a subtotal of the shifts that answered.** Shifts with no amount recorded are
  excluded and counted, never read as `$0.00`, so a period figure is a floor in the same way recorded
  mileage is.
- **Rates cover only the shifts carrying both halves of them.** A shift with an amount but no
  measurable route contributes to neither side of the per-mile rate, so the three rates on one screen
  routinely rest on different subsets — each states its own.
- **Recorded mileage across a period is a floor with no upper bound**, exactly as it is for one
  shift, and partial routes are counted in it. The count of partial routes is reported; how much
  distance they missed is not, because nothing can say.
- **Delivery active time is summed per shift, never unioned across shifts.** Two shifts that overlap
  in clock time — which the app cannot produce, but a store could hold — would be counted twice.
- **Two periods, and no more.** A period is compared with the equivalent period immediately before
  it and with nothing else: no third period, no series, no chart, no trend line, no best or worst
  day, no streak, no goal and no projection. Nothing extrapolates a period that has not finished.
- **A comparison is between records, not between weeks of work.** More recorded is not better and
  less recorded is not worse; the app holds what the driver entered and never saw the work.
- **A percentage change is often withheld, and that is the normal case.** It is stated only when both
  figures exist, the previous one is not zero, the selected period has finished, and both sides cover
  all of their records — which excludes every expense figure, every period holding a partial route,
  and every period still in progress. The difference itself is still shown, with the reason the
  percentage is not.
- **Differences in length are stated, never corrected.** A 31-day month against a 28-day one is
  reported as those two months, with their day counts; nothing is scaled to a common length, because
  a scaled figure is an estimate.
- **Net after recorded expenses and the median recorded pickup wait are not compared.** Each side of
  the first is already a difference between two floors, and two medians over different pickups
  describe no wait anybody experienced.
- **No merchant analysis.** The distinct pickup-place count is a count; no earnings, wait or score is
  grouped by place.
- **Aggregates are recomputed on every view.** A period's routes are measured when it is selected, so
  a week of long routes is measured again each time the driver switches to it. Acceptable at current
  route sizes; caching is deferred until there is a measurement behind it.

## Recorded expenses

- **Only what the driver types exists.** DashPilot observes no purchase, so a period's recorded
  expense total is a floor and a period with none recorded is not a period that cost nothing. A
  completed shift's estimated fuel cost is not an exception: it is derived from that shift's mileage
  and the driver's own assumptions, it becomes no expense, and no expense total includes it.
- **An expense total carries no coverage pair**, because there is no denominator: nothing knows how
  many costs went unrecorded. A count of records is all that can honestly be stated.
- **An expense belongs to a date, not to a shift.** There is no per-shift, per-delivery or per-mile
  **recorded** cost anywhere, and no recorded net figure at shift level. Attaching a cost to work the
  driver did not attach it to would be an attribution the app invented.
- **A recorded fuel expense and an estimated fuel cost are never reconciled.** Both can describe the
  same money, in different places, and DashPilot does not know which shifts a tank was burned on. It
  states the overlap rather than matching them, and never adds or nets the two.
- **Net after recorded expenses is not profit**, not take-home pay and not a tax figure. It is one
  recorded subtotal less another, and it is absent unless both halves were recorded.
- **Five fixed categories.** No custom categories, no subcategories and no renaming.
- **No recurring expenses, receipts, photographs, attachments, merchant, payment method or vehicle.**
- **No tax treatment of any kind**: no deduction, no mileage allowance, no depreciation and no
  classification of a cost as claimable.
- **Expenses are not in the CSV export.** Its rows are deliveries, and an expense belongs to a date
  rather than to one, so it has no row there, the same deliberate refusal the period summary gets.
- **A note is capped at 120 characters** and is exported as the driver wrote it.

## Estimated fuel and net

- **Both inputs are assumptions the driver types.** DashPilot observes no vehicle and reads no pump.
  It does not check a fuel economy, learn one, or notice that a figure is wrong.
- **No gas-price lookup and no station search**, ever: there is no network access in the app at all.
  A price is whatever the driver last entered.
- **One vehicle, and no vehicle record.** There is no vehicle list, no make or model, no tank size
  and no efficiency by season, terrain or load. The most recent pair a driver recorded seeds the next
  shift's fields, and that is the whole of the "default".
- **The estimate covers recorded mileage only.** Recorded mileage is a floor, so the estimated fuel
  is a floor and the estimated net is a ceiling. Where the route is partial the screen says so; where
  it is complete, "no gap was detected" is still a statement about the detection.
- **Estimated net after fuel is not profit**, not take-home pay and not a tax figure, and nothing for
  wear, insurance, maintenance, depreciation, phone costs or tax is subtracted anywhere in DashPilot.
- **It subtracts no recorded expense**, because no expense is attached to a shift. Net after recorded
  expenses remains a period figure.
- **Nothing is aggregated.** There is no period-level estimated fuel, no estimated net for a day, a
  week or a month, and no comparison of one shift's estimated net with another's.
- **Nothing is exported but the assumptions.** The estimated gallons, the estimated fuel cost and the
  estimated net are in no file, in either format.
- **A shift recorded before this existed carries no assumptions**, and none was backfilled. It
  reports no estimate rather than an estimate of nothing.

## Data and safety

- **Deletion is permanent.** No undo, no trash and no archive. A mis-tap past the confirmation costs
  the shift and its route; exporting first is possible but is not offered as part of the deletion
  flow and is not a prompt.
- **No backup beyond the device.** No accounts, no sync and no cloud copy of any kind. An export is a
  copy the driver makes and places somewhere themselves; it is not a backup the app manages.
- **No import.** An exported file cannot be read back in. There is no restore, no merge and no way to
  move history onto another device through the app.

## History

- **History shows one week, and there is no way to widen it.** The default list is the current
  Monday-to-Sunday week and the older weeks are a separate screen. There is no All Shifts list, no
  search, no filter by date, amount or pickup place, and no setting for how much History shows.
- **History's week always starts on Monday; a period summary's week starts on the day the device
  says a week starts.** For a driver whose calendar starts the week on Sunday, the two screens
  describe weeks a day apart. Both name the dates they cover, so the difference is readable rather
  than hidden, but nothing reconciles them and no figure follows History's week.
- **The older weeks are a list, not a summary.** Each group is headed by its dates and footed by how
  many shifts it holds. No earnings, mileage or rate is totalled per week there; that is what the
  [period summary](../product/period-summaries.md) is for, and a second set of weekly figures
  computed somewhere else is exactly the drift this project designs against.
- **Every completed shift is loaded to build the two lists.** The rows are rendered lazily and a
  route is measured only when its row appears, so what a long history costs is memory for the shift
  records rather than work per row. There is no paging, no fetch limit and no cursor, and nothing has
  been measured against a store holding years of work.
- **A shift with a wrong date is filed by that date.** DashPilot does not detect a device clock that
  was wrong when a shift was recorded. A shift stored with a date in a future week is listed under
  Older Weeks rather than in the current one, which keeps it reachable but is the wrong heading for
  it. A shift's **end** can be corrected; its start cannot, and the start is what decides which week,
  day and period the shift belongs to.

## History export

- **Completed shifts only.** A running shift is never exported, and there is no export control on
  one.
- **No raw coordinates.** A route is exported as a measurement and a description of its coverage.
  There is no GPX, KML or GeoJSON output, and no way to export positions at all.
- **The CSV carries neither the period summary nor the recorded expenses**, and a single shift's
  file carries no expenses at all because no expense belongs to a shift.
- **The CSV carries no expected pay either.** It is in the JSON form only. A spreadsheet column is
  something people sum, and an amount that is explicitly not earnings sitting beside one that is
  would be summed as though it were. Deliberate, and it is also why the format version did not move:
  a new JSON key is additive, an inserted CSV column would not be.
- **The CSV carries no period summary.** Each of a summary's figures is paired with the count of
  shifts behind it, and a flat table cannot keep that pairing, so the summary is JSON-only. This is a
  deliberate refusal rather than a gap to be filled by flattening it.
- **CSV cells beginning with a formula character are prefixed with an apostrophe.** That is a visible
  change to a pickup place's name as it appears in the file. It is the only defence that survives an
  RFC 4180 parser stripping the quotes.
- **A rate is exported at two decimal places**, the figure the app displays, not the six fraction
  digits it is derived at.
- **No column selection, date-range builder or scheduled export.** The scope is decided by the
  control that starts the export, and the only choice on the sheet is JSON or CSV.
- **No PDF, spreadsheet or archive format**, and nothing is packaged: one file per export.
- **An export is not a tax statement**, not a deduction calculation and not a record from any
  delivery platform. The expenses in a file are the ones the driver typed, and the net beside them is
  not profit. Nothing in it was imported, confirmed or reconciled against one.
- **Once a file is shared, DashPilot knows nothing about it.** Where it goes and what happens to it
  are outside the app, and there is no revoke, no expiry and no record that it was shared.
- **Exports are temporary and are not kept.** The export directory is emptied before each new export
  and once at launch, so there is no in-app list of past exports to return to.

## Product scope

- **Little is built on the delivery records yet.** Delivery active time, the rate over it, an
  optional pickup place, that place's recorded pickup waits, an optional manually entered amount per
  delivery and the period summaries over all of it are the whole of it: no merchant scoring, no
  merchant profitability, no earnings per pickup place, no wait-time recommendation, no offer
  profitability, no tips-versus-base breakdown and no automatic detection. A completed shift's
  estimated fuel and estimated net are derived from that shift's own mileage and assumptions and read
  nothing from its deliveries.
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
