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

**The first accepted spelling wins and is never rewritten.** A later `mcdonalds` joins the existing
place without renaming it. Restyling a name a driver has been reading all week is a surprise, and
choosing which of two spellings is "better" is not a judgement this app can make.

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
can make the historical record less true. **Lifecycle timestamps remain uneditable**, and this
interval did not change that.

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
  changed, removed, reused or created — never the spelling typed, and never the normalised key
  derived from it.
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

## What is not built on this yet

Identity, and nothing derived from it. There is no average or median pickup wait, no fastest or
slowest place, no merchant score, no offer recommendation and no aggregate of any kind — see
[Limitations](../reference/limitations.md). The purpose of this work is a **trustworthy grouping
key**; the statistics that could be built over it are only worth having if the key underneath them is
one a driver can rely on.
