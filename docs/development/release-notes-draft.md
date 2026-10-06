# Release notes draft

**0.1.0** was tagged and released on October 3, 2026, with the notes below. **0.1.1** is a draft:
nothing has been tagged or released for it. See [Release readiness](release-readiness.md).

---

## DashPilot 0.1.1 (draft)

A hardening release from a real shift on October 3, 2026.

- **Edit Stack.** Two deliveries started one at a time that turn out to share a pickup or a drop-off
  can be marked that way from the running shift, without cancelling and recording them again.
  Nothing else about them changes.
- **Older Weeks scrolls smoothly as your history grows.** Each week's routes are measured once, off
  the main thread, and a route is fetched far more cheaply on a long history.
- **An optional hourly target.** Set one in Settings; each finished shift is compared with the target
  it started with, as above, near or below, and weeks and periods count the shifts at or near theirs.
  Changing the target never changes how earlier shifts are compared.
- **A welcome for new drivers.** Four short screens on first launch, reopenable from Settings, that
  ask for nothing and explain what DashPilot keeps and that it stays on your iPhone.

---

## DashPilot 0.1.0

DashPilot is a local-first companion for delivery drivers. It keeps a truthful record of your own
shifts, deliveries, routes and earnings on your iPhone, and tells you what that record supports. It
is not connected to DoorDash or any other delivery platform; it records only what you tap.

### Shifts and deliveries

- Start, pause, resume and end a shift. Working time leaves out the time you paused.
- Record each delivery with one large control per step: arrived at pickup, picked up, delivered, or
  cancelled. Several deliveries can run at once, each with its own next step and its own clock.
- Record a newly accepted order from a bar pinned to the bottom of the screen, wherever you have
  scrolled to. An offer of several deliveries is one sheet: the count, Same pickup and Same
  drop-off, and Start.
- Correct what was recorded by mistake: undo a Delivered right away, reopen it later in the shift,
  fix which deliveries arrived together, and correct times, pauses and a shift's end afterwards.

### Pickup and parking

- Park while you are away from the vehicle, so the walk is not recorded as driving, without
  stopping your working time.
- Optionally let Park mark Arrived at Pickup and Resume Driving mark Picked Up, moving Same pickup
  deliveries together, with a short Undo.

### Mileage, earnings and fuel

- Recorded mileage from the route captured during the shift, including while you use other apps,
  with partial routes and capture gaps stated rather than filled in.
- Gross earnings for a shift and for each delivery, kept as separate facts, plus tips received
  outside the platform's amount.
- Vehicle profiles and a gas price, copied onto each shift when it starts, for an estimated fuel
  cost over that shift's recorded miles. An estimate is never counted as an expense.
- Recorded expenses, and the net after them.

### History

- This week's shifts first, with every earlier week a tap away and a summary at the top of each.
- Day, week, month and custom-range summaries that say how much of each figure was recorded, beside
  the period before.
- JSON and CSV export of a shift, a period or everything, only when you ask.

### On the Lock Screen and by voice

- A Live Activity for the running shift: working time, recorded mileage, a clock per delivery, and
  controls for the next step, Start Delivery, Park and Resume Driving. It shows no money and no
  place names.
- Siri and Shortcuts actions for starting, pausing and ending a shift, starting a delivery,
  recording its next step or marking it delivered, parking and resuming.

### Privacy

No account, no server, no analytics and no tracking. Everything stays on your iPhone unless you
export it yourself.

### Design

A new visual system: the system typeface with clear figures, one status color for each of running,
paused and parked shared with the Lock Screen, a numbered stop marker for each delivery, and layouts
checked at the largest accessibility text sizes.

### Known limitations

- Recorded mileage can be less than the distance driven: iOS can stop location updates, and gaps
  are never filled in.
- DashPilot has not yet been tested through a full shift on a physical iPhone.
- Figures describe your own recorded history. They are not predictions and do not guarantee any
  earnings.
