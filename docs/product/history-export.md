# History export

DashPilot writes the completed shifts it holds to a **JSON** or **CSV** file on the device, and hands
that file to the system share sheet. The export answers one question:

> What has DashPilot actually recorded?

It is not a report, a statement or a submission. Nothing is computed for the file that the app does
not already show, and nothing recorded is turned into a stronger claim on the way out.

## Scopes

| Scope | Where it is offered | What it holds |
| --- | --- | --- |
| One shift | `Export Shift`, on a completed shift's detail screen | That shift and its deliveries. **No expenses** |
| A day | `Export Day`, on the period summary with **Day** selected | Every completed shift that started that day, the expenses dated that day, plus the day's summary |
| A week | `Export Week`, on the period summary with **Week** selected | Every completed shift that started that week, the expenses dated in it, plus the week's summary |
| A month | `Export Month`, on the period summary with **Month** selected | Every completed shift that started that calendar month, the expenses dated in it, plus the month's summary |
| A chosen range | `Export Range`, on the period summary with **Custom** selected | Every completed shift that started within the selected dates, the expenses dated in them, plus that range's summary |
| All history | `Export All History`, in the History section | Every completed shift and every recorded expense in the store |

**Only completed shifts are exported.** A running shift has no finalised duration and no final
amount, and a file claiming to be its record would be out of date before it finished writing. There
is no export control on a running shift, and the export layer refuses one even if a scope names it.

A period export uses the same membership rule as the [period summary](period-summaries.md): a shift
belongs to the period containing its start, so an overnight shift is exported whole, on the day it
began, and never counted twice. That holds at every period length — a shift starting at 23:00 on
30 September is in September's file, entirely, and is not in October's.

All four period lengths go through **one** `ReportingPeriod` and one calculator. A month is not
exported as a set of weeks and a chosen range is not exported as a set of days: each one selects the
underlying shifts it contains, so the file and the screen cannot disagree about a single figure.

A scope holding **nothing at all**, meaning no completed shift and no recorded expense, is refused
rather than producing an empty file, and such a period offers no export control. A period holding only
expenses *is* exported: a day off with a tank of fuel on it is not an empty day.

Expenses are selected by their **own dates**, never through a shift. A single shift's export
therefore carries none, because no expense belongs to a shift. See
[Recorded expenses](expenses.md).

## Export format version

Every file states `formatVersion: 2`.

**This is not the SwiftData schema version**, which is currently v8. The two describe different
things and are free to move independently:

- The schema version describes how a database is laid out on one device. Nothing outside the app has
  ever seen it.
- The format version describes a **file a driver has already taken somewhere else** — a spreadsheet,
  a folder, an accountant's inbox.

An internal schema change that adds a column nothing exports does not renumber the file format, and
a change to what the file says does not pretend the store changed. The version is bumped only when
an existing field's meaning changes or a field is removed; adding a field is additive, and a reader
that ignores unknown keys keeps working.

Exports are never called "v8".

### Version history

#### Still 2: recorded expenses

Recorded expenses added a top-level `expenses` array, a `summary.expenses` block and a
`summary.netAfterRecordedExpenses` block. The version was **evaluated and deliberately not moved**,
by the rule above:

- **Nothing existing changed meaning.** `shiftCount` still counts shifts, `shifts[]` holds the same
  records, and no earnings, mileage, duration or rate field is derived any differently. Nothing
  subtracts an expense from a figure that already existed: the net is a new field beside them.
- **No field was removed or renamed**, which is what forced version 2.
- **No enumeration gained a value.** `scope.kind` is the same closed set of six.
  `expenses[].category` is a new field, so its set is new rather than widened.
- **The new array is always present.** A scope with no expenses writes `[]`, so a reader never has to
  tell "no expenses" from "an older build".

A reader that ignores unknown keys keeps working unchanged, which is the whole of what the version
number promises. A file produced before expenses existed simply has no such keys.

The CSV is unchanged, and its columns are the same 32.

#### 2 — month and chosen ranges

Two changes, and **both are ones a version-1 reader can be broken by**, which is why the number moved
rather than the values being added quietly:

