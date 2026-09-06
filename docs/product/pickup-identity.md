# Pickup identity

A delivery answers *what were you doing inside a shift*. Pickup identity answers one further
question, and only one: **which place did this delivery come from?**

It exists so that a driver can recognise a recurring pickup in their own history, and so that a
later analysis of pickup waits has one stable thing to group by. It is not a contact list, not a
merchant database and not a directory.

!!! warning "Optional, manual, and local"

    A pickup place is typed by the driver. DashPilot performs **no geocoding, no place search and no
    lookup of any kind** — there is no network code in the project — and it has no integration with
    DoorDash or any other delivery platform. A delivery with no pickup place is a complete, ordinary
    delivery, and the lifecycle never waits for one.

## What is recorded, and what is not

| Recorded | Not recorded |
| --- | --- |
| A display name, as the driver spelled it | Address, city, postcode |
| A normalised key used only to match names | Coordinates or a map pin |
| When the place was first named on this device | Phone number, store number, chain, category |
| Which deliveries reference it | The customer, the destination, a platform order ID |

Nothing aggregated is stored on a place: no visit count, no last-used date, no average wait and no
score. Every one of those is derivable from the deliveries that reference it, and a stored copy is a
second answer free to drift away from the first — the same rule DashPilot applies to mileage, rates
and delivery state.

## Why a shared place rather than a name on each delivery

`McDonald's`, `mcdonalds` and `McDonald's ` typed across three nights are one place. Stored as free
text on three deliveries they would be three unrelated strings, and a question like *how long do I
usually wait here* would have no single thing to answer about.

So a pickup place is its own record, and a delivery holds a **reference** to it. Two deliveries from
the same place point at the same row.

## Normalisation

Every name is reduced to a **comparison key** that decides identity, while the **display form** keeps
the driver's own spelling for the screen. The key is never shown, never spoken and never logged.

Both forms start from the same cleanup:

1. **Unicode canonical composition**, so an accent typed as one code point and the same accent typed
   as a letter plus a combining mark are the same text rather than two byte sequences that look
   identical.
2. **Whitespace collapse**: every run of whitespace or newlines becomes one space, and the ends are
   trimmed.

That result is the display form. The key then adds:

3. **Apostrophe unification** — `’`, `ʼ`, `‘`, `´` and `` ` `` all fold to `'`. iOS substitutes `’`
   for `'` while the driver types, so the same name typed on two keyboards would otherwise become two
   places, and no two genuinely different businesses differ only by which apostrophe glyph was used.
4. **Case folding**, locale-independent.

### What is deliberately not normalised

- **Punctuation is preserved.** `A&B Grill` keys as `a&b grill`, and `McDonald's` and `McDonalds`
  stay two different places.
- **Diacritics are preserved.** `Cafe Rio` and `Café Rio` are two places.
- **Nothing is abbreviated, expanded, spell-checked or matched fuzzily.** There is no
  `St`/`Street` rule, no edit distance and no model of any kind.

The asymmetry is the point. A duplicate is a nuisance the driver can see and avoid next time by
picking the existing place from their recent list; a wrong merge is a distinction the app cannot give
back. So the rule errs toward keeping names apart.

!!! info "This is exact matching, not intelligence"

    Identity is equality of the key. That makes it explainable in one sentence, testable without a
    corpus, and impossible to be surprised by.

## Reuse, and which spelling wins

When a typed name normalises to a place already in the catalogue, that place is **reused**; no second
row is created. When it does not, a new local place is created.

**The first accepted spelling wins and is never rewritten by matching.** A later `mcdonalds` joins
the existing place without renaming it. Restyling a name a driver has been reading all week is a
surprise, and choosing which of two spellings is "better" is not a judgement this app can make.

