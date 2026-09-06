# Voice and system actions

The four shortest actions in DashPilot can be performed without looking at the phone: by voice, from
the Shortcuts app, from Spotlight, or from anywhere else iOS offers an App Shortcut. This is the
driving-safety case the app is designed around. A start time recorded when the driver says so is more
accurate than one recorded three minutes later, once the phone has been picked up, unlocked and
tapped.

Nothing here is a new capability. Each action calls the same service the on-screen control calls, and
every rule that refuses a tap refuses a sentence.

## What can be asked for

| Action | What it records | When it is refused |
| --- | --- | --- |
| Start Shift | A shift, starting now | A shift is already running |
| End Shift | The end of the running shift | No shift is running, or a delivery on it is still in progress |
| Start Delivery | A delivery accepted now, alongside any already running | No shift is running |
| Record Delivery Progress | The next event of the delivery in progress: arrived at the pickup, then picked up, then delivered | No shift is running, no delivery is in progress, or **more than one delivery is in progress** |

Suggested phrases, offered by the system as soon as the app is installed:

- "Start a shift in DashPilot", "Start my DashPilot shift"
- "End my shift in DashPilot"
- "Start a delivery in DashPilot"
- "Record delivery progress in DashPilot"

None of them opens the app. An action that put a screen in front of the driver would be slower than
the tap it is meant to replace.

## The rule that exists only off screen

DashPilot supports stacked deliveries, so a driver can be carrying two or three orders at once. On
screen that is unambiguous: each delivery has its own card and its own button, and a tap lands on the
delivery it was printed under.

A spoken "record the next step" has no card. With two deliveries in progress it names neither of
them, and every way of choosing one (the newest, the oldest, the one furthest along) would write a
driver's sentence into a record they did not mean. So DashPilot records nothing and says so:

> 2 deliveries are in progress, so DashPilot cannot tell which one you mean. Open DashPilot and
> record the step on that delivery.

The refusal lifts by itself. Once one of the two has been delivered or cancelled, the next spoken
step reaches the one that is left.

`Start Delivery` is not affected, because it names no existing delivery: it creates one.

## What the driver hears back

There is no screen to glance at afterwards, so the confirmation is the whole report:

- "Shift started at 5:12 PM. DashPilot records your route only while the app is open."
- "Shift ended after 4 hours, 12 minutes."
- "Delivery 2 started. 2 deliveries in progress."
- "Delivery 1 recorded as picked up."

The event named is read back from the delivery after the write, so a confirmation cannot describe an
event the store did not record. A fact DashPilot does not have is left out rather than filled in: a
delivery whose number could not be resolved is confirmed as "Delivery", never as "Delivery 1".

No confirmation states an amount, a distance, a rate or a total.

## Route capture still needs the app open

Route capture is foreground-only, and that has not changed. **A shift started by voice records no
route until DashPilot is opened**, which is why every start says so out loud, and why the intent's
description in the Shortcuts app says it too. The shift's own times are recorded exactly as they
would be from the screen; the recorded mileage is the part that waits.

## What is deliberately not offered

| Not offered | Why |
| --- | --- |
| Cancelling a delivery | It cannot be undone, and spoken it could not be aimed at one of several deliveries |
| Recording earnings, per shift or per delivery | An amount is dictated, misheard and then believed. Amounts are typed, afterwards, on a screen |
| Recording an expense | The same, with a category and a date as well |
| Naming a pickup place | A dictated name would create a new place under a spelling the driver never saw |
| Anything about location | Nothing about position is asked for or reported here |
| Reading back a summary, a rate or a total | A figure heard without its coverage and its wording is a figure misread |

None of the four intents takes a parameter, so nothing a driver says is stored, and no shortcut,
suggestion or tile carries a value.

## Privacy

- **Nothing is donated.** DashPilot does not donate performed intents to the system. App Shortcuts
  are offered from installation, which is all the discovery this needs; a donation would additionally
  feed the system's prediction of what a driver does and when, and a model of somebody's working
  pattern is not a side effect worth accepting for four voice commands.
- **The intents run on a locked device**, because a phone in a cradle is locked for most of a shift.
  What they write is a timestamp the driver just witnessed, and what they say back is that same fact.
- **The log records which action ran and which rule refused it**, and never a timestamp, a count of
  what was said, or anything else. See [Privacy and logging](../architecture/privacy.md).

## Where the rules live

`IntentLifecycleService` is the only type the four intents call. It owns no lifecycle logic: it calls
`ShiftService` and `DeliveryService`, carries their refusals through word for word, and adds the one
rule above. If a rule there disagreed with the app, the app would be right, so there is no rule there
to disagree with. See [Architecture overview](../architecture/overview.md#system-surfaces-app-intents).