- **`scope.kind` gained `month` and `custom`.** Version 1 documented a closed set — `shift`, `day`,
  `week`, `allHistory` — and a reader switching exhaustively over those four now meets a fifth or a
  sixth. The field's type did not change; the set of things it can say did, and a scope a reader
  cannot name is a file it cannot interpret.
- **`scope.periodEnd` was renamed `scope.periodEndExclusive`.** A key was removed, which is a bump by
  the rule above. The instant was always the exclusive end, and with only whole days and weeks that
  was easy to overlook. With a range the driver chose by two *inclusive* dates it is not: selecting
  *1 September through 7 September* writes `2026-09-08T00:00:00Z`, and the key has to say why rather
  than leaving a reader to assume the range runs to the 8th.

The store's schema was **unchanged at v7** by that release. It is a different number describing a
different thing, and the two moved independently exactly as intended.

#### 1 — the first export format

Shift, day, week and all-history scopes, in JSON and CSV.

## What a file says

### Per shift

Its start and end, elapsed time, the amount recorded on it, what its route measured and how far that
can be trusted, delivery active and non-delivery time, the three derived rates, the delivered and
cancelled counts, and its deliveries.

### Per delivery

Every lifecycle timestamp that was recorded, the state it ended in, the pickup place name if one was
recorded, the recorded pickup wait, acceptance-to-delivery duration, the amount recorded against that
delivery, and that delivery's own gross per recorded delivery hour.

### Per expense (JSON only)

The date the cost was incurred, its category, its amount, the currency, and the driver's note if they
wrote one. Nothing else: there is no shift identifier, no delivery identifier and no allocation,
because there is none to export. A consumer wanting costs beside work joins on the **date**, which is
the only relationship DashPilot can honestly state.

### Per period (JSON only)

The [period summary](period-summaries.md) with **every coverage count preserved**:

```json
"earnings": {
  "recordedGrossEarnings": "90.00",
  "contributingShiftCount": 1,
  "totalShiftCount": 2,
  "currencyCode": "USD"
}
```

Each rate carries its own paired subset — the shifts that had *both* halves of it, which is not the
same count as the earnings coverage:

```json
"grossPerRecordedMile": {
  "amount": "15.79",
  "contributingShiftCount": 1,
  "totalShiftCount": 2
}
```

The period's recorded expenses are carried with the count of records behind them, split by category,
and with the net after them:

```json
"expenses": {
  "recordedTotal": "48.60",
  "recordCount": 2,
  "currencyCode": "USD",
  "byCategory": [
    { "category": "fuel", "total": "42.10", "recordCount": 1 },
    { "category": "parkingAndTolls", "total": "6.50", "recordCount": 1 }
  ]
},
"netAfterRecordedExpenses": {
  "amount": "37.65",
  "contributingShiftCount": 1,
  "totalShiftCount": 2,
  "expenseRecordCount": 2,
  "currencyCode": "USD"
}
```

There is **no coverage pair on the expense total**, and its absence is deliberate: nothing knows how
many costs went unrecorded, so a count of what was entered is all that can honestly be written. The
net is `null` unless both halves were recorded, and the field name is the whole claim: it is not
profit, and a reader relabelling it as such is making a claim this file does not.

Route partiality is preserved as its own counts (`measuredShiftCount`, `partialShiftCount`,
`unmeasurableShiftCount`, `totalShiftCount`), and so is the pickup-wait sample count behind the
median.

## What the file deliberately keeps apart

The export preserves the distinctions the rest of the app spends its effort on, because a flat file
is exactly where they get lost.

- **Recorded mileage is not driven mileage.** The field is `recordedDistanceMetres`, never
  `totalMilesDriven`, and the route fields beside it say how much of the shift capture accounts for.
- **A missing value is never zero.** JSON writes `null`; CSV writes an empty cell. A shift with no
  amount recorded and a shift recorded as paying `$0.00` are two different exports.