The driver may say otherwise. That is [renaming](#correcting-a-place), a deliberate act on one named
place, and it is the only thing that changes a spelling.

Uniqueness is enforced in `PickupPlaceService` rather than by a unique constraint on the model. A
unique attribute in SwiftData resolves a collision by *upserting* — overwriting the row this rule
exists to preserve — and it would freeze a normalisation policy that is allowed to improve into the
store's shape. A fetch-and-reuse is safe here for a concrete reason: one local store, written from
the main actor by operations that run to completion, with no second writer to race.

## Recording one

The control is a small secondary button on a delivery — `Add Pickup Place`, or
`Change Pickup Place` once one is recorded. It opens a sheet asking for a name and nothing else.

Above the field sit the **places recently used**, because the second time a driver picks up somewhere
the honest interaction is one tap and no keyboard. Tapping one records it and closes the sheet; the
field is for a place that is not in the list yet.

- Recency is derived from the deliveries that reference each place, newest first. A place whose only
  delivery was deleted with its shift stops being recent rather than keeping a date describing work
  the store no longer holds.
- The list is capped at five. There is no frequency ranking and no notion of a favourite.
- Ordering is total and repeatable: latest use, then the order the catalogue was built in.

### Where it appears

| Screen | Control |
| --- | --- |
| Running shift, on each delivery card | Secondary button under the delivery's status, above its lifecycle button |
| Completed shift, on each delivery in the log | Secondary button under the delivery's recorded times |

**The lifecycle stays primary.** The pickup control is small and plain where `Arrived at Pickup`,
`Picked Up` and `Delivered` are large and prominent, and it sits above them rather than in their
place. Every lifecycle event is one tap on a delivery that names no place, and there is no text field
anywhere on the running shift itself — naming a pickup happens inside a sheet, which is a thing to do
while stopped.

## Editing

A pickup place can be assigned, changed or removed at any time, including on a delivered or cancelled
delivery whose shift has already ended. A driver who tapped a place onto the wrong card must be able
to fix it without deleting the work the delivery records.

This is deliberately unlike every lifecycle mutation beside it. A pickup place is not an event: it
orders against no timestamp and changes no interval, duration or rate, so nothing about correcting it
can make the historical record less true. **Lifecycle timestamps remain uneditable.**

The same principle governs [renaming and merging a place](#correcting-a-place), which are safe on a
place attached to a delivery that is still running for exactly the same reason.

## Correcting a place

A place typed once is a place typed for good, until the driver corrects it. Two operations do that,
they are different intentions, and **both are explicit**.

### Rename

Renaming changes a place's spelling and, with it, the key the catalogue is matched by. The two are
written together: a place spelled one way and found by another would create a second row the next
time its new spelling was typed, which is the exact failure renaming exists to fix.

Nothing else moves. The place keeps its identity and the date it was first named, every delivery
stays attached to it, no lifecycle timestamp is touched, and its recorded waits — their count, their
median, the shortest and the longest — are the same waits afterwards. Only identity text changes.

Afterwards the new spelling is authoritative: typing it again finds this place, and typing the old
one does not. **A rename leaves no alias behind**, and nothing records that the place was ever called
something else.

The name goes through the same `PickupPlaceName` as naming a place for the first time — the same
whitespace collapse, the same length limit, the same normalisation. There is no second policy.

### Rename collisions are refused, never merged

If the new name normalises to a key another place already holds, the rename is **refused and nothing
is written**. The message names the place it collided with and says that merging is what would put
the two together.

Quietly folding one place into the other would be a merge, and a merge removes a place. A driver
fixing a typo has not asked for that.

### Merge

Merging moves **every delivery** recorded under one place onto another, and then removes the place
left empty.

| | Source | Destination |
| --- | --- | --- |
| Its deliveries | Move to the destination | Stay where they are |
| Its name and key | Removed with it | Kept, unchanged |
| Its identity and creation date | Removed with it | Kept, unchanged |

**The destination wins entirely.** Names are never combined, no alias is kept and no record of the
merge is written anywhere. The source contributes its delivery relationships and nothing else; what
survives is one of the two places the driver already had, chosen by them.

No delivery is deleted. Every reassigned delivery keeps its acceptance, arrival, pickup, delivery
and cancellation times exactly as they were, so its recorded wait is the same interval it always was.

Afterwards the destination's pickup-wait history is the two histories read together, and its position
in the recent list is the most recent use among all the deliveries it now holds. Neither is written
by the merge: both are [derived from the relationship](pickup-wait.md), so combining the deliveries
combines the figures on its own.

A merge is refused when the two places are the same place, and when either is no longer a row the
store holds. Both refusals happen before anything is changed.

### One operation, or none

The reassignment and the deletion are committed **together**. If the store refuses the save,
everything rolls back: both places, every delivery where it started. There is no state in which the
deliveries have moved and the source is still standing beside the destination.

### The interface

Both controls live on a place's own history screen, reached from a delivery in a completed shift's
log — not on the delivery rows, where a control acts on that one delivery's record.

| Control | What it opens |
| --- | --- |
| `Rename` | A sheet with the current spelling prefilled. Nothing is written until Save; Cancel leaves the name as it was |
| `Merge` | A list of every other place, alphabetically, then a confirmation naming both places and the direction |

The confirmation is explicit about direction and about what happens:

> **Merge "Example Diner" into "Nowhere Noodles"?**
> All deliveries recorded under Example Diner will move to Nowhere Noodles, keeping their recorded
> times. Example Diner will then be removed. This cannot be undone.

Destinations are listed by **display name, alphabetically**, with the order the catalogue was built
in breaking a tie. Alphabetical rather than recent-first on purpose: a driver merging already has one
particular name in mind, and a list that reorders itself as work is recorded makes it harder to find.
There is no suggested candidate and no relevance ranking. A new place cannot be created from the
merge screen — merging into a name that does not exist yet is a rename, and is offered as one.

`Merge` is disabled, with a footer saying why, when the catalogue holds only this place.

VoiceOver names the place on every control — `Rename pickup place, Example Diner` — and speaks each
destination as the whole operation, `Merge Example Diner into Nowhere Noodles`, so the direction
cannot be heard as symmetric.

!!! warning "Nothing merges automatically"

    There is no similarity matching, no edit distance, no "did you mean", no background scan for
    near-duplicates and no rule beyond the exact normalised-key reuse described above. `Nowhere
    Noodle` and `Nowhere Noodles` stay two places until a driver deliberately merges them. A
    duplicate is a nuisance they can see; a merge they did not ask for is a distinction the app
    cannot give back.

### Schema

Neither operation changes the store's shape. The schema stays at **version 6**: no aliases, no merge
history, no redirect identifiers and no tombstones. Rename mutates two attributes on one row; merge
mutates relationships and deletes a row. Both are behaviour, not structure.

## On a completed shift

Each delivery in a shift's log shows its place when one was recorded, under the delivery's own
number:

```
Delivery 1 · Delivered
Nowhere Noodles
Accepted            5:12 PM
Arrived at pickup   5:19 PM
```

The place **supplements** the local `Delivery 1` numbering rather than replacing it — that number is
what the delivery was called all shift. A delivery with no place shows no line for it: a
"no pickup place" row on every delivery would be noise on the ordinary case.

VoiceOver reads the delivery, then the place as it is written. The normalised key is never exposed,
aloud or otherwise.

## Deletion

| Deleting | Takes with it | Leaves alone |
| --- | --- | --- |
| A shift | Its route samples and its deliveries | Every pickup place, including ones only that shift used |
| A delivery | Nothing else | Its pickup place |

**A pickup place is never cascade-deleted.** It is shared, so deleting one delivery — or the whole
shift that cascades to it — must leave the place standing for every other delivery that still names
it.

A place that ends up referenced by nothing is kept in the local catalogue. It stops being *recent*,
so it disappears from the list the sheet offers, and typing the name again finds it rather than
creating a second one. It is not garbage collected: collecting it would mean deleting a driver's own
vocabulary as a side effect of deleting a shift, and this project keeps deletion's blast radius
deliberately small.

## Privacy

Pickup-place names are work history. For a driver who works a small area they are close to a
description of where that driver is, so they are treated the same way coordinates and earnings are.

- They stay on the device. There is no network code, no lookup, no sync and no export.
- **They are never logged.** The `pickup-place` log category records that a place was assigned,
  changed, removed, reused, created, renamed or merged, and which rule refused an operation — never
  the spelling typed, never the normalised key derived from it, and never how many deliveries a
  merge moved.
- Every name in this repository — tests, previews, fixtures, screenshots and this page — is invented.
  No real business is named anywhere.

## Schema

Pickup identity is [version 6](../architecture/migrations.md) of the store: a new `PickupPlace`
entity and a new optional `Delivery.pickupPlace` reference to it. The step is additive, and
**existing deliveries migrate with no pickup place**.

That emptiness is the substantive decision. A store written before this existed records nothing about
which business any past delivery came from, and DashPilot has no source from which to recover one.
Attributing a delivery to a place by its route, its timing or its resemblance to another would write a
merchant's name into a driver's history on the app's authority rather than theirs, and no later
screen could tell that apart from a place they named themselves.

## What is built on this

One thing: [pickup wait](pickup-wait.md). Because two spellings of a name resolve to one place, the
waits recorded at it can be read together, and a place's history says how long its pickups have
actually taken. That history is derived on demand and stored nowhere, so this model keeps no counter
of any kind.

Nothing else. There is no fastest or slowest place, no merchant score, no ranking, no offer
recommendation and no aggregate across places — see [Limitations](../reference/limitations.md). The
purpose of this work was a **trustworthy grouping key**; the statistics built over it are only worth
having because the key underneath them is one a driver can rely on.