- **Shift earnings and delivery earnings stay separate.** The shift's amount and the amounts recorded
  against its deliveries are independent fields. Nothing adds one to the other, and **no file
  contains a difference, shortfall, discrepancy or unallocated figure** — that difference is
  ordinary, and naming it would call it an error.
- **Elapsed time is not delivery active time**, and non-delivery time is never called idle time.
  Active time is the already-unioned figure, so deliveries worked at once are counted once; adding up
  the delivery rows gives a larger number, and that one is not a duration of anything.
- **A recorded pickup wait is not a predicted one.** `pickupWaitSeconds` exists only when both ends
  of the wait were recorded and are in order. A delivery cancelled before its pickup exports no wait
  rather than a wait of zero.
- **Gross is gross.** No gross figure in the file has anything subtracted from it. The recorded
  expenses and the net after them are separate fields beside them, and every gross field keeps the
  word.
- **A recorded cost is not a cost.** The expense total is the sum of the rows the driver entered, and
  a period with none is not a period that cost nothing.
- **An expense belongs to a date, not to a shift.** No file relates one to a shift or a delivery, and
  none divides one across work.

## Encoding

| Value | How it is written |
| --- | --- |
| Money | A decimal string at two fraction digits, e.g. `"86.25"`, `"0.00"`. No symbol, no grouping, no locale. |
| Currency | A `currencyCode` field, always `USD`. Stated rather than implied; DashPilot converts nothing. |
| Timestamps | ISO 8601 in UTC to the second, e.g. `2026-09-05T13:04:05Z`. The same string in both formats. |
| Durations | Whole seconds, in fields named for it: `elapsedSeconds`, `pickupWaitSeconds`. |
| Distance | `recordedDistanceMetres` is authoritative; `recordedDistanceMiles` is derived from it. |
| Missing | JSON `null`, CSV empty cell. Never `0`. |

Money is a **string and not a JSON number** deliberately. A `Decimal` written as a JSON number is
re-read by most parsers as a binary double, and the loss happens outside DashPilot, after the file
has left, where nothing can notice it. Amounts are exact at two places because the input layer
rejects anything finer than a cent; a derived rate is kept at six fraction digits internally and is
rounded here to the two the app displays, so an exported rate matches the figure that was on screen.

The device's time zone is not exported. An instant in UTC says exactly when something happened; the
driver's zone would say roughly where they live, and no figure needs it.

## JSON

The canonical machine-readable form, and the only one that carries the period summary. It is
pretty-printed with sorted keys, so the same records produce the same bytes every time.

Every optional field is written as an **explicit `null`** rather than omitted. One convention, so a
reader can tell "DashPilot did not record this" from "this build has no such field" without knowing
the full key set, and so every record in an array is the same shape.

## CSV

**One row per recorded delivery**, with its shift's own columns repeated across it. A shift with no
deliveries still gets a row, with the delivery columns empty. Records end `\r\n`, per RFC 4180, and
the file is UTF-8.

Two things are **not** in the CSV.

The **recorded expenses**, for a reason that comes from the model rather than the format: this
table's unit is a delivery, and an expense belongs to a date rather than to a delivery, so there is
no row it can occupy and putting it on the nearest delivery would manufacture an attribution the app
refuses to make. Appending a second table of expenses under the first was the alternative and was
rejected: a file whose row shape changes half way down is one most parsers read as a corrupt table,
and the row count would stop agreeing with the JSON's shift count.

The **period summary**. Every figure in one is paired with the count of shifts behind
it, and a single flat table has nowhere to keep that pairing — a `2.18` in a spreadsheet cell with
its "4 of 6 shifts" left behind is exactly the claim this project refuses to make. Export JSON for
the summary; the format picker says so before the file is written.

Identifiers are also absent from the CSV. They are of no use in a spreadsheet and would push the
columns a driver reads off the first screen.

### Spreadsheet safety

A pickup place is free text a driver typed. A field beginning with `=`, `+`, `-`, `@`, a tab or a
carriage return is read as a **formula** by every major spreadsheet, so any such field is prefixed
with a single apostrophe before it is quoted. `=NOWHERE()` is written as `"'=NOWHERE()"` and opens as
text.

Quoting alone does not protect against this: an RFC 4180 parser strips the quotes long before the
cell reaches the formula engine. The apostrophe is a visible change to the bytes, and it is stated
here rather than hidden.

Commas, quotation marks, line breaks, edge whitespace and Unicode are handled by ordinary RFC 4180
quoting; a name's own line breaks are preserved inside its quotes and never rewritten.

## Privacy

- **Export is a user action.** Nothing exports on a schedule, on shift end or at launch.
- **Nothing is uploaded.** DashPilot has no network code, so there is nowhere for a file to be sent.
  The file is written locally and handed to the system share sheet.
- **Where it goes next is the driver's choice.** Once a file is in another app, a drive or a message,
  it is outside DashPilot and outside anything the app can say about it. That is the point of the
  feature, and it is stated on the sheet before the file is shared.
- **Raw coordinates are not exported.** A shift's route appears as a measurement and a description of
  its coverage — never latitude, longitude, a timestamped position or a capture-session identifier.
  Exact positions are substantially more sensitive than a shift summary and are not needed to answer
  what the app recorded. If exporting them is ever wanted it will be a separate, explicit feature
  with its own consent, not a field that appeared because the model had it.
- **Expense notes are exported**, because they are the driver's own record and a file that dropped
  them would hand back less than they entered. They are free text, so the sheet says what leaves the
  device before the file is written.
- **Pickup place names are exported**, because they are part of the driver's own recorded history.
  They can reveal where someone works: for a driver working a small area, the places they pick up
  from are close to a description of where they are. The **normalised matching key** the catalogue
  uses internally is never exported, and neither is a place's catalogue bookkeeping.
- **No device or account metadata.** No device name or model, no time zone, no user name, no Apple
  Account, no home location and no analytics identifier. The metadata is the format version, when the
  file was written, what it covers and how many shifts it holds.
- **Nothing about a file's contents is logged.** The `export` log category records the scope, the
  format and a count — never a date a driver worked, an amount, a place, a distance, or the path the
  file was written to.

## Files

Names are predictable and filesystem-safe: `DashPilot-Shift-2026-09-05.json`,
`DashPilot-Week-2026-08-31.csv`, `DashPilot-Day-2026-09-05.json`,
`DashPilot-Month-2026-09.json`, `DashPilot-Range-2026-09-01-to-2026-09-07.json`,
`DashPilot-History-2026-09-06.json`. ASCII letters, digits and hyphens only.

The dates are machine-written — `yyyy-MM-dd`, or `yyyy-MM` for a month — never a locale-formatted
date with slashes in it, so a name sorts, parses and is legal on every filesystem the file passes
through.

The date is the day the records are **about**, in the driver's own calendar — the shift's day, the
period's first day, or, for an all-history export, the day it was written. A month is named by its
month rather than by its first day, and a chosen range names **both** of the days the driver
selected: a range chosen as *1 through 7 September* is `…-2026-09-01-to-2026-09-07`, never
`…-to-2026-09-08`, so the name cannot contradict the screen it came from.

No pickup place, merchant or amount ever appears in a file name: a name shows up in a share sheet, a
notification and a folder listing, often on someone else's screen.

Exports go into one temporary directory that is **emptied before each new export** and once at
launch, so at most one export exists at a time and the app never accumulates copies of a driver's
history. A file is never deleted the instant the share sheet closes: the sheet may still be reading
it, and pulling it away produces a truncated attachment rather than an error anyone sees. An existing
file is never overwritten — a numbered suffix is added instead.

## What this is not

- **Not a tax statement**, and not a deduction calculation. The expenses in a file are the ones the
  driver typed; no mileage allowance, deduction or taxable figure is derived anywhere in DashPilot,
  and the net after recorded expenses is not profit.
- **Not a record from any delivery platform.** Nothing in the file was imported, confirmed or
  reconciled against one.
- **Not a backup.** There is no import, no restore and no sync. An export is a copy of what was
  recorded, read by whatever the driver opens it with.
- **Not a route file.** No coordinates, and no GPX, KML or GeoJSON.
